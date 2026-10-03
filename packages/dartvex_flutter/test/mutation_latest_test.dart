import 'dart:async';

import 'package:dartvex/src/sync/local_state.dart';
import 'package:dartvex/src/sync/optimistic_updates.dart';
import 'package:dartvex/src/sync/remote_query_set.dart';
import 'package:dartvex_flutter/dartvex_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers/fake_runtime_client.dart';

final _query = ConvexQueryReference<NoArgs, String>(
  name: 'user:current',
  encode: (_) => {},
  decodeArgs: (_) => const NoArgs(),
  decode: (raw) => raw as String,
  encodeResult: (value) => value,
);

// Uses the real core overlay engine, rather than a fake that ignores updates.
class _OverlayRuntime extends FakeRuntimeClient {
  final results = OptimisticQueryResults();
  final token = LocalSyncState.serializeQueryToken('user:current', {});
  String server = 'original';
  int nextId = -1;

  Map<String, OverlayServerQuery> get serverResults => {
    token: (
      result: StoredQuerySuccess(value: server, logLines: []),
      udfPath: 'user:current',
      args: {},
    ),
  };

  String get selected =>
      (results.rawResultForToken(token) as StoredQuerySuccess).value as String;

  void receive(String value) {
    server = value;
    results.ingestQueryResultsFromServer(serverResults, {});
  }

  @override
  OptimisticUpdateHandle createOptimisticUpdate(OptimisticUpdate update) {
    final id = nextId--;
    results.replaceOptimisticUpdate(update, id, serverResults);
    return OptimisticUpdateHandle(
      onReplace: (update) =>
          results.replaceOptimisticUpdate(update, id, serverResults),
      onDispose: () =>
          results.ingestQueryResultsFromServer(serverResults, {id}),
    );
  }
}

void main() {
  late _OverlayRuntime client;
  late Future<String> Function(String) mutate;
  late ConvexRequestSnapshot<String> snapshot;
  late List<Completer<dynamic>> requests;

  Widget widget({
    MutationMode mode = MutationMode.latest,
    String name = 'set',
    bool optimistic = true,
  }) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ConvexMutation<String, String>(
        client: client,
        mode: mode,
        mutation: ConvexMutationReference(
          name: name,
          encode: (value) => {'color': value},
          decode: (raw) => raw as String,
        ),
        typedOptimisticUpdate: optimistic
            ? (store, args, _) => store.setQuery(_query, const NoArgs(), args)
            : null,
        builder: (_, execute, state) {
          mutate = execute;
          snapshot = state;
          return const SizedBox();
        },
      ),
    );
  }

  setUp(() {
    client = _OverlayRuntime()..receive('original');
    requests = [];
    client.onMutate = (_, __) {
      final request = Completer<dynamic>();
      requests.add(request);
      return request.future;
    };
  });

  testWidgets('latest mode works without optimistic callbacks', (tester) async {
    await tester.pumpWidget(widget(optimistic: false));
    final a = mutate('A');
    final b = mutate('B');
    requests[0].complete('A');
    await a;
    await tester.pump();
    expect(client.mutateCalls.last.args['color'], 'B');
    requests[1].complete('B');
    expect(await b, 'B');
    await tester.pump();
    expect(snapshot.data, 'B');
  });

  testWidgets('ignored superseded futures do not cause unhandled errors', (
    tester,
  ) async {
    await tester.pumpWidget(widget());
    final a = mutate('A');
    mutate('B');
    final c = mutate('C');
    requests[0].complete('A');
    await a;
    await tester.pump();
    client.receive('C');
    requests[1].complete('C');
    await c;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('immediate latest overlays, coalescing and final server value', (
    tester,
  ) async {
    await tester.pumpWidget(widget());
    final a = mutate('A');
    expect(client.selected, 'A');
    final b = mutate('B');
    expect(client.selected, 'B');
    final superseded = expectLater(
      b,
      throwsA(isA<MutationSupersededException>()),
    );
    final c = mutate('C');
    expect(client.selected, 'C');
    await superseded;
    await tester.pump();
    expect(snapshot.isLoading, isTrue);
    expect(client.mutateCalls, hasLength(1));

    client.receive('A');
    expect(client.selected, 'C');
    requests[0].complete('saved A');
    expect(await a, 'saved A');
    await tester.pump();
    expect(client.selected, 'C');
    expect(snapshot.isLoading, isTrue);
    expect(snapshot.hasData, isFalse);
    expect(client.mutateCalls.map((call) => call.args['color']), ['A', 'C']);

    client.receive('C');
    requests[1].complete('saved C');
    expect(await c, 'saved C');
    await tester.pump();
    expect(snapshot.isLoading, isFalse);
    expect(snapshot.data, 'saved C');
    expect(client.selected, 'C');
    expect(client.results.hasActiveUpdates, isFalse);
  });

  testWidgets('earlier failure continues; final failure rolls back', (
    tester,
  ) async {
    await tester.pumpWidget(widget());
    final a = mutate('A');
    final aError = expectLater(a, throwsStateError);
    final b = mutate('B');
    final bError = expectLater(b, throwsStateError);
    requests[0].completeError(StateError('A failed'));
    await aError;
    await tester.pump();
    expect(client.selected, 'B');
    expect(snapshot.isLoading, isTrue);
    expect(snapshot.hasError, isFalse);
    requests[1].completeError(StateError('B failed'));
    await bError;
    await tester.pump();
    expect(client.selected, 'original');
    expect(snapshot.error.toString(), contains('B failed'));
    expect(snapshot.isLoading, isFalse);
    final retry = mutate('B');
    expect(client.selected, 'B');
    client.receive('B');
    requests[2].complete('B');
    await retry;
    await tester.pump();
    expect(snapshot.hasError, isFalse);
    expect(client.selected, 'B');
  });

  testWidgets('same active value can supersede a pending different value', (
    tester,
  ) async {
    await tester.pumpWidget(widget());
    final a = mutate('A');
    final b = mutate('B');
    final bError = expectLater(b, throwsA(isA<MutationSupersededException>()));
    final latestA = mutate('A');
    await bError;
    expect(client.selected, 'A');
    client.receive('A');
    requests[0].complete('A');
    await a;
    await tester.pump();
    expect(client.mutateCalls.last.args['color'], 'A');
    requests[1].complete('A');
    await latestA;
    await tester.pump();
    expect(client.selected, 'A');
  });

  for (final change in ['dispose', 'identity', 'mode', 'client']) {
    testWidgets('$change cancels queued work and ignores stale completion', (
      tester,
    ) async {
      await tester.pumpWidget(widget());
      final oldClient = client;
      final a = mutate('A');
      final b = mutate('B');
      final cancelled = expectLater(
        b,
        throwsA(isA<MutationCancelledException>()),
      );
      switch (change) {
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
        case 'identity':
          await tester.pumpWidget(widget(name: 'other'));
        case 'mode':
          await tester.pumpWidget(widget(mode: MutationMode.single));
        case 'client':
          client = _OverlayRuntime()..receive('other user');
          await tester.pumpWidget(widget());
      }
      await cancelled;
      expect(oldClient.selected, 'original');
      requests[0].complete('A');
      expect(await a, 'A');
      await tester.pump();
      expect(oldClient.mutateCalls, hasLength(1));
      if (change != 'dispose') {
        expect(snapshot.isLoading, isFalse);
        expect(snapshot.hasData, isFalse);
      }
    });
  }

  testWidgets('inline callback rebuilds retain the queue and overlay', (
    tester,
  ) async {
    await tester.pumpWidget(widget());
    final a = mutate('A');
    final b = mutate('B');
    await tester.pumpWidget(widget());
    expect(client.selected, 'B');
    requests[0].complete('A');
    await a;
    await tester.pump();
    client.receive('B');
    requests[1].complete('B');
    await b;
    await tester.pump();
    expect(snapshot.data, 'B');
  });
}

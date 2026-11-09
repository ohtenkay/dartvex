import 'package:dartvex_flutter/dartvex_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers/fake_runtime_client.dart';

final _query = ConvexQueryReference<NoArgs, String?>(
  name: 'user:current',
  encode: (_) => {},
  decodeArgs: (_) => const NoArgs(),
  decode: (raw) => raw as String?,
  encodeResult: (value) => value,
);

void main() {
  testWidgets('default retry icon restarts a failed typed query once', (
    tester,
  ) async {
    final client = FakeRuntimeClient();
    await tester.pumpWidget(
      MaterialApp(
        home: ConvexTypedQuery(
          query: _query,
          args: const NoArgs(),
          client: client,
          builder: (context, value) => Text(value ?? 'null'),
        ),
      ),
    );
    final first = client.subscribeCalls.single.subscription;
    first.emitError(StateError('Unavailable'));
    await tester.pump();
    expect(find.byIcon(Icons.refresh), findsOneWidget);
    expect(find.byTooltip('Retry'), findsOneWidget);
    final retry = tester.widget<IconButton>(find.byType(IconButton)).onPressed!;
    retry();
    retry();
    await tester.pump();
    expect(first.isCanceled, isTrue);
    expect(client.subscribeCalls, hasLength(2));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    client.subscribeCalls.last.subscription.emitSuccess(null);
    await tester.pump();
    expect(find.text('null'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsNothing);
    expect(client.mutateCalls, isEmpty);
    expect(client.actionCalls, isEmpty);
  });

  testWidgets('custom error UI can retry through its builder context', (
    tester,
  ) async {
    final client = FakeRuntimeClient();
    await tester.pumpWidget(
      MaterialApp(
        home: ConvexTypedQuery(
          query: _query,
          args: const NoArgs(),
          client: client,
          builder: (context, value) => Text(value ?? 'null'),
          errorBuilder: (context, error) => FilledButton(
            onPressed: ConvexQuery.retryOf(context),
            child: const Text('Try again'),
          ),
        ),
      ),
    );
    client.subscribeCalls.single.subscription.emitError(
      StateError('Unavailable'),
    );
    await tester.pump();
    expect(find.byIcon(Icons.refresh), findsNothing);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    client.subscribeCalls.last.subscription.emitSuccess('Recovered');
    await tester.pump();
    expect(find.text('Recovered'), findsOneWidget);
  });

  testWidgets('snapshot retry preserves cached null while refreshing', (
    tester,
  ) async {
    final client = FakeRuntimeClient();
    late ConvexQuerySnapshot<String?> snapshot;
    await tester.pumpWidget(
      MaterialApp(
        home: ConvexTypedQuery.snapshot(
          query: _query,
          args: const NoArgs(),
          client: client,
          snapshotBuilder: (context, value) {
            snapshot = value;
            return const SizedBox();
          },
        ),
      ),
    );
    final first = client.subscribeCalls.single.subscription;
    first.emitSuccess(
      null,
      source: ConvexQuerySource.cache,
      hasPendingWrites: true,
    );
    await tester.pump();
    snapshot.retry();
    expect(client.subscribeCalls, hasLength(1));
    first.emitStreamError(StateError('Stream failed'));
    await tester.pump();
    final failed = snapshot.copyWith();
    failed.retry();
    await tester.pump();
    expect(snapshot.hasData, isTrue);
    expect(snapshot.data, isNull);
    expect(snapshot.isRefreshing, isTrue);
    expect(snapshot.isLoading, isFalse);
    expect(snapshot.hasError, isFalse);
    expect(snapshot.error, isNull);
    expect(snapshot.source, ConvexQuerySource.unknown);
    expect(snapshot.hasPendingWrites, isFalse);
    failed.retry();
    expect(client.subscribeCalls, hasLength(2));
    client.subscribeCalls.last.subscription.emitSuccess('Fresh');
    await tester.pump();
    expect(snapshot.data, 'Fresh');
    expect(snapshot.isRefreshing, isFalse);
  });

  testWidgets('retry recovers decoder errors', (tester) async {
    final client = FakeRuntimeClient();
    late ConvexQuerySnapshot<String?> snapshot;
    await tester.pumpWidget(
      MaterialApp(
        home: ConvexTypedQuery.snapshot(
          query: _query,
          args: const NoArgs(),
          client: client,
          snapshotBuilder: (context, value) {
            snapshot = value;
            return const SizedBox();
          },
        ),
      ),
    );
    client.subscribeCalls.single.subscription.emitSuccess(123);
    await tester.pump();
    expect(snapshot.hasError, isTrue);
    snapshot.retry();
    await tester.pump();
    client.subscribeCalls.last.subscription.emitSuccess('Decoded');
    await tester.pump();
    expect(snapshot.hasError, isFalse);
    expect(snapshot.data, 'Decoded');
  });

  testWidgets('callbacks captured before input changes or disposal are inert', (
    tester,
  ) async {
    final client = FakeRuntimeClient();
    late ConvexQuerySnapshot<String> snapshot;
    Widget build(String channel) => MaterialApp(
      home: ConvexQuery<String>(
        query: 'messages:list',
        args: {'channel': channel},
        client: client,
        builder: (context, value) {
          snapshot = value;
          return const SizedBox();
        },
      ),
    );
    await tester.pumpWidget(build('first'));
    client.subscribeCalls.single.subscription.emitError(
      StateError('First failed'),
    );
    await tester.pump();
    final old = snapshot;
    await tester.pumpWidget(build('second'));
    client.subscribeCalls.last.subscription.emitError(
      StateError('Second failed'),
    );
    await tester.pump();
    old.retry();
    expect(client.subscribeCalls, hasLength(2));
    final disposed = snapshot;
    await tester.pumpWidget(const SizedBox());
    disposed.retry();
    expect(client.subscribeCalls, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested retry targets the nearest query', (tester) async {
    final client = FakeRuntimeClient();
    await tester.pumpWidget(
      MaterialApp(
        home: ConvexQuery<String>(
          query: 'outer',
          client: client,
          builder: (context, snapshot) => ConvexTypedQuery(
            query: _query,
            args: const NoArgs(),
            client: client,
            builder: (context, value) => Text(value ?? 'null'),
          ),
        ),
      ),
    );
    client.subscribeCalls.last.subscription.emitError(
      StateError('Inner failed'),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Retry'));
    await tester.pump();
    expect(client.subscribeCalls, hasLength(3));
    expect(client.subscribeCalls.first.subscription.isCanceled, isFalse);
    expect(client.subscribeCalls.last.name, 'user:current');
  });
}

import 'package:dartvex_flutter/dartvex_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Exercise actual generator output, including its typed codecs and imports.
import '../../dartvex_codegen/test/goldens/sample/modules/messages.dart'
    show PaginatePublicPageItem;
import '../../dartvex_codegen/test/goldens/sample/runtime.dart' show Optional;
import '../../dartvex_codegen/test/goldens/sample/widgets/messages.dart';
import 'test_helpers/fake_runtime_client.dart';

final _numbers = ConvexPaginatedQueryReference<NoArgs, int>(
  name: 'numbers:list',
  encode: (_) => const {},
  decodeItem: (raw) => (raw as num).toInt(),
);

void main() {
  late FakeRuntimeClient client;
  setUp(() => client = FakeRuntimeClient());
  tearDown(() => client.dispose());

  Widget host(Widget child) => MaterialApp(
    home: ConvexProvider(
      client: client,
      child: Scaffold(body: child),
    ),
  );

  testWidgets(
    'generated widget encodes filters, decodes items, and loads more',
    (tester) async {
      List<PaginatePublicPageItem>? items;
      PaginationStatus? status;
      VoidCallback? more;
      await tester.pumpWidget(
        host(
          MessagesPaginatePublicQuery(
            channel: const Optional.of('general'),
            pageSize: 3,
            builder: (context, value, loadMore, state) {
              items = value;
              status = state;
              more = loadMore;
              return Text(value.map((item) => item.text).join(','));
            },
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final call = client.paginatedQueryCalls.single;
      expect(call.name, 'messages:paginatePublic');
      expect(call.args, {'channel': 'general'});
      expect(call.pageSize, 3);
      final first = {'_id': 'one', 'author': 'Alice', 'text': 'First'};
      call.query.emitPage([first], status: ConvexPaginationStatus.canLoadMore);
      await tester.pump();
      expect(items!.single.id.value, 'one');
      expect(find.text('First'), findsOneWidget);
      more!();
      call.query.emitPage([first], status: ConvexPaginationStatus.loadingMore);
      await tester.pump();
      expect(status, PaginationStatus.loadingMore);
      expect(find.text('First'), findsOneWidget);
      expect(call.query.loadMoreCount, 1);
      more!();
      expect(call.query.loadMoreCount, 1);
      call.query.emitPage(
        [
          {...first, 'text': 'Edited'},
          {'_id': 'two', 'author': 'Bob', 'text': 'Second'},
        ],
        status: ConvexPaginationStatus.exhausted,
        isDone: true,
      );
      await tester.pump();
      expect(status, PaginationStatus.allLoaded);
      expect(items, hasLength(2));
      expect(find.text('Edited,Second'), findsOneWidget);
      more!();
      expect(call.query.loadMoreCount, 1);
      await tester.pumpWidget(const SizedBox());
      expect(call.query.isCanceled, isTrue);
      more!();
      expect(call.query.loadMoreCount, 1);
    },
  );

  testWidgets('generated snapshot supports map fallback and omitted filters', (
    tester,
  ) async {
    ConvexPaginatedQuerySnapshot<Map<String, dynamic>>? snapshot;
    await tester.pumpWidget(
      host(
        MessagesPaginateRawQuery.snapshot(
          snapshotBuilder: (context, value, more) {
            snapshot = value;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(snapshot!.status, PaginationStatus.loading);
    expect(client.paginatedQueryCalls.single.args, isEmpty);
    final error = StateError('backend');
    client.paginatedQueryCalls.single.query.emitPage(
      [
        {'id': 'raw'},
      ],
      status: ConvexPaginationStatus.error,
      error: error,
    );
    await tester.pump();
    expect(snapshot!.items.single, {'id': 'raw'});
    expect(snapshot!.error, same(error));
    expect(snapshot!.status, PaginationStatus.error);
    expect(snapshot!.isDone, isFalse);
    expect(() => snapshot!.items.clear(), throwsUnsupportedError);
  });

  testWidgets(
    'scalar snapshots retain data and expose decode and stream errors',
    (tester) async {
      ConvexPaginatedQuerySnapshot<int>? snapshot;
      VoidCallback? loadMore;
      await tester.pumpWidget(
        host(
          ConvexTypedPaginatedQuery<NoArgs, int>.snapshot(
            query: _numbers,
            args: const NoArgs(),
            snapshotBuilder: (context, value, more) {
              snapshot = value;
              loadMore = more;
              return const SizedBox();
            },
          ),
        ),
      );
      final query = client.paginatedQueryCalls.single.query;
      loadMore!();
      expect(query.loadMoreCount, 0);
      query.emitPage([1, 2], status: ConvexPaginationStatus.canLoadMore);
      await tester.pump();
      expect(snapshot!.items, [1, 2]);
      query.emitPage(['invalid'], status: ConvexPaginationStatus.canLoadMore);
      await tester.pump();
      expect(snapshot!.items, [1, 2]);
      expect(snapshot!.error, isA<TypeError>());
      expect(snapshot!.status, PaginationStatus.error);
      loadMore!();
      expect(query.loadMoreCount, 0);
      query.emitPage([3], status: ConvexPaginationStatus.canLoadMore);
      await tester.pump();
      expect(snapshot!.error, isNull);
      final error = StateError('stream');
      query.emitStreamError(error);
      await tester.pump();
      expect(snapshot!.items, [3]);
      expect(snapshot!.error, same(error));
      expect(snapshot!.status, PaginationStatus.error);
    },
  );

  testWidgets('initial UI overrides and later errors preserve the list', (
    tester,
  ) async {
    Object? receivedError;
    PaginationStatus? status;
    await tester.pumpWidget(
      host(
        ConvexTypedPaginatedQuery<NoArgs, int>(
          query: _numbers,
          args: const NoArgs(),
          waitingBuilder: (_) => const Text('Waiting'),
          errorBuilder: (_, error) {
            receivedError = error;
            return const Text('Failed');
          },
          builder: (_, items, more, value) {
            status = value;
            return Text(items.join(','));
          },
        ),
      ),
    );
    expect(find.text('Waiting'), findsOneWidget);
    final query = client.paginatedQueryCalls.single.query;
    final error = StateError('first page');
    query.emitPage([], status: ConvexPaginationStatus.error, error: error);
    await tester.pump();
    expect(find.text('Failed'), findsOneWidget);
    expect(receivedError, same(error));
    query.emitPage([1], status: ConvexPaginationStatus.error, error: error);
    await tester.pump();
    expect(find.text('1'), findsOneWidget);
    expect(status, PaginationStatus.error);
  });

  testWidgets(
    'filters and page size reset pagination; parent rebuilds do not',
    (tester) async {
      Widget widget(String channel, int size) => host(
        MessagesPaginatePublicQuery.snapshot(
          channel: Optional.of(channel),
          pageSize: size,
          snapshotBuilder: (_, snapshot, more) =>
              Text('${snapshot.items.length}'),
        ),
      );
      await tester.pumpWidget(widget('one', 2));
      final first = client.paginatedQueryCalls.single.query;
      first.emitPage([
        {'_id': 'one', 'author': 'Alice', 'text': 'First'},
      ], status: ConvexPaginationStatus.canLoadMore);
      await tester.pump();
      await tester.pumpWidget(widget('one', 2));
      expect(client.paginatedQueryCalls, hasLength(1));
      expect(find.text('1'), findsOneWidget);
      await tester.pumpWidget(widget('two', 2));
      expect(first.isCanceled, isTrue);
      expect(client.paginatedQueryCalls.last.args, {'channel': 'two'});
      expect(find.text('0'), findsOneWidget);
      final second = client.paginatedQueryCalls.last.query;
      await tester.pumpWidget(widget('two', 5));
      expect(second.isCanceled, isTrue);
      expect(client.paginatedQueryCalls.last.pageSize, 5);
      expect(client.paginatedQueryCalls, hasLength(3));
    },
  );

  testWidgets('client override changes cancel the old query', (tester) async {
    final other = FakeRuntimeClient();
    addTearDown(other.dispose);
    Widget widget(FakeRuntimeClient override) => host(
      MessagesPaginateRawQuery(
        client: override,
        builder: (_, items, more, status) => const SizedBox(),
      ),
    );
    await tester.pumpWidget(widget(other));
    expect(client.paginatedQueryCalls, isEmpty);
    final first = other.paginatedQueryCalls.single.query;
    await tester.pumpWidget(widget(client));
    expect(first.isCanceled, isTrue);
    expect(client.paginatedQueryCalls, hasLength(1));
  });
}

import 'package:dartvex_flutter/dartvex_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers/fake_runtime_client.dart';

final _names = ConvexPaginatedQueryReference<({String prefix}), String>(
  name: 'names:list',
  encode: (args) => {'prefix': args.prefix},
  decodeItem: (raw) => raw as String,
);
final _numbers = ConvexPaginatedQueryReference<NoArgs, int>(
  name: 'numbers:list',
  encode: (_) => {},
  decodeItem: (raw) => (raw as num).toInt(),
);

void main() {
  late FakeRuntimeClient client;
  late ConvexPaginatedQueryGroupSnapshot<String, int> group;

  setUp(() => client = FakeRuntimeClient());
  tearDown(() => client.dispose());

  Widget host({
    String prefix = 'a',
    ConvexRuntimeClient? override,
  }) => MaterialApp(
    home: ConvexProvider(
      client: client,
      child: ConvexPaginatedQueryGroup(
        firstQuery: _names,
        firstArgs: (prefix: prefix),
        secondQuery: _numbers,
        secondArgs: const NoArgs(),
        firstPageSize: 3,
        secondPageSize: 5,
        client: override,
        builder: (context, value) {
          // This assignment exercises inference of both different item types.
          group = value;
          return Text(
            '${value.first.items.join(',')}/${value.second.items.join(',')}',
          );
        },
      ),
    ),
  );

  testWidgets('keeps typed results separate and loads each eligible source', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    expect(group.isLoading, isTrue);
    expect(group.hasMore, isTrue);
    expect(group.errors, isEmpty);
    final first = client.paginatedQueryCalls[0];
    final second = client.paginatedQueryCalls[1];
    expect(first.name, 'names:list');
    expect(first.args, {'prefix': 'a'});
    expect(first.pageSize, 3);
    expect(second.name, 'numbers:list');
    expect(second.args, isEmpty);
    expect(second.pageSize, 5);
    group.loadMore();
    expect(first.query.loadMoreCount, 0);
    expect(second.query.loadMoreCount, 0);

    // An empty intermediate page still permits advancing this source.
    first.query.emitPage([], status: ConvexPaginationStatus.canLoadMore);
    await tester.pump();
    group.loadMore();
    expect(first.query.loadMoreCount, 1);
    expect(second.query.loadMoreCount, 0);

    first.query.emitPage(
      ['Alice'],
      status: ConvexPaginationStatus.exhausted,
      isDone: true,
    );
    second.query.emitPage([1, 2], status: ConvexPaginationStatus.canLoadMore);
    await tester.pump();
    expect(group.isLoading, isFalse);
    expect(group.first.items, ['Alice']);
    expect(group.second.items, [1, 2]);
    group.loadMore();
    expect(first.query.loadMoreCount, 1);
    expect(second.query.loadMoreCount, 1);
    second.query.emitPage(
      [1, 2, 3],
      status: ConvexPaginationStatus.exhausted,
      isDone: true,
    );
    await tester.pump();
    expect(group.isDone, isTrue);
    expect(group.hasMore, isFalse);
    group.loadMore();
    expect(second.query.loadMoreCount, 1);
    await tester.pumpWidget(const SizedBox());
    expect(first.query.isCanceled, isTrue);
    expect(second.query.isCanceled, isTrue);
    group.reset();
    group.retry();
    group.loadMore();
    expect(client.paginatedQueryCalls, hasLength(2));
  });

  testWidgets('retry restarts failed sources and preserves healthy pages', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    final first = client.paginatedQueryCalls[0].query;
    final second = client.paginatedQueryCalls[1].query;
    first.emitPage(
      ['Alice'],
      status: ConvexPaginationStatus.exhausted,
      isDone: true,
    );
    final error = StateError('offline');
    second.emitPage([1], status: ConvexPaginationStatus.error, error: error);
    await tester.pump();
    expect(group.error, same(error));
    expect(group.errors, [error]);
    expect(group.isDone, isFalse);
    final failedGroup = group;
    failedGroup.retry();
    failedGroup.retry();
    await tester.pump();
    expect(client.paginatedQueryCalls, hasLength(3));
    expect(first.isCanceled, isFalse);
    expect(second.isCanceled, isTrue);
    expect(group.first.items, ['Alice']);
    expect(group.second.items, isEmpty);
    expect(group.isLoading, isTrue);
    final replacement = client.paginatedQueryCalls.last.query;
    replacement.emitPage(
      [2],
      status: ConvexPaginationStatus.exhausted,
      isDone: true,
    );
    await tester.pump();
    group.retry();
    expect(client.paginatedQueryCalls, hasLength(3));
    final oldGroup = group;
    group.reset();
    await tester.pump();
    expect(client.paginatedQueryCalls, hasLength(5));
    expect(first.isCanceled, isTrue);
    expect(replacement.isCanceled, isTrue);
    expect(group.first.items, isEmpty);
    expect(group.second.items, isEmpty);
    oldGroup.reset();
    oldGroup.loadMore();
    expect(client.paginatedQueryCalls, hasLength(5));
  });

  testWidgets('reports both errors and retries both failed queries', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    final firstError = StateError('first');
    final secondError = StateError('second');
    client.paginatedQueryCalls[0].query.emitPage(
      [],
      status: ConvexPaginationStatus.error,
      error: firstError,
    );
    client.paginatedQueryCalls[1].query.emitPage(
      [],
      status: ConvexPaginationStatus.error,
      error: secondError,
    );
    await tester.pump();
    expect(group.error, same(firstError));
    expect(group.errors, [firstError, secondError]);
    expect(() => group.errors.clear(), throwsUnsupportedError);
    group.retry();
    await tester.pump();
    expect(client.paginatedQueryCalls, hasLength(4));
    expect(group.error, isNull);
    expect(group.isLoading, isTrue);
  });

  testWidgets(
    'rebuilds preserve pages and argument changes reset only their source',
    (tester) async {
      await tester.pumpWidget(host());
      final first = client.paginatedQueryCalls[0].query;
      final second = client.paginatedQueryCalls[1].query;
      first.emitPage(['Alice'], status: ConvexPaginationStatus.canLoadMore);
      second.emitPage([1], status: ConvexPaginationStatus.canLoadMore);
      await tester.pump();
      final oldGroup = group;
      await tester.pumpWidget(host());
      expect(client.paginatedQueryCalls, hasLength(2));
      expect(group.first.items, ['Alice']);
      expect(group.second.items, [1]);
      await tester.pumpWidget(host(prefix: 'b'));
      expect(client.paginatedQueryCalls, hasLength(3));
      expect(first.isCanceled, isTrue);
      expect(second.isCanceled, isFalse);
      expect(group.second.items, [1]);
      expect(client.paginatedQueryCalls.last.args, {'prefix': 'b'});
      oldGroup.first.reset();
      expect(client.paginatedQueryCalls, hasLength(3));
    },
  );

  testWidgets(
    'client override owns both subscriptions and replacement cancels both',
    (tester) async {
      final other = FakeRuntimeClient();
      addTearDown(other.dispose);
      await tester.pumpWidget(host(override: other));
      expect(client.paginatedQueryCalls, isEmpty);
      expect(other.paginatedQueryCalls, hasLength(2));
      await tester.pumpWidget(host());
      expect(
        other.paginatedQueryCalls.every((call) => call.query.isCanceled),
        isTrue,
      );
      expect(client.paginatedQueryCalls, hasLength(2));
    },
  );
}

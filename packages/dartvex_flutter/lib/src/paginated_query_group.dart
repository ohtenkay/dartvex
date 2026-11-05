import 'package:dartvex/dartvex.dart' as convex;
import 'package:flutter/widgets.dart';

import 'paginated_query_builder.dart';
import 'runtime_client.dart';

/// Typed results and controls for two independently paginated queries.
///
/// Items remain separate: the application chooses their ordering and whether
/// to combine them. This group does not merge cursors, sort, or deduplicate.
class ConvexPaginatedQueryGroupSnapshot<First, Second> {
  /// Creates a group from two query snapshots.
  const ConvexPaginatedQueryGroupSnapshot({
    required this.first,
    required this.second,
  });

  /// Results, status, error, and controls for the first query.
  final ConvexPaginatedQuerySnapshot<First> first;

  /// Results, status, error, and controls for the second query.
  final ConvexPaginatedQuerySnapshot<Second> second;

  /// Whether either query is loading its first or an additional page.
  bool get isLoading => first.isLoading || second.isLoading;

  /// Whether both queries have exhausted their results.
  bool get isDone => first.isDone && second.isDone;

  /// Whether at least one query has not exhausted its results.
  ///
  /// A loading or failed query may still have more results. [loadMore] only
  /// advances queries that are currently idle.
  bool get hasMore => !isDone;

  /// The first available error, or null if neither query failed.
  Object? get error => first.error ?? second.error;

  /// Errors from both queries, in query order, without discarding either.
  List<Object> get errors =>
      List<Object>.unmodifiable([?first.error, ?second.error]);

  /// Advances each idle query; loading, failed, and exhausted queries are left
  /// alone. One query can advance even when the other is still loading.
  void loadMore() {
    first.loadMore();
    second.loadMore();
  }

  /// Restarts only failed queries from page one, leaving healthy queries and
  /// their accumulated pages untouched.
  void retry() {
    first.retry();
    second.retry();
  }

  /// Discards both queries' pages and restarts both from page one.
  void reset() {
    first.reset();
    second.reset();
  }
}

/// Runs two typed paginated queries with combined loading and recovery controls.
///
/// Uses the same lifecycle and argument comparison as
/// [ConvexTypedPaginatedQuery]. Changing one query's arguments resets only that
/// query. Parent rebuilds preserve both queries' loaded pages, and disposal
/// cancels both subscriptions. Generated paginated query references can be
/// passed directly; argument and item types are inferred from each reference.
///
/// ```dart
/// ConvexPaginatedQueryGroup(
///   firstQuery: searchByUsernamePaginatedQueryReference,
///   firstArgs: (query: search),
///   secondQuery: searchByEmailPaginatedQueryReference,
///   secondArgs: (query: search),
///   builder: (context, group) => UserResults(
///     users: [...group.first.items, ...group.second.items],
///     isLoading: group.isLoading,
///     onLoadMore: group.hasMore ? group.loadMore : null,
///     onRetry: group.retry,
///   ),
/// )
/// ```
class ConvexPaginatedQueryGroup<FirstArgs, First, SecondArgs, Second>
    extends StatelessWidget {
  /// Creates a typed group with independently configurable page sizes.
  const ConvexPaginatedQueryGroup({
    super.key,
    required this.firstQuery,
    required this.firstArgs,
    required this.secondQuery,
    required this.secondArgs,
    required this.builder,
    this.firstPageSize = 20,
    this.secondPageSize = 20,
    this.client,
  });

  /// Generated reference for the first paginated query.
  final convex.ConvexPaginatedQueryReference<FirstArgs, First> firstQuery;

  /// First query's typed arguments, excluding pagination options.
  final FirstArgs firstArgs;

  /// Generated reference for the second paginated query.
  final convex.ConvexPaginatedQueryReference<SecondArgs, Second> secondQuery;

  /// Second query's typed arguments, excluding pagination options.
  final SecondArgs secondArgs;

  /// Number of items requested per page for the first query.
  final int firstPageSize;

  /// Number of items requested per page for the second query.
  final int secondPageSize;

  /// Client shared by both queries; defaults to the surrounding provider.
  final ConvexRuntimeClient? client;

  /// Builds all states with each source's typed items and combined controls.
  final Widget Function(
    BuildContext,
    ConvexPaginatedQueryGroupSnapshot<First, Second>,
  )
  builder;

  @override
  Widget build(BuildContext context) =>
      ConvexTypedPaginatedQuery<FirstArgs, First>.snapshot(
        query: firstQuery,
        args: firstArgs,
        pageSize: firstPageSize,
        client: client,
        snapshotBuilder: (context, first, _) =>
            ConvexTypedPaginatedQuery<SecondArgs, Second>.snapshot(
              query: secondQuery,
              args: secondArgs,
              pageSize: secondPageSize,
              client: client,
              snapshotBuilder: (context, second, _) => builder(
                context,
                ConvexPaginatedQueryGroupSnapshot(first: first, second: second),
              ),
            ),
      );
}

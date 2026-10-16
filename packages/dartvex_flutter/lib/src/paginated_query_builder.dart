import 'dart:async';

import 'package:collection/collection.dart';
import 'package:dartvex/dartvex.dart' as convex;
import 'package:flutter/material.dart';

import 'provider.dart';
import 'runtime_client.dart';

/// Status of a paginated query.
enum PaginationStatus {
  /// Loading the first page.
  loading,

  /// Idle — data loaded, more pages available.
  idle,

  /// Loading additional pages.
  loadingMore,

  /// All pages have been loaded.
  allLoaded,

  /// An error occurred.
  error,
}

/// Builder callback for [PaginatedQueryBuilder].
typedef PaginatedQueryWidgetBuilder<T> =
    Widget Function(
      BuildContext context,
      List<T> items,
      VoidCallback loadMore,
      PaginationStatus status,
    );

/// Widget that manages cursor-based pagination with Convex.
///
/// Backed by the core reactive pagination engine (`ConvexClient.paginatedQuery`)
/// via [ConvexRuntimeClient.paginatedQuery]: each page is a live query
/// subscription, so loaded pages update reactively as their data changes and
/// stay gapless at page boundaries. `loadMore` extends the list using the last
/// page's cursor; changing [query], [args], [pageSize], or [client] resets the
/// query, while changing [fromJson] re-maps the already-loaded items in place
/// (so an inline closure is safe — parent rebuilds do not reset pagination).
///
/// ```dart
/// PaginatedQueryBuilder<Message>(
///   query: 'messages:list',
///   pageSize: 20,
///   fromJson: Message.fromJson,
///   builder: (context, items, loadMore, status) {
///     return ListView.builder(
///       itemCount: items.length + (status == PaginationStatus.allLoaded ? 0 : 1),
///       itemBuilder: (_, i) => i < items.length
///         ? MessageTile(items[i])
///         : TextButton(onPressed: loadMore, child: Text('Load more')),
///     );
///   },
/// )
/// ```
class PaginatedQueryBuilder<T> extends StatelessWidget {
  /// Creates a paginated query builder.
  const PaginatedQueryBuilder({
    super.key,
    required this.query,
    required this.builder,
    required this.fromJson,
    this.args,
    this.pageSize = 20,
    this.client,
  });

  /// The paginated Convex query function name.
  final String query;

  /// Additional arguments merged with `paginationOpts`.
  final Map<String, dynamic>? args;

  /// Number of items per page.
  final int pageSize;

  /// Builder function receiving the accumulated items and controls.
  final PaginatedQueryWidgetBuilder<T> builder;

  /// Deserializer for individual items.
  final T Function(Map<String, dynamic>) fromJson;

  /// Optional runtime client override. If omitted, uses [ConvexProvider.of].
  final ConvexRuntimeClient? client;

  @override
  Widget build(BuildContext context) => _PaginatedQuery<T>(
    query: query,
    args: args,
    pageSize: pageSize,
    client: client,
    decode: (raw) => fromJson(raw as Map<String, dynamic>),
    builder: (context, snapshot, loadMore) =>
        builder(context, snapshot.items, loadMore, snapshot.status),
  );
}

/// Immutable state of a typed paginated query.
class ConvexPaginatedQuerySnapshot<T> {
  /// Creates a snapshot. [items] must be an immutable list.
  const ConvexPaginatedQuerySnapshot({
    required this.items,
    required this.status,
    required this.isDone,
    this.error,
  });

  /// Accumulated items from all loaded pages.
  final List<T> items;

  /// Current pagination state.
  final PaginationStatus status;

  /// Whether the server has exhausted the query.
  final bool isDone;

  /// The backend, stream, or decoding error, if any.
  final Object? error;
}

/// A typed paginated query using generated argument and item codecs.
class ConvexTypedPaginatedQuery<Args, Item> extends StatelessWidget {
  /// Creates a query with default initial loading and error UI.
  const ConvexTypedPaginatedQuery({
    super.key,
    required this.query,
    required this.args,
    required this.builder,
    this.pageSize = 20,
    this.client,
    this.waitingBuilder,
    this.errorBuilder,
  }) : snapshotBuilder = null;

  /// Creates a query whose builder handles every pagination state.
  const ConvexTypedPaginatedQuery.snapshot({
    super.key,
    required this.query,
    required this.args,
    required this.snapshotBuilder,
    this.pageSize = 20,
    this.client,
  }) : builder = null,
       waitingBuilder = null,
       errorBuilder = null;

  /// Generated function name and codecs.
  final convex.ConvexPaginatedQueryReference<Args, Item> query;

  /// Typed arguments excluding pagination options.
  final Args args;

  /// Number of items requested per page.
  final int pageSize;

  /// Optional runtime client override.
  final ConvexRuntimeClient? client;

  /// Builds loaded items, including while fetching additional pages.
  /// Later-page errors retain the list and report [PaginationStatus.error].
  final PaginatedQueryWidgetBuilder<Item>? builder;

  /// Builds every state, including errors with their original details.
  final Widget Function(
    BuildContext,
    ConvexPaginatedQuerySnapshot<Item>,
    VoidCallback,
  )?
  snapshotBuilder;

  /// Overrides the initial loading UI.
  final WidgetBuilder? waitingBuilder;

  /// Overrides the error UI when no items are available.
  final Widget Function(BuildContext, Object)? errorBuilder;

  @override
  Widget build(BuildContext context) => _PaginatedQuery<Item>(
    query: query.name,
    args: query.encode(args),
    decode: query.decodeItem,
    pageSize: pageSize,
    client: client,
    builder: (context, snapshot, loadMore) {
      final buildSnapshot = snapshotBuilder;
      if (buildSnapshot != null) {
        return buildSnapshot(context, snapshot, loadMore);
      }
      if (snapshot.status == PaginationStatus.loading) {
        return waitingBuilder?.call(context) ??
            const Center(child: CircularProgressIndicator());
      }
      if (snapshot.error != null && snapshot.items.isEmpty) {
        return errorBuilder?.call(context, snapshot.error!) ??
            Center(child: Text('Error: ${snapshot.error}'));
      }
      return builder!(context, snapshot.items, loadMore, snapshot.status);
    },
  );
}

class _PaginatedQuery<T> extends StatefulWidget {
  const _PaginatedQuery({
    required this.query,
    required this.args,
    required this.pageSize,
    required this.client,
    required this.decode,
    required this.builder,
  });

  final String query;
  final Map<String, dynamic>? args;
  final int pageSize;
  final ConvexRuntimeClient? client;
  final T Function(dynamic) decode;
  final Widget Function(
    BuildContext,
    ConvexPaginatedQuerySnapshot<T>,
    VoidCallback,
  )
  builder;

  @override
  State<_PaginatedQuery<T>> createState() => _PaginatedQueryState<T>();
}

class _PaginatedQueryState<T> extends State<_PaginatedQuery<T>> {
  static const DeepCollectionEquality _deepEquality = DeepCollectionEquality();

  ConvexRuntimeClient? _client;
  ConvexRuntimePaginatedQuery? _query;
  StreamSubscription<convex.ConvexPaginatedResult>? _subscription;
  Map<String, dynamic>? _subscribedArgs;
  int _queryGeneration = 0;

  List<T> _items = const <Never>[];
  PaginationStatus _status = PaginationStatus.loading;
  convex.ConvexPaginatedResult? _lastResult;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final client = widget.client ?? ConvexProvider.of(context);
    if (_client != client || _query == null) {
      _client = client;
      _start();
    }
  }

  @override
  void didUpdateWidget(covariant _PaginatedQuery<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final client = widget.client ?? ConvexProvider.of(context);
    if (oldWidget.query != widget.query ||
        oldWidget.pageSize != widget.pageSize ||
        _client != client ||
        !_deepEquality.equals(
          _subscribedArgs,
          widget.args ?? const <String, dynamic>{},
        )) {
      _client = client;
      _start();
    } else if (oldWidget.decode != widget.decode) {
      // The item mapper is not part of the query identity — an inline closure
      // differs on every parent rebuild, and restarting would drop every
      // loaded page. Re-map the current result in place instead; a rebuild is
      // already scheduled, so plain assignment is enough.
      final result = _lastResult;
      if (result != null) {
        try {
          _items = _mapItems(result);
          _status = _mapStatus(result.status);
          _error = result.error;
        } catch (error) {
          _error = error;
          _status = PaginationStatus.error;
        }
      }
    }
  }

  void _start() {
    final generation = ++_queryGeneration;
    _subscription?.cancel();
    _query?.cancel();
    final argsSnapshot = _snapshotArgs(widget.args);
    _subscribedArgs = argsSnapshot;
    final query = _client!.paginatedQuery(
      widget.query,
      argsSnapshot,
      pageSize: widget.pageSize,
    );
    _query = query;
    // Seed synchronously from the current snapshot (a build is already pending
    // from this lifecycle callback), then update reactively from the stream.
    final initial = query.current;
    _lastResult = initial;
    _error = initial.error;
    try {
      _items = _mapItems(initial);
      _status = _mapStatus(initial.status);
    } catch (error) {
      _error = error;
      _items = const <Never>[];
      _status = PaginationStatus.error;
    }
    _subscription = query.stream.listen(
      (result) {
        if (generation != _queryGeneration) {
          return;
        }
        _apply(result);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (generation != _queryGeneration || !mounted) {
          return;
        }
        _lastResult = convex.ConvexPaginatedResult(
          results: _lastResult?.results ?? const <dynamic>[],
          status: convex.ConvexPaginationStatus.error,
          isDone: false,
          error: error,
        );
        setState(() {
          _error = error;
          _status = PaginationStatus.error;
        });
      },
    );
  }

  void _apply(convex.ConvexPaginatedResult result) {
    if (!mounted) {
      return;
    }
    _lastResult = result;
    _error = result.error;
    late final List<T> items;
    late final PaginationStatus status;
    try {
      items = _mapItems(result);
      status = _mapStatus(result.status);
    } catch (error) {
      _error = error;
      items = _items;
      status = PaginationStatus.error;
    }
    setState(() {
      _items = items;
      _status = status;
    });
  }

  List<T> _mapItems(convex.ConvexPaginatedResult result) {
    return result.results.map(widget.decode).toList(growable: false);
  }

  static PaginationStatus _mapStatus(convex.ConvexPaginationStatus status) {
    switch (status) {
      case convex.ConvexPaginationStatus.loadingFirstPage:
        return PaginationStatus.loading;
      case convex.ConvexPaginationStatus.loadingMore:
        return PaginationStatus.loadingMore;
      case convex.ConvexPaginationStatus.canLoadMore:
        return PaginationStatus.idle;
      case convex.ConvexPaginationStatus.exhausted:
        return PaginationStatus.allLoaded;
      case convex.ConvexPaginationStatus.error:
        return PaginationStatus.error;
    }
  }

  Map<String, dynamic> _snapshotArgs(Map<String, dynamic>? args) {
    return convex.jsonToConvex(
          convex.convexToJson(args ?? const <String, dynamic>{}),
        )
        as Map<String, dynamic>;
  }

  void _loadMore() {
    // Also guard decoding failures, which only exist in the widget layer.
    if (!mounted || _status != PaginationStatus.idle) {
      return;
    }
    _query?.loadMore();
  }

  @override
  void dispose() {
    _queryGeneration += 1;
    _subscription?.cancel();
    _query?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      ConvexPaginatedQuerySnapshot<T>(
        items: List<T>.unmodifiable(_items),
        status: _status,
        isDone: _lastResult?.isDone ?? false,
        error: _error,
      ),
      _loadMore,
    );
  }
}

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:dartvex/dartvex.dart' as convex;
import 'package:flutter/material.dart';

import 'args.dart';
import 'provider.dart';
import 'runtime_client.dart';
import 'safe_rebuild.dart';
import 'snapshot.dart';

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

/// Builder used by [PaginatedQueryBuilder.errorBuilder] when the query fails.
///
/// [error] is the server or transport error of the failing page, or a
/// [ConvexDecodeException] when an item could not be decoded. [items] are the
/// items decoded before the failure, and [retry] restarts the query from the
/// first page.
typedef PaginatedQueryErrorWidgetBuilder<T> =
    Widget Function(
      BuildContext context,
      Object error,
      List<T> items,
      VoidCallback retry,
    );

/// Widget that manages cursor-based pagination with Convex.
///
/// Backed by the core reactive pagination engine (`ConvexClient.paginatedQuery`)
/// via [ConvexRuntimeClient.paginatedQuery]: each page is a live query
/// subscription, so loaded pages update reactively as their data changes and
/// stay gapless at page boundaries. `loadMore` extends the list using the last
/// page's cursor; changing [query], [args], [pageSize], or [client] resets the
/// query, while changing [fromJson] re-maps the already-loaded items in place
/// (so an inline closure is safe — parent rebuilds do not reset pagination —
/// but it re-decodes every loaded item on each parent rebuild; prefer a stable
/// reference such as `Message.fromJson` when the parent rebuilds often).
///
/// Items whose raw value did not change between emissions are not decoded
/// again. When the query fails, [errorBuilder] (if provided) receives the
/// error object; decode failures are also reported to
/// [FlutterError.reportError]. `loadMore` may be called from anywhere,
/// including an `itemBuilder` during layout.
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
///   errorBuilder: (context, error, items, retry) => TextButton(
///     onPressed: retry,
///     child: Text('Failed: $error — tap to retry'),
///   ),
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
    this.errorBuilder,
  }) : snapshotBuilder = null;

  /// Creates a builder with snapshots and load, retry, and reset controls.
  const PaginatedQueryBuilder.snapshot({
    super.key,
    required this.query,
    required this.snapshotBuilder,
    required this.fromJson,
    this.args,
    this.pageSize = 20,
    this.client,
  }) : builder = null,
       errorBuilder = null;

  /// Builds every pagination state and exposes query controls.
  final Widget Function(
    BuildContext,
    ConvexPaginatedQuerySnapshot<T>,
    VoidCallback,
  )?
  snapshotBuilder;

  /// The paginated Convex query function name.
  final String query;

  /// Additional arguments merged with `paginationOpts`.
  final Map<String, dynamic>? args;

  /// Number of items per page.
  final int pageSize;

  /// Builder function receiving the accumulated items and controls.
  final PaginatedQueryWidgetBuilder<T>? builder;

  /// Deserializer for individual items.
  final T Function(Map<String, dynamic>) fromJson;

  /// Optional runtime client override. If omitted, uses [ConvexProvider.of].
  final ConvexRuntimeClient? client;

  /// Builds errors with retained items and a callback that restarts page one.
  final PaginatedQueryErrorWidgetBuilder<T>? errorBuilder;

  @override
  Widget build(BuildContext context) => _PaginatedQuery<T>(
    query: query,
    args: args,
    pageSize: pageSize,
    client: client,
    decode: (raw) => fromJson(raw as Map<String, dynamic>),
    decoderIdentity: fromJson,
    builder: (context, snapshot, loadMore) {
      final buildSnapshot = snapshotBuilder;
      if (buildSnapshot != null) {
        return buildSnapshot(context, snapshot, loadMore);
      }
      final buildError = errorBuilder;
      if (buildError != null && snapshot.error != null) {
        return buildError(
          context,
          snapshot.error!,
          snapshot.items,
          snapshot.retry,
        );
      }
      return builder!(context, snapshot.items, loadMore, snapshot.status);
    },
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
    this.hasPendingWrites = false,
    VoidCallback? onLoadMore,
    VoidCallback? onRetry,
    VoidCallback? onReset,
  }) : _onLoadMore = onLoadMore,
       _onRetry = onRetry,
       _onReset = onReset;

  final VoidCallback? _onLoadMore;
  final VoidCallback? _onRetry;
  final VoidCallback? _onReset;

  /// Whether the first or an additional page is loading.
  bool get isLoading =>
      status == PaginationStatus.loading ||
      status == PaginationStatus.loadingMore;

  /// Whether the server has not yet exhausted the query.
  ///
  /// This can be true while loading or failed; [loadMore] only acts when idle.
  bool get hasMore => !isDone;

  /// Loads another page when idle; otherwise does nothing.
  ///
  /// Controls on manually constructed snapshots with no callbacks do nothing.
  /// Controls captured before a reset, argument change, or disposal are inert.
  void loadMore() => _onLoadMore?.call();

  /// Restarts a failed query from page one, discarding its loaded pages.
  ///
  /// Does nothing unless the current query is in an error state. This also
  /// recovers stream and item-decoding errors. Successful queries are untouched.
  void retry() => _onRetry?.call();

  /// Discards all loaded pages and restarts from page one, in any state.
  void reset() => _onReset?.call();

  /// Accumulated items from all loaded pages.
  final List<T> items;

  /// Current pagination state.
  final PaginationStatus status;

  /// Whether the server has exhausted the query.
  final bool isDone;

  /// The backend, stream, or decoding error, if any.
  /// Item-decoding failures are wrapped in [ConvexDecodeException].
  final Object? error;

  /// Whether optimistic writes affect any loaded page.
  final bool hasPendingWrites;
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
    decoderIdentity: query.decodeItem,
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
    required this.decoderIdentity,
    required this.builder,
  });

  final String query;
  final Map<String, dynamic>? args;
  final int pageSize;
  final ConvexRuntimeClient? client;
  final T Function(dynamic) decode;
  final Object decoderIdentity;
  final Widget Function(
    BuildContext,
    ConvexPaginatedQuerySnapshot<T>,
    VoidCallback,
  )
  builder;

  @override
  State<_PaginatedQuery<T>> createState() => _PaginatedQueryState<T>();
}

class _PaginatedQueryState<T> extends State<_PaginatedQuery<T>>
    with ConvexSafeRebuild<_PaginatedQuery<T>> {
  static const DeepCollectionEquality _deepEquality = DeepCollectionEquality();

  ConvexRuntimeClient? _client;
  ConvexRuntimePaginatedQuery? _query;
  StreamSubscription<convex.ConvexPaginatedResult>? _subscription;
  Map<String, dynamic>? _subscribedArgs;
  int _queryGeneration = 0;

  List<T> _items = List<T>.unmodifiable(const <Never>[]);
  PaginationStatus _status = PaginationStatus.loading;
  Object? _error;
  convex.ConvexPaginatedResult? _lastResult;

  /// Decoded items keyed by their raw map instance. The core reuses the item
  /// maps of unchanged pages, so an emission only decodes what changed.
  /// Replaced whenever [PaginatedQueryBuilder.fromJson] changes.
  Expando<_Decoded<T>> _decodedItems = Expando<_Decoded<T>>();

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
    } else if (oldWidget.decoderIdentity != widget.decoderIdentity) {
      // The item mapper is not part of the query identity — an inline closure
      // differs on every parent rebuild, and restarting would drop every
      // loaded page. Re-map the current result in place instead; a rebuild is
      // already scheduled, so plain assignment is enough.
      _decodedItems = Expando<_Decoded<T>>();
      final result = _lastResult;
      if (result != null) {
        _applyResult(result);
      }
    }
  }

  /// (Re)starts the query. Called from lifecycle callbacks (always followed
  /// by a build) or inside [applyAndRebuild], so state is assigned directly.
  void _start() {
    final generation = ++_queryGeneration;
    _subscription?.cancel();
    _subscription = null;
    _query?.cancel();
    _query = null;
    _lastResult = null;
    _error = null;
    _decodedItems = Expando<_Decoded<T>>();
    final ConvexRuntimePaginatedQuery query;
    try {
      final argsSnapshot = snapshotConvexArgs(widget.args);
      _subscribedArgs = argsSnapshot;
      query = _client!.paginatedQuery(
        widget.query,
        argsSnapshot,
        pageSize: widget.pageSize,
      );
    } catch (error) {
      // A disposed client throws synchronously; show the error state instead
      // of an ErrorWidget. With no query, the next dependency or client change
      // (or the error builder's retry) tries again.
      _items = List<T>.unmodifiable(const <Never>[]);
      _status = PaginationStatus.error;
      _error = error;
      return;
    }
    _query = query;
    // Seed synchronously from the current snapshot (a build is already pending
    // from this lifecycle callback), then update reactively from the stream.
    _items = List<T>.unmodifiable(const <Never>[]);
    _applyResult(query.current);
    _subscription = query.stream.listen(
      (result) {
        if (generation != _queryGeneration || !mounted) {
          return;
        }
        // Synchronous core stream: loadMore() from an itemBuilder emits during
        // layout, so the rebuild may be deferred to after the frame.
        applyAndRebuild(() => _applyResult(result));
      },
      onError: (Object error, StackTrace stackTrace) {
        if (generation != _queryGeneration || !mounted) {
          return;
        }
        applyAndRebuild(() {
          _lastResult = convex.ConvexPaginatedResult(
            results: _lastResult?.results ?? const <dynamic>[],
            status: convex.ConvexPaginationStatus.error,
            isDone: false,
            error: error,
            hasPendingWrites: _lastResult?.hasPendingWrites ?? false,
          );
          _status = PaginationStatus.error;
          _error = error;
        });
      },
    );
  }

  /// Maps [result] into the items, status and error. A decode failure keeps
  /// the current items, switches to the error status, and is reported.
  void _applyResult(convex.ConvexPaginatedResult result) {
    _lastResult = result;
    try {
      _items = _mapItems(result);
      _status = _mapStatus(result.status);
      _error = _status == PaginationStatus.error
          ? (result.error ??
                StateError(
                  'Paginated query "${widget.query}" '
                  'failed',
                ))
          : null;
    } on ConvexDecodeException catch (error) {
      _status = PaginationStatus.error;
      _error = error;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error.error,
          stack: error.stackTrace,
          library: 'dartvex_flutter',
          context: ErrorDescription(
            'while decoding an item of PaginatedQueryBuilder '
            '"${widget.query}"',
          ),
        ),
      );
    }
  }

  List<T> _mapItems(convex.ConvexPaginatedResult result) {
    final decodedItems = _decodedItems;
    final decode = widget.decode;
    final items = <T>[];
    for (final item in result.results) {
      final memoizable = item is Map;
      if (memoizable) {
        final cached = decodedItems[item];
        if (cached != null) {
          items.add(cached.value);
          continue;
        }
      }
      final T decoded;
      try {
        decoded = decode(item);
      } catch (error, stackTrace) {
        throw ConvexDecodeException(error, stackTrace, value: item);
      }
      if (memoizable) {
        decodedItems[item] = _Decoded<T>(decoded);
      }
      items.add(decoded);
    }
    return List<T>.unmodifiable(items);
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

  void _loadMore() {
    if (!mounted || _status != PaginationStatus.idle) return;
    _query?.loadMore();
  }

  void _restart({required bool onlyIfFailed}) {
    if (!mounted ||
        _client == null ||
        (onlyIfFailed && _status != PaginationStatus.error)) {
      return;
    }
    applyAndRebuild(_start);
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
    final generation = _queryGeneration;
    void act(VoidCallback action) {
      if (mounted && generation == _queryGeneration) action();
    }

    void loadMore() => act(_loadMore);
    return widget.builder(
      context,
      ConvexPaginatedQuerySnapshot<T>(
        items: _items,
        status: _status,
        isDone: _lastResult?.isDone ?? false,
        error: _error,
        hasPendingWrites: _lastResult?.hasPendingWrites ?? false,
        onLoadMore: loadMore,
        onRetry: () => act(() => _restart(onlyIfFailed: true)),
        onReset: () => act(() => _restart(onlyIfFailed: false)),
      ),
      loadMore,
    );
  }
}

/// Wraps a decoded item so a nullable `T` can be memoized in an [Expando].
class _Decoded<T> {
  const _Decoded(this.value);

  final T value;
}

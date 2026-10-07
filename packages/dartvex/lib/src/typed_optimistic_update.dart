import 'query.dart';
import 'sync/optimistic_updates.dart';

/// A typed local view of query results during an optimistic mutation.
final class TypedOptimisticLocalStore {
  /// Wraps the runtime's local query store.
  const TypedOptimisticLocalStore(this._store);

  final OptimisticLocalStore _store;

  /// Returns a cached query result, or null when unavailable or actually null.
  Result? getQuery<Args, Result>(
    ConvexQueryReference<Args, Result> query,
    Args args,
  ) {
    final raw = _store.getQuery(query.name, query.encode(args));
    return raw == null ? null : query.decode(raw);
  }

  /// Returns all cached argument variants for a query.
  List<TypedOptimisticQueryEntry<Args, Result>> getAllQueries<Args, Result>(
    ConvexQueryReference<Args, Result> query,
  ) =>
      _store.getAllQueries(query.name).map((entry) {
        final raw = entry.value;
        return TypedOptimisticQueryEntry<Args, Result>(
          args: query.decodeArgs(entry.args),
          value: raw == null ? null : query.decode(raw),
          isLoading: entry.isLoading,
        );
      }).toList();

  /// Overlays a complete typed query result until the mutation settles.
  void setQuery<Args, Result>(
    ConvexQueryReference<Args, Result> query,
    Args args,
    Result value,
  ) =>
      _store.setQuery(
        query.name,
        query.encode(args),
        query.encodeResult(value),
      );

  /// Shows loading for a query until the mutation settles.
  void clearQuery<Args, Result>(
    ConvexQueryReference<Args, Result> query,
    Args args,
  ) =>
      _store.clearQuery(query.name, query.encode(args));

  /// Replaces a loaded non-null result, leaving absent results unchanged.
  void updateQuery<Args, Result>(
    ConvexQueryReference<Args, Result> query,
    Args args,
    Result Function(Result current) update,
  ) {
    final current = getQuery(query, args);
    if (current == null) return;
    setQuery(query, args, update(current));
  }
}

/// A cached query variant visible during an optimistic update.
final class TypedOptimisticQueryEntry<Args, Result> {
  /// Creates an entry with typed arguments and result.
  const TypedOptimisticQueryEntry({
    required this.args,
    required this.value,
    required this.isLoading,
  });

  /// Arguments for this query variant.
  final Args args;

  /// Current value, or null for loading, error, or a real null result.
  final Result? value;

  /// Whether the query was explicitly cleared to loading.
  final bool isLoading;
}

/// Stable values created once for an optimistic mutation invocation.
final class OptimisticMutationContext {
  OptimisticMutationContext._(this.temporaryId, this.startedAt);

  static int _nextId = 0;
  static const String _temporaryIdPrefix = 'optimistic:';

  /// Creates a fresh context for one mutation invocation.
  factory OptimisticMutationContext.create() {
    final now = DateTime.now();
    return OptimisticMutationContext._(
      '$_temporaryIdPrefix${now.microsecondsSinceEpoch}:${_nextId++}',
      now.millisecondsSinceEpoch.toDouble(),
    );
  }

  /// Stable, local-only ID for temporary query items.
  final String temporaryId;

  /// Stable client time in milliseconds since the Unix epoch.
  final double startedAt;

  /// Whether [id] was created for an in-flight optimistic mutation.
  static bool isTemporaryId(String id) => id.startsWith(_temporaryIdPrefix);
}

/// Typed optimistic update that can inspect the mutation arguments.
typedef TypedOptimisticUpdate<Args> = void Function(
  TypedOptimisticLocalStore store,
  Args args,
  OptimisticMutationContext context,
);

/// Binds typed arguments and a stable context for each callback replay.
OptimisticUpdate bindTypedOptimisticUpdate<Args>(
  TypedOptimisticUpdate<Args> update,
  Args args,
) {
  final context = OptimisticMutationContext.create();
  return (store) => update(TypedOptimisticLocalStore(store), args, context);
}

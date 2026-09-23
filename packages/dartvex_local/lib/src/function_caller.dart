import 'package:dartvex/dartvex.dart';

import 'client.dart';

/// Adapts [ConvexLocalClient] to the generated API's [ConvexFunctionCaller].
///
/// Ordinary queries, subscriptions, mutations, and actions use [localClient].
/// Paginated queries are delegated to [remoteCaller], because local pagination
/// does not currently provide the page-level runtime required by
/// [ConvexPaginatedQuery].
class ConvexLocalFunctionCaller implements ConvexFunctionCaller {
  /// Creates a generated-API-compatible local caller.
  const ConvexLocalFunctionCaller({
    required this.localClient,
    required this.remoteCaller,
    this.nullableQueuedMutations = const <String>{},
  });

  /// Local client used for non-paginated function calls.
  final ConvexLocalClient localClient;

  /// Remote caller used only for paginated queries.
  final ConvexFunctionCaller remoteCaller;

  /// Mutations whose generated return type accepts `null` while queued.
  ///
  /// Every other queued mutation must have a handler-provided
  /// [LocalMutationQueued.optimisticValue]. This prevents a generated API with
  /// a non-null return type from receiving an unusable `null` result.
  final Set<String> nullableQueuedMutations;

  @override
  Future<dynamic> action(
    String name, [
    Map<String, dynamic> args = const <String, dynamic>{},
  ]) => localClient.action(name, args);

  @override
  Future<dynamic> mutate(
    String name, [
    Map<String, dynamic> args = const <String, dynamic>{},
  ]) async {
    final result = await localClient.mutate(name, args);
    return switch (result) {
      LocalMutationSuccess(:final value) => value,
      LocalMutationQueued(:final optimisticValue) =>
        optimisticValue ??
            (nullableQueuedMutations.contains(name)
                ? null
                : throw StateError(
                    'Mutation "$name" was queued without an optimistic '
                    'return value. Override '
                    'LocalMutationHandler.optimisticValue or add the mutation '
                    'to nullableQueuedMutations if it returns null.',
                  )),
      LocalMutationFailed(:final error) => throw error,
    };
  }

  @override
  ConvexPaginatedQuery paginatedQuery(
    String name,
    Map<String, dynamic> args, {
    int pageSize = 20,
  }) => remoteCaller.paginatedQuery(name, args, pageSize: pageSize);

  @override
  Future<dynamic> query(
    String name, [
    Map<String, dynamic> args = const <String, dynamic>{},
  ]) => localClient.query(name, args);

  @override
  Future<T> queryOnce<T>(
    String name, [
    Map<String, dynamic> args = const <String, dynamic>{},
  ]) async {
    final value = await localClient.query(name, args);
    return value as T;
  }

  @override
  ConvexSubscription subscribe(
    String name, [
    Map<String, dynamic> args = const <String, dynamic>{},
  ]) {
    final subscription = localClient.subscribe(name, args);
    return ConvexSubscription(
      stream: subscription.stream.map(_mapQueryEvent),
      onCancel: () async => subscription.cancel(),
    );
  }

  static QueryResult _mapQueryEvent(LocalQueryEvent event) {
    return switch (event) {
      LocalQuerySuccess(:final value, :final hasPendingWrites) => QuerySuccess(
        value,
        hasPendingWrites: hasPendingWrites,
      ),
      LocalQueryError(:final error) => switch (error) {
        ConvexException(:final message, :final data, :final logLines) =>
          QueryError(message, data: data, logLines: logLines),
        _ => QueryError(error.toString()),
      },
    };
  }
}

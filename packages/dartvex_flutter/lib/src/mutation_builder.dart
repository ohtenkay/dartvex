import 'dart:async';

import 'package:dartvex/dartvex.dart'
    show
        ConvexMutationReference,
        OptimisticUpdate,
        OptimisticUpdateHandle,
        convexToJson,
        jsonToConvex,
        TypedOptimisticUpdate,
        bindTypedOptimisticUpdate;
import 'package:flutter/widgets.dart';

import 'provider.dart';
import 'runtime_client.dart';
import 'snapshot.dart';

/// Controls overlapping calls to a mutation widget.
enum MutationMode {
  /// Reject calls while a request is active (the default for forms).
  single,

  /// Apply every optimistic selection immediately, sending the active request
  /// followed by only the newest pending invocation. Use for replacement writes,
  /// not increments, inserts, or other operations that must execute every call.
  latest,
}

/// An unsent invocation was replaced by a newer invocation in latest mode.
final class MutationSupersededException implements Exception {
  /// Creates a superseded invocation error.
  const MutationSupersededException();

  @override
  String toString() => 'Mutation invocation superseded by a newer value.';
}

/// An unsent invocation was cancelled when its widget identity changed.
final class MutationCancelledException implements Exception {
  /// Creates a cancelled invocation error.
  const MutationCancelledException();

  @override
  String toString() => 'Queued mutation cancelled.';
}

class _LatestInvocation<Result> {
  _LatestInvocation({
    required this.name,
    required this.args,
    required this.decode,
    required this.client,
  });

  final String name;
  final Map<String, dynamic> args;
  final Result Function(dynamic) decode;
  final ConvexRuntimeClient client;
  final Completer<Result> completer = Completer<Result>();
}

/// Builder callback for [ConvexMutation].
typedef ConvexMutationBuilder<Args, Result> =
    Widget Function(
      BuildContext context,
      Future<Result> Function(Args args) mutate,
      ConvexRequestSnapshot<Result> snapshot,
    );

/// Widget that exposes an imperative Convex mutation and request snapshot.
class ConvexMutation<Args, Result> extends StatefulWidget {
  /// Creates a [ConvexMutation].
  const ConvexMutation({
    super.key,
    required this.mutation,
    required this.builder,
    this.client,
    this.optimisticUpdate,
    this.typedOptimisticUpdate,
    this.mode = MutationMode.single,
  }) : assert(optimisticUpdate == null || typedOptimisticUpdate == null);

  /// Policy for overlapping calls. Defaults to duplicate-call rejection.
  final MutationMode mode;

  /// Generated mutation reference containing its name and wire codecs.
  final ConvexMutationReference<Args, Result> mutation;

  /// Optional runtime client override.
  final ConvexRuntimeClient? client;

  /// Optional optimistic update applied while the mutation is in flight.
  ///
  /// Overlays query results locally the moment the mutation is sent and rolls
  /// back automatically when it completes or fails. See `ConvexClient.mutate`.
  final OptimisticUpdate? optimisticUpdate;

  /// Typed optimistic update with the arguments for this mutation invocation.
  final TypedOptimisticUpdate<Args>? typedOptimisticUpdate;

  /// Builder that receives the mutate callback and current request snapshot.
  final ConvexMutationBuilder<Args, Result> builder;

  @override
  State<ConvexMutation<Args, Result>> createState() =>
      _ConvexMutationState<Args, Result>();
}

class _ConvexMutationState<Args, Result>
    extends State<ConvexMutation<Args, Result>> {
  ConvexRuntimeClient? _runtimeClient;
  ConvexRequestSnapshot<Result> _snapshot =
      ConvexRequestSnapshot<Result>.initial();
  Future<Result>? _inFlight;
  int _requestGeneration = 0;
  bool _latestRunning = false;
  _LatestInvocation<Result>? _latestPending;
  OptimisticUpdateHandle? _latestOverlay;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final resolvedClient = widget.client ?? ConvexProvider.of(context);
    if (_runtimeClient == null) {
      _runtimeClient = resolvedClient;
      return;
    }
    if (_runtimeClient != resolvedClient) {
      _runtimeClient = resolvedClient;
      _invalidateRequestState();
    }
  }

  @override
  void didUpdateWidget(covariant ConvexMutation<Args, Result> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final resolvedClient = widget.client ?? ConvexProvider.of(context);
    // codecs and optimisticUpdate are captured per request, not part of the
    // mutation identity — inline closures differ on every parent rebuild and
    // must not wipe the snapshot or orphan an in-flight request.
    final identityChanged =
        oldWidget.mutation.name != widget.mutation.name ||
        oldWidget.mode != widget.mode ||
        _runtimeClient != resolvedClient;
    _runtimeClient = resolvedClient;
    if (identityChanged) {
      _invalidateRequestState();
    }
  }

  @override
  void dispose() {
    _cancelLatest();
    _requestGeneration += 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _mutate, _snapshot);
  }

  Future<Result> _mutate(Args args) {
    if (widget.mode == MutationMode.latest) return _mutateLatest(args);
    final active = _inFlight;
    if (active != null) {
      // ignore() keeps an ignored return value (the normal builder pattern,
      // where the snapshot carries the state) from surfacing as an unhandled
      // zone error; awaiting callers still receive the StateError.
      final rejection = Future<Result>.error(
        StateError(
          'Mutation "${widget.mutation.name}" is already in progress.',
        ),
      );
      rejection.ignore();
      return rejection;
    }
    final completer = Completer<Result>();
    final future = completer.future;
    // The builder API intentionally lets callers ignore the returned future
    // and observe failures through the snapshot.
    future.ignore();
    _inFlight = future;
    final generation = ++_requestGeneration;
    final runtimeClient = _runtimeClient!;
    final mutation = widget.mutation;
    final typedUpdate = widget.typedOptimisticUpdate;
    final optimisticUpdate = typedUpdate == null
        ? widget.optimisticUpdate
        : bindTypedOptimisticUpdate(typedUpdate, args);
    setState(() {
      _snapshot = _snapshot.copyWith(
        error: null,
        isLoading: true,
        hasError: false,
      );
    });

    () async {
      try {
        final raw = await runtimeClient.mutate(
          mutation.name,
          mutation.encode(args),
          optimisticUpdate,
        );
        final decoded = mutation.decode(raw);
        if (mounted && generation == _requestGeneration) {
          setState(() {
            _snapshot = ConvexRequestSnapshot<Result>(
              data: decoded,
              error: null,
              isLoading: false,
              hasData: true,
              hasError: false,
            );
          });
        }
        completer.complete(decoded);
      } catch (error, stackTrace) {
        if (mounted && generation == _requestGeneration) {
          setState(() {
            _snapshot = _snapshot.copyWith(
              error: error,
              isLoading: false,
              hasError: true,
            );
          });
        }
        completer.completeError(error, stackTrace);
      } finally {
        if (generation == _requestGeneration) {
          _inFlight = null;
        }
      }
    }();

    return future;
  }

  Future<Result> _mutateLatest(Args args) {
    try {
      return _queueLatest(args);
    } catch (error, stack) {
      setState(() {
        _snapshot = _snapshot.copyWith(
          error: error,
          hasError: true,
          isLoading: _latestRunning,
        );
      });
      final future = Future<Result>.error(error, stack);
      future.ignore();
      return future;
    }
  }

  Future<Result> _queueLatest(Args args) {
    final invocation = _LatestInvocation<Result>(
      name: widget.mutation.name,
      args: Map<String, dynamic>.from(
        jsonToConvex(convexToJson(widget.mutation.encode(args))) as Map,
      ),
      decode: widget.mutation.decode,
      client: _runtimeClient!,
    );
    final future = invocation.completer.future;
    future.ignore();
    final typedUpdate = widget.typedOptimisticUpdate;
    final update = typedUpdate == null
        ? widget.optimisticUpdate
        : bindTypedOptimisticUpdate(typedUpdate, args);
    if (update != null) {
      final overlay = _latestOverlay;
      if (overlay == null) {
        _latestOverlay = invocation.client.createOptimisticUpdate(update);
      } else {
        overlay.replace(update);
      }
    } else {
      _latestOverlay?.dispose();
      _latestOverlay = null;
    }
    _latestPending?.completer.completeError(
      const MutationSupersededException(),
    );
    _latestPending = invocation;
    setState(() {
      _snapshot = _snapshot.copyWith(
        error: null,
        hasError: false,
        isLoading: true,
      );
    });
    if (!_latestRunning) {
      _latestRunning = true;
      unawaited(_drainLatest(_requestGeneration));
    }
    return future;
  }

  Future<void> _drainLatest(int generation) async {
    while (generation == _requestGeneration) {
      final invocation = _latestPending;
      if (invocation == null) break;
      _latestPending = null;
      Result? result;
      Object? failure;
      try {
        final raw = await invocation.client.mutate(
          invocation.name,
          invocation.args,
        );
        final decoded = invocation.decode(raw);
        result = decoded;
        invocation.completer.complete(decoded);
      } catch (error, stack) {
        failure = error;
        invocation.completer.completeError(error, stack);
      }
      if (generation != _requestGeneration) return;
      // A newer intent stays visible even when the older request fails.
      if (_latestPending != null) continue;
      _latestRunning = false;
      _latestOverlay?.dispose();
      _latestOverlay = null;
      if (mounted) {
        setState(() {
          _snapshot = failure == null
              ? ConvexRequestSnapshot<Result>(
                  data: result,
                  error: null,
                  isLoading: false,
                  hasData: true,
                  hasError: false,
                )
              : _snapshot.copyWith(
                  error: failure,
                  hasError: true,
                  isLoading: false,
                );
        });
      }
      return;
    }
  }

  void _cancelLatest() {
    _latestPending?.completer.completeError(const MutationCancelledException());
    _latestPending = null;
    _latestRunning = false;
    _latestOverlay?.dispose();
    _latestOverlay = null;
  }

  void _invalidateRequestState() {
    _cancelLatest();
    _requestGeneration += 1;
    _inFlight = null;
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = ConvexRequestSnapshot<Result>.initial();
    });
  }
}

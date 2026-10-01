import 'dart:async';

import 'package:dartvex/dartvex.dart'
    show
        ConvexMutationReference,
        OptimisticUpdate,
        TypedOptimisticUpdate,
        bindTypedOptimisticUpdate;
import 'package:flutter/widgets.dart';

import 'provider.dart';
import 'runtime_client.dart';
import 'snapshot.dart';

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
  }) : assert(optimisticUpdate == null || typedOptimisticUpdate == null);

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
        _runtimeClient != resolvedClient;
    _runtimeClient = resolvedClient;
    if (identityChanged) {
      _invalidateRequestState();
    }
  }

  @override
  void dispose() {
    _requestGeneration += 1;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _mutate, _snapshot);
  }

  Future<Result> _mutate(Args args) {
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

  void _invalidateRequestState() {
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

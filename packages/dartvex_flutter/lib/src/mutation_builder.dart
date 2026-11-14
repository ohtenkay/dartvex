import 'package:dartvex/dartvex.dart'
    show
        ConvexMutationReference,
        OptimisticUpdate,
        TypedOptimisticUpdate,
        bindTypedOptimisticUpdate;
import 'package:flutter/widgets.dart';

import 'request_state.dart';
import 'runtime_client.dart';
import 'safe_rebuild.dart';
import 'snapshot.dart';

/// Builder callback for [ConvexMutation].
typedef ConvexMutationBuilder<Args, Result> =
    Widget Function(
      BuildContext context,
      Future<Result> Function(Args args) mutate,
      ConvexRequestSnapshot<Result> snapshot,
    );

/// Widget exposing a typed mutation executor and request snapshot.
///
/// The executor is single-flight: overlapping calls reject with [StateError].
/// A request stays in flight until the server confirms it, including while
/// offline. Disable its trigger while `snapshot.isLoading`.
///
/// Captured executors remain usable after unmount: the request is sent, while
/// snapshot updates stop. Decoder failures report [ConvexDecodeException];
/// the server write already succeeded and must not be retried as a rejection.
class ConvexMutation<Args, Result> extends StatefulWidget {
  /// Creates a typed mutation widget.
  const ConvexMutation({
    super.key,
    required this.mutation,
    required this.builder,
    this.client,
    this.optimisticUpdate,
    this.typedOptimisticUpdate,
  }) : assert(optimisticUpdate == null || typedOptimisticUpdate == null);

  /// Mutation name and codecs, normally generated from the backend.
  final ConvexMutationReference<Args, Result> mutation;

  /// Optional runtime client override.
  final ConvexRuntimeClient? client;

  /// Raw optimistic update, mutually exclusive with [typedOptimisticUpdate].
  final OptimisticUpdate? optimisticUpdate;

  /// Typed update bound to the arguments and stable context of this invocation.
  final TypedOptimisticUpdate<Args>? typedOptimisticUpdate;

  /// Builds the UI with the executor and current request state.
  final ConvexMutationBuilder<Args, Result> builder;

  @override
  State<ConvexMutation<Args, Result>> createState() =>
      _ConvexMutationState<Args, Result>();
}

class _ConvexMutationState<Args, Result>
    extends State<ConvexMutation<Args, Result>>
    with
        ConvexSafeRebuild<ConvexMutation<Args, Result>>,
        ConvexRequestState<ConvexMutation<Args, Result>, Args, Result> {
  @override
  ConvexRuntimeClient? get clientOverride => widget.client;

  @override
  String get requestLabel => 'Mutation "${widget.mutation.name}"';

  @override
  ConvexDecoder<Result> get decoder => widget.mutation.decode;

  @override
  ConvexRequestCall<Args> captureRequest() {
    final mutation = widget.mutation;
    final optimisticUpdate = widget.optimisticUpdate;
    final typedUpdate = widget.typedOptimisticUpdate;
    return (client, args) => client.mutate(
      mutation.name,
      mutation.encode(args),
      typedUpdate == null
          ? optimisticUpdate
          : bindTypedOptimisticUpdate(typedUpdate, args),
    );
  }

  @override
  void didUpdateWidget(covariant ConvexMutation<Args, Result> oldWidget) {
    super.didUpdateWidget(oldWidget);
    updateRequestIdentity(
      nameChanged: oldWidget.mutation.name != widget.mutation.name,
    );
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, runRequest, requestSnapshot);
}

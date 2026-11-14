import 'dart:async';
import 'dart:collection';

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

import 'request_state.dart';
import 'runtime_client.dart';
import 'safe_rebuild.dart';
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

/// An unsent invocation was cancelled when its owner or identity changed.
final class MutationCancelledException implements Exception {
  /// Creates a cancelled invocation error.
  const MutationCancelledException();

  @override
  String toString() => 'Queued mutation cancelled.';
}

/// Builder callback for [ConvexMutation].
typedef ConvexMutationBuilder<Args, Result> =
    Widget Function(
      BuildContext context,
      Future<Result> Function(Args args) mutate,
      ConvexRequestSnapshot<Result> snapshot,
    );

/// Widget exposing a typed mutation executor and request snapshot.
///
/// In [MutationMode.single], overlapping calls reject with [StateError].
/// [MutationMode.latest] sends the active request followed by the newest queued
/// value. Use it for replacement writes, not increments or inserts.
/// A request stays in flight until the server confirms it, including while
/// offline. Disable its trigger while `snapshot.isLoading`.
///
/// Single-mode executors remain usable after unmount: the request is sent, while
/// snapshot updates stop. Latest-mode calls after unmount and unsent queued
/// calls on unmount reject with [MutationCancelledException]. Decoder failures report [ConvexDecodeException];
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
    this.mode = MutationMode.single,
  }) : assert(optimisticUpdate == null || typedOptimisticUpdate == null);

  /// Policy for overlapping calls. Latest mode coalesces unsent invocations.
  final MutationMode mode;

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
  final Queue<_LatestInvocation<Result>> _latestSubmissions = Queue();
  _LatestInvocation<Result>? _latestPending;
  _LatestInvocation<Result>? _latestOwner;
  OptimisticUpdateHandle? _latestOverlay;
  bool _latestRunning = false;
  bool _submittingLatest = false;
  bool _latestDisposed = false;

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
      nameChanged:
          oldWidget.mutation.name != widget.mutation.name ||
          oldWidget.mode != widget.mode,
    );
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _mutate, requestSnapshot);

  @override
  void dispose() {
    _latestDisposed = true;
    super.dispose();
  }

  @override
  void onRequestInvalidated() {
    final pending = _latestPending;
    final overlay = _latestOverlay;
    _latestPending = null;
    _latestOverlay = null;
    _latestOwner = null;
    _latestRunning = false;
    pending?.completer.completeError(const MutationCancelledException());
    while (_latestSubmissions.isNotEmpty) {
      _latestSubmissions.removeFirst().completer.completeError(
        const MutationCancelledException(),
      );
    }
    overlay?.dispose();
  }

  Future<Result> _mutate(Args args) {
    if (widget.mode == MutationMode.single) return runRequest(args);
    if (_latestDisposed || !mounted) {
      return _rejected(const MutationCancelledException());
    }
    // An adapter may keep its instance while auth changes underneath it.
    if (_latestOwner case final owner? when !owner.identityIsCurrent) {
      invalidateRequestState();
    }
    final mutation = widget.mutation;
    final _LatestInvocation<Result> invocation;
    try {
      final encoded = Map<String, dynamic>.from(
        jsonToConvex(convexToJson(mutation.encode(args))) as Map,
      );
      final typedUpdate = widget.typedOptimisticUpdate;
      invocation = _LatestInvocation(
        name: mutation.name,
        args: encoded,
        decode: mutation.decode,
        client: requestClient,
        generation: requestGeneration,
        update: typedUpdate == null
            ? widget.optimisticUpdate
            : bindTypedOptimisticUpdate(typedUpdate, args),
      );
    } catch (error, stack) {
      updateRequestSnapshot(
        requestSnapshot.copyWith(
          error: error,
          hasError: true,
          isLoading: _latestRunning,
        ),
      );
      return _rejected(error, stack);
    }
    _latestSubmissions.add(invocation);
    _submitLatest();
    return invocation.completer.future;
  }

  Future<Result> _rejected(Object error, [StackTrace? stack]) {
    final future = Future<Result>.error(error, stack);
    future.ignore();
    return future;
  }

  bool _isCurrent(_LatestInvocation<Result> invocation) =>
      !_latestDisposed &&
      mounted &&
      invocation.generation == requestGeneration &&
      invocation.identityIsCurrent;

  void _submitLatest() {
    // Overlay notifications are synchronous and can submit another intent.
    // Serialize those submissions before starting the next network request.
    if (_submittingLatest) return;
    _submittingLatest = true;
    try {
      while (_latestSubmissions.isNotEmpty) {
        final invocation = _latestSubmissions.removeFirst();
        if (!_isCurrent(invocation)) {
          invocation.completer.completeError(
            const MutationCancelledException(),
          );
          continue;
        }
        try {
          final update = invocation.update;
          final overlay = _latestOverlay;
          if (update == null) {
            _latestOverlay = null;
            overlay?.dispose();
          } else if (overlay == null) {
            final created = invocation.client.createOptimisticUpdate(update);
            if (!_isCurrent(invocation)) {
              created.dispose();
            } else {
              _latestOverlay = created;
            }
          } else {
            overlay.replace(update);
          }
        } catch (error, stack) {
          final failure = _isCurrent(invocation)
              ? error
              : const MutationCancelledException();
          invocation.completer.completeError(failure, stack);
          if (_isCurrent(invocation)) {
            updateRequestSnapshot(
              requestSnapshot.copyWith(
                error: error,
                hasError: true,
                isLoading: _latestRunning,
              ),
            );
          }
          continue;
        }
        if (!_isCurrent(invocation)) {
          invocation.completer.completeError(
            const MutationCancelledException(),
          );
          continue;
        }
        _latestPending?.completer.completeError(
          const MutationSupersededException(),
        );
        _latestPending = invocation;
        _latestOwner ??= invocation;
        updateRequestSnapshot(
          requestSnapshot.copyWith(
            error: null,
            hasError: false,
            isLoading: true,
          ),
        );
      }
    } finally {
      _submittingLatest = false;
    }
    if (!_latestRunning && _latestPending != null) {
      _latestRunning = true;
      unawaited(_drainLatest(requestGeneration));
    }
  }

  Future<void> _drainLatest(int generation) async {
    while (generation == requestGeneration) {
      final invocation = _latestPending;
      if (invocation == null) return;
      if (!_isCurrent(invocation)) {
        invalidateRequestState();
        return;
      }
      _latestPending = null;
      Result? result;
      Object? failure;
      try {
        final raw = await invocation.client.mutate(
          invocation.name,
          invocation.args,
        );
        try {
          result = invocation.decode(raw);
        } catch (error, stack) {
          throw ConvexDecodeException(error, stack, value: raw);
        }
        invocation.completer.complete(result);
      } catch (error, stack) {
        failure = error;
        invocation.completer.completeError(error, stack);
      }
      if (generation != requestGeneration) return;
      if (!_isCurrent(invocation)) {
        invalidateRequestState();
        return;
      }
      if (_latestPending != null) continue;
      _latestRunning = false;
      _latestOwner = null;
      final overlay = _latestOverlay;
      _latestOverlay = null;
      overlay?.dispose();
      // Removing the overlay can synchronously start a new wave of work.
      if (generation != requestGeneration || _latestOwner != null) return;
      updateRequestSnapshot(
        failure == null
            ? ConvexRequestSnapshot<Result>(
                data: result,
                error: null,
                isLoading: false,
                hasData: true,
                hasError: false,
              )
            : requestSnapshot.copyWith(
                error: failure,
                hasError: true,
                isLoading: false,
              ),
      );
      return;
    }
  }
}

class _LatestInvocation<Result> {
  _LatestInvocation({
    required this.name,
    required this.args,
    required this.decode,
    required this.client,
    required this.generation,
    required this.update,
  }) : identity = client is ConvexRuntimeIdentitySource
           ? (client as ConvexRuntimeIdentitySource).queryIdentityGeneration
           : null {
    completer.future.ignore();
  }
  final String name;
  final Map<String, dynamic> args;
  final Result Function(dynamic) decode;
  final ConvexRuntimeClient client;
  final int generation;
  final int? identity;
  final OptimisticUpdate? update;
  final Completer<Result> completer = Completer<Result>();

  bool get identityIsCurrent =>
      client is! ConvexRuntimeIdentitySource ||
      (client as ConvexRuntimeIdentitySource).queryIdentityGeneration ==
          identity;
}

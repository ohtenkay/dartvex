// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: type=lint, unused_element, unused_import, unused_local_variable
// ignore_for_file: unnecessary_import

import '../api.dart';
import '../modules/messages.dart';

import 'dart:async';
import 'dart:typed_data';

import 'package:dartvex_flutter/dartvex_flutter.dart';
import 'package:flutter/widgets.dart';

/// Callable typed mutation for messages:send.
class MessagesSendMutationExecutor {
  /// Creates an executor backed by the mutation widget.
  const MessagesSendMutationExecutor(this._mutate);

  final Future<MessagesId> Function(SendArgs) _mutate;

  /// Runs the mutation.
  Future<MessagesId> call({
    required String author,
    required String text,
    Optional<Uint8List> attachment = const Optional.absent(),
  }) => _mutate((author: author, text: text, attachment: attachment));

  /// Starts the mutation, observing failures through the widget snapshot.
  ///
  /// [onSuccess] runs only on success. Errors from that callback are not
  /// suppressed. Use [call] when you need to await the result or handle errors.
  void run({
    required String author,
    required String text,
    Optional<Uint8List> attachment = const Optional.absent(),
    void Function(MessagesId result)? onSuccess,
  }) {
    unawaited(
      _mutate((author: author, text: text, attachment: attachment))
          .then<void>((result) {
            onSuccess?.call(result);
          }, onError: (Object error, StackTrace stackTrace) {}),
    );
  }
}

/// Flutter widget for messages:send.
class MessagesSendMutation extends StatelessWidget {
  /// Creates a typed mutation widget.
  const MessagesSendMutation({
    super.key,
    required this.builder,
    this.client,
    this.optimisticUpdate,
    this.mode = MutationMode.single,
  });

  /// Builds the UI with the callable mutation and current request state.
  final Widget Function(
    BuildContext,
    MessagesSendMutationExecutor,
    ConvexRequestSnapshot<MessagesId>,
  )
  builder;

  /// Optional runtime client override.
  final ConvexRuntimeClient? client;

  /// Optional optimistic update for the mutation.
  final TypedOptimisticUpdate<SendArgs>? optimisticUpdate;

  /// Whether overlapping calls are rejected or coalesced to the latest value.
  final MutationMode mode;

  @override
  Widget build(BuildContext context) => ConvexMutation<SendArgs, MessagesId>(
    mutation: sendMutationReference,
    client: client,
    typedOptimisticUpdate: optimisticUpdate,
    mode: mode,
    builder: (context, mutate, snapshot) =>
        builder(context, MessagesSendMutationExecutor(mutate), snapshot),
  );
}

/// Flutter widget for messages:list.
class MessagesListQuery extends StatelessWidget {
  /// Creates a typed query widget with default loading and error UI.
  const MessagesListQuery({
    super.key,
    required this.builder,
    this.client,
    this.waitingBuilder,
    this.errorBuilder,
    this.limit = const Optional.absent(),
    this.author = const Optional.absent(),
    this.filters = const Optional.absent(),
  }) : snapshotBuilder = null;

  /// Creates a query widget whose builder handles every snapshot state.
  const MessagesListQuery.snapshot({
    super.key,
    required this.snapshotBuilder,
    this.client,
    this.limit = const Optional.absent(),
    this.author = const Optional.absent(),
    this.filters = const Optional.absent(),
  }) : builder = null,
       waitingBuilder = null,
       errorBuilder = null;

  /// Builds the UI when query data is available.
  final Widget Function(BuildContext, List<ListResultItem>)? builder;

  /// Builds the UI from every query snapshot in snapshot mode.
  final Widget Function(
    BuildContext,
    ConvexQuerySnapshot<List<ListResultItem>>,
  )?
  snapshotBuilder;

  /// Overrides the initial loading UI.
  final WidgetBuilder? waitingBuilder;

  /// Overrides the error UI.
  final Widget Function(BuildContext, Object)? errorBuilder;

  /// Optional runtime client override.
  final ConvexRuntimeClient? client;

  final Optional<double> limit;
  final Optional<String?> author;
  final Optional<ListArgsFilters> filters;

  @override
  Widget build(BuildContext context) {
    final buildSnapshot = snapshotBuilder;
    if (buildSnapshot != null) {
      return ConvexTypedQuery<ListArgs, List<ListResultItem>>.snapshot(
        query: listQueryReference,
        args: (limit: limit, author: author, filters: filters),
        client: client,
        snapshotBuilder: buildSnapshot,
      );
    }
    return ConvexTypedQuery<ListArgs, List<ListResultItem>>(
      query: listQueryReference,
      args: (limit: limit, author: author, filters: filters),
      client: client,
      builder: builder!,
      waitingBuilder: waitingBuilder,
      errorBuilder: errorBuilder,
    );
  }
}

/// Flutter widget for messages:ping.
class MessagesPingQuery extends StatelessWidget {
  /// Creates a typed query widget with default loading and error UI.
  const MessagesPingQuery({
    super.key,
    required this.builder,
    this.client,
    this.waitingBuilder,
    this.errorBuilder,
    this.args = const <String, dynamic>{},
  }) : snapshotBuilder = null;

  /// Creates a query widget whose builder handles every snapshot state.
  const MessagesPingQuery.snapshot({
    super.key,
    required this.snapshotBuilder,
    this.client,
    this.args = const <String, dynamic>{},
  }) : builder = null,
       waitingBuilder = null,
       errorBuilder = null;

  /// Builds the UI when query data is available.
  final Widget Function(BuildContext, dynamic)? builder;

  /// Builds the UI from every query snapshot in snapshot mode.
  final Widget Function(BuildContext, ConvexQuerySnapshot<dynamic>)?
  snapshotBuilder;

  /// Overrides the initial loading UI.
  final WidgetBuilder? waitingBuilder;

  /// Overrides the error UI.
  final Widget Function(BuildContext, Object)? errorBuilder;

  /// Optional runtime client override.
  final ConvexRuntimeClient? client;

  final Map<String, dynamic> args;

  @override
  Widget build(BuildContext context) {
    final buildSnapshot = snapshotBuilder;
    if (buildSnapshot != null) {
      return ConvexTypedQuery<Map<String, dynamic>, dynamic>.snapshot(
        query: pingQueryReference,
        args: args,
        client: client,
        snapshotBuilder: buildSnapshot,
      );
    }
    return ConvexTypedQuery<Map<String, dynamic>, dynamic>(
      query: pingQueryReference,
      args: args,
      client: client,
      builder: builder!,
      waitingBuilder: waitingBuilder,
      errorBuilder: errorBuilder,
    );
  }
}

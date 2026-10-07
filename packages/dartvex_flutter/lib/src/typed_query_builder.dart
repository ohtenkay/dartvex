import 'package:dartvex/dartvex.dart' show ConvexQueryReference;
import 'package:flutter/material.dart';

import 'query_builder.dart';
import 'runtime_client.dart';
import 'snapshot.dart';

/// A query widget whose arguments and result are defined by a generated reference.
class ConvexTypedQuery<Args, Result> extends StatelessWidget {
  /// Creates a typed query subscription.
  const ConvexTypedQuery({
    super.key,
    required this.query,
    required this.args,
    required this.builder,
    this.client,
    this.waitingBuilder,
    this.errorBuilder,
  }) : snapshotBuilder = null;

  /// Creates a query widget whose builder handles every snapshot state.
  const ConvexTypedQuery.snapshot({
    super.key,
    required this.query,
    required this.args,
    required this.snapshotBuilder,
    this.client,
  }) : builder = null,
       waitingBuilder = null,
       errorBuilder = null;

  /// Generated query name and wire codecs.
  final ConvexQueryReference<Args, Result> query;

  /// Typed arguments for the query.
  final Args args;

  /// Builds the UI after a query value arrives, including a valid null value.
  final Widget Function(BuildContext, Result)? builder;

  /// Builds the UI for every query state when using the snapshot constructor.
  final Widget Function(BuildContext, ConvexQuerySnapshot<Result>)?
  snapshotBuilder;

  /// Overrides the initial loading UI.
  final WidgetBuilder? waitingBuilder;

  /// Overrides the error UI.
  final Widget Function(BuildContext, Object)? errorBuilder;

  /// Optional runtime client override.
  final ConvexRuntimeClient? client;

  @override
  Widget build(BuildContext context) => ConvexQuery<Result>(
    query: query.name,
    args: query.encode(args),
    decode: query.decode,
    client: client,
    builder: (context, snapshot) {
      final buildSnapshot = snapshotBuilder;
      if (buildSnapshot != null) return buildSnapshot(context, snapshot);
      if (snapshot.hasError) {
        return (errorBuilder ?? _defaultErrorBuilder)(context, snapshot.error!);
      }
      if (!snapshot.hasData) {
        return (waitingBuilder ?? _defaultWaitingBuilder)(context);
      }
      return builder!(context, snapshot.data as Result);
    },
  );

  static Widget _defaultWaitingBuilder(BuildContext context) =>
      const Center(child: CircularProgressIndicator());

  static Widget _defaultErrorBuilder(BuildContext context, Object error) =>
      Center(child: Text('Error: $error'));
}

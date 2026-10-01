import 'package:dartvex/dartvex.dart' show ConvexQueryReference;
import 'package:flutter/widgets.dart';

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
  });

  /// Generated query name and wire codecs.
  final ConvexQueryReference<Args, Result> query;

  /// Typed arguments for the query.
  final Args args;

  /// Builds the UI from the latest query snapshot.
  final Widget Function(BuildContext, ConvexQuerySnapshot<Result>) builder;

  /// Optional runtime client override.
  final ConvexRuntimeClient? client;

  @override
  Widget build(BuildContext context) => ConvexQuery<Result>(
    query: query.name,
    args: query.encode(args),
    decode: query.decode,
    client: client,
    builder: builder,
  );
}

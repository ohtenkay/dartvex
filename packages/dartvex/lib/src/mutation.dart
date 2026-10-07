/// Arguments for a Convex mutation that takes no fields.
final class NoArgs {
  /// Creates an empty argument value.
  const NoArgs();
}

/// Generated metadata for a typed Convex mutation.
final class ConvexMutationReference<Args, Result> {
  /// Creates a mutation reference with its wire codecs.
  const ConvexMutationReference({
    required this.name,
    required this.encode,
    required this.decode,
  });

  /// Convex function name.
  final String name;

  /// Encodes typed arguments for transport.
  final Map<String, dynamic> Function(Args args) encode;

  /// Decodes the raw mutation result.
  final Result Function(dynamic raw) decode;
}

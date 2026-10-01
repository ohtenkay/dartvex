/// Generated metadata for a typed Convex query.
final class ConvexQueryReference<Args, Result> {
  /// Creates a query reference with its wire codecs.
  const ConvexQueryReference({
    required this.name,
    required this.encode,
    required this.decode,
  });

  /// Convex function name.
  final String name;

  /// Encodes typed arguments for transport.
  final Map<String, dynamic> Function(Args args) encode;

  /// Decodes the raw query result.
  final Result Function(dynamic raw) decode;
}

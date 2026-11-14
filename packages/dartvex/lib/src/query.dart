/// Generated metadata for a typed Convex query.
final class ConvexQueryReference<Args, Result> {
  /// Creates a query reference with its wire codecs.
  const ConvexQueryReference({
    required this.name,
    required this.encode,
    required this.decodeArgs,
    required this.decode,
    required this.encodeResult,
  });

  /// Convex function name.
  final String name;

  /// Encodes typed arguments for transport.
  final Map<String, dynamic> Function(Args args) encode;

  /// Decodes query arguments from the local query store.
  final Args Function(Map<String, dynamic> raw) decodeArgs;

  /// Decodes the raw query result.
  final Result Function(dynamic raw) decode;

  /// Encodes a typed result for an optimistic query overlay.
  final Object? Function(Result value) encodeResult;
}

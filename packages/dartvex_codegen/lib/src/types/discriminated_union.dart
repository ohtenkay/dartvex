import '../generator/naming.dart';
import '../spec/function_spec.dart';

/// A validated object union whose members use a string-literal discriminator.
class DiscriminatedUnion {
  /// Creates a discriminated union description.
  const DiscriminatedUnion({
    required this.discriminator,
    required this.members,
  });

  /// Wire field selecting the concrete union member.
  final String discriminator;

  /// Concrete members in validator order.
  final List<DiscriminatedUnionMember> members;
}

/// One concrete member of a [DiscriminatedUnion].
class DiscriminatedUnionMember {
  /// Creates a discriminated union member.
  const DiscriminatedUnionMember({
    required this.literal,
    required this.className,
    required this.object,
  });

  /// String literal stored in the discriminator field.
  final String literal;

  /// Unprefixed Dart class name derived from [literal].
  final String className;

  /// Full object validator, including the wire discriminator field.
  final ConvexObjectType object;
}

/// Recognizes a union using [discriminator] as a required string literal.
DiscriminatedUnion? inspectDiscriminatedUnion(
  ConvexType type, {
  required String discriminator,
  Naming naming = const Naming(),
}) {
  if (type is! ConvexUnionType || type.value.length < 2) {
    return null;
  }

  final members = <DiscriminatedUnionMember>[];
  final literals = <String>{};
  final classNames = <String, String>{};
  for (final unionMember in type.value) {
    if (unionMember is! ConvexObjectType) {
      return null;
    }
    final field = unionMember.value[discriminator];
    if (field == null || field.optional) {
      return null;
    }
    final fieldType = field.fieldType;
    if (fieldType is! ConvexLiteralType || fieldType.value is! String) {
      return null;
    }
    final literal = fieldType.value! as String;
    if (!literals.add(literal)) {
      throw DiscriminatedUnionException(
        'Duplicate discriminator value "$literal".',
      );
    }
    final className = naming.typeName(literal);
    final existingLiteral = classNames[className];
    if (existingLiteral != null) {
      throw DiscriminatedUnionException(
        'Discriminator values "$existingLiteral" and "$literal" both '
        'generate Dart class "$className".',
      );
    }
    classNames[className] = literal;
    members.add(
      DiscriminatedUnionMember(
        literal: literal,
        className: className,
        object: unionMember,
      ),
    );
  }
  return DiscriminatedUnion(discriminator: discriminator, members: members);
}

/// Raised when a discriminator cannot produce unique Dart subclasses.
class DiscriminatedUnionException implements Exception {
  /// Creates a discriminator error.
  DiscriminatedUnionException(this.message);

  /// Human-readable failure details.
  final String message;

  @override
  String toString() => message;
}

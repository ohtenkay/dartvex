import '../generator/naming.dart';
import '../generator/string_literals.dart';
import '../spec/function_spec.dart';
import 'discriminated_union.dart';
import 'type_identity.dart';

/// Constants associated with union variants, separate from their wire fields.
class UnionMetadata {
  /// Associates a union [validator] with constants keyed by wire variant value.
  const UnionMetadata({required this.validator, required this.variants});

  /// Validator whose structurally identical uses receive these getters.
  final ConvexType validator;

  /// Scalar constants for each string literal or discriminator value.
  final Map<String, Map<String, Object?>> variants;
}

/// A validated getter shared by every variant of a union.
class UnionMetadataProperty {
  /// Creates a getter description.
  const UnionMetadataProperty({
    required this.name,
    required this.annotation,
    required this.values,
  });

  /// Normalized Dart getter name.
  final String name;

  /// Inferred Dart scalar type.
  final String annotation;

  /// Dart constant expressions keyed by wire variant value.
  final Map<String, String> values;
}

/// Validates metadata once and resolves it by structural validator identity.
class UnionMetadataRegistry {
  /// Builds a registry, rejecting incomplete variants and invalid getter names.
  UnionMetadataRegistry(
    List<UnionMetadata> entries, {
    required String discriminator,
    Naming naming = const Naming(),
  }) {
    for (final entry in entries) {
      final validator = _nonNullUnion(entry.validator);
      if (validator is! ConvexUnionType || validator.value.length < 2) {
        throw FormatException('Union metadata requires a union validator.');
      }
      final objectUnion = inspectDiscriminatedUnion(
        validator,
        discriminator: discriminator,
        naming: naming,
      );
      final literals = objectUnion != null
          ? objectUnion.members.map((member) => member.literal).toList()
          : validator.value.map((member) {
              if (member is! ConvexLiteralType || member.value is! String) {
                throw FormatException(
                  'Union metadata requires string literals or a discriminated object union.',
                );
              }
              return member.value! as String;
            }).toList();
      if (literals.toSet().length != literals.length ||
          literals.length != entry.variants.length ||
          !literals.every(entry.variants.containsKey)) {
        throw FormatException(
          'Union metadata variants must match exactly: ${literals.join(', ')}.',
        );
      }
      final fields = entry.variants[literals.first]!.keys.toSet();
      if (!entry.variants.values.every(
        (values) =>
            values.length == fields.length && fields.every(values.containsKey),
      )) {
        throw FormatException(
          'Every metadata variant must define the same properties.',
        );
      }
      final reserved = <String>{
        'hashCode',
        'runtimeType',
        'toString',
        'noSuchMethod',
        if (objectUnion == null) ...[
          'value',
          'values',
          'index',
          'name',
          'fromJson',
        ],
        if (objectUnion != null) ...[
          for (final member in objectUnion.members) ...[
            member.className,
            'is${member.className}',
            for (final field in member.object.value.keys)
              naming.fieldName(field),
          ],
        ],
      };
      final properties = <UnionMetadataProperty>[];
      for (final rawName in fields.toList()..sort()) {
        final name = naming.fieldName(rawName);
        if (!reserved.add(name) || name.startsWith('_')) {
          throw FormatException(
            'Union metadata property "$rawName" collides with "$name".',
          );
        }
        final values = {
          for (final literal in literals)
            literal: entry.variants[literal]![rawName],
        };
        final types = values.values
            .where((value) => value != null)
            .map(
              (value) => switch (value) {
                String() => 'String',
                bool() => 'bool',
                int() => 'int',
                double() when value.isFinite => 'double',
                _ => throw FormatException(
                  'Metadata "$rawName" must contain finite JSON scalars.',
                ),
              },
            )
            .toSet();
        if (types.length > 1 &&
            !types.every((type) => type == 'int' || type == 'double')) {
          throw FormatException(
            'Metadata "$rawName" must have a consistent scalar type.',
          );
        }
        final type = types.isEmpty
            ? 'Object'
            : types.length == 1
            ? types.single
            : 'num';
        final nullable = values.values.any((value) => value == null);
        properties.add(
          UnionMetadataProperty(
            name: name,
            annotation: '$type${nullable ? '?' : ''}',
            values: {
              for (final entry in values.entries)
                entry.key: entry.value is String
                    ? dartSingleQuotedString(entry.value! as String)
                    : '${entry.value}',
            },
          ),
        );
      }
      final identity = convexTypeIdentity(validator);
      if (_properties.containsKey(identity)) {
        throw FormatException(
          'Union metadata is declared more than once for the same validator.',
        );
      }
      _properties[identity] = properties;
    }
  }

  final _properties = <String, List<UnionMetadataProperty>>{};

  /// Returns getters for [validator], including nullable uses of the union.
  List<UnionMetadataProperty> resolve(ConvexType validator) =>
      _properties[convexTypeIdentity(_nonNullUnion(validator))] ?? const [];
}

ConvexType _nonNullUnion(ConvexType type) => type is ConvexUnionType
    ? ConvexUnionType(
        type.value
            .where(
              (member) =>
                  member is! ConvexNullType &&
                  !(member is ConvexLiteralType && member.value == null),
            )
            .toList(),
      )
    : type;

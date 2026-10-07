import '../generator/naming.dart';
import '../spec/function_spec.dart';
import '../spec/schema_spec.dart';
import 'discriminated_union.dart';
import 'type_identity.dart';

/// A shared discriminated union discovered from the Convex schema.
class SharedSchemaType {
  /// Creates shared schema type metadata.
  const SharedSchemaType({
    required this.name,
    required this.fieldName,
    required this.type,
    required this.paths,
  });

  /// Generated sealed base class name.
  final String name;

  /// Raw schema field name establishing semantic identity.
  final String fieldName;

  /// Convex validator represented by this type.
  final ConvexType type;

  /// Schema paths using this field name and structure.
  final List<String> paths;
}

/// Discovers and resolves reusable schema-defined discriminated unions.
class SchemaTypeRegistry {
  SchemaTypeRegistry._({
    required this.types,
    required Map<String, SharedSchemaType> byFieldAndIdentity,
    required Map<String, List<SharedSchemaType>> byIdentity,
  }) : _byFieldAndIdentity = byFieldAndIdentity,
       _byIdentity = byIdentity;

  /// Builds a registry from every nested table field in [schema].
  factory SchemaTypeRegistry.fromSchema(
    SchemaSpec schema, {
    required String discriminator,
    Naming naming = const Naming(),
  }) {
    final byField = <String, SharedSchemaType>{};
    final subtypeOwners = <String, String>{};

    void register(String fieldName, ConvexType type, String schemaPath) {
      final candidate = switch (type) {
        ConvexUnionType(:final value) => ConvexUnionType(
          value.where((member) => !_isNullMember(member)).toList(),
        ),
        _ => type,
      };
      final union = inspectDiscriminatedUnion(
        candidate,
        discriminator: discriminator,
        naming: naming,
      );
      if (union == null) {
        return;
      }
      final identity = convexTypeIdentity(type);
      final existing = byField[fieldName];
      if (existing != null) {
        if (convexTypeIdentity(existing.type) != identity) {
          throw SchemaTypeRegistryException(
            'Schema field "$fieldName" defines incompatible discriminated '
            'unions at ${[...existing.paths, schemaPath].join(', ')}.',
          );
        }
        existing.paths.add(schemaPath);
        return;
      }

      final name = naming.typeName(fieldName);
      for (final member in union.members) {
        final owner = subtypeOwners[member.className];
        if (owner != null && owner != name) {
          throw SchemaTypeRegistryException(
            'Generated subtype "${member.className}" is used by both '
            '"$owner" and "$name". Discriminator subclass names are '
            'global in generated types.dart.',
          );
        }
        subtypeOwners[member.className] = name;
      }
      byField[fieldName] = SharedSchemaType(
        name: name,
        fieldName: fieldName,
        type: type,
        paths: <String>[schemaPath],
      );
    }

    void visit(ConvexType type, String? ownerField, String path) {
      if (ownerField != null) {
        register(ownerField, type, path);
      }
      switch (type) {
        case ConvexObjectType(:final value):
          for (final entry in value.entries) {
            visit(entry.value.fieldType, entry.key, '$path.${entry.key}');
          }
        case ConvexArrayType(:final value):
          visit(value, ownerField, '$path[]');
        case ConvexRecordType(:final values):
          visit(values.fieldType, ownerField, '$path{}');
        case ConvexUnionType(:final value):
          for (var index = 0; index < value.length; index += 1) {
            visit(value[index], null, '$path|$index');
          }
        default:
          break;
      }
    }

    for (final table in schema.tables) {
      visit(table.documentType, null, table.name);
    }

    final types =
        byField.values.toList()
          ..sort((left, right) => left.name.compareTo(right.name));
    final byFieldAndIdentity = <String, SharedSchemaType>{};
    final byIdentity = <String, List<SharedSchemaType>>{};
    for (final type in types) {
      final identity = convexTypeIdentity(type.type);
      byFieldAndIdentity[_fieldIdentity(type.fieldName, identity)] = type;
      (byIdentity[identity] ??= <SharedSchemaType>[]).add(type);
    }
    return SchemaTypeRegistry._(
      types: types,
      byFieldAndIdentity: byFieldAndIdentity,
      byIdentity: byIdentity,
    );
  }

  /// Shared types in deterministic generated-name order.
  final List<SharedSchemaType> types;

  final Map<String, SharedSchemaType> _byFieldAndIdentity;
  final Map<String, List<SharedSchemaType>> _byIdentity;

  /// Resolves [type], preferring its containing raw [fieldName].
  SharedSchemaType? resolve(ConvexType type, {String? fieldName}) {
    final identity = convexTypeIdentity(type);
    if (fieldName != null) {
      return _byFieldAndIdentity[_fieldIdentity(fieldName, identity)];
    }
    final matches = _byIdentity[identity];
    return matches?.length == 1 ? matches!.single : null;
  }

  static String _fieldIdentity(String fieldName, String identity) =>
      '$fieldName\u0000$identity';
}

bool _isNullMember(ConvexType type) =>
    type is ConvexNullType || (type is ConvexLiteralType && type.value == null);

/// Raised when schema naming conventions produce incompatible shared types.
class SchemaTypeRegistryException implements Exception {
  /// Creates a schema type registry error.
  SchemaTypeRegistryException(this.message);

  /// Human-readable failure details.
  final String message;

  @override
  String toString() => message;
}

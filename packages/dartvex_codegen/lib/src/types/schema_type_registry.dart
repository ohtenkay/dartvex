import '../generator/naming.dart';
import '../spec/function_spec.dart';
import '../spec/schema_spec.dart';
import 'discriminated_union.dart';
import 'type_identity.dart';

/// A shared document or discriminated union discovered from the Convex schema.
class SharedSchemaType {
  /// Creates shared schema type metadata.
  const SharedSchemaType({
    required this.name,
    required this.fieldName,
    required this.type,
    required this.paths,
    this.isDocument = false,
  });

  /// Whether this type represents a complete table document.
  final bool isDocument;

  /// Generated record or sealed base class name.
  final String name;

  /// Raw schema field or table name establishing semantic identity.
  final String fieldName;

  /// Convex validator represented by this type.
  final ConvexType type;

  /// Schema paths using this field name and structure.
  final List<String> paths;
}

/// Discovers and resolves reusable documents and schema-defined unions.
class SchemaTypeRegistry {
  SchemaTypeRegistry._({
    required this.types,
    required Map<String, SharedSchemaType> byFieldAndIdentity,
    required Map<String, List<SharedSchemaType>> byIdentity,
    required Map<String, SharedSchemaType> documentsByIdentity,
  }) : _byFieldAndIdentity = byFieldAndIdentity,
       _byIdentity = byIdentity,
       _documentsByIdentity = documentsByIdentity;

  /// Builds a registry from table documents and nested union fields in [schema].
  factory SchemaTypeRegistry.fromSchema(
    SchemaSpec schema, {
    required String discriminator,
    Naming naming = const Naming(),
  }) {
    final byField = <String, SharedSchemaType>{};
    final subtypeOwners = <String, String>{};
    final documents = <SharedSchemaType>[];

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
      final documentType = _documentType(table.documentType, table.name);
      if (documentType != null) {
        documents.add(
          SharedSchemaType(
            name: '${naming.typeName(table.name)}Document',
            fieldName: table.name,
            type: documentType,
            paths: <String>[table.name],
            isDocument: true,
          ),
        );
      }
      visit(table.documentType, null, table.name);
    }

    final types = <SharedSchemaType>[...byField.values, ...documents]
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
      documentsByIdentity: {
        for (final document in documents)
          convexTypeIdentity(document.type): document,
      },
    );
  }

  /// Shared types in deterministic generated-name order.
  final List<SharedSchemaType> types;

  final Map<String, SharedSchemaType> _byFieldAndIdentity;
  final Map<String, List<SharedSchemaType>> _byIdentity;
  final Map<String, SharedSchemaType> _documentsByIdentity;

  /// Resolves complete documents, then named or uniquely matching field unions.
  SharedSchemaType? resolve(ConvexType type, {String? fieldName}) {
    final nonNull =
        type is ConvexUnionType
            ? type.value.where((member) => !_isNullMember(member)).toList()
            : <ConvexType>[type];
    final documentCandidate =
        nonNull.length == 1 ? nonNull.single : ConvexUnionType(nonNull);
    final document =
        _documentsByIdentity[convexTypeIdentity(documentCandidate)];
    if (document != null) return document;
    final identity = convexTypeIdentity(type);
    if (fieldName != null) {
      final named = _byFieldAndIdentity[_fieldIdentity(fieldName, identity)];
      if (named != null) return named;
    }
    final matches = _byIdentity[identity];
    return matches?.length == 1 ? matches!.single : null;
  }

  static String _fieldIdentity(String fieldName, String identity) =>
      '$fieldName\u0000$identity';
}

ConvexType? _documentType(ConvexType type, String tableName) {
  if (type is ConvexObjectType) {
    return ConvexObjectType({
      ...type.value,
      '_id': ConvexField(fieldType: ConvexIdType(tableName), optional: false),
      '_creationTime': const ConvexField(
        fieldType: ConvexNumberType(),
        optional: false,
      ),
    });
  }
  if (type is ConvexUnionType) {
    final members =
        type.value.map((member) => _documentType(member, tableName)).toList();
    if (members.every((member) => member != null)) {
      return ConvexUnionType(members.cast<ConvexType>());
    }
  }
  return null;
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

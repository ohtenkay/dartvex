import 'dart:convert';

import 'spec_parser.dart';
import 'schema_spec.dart';
import '../types/union_metadata.dart';

/// Parses JSON returned by Convex's `SchemaDefinition.export()`.
class SchemaSpecParser {
  /// Creates a schema parser.
  const SchemaSpecParser();

  /// Parses an exported schema JSON string.
  SchemaSpec parseString(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw SpecParserException('schema export root must be a JSON object');
    }
    final rawTables = decoded['tables'];
    if (rawTables is! List<dynamic>) {
      throw SpecParserException('Expected schema "tables" to be a list');
    }

    final warnings = <String>[];
    final tables = <SchemaTableSpec>[];
    for (final rawTable in rawTables) {
      if (rawTable is! Map) {
        throw SpecParserException('Each schema table must be a JSON object');
      }
      final table = rawTable.cast<String, dynamic>();
      final tableName = table['tableName'];
      final documentType = table['documentType'];
      if (tableName is! String) {
        throw SpecParserException('Expected schema tableName to be a string');
      }
      if (documentType is! Map) {
        throw SpecParserException(
          'Expected documentType for table "$tableName" to be an object',
        );
      }
      tables.add(
        SchemaTableSpec(
          name: tableName,
          documentType: const SpecParser().parseTypeMap(
            documentType.cast<String, dynamic>(),
            context: 'schema table "$tableName"',
            warnings: warnings,
          ),
        ),
      );
    }

    final rawMetadata = decoded.containsKey('dartvexUnionMetadata')
        ? decoded['dartvexUnionMetadata']
        : <dynamic>[];
    if (rawMetadata is! List) {
      throw SpecParserException('dartvexUnionMetadata must be a list');
    }
    final metadata = <UnionMetadata>[];
    for (final entry in rawMetadata) {
      if (entry is! Map ||
          entry['validator'] is! Map ||
          entry['variants'] is! Map) {
        throw SpecParserException(
          'Union metadata requires validator and variants objects',
        );
      }
      final variants = <String, Map<String, Object?>>{};
      for (final variant in (entry['variants'] as Map).entries) {
        if (variant.key is! String || variant.value is! Map) {
          throw SpecParserException(
            'Union metadata variants must be objects keyed by string values',
          );
        }
        variants[variant.key as String] = Map<String, Object?>.from(
          variant.value as Map,
        );
      }
      metadata.add(
        UnionMetadata(
          validator: const SpecParser().parseTypeMap(
            (entry['validator'] as Map).cast<String, dynamic>(),
            context: 'union metadata',
            warnings: warnings,
          ),
          variants: variants,
        ),
      );
    }
    return SchemaSpec(
      tables: tables,
      warnings: warnings,
      unionMetadata: metadata,
    );
  }
}

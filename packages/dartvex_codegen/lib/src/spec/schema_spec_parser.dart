import 'dart:convert';

import 'spec_parser.dart';
import 'schema_spec.dart';

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

    return SchemaSpec(tables: tables, warnings: warnings);
  }
}

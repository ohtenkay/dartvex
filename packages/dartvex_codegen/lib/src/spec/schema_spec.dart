import 'function_spec.dart';

/// Parsed representation of a Convex schema export.
class SchemaSpec {
  /// Creates a schema specification.
  const SchemaSpec({required this.tables, this.warnings = const <String>[]});

  /// Tables declared by the schema.
  final List<SchemaTableSpec> tables;

  /// Non-fatal diagnostics encountered while parsing the schema.
  final List<String> warnings;
}

/// A table and its document validator from a Convex schema export.
class SchemaTableSpec {
  /// Creates a table specification.
  const SchemaTableSpec({required this.name, required this.documentType});

  /// Convex table name.
  final String name;

  /// Validator for user-defined document fields.
  final ConvexType documentType;
}

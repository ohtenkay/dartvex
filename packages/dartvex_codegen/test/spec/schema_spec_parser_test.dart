import 'package:dartvex_codegen/dartvex_codegen.dart';
import 'package:test/test.dart';

void main() {
  test('parses exported Convex table document validators', () {
    final schema = const SchemaSpecParser().parseString('''
{
  "tables": [
    {
      "tableName": "drinks",
      "documentType": {
        "type": "object",
        "value": {
          "name": {
            "fieldType": {"type": "string"},
            "optional": false
          }
        }
      }
    }
  ],
  "schemaValidation": true
}
''');

    expect(schema.tables, hasLength(1));
    expect(schema.tables.single.name, 'drinks');
    final documentType = schema.tables.single.documentType;
    expect(documentType, isA<ConvexObjectType>());
    expect(
      (documentType as ConvexObjectType).value['name']?.fieldType,
      isA<ConvexStringType>(),
    );
  });
}

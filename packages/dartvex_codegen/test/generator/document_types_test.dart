import 'dart:io';

import 'package:dartvex_codegen/dartvex_codegen.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

ConvexField field(ConvexType type) =>
    ConvexField(fieldType: type, optional: false);

ConvexObjectType object(Map<String, ConvexType> fields) =>
    ConvexObjectType(fields.map((key, type) => MapEntry(key, field(type))));

FunctionSpec query(String name, ConvexType returns) => FunctionSpec(
  functionType: 'Query',
  args: object({}),
  returns: returns,
  identifier: 'session.ts:$name',
  visibility: const Visibility('public'),
);

void main() {
  final common = {'name': const ConvexStringType()};
  final sessionFields = ConvexUnionType([
    for (final kind in ['session', 'party'])
      object({...common, 'kind': ConvexLiteralType(kind)}),
  ]);
  final document = ConvexUnionType([
    for (final variant in sessionFields.value.cast<ConvexObjectType>())
      ConvexObjectType({
        ...variant.value,
        '_id': field(const ConvexIdType('session')),
        '_creationTime': field(const ConvexNumberType()),
      }),
  ]);
  final nullableDocument = ConvexUnionType([
    ...document.value,
    const ConvexNullType(),
  ]);
  final drinkFields = object({'name': const ConvexStringType()});
  final drinkDocument = object({
    'name': const ConvexStringType(),
    '_id': const ConvexIdType('drink'),
    '_creationTime': const ConvexNumberType(),
  });
  final role = ConvexUnionType([
    for (final kind in ['member', 'admin'])
      object({'kind': ConvexLiteralType(kind)}),
  ]);
  final schema = SchemaSpec(
    tables: [
      SchemaTableSpec(name: 'session', documentType: sessionFields),
      SchemaTableSpec(name: 'drink', documentType: drinkFields),
      SchemaTableSpec(
        name: 'sessionMember',
        documentType: object({'sessionMemberRole': role}),
      ),
    ],
  );
  final spec = FunctionsSpec(
    url: 'https://example.com',
    functions: [
      FunctionSpec(
        functionType: 'Query',
        identifier: 'session.ts:setRole',
        visibility: const Visibility('public'),
        args: object({'role': ConvexUnionType(role.value.reversed.toList())}),
        returns: const ConvexNullType(),
      ),
      query('get', document),
      query('listCurrent', ConvexArrayType(document)),
      query('find', nullableDocument),
      query('invitations', ConvexArrayType(object({'invitation': document}))),
      query('drink', drinkDocument),
      query(
        'maybeDrink',
        ConvexUnionType([drinkDocument, const ConvexNullType()]),
      ),
      query('projection', object({'_id': const ConvexIdType('drink')})),
      query(
        'enriched',
        ConvexObjectType({
          ...drinkDocument.value,
          'extra': field(const ConvexStringType()),
        }),
      ),
      query(
        'reordered',
        ConvexUnionType([
          for (final variant
              in document.value.reversed.cast<ConvexObjectType>())
            ConvexObjectType(
              Map.fromEntries(variant.value.entries.toList().reversed),
            ),
        ]),
      ),
    ],
  );

  test('shares document records and root unions across endpoint shapes', () {
    final output = DartGenerator(schema: schema).generate(spec);
    final types = output.files['types.dart']!;
    final module = output.files['modules/session.dart']!;
    expect(types, contains('sealed class SessionDocument'));
    expect(types, contains('final class Session extends SessionDocument'));
    expect(types, contains('final class Party extends SessionDocument'));
    expect(types, contains('typedef DrinkDocument'));
    expect(module, contains('required SessionMemberRole role'));
    expect(module, isNot(contains('sealed class SetRoleArgsRole')));
    expect(module, contains('Future<SessionDocument> get'));
    expect(module, contains('Future<List<SessionDocument>> listCurrent'));
    expect(module, contains('Future<SessionDocument?> find'));
    expect(module, contains('SessionDocument invitation'));
    expect(module, contains('Future<DrinkDocument> drink'));
    expect(module, contains('Future<DrinkDocument?> maybeDrink'));
    expect(module, contains('Future<ProjectionResult> projection'));
    expect(module, contains('Future<EnrichedResult> enriched'));
    expect(module, isNot(contains('sealed class GetTypeResult')));
    expect(module, isNot(contains('final class Session')));
    expect(types, contains('SessionId id'));
    expect(types, contains('double creationTime'));
    expect(output.files['schema.dart'], contains('class DrinkId'));
  });

  test(
    'document codecs compile and round-trip IDs, timestamps and variants',
    () async {
      final output = DartGenerator(schema: schema).generate(spec);
      final directory = await Directory.systemTemp.createTemp(
        'dartvex_documents_',
      );
      addTearDown(() => directory.delete(recursive: true));
      for (final entry in output.files.entries) {
        final file = File(path.join(directory.path, entry.key));
        await file.parent.create(recursive: true);
        await file.writeAsString(entry.value);
      }
      final script = File(path.join(directory.path, 'check.dart'));
      await script.writeAsString('''
import 'modules/session.dart';
void check(bool condition) { if (!condition) throw StateError('Check failed'); }
void main() {
  for (final kind in ['session', 'party']) {
    final raw = {'_id': 'session-id', '_creationTime': 123.0, 'name': 'Evening', 'kind': kind};
    final decoded = getValueQueryReference.decode(raw);
    final encoded = getValueQueryReference.encodeResult!(decoded) as Map;
    check(encoded.length == raw.length && raw.keys.every((key) => encoded[key] == raw[key]));
    check(findQueryReference.decode(raw).runtimeType == decoded.runtimeType);
    check(listCurrentQueryReference.decode([raw]).single.runtimeType == decoded.runtimeType);
    check(invitationsQueryReference.decode([{'invitation': raw}]).single.invitation.runtimeType == decoded.runtimeType);
    check(reorderedQueryReference.decode(raw).runtimeType == decoded.runtimeType);
  }
  final roleArgs = setRoleQueryReference.decodeArgs({'role': {'kind': 'admin'}});
  check(roleArgs.role.runtimeType.toString() == 'Admin');
  check(((setRoleQueryReference.encode(roleArgs) as Map)['role'] as Map)['kind'] == 'admin');
  check(findQueryReference.decode(null) == null);
  check(findQueryReference.encodeResult!(null) == null);
  final drink = drinkQueryReference.decode({'_id': 'drink-id', '_creationTime': 456.0, 'name': 'Beer'});
  check(drink.id.value == 'drink-id' && drink.creationTime == 456.0);
  check((drinkQueryReference.encodeResult!(drink) as Map)['_id'] == 'drink-id');
  check(maybeDrinkQueryReference.decode(null) == null);
  try {
    getValueQueryReference.decode({'_id': 'session-id', '_creationTime': 123.0, 'name': 'Evening', 'kind': 'unknown'});
    throw StateError('Expected invalid discriminator rejection');
  } on FormatException { }
}
''');
      final result = await Process.run(Platform.resolvedExecutable, [
        '--packages=${path.absolute('.dart_tool/package_config.json')}',
        script.path,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );

  test(
    'document resolution ignores nesting names and preserves projections',
    () {
      final registry = SchemaTypeRegistry.fromSchema(
        schema,
        discriminator: 'kind',
      );
      expect(
        registry.resolve(document, fieldName: 'unrelated')?.name,
        'SessionDocument',
      );
      expect(registry.resolve(nullableDocument)?.name, 'SessionDocument');
      expect(registry.resolve(drinkDocument)?.name, 'DrinkDocument');
      expect(registry.resolve(drinkFields), isNull);
      expect(
        registry.resolve(object({'_id': const ConvexIdType('drink')})),
        isNull,
      );
    },
  );

  test('different root unions claiming the same subclass still fail', () {
    expect(
      () => DartGenerator(
        schema: SchemaSpec(
          tables: [
            ...schema.tables,
            SchemaTableSpec(name: 'otherSession', documentType: sessionFields),
          ],
        ),
      ).generate(spec),
      throwsA(isA<TypeMapperException>()),
    );
  });
}

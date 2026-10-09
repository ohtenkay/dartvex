import 'dart:io';

import 'package:dartvex_codegen/dartvex_codegen.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

ConvexField field(ConvexType type, {bool optional = false}) =>
    ConvexField(fieldType: type, optional: optional);

FunctionsSpec spec(ConvexType union) => FunctionsSpec(
  url: 'https://example.com',
  functions: [
    FunctionSpec(
      functionType: 'Query',
      identifier: 'states.ts:get',
      visibility: const Visibility('public'),
      args: const ConvexObjectType({}),
      returns: union,
    ),
  ],
);

void main() {
  final phase = const ConvexUnionType([
    ConvexLiteralType('early'),
    ConvexLiteralType('late'),
  ]);
  final union = ConvexUnionType([
    for (final kind in ['alpha', 'beta'])
      ConvexObjectType({
        'kind': field(ConvexLiteralType(kind)),
        'name': field(const ConvexStringType()),
        'endedAt': field(
          const ConvexUnionType([ConvexNumberType(), ConvexNullType()]),
        ),
        'note': field(const ConvexStringType(), optional: true),
        'phase': field(
          kind == 'alpha'
              ? phase
              : ConvexUnionType(phase.value.reversed.toList()),
        ),
        'details': field(
          ConvexObjectType({'count': field(const ConvexNumberType())}),
        ),
        'different': field(
          kind == 'alpha' ? const ConvexStringType() : const ConvexNumberType(),
        ),
        'presence': field(const ConvexStringType(), optional: kind == 'alpha'),
        if (kind == 'alpha') 'alphaOnly': field(const ConvexBooleanType()),
      }),
  ]);

  test('generates common getters and predicates for endpoint-local unions', () {
    final output = DartGenerator().generate(spec(union));
    final module = output.files['modules/states.dart']!;
    final base = module.substring(
      module.indexOf('sealed class GetTypeResult'),
      module.indexOf('final class Alpha'),
    );
    expect(base, contains('String get name;'));
    expect(base, contains('double? get endedAt;'));
    expect(base, contains('Optional<String> get note;'));
    expect(base, contains('GetTypeResultPhase get phase;'));
    expect(base, contains('GetTypeResultDetails get details;'));
    expect(base, contains('bool get isAlpha => this is Alpha;'));
    expect(base, contains('bool get isBeta => this is Beta;'));
    for (final name in ['different', 'presence', 'alphaOnly', 'kind']) {
      expect(base, isNot(contains('get $name')));
    }
    expect(module, isNot(contains('AlphaPhase')));
    expect(module, isNot(contains('BetaPhase')));
  });

  test(
    'compiled getters preserve optionality and predicates identify each variant',
    () async {
      final output = DartGenerator().generate(spec(union));
      final directory = await Directory.systemTemp.createTemp(
        'dartvex_accessors_',
      );
      addTearDown(() => directory.delete(recursive: true));
      for (final entry in output.files.entries) {
        final file = File(path.join(directory.path, entry.key));
        await file.parent.create(recursive: true);
        await file.writeAsString(entry.value);
      }
      final script = File(path.join(directory.path, 'check.dart'));
      await script.writeAsString('''
import 'modules/states.dart';
void check(bool value) { if (!value) throw StateError('Check failed'); }
void main() {
  for (final kind in ['alpha', 'beta']) {
    final raw = <String, dynamic>{
      'kind': kind, 'name': 'Name', 'endedAt': null, 'phase': 'early',
      'details': {'count': 2.0}, 'different': kind == 'alpha' ? 'Text' : 3.0,
      'presence': 'present', if (kind == 'alpha') 'alphaOnly': true,
    };
    final GetTypeResult value = getValueQueryReference.decode(raw);
    final String name = value.name;
    final double? end = value.endedAt;
    final GetTypeResultPhase phase = value.phase;
    check(name == 'Name' && end == null && phase.value == 'early');
    check(value.details.count == 2.0 && !value.note.isDefined);
    check(value.isAlpha == (kind == 'alpha') && value.isBeta == (kind == 'beta'));
    final encoded = getValueQueryReference.encodeResult(value) as Map;
    check(!encoded.containsKey('note') && encoded['kind'] == kind);
    raw['note'] = 'Note';
    check(getValueQueryReference.decode(raw).note.value == 'Note');
    if (value is Alpha) check(value.alphaOnly);
  }
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
    'rejects predicates colliding with fields in any variant after normalization',
    () {
      for (final name in ['isAlpha', 'is-alpha']) {
        final collision = ConvexUnionType([
          ConvexObjectType({'kind': field(const ConvexLiteralType('alpha'))}),
          ConvexObjectType({
            'kind': field(const ConvexLiteralType('beta')),
            name: field(const ConvexBooleanType()),
          }),
        ]);
        expect(
          () => DartGenerator().generate(spec(collision)),
          throwsA(
            isA<TypeMapperException>().having(
              (error) => error.message,
              'message',
              contains('predicate "isAlpha" collides'),
            ),
          ),
        );
      }
    },
  );

  test('supports custom discriminators and normalized variant names', () {
    final custom = ConvexUnionType([
      for (final kind in ['in-progress', 'done'])
        ConvexObjectType({'state': field(ConvexLiteralType(kind))}),
    ]);
    final output = DartGenerator(discriminator: 'state').generate(spec(custom));
    expect(
      output.files['modules/states.dart'],
      contains('bool get isInProgress => this is InProgress;'),
    );
    expect(
      output.files['modules/states.dart'],
      contains('bool get isDone => this is Done;'),
    );
  });
}

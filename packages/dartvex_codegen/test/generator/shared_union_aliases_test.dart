import 'dart:io';

import 'package:dartvex_codegen/dartvex_codegen.dart';
import 'package:path/path.dart' as path;
import 'package:test/test.dart';

ConvexField field(ConvexType type) =>
    ConvexField(fieldType: type, optional: false);

void main() {
  final slot = ConvexUnionType([
    ConvexObjectType({
      'kind': field(const ConvexLiteralType('team')),
      'teamId': field(const ConvexIdType('teams')),
    }),
    for (final kind in ['winner', 'loser'])
      ConvexObjectType({
        'kind': field(ConvexLiteralType(kind)),
        'matchId': field(const ConvexIdType('matches')),
      }),
    ConvexObjectType({'kind': field(const ConvexLiteralType('bye'))}),
  ]);

  for (final nullable in [false, true]) {
    test(
      'shared slot codecs compile and round-trip (nullable: $nullable)',
      () async {
        final union = ConvexUnionType([
          ...slot.value,
          if (nullable) const ConvexNullType(),
        ]);
        final reordered = ConvexUnionType([
          for (final member in union.value.reversed)
            if (member is ConvexObjectType)
              ConvexObjectType(
                Map.fromEntries(member.value.entries.toList().reversed),
              )
            else
              member,
        ]);
        final schema = SchemaSpec(
          tables: [
            SchemaTableSpec(
              name: 'matches',
              documentType: ConvexObjectType({
                'slotA': field(union),
                'slotB': field(reordered),
              }),
            ),
          ],
        );
        final output = DartGenerator(schema: schema).generate(
          FunctionsSpec(
            url: 'https://example.com',
            functions: [
              FunctionSpec(
                functionType: 'Query',
                identifier: 'matches.ts:inspect',
                visibility: const Visibility('public'),
                args: ConvexObjectType({'slotB': field(reordered)}),
                returns: ConvexObjectType({
                  'slotA': field(union),
                  'slotB': field(reordered),
                  'endpointSlot': field(union),
                }),
              ),
            ],
          ),
        );
        final types = output.files['types.dart']!;
        expect(RegExp('sealed class SlotA').allMatches(types), hasLength(1));
        expect(types, isNot(contains('sealed class SlotB')));
        for (final name in ['Team', 'Winner', 'Loser', 'Bye']) {
          expect(
            RegExp('final class $name extends SlotA').allMatches(types),
            hasLength(1),
          );
        }
        final module = output.files['modules/matches.dart']!;
        expect(module, contains('required SlotA${nullable ? '?' : ''} slotB'));
        expect(module, contains('SlotA${nullable ? '?' : ''} endpointSlot'));

        final directory = await Directory.systemTemp.createTemp(
          'dartvex_shared_slots_',
        );
        addTearDown(() => directory.delete(recursive: true));
        for (final entry in output.files.entries) {
          final file = File(path.join(directory.path, entry.key));
          await file.parent.create(recursive: true);
          await file.writeAsString(entry.value);
        }
        final script = File(path.join(directory.path, 'check.dart'));
        await script.writeAsString('''
import 'dart:convert';
import 'modules/matches.dart';
import 'types.dart';
void check(bool value) { if (!value) throw StateError('Check failed'); }
void main() {
  final cases = [
    {'kind': 'team', 'teamId': 'team-1'},
    {'kind': 'winner', 'matchId': 'match-1'},
    {'kind': 'loser', 'matchId': 'match-2'},
    {'kind': 'bye'},
    ${nullable ? 'null,' : ''}
  ];
  for (final raw in cases) {
    final value = inspectQueryReference.decode({'slotA': raw, 'slotB': raw, 'endpointSlot': raw});
    final SlotA${nullable ? '?' : ''} a = value.slotA;
    final SlotA${nullable ? '?' : ''} b = value.slotB;
    check(a.runtimeType == b.runtimeType);
    check(value.endpointSlot.runtimeType == a.runtimeType);
    final encoded = inspectQueryReference.encodeResult!(value) as Map;
    for (final key in ['slotA', 'slotB', 'endpointSlot']) {
      check(jsonEncode(encoded[key]) == jsonEncode(raw));
    }
    final args = inspectQueryReference.decodeArgs({'slotB': raw});
    check(args.slotB.runtimeType == a.runtimeType);
    check(jsonEncode((inspectQueryReference.encode(args) as Map)['slotB']) == jsonEncode(raw));
  }
}
''');
        final result = await Process.run(Platform.resolvedExecutable, [
          '--packages=${path.absolute('.dart_tool/package_config.json')}',
          script.path,
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      },
    );
  }
}

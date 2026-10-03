/// Regenerates golden files from the current generator output.
///
/// Run: dart test/update_goldens.dart
library;

import 'dart:io';

import 'package:dartvex_codegen/dartvex_codegen.dart';
import 'package:path/path.dart' as path;

void main() async {
  final fixture =
      await File(
        path.join('test', 'fixtures', 'function_spec.json'),
      ).readAsString();
  final spec = const SpecParser().parseString(fixture);
  final output = DartGenerator().generate(spec);

  final widgetOutput = DartGenerator(
    generateFlutterWidgets: true,
  ).generate(spec);
  final widgetFile = File(
    path.join('test', 'goldens', 'sample', 'widgets', 'messages.dart'),
  );
  await widgetFile.parent.create(recursive: true);
  await widgetFile.writeAsString(widgetOutput.files['widgets/messages.dart']!);

  for (final entry in output.files.entries) {
    final file = File(path.join('test', 'goldens', 'sample', entry.key));
    await file.parent.create(recursive: true);
    await file.writeAsString(entry.value);
    print('Updated ${entry.key}');
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../spec/spec_json.dart';

/// Thrown when the external Convex CLI cannot be executed successfully.
class ProcessRunnerException implements Exception {
  /// Creates a process runner failure with optional captured output.
  ProcessRunnerException(
    this.message, {
    this.stdout,
    this.stderr,
    this.exitCode,
  });

  /// Maximum number of captured output lines included by [toString].
  static const int outputTailLines = 10;

  /// Human-readable failure details.
  final String message;

  /// Captured standard output, when available.
  final String? stdout;

  /// Captured standard error, when available.
  final String? stderr;

  /// The exit code of the failed process, when it ran.
  final int? exitCode;

  /// Returns [message] followed by the last [outputTailLines] lines of the
  /// captured stderr (or stdout when stderr is empty), so the real Convex CLI
  /// error (for example `No CONVEX_DEPLOYMENT set`) reaches the user.
  @override
  String toString() {
    final stderrText = stderr?.trim() ?? '';
    final output = stderrText.isNotEmpty ? stderrText : (stdout?.trim() ?? '');
    if (output.isEmpty) {
      return message;
    }
    final lines = output.split(RegExp(r'\r?\n'));
    final truncated = lines.length > outputTailLines;
    final tail =
        truncated ? lines.sublist(lines.length - outputTailLines) : lines;
    final buffer =
        StringBuffer(message)
          ..writeln()
          ..write(tail.map((line) => '  $line').join('\n'));
    if (truncated) {
      buffer
        ..writeln()
        ..write('  (output truncated; rerun with --verbose for the full log)');
    }
    return buffer.toString();
  }
}

/// Abstraction for obtaining a Convex function spec from an external process.
abstract class ProcessRunner {
  /// Creates a process runner.
  ProcessRunner();

  /// Runs the function-spec command in [projectDirectory].
  Future<String> runFunctionSpec({
    required String projectDirectory,
    required bool verbose,
  });
}

/// Optional process capability for exporting a local Convex schema.
abstract interface class SchemaProcessRunner {
  /// Exports the local Convex schema in [projectDirectory], when present.
  Future<String?> runSchemaSpec({
    required String projectDirectory,
    required bool verbose,
  });
}

/// Default [ProcessRunner] that shells out to the Convex CLI.
class SystemProcessRunner implements ProcessRunner, SchemaProcessRunner {
  /// Creates a system-backed process runner.
  const SystemProcessRunner();

  /// Candidate commands tried when invoking `convex function-spec`.
  static const List<List<String>> _candidates = <List<String>>[
    <String>['convex', 'function-spec'],
    <String>['npx', 'convex', 'function-spec'],
    <String>['pnpm', 'exec', 'convex', 'function-spec'],
    <String>['bunx', 'convex', 'function-spec'],
    <String>['yarn', 'convex', 'function-spec'],
  ];

  static const List<List<String>> _esbuildCandidates = <List<String>>[
    <String>['npx', '--no-install', 'esbuild'],
    <String>['pnpm', 'exec', 'esbuild'],
    <String>['bunx', 'esbuild'],
    <String>['yarn', 'esbuild'],
  ];

  @override
  /// Executes `convex function-spec` using the first available CLI candidate.
  Future<String> runFunctionSpec({
    required String projectDirectory,
    required bool verbose,
  }) async {
    ProcessRunnerException? lastFailure;
    for (final candidate in _candidates) {
      final executable = candidate.first;
      final arguments = candidate.sublist(1);
      ProcessResult result;
      try {
        result = await Process.run(
          executable,
          arguments,
          workingDirectory: projectDirectory,
          runInShell: true,
        );
      } on ProcessException catch (error) {
        lastFailure = ProcessRunnerException(
          error.message,
          stderr: error.message,
        );
        continue;
      }

      final stdoutText = '${result.stdout}'.trim();
      final stderrText = '${result.stderr}'.trim();
      if (result.exitCode == 0) {
        return extractFunctionSpecJson(stdoutText);
      }
      if (verbose) {
        stdout.writeln(stdoutText);
        stderr.writeln(stderrText);
      }
      if (looksLikeMissingExecutable(result.exitCode, stderrText)) {
        lastFailure = ProcessRunnerException(
          '${candidate.join(' ')} is not available',
          stdout: stdoutText,
          stderr: stderrText,
          exitCode: result.exitCode,
        );
        continue;
      }
      throw ProcessRunnerException(
        'convex function-spec failed in $projectDirectory '
        '(`${candidate.join(' ')}` exited with code ${result.exitCode}):',
        stdout: stdoutText,
        stderr: stderrText,
        exitCode: result.exitCode,
      );
    }
    throw ProcessRunnerException(
      'Unable to run "convex function-spec". Install the Convex CLI or use '
      '--spec-file.',
      stderr: lastFailure?.stderr,
      exitCode: lastFailure?.exitCode,
    );
  }

  @override
  Future<String?> runSchemaSpec({
    required String projectDirectory,
    required bool verbose,
  }) async {
    final resolvedSchema = _resolveSchemaFile(projectDirectory);
    if (resolvedSchema == null) {
      return null;
    }

    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'dartvex_schema_',
    );
    try {
      final entrypoint = File(path.join(temporaryDirectory.path, 'schema.mjs'));
      final bundle = path.join(temporaryDirectory.path, 'schema.cjs');
      await entrypoint.writeAsString(
        'import schema, * as module from ${jsonEncode(resolvedSchema)};\n'
        'const exported = JSON.parse(schema.export());\n'
        'if (module.dartvexUnionMetadata !== undefined) {\n'
        '  if (!Array.isArray(module.dartvexUnionMetadata)) {\n'
        '    throw new Error("dartvexUnionMetadata must be an array");\n'
        '  }\n'
        '  exported.dartvexUnionMetadata = module.dartvexUnionMetadata.map(\n'
        '    ({validator, variants}) => {\n'
        '      if (!validator || !variants || typeof variants !== "object" || Array.isArray(variants)) {\n'
        '        throw new Error("Union metadata requires validator and variants objects");\n'
        '      }\n'
        '      for (const properties of Object.values(variants)) {\n'
        '        if (!properties || typeof properties !== "object" || Array.isArray(properties)) {\n'
        '          throw new Error("Union metadata variants must be objects");\n'
        '        }\n'
        '        for (const value of Object.values(properties)) {\n'
        '          if (value !== null && !["string", "boolean", "number"].includes(typeof value) ||\n'
        '              typeof value === "number" && !Number.isFinite(value)) {\n'
        '            throw new Error("Union metadata values must be finite JSON scalars");\n'
        '          }\n'
        '        }\n'
        '      }\n'
        '      return {validator: validator.json, variants};\n'
        '    },\n'
        '  );\n'
        '}\n'
        'process.stdout.write(JSON.stringify(exported));\n',
      );

      ProcessRunnerException? lastFailure;
      var bundled = false;
      for (final candidate in _esbuildCandidates) {
        final result = await _runCandidate(candidate.first, <String>[
          ...candidate.sublist(1),
          entrypoint.path,
          '--bundle',
          '--platform=node',
          '--format=cjs',
          '--outfile=$bundle',
        ], workingDirectory: projectDirectory);
        if (result == null) {
          continue;
        }
        final stderrText = '${result.stderr}'.trim();
        if (result.exitCode == 0) {
          bundled = true;
          break;
        }
        if (verbose) {
          stdout.writeln('${result.stdout}'.trim());
          stderr.writeln(stderrText);
        }
        if (looksLikeMissingExecutable(result.exitCode, stderrText)) {
          lastFailure = ProcessRunnerException(stderrText);
          continue;
        }
        throw ProcessRunnerException(
          'Failed to bundle Convex schema $resolvedSchema',
          stdout: '${result.stdout}'.trim(),
          stderr: stderrText,
        );
      }
      if (!bundled) {
        throw ProcessRunnerException(
          'Unable to run esbuild while loading $resolvedSchema. Install '
          'esbuild or generate with --spec-file without schema sharing.',
          stderr: lastFailure?.stderr,
        );
      }

      final result = await Process.run(
        'node',
        <String>[bundle],
        workingDirectory: projectDirectory,
        runInShell: true,
      );
      final stdoutText = '${result.stdout}'.trim();
      final stderrText = '${result.stderr}'.trim();
      if (result.exitCode != 0) {
        throw ProcessRunnerException(
          'Failed to evaluate Convex schema $resolvedSchema',
          stdout: stdoutText,
          stderr: stderrText,
        );
      }
      return extractSchemaSpecJson(stdoutText);
    } finally {
      await temporaryDirectory.delete(recursive: true);
    }
  }

  String? _resolveSchemaFile(String projectDirectory) {
    var functionsDirectory = 'convex';
    final convexConfig = File(path.join(projectDirectory, 'convex.json'));
    if (convexConfig.existsSync()) {
      final decoded = jsonDecode(convexConfig.readAsStringSync());
      if (decoded is Map<String, dynamic> && decoded['functions'] is String) {
        functionsDirectory = decoded['functions'] as String;
      }
    }
    for (final filename in const <String>['schema.ts', 'schema.js']) {
      final candidate = path.join(
        projectDirectory,
        functionsDirectory,
        filename,
      );
      if (File(candidate).existsSync()) {
        return path.normalize(path.absolute(candidate));
      }
    }
    return null;
  }

  Future<ProcessResult?> _runCandidate(
    String executable,
    List<String> arguments, {
    required String workingDirectory,
  }) async {
    try {
      return await Process.run(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        runInShell: true,
      );
    } on ProcessException {
      return null;
    }
  }
}

/// Whether a failed candidate run means the CLI itself is missing, so the
/// next package runner should be tried.
///
/// Only shell "command not found" exit codes (127 on POSIX shells, 9009 for
/// `cmd.exe`) and the package runners' own "no such executable" messages
/// count. Real Convex CLI failures that merely contain "not found" (such as
/// `Deployment "x" not found`) are reported instead of being retried.
bool looksLikeMissingExecutable(int exitCode, String stderrText) {
  if (exitCode == 127 || exitCode == 9009) {
    return true;
  }
  final lowered = stderrText.toLowerCase();
  return lowered.contains('command not found') ||
      lowered.contains('is not recognized as an internal or external') ||
      lowered.contains('command "convex" not found') ||
      lowered.contains('could not determine executable to run');
}

/// Extracts the first balanced Convex function spec JSON object from stdout.
String extractFunctionSpecJson(String stdoutText) {
  if (stdoutText.isEmpty) {
    throw ProcessRunnerException('convex function-spec produced no output.');
  }
  if (!stdoutText.contains('{')) {
    throw ProcessRunnerException(
      'convex function-spec did not emit valid JSON.',
      stdout: stdoutText,
    );
  }
  final scan = scanFunctionSpecJson(stdoutText);
  final json = scan.json;
  if (json != null) {
    return json;
  }
  throw ProcessRunnerException(
    scan.foundJsonObject
        ? 'convex function-spec did not emit a Convex function spec JSON '
            'object.'
        : scan.lastError == null
        ? 'convex function-spec did not emit a complete JSON object.'
        : 'convex function-spec output contains invalid JSON: '
            '${scan.lastError}',
    stdout: stdoutText,
  );
}

/// Extracts an exported Convex schema JSON object from process output.
String extractSchemaSpecJson(String stdoutText) {
  return _extractJsonObject(
    stdoutText,
    description: 'Convex schema export',
    matches: (object) => object['tables'] is List<dynamic>,
  );
}

String _extractJsonObject(
  String stdoutText, {
  required String description,
  required bool Function(Map<String, dynamic> object) matches,
}) {
  if (stdoutText.isEmpty) {
    throw ProcessRunnerException('$description produced no output.');
  }
  var searchStart = stdoutText.indexOf('{');
  while (searchStart != -1) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = searchStart; index < stdoutText.length; index += 1) {
      final char = stdoutText.codeUnitAt(index);
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == 0x5c) {
          escaped = true;
        } else if (char == 0x22) {
          inString = false;
        }
        continue;
      }
      if (char == 0x22) {
        inString = true;
      } else if (char == 0x7b) {
        depth += 1;
      } else if (char == 0x7d) {
        depth -= 1;
        if (depth == 0) {
          final candidate = stdoutText.substring(searchStart, index + 1);
          try {
            final decoded = jsonDecode(candidate);
            if (decoded is Map<String, dynamic> && matches(decoded)) {
              return candidate;
            }
          } on FormatException {
            // Continue searching after non-JSON diagnostic output.
          }
          break;
        }
      }
    }
    searchStart = stdoutText.indexOf('{', searchStart + 1);
  }
  throw ProcessRunnerException(
    '$description did not emit a matching JSON object.',
    stdout: stdoutText,
  );
}

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

/// Thrown when the external Convex CLI cannot be executed successfully.
class ProcessRunnerException implements Exception {
  /// Creates a process runner failure with optional captured output.
  ProcessRunnerException(this.message, {this.stdout, this.stderr});

  /// Human-readable failure details.
  final String message;

  /// Captured standard output, when available.
  final String? stdout;

  /// Captured standard error, when available.
  final String? stderr;

  @override
  String toString() => message;
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
    String? schemaFile,
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
        lastFailure = ProcessRunnerException(error.message);
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
      if (_looksLikeMissingExecutable(stderrText)) {
        lastFailure = ProcessRunnerException(stderrText);
        continue;
      }
      throw ProcessRunnerException(
        'convex function-spec failed in $projectDirectory',
        stdout: stdoutText,
        stderr: stderrText,
      );
    }
    throw ProcessRunnerException(
      'Unable to run "convex function-spec". Install the Convex CLI or use '
      '--spec-file.',
      stderr: lastFailure?.stderr,
    );
  }

  @override
  Future<String?> runSchemaSpec({
    required String projectDirectory,
    required bool verbose,
    String? schemaFile,
  }) async {
    final resolvedSchema = _resolveSchemaFile(projectDirectory, schemaFile);
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
        'import schema from ${jsonEncode(resolvedSchema)};\n'
        'process.stdout.write(schema.export());\n',
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
        if (_looksLikeMissingExecutable(stderrText)) {
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

  String? _resolveSchemaFile(String projectDirectory, String? configuredPath) {
    if (configuredPath != null) {
      final resolved =
          path.isAbsolute(configuredPath)
              ? configuredPath
              : path.join(projectDirectory, configuredPath);
      if (!File(resolved).existsSync()) {
        throw ProcessRunnerException('Schema file does not exist: $resolved');
      }
      return path.normalize(path.absolute(resolved));
    }

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

  bool _looksLikeMissingExecutable(String stderrText) {
    final lowered = stderrText.toLowerCase();
    return lowered.contains('not found') ||
        lowered.contains('command not found') ||
        lowered.contains('is not recognized');
  }
}

/// Extracts the first balanced Convex function spec JSON object from stdout.
String extractFunctionSpecJson(String stdoutText) {
  if (stdoutText.isEmpty) {
    throw ProcessRunnerException('convex function-spec produced no output.');
  }

  var searchStart = stdoutText.indexOf('{');
  if (searchStart == -1) {
    throw ProcessRunnerException(
      'convex function-spec did not emit valid JSON.',
      stdout: stdoutText,
    );
  }

  Object? lastError;
  var foundJsonObject = false;
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
            if (decoded is Map<String, dynamic>) {
              foundJsonObject = true;
              if (_looksLikeFunctionSpec(decoded)) {
                return candidate;
              }
              lastError =
                  'JSON object is missing string "url" and list "functions" '
                  'fields';
            } else {
              lastError = 'JSON value is ${decoded.runtimeType}, not an object';
            }
          } catch (error) {
            lastError = error;
          }
          break;
        }
        if (depth < 0) {
          break;
        }
      }
    }
    searchStart = stdoutText.indexOf('{', searchStart + 1);
  }

  throw ProcessRunnerException(
    foundJsonObject
        ? 'convex function-spec did not emit a Convex function spec JSON '
            'object.'
        : lastError == null
        ? 'convex function-spec did not emit a complete JSON object.'
        : 'convex function-spec output contains invalid JSON: $lastError',
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

bool _looksLikeFunctionSpec(Map<String, dynamic> object) {
  return object['url'] is String && object['functions'] is List<dynamic>;
}

<p align="center">
  <img src="assets/dartvex-logo.svg" width="200" alt="Dartvex Logo" />
</p>

<h1 align="center">Dartvex</h1>

<p align="center">
  Dart packages for <a href="https://convex.dev">Convex</a> — pure-Dart realtime sync, type-safe codegen, Flutter widgets, and offline support.
</p>

<p align="center">
  <a href="https://github.com/AndreFrelicot/dartvex/actions/workflows/ci.yml"><img src="https://github.com/AndreFrelicot/dartvex/actions/workflows/ci.yml/badge.svg?branch=main&event=push" alt="CI" /></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="License: MIT" /></a>
  <a href="https://dart.dev"><img src="https://img.shields.io/badge/dart-packages-blue.svg" alt="Dart packages" /></a>
  <a href="https://pub.dev/publishers/andrefrelicot.dev/packages"><img src="https://img.shields.io/badge/pub.dev-andrefrelicot.dev-0175C2" alt="pub.dev publisher: andrefrelicot.dev" /></a>
</p>

<p align="center">
  <img src="assets/dartvex-poster.webp" width="900" alt="Dartvex Flutter demo — real-time chats running on iOS and macOS" />
</p>

---

## Fork additions

This is [ohtenkay/dartvex](https://github.com/ohtenkay/dartvex), a fork of
[AndreFrelicot/dartvex](https://github.com/AndreFrelicot/dartvex). Sections marked
**(fork addition)** describe features added here since upstream commit `e5800e5`.

- **Shared table documents and schema-derived sealed unions** with reusable
  `<TableName>Document` types and a configurable
  discriminator — [codegen guide](packages/dartvex_codegen/README.md#schema-derived-discriminated-unions-fork-addition).
- **Generated typed Flutter query and mutation widgets**, default loading/error
  UI, and mutation executors with `run(...)` and success callbacks —
  [codegen guide](packages/dartvex_codegen/README.md#generated-flutter-widgets-fork-addition).
- **Typed optimistic query updates** and replaceable local optimistic layers —
  [core guide](packages/dartvex/README.md#typed-optimistic-updates-fork-addition).
- **Latest-value mutations** for selectors and other replacement writes —
  [Flutter guide](packages/dartvex_flutter/README.md#latest-value-mutations-fork-addition).
- **Authenticated password changes** —
  [auth guide](packages/dartvex_auth_better/README.md#6-change-password-fork-addition).
- **Native social sign-in and session adoption** —
  [auth guide](packages/dartvex_auth_better/README.md#native-social-sign-in-fork-addition).
- **Minimal Nix development environment** — [development setup](#development-setup-fork-addition).

Fork changes are unreleased. The pub.dev versions and badges below refer to
upstream; use this checkout or Git dependencies pinned to a fork commit for
these additions. Keep related Dartvex packages on the same fork revision.
See the package changelogs for release details and migration notes:
[core](packages/dartvex/CHANGELOG.md#unreleased),
[codegen](packages/dartvex_codegen/CHANGELOG.md#unreleased),
[Flutter](packages/dartvex_flutter/CHANGELOG.md#unreleased), and
[auth](packages/dartvex_auth_better/CHANGELOG.md#unreleased).
`dartvex_local` has no fork-specific changes on this branch.

## Why Dartvex?

- **Pure-Dart core** — the `dartvex` client has no Rust FFI or Flutter
  dependency; companion packages add Flutter/native integrations where noted.
- **Type-safe codegen** — Generate Dart bindings from your Convex schema. Catch errors at compile time.
- **Flutter widgets** — `ConvexProvider`, `ConvexQuery`, `ConvexMutation` and more for reactive UI.
- **Offline capable** — SQLite query cache and mutation queue with optimistic updates.
- **Multi-platform** — iOS, Android, web, macOS, Linux, Windows.

Web support covers the core realtime client, auth, storage URL resolution, and
Flutter query/mutation widgets. Disk-backed file/image cache and offline image
fallback are native-only because they rely on `dart:io` and local filesystem
storage.

## Quick Start

```dart
import 'package:dartvex/dartvex.dart';

void main() async {
  final client = ConvexClient('https://your-deployment.convex.cloud');

  // Subscribe to a query
  final sub = client.subscribe('messages:list', {});
  sub.stream.listen((result) {
    if (result case QuerySuccess(:final value)) {
      print('Messages: $value');
    }
  });

  // Run a mutation
  await client.mutate('messages:send', {'body': 'Hello from Dart!'});
}
```

## Packages

| Package | Description | Version |
|---------|-------------|---------|
| [`dartvex`](packages/dartvex/) | Core client — WebSocket sync, subscriptions, auth | 0.2.0 |
| [`dartvex_flutter`](packages/dartvex_flutter/) | Flutter widgets — Provider, Query, Mutation | 0.2.0 |
| [`dartvex_codegen`](packages/dartvex_codegen/) | CLI code generator — type-safe Dart bindings from schema | 0.2.0 |
| [`dartvex_local`](packages/dartvex_local/) | Offline support — SQLite cache, mutation queue | 0.2.0 |
| [`dartvex_auth_better`](packages/dartvex_auth_better/) | Better Auth adapter | 0.2.0 |

## Agent Skills

This repo ships [Agent Skills](https://agentskills.io) that teach AI coding
agents (Claude Code, Cursor, Copilot, Codex, …) how to build apps with
Dartvex:

```bash
npx skills add AndreFrelicot/dartvex
```

| Skill | Use it to |
|-------|-----------|
| `dartvex` | Route any Dartvex task to the right skill |
| `dartvex-quickstart` | Connect a Dart/Flutter app to Convex |
| `dartvex-generate-bindings` | Generate a type-safe API with `dartvex_codegen` |
| `dartvex-setup-auth` | Better Auth login, session restore, manual JWT auth |
| `dartvex-build-realtime-ui` | Live queries, optimistic mutations, pagination widgets |
| `dartvex-setup-offline` | SQLite cache and offline mutation queue |
| `dartvex-upload-files` | Convex file storage and cached image widgets |
| `dartvex-test-with-fakes` | Widget tests with `FakeConvexClient` |

They pair with the official [`get-convex/agent-skills`](https://github.com/get-convex/agent-skills)
(backend authoring) and [`flutter/skills`](https://github.com/flutter/skills)
(general Flutter UI).

## Architecture

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                                  Your App                                   │
├────────────────────────┬──────────────────────┬─────────────────────────────┤
│ dartvex_flutter        │ dartvex_local        │ dartvex_auth_*              │
│ (widgets)              │ (offline)            │ (better auth adapters)      │
├────────────────────────┴──────────────────────┴─────────────────────────────┤
│                                  dartvex                                    │
│                     (core client + WebSocket sync)                          │
├─────────────────────────────────────────────────────────────────────────────┤
│                              Convex Backend                                 │
└─────────────────────────────────────────────────────────────────────────────┘

                              dartvex_codegen
                   (generates typed bindings from schema)
```

## Installation

### 1. Add dependencies

```yaml
# pubspec.yaml
dependencies:
  dartvex: ^0.2.0
  dartvex_flutter: ^0.2.0  # If using Flutter

dev_dependencies:
  dartvex_codegen: ^0.2.0  # For code generation
```

### 2. Configure your client

```dart
import 'package:dartvex/dartvex.dart';
import 'package:dartvex_flutter/dartvex_flutter.dart';

final client = ConvexClient('https://your-deployment.convex.cloud');
final runtime = ConvexClientRuntime(client);

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ConvexProvider(
      client: runtime,
      child: MaterialApp(home: HomePage()),
    );
  }
}
```

### 3. Generate type-safe bindings

```bash
dart run dartvex_codegen generate \
  --spec-file path/to/function_spec.json \
  --output lib/convex_api/
```

### 4. Use in your widgets

```dart
ConvexQuery<List<Message>>(
  query: 'messages:list',
  args: const {},
  decode: (v) => [
    for (final item in v as List) Message.fromJson(item as Map<String, dynamic>),
  ],
  builder: (context, snapshot) {
    if (snapshot.isLoading) return const CircularProgressIndicator();
    if (snapshot.hasError) return Text('Error: ${snapshot.error}');
    final messages = snapshot.data ?? const <Message>[];
    return ListView(children: messages.map(MessageTile.new).toList());
  },
)
```

## Usage Examples

### Queries

```dart
final sub = client.subscribe('tasks:list', {'projectId': 'abc123'});
sub.stream.listen((result) {
  if (result case QuerySuccess(:final value)) {
    print('Tasks: $value');
  }
});
```

### Mutations

```dart
await client.mutate('tasks:create', {
  'title': 'Ship dartvex',
  'projectId': 'abc123',
});
```

### Actions

```dart
final result = await client.action('ai:summarize', {
  'documentId': 'doc456',
});
```

### Authentication

```dart
final authClient = BetterAuthClient(
  baseUrl: 'https://your-deployment.convex.cloud',
);
final provider = ConvexBetterAuthProvider(client: authClient)
  ..email = 'user@example.com'
  ..password = 'securePassword';

final client = ConvexClient('https://your-deployment.convex.cloud');
final authedClient = client.withAuth(provider);
await authedClient.login();
```

### Offline Support

```dart
import 'package:dartvex_local/dartvex_local.dart';

final remoteClient = ConvexClient('https://your-deployment.convex.cloud');
final store = await SqliteLocalStore.open('my_app.sqlite');
final localClient = await ConvexLocalClient.open(
  client: remoteClient,
  config: LocalClientConfig(
    cacheStorage: store,
    queueStorage: store,
    disposeRemoteClient: true,
  ),
);

// Queries served from cache when offline
// Mutations queued and synced when back online
```

The local-first query cache and mutation queue use SQLite and are intended for
native targets. For files on web, resolve signed Convex storage URLs and render
them directly; disk-backed file cache/offline image fallback is not supported on
web in this release.

## Development setup (fork addition)

With [devenv](https://devenv.sh/) installed, enter the pinned development shell:

```bash
devenv shell
```

It provides Flutter (including Dart), Node.js 24, and npm. Package analysis,
Dart tests, and Flutter widget tests need no emulator. Android builds and device
testing need an Android SDK; an emulator is optional with a physical device.
The main Flutter example requires Dart 3.11 or newer.

Resolve local package dependencies before testing your changes. For example:

```bash
bash scripts/ci-local-dependency-overrides.sh packages/dartvex_flutter
cd packages/dartvex_flutter
flutter pub get
flutter analyze
flutter test
```

Run the override script for each affected package; use `dart pub get`,
`dart analyze`, and `dart test` for pure Dart packages. See
[the example guide](example/README.md) for the Convex backend and demo app.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.

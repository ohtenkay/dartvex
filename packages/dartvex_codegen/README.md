<p align="center">
  <a href="https://github.com/AndreFrelicot/dartvex">
    <img src="https://raw.githubusercontent.com/AndreFrelicot/dartvex/main/assets/dartvex-logo-512.png" width="128" alt="Dartvex" />
  </a>
</p>

# dartvex_codegen

CLI code generator for [Convex](https://convex.dev) backends. Generates type-safe Dart bindings from your Convex schema and function spec — companion tool to [`dartvex`](https://pub.dev/packages/dartvex).

## Fork additions

This package is part of [ohtenkay/dartvex](https://github.com/ohtenkay/dartvex),
a fork of [AndreFrelicot/dartvex](https://github.com/AndreFrelicot/dartvex).

Adds schema-derived sealed unions and opt-in generated Flutter query/mutation
widgets, typed references, and mutation executors. See
[schema unions](#schema-derived-discriminated-unions-fork-addition),
[Flutter generation](#generated-flutter-widgets-fork-addition), and the
[Unreleased changelog](CHANGELOG.md#unreleased).

The pub.dev installation examples below refer to upstream releases. Use this
checkout or Git dependencies pinned to a fork commit for fork additions, keeping
related Dartvex packages on the same revision. See the
[root fork overview](../../README.md#fork-additions).

<p align="center">
  <a href="https://github.com/AndreFrelicot/dartvex">
    <img src="https://raw.githubusercontent.com/AndreFrelicot/dartvex/main/assets/dartvex-poster.webp" width="900" alt="Dartvex Flutter demo — real-time chats running on iOS and macOS" />
  </a>
</p>

## The Dartvex ecosystem

| Package | Description |
|---------|-------------|
| [`dartvex`](https://pub.dev/packages/dartvex) | Core client — WebSocket sync, subscriptions, auth |
| [`dartvex_flutter`](https://pub.dev/packages/dartvex_flutter) | Flutter widgets — Provider, Query, Mutation |
| **[`dartvex_codegen`](https://pub.dev/packages/dartvex_codegen)** | CLI code generator — type-safe Dart bindings from schema |
| [`dartvex_local`](https://pub.dev/packages/dartvex_local) | Offline support — SQLite cache, mutation queue |
| [`dartvex_auth_better`](https://pub.dev/packages/dartvex_auth_better) | Better Auth adapter |

Fork source and docs: [github.com/ohtenkay/dartvex](https://github.com/ohtenkay/dartvex).
Upstream: [github.com/AndreFrelicot/dartvex](https://github.com/AndreFrelicot/dartvex).

## Installation

```yaml
dev_dependencies:
  dartvex_codegen: ^0.2.0
```

Requires Dart `^3.7.0`.

The generated bindings call APIs introduced in `dartvex` 0.2.0 (such as
`ConvexFunctionCaller.paginatedQuery` and `QueryLoading`), so the application
consuming the generated code needs:

```yaml
dependencies:
  dartvex: ^0.2.0
```

## Usage

Generate from an existing Convex TypeScript project:

```bash
dart run dartvex_codegen generate \
  --project /path/to/convex-backend \
  --output /path/to/dart_app/lib/convex_api
```

Generate from a previously exported spec file:

```bash
dart run dartvex_codegen generate \
  --spec-file /path/to/function_spec.json \
  --output /path/to/dart_app/lib/convex_api
```

Useful flags:

- `--client-import package:dartvex/dartvex.dart`
- `--flutter-widgets` **(fork addition)** generates `widgets.dart` with a typed widget for every public mutation and non-paginated query. Add `dartvex_flutter` and Flutter to the consuming app.
- `--discriminator kind` **(fork addition)**
- `--dry-run`
- `--verbose`
- `--watch`

### Generated Flutter widgets (fork addition)

The Flutter output is opt-in and separate from `api.dart`. For example,
`DrinkCreateMutation` wraps `ConvexMutation` and passes a typed callable to
its builder. Call it with named arguments such as
`create(name: name, alcoholPercentage: percentage, drinkCategory: category)`;
the generated wrapper constructs and encodes the argument record. Its
`run(...)` method returns void and reports mutation errors through the snapshot;
pass `onSuccess` for a result callback, or await the callable for explicit error
handling. See [executor usage](../dartvex_flutter/README.md#generated-mutation-executors-fork-addition).
Generated mutation widgets also accept a typed `optimisticUpdate` callback
that can read and update generated query references without raw maps.
`DrinkListCustomQuery` wraps `ConvexTypedQuery` and gives its builder typed
data, with default loading and error UI. Use `waitingBuilder` or `errorBuilder`
to replace those states, or the `.snapshot` constructor to handle every state
and its metadata. Query widgets accept named arguments and manage their
subscriptions automatically. Paginated queries continue to use the generated
pagination API.

### Exported spec hygiene

Before committing an exported spec file, scrub the real deployment URL it
bakes in:

```bash
npx convex function-spec | dart run dartvex_codegen scrub > function_spec.json
```

`scrub` reads from stdin (or `--spec-file`) and writes the spec with the
top-level `url` replaced by `https://your-deployment.convex.cloud`
(customizable via `--placeholder-url`). The transform is idempotent and
preserves key order, so committed diffs stay minimal.

## Generated API

The generator produces:

- `api.dart` as the main entrypoint
- `runtime.dart` with shared helper types like `Optional<T>`
- `schema.dart` with typed table IDs
- `types.dart` **(fork addition)** with shared table documents and schema-derived discriminated unions, when present
- `modules/...` with typed wrappers around Convex queries, mutations, and actions

### Schema-derived discriminated unions (fork addition)

Project generation automatically loads `convex/schema.ts` (or `schema.js`).
Every table document generates a shared `<TableName>Document` type, including
its typed `_id` and `_creationTime` fields (named `id` and `creationTime` in Dart).
Ordinary documents become record typedefs. Table-root object unions with a
required string-literal `kind` become sealed document types:

```dart
sealed class SessionDocument {
  const SessionDocument();

  SessionId get id;
  String get name;

  bool get isSession => this is Session;
  bool get isParty => this is Party;
}
final class Session extends SessionDocument { /* ... */ }
final class Party extends SessionDocument { /* ... */ }
```

Queries returning the same complete document reuse that type in direct,
nullable, list, and nested results, regardless of the containing field name.
Matching uses the complete schema shape, so projections and enriched responses
keep endpoint-specific result types. Regenerating existing project bindings
renames complete-document result types to `<TableName>Document`; update callers
to import those types from `types.dart` or the root `api.dart`.

Every discriminated union base exposes abstract getters for fields present in
all variants with identical validator types and optionality. Common enums and
nested objects also share their generated Dart types. Fields with different
validators, missing fields, and fields with differing optionality stay on the
concrete variants. The discriminator remains a wire-only field.

The base also exposes `is<Variant>` boolean getters for every variant, including
unions without any common fields. Predicate names follow the generated subclass
names, and generation fails if a predicate collides with a schema field name.
These getters help with UI decisions; use Dart's `value is Party` check to
promote a value before accessing party-specific fields.

Nested schema object unions are also shared. Their field name supplies the base
name, and they keep their existing naming convention without a `Document`
suffix. The discriminator can be changed globally with `--discriminator`.

```ts
category: v.union(
  v.object({ kind: v.literal("beer") }),
  v.object({
    kind: v.literal("cocktail"),
    ingredients: v.array(v.string()),
  }),
)
```

The schema field name becomes the shared sealed base name. The discriminator
values become unprefixed subclasses, and `kind` remains a wire-only field:

```dart
sealed class Category {
  const Category();
}

final class Beer extends Category {
  const Beer();
}

final class Cocktail extends Category {
  const Cocktail({required this.ingredients});

  final List<String> ingredients;
}
```

Dartvex recursively discovers unions at any object or array nesting depth.
Using the same field name in multiple schema locations reuses one Dart type
when the union structures are identical. Endpoint fields with a different name
also reuse a uniquely matching schema union. Different structures using the same
field name fail generation. Subclass names are global within `types.dart`, so
discriminator values that normalize to the same Dart name also fail clearly.

Project generation requires the backend's installed `esbuild` and Convex
dependencies. Generation from only `--spec-file` has no local schema and
therefore retains endpoint-local types. See the
[Unreleased changelog](CHANGELOG.md#unreleased) for generator implementation
and compatibility changes.

Example:

```dart
import 'package:dartvex/dartvex.dart';
import 'package:my_app/convex_api/api.dart';

final client = ConvexClient('https://your-deployment.convex.cloud');
final api = ConvexApi(client);

final messages = await api.messages.list();
await api.messages.send(author: 'Andre', text: 'Hello');
final subscription = api.messages.listSubscribe();
```

## How It Works

The public Dart API is the CLI entrypoint (`GenerateCommand` /
`runConvexCodegen`); the stages below are internal:

| Stage | Description |
|-------|-------------|
| `GenerateCommand` | Main CLI command for code generation |
| `SpecParser` | Parses Convex function_spec.json |
| `TypeMapper` | Maps Convex types to Dart types |
| `DartGenerator` | Generates Dart source from function specs |
| `FileEmitter` | Writes generated files to disk |

## Workflow

1. Keep your Convex backend in TypeScript.
2. Run `dartvex_codegen generate`.
3. Import the generated `api.dart` in your Dart or Flutter app.
4. Call typed wrappers instead of raw function names and raw maps.

## Full Documentation

See the [Dartvex monorepo](https://github.com/AndreFrelicot/dartvex) for full documentation and examples.

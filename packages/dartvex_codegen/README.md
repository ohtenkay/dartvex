<p align="center">
  <a href="https://github.com/AndreFrelicot/dartvex">
    <img src="https://raw.githubusercontent.com/AndreFrelicot/dartvex/main/assets/dartvex-logo-512.png" width="128" alt="Dartvex" />
  </a>
</p>

# dartvex_codegen

CLI code generator for [Convex](https://convex.dev) backends. Generates type-safe Dart bindings from your Convex schema and function spec — companion tool to [`dartvex`](https://pub.dev/packages/dartvex).

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

Source and full docs: [github.com/AndreFrelicot/dartvex](https://github.com/AndreFrelicot/dartvex)

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
- `--flutter-widgets` generates `widgets.dart` with a typed widget for every public mutation and non-paginated query. Add `dartvex_flutter` and Flutter to the consuming app.
- `--discriminator kind`
- `--dry-run`
- `--verbose`
- `--watch`

The Flutter output is opt-in and separate from `api.dart`. For example,
`DrinkCreateMutation` wraps `ConvexMutation` and passes a typed callable to
its builder. Call it with named arguments such as
`create(name: name, alcoholPercentage: percentage, drinkCategory: category)`;
the generated wrapper constructs and encodes the argument record.
Generated mutation widgets also accept a typed `optimisticUpdate` callback
that can read and update generated query references without raw maps.
`DrinkListCustomQuery` wraps `ConvexTypedQuery` and gives its builder typed
data, with default loading and error UI. Use `waitingBuilder` or `errorBuilder`
to replace those states, or the `.snapshot` constructor to handle every state
and its metadata. Query widgets accept named arguments and manage their
subscriptions automatically. Paginated queries continue to use the generated
pagination API.

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
- `types.dart` with shared schema-derived discriminated unions, when present
- `modules/...` with typed wrappers around Convex queries, mutations, and actions

### Schema-derived discriminated unions

Project generation automatically loads `convex/schema.ts` (or `schema.js`) and
discovers object unions whose members have a required string-literal `kind`
field. The discriminator can be changed globally with `--discriminator`.

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
when the union structures are identical. Different structures using the same
field name fail generation. Subclass names are global within `types.dart`, so
discriminator values that normalize to the same Dart name also fail clearly.

Schema loading bundles and evaluates the local schema with the project's
installed `esbuild`, then calls Convex's `SchemaDefinition.export()`. Generation
from only `--spec-file` has no local schema and therefore retains endpoint-local
types.

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

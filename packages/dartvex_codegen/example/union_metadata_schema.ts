import { defineSchema, defineTable } from "convex/server";
import { v, type Infer } from "convex/values";

export const drinkCategory = v.union(
  v.object({ kind: v.literal("beer") }),
  v.object({ kind: v.literal("wine") }),
);

// Backend code can read drinkCategoryMetadata[category.kind].defaultVolumeMl.
export const drinkCategoryMetadata = {
  beer: { defaultVolumeMl: 500 },
  wine: { defaultVolumeMl: 200 },
} satisfies Record<Infer<typeof drinkCategory>["kind"], { defaultVolumeMl: number }>;

export const accentColor = v.union(v.literal("amber"), v.literal("rose"));

export const accentColorMetadata = {
  amber: { rgb: 0xf59e0b },
  rose: { rgb: 0xe11d48 },
} satisfies Record<Infer<typeof accentColor>, { rgb: number }>;

// Re-export this array from convex/schema.ts. `generate --project` reads it
// locally; validators and persisted documents contain no metadata fields.
// Matching validators share metadata even in different fields or endpoints.
// Every variant must define the same scalar properties (string, number,
// boolean, or null). A property must have a consistent type across variants.
export const dartvexUnionMetadata = [
  { validator: drinkCategory, variants: drinkCategoryMetadata },
  { validator: accentColor, variants: accentColorMetadata },
];

// Generated Dart exposes category.defaultVolumeMl and accentColor.rgb.
// Flutter can use Color(0xff000000 | accentColor.rgb) to add the alpha channel.
export default defineSchema({
  drinks: defineTable({ category: drinkCategory, accentColor }),
});

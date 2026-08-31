import { defineCollection, z } from "astro:content";
import { glob } from "astro/loaders";

/**
 * Fed by scripts/sync-docs.mjs from ../docs, which is the single source: those
 * files stay valid markdown for anyone reading them on GitHub, and the sync
 * translates their links for the web. Titles and menu labels live in
 * src/lib/guides.ts, so the guides need no front matter (which would show up
 * as a stray table above every file in the GitHub view).
 */
const guides = defineCollection({
  loader: glob({ pattern: "*.md", base: "./src/content/guides" }),
  schema: z.object({}),
});

export const collections = { guides };

// @ts-check
import { defineConfig, fontProviders } from "astro/config";

// Served as a GitHub Pages *project* site. Because the user site
// (frankhuettner.github.io) carries the custom domain huettner.io, this lands
// at https://huettner.io/kingo-pod/ — hence the base. Never add a CNAME file
// here: that would fight the main site over the domain.
const BASE = "/kingo-pod";

export default defineConfig({
  site: "https://huettner.io",
  base: BASE,
  trailingSlash: "always",

  markdown: {
    shikiConfig: {
      themes: { light: "github-light", dark: "github-dark" },
    },
  },

  // Self-hosted at build time: no CDN, no third-party request from a student's
  // browser. Same face as huettner.io.
  fonts: [
    {
      provider: fontProviders.google(),
      name: "Inter",
      cssVariable: "--font-sans",
      weights: [400, 500, 600, 700],
      styles: ["normal", "italic"],
      subsets: ["latin", "latin-ext"],
      fallbacks: ["system-ui", "-apple-system", "Segoe UI", "sans-serif"],
    },
  ],
});

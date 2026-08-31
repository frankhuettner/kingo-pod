/**
 * The guides live in ../docs and must stay correct as plain files on GitHub:
 * they link to each other by file name (STUDENT-GUIDE-MAC.md) and to
 * screenshots by repo-relative path (img/foo.png). This script copies them
 * into the Astro content folder and translates those two things for the
 * website, so neither copy has to compromise. It also drops the leading
 * "# Title" — the page header renders that.
 *
 * Everything it writes is gitignored: ../docs stays the single source.
 * Runs before every dev/build (see package.json).
 */
import { cp, mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { basename, join } from "node:path";

const DOCS = fileURLToPath(new URL("../../docs", import.meta.url));
const OUT = fileURLToPath(new URL("../src/content/guides", import.meta.url));
const IMG_OUT = fileURLToPath(new URL("../public/img", import.meta.url));
const BASE = "/kingo-pod";
const REPO_DOCS = "https://github.com/frankhuettner/kingo-pod/blob/main/docs/";

/** Guide file → URL slug. Keep in step with src/lib/guides.ts. */
const SLUGS = {
  "STUDENT-GUIDE-MAC.md": "mac",
  "STUDENT-GUIDE-WINDOWS.md": "windows",
  "STUDENT-GUIDE-MAC-USB.md": "mac-usb",
  "STUDENT-GUIDE-WINDOWS-USB.md": "windows-usb",
  "USING-MAC.md": "using-mac",
  "USING-WINDOWS.md": "using-windows",
  "CLOUDBEAVER.md": "cloudbeaver",
};

const rewrite = (md) =>
  md
    // the H1 becomes the page header
    .replace(/^# .*\n\n/, "")
    // the "Jump to:" line is the GitHub view's stand-in for a table of
    // contents; on the website the sidebar does that job.
    .replace(/^> \*\*Jump to:\*\*(?:.*\n)*?\n/m, "")
    // links between guides, with or without an #anchor
    .replace(/\]\(([A-Z0-9-]+\.md)(#[^)]*)?\)/g, (whole, file, hash = "") =>
      SLUGS[file] ? `](${BASE}/${SLUGS[file]}/${hash})` : `](${REPO_DOCS}${file}${hash})`,
    )
    // screenshots
    .replace(/\]\(img\//g, `](${BASE}/img/`);

await rm(OUT, { recursive: true, force: true });
await mkdir(OUT, { recursive: true });

// Written out under the URL slug, so the content-collection id and the page
// name are the same word.
for (const [file, slug] of Object.entries(SLUGS)) {
  const md = await readFile(join(DOCS, file), "utf8");
  await writeFile(join(OUT, `${slug}.md`), rewrite(md));
}

await rm(IMG_OUT, { recursive: true, force: true });
await mkdir(IMG_OUT, { recursive: true });
for (const img of await readdir(join(DOCS, "img"))) {
  await cp(join(DOCS, "img", img), join(IMG_OUT, basename(img)));
}

console.log(`[sync] ${Object.keys(SLUGS).length} guides + images from docs/`);

# site/ — the guides as a website

Publishes the markdown in [`../docs`](../docs) to
**<https://huettner.io/kingo-pod/>**: a landing page, the four setup guides, the
two everyday-use guides, the CloudBeaver walkthrough, a table of contents per
page and a Copy button on every command.

`../docs` is the single source. Nothing here holds a second copy of a guide —
`scripts/sync-docs.mjs` reads them at build time into `src/content/guides/`
(gitignored) and rewrites what differs between the GitHub view and the web:

| In `docs/*.md` (correct on GitHub) | On the website |
| --- | --- |
| `](STUDENT-GUIDE-MAC.md)` | `](/kingo-pod/mac/)` |
| `](img/foo.png)` | `](/kingo-pod/img/foo.png)` |
| `# Title` first line | the page header |
| `> **Jump to:** …` | the sidebar table of contents |
| `](INSTRUCTOR.md)` | a link into the repo on GitHub |

So: **edit the guides in `docs/`, never here.** What does live here is the
presentation — and `src/lib/guides.ts`, which holds each guide's URL slug,
title, one-line summary, menu label and menu group (kept out of the markdown,
where front matter would show up as a stray table in the GitHub view). The
`group` is why the header carries two menus, **Setup** and **Use**: a student
follows a setup guide once and then lives in the using guide, so the two "Mac"
entries are told apart by their group label, not by longer names.

## Work on it

```bash
npm install
npm run dev      # http://localhost:4321/kingo-pod/
npm run build    # → dist/
npm run preview
```

## Deployment

`.github/workflows/pages.yml` builds and deploys on every push to `main` that
touches `docs/`, `site/` or the workflow. It needs **Settings → Pages → Source =
GitHub Actions** set once.

The URL is `huettner.io/kingo-pod` because GitHub serves project pages under the
custom domain of the user site (`frankhuettner.github.io` → huettner.io); hence
`base: "/kingo-pod"` in `astro.config.mjs`. **Never add a `CNAME` file here** —
that would fight the main site over the domain.

Design tokens (palette, type scale, dark mode) are copied from huettner.io so
the guides look like part of it, but the chrome is a documentation chrome: the
header names the guides instead of a CV.

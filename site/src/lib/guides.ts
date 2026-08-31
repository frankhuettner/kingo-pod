/**
 * The guides themselves are plain markdown in ../../docs — unchanged, so they
 * still read correctly as files on GitHub. Everything the website needs on top
 * of the prose lives here instead of in front matter, which would show up as a
 * stray table above every guide in the GitHub view.
 *
 * `file` is the name in docs/; `slug` is the URL. Old GitHub links keep
 * working because the file names never change.
 *
 * Two groups, because they are read at different times: a student follows a
 * SETUP guide once and then never again, and lives in the USE guide for the
 * rest of the term.
 */
export interface Guide {
  slug: string;
  file: string;
  title: string;
  /** One line, shown under the title and on the card. */
  summary: string;
  /** Short label for the header menu — unique only within its group. */
  nav: string;
  group: "Setup" | "Use";
  platform: "Mac" | "Windows" | "Any";
  kind: "Internet" | "USB stick" | "Everyday use" | "The class database";
}

export const GUIDES: Guide[] = [
  {
    slug: "mac",
    file: "STUDENT-GUIDE-MAC.md",
    title: "Mac setup",
    summary: "Apple Silicon, over the internet. One command installs and starts the whole class stack.",
    nav: "Mac",
    group: "Setup",
    platform: "Mac",
    kind: "Internet",
  },
  {
    slug: "windows",
    file: "STUDENT-GUIDE-WINDOWS.md",
    title: "Windows setup",
    summary: "Windows 10/11 via WSL2. Turn WSL2 on once, then one command does the rest.",
    nav: "Windows",
    group: "Setup",
    platform: "Windows",
    kind: "Internet",
  },
  {
    slug: "mac-usb",
    file: "STUDENT-GUIDE-MAC-USB.md",
    title: "Mac setup from the USB stick",
    summary: "Same result as the Mac guide, but the ~14 GB of images come off the instructor's stick.",
    nav: "Mac (USB)",
    group: "Setup",
    platform: "Mac",
    kind: "USB stick",
  },
  {
    slug: "windows-usb",
    file: "STUDENT-GUIDE-WINDOWS-USB.md",
    title: "Windows setup from the USB stick",
    summary: "Same result as the Windows guide, but the ~14 GB of images come off the instructor's stick.",
    nav: "Windows (USB)",
    group: "Setup",
    platform: "Windows",
    kind: "USB stick",
  },
  {
    slug: "using-mac",
    file: "USING-MAC.md",
    title: "Using the stack on a Mac",
    summary: "Your addresses and logins, the everyday commands, your own files, updating, and fixing things.",
    nav: "Mac",
    group: "Use",
    platform: "Mac",
    kind: "Everyday use",
  },
  {
    slug: "using-windows",
    file: "USING-WINDOWS.md",
    title: "Using the stack on Windows",
    summary: "Your addresses and logins, the everyday commands, your own files, updating, and fixing things.",
    nav: "Windows",
    group: "Use",
    platform: "Windows",
    kind: "Everyday use",
  },
  {
    slug: "cloudbeaver",
    file: "CLOUDBEAVER.md",
    title: "Using CloudBeaver",
    summary: "How to log in to the browser SQL workbench and open the class database.",
    nav: "CloudBeaver",
    group: "Use",
    platform: "Any",
    kind: "The class database",
  },
];

export const SETUP = GUIDES.filter((g) => g.group === "Setup");
export const USE = GUIDES.filter((g) => g.group === "Use");

/** docs/<file> → /<slug>/, used by the doc-sync script. */
export const FILE_TO_SLUG = Object.fromEntries(GUIDES.map((g) => [g.file, g.slug]));

export const bySlug = (slug: string) => GUIDES.find((g) => g.slug === slug);

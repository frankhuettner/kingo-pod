# How `kingo claude` differs from a standard Claude Code

`./kingo claude` (or `./kingo yolo`, the same without requests for permission) starts Claude Code set up for the course. This page
says what is different from a Claude Code you install and start with `claude`, and where the course configures each part. The
templates in this folder are what `kingo claude` copies into `kingo-pod/claude/` on the first start.

Only a start with `./kingo claude` or `./kingo yolo` sets all this up. A plain `claude`, in any folder, is a standard
Claude Code with Anthropic's settings, the student's own `~/.claude` and their own login. In `kingo-pod/claude` it
also reads the folder's `.claude/settings.json` and `AGENTS.md`, but it runs without the sandbox, without the keys and
without the way to OpenRouter.

| | A standard Claude Code | Here, started with `./kingo claude` | Configured for the course in |
|---|---|---|---|
| Start | `claude`, in any folder | `./kingo claude` in the kingo-pod folder; `./kingo yolo` is the same without requests for permission. Claude works in `kingo-pod/claude` | `kingo-pod/kingo`, the script behind every `./kingo` command. Before Claude starts, it checks that n8n and Langflow run, asks for the student's keys the first time, copies `AGENTS.md`, `CLAUDE.md` and `.claude/settings.json` into `kingo-pod/claude/` the first time, and writes the nono profile. Then it starts Claude Code inside nono. |
| Model and bill | Claude models, with an Anthropic account or key | GLM 5.3 Flash through OpenRouter, paid with the student's OpenRouter key | `kingo-pod/claude/.claude/settings.json` names the model, for every role (`ANTHROPIC_MODEL` and the lines `ANTHROPIC_DEFAULT_…_MODEL`). The nono profile sends Claude's requests to OpenRouter instead of Anthropic, and puts the student's OpenRouter key into them. Claude Code does not know this model: `kingo-pod/kingo` tells it the context size to work with (`CLAUDE_CODE_MAX_CONTEXT_TOKENS`), 200,000 tokens. |
| Keys | kept by Claude Code itself | kept in `~/.config/kingo/`; Claude sees only stand-ins | `kingo-pod/kingo` asks for the student's OpenRouter and n8n keys, makes the Langflow key itself, and keeps them in `~/.config/kingo/`, readable only by the student. nono reads them from these files when it starts; they are never in an environment variable. The nono profile says, for OpenRouter, n8n and Langflow, which file holds the key and where nono's proxy puts it into a request. In the course, the OpenRouter key has a second route, `$OPENROUTER_BASE_URL`, also with `--login`: with it, Claude can try a model or an embedding of the student's flows. |
| Files | Claude reads and writes wherever the student may, after asking | Claude writes only in `kingo-pod/claude` and `~/.kingo-claude`, reads `kingo-pod`, and nothing else; the operating system enforces it | The nono profile `~/.config/nono/profiles/kingo-claude.json` lists the folders Claude may read and write, and the few environment variables that reach Claude: other keys on the laptop do not. `kingo` writes it anew at every start from `kingo-pod/setup/claude/nono-profile.json`, so a change to it does not last. On top, `kingo-pod/claude/.claude/settings.json` forbids Claude to read `.env` files, `~/.ssh` and `~/.aws`. |
| Sandbox | Claude Code's own sandbox, for commands only, if the student turn it on | nono, around all of Claude Code: its commands, and its own tools for files too | the nono profile. `kingo-pod/kingo` downloads one fixed version of nono on the first start, checks it against a checksum, keeps it in `~/.local/share/kingo/nono` and starts that one, not a nono that is installed: the profile is written for this version, and a newer one comes with `./kingo update`. `./kingo claude nono` says which nono it starts. `kingo-pod/claude/.claude/settings.json` turns Claude Code's own sandbox off (`sandbox.enabled`): nono covers more. On Windows, nono prints `WARNING: WSL2 insecure proxy mode` at every start: there it cannot force Claude's traffic through its proxy, and the profile line `wsl2_proxy_policy` lets it start anyway. On Windows and Linux, nono also does not keep a program from talking to a service over a Unix socket (Docker, Podman, systemd), and such a service works outside the sandbox. There `kingo-pod/kingo` starts Claude Code through `setup/claude/no_unix_sockets.py`, which takes Unix sockets away from Claude Code and from every program it starts. |
| Settings and history | `~/.claude` | `~/.kingo-claude`; the student's own `~/.claude` stays untouched | `kingo-pod/kingo` starts Claude with `CLAUDE_CONFIG_DIR=~/.kingo-claude`: Claude Code keeps its settings, sessions and history there. An Anthropic login stored there, `kingo` removes at every start: the course does not use it, and Claude could read it. |
| Instructions | a `CLAUDE.md` that the student write | `AGENTS.md`: the part about kingo-pod and the team's rules; `CLAUDE.md` only points to it | `kingo-pod/claude/AGENTS.md`: every start writes its course part, above `# Your team's rules`, from `setup/claude/AGENTS.md`, and the facts that it loads from `info-for-ai/`; the team's part is the student's. `kingo-pod/claude/CLAUDE.md` holds only `@AGENTS.md`. `settings.json` makes Claude skip the `CLAUDE.md` of kingo-pod itself, which is for kingo-pod's developers (`claudeMdExcludes`). |
| Memory | hidden in `~/.claude/projects/` | in `kingo-pod/claude/memory-of-ai/`, where the student can read it; with `--in`, in `memory-of-ai/` of that folder | `kingo-pod/claude/.claude/settings.json` (`autoMemoryDirectory`); with `--in`, kingo adds it to the settings at every start |
| What leaves the laptop | the model's requests, plus usage data, error reports and feedback to Anthropic; pages on claude.ai (artifacts) and Remote Control, if the student use them | the model's requests, to OpenRouter only; usage data, error reports, feedback, pages on claude.ai and Remote Control are off | `kingo-pod/kingo` turns off pages on claude.ai, usage data, error reports and all traffic that is not needed, when it starts Claude. `kingo-pod/claude/.claude/settings.json` turns off the same, and also feedback (`DISABLE_FEEDBACK_COMMAND`), Remote Control (`disableRemoteControl`), pages on claude.ai (`enableArtifact`) and the check of each web address at Anthropic before Claude reads a page (`skipWebFetchPreflight`). |
| A way back | none | every start saves each n8n workflow and Langflow flow as a JSON file in `kingo-pod/backups/flows/`, a folder per start; the newest 10 stay. Claude can read them but not change them. A file can be imported again in n8n or in Langflow | `kingo-pod/kingo`, before it starts Claude. It needs `psql`. |
| Seeing and trying pages | Claude Code reads pictures, but it has no browser to make one of a page it wrote, or to click through one | `look page.html` makes pictures of the whole page, part by part, in `look/`, and Claude reads them. `--width 600` gives a narrow window, `--pdf` the page as it prints. look waits a moment for the page's scripts before each picture | `kingo-pod/setup/claude/bin/look`, which `kingo-pod/kingo` puts on the PATH. The browser is Chrome without a window (chrome-headless-shell, one fixed version). `kingo` downloads it on the first start, checks it against a checksum and keeps it in `~/.local/share/kingo/browsers`, which the sandbox can read and not change; it runs inside the sandbox. On a Mac, Chrome registers a name with the system for its helper programs; one rule in the nono profile allows exactly that name. Where a Mac refuses it all the same, look runs Chrome as one program and says that it could not wait for scripts. `./kingo claude browser` gets it again and names the system packages it needs under Windows (WSL). `kingo` also tells Claude Code at every start to look at a page before it calls it done.<br><br>`clickthrough try.cjs` runs a short Node.js script with playwright-core, in which Claude clicks through a page as a person would: opens it, fills in a form, presses a button and reads the answer. The name says what it does: look takes a picture of a page, clickthrough clicks through it, and to read the internet Claude has its web tools. The script is a `.cjs`, since in a Vite project a `.js` is an ES module. Pages on the internet work too, by https through nono's proxy. In clickthrough, http addresses and WebSockets are closed (in Chrome itself and in every context of the script), so that no page of the internet can reach n8n, Langflow or another service on the laptop: when the network is open, nono's proxy lets the laptop's own addresses through, and under WSL2 nothing stops a direct connection to 127.0.0.1. The locks hold whatever the script does through Playwright's API: every require and import of Playwright gets kingo's copy, also in a folder with a copy of its own in `node_modules`; a route of the script cannot get ahead of them; no context gets a proxy of its own; and the other ways to a browser (connectOverCDP and the like) are closed. To try a webhook of n8n, Claude uses curl with `$N8N_BASE_URL`. `kingo` gets Node.js and playwright-core with the browser (fixed versions, checksums) into `~/.local/share/kingo`, read only for the sandbox; `kingo-pod/setup/claude/clickthrough-setup.js` makes `chromium.launch()` start the browser of look. Playwright's MCP server and its CLI do not run in the sandbox: both open a Unix socket for their browser. `clickthrough --dev 5173 try.cjs` also opens the student's dev server (Vite and the like): http and its WebSocket on that one port, for pages that come from it and for page.goto of the script; a page of the internet can neither fetch from it nor send the tab there (it could open a WebSocket to it, which clickthrough cannot see). kingo opens this port in the profile: `KINGO_DEV_PORT`, 5173 unless the student names another before `./kingo claude`, never a port of kingo-pod. On a Mac the student starts the dev server in their own terminal (npm run dev): the sandbox lets no program listen there. Under Linux and WSL2 the sandbox lets a program listen on this one port too. |
| Requests for permission | since version 2.1.283, Claude Code starts in auto mode: a model checks each command, runs what it judges safe and blocks the rest, without asking | Claude asks before a command (manual mode). Shift+Tab switches the mode, to auto mode too: there, GLM 5.3 Flash is the judge. `./kingo yolo` turns the requests off | `kingo-pod/kingo` starts Claude with `--permission-mode default`, and `./kingo yolo` starts it with `--dangerously-skip-permissions`. The sandbox stays the same. |
| Updates | Claude Code updates itself | no self-update: run the install line again | `kingo-pod/claude/.claude/settings.json`: `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` also turns off the self-update. |

## Changing the sandbox yourself

The sandbox is a profile for nono, built from small files in `setup/claude/`. Each has comments; read them to see
what Claude Code gets.

| File | What it holds |
|---|---|
| `nono-profile-core.json` | what Claude Code may read, the variables it gets, the rule for `look`. No way to a model |
| `nono-profile-base.json` | core, and the way to OpenRouter with your key. `./kingo claude --in` starts with it |
| `nono-profile-course.json` | what the course adds: n8n, Langflow, PostgreSQL, and OpenRouter for the models of your flows |
| `nono-profile.json` | base and course together. `./kingo claude` starts with it |
| `nono-profile-login.json`, `-login-course.json`, `-login-open.json` | the same with your Anthropic login in place of OpenRouter (see below) |

To give Claude Code more, for example the folder `kingo-pod/shared`:

```
cp setup/claude/my-nono-profile.example.json my-nono-profile.json
```

Change `my-nono-profile.json` and start `./kingo claude` again. Your file adds to the course profile; it cannot take
anything of it away. Claude Code can read the file and cannot change it, so the sandbox is yours to widen, not
Claude's. Delete the file to go back.

For one start, without a file: `./kingo claude --read <folder>` lets Claude Code also read a folder, and
`--write <folder>` also change it; both go more than once, with `--in` and `--login` too, and with the short commands
(`kc ~/projects/site --read ~/projects/notes`). kingo gives the folders to nono (`--read`, `--allow`) and to Claude
Code (`--add-dir`, so that it reads there without asking), names them before the start, and tells Claude Code. The
rules are those of `--in` (below). Of kingo-pod, both take only `shared/`; in the course, `--read` takes all of it,
as the course reads it anyway. The next start without them is the sandbox as before.

`/add-dir` in Claude Code is no way into the sandbox: it adds a folder to Claude Code's own list, and nono, which no
program inside it can widen, still refuses it (`Operation not permitted` on a Mac, `Permission denied` under Linux
and Windows). So kingo gives Claude Code, with its instructions, the line for a new start with one more folder: this
start's own (`--login`, the folder, the folders of `--read` and `--write`), with one `--read` more. `AGENTS.md` and
the text for `--in` tell Claude Code to give the student that line in place of `/add-dir`.

## A folder of your own, without the course

`./kingo claude --in ~/projects/thesis` starts the same Claude Code in that folder: the same sandbox, the same model
and key, `look`. It writes only in that folder. There is no n8n, no Langflow and no database, and the pod need not
run. kingo puts no file into your folder; Claude Code keeps its memory there, in `memory-of-ai/`, with and without
`--login`. The folder must be inside your home folder. kingo refuses:

- the home folder itself, and `Desktop`, `Documents`, `Downloads`, `Pictures`, `Music`, `Movies` and `Library` as a
  whole. A folder in them is your choice: on a Mac, Dropbox, OneDrive, Google Drive and iCloud Drive keep their files
  in `~/Library` (`~/Library/CloudStorage/Dropbox/notes`);
- hidden folders;
- where kingo and other programs keep their keys and settings, also when a link puts such a folder elsewhere
  (`~/.config` in `~/dotfiles/config`);
- a folder where your terminal finds its commands (`~/bin`, the folders of `PATH`), or one that holds one, and
  `~/Library/LaunchAgents`, whose programs a Mac starts at login: a program put there would run outside the sandbox
  later;
- a folder that holds kingo-pod, and Windows folders (`/mnt/c/...`).

The same rules hold for `--read` and `--write`, but `--read` may take a folder with commands in it.

You can name the folder from where you are: `--in .` is the folder you are in, `--in thesis` the folder `thesis` in
it. kingo-pod or a folder in it starts Claude Code for the course, as `./kingo claude` does, and kingo says so.

## Another OpenRouter key for one project

`./kingo claude --key <name>` (with the short commands: `kc ~/projects/thesis --key thesis`) pays Claude Code's model
with another OpenRouter key of yours, for this start, in the course and with `--in`. The first start with a name asks
for the key and keeps it with the other keys, in `~/.config/kingo/openrouter-<name>.key`, outside the sandbox; a key
that OpenRouter refuses is deleted, and the next start asks again. For another key under a name, delete its file.

On openrouter.ai, each key has its own credit limit and its own costs: a project can have a budget of its own. kingo
starts nono with one more profile, `kingo-claude-key-<course|base|mine>-<name>`, which extends the profile of this
start and gives the route of the model again, with that key file; nono takes it in place of the base profile's route.
With `--in`, only the key of that name is asked for and checked. In the course, the route for the models of your flows
keeps the key of your flows. Names are small letters, digits and `-` (not at the start or the end). Not with
`--login`, and not with a `my-nono-profile.json` that names another provider for the model.

## Shorter commands: `./kingo shortcuts`

`./kingo shortcuts` adds short commands to your terminal. It shows a list: type the numbers you want, or press Enter
for all of them.

| Shortcut | What it does |
|---|---|
| `kc` | `kingo claude`, the course; `kc .` in the folder you are in, `kc ~/projects/thesis` in that folder |
| `kcl` | the same with `--login`: your own Claude subscription |
| `ky` | the same as `kc`, with `kingo yolo`: Claude works without asking |
| `kyl` | the same with `--login` |
| `kingo` | `kingo` from any folder, for example `kingo status` |

`kc` alone is `./kingo claude`, the course; `kc .` is `./kingo claude --in .`, the folder you are in, and
`kc <folder>` is `./kingo claude --in <folder>` (in kingo-pod, that is the course too). An option first, as in
`kc --resume`, goes to the course. kingo writes the shortcuts into the file that a new terminal reads (`~/.zshrc`; for bash `~/.bashrc`, on a
Mac `~/.bash_profile`), between two marked lines, and keeps a copy of the file first. They call kingo-pod's `kingo`,
so `./kingo update` keeps them up to date, and it writes a block of an older kingo anew. A name that means something in your terminal already, kingo writes only
when you say yes. `./kingo shortcuts remove` takes them out again.

To keep versions of what Claude Code writes, use git in the folder (`git init`); it works inside the sandbox, in the
course folder `kingo-pod/claude` too. Claude Code can commit. It cannot push: your login for GitHub is outside the
sandbox. Push from your own terminal.

## Your Claude subscription in place of OpenRouter

Do you have a Claude subscription (Pro or Max)? Then `./kingo claude --login` starts the same Claude Code with it:
Anthropic's models, paid by your subscription. For the course, kingo still asks for your OpenRouter key, the one of
your flows in Langflow: with it, Claude can try a model or an embedding. With `--in <folder>` it does not ask.
`--login` goes together with `--in <folder>`.

```
./kingo claude --login
```

- **The first start asks you to log in.** On a Mac your browser opens. Under Windows (WSL), Claude Code shows an
  address: open it in your browser, log in, and paste the code into the terminal.
- **The login stays outside the sandbox.** nono, the sandbox, reads the answer of Anthropic's login server, keeps the
  real login for itself and hands Claude Code stand-ins. What Claude Code holds is of no use outside this sandbox.
  kingo checks this after the login: a login that is not a stand-in, it deletes.
- **Where nono keeps it:** in `~/.local/state/nono/oauth-capture`, readable only by you, not encrypted, for up to
  90 days.
- **One session at a time.** Two sessions with `--login` at once break the login (a fault of nono, issues 2087 and
  2299), so `kingo` starts no second one, and no logout, while the first runs.
- **To end the login:** `./kingo claude logout`. Do the same when Claude Code says that you are not logged in, and
  start again.
- **The model:** Claude Code picks one of Anthropic's models. `/model` inside Claude Code changes it.
- **Settings and history** of these sessions are in `~/.kingo-claude-login`, apart from those of `./kingo claude`.

Everything else is the same: the sandbox, `look`, and for the course n8n, Langflow and the database.

You may change `claude/.claude/settings.json`: it is yours after the first start. In `claude/AGENTS.md`, the part
from the heading `# Your team's rules` on is yours. The part above it and the files in `claude/info-for-ai/` are
kingo's: every start writes them anew, so that what kingo knows reaches every course folder. When such a file had
changed, the start keeps it as it was in `kingo-pod/backups/course-files/` (the newest 10 stay). A line above the
heading that no template of kingo's ever had there (`setup/claude/agents-course-lines.txt` keeps them all) is the
team's: kingo moves it below the heading, so that team rules pasted in the wrong place still count. A file without the
heading stays as it is, and kingo says so. The nono profile is written anew at every start, so a change there does
not last.

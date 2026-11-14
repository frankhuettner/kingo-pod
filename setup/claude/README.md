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
| Keys | kept by Claude Code itself | kept in `~/.config/kingo/`; Claude sees only stand-ins | `kingo-pod/kingo` asks for the student's OpenRouter and n8n keys, makes the Langflow key itself, and keeps them in `~/.config/kingo/`, readable only by the student. nono reads them from these files when it starts; they are never in an environment variable. The nono profile says, for OpenRouter, n8n and Langflow, which file holds the key and where nono's proxy puts it into a request. |
| Files | Claude reads and writes wherever the student may, after asking | Claude writes only in `kingo-pod/claude` and `~/.kingo-claude`, reads `kingo-pod`, and nothing else; the operating system enforces it | The nono profile `~/.config/nono/profiles/kingo-claude.json` lists the folders Claude may read and write, and the few environment variables that reach Claude: other keys on the laptop do not. `kingo` writes it anew at every start from `kingo-pod/setup/claude/nono-profile.json`, so a change to it does not last. On top, `kingo-pod/claude/.claude/settings.json` forbids Claude to read `.env` files, `~/.ssh` and `~/.aws`. |
| Sandbox | Claude Code's own sandbox, for commands only, if the student turn it on | nono, around all of Claude Code: its commands, and its own tools for files too | the nono profile. `kingo-pod/kingo` downloads one fixed version of nono on the first start, checks it against a checksum, keeps it in `~/.local/share/kingo/nono` and starts that one, not a nono that is installed: the profile is written for this version, and a newer one comes with `./kingo update`. `./kingo claude nono` says which nono it starts. `kingo-pod/claude/.claude/settings.json` turns Claude Code's own sandbox off (`sandbox.enabled`): nono covers more. On Windows, nono prints `WARNING: WSL2 insecure proxy mode` at every start: there it cannot force Claude's traffic through its proxy, and the profile line `wsl2_proxy_policy` lets it start anyway. On Windows and Linux, nono also does not keep a program from talking to a service over a Unix socket (Docker, Podman, systemd), and such a service works outside the sandbox. There `kingo-pod/kingo` starts Claude Code through `setup/claude/no_unix_sockets.py`, which takes Unix sockets away from Claude Code and from every program it starts. |
| Settings and history | `~/.claude` | `~/.kingo-claude`; the student's own `~/.claude` stays untouched | `kingo-pod/kingo` starts Claude with `CLAUDE_CONFIG_DIR=~/.kingo-claude`: Claude Code keeps its settings, sessions and history there. An Anthropic login stored there, `kingo` removes at every start: the course does not use it, and Claude could read it. |
| Instructions | a `CLAUDE.md` that the student write | `AGENTS.md`: the part about kingo-pod and the team's rules; `CLAUDE.md` only points to it | `kingo-pod/claude/AGENTS.md`, the student's to change, and `kingo-pod/claude/CLAUDE.md`, which holds only `@AGENTS.md`. `settings.json` makes Claude skip the `CLAUDE.md` of kingo-pod itself, which is for kingo-pod's developers (`claudeMdExcludes`). |
| Memory | hidden in `~/.claude/projects/` | in `kingo-pod/claude/memory/`, where the student can read it | `kingo-pod/claude/.claude/settings.json` (`autoMemoryDirectory`) |
| What leaves the laptop | the model's requests, plus usage data, error reports and feedback to Anthropic; pages on claude.ai (artifacts) and Remote Control, if the student use them | the model's requests, to OpenRouter only; usage data, error reports, feedback, pages on claude.ai and Remote Control are off | `kingo-pod/kingo` turns off pages on claude.ai, usage data, error reports and all traffic that is not needed, when it starts Claude. `kingo-pod/claude/.claude/settings.json` turns off the same, and also feedback (`DISABLE_FEEDBACK_COMMAND`), Remote Control (`disableRemoteControl`), pages on claude.ai (`enableArtifact`) and the check of each web address at Anthropic before Claude reads a page (`skipWebFetchPreflight`). |
| A way back | none | every start saves each n8n workflow and Langflow flow as a JSON file in `kingo-pod/backups/flows/`, a folder per start; the newest 10 stay. Claude can read them but not change them. A file can be imported again in n8n or in Langflow | `kingo-pod/kingo`, before it starts Claude. It needs `psql`. |
| Seeing and trying pages | Claude Code reads pictures, but it has no browser to make one of a page it wrote, or to click through one | `look page.html` makes pictures of the whole page, part by part, in `look/`, and Claude reads them. `--width 600` gives a narrow window, `--pdf` the page as it prints. look waits a moment for the page's scripts before each picture | `kingo-pod/setup/claude/bin/look`, which `kingo-pod/kingo` puts on the PATH. The browser is Chrome without a window (chrome-headless-shell, one fixed version). `kingo` downloads it on the first start, checks it against a checksum and keeps it in `~/.local/share/kingo/browsers`, which the sandbox can read and not change; it runs inside the sandbox. On a Mac, Chrome registers a name with the system for its helper programs; one rule in the nono profile allows exactly that name. Where a Mac refuses it all the same, look runs Chrome as one program and says that it could not wait for scripts. `./kingo claude browser` gets it again and names the system packages it needs under Windows (WSL). `kingo` also tells Claude Code at every start to look at a page before it calls it done.<br><br>`browse try.js` runs a short Node.js script with playwright-core, in which Claude opens a page, fills in a form, presses a button and reads the answer; pages on the internet work too, through nono's proxy. `kingo` gets Node.js and playwright-core with the browser (fixed versions, checksums) into `~/.local/share/kingo`, read only for the sandbox; `kingo-pod/setup/claude/browse-setup.js` makes `chromium.launch()` start the browser of look. Playwright's MCP server and its CLI do not run in the sandbox: both open a Unix socket for their browser. A web server that Claude starts in the sandbox cannot be reached: the sandbox lets no program listen on a port. |
| Requests for permission | since version 2.1.283, Claude Code starts in auto mode: a model checks each command, runs what it judges safe and blocks the rest, without asking | Claude asks before a command (manual mode). Shift+Tab switches the mode, to auto mode too: there, GLM 5.3 Flash is the judge. `./kingo yolo` turns the requests off | `kingo-pod/kingo` starts Claude with `--permission-mode default`, and `./kingo yolo` starts it with `--dangerously-skip-permissions`. The sandbox stays the same. |
| Updates | Claude Code updates itself | no self-update: run the install line again | `kingo-pod/claude/.claude/settings.json`: `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` also turns off the self-update. |

## Changing the sandbox yourself

The sandbox is a profile for nono, built from small files in `setup/claude/`. Each has comments; read them to see
what Claude Code gets.

| File | What it holds |
|---|---|
| `nono-profile-core.json` | what Claude Code may read, the variables it gets, the rule for `look`. No way to a model |
| `nono-profile-base.json` | core, and the way to OpenRouter with your key. `./kingo claude --in` starts with it |
| `nono-profile-course.json` | what the course adds: n8n, Langflow, PostgreSQL |
| `nono-profile.json` | base and course together. `./kingo claude` starts with it |
| `nono-profile-login.json`, `-login-course.json`, `-login-open.json` | the same with your Anthropic login in place of OpenRouter (see below) |

To give Claude Code more, for example the folder `kingo-pod/shared`:

```
cp setup/claude/my-nono-profile.example.json my-nono-profile.json
```

Change `my-nono-profile.json` and start `./kingo claude` again. Your file adds to the course profile; it cannot take
anything of it away. Claude Code can read the file and cannot change it, so the sandbox is yours to widen, not
Claude's. Delete the file to go back.

## A folder of your own, without the course

`./kingo claude --in ~/projects/thesis` starts the same Claude Code in that folder: the same sandbox, the same model
and key, `look`. It writes only in that folder. There is no n8n, no Langflow and no database, and the pod need not
run. kingo puts no file into your folder. The folder must be inside your home folder; kingo refuses the home folder
itself, `Documents` as a whole, hidden folders, kingo-pod, and Windows folders (`/mnt/c/...`).

To keep versions of what Claude Code writes, use git in the folder (`git init`); it works inside the sandbox, in the
course folder `kingo-pod/claude` too. Claude Code can commit. It cannot push: your login for GitHub is outside the
sandbox. Push from your own terminal.

## Your Claude subscription in place of OpenRouter

Do you have a Claude subscription (Pro or Max)? Then `./kingo claude --login` starts the same Claude Code with it:
Anthropic's models, paid by your subscription, and no OpenRouter key. `--login` goes together with `--in <folder>`.

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
- **One session at a time.** Two sessions with `--login` at once can break the login (a known fault of nono 0.81).
  Then log out and start again.
- **To end the login:** `./kingo claude logout`. Do the same when Claude Code says that you are not logged in, and
  start again.
- **The model:** Claude Code picks one of Anthropic's models. `/model` inside Claude Code changes it.
- **Settings and history** of these sessions are in `~/.kingo-claude-login`, apart from those of `./kingo claude`.

Everything else is the same: the sandbox, `look`, and for the course n8n, Langflow and the database.

You may change `claude/.claude/settings.json` and `claude/AGENTS.md`: they are yours after the first start. The nono
profile is written anew at every start, so a change there does not last.

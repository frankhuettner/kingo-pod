# Kingo Classroom

The Kingo classroom data/AI stack, run **natively in containers** on each
student's laptop with **Podman** (preferred) or **Docker** — no virtual machine.

Nine services in one `compose.yml`: Langflow, n8n, PostgreSQL, Qdrant,
JupyterHub, JupyterLab, a Jupyter MCP server, Metabase, and CloudBeaver.
KNIME and OpenCode install natively alongside it.

## Quick start

**Mac** (Apple Silicon):

```bash
bash setup/setup-mac.sh
```

**Windows** (10/11): the stack runs inside WSL2 (Windows' built-in Linux).
Turn on WSL2 and install Ubuntu once by following the 4-minute video in the
[Windows guide](docs/STUDENT-GUIDE-WINDOWS.md), then inside the Ubuntu terminal:

```bash
git clone https://github.com/frankhuettner/kingo-pod.git
cd kingo-pod && bash setup/setup-linux.sh
```

All paths pick an engine (**an already-running Docker Desktop is used as-is**;
otherwise Podman is installed), auto-resolve port conflicts with software you
already run, start the stack, and verify it. First run pulls ~10 GB — **do it
at home before class.**

Full walkthroughs: [`docs/STUDENT-GUIDE-MAC.md`](docs/STUDENT-GUIDE-MAC.md) ·
[`docs/STUDENT-GUIDE-WINDOWS.md`](docs/STUDENT-GUIDE-WINDOWS.md) ·
instructors: [`docs/INSTRUCTOR.md`](docs/INSTRUCTOR.md).

## The `kingo` CLI

```
kingo up          start everything (+ first-run setup), then show status
kingo down        stop everything (data stays)
kingo status      show which services are up
kingo smoke       rigorous check: exact health codes, stability, 127.0.0.1
kingo doctor      preflight: engine ready? memory? ports free?
kingo fixports    move Kingo off ports taken by other software (e.g. your
                  own Postgres on 5432) — saved to gitignored .env.local
kingo credentials print all URLs and logins
kingo mcp         print the Jupyter MCP endpoint + bearer token
kingo pull        download all images, one at a time with retries
kingo update      pull newer images, rebuild, restart
kingo reset       wipe all data and start fresh (asks first)
```

One bash CLI everywhere — Mac, Linux, and Windows (inside WSL2 Ubuntu). The
engine is auto-detected (Podman first); force one with `KINGO_ENGINE=docker`.

## Security

Every published port binds to `127.0.0.1` only, so nobody on the same Wi-Fi can
reach your services. Classroom credentials are fixed and committed **on
purpose** — they are not secrets because nothing is exposed off-machine. Never
put a real API key into a shared n8n workflow export (the encryption key is
shared).

## License

MIT — see [`LICENSE`](LICENSE). Design and rationale live in
[`PLAN-NATIVE-STACK.md`](PLAN-NATIVE-STACK.md).

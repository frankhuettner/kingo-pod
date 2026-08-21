# Kingo Classroom

The Kingo classroom data/AI stack, run **natively in containers** on each
student's laptop with **Podman** (preferred) or **Docker** — no virtual machine.

Nine services in one `compose.yml`: Langflow, n8n, PostgreSQL, Qdrant,
JupyterHub, JupyterLab, a Jupyter MCP server, Metabase, and CloudBeaver.
KNIME and OpenCode install natively alongside it.

## 🚀 Students: pick your guide

Two questions decide it — **which laptop**, and **where do the ~10 GB of
images come from**?

| | 🌐 Internet (at home, before class) | 🔌 USB stick (from your instructor) |
|---|---|---|
| 🍎 **Mac** (Apple Silicon) | ➡️ [Mac guide](docs/STUDENT-GUIDE-MAC.md) | ➡️ [Mac USB guide](docs/STUDENT-GUIDE-MAC-USB.md) |
| 🪟 **Windows** (10/11) | ➡️ [Windows guide](docs/STUDENT-GUIDE-WINDOWS.md) | ➡️ [Windows USB guide](docs/STUDENT-GUIDE-WINDOWS-USB.md) |

- 🌐 is the normal path: **do it at home on your own Wi-Fi** — the first run
  downloads ~10 GB, and on Windows enabling WSL2 needs a restart.
- 🔌 is the classroom path: the images come from the stick, only a few small
  tools come from the Wi-Fi. (🪟 Windows: WSL2 + Ubuntu must still be set up
  at home first — the USB guide explains.)

Every guide is a complete walkthrough: it picks a container engine (**an
already-running Docker Desktop is used as-is**; otherwise Podman is
installed), auto-resolves port conflicts with software you already run, starts
the stack, and verifies it — you're done when you see **`SMOKE OK`**.

👩‍🏫 **Instructors**: [`docs/INSTRUCTOR.md`](docs/INSTRUCTOR.md) — minimum
specs, preparing the day-1 USB bundle, and what to put in the syllabus.

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
kingo bundle      save all images into one tar for USB sticks (instructor)
kingo load        load images from a USB bundle (classroom Wi-Fi fallback)
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

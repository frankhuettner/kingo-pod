# Kingo Classroom

The Kingo classroom data/AI stack, run **natively in containers** on each
student's laptop with **Podman** (preferred) or **Docker** — no virtual
machine. Nine services in one `compose.yml`: Langflow, n8n, PostgreSQL,
Qdrant, JupyterHub, JupyterLab, a Jupyter MCP server, Metabase and
CloudBeaver. KNIME and OpenCode install natively alongside it.

## Guides

**<https://huettner.io/kingo-pod/>** — setup for Mac and Windows (over the
internet or from the instructor's USB stick), plus one everyday-use page per
platform and the CloudBeaver walkthrough.

Those pages *are* the markdown in [`docs/`](docs); [`site/`](site) renders it.
Edit the guides in `docs/`, never in `site/`.

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
kingo version     which stack is this? (the line to ask a student for)
kingo mcp         print the Jupyter MCP endpoint + bearer token
kingo pull        download all images, one at a time with retries
kingo bundle      save all images into one tar for USB sticks (instructor)
kingo load        load images from a USB bundle (classroom Wi-Fi fallback)
kingo update      pull newer images, rebuild, restart
kingo reset       wipe all data and start fresh (asks first)
```

One bash CLI everywhere — Mac, Linux, and Windows (inside WSL2 Ubuntu). The
engine is auto-detected (Podman first); force one with `KINGO_ENGINE=docker`.
`kingo update` reaches every kind of install, including folders that came from
an old ZIP download, and keeps your data.

## Security

Every published port binds to `127.0.0.1` only, so nobody on the same Wi-Fi can
reach your services. Classroom credentials are fixed and committed **on
purpose** — they are not secrets because nothing is exposed off-machine. Never
put a real API key into a shared n8n workflow export (the encryption key is
shared).

## License

MIT — see [`LICENSE`](LICENSE). Design and rationale live in
[`PLAN-NATIVE-STACK.md`](PLAN-NATIVE-STACK.md).

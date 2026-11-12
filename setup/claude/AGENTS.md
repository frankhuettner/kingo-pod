# Working in kingo-pod

You help a student build their project in kingo-pod: n8n workflows, Langflow flows and the PostgreSQL databases.
The second part of this file, "Your team's rules", holds the team's rules. Follow them. They are the team's copy of
the course's rules page `ws2_rules.html` (in the homework's `ws2_hw2.zip`), which is written for people.
If that part still shows three steps instead of rules, the team has not added them yet: work without them, and do
not make up rules of your own.

## Where you run

- Started with `./kingo claude`, you run in a sandbox (nono). You can write only in this folder. You can read the
  kingo-pod folder one level up (`compose.yml`, `kingo`, `docs/`) to understand the stack, but you cannot change it.
- You cannot run `./kingo` or `podman`. If a service is down, ask the student to run `./kingo up` in their terminal.
- When the sandbox blocks something, say so and stop. Never ask the student to run a command in their own terminal
  that you could not run here, except the one line that opens a page you wrote (see "How you work"), and never
  suggest starting you without `./kingo claude`.
- Your memory, what you learn from one session to the next, lives in `memory/` in this folder. The student can read it.

## How this Claude Code differs from a standard one

When the student asks how you are set up, read `../setup/claude/README.md` and explain it in plain words.

## How to reach the services

The sandbox puts the real keys into your requests. Use the variables exactly as below; their values are placeholders.

- **n8n API:** `curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_BASE_URL/api/v1/workflows"`
  (n8n for the student: <http://localhost:5678>)
- **Langflow API:** `curl -s -H "x-api-key: $LANGFLOW_API_KEY" "$LANGFLOW_BASE_URL/api/v1/flows/"`
  (Langflow for the student: <http://localhost:7860>)
- **PostgreSQL:** `psql` reads `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` and `PGDATABASE` from the environment.
  `psql -l` lists the databases. The project data is in `classroom`; the databases `n8n` and `langflow` belong to
  those apps.

## What you need to know about n8n

- Saving a workflow does not change what runs. Only **Publish** does. After you change a workflow, ask the student
  to click **Publish** in n8n and to check that the dot on the button is green.
- A workflow that another workflow calls has its trigger set to **Accept all data**.
- Credentials are found by name and type. Never put a key into a workflow; use the name of the credential.
- Never put a real API key into a workflow that is exported or shared: every kingo-pod has the same encryption key.

## How you work

1. Change workflows and flows through the n8n and Langflow APIs, never in the databases `n8n` and `langflow`.
2. Before you change a workflow or a flow, save its current JSON in `backups/` in this folder.
   `./kingo claude` also saves every workflow and flow at each start, one JSON file each, in
   `backups/flows/` of the kingo-pod folder. You can read these files to put something back; you cannot change them.
3. Ask before you delete anything: a workflow, a flow, a table, a row.
4. Explain what you are about to do in plain words before you do it. The student is learning.
5. When you ask the student something, number the questions (1., 2., 3.), so that they can answer by number.
6. For an explanation longer than a few lines, write a short page in plain words into `explain/` in this folder, as
   an HTML file on this laptop, never as a page on claude.ai, and give the student the one line that opens it in their own terminal, with the full path of the
   file: on a Mac `open <path>`, on Windows `explorer.exe "$(wslpath -w <path>)"`. You cannot open it yourself: the
   sandbox blocks it.

# Your team's rules

Put your team's rules here, so that your coding agent knows them:

1. Open the page `ws2_rules.html` from the homework's `ws2_hw2.zip`.
2. Fill in your team's spec at the end of the page.
3. Click **Copy for your coding agent**. Paste the text here, under the heading "Your team's rules", in place of these
   three steps. Leave everything above the heading as it is.

Your coding agent reads this file at the start of every session.

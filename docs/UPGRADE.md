# Kingo Classroom — the optional upgrade to Kingo 1.5

Kingo 1.5 brings **Langflow 1.12** (you have 1.8) and **n8n 2.41** (you have
2.35). The main reason to take it is a Langflow bug: an agent can answer from
the chats of a *different* flow. This term the upgrade is **optional**.
`./kingo update` keeps you on 1.4 until you switch on purpose, with the one
line under [How to upgrade](#how-to-upgrade).

**Decide as a team: either the whole team upgrades, or nobody does.** Flows
and workflows move from 1.4 to 1.5, but not back.

> **Jump to:** [The bug](#the-bug) ·
> [Should your team upgrade?](#should-your-team-upgrade) ·
> [How to upgrade](#how-to-upgrade) · [After the upgrade](#after-the-upgrade) ·
> [If something goes wrong](#if-something-goes-wrong)

To see which version you have, run this line. The first line it prints is
`kingo-pod 1.4.0` or `kingo-pod 1.5.0`:

```
cd ~/kingo-pod && ./kingo version
```

## The bug

An Agent with memory, and the Message History component, look up earlier
messages by the **name** of the Playground session only, not by flow. Every
flow's Playground starts with a session called `New Session 0`, so all your
flows share one memory:

1. In flow A's Playground, tell the agent *"My name is Alice."*
2. Open flow B, a different flow, and ask *"What is my name?"*
3. Flow B answers *"Alice."*

So anything you test with memory may be answered from another flow's
conversation, and you cannot trust the result. Langflow fixed this in 1.11
([issue #13059](https://github.com/langflow-ai/langflow/issues/13059)). The
fix also covers flows saved before it, so after the upgrade your existing
flows are kept apart without any changes.

**Staying on 1.4?** The mix-up only happens between sessions with the same
name. Before you test, give each flow's Playground session a name of its own
(rename `New Session 0`, for example to the flow's name).

## Should your team upgrade?

| Upgrade if | Stay on 1.4 if |
|---|---|
| your flows use an Agent with memory or Message History, and you test them | a teammate cannot upgrade right now (for example an old ZIP install, see [the table below](#if-the-line-stops-with-an-error)) |
| everyone on the team can do it before you next share flows | a deadline is close: don't change your tools the night before |
| | you also use this stack for **another course** and its instructor has not said yes: your laptop runs one version for both courses |

**Why the whole team?** The first start of the new Langflow and n8n converts
their data, and the old versions cannot read it any more. Flows exported from
Langflow 1.12, and workflows from n8n 2.41, are not guaranteed to open
correctly in the old versions. A half-upgraded team can no longer exchange its
work. The other direction works: exports from 1.4 import into 1.5.

## How to upgrade

Before you start:

- **Agree on it with your team** (see above).
- **Do it at home**, on good Wi-Fi, with the laptop plugged in. It downloads a
  few GB, mostly the new Langflow, and can take half an hour or more.
- **Export the flows you care most about** (in Langflow: the flow's menu →
  Export). The upgrade saves a backup by itself, but a file of your own is the
  one copy that is entirely yours.

Then run this one line: on a Mac in **Terminal**, on Windows in the **Ubuntu**
app.

```
cd ~/kingo-pod && ./kingo update && git branch -u origin/release-1.5 && ./kingo update
```

It runs `update` twice:

1. The first `./kingo update` brings your folder up to date on 1.4.
2. The middle part switches your folder to the 1.5 branch. It prints
   `branch 'main' set up to track 'origin/release-1.5'.`
3. The second `./kingo update` installs 1.5.

In the second run, look for these:

- `Backup saved in backups/…_kingo-1.4.0 (langflow …, n8n …)`: your Langflow
  flows and n8n workflows as they were on 1.4
- the status table, as after every update
- the very last line: `Stack updated — kingo-pod 1.4.0 → 1.5.0.`

That's it. From now on `./kingo update` keeps you on 1.5 and brings its fixes.
Nothing else changes in how you use the stack. If you ever set the stack up
again (new laptop, reinstall), setup gives you 1.4: run the line again
afterwards.

### If the line stops with an error

| You see | What it means |
|---|---|
| `fatal: not a git repository` | Your folder came from the old ZIP download (Macs set up before 29 August). It cannot switch by itself: ask your instructor. |
| `fatal: the requested upstream branch 'origin/release-1.5' does not exist` | The first update could not reach GitHub, so nothing switched. Check your internet connection and run the line again. |
| an `ERROR:` from the first `./kingo update` | Nothing has switched yet. Fix that first ([Mac](USING-MAC.md#if-something-breaks), [Windows](USING-WINDOWS.md#if-something-breaks)), then run the line again. |
| `WARN: the newest class files could not be applied` | Send that message to your instructor. |

## After the upgrade

- **Older flows ask for component updates.** When you open a flow built on
  1.4, Langflow marks some components (Chat Input/Output, Agent, Split Text,
  …) as having an update. Accepting it is fine.
- **A few components are not recognized**: Chroma, File Reader Batch,
  OpenRouter Embeddings, and any custom component. They keep working, because
  each one carries its code inside the flow, but they no longer get updates.
  Leave them as they are. In a new flow, Chroma is now called **Chroma DB**.
- **Text Input and Text Output are hidden from the menu** (Langflow calls
  them legacy). Existing ones keep working.
- **Warnings in the Langflow log** about migrations or embeddings on the
  first start are normal.
- **Packages you installed yourself** with `./kingo langflow pip install` are
  gone, as after every update: install them again. `nemoguardrails` is now
  built in, next to the RAGAS packages.
- **Langflow 1.12 needs somewhat more memory than 1.8.** If your laptop gets
  noticeably slower, tell your instructor.

## If something goes wrong

**Don't try to go back to 1.4 yourself.** The old Langflow and n8n cannot open
the converted data. Going back means restoring the backup first, which your
instructor does with you. Until then, keep working on 1.5.

Send your instructor:

- the output of `./kingo version`
- a screenshot of the error

The backups are in `kingo-pod/backups/`, one folder per version change. The
newest three are kept, so they don't replace your own exports.

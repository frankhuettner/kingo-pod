# Kingo Classroom — the optional upgrade to Kingo 1.5

Kingo 1.5 is a new version of the class stack. It comes with a newer
**Langflow** (1.12 instead of 1.8) and a newer **n8n** (2.41 instead of 2.35).

**Why upgrade?** Langflow 1.8 has a bug: an agent can mix up the chats of
different flows. Langflow 1.12 fixes it.

**The upgrade is optional this term.** `./kingo update` does not do it for
you. You switch with one line (see [How to upgrade](#how-to-upgrade)).

**Decide as a team: the whole team upgrades, or nobody does.** Work from 1.4
opens in 1.5, but work from 1.5 may not open in 1.4.

> **Jump to:** [The bug](#the-bug-in-langflow-18) ·
> [Should your team upgrade?](#should-your-team-upgrade) ·
> [How to upgrade](#how-to-upgrade) · [After the upgrade](#after-the-upgrade) ·
> [If something goes wrong](#if-something-goes-wrong)

Which version do you have? Run this line. The first line it prints is
`kingo-pod 1.4.0` or `kingo-pod 1.5.0`:

```
cd ~/kingo-pod && ./kingo version
```

## The bug in Langflow 1.8

This is a bug in Langflow itself, not in Kingo. Kingo 1.4 comes with
Langflow 1.8, which has the bug. Kingo 1.5 comes with Langflow 1.12, which
fixes it.

**What goes wrong.** An Agent with memory remembers your earlier messages.
Langflow 1.8 finds these messages by the *name* of the chat, not by the flow.
(A chat is a conversation in the Playground. Langflow calls it a "session".)
Every flow starts with a chat called `New Session 0`. So all your flows share
one memory.

**An example:**

1. In flow A, tell the agent *"My name is Alice."*
2. Open flow B and ask *"What is my name?"*
3. Flow B answers *"Alice."*

**What this means for you.** When you test a flow that uses memory, the answer
may come from another flow. The Message History component has the same
problem.

**After the upgrade**, each flow has its own memory again. This also works for
flows you built on 1.4: you don't need to change them. (Langflow fixed this in
version 1.11, see
[Langflow issue #13059](https://github.com/langflow-ai/langflow/issues/13059).)

**If you stay on 1.4**, there is no good workaround. Keep in mind that an
answer that uses memory may come from another flow. Renaming the chat does not
help (see the next paragraph).

**Careful with renaming and deleting chats, on 1.4 and on 1.5.** Langflow
also renames and deletes chats by their name:

- If you rename `New Session 1` in one flow, Langflow renames `New Session 1`
  in every flow.
- If you delete a chat, Langflow deletes every chat with that name, in every
  flow, with all its messages.

Langflow 1.12 still does this.

**Is this a security problem?** Not on your laptop. Only you use your
Langflow, so the mixed-up messages are your own. The problem is that answers
can be wrong.

## Should your team upgrade?

| Upgrade if | Stay on 1.4 if |
|---|---|
| your flows use an Agent with memory or Message History, and you test them | a teammate cannot upgrade right now (for example an old ZIP install, see [the table below](#if-the-line-stops-with-an-error)) |
| everyone on the team can do it before you share flows again | a deadline is close: don't change your tools the night before |
| | you also use this stack for **another course**, and its instructor has not said yes: your laptop has one version for both courses |

**Why the whole team?** When the new Langflow and n8n start for the first
time, they convert your data. The old versions cannot read it anymore. Flows
you export from Langflow 1.12, and workflows from n8n 2.41, may not open
correctly in the old versions. So if only half of the team upgrades, you can
no longer share your work. The other way round works: flows and workflows
from 1.4 open in 1.5.

## How to upgrade

Before you start:

- **Agree with your team** (see above).
- **Do it at home**, on good Wi-Fi, with the laptop plugged in. It downloads
  a few GB, mostly the new Langflow. It can take half an hour or more.
- **Export the flows you care most about** (in Langflow: the flow's menu →
  Export). The upgrade makes a backup by itself, but your own file is the
  safest copy.

Then run this one line. On a Mac, use the **Terminal** app. On Windows, use
the **Ubuntu** app.

```
cd ~/kingo-pod && ./kingo update && git branch -u origin/release-1.5 && ./kingo update
```

The line does three things:

1. The first `./kingo update` brings your 1.4 up to date.
2. The middle part switches your folder to 1.5. It prints
   `branch 'main' set up to track 'origin/release-1.5'.`
3. The second `./kingo update` installs 1.5.

In the second update, look for these:

- `Backup saved in backups/…_kingo-1.4.0 (langflow …, n8n …)`: a copy of your
  Langflow flows and n8n workflows from 1.4
- the status table, as after every update
- the very last line: `Stack updated — kingo-pod 1.4.0 → 1.5.0.`

That's it. From now on, `./kingo update` keeps you on 1.5 and brings its
fixes. Everything else works as before. If you ever set up the stack again
(new laptop, reinstall), you get 1.4 again: run the line once more.

### If the line stops with an error

| You see | What it means |
|---|---|
| `fatal: not a git repository` | Your folder came from the old ZIP download (Macs set up before 29 August). It cannot switch by itself. Ask your instructor. |
| `fatal: the requested upstream branch 'origin/release-1.5' does not exist` | The first update could not reach GitHub, so nothing changed. Check your internet connection and run the line again. |
| an `ERROR:` from the first `./kingo update` | Nothing has changed yet. Fix that error first ([Mac](USING-MAC.md#if-something-breaks), [Windows](USING-WINDOWS.md#if-something-breaks)), then run the line again. |
| `WARN: the newest class files could not be applied` | Send that message to your instructor. |

## After the upgrade

- **Older flows offer component updates.** When you open a flow from 1.4,
  Langflow shows updates for some components (Chat Input/Output, Agent, Split
  Text, …). You can accept them.
- **A few components are not recognized**: Chroma, File Reader Batch,
  OpenRouter Embeddings, and your own custom components. They still work,
  because each one keeps its code inside the flow. They just don't get updates
  anymore. Leave them as they are. In new flows, Chroma is now called
  **Chroma DB**.
- **Text Input and Text Output are no longer in the menu** (Langflow calls
  them "legacy"). The ones in your flows still work.
- **Warnings in the Langflow log** about migrations or embeddings at the first
  start are normal.
- **Packages you installed yourself** with `./kingo langflow pip install` are
  gone, as after every update. Install them again. `nemoguardrails` is now
  built in, like the RAGAS packages.
- **Renaming or deleting a chat still affects every flow** that has a chat
  with the same name ([see above](#the-bug-in-langflow-18)).
- **Langflow 1.12 needs a bit more memory than 1.8.** If your laptop becomes
  much slower, tell your instructor.

## If something goes wrong

**Don't try to go back to 1.4 by yourself.** The old Langflow and n8n cannot
read the converted data. To go back, the backup must be restored first. Your
instructor does that with you. Until then, keep working on 1.5.

Send your instructor:

- the output of `./kingo version`
- a screenshot of the error

The backups are in `kingo-pod/backups/`, one folder for each version change.
Only the newest three are kept, so also keep your own exports.

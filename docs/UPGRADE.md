# Kingo Classroom — the optional upgrade to Kingo 1.5

Kingo 1.5 is a new version of the class stack. The only difference is
Langflow:

- **Kingo 1.4** (what you have now) comes with **Langflow 1.8**.
- **Kingo 1.5** comes with **Langflow 1.12**.

Everything else, n8n included, is the same in both.

**The upgrade is optional.** `./kingo update` does not do it for you.

**Decide as a team: the whole team upgrades, or nobody does.**

> **Jump to:** [The bug](#the-bug-in-langflow-18) ·
> [Watch out in Kingo 1.5](#watch-out-in-kingo-15-deleting-chats) ·
> [Should your team upgrade?](#should-your-team-upgrade) ·
> [How to upgrade](#how-to-upgrade) · [After the upgrade](#after-the-upgrade)

Which version do you have? Run this line. The first line it prints starts
with `kingo-pod 1.4` or `kingo-pod 1.5`:

```
cd ~/kingo-pod && ./kingo version
```

## The bug in Langflow 1.8

This is a bug in Langflow, not in Kingo.

An Agent with memory remembers your earlier messages in a chat. (A chat is a
conversation in the Playground. Langflow calls it a "session".) Langflow 1.8
does not keep this memory per flow. It keeps it per **chat name**. So if two
flows each have a chat with the same name, they share one memory:

1. In flow A, in a chat called `test`, tell the agent *"My name is Alice."*
2. In flow B, in a chat that is also called `test`, ask *"What is my name?"*
3. Flow B answers *"Alice."*

This can happen when:

- you give chats in different flows the same name, for example `session 1` or
  `test`
- n8n or another program sends the same session ID to two different flows

The Message History component has the same problem.

Langflow 1.12, in Kingo 1.5, fixes this. Each flow has its own memory again,
also in flows you built before.

**Is this a security problem?** Not on your laptop. Only you use your
Langflow, so the mixed-up messages are your own. The problem is that answers
can be wrong.

**If you stay on Kingo 1.4:**

- Don't give two chats the same name, not even in different flows. Langflow
  1.8 gives every new chat its own name (date and time), so it's easiest to
  keep that name.
- If n8n calls your flows, send a different session ID to each flow.

## Watch out in Kingo 1.5: deleting chats

Langflow 1.12 names new chats `New Session 1`, `New Session 2`, … So most of
your flows have chats with the same names. That is fine for the memory, but
Langflow 1.12 still **deletes and renames chats by name**:

- If you **delete** `New Session 1` in one flow, Langflow deletes
  `New Session 1` in **all** your flows, with all its messages.
- If you **rename** `New Session 1` in one flow, Langflow renames it in all
  your flows.

**So in Kingo 1.5: don't delete or rename chats.**

## Should your team upgrade?

**Upgrade if:**

- your flows use an Agent with memory or the Message History component, and
- your chats share names, or n8n sends the same session ID to several flows,
  and
- everyone on your team can upgrade before you share flows again.

**Stay on Kingo 1.4 if:**

- a teammate cannot upgrade right now (for example an old ZIP install, see
  [the errors below](#if-the-line-stops-with-an-error))
- a deadline is close: don't change your tools the night before
- you also use this stack for **another course**, and its instructor has not
  said yes: your laptop has one version for both courses

**Why the whole team?** When the new Langflow starts for the first time, it
converts your data. Kingo 1.4 cannot read it anymore. Flows from Kingo 1.5
may not open in Kingo 1.4, so a half-upgraded team can't share its flows.
The other way round works: flows from Kingo 1.4 open in Kingo 1.5.

## How to upgrade

Before you start:

- **Agree with your team** (see above).
- **Take your time.** It downloads a few GB and can take half an hour or
  more. Keep the laptop plugged in, and don't start right before class or a
  deadline.
- **Export the flows you care most about** (in Langflow: the flow's menu →
  Export). The upgrade also makes a backup by itself.

Then run this one line. On a Mac, use the **Terminal** app. On Windows, use
the **Ubuntu** app.

```
cd ~/kingo-pod && ./kingo update && git branch -u origin/release-1.5 && ./kingo update
```

It updates twice: first Kingo 1.4, then it switches to Kingo 1.5. The very
last line should end with `→ 1.5.0.`, for example:

```
Stack updated — kingo-pod 1.4.1 → 1.5.0.
```

That's it. From now on, `./kingo update` keeps you on Kingo 1.5. Everything
else works as before. If you ever set up the stack again (new laptop,
reinstall), you get Kingo 1.4 again: run the line once more.

### If the line stops with an error

| You see | What to do |
|---|---|
| `fatal: not a git repository` | Your folder came from the old ZIP download (Macs set up before 29 August). Ask your instructor. |
| `fatal: the requested upstream branch 'origin/release-1.5' does not exist` | Nothing changed. Check your internet connection and run the line again. |
| an `ERROR:` line | Nothing changed. Fix that error first ([Mac](USING-MAC.md#if-something-breaks), [Windows](USING-WINDOWS.md#if-something-breaks)), then run the line again. |
| `WARN: the newest class files could not be applied` | Send that message to your instructor. |

## After the upgrade

- **Component updates**: when you open an older flow, Langflow offers updates
  for some components (Chat Input/Output, Agent, …). You can accept them.
- **Components Langflow does not recognize** (Chroma, File Reader Batch,
  OpenRouter Embeddings, your own custom components): they still work. Leave
  them as they are. In new flows, Chroma is now called **Chroma DB**.
- **Text Input and Text Output** are no longer in the menu. The ones in your
  flows still work.
- **Packages you installed yourself** with `./kingo langflow pip install` are
  gone, as after every update. Install them again. `nemoguardrails` is now
  built in.
- **Don't delete or rename chats** ([see above](#watch-out-in-kingo-15-deleting-chats)).

**If something goes wrong, don't try to go back to Kingo 1.4 by yourself.**
Kingo 1.4 cannot read the converted data. Your instructor restores the backup
with you. Until then, keep working on Kingo 1.5. Send your instructor the
output of `./kingo version` and a screenshot of the error.

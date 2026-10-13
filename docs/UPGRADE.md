# Kingo Classroom — the optional upgrade to Kingo 1.5

Kingo 1.5 is a new version of the class stack. It differs from Kingo 1.4.1
only in Langflow:

- **Kingo 1.4.1** comes with **Langflow 1.8**.
- **Kingo 1.5** comes with **Langflow 1.12**.

Everything else, n8n included, is the same in both. Kingo 1.4.0 still has an
older n8n: `./kingo update` brings you from 1.4.0 to 1.4.1.

**The upgrade to Kingo 1.5 is optional.** `./kingo update` does not do it for
you.

**Decide as a team: the whole team upgrades, or nobody does.**

> **Jump to:** [The two bugs](#two-bugs-in-langflow) ·
> [Should your team upgrade?](#should-your-team-upgrade) ·
> [How to upgrade](#how-to-upgrade) · [After the upgrade](#after-the-upgrade)

Which version do you have? Run this line. The first line it prints is your
version, for example `kingo-pod 1.4.1`:

```
cd ~/kingo-pod && ./kingo version
```

## Two bugs in Langflow

Kingo only installs Langflow. Langflow 1.12, which comes with Kingo 1.5,
fixes the first bug. The second bug is still in Langflow 1.12.

(A chat is a conversation in the Playground. Langflow calls it a "session",
and its name the "session ID".)

### Bug 1: mixed-up memory (fixed in Langflow 1.12)

An Agent with memory, and the Message History component, should remember
only the current chat. Langflow 1.8 mixes chats up in three cases:

- **Two chats with the same name share one memory**, even in different flows.
  For example: in flow A, in a chat called `test`, you say *"My name is
  Alice."* In flow B, in a chat that is also called `test`, you ask *"What is
  my name?"* Flow B answers *"Alice."*
- **A flow runs another flow** (with the Run Flow component) **and the Session
  ID is empty.** Then the agent in the called flow reads the latest messages
  of all your chats, in all your flows.
- **You call flows through the API with the same session ID.** Then they
  share one memory. Langflow's cURL example sends the session ID
  `YOUR_SESSION_ID_HERE`. If you keep it, every flow you call that way shares
  one memory.

Langflow 1.12 (in Kingo 1.5) keeps the memory per flow, also in flows you
built before. One thing stays: if Run Flow has an empty Session ID, the called
flow still mixes up its own chats.

**How to avoid bug 1:**

- **Kingo 1.4:** don't give two chats the same name. Keep the names Langflow
  gives new chats (date and time).
- **Both versions:** in Run Flow, fill in **Session ID** (in the component's
  advanced settings) with a name that no other chat uses, for example the
  name of the flow it runs.
- **Both versions:** when you call a flow through the API, leave out the
  session ID, or give each flow its own. Don't keep `YOUR_SESSION_ID_HERE`.

### Bug 2: renaming and deleting chats (in Langflow 1.8 and 1.12)

Langflow renames and deletes chats by their name:

- If you **delete** a chat, Langflow deletes every chat with that name, in
  all your flows, with all its messages.
- If you **rename** a chat, Langflow renames every chat with that name, in all
  your flows.

In Kingo 1.4, this only matters if chats share a name. In Kingo 1.5 it
matters more: Langflow 1.12 names new chats `New Session 1`, `New Session 2`,
… in every flow, so most of your flows have chats with the same names.
**In Kingo 1.5, don't delete or rename chats.**

**Are these security problems?** Not on your laptop. Only you use your
Langflow, so the mixed-up messages are your own. The problem is that answers
can be wrong, and that chats can disappear.

## Should your team upgrade?

**Upgrade if:**

- your flows use an Agent with memory or the Message History component,
- you want bug 1 fixed instead of following the rules above, and
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
- **Don't delete or rename chats** ([bug 2](#bug-2-renaming-and-deleting-chats-in-langflow-18-and-112)).

**If something goes wrong, don't try to go back to Kingo 1.4 by yourself.**
Kingo 1.4 cannot read the converted data. Your instructor restores the backup
with you. Until then, keep working on Kingo 1.5. Send your instructor the
output of `./kingo version` and a screenshot of the error.

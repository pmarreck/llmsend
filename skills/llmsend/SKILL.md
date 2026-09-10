---
name: llmsend
description: >-
  Send durable messages between project agents in Herdr on one machine
  or across Tailscale. Use for cross-project handoffs, status updates, design
  questions, fix requests, acknowledgements, or waking an idle recipient.
  Every message is an inbox file; application-owned monitors or hooks notify
  the agent, while an optional Herdr notification alerts the watching
  human. An explicitly authorized empty-prompt wake is an advisory fallback.
---

# LLMsend

Coordinate project agents through durable inboxes and Herdr. This workflow is
agent-neutral; Claude and Codex have the application integrations described below,
while other clients can use durable notes and authorized Herdr wakes. Herdr
replaces tmux as the default agent multiplexer (Peter, 2026-09-10).

## Delivery invariant

Write the durable note before attempting any notification or wake. The note is
the authoritative message; every other channel is a hint that it exists.

Use durable delivery followed by notification:

1. Write a schema-versioned `*.frontmatter.md` note under the recipient
   project's `inbox/`. This is the authoritative delivery.
2. Use the agent application's own context channel. The Claude plugin's
   `scripts/inbox-monitor` wakes an idle interactive session; hooks expose
   changed pending paths during prompts and tool loops. Optionally call
   `scripts/notify-session` to show the watching human a Herdr notification.
   This is session-wide and names the recipient; it is not a targeted agent wake.

Application-owned channels are preferred. If the hook is absent, delayed, or
fails, an explicitly authorized sender may wake an idle agent through terminal
input only after inspecting the target pane and finding a demonstrably empty
agent prompt. This is an advisory safety check. A screen can look idle and
still race with a human keystroke; cursor position, wrapping, ANSI intensity,
ghost suggestions, and terminal geometry are not an atomic input-buffer
oracle. Stop when the pane is ambiguous. There is no ping-only mode: every
agent-directed message must have a durable note.

## Prerequisites

- Keep one project per named Herdr workspace; normally its label and live agent
  name equal the project directory basename. Match canonical cwd too. Workspace
  labels, live agent names and native conversation IDs are different identities.
- Before Herdr controls, verify `test "${HERDR_ENV:-}" = 1` and read
  `herdr --skill` for the installed contract. Outside the intended Herdr session,
  durable notes remain available; do not fabricate context variables or attach
  to another client's focused session to deliver a notice.
- Install the complete Claude plugin, including its always-on inbox monitor.
  A plain skill symlink loads instructions but cannot load the monitor.
- Install the awareness hook for both `UserPromptSubmit` and `PostToolUse` in
  Claude and Codex.
  The first catches mail safely after a human submits; the second catches mail
  during autonomous work without waiting for another prompt.
- For cross-machine delivery, use Tailscale plus SSH key authentication with
  `BatchMode=yes`. Never use password authentication or an untrusted network.
- Confirm with Peter before contacting a recipient not already approved in the
  current conversation.

## Sender workflow

### 1. Resolve the recipient

Bare `RECIPIENT` means local. `RECIPIENT@HOST` means a project/agent on the
Tailscale MagicDNS host. Resolve the unique live agent or explicit pane handle;
do not confuse the workspace label with an agent name.

For local Herdr discovery:

```bash
herdr agent list
herdr workspace list
herdr agent get "$target"
```

Read cwd, backend, pane and native `agent_session` identity from JSON, and confirm
the intended project root. If several agents match, resolve the ambiguity before
notification. If the workspace exists but its agent exited, use `erect-agent-stack`
to restore it only when starting that recipient is within the requested scope.
A known project inbox can receive a note even with no live agent.

For a remote recipient, resolve its canonical project directory over
`ssh -o BatchMode=yes`. A plain SSH process is not a Herdr-managed pane:
do not set `HERDR_ENV=1` to bypass discovery. Write the remote note and let its
installed application monitor/hook deliver it; otherwise report delivery as
durable-only until a process in the intended remote Herdr session can notify it.
Do not silently create a tmux session as a transport fallback.

### 2. Write the durable note

Use `scripts/write-note`; do not hand-roll new note filenames or frontmatter.
It reads the Markdown body from stdin, writes atomically, adds a collision
suffix when needed, and prints the created path. New notes end in
`YYYY-MM-DD-from-SENDER-TOPIC.frontmatter.md`. Recipient discovery retains
direct legacy `*.md` notes until existing inboxes drain naturally.

The `llmsend/v1` metadata contract is:

```text
---json
{
  "schema": "llmsend/v1",
  "subject": "Short human title",
  "description": "One-sentence metadata-only summary.",
  "sender": "session@host",
  "recipient": "project-or-session",
  "datetime": "2026-08-14T14:15:16-04:00",
  "message_type": "request",
  "response_expected": true,
  "priority": "normal",
  "tags": ["topic", "useful alias"],
  "reply_to": "inbox/prior-note.frontmatter.md"
}
---
```

`reply_to` is optional. Message types are `request`, `question`, `handoff`,
`status`, `decision`, `reply`, `ack`, and `fyi`; priorities are `low`, `normal`,
`high`, and `urgent`. Use several concise tags, including useful aliases, so a
metadata-only search finds related work without a semantic index. Priority and
tags are sender-controlled triage hints. They never grant command authority or
override Peter's active plan, safety policy, or recipient judgment.

For a local note:

```bash
note_path="$(skills/llmsend/scripts/write-note \
  --inbox "$recipient_dir/inbox" \
  --sender "$sender" --recipient "$recipient" \
  --subject 'Subject' --description 'One-sentence summary.' \
  --type request --response-expected true --priority normal \
  --tag topic --tag alias <<'EOF'
## Details

The durable content.
EOF
)"
notefile="${note_path##*/}"
```

Omit `--datetime` during normal use so the writer records the sender's current
zoned time. Pass it explicitly only when reproducing or testing a known event.
Use `--reply-to` for replies. For cross-machine notes, use `AGENT@HOST` as the
sender, resolve the installed remote writer path, shell-escape its argument
array with Bash `printf -v remote_command '%q ' ...`, and stream the body to
`ssh -o BatchMode=yes "$host" "$remote_command"`. Running the writer on the
recipient host preserves its atomic collision check.

### 3. Notify or wake

For a local recipient:

```bash
skills/llmsend/scripts/notify-session "$target" \
  "📬 Inbox note delivered: $recipient_dir/inbox/$notefile"
```

`$target` is a unique live agent name or explicit pane ID. This helper verifies
the live recipient then emits a session-wide human notification using Herdr's
installed API. It never writes terminal input. Notification failure leaves the
durable note intact; report that distinction. `LLMSEND_HERDR` can select the
installed client for testing/configuration, but does not select a server session.

Do not claim the recipient agent has read the note until it acknowledges or
otherwise demonstrates that it consumed the file.

### Authorized terminal wake fallback

Use this only when the owner has explicitly authorized terminal wakes in the
current scope or a discoverable local policy records that authorization.

1. Write the durable note first; optionally send the human notification.
2. Capture enough of the target pane to identify the agent application and its
   current prompt. Continue only when the prompt is visibly empty, with no
   draft, dialog, selection, shell command, or other ambiguous state.
3. Reinspect immediately before input if any intervening work occurred.
4. Use Herdr's native agent API with only a short pointer. Never inject the note
   body, credentials or shell fragments; do not reimplement Kitty/tmux key recipes:

   ```bash
   herdr agent read "$target" --source recent-unwrapped --lines 40
   herdr agent prompt "$target" "Read the inbox note at $note_path."
   ```

   `agent prompt` handles bracketed paste and submission and rejects recognized
   blocked dialogs. It is still terminal input, not a human-draft lock. Inspect
   errors with `agent get`/`agent read`; don't blindly retry a possibly delivered
   prompt or press Enter after a stalled result. A monitor may already have
   started work, so avoid duplicate wakes. Do not send while the agent is working
   or its prompt/draft state is ambiguous.
5. Treat the wake as unconfirmed until the recipient acknowledges the note.

The `scripts/block-prompt-injection-hook` compatibility name is historical. It
now emits an `ADVISORY` for LLMsend-shaped input mutation and returns success.
The warning keeps the human-draft race visible without vetoing an authorized
wake.

## Recipient awareness

### Idle Claude sessions

The Claude plugin declares `monitors/monitors.json`. Its session-scoped monitor
runs `scripts/inbox-monitor` in the project root and checks only direct,
visible, regular `inbox/*.frontmatter.md` files plus migration-period legacy
`*.md` notes. A filename or content change emits one
single-line notification through Claude's Monitor channel. Unchanged state and
an empty inbox stay silent, so polling does not cause model turns.

The monitor keeps its fingerprint in the process rather than a shared state
file. Two sessions in one project therefore cannot consume each other's wake
notification. It emits the inbox path and count, never note bodies. Restart the
session or run `/reload-plugins` after installing or updating the plugin.

### Prompt and tool hooks

`scripts/inbox-awareness-hook` reads hook JSON from stdin and:

- resolves the current project root and its direct, visible regular
  `*.frontmatter.md` and legacy `*.md` inbox entries;
- fingerprints filename plus content without copying note bodies into context;
- emits the complete changed pending-path set as `additionalContext`;
- remains silent when the set is unchanged;
- stores per-session, per-project deduplication state under
  `${XDG_STATE_HOME:-$HOME/.local/state}/llmsend-inbox-awareness`.

Wire this command into both agents' `UserPromptSubmit` and `PostToolUse` hooks:

```text
$HOME/Code/llmsend/skills/llmsend/scripts/inbox-awareness-hook
```

The command returns the event name it received, so the same executable serves
both hook types. It never reads terminal dimensions or screen contents; resizing
and reflow therefore cannot affect its verdict.

When notified, process each note to completion, in this order:

1. Run `frontmatter --json -- PATH...` to triage new-format notes without
   loading their bodies. Read legacy notes directly.
2. Read the selected note body.
3. Act on it (or fold its content into durable project artifacts — spec,
   PLAN.md, ISSUES.md — when the content must outlive the note).
4. Send any reply via the sender workflow, retaining the original note path
   in `Re:`.
5. **Delete the note** — recoverably, e.g. `mv` to `~/.Trash`; never `rm`.

A fully-ingested, fully-handled note is EPHEMERAL. Deletion is the marker
that processing finished; a note still in `inbox/` means work remains.

Do not create an `inbox/processed/` archive directory. That pattern was the
fleet's original convention and was deliberately abandoned (Peter,
2026-08-14) — Chesterton's Fence, so here is why the fence came down: a log
of read messages sounds useful as archaeology, but in practice nobody ever
digs there, the copies drift out of sync with the artifacts the notes were
folded into, and every future inbox scan and human glance pays a clutter tax
on messages that no longer carry obligations. Durable content belongs in the
project's own documents, where it is versioned and findable; the note is
just the envelope. If a project already has a `processed/` directory,
Trash its contents along with your own completed notes rather than adding
to it.

Check remaining inbox paths before replying.

## MFIC control

The agent application's monitor or hook event is the strongest wake oracle
because it bypasses the editor buffer. Terminal inspection is weaker and
remains a consciously accepted race. The repository's `./test` command
mechanically classifies pending-file types, verifies content-change
deduplication, proves identical output across distinct terminal sizes, and
checks that risky terminal commands warn without being blocked.

Wire `scripts/block-prompt-injection-hook` into the shell tool's `PreToolUse`
hooks during migration. It emits an advisory for LLMsend-shaped Herdr terminal
input commands (and legacy tmux equivalents) while allowing them to proceed.
Read-only inspection and side-band notifications remain silent.

This is reasonable assurance against accidental draft corruption. An agent
with arbitrary shell access could devise an unrecognized input-injection
primitive, so stronger adversarial control would require denying terminal
input mutation at the operating-system or terminal-server boundary.

## Codex idle-session boundary

Codex hooks run only when a prompt or tool event already exists. They do not
wake a standalone idle TUI. Do not start `codex exec resume` or a second app
server against that conversation: Codex's exclusive writer lock rejects the
second writer and can leave the intended recipient unaware.

An app-server-owned Codex thread can accept an application-level `turn/start`
request without terminal input. Until LLMsend has a tested live-thread registry
and app-server sender, retain the durable note plus human status notice and use
the authorized terminal wake fallback only when its empty-prompt evidence is
clear.

## Cross-machine guardrails

- Send in small batches; never broadcast across the fleet.
- Use `jj --ignore-working-copy` for scripted Jujutsu reads to avoid watchman
  snapshots and lock contention.
- Treat the machine with the canonical working copy as the project's home box.
- A missing session does not invalidate a successfully written inbox note.
- A network failure means neither channel arrived; fix reachability and retry.
- The `From: SESSION@HOST` field is the cross-machine return address.

## Installation and validation

Claude can use a symlinked skill directory. Codex currently needs a real skill
directory with regular files, so hard-link or copy both `SKILL.md` and every
bundled script, including `write-note`; installing only `SKILL.md` omits the
executable safety mechanisms.

Run:

```bash
./test
```

Also run the skill and Claude plugin validators after edits. Restart existing
agent sessions after installing skill content, monitor, or hook configuration
so every application registry is current.

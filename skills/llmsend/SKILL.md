---
name: llmsend
description: >-
  Send durable messages between Claude Code or Codex sessions on one machine
  or across Tailscale. Use for cross-project handoffs, status updates, design
  questions, fix requests, acknowledgements, or waking an idle recipient.
  Every message is an inbox file; application-owned monitors or hooks notify
  the agent, while an optional tmux status-line notice alerts the watching
  human without injecting terminal input.
---

# LLMsend

Coordinate project-named Claude Code and Codex sessions through a durable inbox
and an editor-independent hook channel.

## Safety invariant

Never write bytes into another agent pane's terminal input stream. A screen can
look idle and still race with a human keystroke; cursor position, wrapping,
ANSI intensity, ghost suggestions, and terminal geometry are not an atomic
input-buffer oracle.

Use exactly two channels:

1. Write a Markdown note under the recipient project's `inbox/`. This is the
   authoritative delivery.
2. Use the agent application's own context channel. The Claude plugin's
   `scripts/inbox-monitor` wakes an idle interactive session; hooks expose
   changed pending paths during prompts and tool loops. Optionally call
   `scripts/notify-session` to show the watching human a tmux status message.

If the hook is absent, delayed, or fails, stop at file delivery plus the safe
status-line notice. Never fall back to terminal input injection. There is no
ping-only mode: every agent-directed message must have a durable note.

## Prerequisites

- Keep one project per named tmux session; normally the session name equals the
  project directory basename.
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

Bare `SESSION` means local. `SESSION@HOST` means the named session on the
Tailscale MagicDNS host.

For a local session:

```bash
tmux has-session -t "$session"
recipient_dir="$(tmux display-message -p -t "$session" '#{pane_current_path}')"
```

For a remote session, keep the complete remote command in one quoted string so
the remote shell cannot reinterpret tmux's `#` format syntax:

```bash
ssh -o BatchMode=yes "$host" "tmux has-session -t '$session'"
recipient_dir="$(ssh -o BatchMode=yes "$host" \
  "tmux display-message -p -t '$session' '#{pane_current_path}'")"
```

Resolve the project root from that directory when needed. Do not assume the
pane happens to remain at its repository root.

### 2. Write the durable note

Create `inbox/` if needed. Name notes
`YYYY-MM-DD-from-SENDER-TOPIC.md`, adding a numeric suffix on collision. For
cross-machine notes, identify the sender as `SESSION@HOST` in both the filename
and the `From:` field so replies are routable.

Recommended body:

```markdown
# Subject

**From:** sender-or-session@host
**Date:** YYYY-MM-DD
**Re:** prior note path, when replying
**FYI only — no response needed.**

## TL;DR

One or two sentences.

## Details

The durable content.

— sender
```

Omit the FYI line when a response is expected. Stream remote note contents over
standard input instead of embedding them in a remote command:

```bash
ssh -o BatchMode=yes "$host" \
  "mkdir -p '$recipient_dir/inbox' && cat > '$recipient_dir/inbox/$notefile'" \
  < "$local_note"
```

### 3. Notify without touching the editor

For a local recipient:

```bash
skills/llmsend/scripts/notify-session "$session" \
  "📬 Inbox note delivered: $recipient_dir/inbox/$notefile"
```

For a remote recipient, invoke the same script on that host when installed, or
use tmux's status-message facility directly over `BatchMode=yes` SSH. This
notice is for the human; the application hook is what informs the agent.

Do not claim the recipient agent has read the note until it acknowledges or
otherwise demonstrates that it consumed the file.

## Recipient awareness

### Idle Claude sessions

The Claude plugin declares `monitors/monitors.json`. Its session-scoped monitor
runs `scripts/inbox-monitor` in the project root and checks only direct,
visible, regular `inbox/*.md` files. A filename or content change emits one
single-line notification through Claude's Monitor channel. Unchanged state and
an empty inbox stay silent, so polling does not cause model turns.

The monitor keeps its fingerprint in the process rather than a shared state
file. Two sessions in one project therefore cannot consume each other's wake
notification. It emits the inbox path and count, never note bodies. Restart the
session or run `/reload-plugins` after installing or updating the plugin.

### Prompt and tool hooks

`scripts/inbox-awareness-hook` reads hook JSON from stdin and:

- resolves the current project root and its direct, visible regular `*.md`
  inbox entries;
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

When notified, read each path, act on it, then move it to a project-defined
`inbox/processed/` directory or remove it according to that project's data
policy. Check remaining inbox paths before replying. Use this sender workflow
for replies and retain the original note path in `Re:`.

## MFIC control

The independent oracle is the agent application's monitor or hook event, not a
visual guess produced by the sender. Both channels bypass the editor buffer.
The repository's `./test` command supplies the blocking control: it rejects
prompt-injection primitives in shipped skill content, mechanically classifies
pending-file types, verifies content-change deduplication, and proves identical
output across distinct terminal sizes.

Wire `scripts/block-prompt-injection-hook` into the shell tool's `PreToolUse`
hooks during migration. It blocks LLMsend-shaped tmux input-mutation commands
while allowing ordinary tmux automation such as answering a trust prompt.
This independent enforcement layer catches stale sessions that still remember
the old delivery protocol.

This is reasonable assurance against accidental draft corruption. An agent
with arbitrary shell access could devise an unrecognized input-injection
primitive, so stronger adversarial control would require denying terminal
input mutation at the operating-system or tmux-policy boundary.

## Codex idle-session boundary

Codex hooks run only when a prompt or tool event already exists. They do not
wake a standalone idle TUI. Do not start `codex exec resume` or a second app
server against that conversation: Codex's exclusive writer lock rejects the
second writer and can leave the intended recipient unaware.

An app-server-owned Codex thread can accept an application-level `turn/start`
request without terminal input. Until LLMsend has a tested live-thread registry
and app-server sender, treat this as an explicit unsupported state and retain
the durable note plus human status notice. Never fall back to `send-keys`.

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
directory with regular files, so hard-link or copy both `SKILL.md` and bundled
scripts; installing only `SKILL.md` omits the executable safety mechanism.

Run:

```bash
./test
```

Also run the skill and Claude plugin validators after edits. Restart existing
agent sessions after installing skill content, monitor, or hook configuration
so every application registry is current.

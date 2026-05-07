---
name: LLMsend
description: Send a message between Claude Code sessions running related projects. Drops a markdown note in the recipient's inbox/ directory and live-pings their tmux session so they pick it up immediately. Use when sibling projects (each running its own Claude Code instance in its own tmux session) need to coordinate — passing handoff notes, design questions, status updates, fix requests. Two-channel design: the file is the durable record; the tmux ping is the live "check your mail" notification.
---

# LLMsend

Two-channel inter-LLM messaging between Claude Code sessions running
in named tmux sessions, where each session corresponds to one project.

The **inbox file** under `<recipient-project>/inbox/` is the durable
record — it survives session restarts, is grep-able, and forms a
permanent audit trail. The **tmux send-keys ping** is a live "you have
mail" notification so the recipient picks it up at their next prompt
rather than at their next manual inbox poll.

<prerequisites>
- Both sender and recipient run inside `tmux`.
- Each session is named after its project — by convention the project
  directory's basename, but the convention can be overridden if the
  project's owner has chosen a different session name.
- Both Claude Code instances run under a terminal that supports kitty's
  enhanced keyboard mode (kitty itself, WezTerm, recent Ghostty —
  most modern terminals). Without this, the submit-escape doesn't
  fire and the message lands as a draft requiring a manual Enter
  press from the user at the recipient's keyboard.
</prerequisites>

## Sender workflow

<sender_steps>

### Step 1 — verify YOU are in the right tmux session (once per session)

Fast detection: compare the current tmux session name to the project
directory basename. If they match, you're set.

```bash
session="$(tmux display-message -p '#S' 2>/dev/null)"
project="$(basename "$(git rev-parse --show-toplevel 2>/dev/null || pwd)")"
if [ -z "$session" ]; then
    echo "ERROR: not in a tmux session — LLMsend requires tmux"
    exit 1
elif [ "$session" != "$project" ]; then
    echo "WARNING: tmux session ($session) doesn't match project ($project)"
    # Confirm with user before proceeding — naming convention may be
    # intentional or session may be the wrong one for this project.
fi
```

You only need to verify this once per Claude Code session. Cache the
result.

### Step 2 — verify the RECIPIENT session exists (once per recipient per session)

```bash
recipient="<project-name>"
if ! tmux list-sessions -F '#S' 2>/dev/null | grep -qx "$recipient"; then
    echo "ERROR: no tmux session named '$recipient' — recipient unreachable"
    # Ask the user how to proceed (start the session? abort? different name?)
    exit 1
fi
```

<important>
If the recipient is a project you have NOT messaged before in this
conversation, **confirm with the user** before sending. Reasons:
1. The session might exist but not be running a Claude Code instance.
2. The recipient's terminal might not handle the kitty CSI u submit
   escape, in which case the ping lands as a draft requiring manual
   Enter.
3. There may be a privacy / process reason the user wants you NOT to
   ping that recipient automatically.

Once confirmed for a given recipient in a session, you don't need to
re-confirm for subsequent messages to the same recipient.
</important>

### Step 3 — ensure the recipient's `inbox/` directory exists

The convention: `<recipient-project-dir>/inbox/`. Create it if absent.

```bash
recipient_dir="<full path to recipient project>"
mkdir -p "$recipient_dir/inbox"
```

The full path depends on the user's project layout. Common patterns:
sibling directories under a shared parent, or use `tmux display-message
-pt "$recipient" '#{pane_current_path}'` to ask tmux where the
recipient is currently rooted.

### Step 4 — write the markdown note in the recipient's inbox

File naming convention: `YYYY-MM-DD-<short-topic>.md` (date-first so
they sort chronologically; topic-second so they're readable in `ls`).
Append `-NNN` if multiple notes are dropped on the same day with the
same topic (rare).

```
<recipient-project-dir>/inbox/2026-05-07-status-update.md
```

Note body conventions (recommended, not strict):

- **Header line** with `From:`, `Date:`, and `Re:` (if replying to a
  prior note — include the path of the prior note for traceability).
- **TL;DR** at the top if the note is long.
- **Body** with the substantive content.
- **Sign-off** with `— <sender-project>` so the recipient knows who
  to reply to.

Example skeleton:

```markdown
# <Subject>

**From:** <sender-project>
**Date:** YYYY-MM-DD
**Re:** <path to prior note, if any>

## TL;DR

<one or two sentences>

## <Body sections>

...

— <sender-project>
```

If no response is expected, **say so explicitly** at the top of the
note (e.g. `**FYI only — no response needed.**`). Without that the
recipient will assume a reply is wanted.

### Step 5 — notify via tmux send-keys + kitty CSI u submit

The two-call pattern is required for the message to actually submit
to Claude Code. Plain `tmux send-keys ... Enter` only inserts a
newline into the recipient's input buffer; the CSI u escape fires
the actual submit handler.

```bash
ping_text="📬 New inbox message from <sender-project>: <full-path-to-note>"
[ "$response_expected" = "no" ] && ping_text="$ping_text (FYI only)"

tmux send-keys -t "$recipient" "$ping_text"
tmux send-keys -t "$recipient" $'\e[13u'   # kitty CSI u for keycode 13 (Enter)
```

**Critical syntax notes:**

- The `\e[13u` MUST be in bash `$'...'` ANSI-C quoting so the escape
  is interpreted, not treated as the literal five characters.
- The two `send-keys` calls are SEPARATE invocations. Don't combine
  them into a single call with a trailing argument; tmux's argument
  parser doesn't apply ANSI-C quoting to non-`$'...'` arguments.
- Use the 📬 emoji as a visual signal to the recipient that this is
  an inter-LLM ping vs. user input. Optional but recommended.

</sender_steps>

## Recipient workflow

<recipient_steps>

### Step 1 — see the ping in your prompt area

A line like `📬 New inbox message from <project>: <path>` arriving in
your input area indicates a new note. The CSI u escape submitted it
for you, so you'll see it as if the user typed it.

If multiple pings arrive while you're mid-task, the inbox is the
ground truth — handle them in order after the current task settles.

### Step 2 — read the note

```bash
cat "<path-from-the-ping>"
```

The note's contents become part of your context. Treat it as you
would any user message at this priority — if it's an FYI, log
it; if it asks a question, prepare a reply; if it's a fix request,
queue it as a task.

### Step 3 — delete the note after reading

<important>
Delete each note after you've fully consumed it. The inbox is a
queue, not a log — it should not accumulate. If you don't delete,
future you will see the same note again and can't tell whether it
was handled.
</important>

```bash
rm "<path-from-the-ping>"   # or move to a /processed/ dir if your
                            # project wants an audit trail
```

If your project has a stronger audit-trail policy, move the note to
an `inbox/processed/` subdirectory instead of deleting. The default
is delete.

### Step 4 — check for other lingering notes

After reading the named note, scan the rest of the inbox for anything
that didn't get cleaned up — either previous notes whose pings landed
during user typing (and got swallowed into a draft), or pings sent
to a session that wasn't yet running a Claude Code instance.

```bash
ls -la <your-inbox>/
```

Handle anything you find. Same flow: read, act, delete.

### Step 5 — reply if requested

If the sender asked for a response, follow the sender workflow above
to drop a note in their inbox and ping them back. Reference the
original note's path in your reply's `Re:` header.

If no response is needed (sender said `FYI only`), don't reply — but
do delete the original note per Step 3.

</recipient_steps>

## Why two channels (file + tmux ping)?

- **The file is durable.** It survives session crashes, can be grep-ed
  later, and acts as a record of what was communicated when. If the
  ping fails (terminal mode mismatch, recipient's session paused,
  user typing at the moment), the note is still there for next time.
- **The ping is live.** Without it, the recipient only sees new notes
  on their next manual `ls inbox/`. With it, they see the ping
  immediately and pick up the message at their next prompt.
- **Either channel alone is incomplete.** File-only is too slow.
  Ping-only is too fragile (lost on every collision).

## Race / collision caveat

If the user (or the recipient Claude Code instance) is mid-typing in
the target session when send-keys fires, the ping text gets
concatenated into their draft. There is no way to detect "user is
typing" from outside tmux. Mitigation: the inbox file is authoritative;
the recipient will catch swallowed pings on their next inbox scan
(Step 4).

This is acceptable in practice. The latency win from the live ping
outweighs the occasional user-keyboard collision.

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| Ping lands but doesn't submit, sits as a draft | Plain `Enter` instead of `$'\e[13u'` | Use the CSI u escape; see Step 5 |
| `tmux send-keys` returns non-zero | Recipient session doesn't exist | Verify with `tmux list-sessions` |
| Garbage characters appear at recipient | Recipient's terminal doesn't handle kitty CSI u | Recipient should switch to a kitty-mode-compatible terminal, OR sender should fall back to file-only delivery and tell the user to manually notify |
| Recipient never reads the note | Inbox dir doesn't exist or sender wrote to wrong path | Verify path; recipient may need to add inbox-watching to their startup routine |
| Two notes with the same filename | Both senders dropped on the same day with the same topic | Append `-NNN` suffix to disambiguate |

## Sharing this skill

This skill is project-agnostic — it depends only on tmux, the kitty
CSI u submit escape, and a shared filesystem with sibling project
directories. To use it, anyone needs:

1. A multi-project setup where each project runs in its own
   project-named tmux session.
2. Claude Code instances in those sessions running on a
   kitty-enhanced-keyboard-compatible terminal.
3. Filesystem access between the sender and recipient projects (same
   machine, or a shared filesystem mount).

Drop this `SKILL.md` into `~/.claude/skills/LLMsend/` and Claude Code
will pick it up at next session start. Confirm with the user before
pinging recipients you haven't messaged before — the convention may
not yet be established for that project, and the user should opt in
explicitly the first time.

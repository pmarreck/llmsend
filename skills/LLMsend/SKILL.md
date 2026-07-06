---
name: LLMsend
description: >-
  Send a message between Claude Code sessions running related projects,
  on the same machine OR across machines over tailscale. Drops a markdown
  note in the recipient's inbox/ directory and live-pings their tmux
  session so they pick it up immediately. Use when sibling projects (each
  running its own Claude Code instance in its own tmux session) need to
  coordinate — passing handoff notes, design questions, status updates,
  fix requests. Addressing: bare `<session>` = local; `<session>@<host>` =
  a session on another tailnet machine. Two-channel design — the file is
  the durable record; the tmux ping is the live "check your mail" ping.
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
- The recipient **Claude Code instance** (under tmux) must accept the
  CSI u Enter encoding (`\e[13u`). NOTE the corrected mental model
  (verified 2026-06-11): `tmux send-keys` injects bytes directly into the
  pane's pty — the outer terminal emulator NEVER sees them, so its
  kitty-protocol support is irrelevant to delivery. Sessions created
  detached, with no terminal ever attached, accept the submit escape fine.
  (The emulator's kitty/CSI-u support only affects keys the human
  physically types — e.g. WezTerm historically wants
  `enable_kitty_keyboard = true` for that, but it has no bearing on
  LLMsend.) Where delivery CAN fail is version-shaped: an old tmux
  without extended-keys handling or an old Claude Code input parser —
  symptom: the ping lands as a draft requiring a manual Enter at the
  recipient's keyboard; fallback: the inbox file is durable regardless.
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

**Before you send, glance at the recipient's input line _with ANSI
codes_** so you don't clobber a real mid-typed draft. A dim/grey line
after `❯` is just Claude Code's suggested reply (safe to type over);
normal-intensity text is a real draft (hold, or use the inbox note
alone). See "Disambiguate the input line" under the Race / collision
caveat below for the one-liner.

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

## Lightweight mode — ping-only (inbox note optional)

The inbox note exists for **durability and elucidation**. When a message
needs neither, skip Steps 3–4 and put the entire message in the tmux ping
itself:

```bash
tmux send-keys -t "$recipient" "📬 <sender> (live ping, no inbox note): <the whole message>"
tmux send-keys -t "$recipient" $'\e[13u'
```

**Decision rule — write a full inbox note when ANY of these hold; otherwise
ping-only is fine:**

- The content carries decisions, specs, briefs, or anything a future
  session might need to re-read (durable record wanted).
- Delivery MUST happen — ping-only has **no fallback**: if it lands in a
  mid-typing draft or a dead session, it is simply lost (see the collision
  caveat below, which bites harder here).
- The message is longer than a sentence or two — long pings are hostile
  to the recipient's input buffer and to any human watching the pane.

Good ping-only uses: status nudges ("how's the build?"), acks, elapsed-time
checks, "look at X when you surface" pointers. Mark them clearly with
`(live ping, no inbox note)` so the recipient knows there is no file to
read or delete.

## Cross-machine addressing (tailscale) — `<session>@<host>`

LLMsend works across machines on a **tailnet** using plain SSH — no daemon,
no new transport. The two channels are unchanged; only the *reach* extends.

### The address grammar

- **`<session>`** (bare) — a session on THIS machine. **Grandfathered: zero
  change, always local.** Nobody is forced onto `@host` — bare addressing is
  the default and keeps working exactly as before. During a fleet migration,
  address a project bare when its live session is on your box.
- **`<session>@<host>`** — the session named `<session>` on tailnet machine
  `<host>`, where `<host>` is the **tailscale MagicDNS name** (`tailscale
  status`, or the machine's `hostname`). Opt-in, additive.

The fleet convention still holds: `<session>` == the project directory
basename == the "agent name". So `validate_gui@thelio-pm` is the
validate_gui agent on the Thelio; `validate_gui@peters-macbook-pro-m4-max`
is the one on the Mac — and during a migration BOTH can be live at once,
which is exactly why the `@host` qualifier exists.

### Prerequisites (cross-machine)

- **Tailnet-only, key-auth only.** Cross-machine send-keys IS remote
  keystroke injection into another agent's pty. Do it ONLY over the trusted
  tailnet with `BatchMode=yes` SSH key auth. **Never** over an untrusted
  network; **never** with password auth. This is guardrail #5 and it is not
  optional.
- Repos live at the same path on every box (fleet convention: `~/Code/<name>`),
  so recipient-dir resolution stays mechanical.

### Sender workflow — the same 5 steps, with SSH substitutions

**Your own address** (for `From:` headers): `"$(tmux display-message -p
'#S')@$(hostname)"`. Cross-machine notes MUST carry a `From: <session>@<host>`
header (reply routing depends on it), and the filename gains the origin:
`YYYY-MM-DD-from-<session>@<host>-<topic>.md`.

**Step 2 — verify the recipient session exists** (guardrail #3: guard every
remote ping; a missing session errors noisily):

```bash
ssh -o BatchMode=yes "$host" tmux has-session -t "$session" 2>/dev/null \
  || { echo "ERROR: no session '$session' on '$host'"; exit 1; }
```

**Step 3 — resolve the recipient dir + write the note** (produce the note
LOCALLY, stream it over SSH — no fragile remote quoting):

```bash
# where the recipient session is rooted, on its machine:
rdir="$(ssh -o BatchMode=yes "$host" \
  tmux display-message -pt "$session" '#{pane_current_path}')"
ssh -o BatchMode=yes "$host" "mkdir -p '$rdir/inbox' && cat > '$rdir/inbox/$notefile'" < ./localnote.md
```

**Step 5 — ping, with the CSI-u escape evaluated LOCALLY** (guardrail #4 —
produce the `\e[13u` bytes sender-side so SSH just carries them; this
sidesteps remote login-shell/quoting fragility):

```bash
ssh -o BatchMode=yes "$host" tmux send-keys -t "$session" \
  "📬 New inbox message from $self: $rdir/inbox/$notefile"
ssh -o BatchMode=yes "$host" tmux send-keys -t "$session" "$(printf '\033[13u')"
```

Note the `"$(printf '\033[13u')"` — the escape is expanded in YOUR shell
(bash `printf` renders `\033` = ESC universally, where `\e` is less
portable), and SSH transmits the resulting bytes; the remote `tmux
send-keys` receives them literally. Do NOT `printf` on the remote side.

### Guardrails (hard-won; violate at your peril)

1. **BATCH, NEVER BROADCAST.** Never fan a ping across many sessions at
   once — a `send-keys` storm caused a watchman thundering-herd lockup AND
   tripped Anthropic's automation flag (both observed live, 2026-07-06).
   Cross-machine amplifies both. Send to at most ~4 recipients per batch
   with pauses between; never all-sessions-at-once.
2. **jj/watchman wedges under concurrency.** Simultaneous jj ops across
   boxes — even `jj status`, which SNAPSHOTS (not read-only) — can lock
   watchman. For any scripted/agent jj READ, use `jj --ignore-working-copy`.
   Recovery: `jj --config fsmonitor.backend=none util snapshot`, then
   `killall -9 watchman`.
3. **File is truth; ping is best-effort — more so across machines.** The
   inbox note is the durable channel; the remote ping fails more ways
   (session gone, tmux version, mid-typing draft). Always guard the ping
   with `tmux has-session` (Step 2) and prefer a full note for anything
   that must not be lost.
4. **Evaluate the CSI-u escape locally** (see Step 5) — never via remote
   `printf`.
5. **Tailnet-only, key-auth only** (see prerequisites).
6. **"Home box" == the machine holding the canonical WORKING COPY.** Tie to
   the fleet invariant: uncommitted work lives on exactly ONE machine.
   Handoff etiquette when a project moves boxes: drop a **wind-down note**
   in the departing session's own inbox pointing at the new home, then let
   the new box become canonical. (This is the same mechanism as a fleet
   migration; during one, `@host` keeps addressing unambiguous.)

## Recipient workflow

<recipient_steps>

**Live pings first:** a message marked `(live ping, no inbox note)` IS the
entire message — there is no file to read or delete. Act on it directly
and skip Steps 2–3 for that message.

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

**Cross-machine replies:** if the sender's `From:` header is
`<session>@<host>` (not a bare name), the sender is on another machine —
reply back over SSH to that same `<host>` using the cross-machine sender
steps, not a local `tmux send-keys`. The `From:` header IS the return
address; a cross-machine note without one is a dead letter.

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

If the recipient is mid-typing a **real draft** when send-keys fires,
the ping concatenates into it. But a real draft and a false alarm look
**identical without colour** — so read the pane **with ANSI codes** to
tell them apart before sending:

- **Dim/grey text** (SGR 2, `\e[2m`) after the `❯` is Claude Code's
  **suggested next reply** (ghost autocomplete), NOT a real draft.
  Typing over it just replaces it — **safe to send.**
- **Normal-intensity text** after the `❯` is a **real mid-typed draft**.
  Sending would clobber it — **hold**, or fall back to the inbox note
  alone (it is authoritative; the recipient catches it on the next
  inbox scan, Step 4).

### Disambiguate the input line — do this before every send-keys
```bash
tmux capture-pane -pet "$recipient" -S -3 | gcat -v | tail -3   # READ the input line
#   input line's text wrapped in ^[[2m … ^[[0m => dim suggestion => safe to type over
#   input line's text at normal intensity       => real draft     => HOLD / inbox-only
#   nothing after the prompt glyph               => idle           => safe to send
# Quick boolean (dim run present near input?):  … | gcat -v | tail -3 | grep -c '\[2m'  (>0 ⇒ suggestion)
# GOTCHA: grep the dim CODE '\[2m', NOT the ❯ glyph — `gcat -v` mangles the multibyte
# ❯ into M-b… bytes, so a literal ❯ grep matches NOTHING (a false "empty/idle" reading).
```
`capture-pane -e` includes the escape sequences and `gcat -v` renders
ESC as `^[`, so the `^[[2m` dim marker becomes visible. **Without `-e`
the suggestion and a real draft are indistinguishable — that is the
trap** (a dim suggestion looks like a draft, so you "hold" forever, or
you assume it's a suggestion and clobber a real one). `cat -v` is GNU
coreutils; on macOS use `gcat`. A one-glance check turns "occasional
clobber" into "never clobber" — and the live-ping latency win still
stands.

## Common failure modes

| Symptom | Likely cause | Fix |
|---|---|---|
| Ping lands but doesn't submit, sits as a draft | Plain `Enter` instead of `$'\e[13u'` | Use the CSI u escape; see Step 5 |
| `tmux send-keys` returns non-zero | Recipient session doesn't exist | Verify with `tmux list-sessions` |
| Garbage characters appear at recipient | Recipient's terminal doesn't handle kitty CSI u | Recipient should switch to a kitty-mode-compatible terminal, OR sender should fall back to file-only delivery and tell the user to manually notify |
| Recipient never reads the note | Inbox dir doesn't exist or sender wrote to wrong path | Verify path; recipient may need to add inbox-watching to their startup routine |
| Two notes with the same filename | Both senders dropped on the same day with the same topic | Append `-NNN` suffix to disambiguate |
| Ping sent right after Esc/interrupt silently vanishes | Recipient's input buffer is cleared during turn teardown (observed live, 2026-06-11) | After interrupting, wait until the recipient's pane shows an idle prompt (`capture-pane` → `❯`) before sending; or use a full inbox note, which survives regardless |
| Ping shows "Press up to edit queued messages" but is never read | Queued messages don't preempt — the recipient may have self-started a new turn (e.g. resuming its todo list after an interrupt), and your ping waits behind it indefinitely (also observed live, 2026-06-11) | "Queued" ≠ "read". For urgent delivery, verify the recipient's spinner is processing YOUR message; if it's grinding its own work, a (second) Esc ends that turn and releases the queue |
| Cross-machine ping/note fails with an SSH error | Recipient host unreachable, not on the tailnet, or key auth not set up | `ssh -o BatchMode=yes <host> true` to confirm reachability + key auth; `tailscale status` to confirm the host is on the tailnet. The inbox note can't be written either, so nothing was delivered — fix the link and retry |
| Cross-machine note delivered but reply never arrives | Note lacked a `From: <session>@<host>` header, so the recipient can't route back across machines | Always include the `From:` origin header + origin-in-filename for cross-machine notes; it is the return address |
| Ambiguous which machine a project's session is on | Same-named session live on two boxes during a fleet migration | Use the `<session>@<host>` qualifier; the "home box" (canonical working copy) is authoritative — see guardrail #6 |
| `jj`/watchman hangs after a burst of cross-machine coordination | Concurrent jj snapshots across boxes locked watchman (guardrail #2) | `jj --config fsmonitor.backend=none util snapshot` then `killall -9 watchman`; use `jj --ignore-working-copy` for scripted reads |

## Sharing this skill

This skill is project-agnostic — it depends only on tmux, the kitty
CSI u submit escape, and either a shared filesystem (same machine) or
tailnet SSH (across machines). To use it, anyone needs:

1. A multi-project setup where each project runs in its own
   project-named tmux session.
2. Claude Code instances in those sessions running on a
   kitty-enhanced-keyboard-compatible terminal.
3. Reach to the recipient: same-machine filesystem access, OR — for
   `<session>@<host>` addressing — the recipient host on the same
   tailnet with `BatchMode=yes` SSH key auth (guardrail #5).

Drop this `SKILL.md` into `~/.claude/skills/LLMsend/` and Claude Code
will pick it up at next session start. Confirm with the user before
pinging recipients you haven't messaged before — the convention may
not yet be established for that project, and the user should opt in
explicitly the first time.

# llmsend

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A Claude Code/Codex skill for sending messages between agent sessions
running related projects. Each project runs its own agent instance in its
own tmux session; this skill lets them coordinate via a hybrid file-based
inbox and live tmux notification.

## Why

When you run multiple related projects (e.g. a library and several
consumers, or a stack of sibling projects with cross-cutting concerns)
each in its own agent session, they need to communicate without
relying on you-the-human to relay every message by hand. `llmsend`
codifies a battle-tested pattern: a durable inbox file plus a live
tmux ping.

## How it works

- **Sender** drops a markdown note in `<recipient-project>/inbox/`,
  then sends two `tmux send-keys` calls to the recipient's session —
  the message text plus the kitty CSI u submit escape (`\e[13u`),
  which fires the agent's submit handler.
- **Recipient** sees the ping arrive in their prompt area as if the
  user typed it, reads the note (which becomes part of their
  context), deletes it, and optionally replies using the same flow.

The file is the durable record (survives session crashes, grep-able,
audit-trail-friendly). The ping is the live notification (recipient
picks up the message at their next prompt rather than at their next
manual inbox poll).

See `skills/llmsend/SKILL.md` for the full protocol — sender steps,
recipient steps, prerequisites, failure modes.

## Install

### Via Claude Code's plugin system (recommended)

This repo doubles as a single-plugin marketplace. Add it once, then
install:

```
/plugin marketplace add pmarreck/llmsend
/plugin install llmsend@llmsend
```

Update later with:

```
/plugin marketplace update llmsend
/plugin install llmsend@llmsend   # re-runs install on the updated version
```

### Manual install (no marketplace)

```sh
git clone https://github.com/pmarreck/llmsend ~/Documents-CloudManaged/llmsend
ln -sfn ~/Code/llmsend/skills/llmsend ~/.claude/skills/llmsend
mkdir -p ~/.codex/skills/llmsend
cp ~/Code/llmsend/skills/llmsend/SKILL.md ~/.codex/skills/llmsend/SKILL.md
```

Claude Code can load the symlinked skill directory. Codex 0.142.x needs a
real directory and real `SKILL.md` under `~/.codex/skills`; symlinked skill
directories and symlinked `SKILL.md` files are skipped during discovery.
Restart the agent session to load the skill into the available-skills list.

## Prerequisites

- Each project runs in a tmux session named after the project (by
  convention: the project directory's basename).
- Both agent instances run under a terminal that handles
  kitty's enhanced keyboard mode (kitty itself, WezTerm, recent
  Ghostty, etc.). Without this, the submit-escape lands as a draft
  requiring manual Enter.
- Reach to the recipient: filesystem access between sender and
  recipient project trees on the same machine, OR — for
  `<session>@<host>` cross-machine addressing — the recipient host on
  the same tailnet with `BatchMode=yes` SSH key auth. (Bare `<session>`
  names stay local and unchanged; `@<host>` is opt-in.)

## License

MIT (see `LICENSE`).

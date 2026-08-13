# llmsend

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A Claude Code/Codex skill for safe messaging between project-named agent
sessions on one machine or across Tailscale.

## Architecture

Every message is a Markdown file under the recipient project's `inbox/`.
Claude's session-scoped plugin monitor wakes an idle interactive agent when its
bounded inbox changes. `UserPromptSubmit` and `PostToolUse` hooks surface
pending paths during existing turns; an optional tmux status-line message
alerts the watching human.

LLMsend never writes into another pane's terminal input. That structural rule
eliminates draft corruption and makes delivery independent of terminal width,
reflow, ANSI styling, and dim suggested prompts. If hooks are unavailable, the
durable file remains authoritative and delivery degrades safely.

The implementation lives in `skills/llmsend/`:

- `SKILL.md` defines local and cross-machine workflows.
- `scripts/inbox-monitor` wakes idle Claude sessions through the application
  notification channel.
- `scripts/inbox-awareness-hook` supplies editor-independent agent context.
- `scripts/notify-session` emits only a human-visible tmux status message.
- `./test` enforces the no-prompt-injection boundary and hook behavior.

## Install

### Claude Code plugin

```text
/plugin marketplace add pmarreck/llmsend
/plugin install llmsend@llmsend
```

For a local checkout under development:

```bash
claude plugin marketplace add "$HOME/Code/llmsend"
claude plugin install --scope user llmsend@llmsend
```

The plugin is required for idle wakeups. A plain `SKILL.md` symlink supplies
instructions and hooks only; Claude does not discover monitors from it.

### Manual

Claude Code can load the repository skill directory through a symlink:

```bash
ln -sfn "$HOME/Code/llmsend/skills/llmsend" "$HOME/.claude/skills/llmsend"
```

Codex currently requires regular files. Materialize the whole skill, including
its scripts, rather than installing only `SKILL.md`:

```bash
mkdir -p "$HOME/.codex/skills/llmsend/scripts"
ln -f "$HOME/Code/llmsend/skills/llmsend/SKILL.md" "$HOME/.codex/skills/llmsend/SKILL.md"
ln -f "$HOME/Code/llmsend/skills/llmsend/scripts/inbox-awareness-hook" "$HOME/.codex/skills/llmsend/scripts/inbox-awareness-hook"
ln -f "$HOME/Code/llmsend/skills/llmsend/scripts/inbox-monitor" "$HOME/.codex/skills/llmsend/scripts/inbox-monitor"
ln -f "$HOME/Code/llmsend/skills/llmsend/scripts/block-prompt-injection-hook" "$HOME/.codex/skills/llmsend/scripts/block-prompt-injection-hook"
ln -f "$HOME/Code/llmsend/skills/llmsend/scripts/notify-session" "$HOME/.codex/skills/llmsend/scripts/notify-session"
```

Wire `inbox-awareness-hook` into both `UserPromptSubmit` and `PostToolUse` for
Claude and Codex. The copied Codex monitor is documentation/package parity;
Codex does not yet expose a session monitor lifecycle. During migration, also
wire `block-prompt-injection-hook`
into the shell tool's `PreToolUse` hooks. It blocks only LLMsend-shaped tmux
input injection; ordinary tmux automation, including answering a trust prompt,
remains available. Restart existing sessions after changing skill or hook
configuration. Claude sessions also need a restart or `/reload-plugins` after a
monitor change.

## Validate

```bash
./test
```

## License

MIT (see `LICENSE`).

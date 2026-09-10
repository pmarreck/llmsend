# llmsend

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

An agent-neutral skill for durable messaging between projects in Herdr,
locally or across Tailscale, with Claude and Codex application adapters.

## Architecture

Every new message is a schema-versioned `*.frontmatter.md` file under the
recipient project's `inbox/`. Legacy Markdown notes remain discoverable during
migration.
Claude's session-scoped plugin monitor wakes an idle interactive agent when its
bounded inbox changes. `UserPromptSubmit` and `PostToolUse` hooks surface
pending paths during existing turns; an optional Herdr notification
alerts the watching human.

LLMsend writes the durable inbox file first and prefers application-owned wake
channels. An explicitly authorized sender may wake an idle agent through its
terminal only after verifying a visibly empty prompt. The supplied advisory
hook warns about the residual human-draft race without blocking the command.

The implementation lives in `skills/llmsend/`:

- `SKILL.md` defines local and cross-machine workflows.
- `scripts/inbox-monitor` wakes idle Claude sessions through the application
  notification channel.
- `scripts/inbox-awareness-hook` supplies editor-independent agent context.
- `scripts/notify-session AGENT_OR_PANE MESSAGE` verifies a live Herdr recipient
  and emits a session-wide human notification naming it. It never writes input.
- `scripts/write-note` writes atomic, collision-safe `llmsend/v1` notes from
  stdin with relevance metadata for body-free triage.
- `./test` enforces durable delivery and advisory-hook behavior.

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

For Codex, use its shared agent-skills discovery root. This installation's
shared `llm_skills` repository already links this complete skill for both clients;
do not create a duplicate if it is installed there. For a standalone setup:

```bash
mkdir -p "$HOME/.agents/skills"
ln -s "$HOME/Code/llmsend/skills/llmsend" "$HOME/.agents/skills/llmsend"
```

Wire `inbox-awareness-hook` into both `UserPromptSubmit` and `PostToolUse` for
Claude and Codex. The shared Codex monitor is documentation/package parity;
Codex does not yet expose a session monitor lifecycle. During migration, also
wire `block-prompt-injection-hook`
into the shell tool's `PreToolUse` hooks. It warns on LLMsend-shaped Herdr input
mutation and legacy tmux equivalents but returns success. Read-only inspection
and side-band notifications stay silent. Restart
existing sessions after changing skill or hook configuration. Claude sessions
also need a restart or `/reload-plugins` after a monitor change.

## Herdr delivery

Run Herdr controls from the intended managed session (`HERDR_ENV=1`). Discover
the exact agent/pane and project cwd with `herdr agent list` and `herdr agent get`.
Write a note with `scripts/write-note` before attempting notification. Read the
[skill](skills/llmsend/SKILL.md) for the metadata contract and authorized wake
workflow. A notification is human-visible; it does not itself make an agent read.

The Nix notification package expects the session's installed `herdr` client on
PATH (or `LLMSEND_HERDR` pointing at that executable). It deliberately does not
bundle a competing Herdr server/client version. No tmux dependency is required.
On plain remote SSH, write the note and use the recipient's application monitor;
do not invent Herdr context variables to target a possibly unrelated session.

## Validate

```bash
./test
```

## License

MIT (see `LICENSE`).

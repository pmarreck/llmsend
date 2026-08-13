# Project overview

LLMsend coordinates Claude Code and Codex sessions through durable project
inbox files. Claude's plugin monitor wakes an idle interactive session, while
agent-owned hooks expose pending note paths during prompts and tool loops. A
separate tmux status-line message may notify the watching human without entering
the agent editor.

The defining safety property is structural: LLMsend never injects terminal
input. Consequently, human drafts, dim suggestions, line wrapping, terminal
resizes, and backend-specific submit keys cannot collide with delivery.

The repository is both a Claude plugin and a Codex-compatible skill source.
Bundled deterministic scripts implement hook delivery, human notification, and
the migration-period prompt-injection block. Codex idle wakeup remains bounded
to future app-server-owned sessions because standalone TUIs hold exclusive
thread-writer locks.

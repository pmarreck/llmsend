# Project overview

LLMsend coordinates Claude Code and Codex sessions through durable project
inbox files. New notes use the `llmsend/v1` JSON metadata contract and the
`.frontmatter.md` suffix so recipients can triage relevance without loading
message bodies. Claude's plugin monitor wakes an idle interactive session, while
agent-owned hooks expose pending note paths during prompts and tool loops. A
separate tmux status-line message may notify the watching human without entering
the agent editor.

The defining safety property is structural: LLMsend never injects terminal
input. Consequently, human drafts, dim suggestions, line wrapping, terminal
resizes, and backend-specific submit keys cannot collide with delivery.

The repository is both a Claude plugin and a Codex-compatible skill source.
Bundled deterministic scripts implement atomic note creation, hook delivery,
human notification, and the migration-period prompt-injection block. Codex idle wakeup remains bounded
to future app-server-owned sessions because standalone TUIs hold exclusive
thread-writer locks.

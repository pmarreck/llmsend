# Plan

- [x] Replace tmux prompt injection with durable inbox delivery plus agent-owned hook context. (2026-07-22 14:05 EDT)
  - Curiosity poke: a human may type between any screen check and key injection, so no capture-pane classifier can close the race.
- [x] Add deterministic hook and side-band notification scripts with a complete Bash test runner. (2026-07-22 14:05 EDT)
  - Curiosity poke: terminal resize, wrapping, dim suggestions, and arbitrary real drafts must not affect delivery safety.
- [x] Wire the hook into both Codex and Claude, validate the skill, and synchronize the installed skill copies. (2026-07-22 14:05 EDT)
  - Curiosity poke: an absent hook must degrade to durable file plus human-visible tmux status, never prompt injection.
- [x] Document and verify backend-specific tmux submission: Kitty CSI-u Enter
  for Claude; bracketed paste plus plain Enter for Codex, locally and across
  the tailnet. (2026-07-17 10:10 EDT)
  - Curiosity poke: how should an unknown or temporarily obscured foreground
    process fall back without risking a recipient's real draft?

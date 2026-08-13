# Plan

- [x] Add a Claude-native inbox monitor that wakes an idle interactive agent
      through the application notification channel, without terminal input or
      periodic model calls. Prove bounded direct-file classification, content
      change detection, deduplication, and resize independence.
  - Curiosity poke: every session needs independent in-memory state so one
    agent observing a project cannot consume another agent's notification.
  - Completed 2026-08-13 16:40 EDT; plugin 0.2.0 installed user-wide and all
    repository, Nix, plugin, and skill checks pass.
- [x] Define the Codex wake boundary: app-server-owned threads may receive
      `turn/start` over the supported protocol, while standalone TUI writer
      locks must fail safely instead of spawning a competing writer.
  - Curiosity poke: project directory alone may map to several historical
    threads, so an external sender needs an explicit live-thread identity.
  - Completed 2026-08-13 16:40 EDT; implementation remains a separate fleet
    launcher migration because existing standalone sessions own writer locks.
- [x] Bound inbox-awareness discovery to direct Markdown children, prove it does
      not recursively invoke `find`, and retain content-change notifications.
      Curiosity poke: prompt hooks must not walk unrelated nested artifacts
      merely because a project has an `inbox/` directory. (2026-08-12 10:46
      EDT; failing-then-passing regression test; full suite green.)
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

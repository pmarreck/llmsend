# Plan

- [x] Add opt-in `notify-session TARGET --wake NOTE_PATH` with guarded Herdr
      input, bounded observation/Enter recovery, durable attempt deduplication,
      and explicit outcomes. Preserve human drafts, prefer existing monitors,
      and test changed geometry/identity and delayed submissions before coding.
      Peter authorized this advisory terminal wake on 2026-09-10 EDT. A screen
      check is not an atomic lock against simultaneous human typing.
      Completed 2026-09-10 16:57 EDT: 127 deterministic assertions plus CLI,
      persistent dedup and real kernel-lock integration tests pass. Nix Linux
      package/check passes; all three platform outputs evaluate (Darwin/ARM
      execution not tested). ANSI classifications checked against live Codex,
      Grok and Claude captures. Codex `glob` and Grok `difz` acknowledged tests
      in their existing sessions, with no Enter recovery needed. Live Codex
      exposed a transient capture/status-transition false negative; added a
      failing regression then fixed observation retries. Final Codex wake ID
      a2d375b96a7d6c7f returned activity-observed and recipient ACKed. Grok ID
      63d7c3ebe38b18a1 likewise ACKed. No agent/process restart or focus change.
- [x] Wire the separate mail watcher to the explicit wake helper. Peter
      authorized this on 2026-09-10. Thelio now runs unix_mail_redux 39702a7 with
      helper e983780, using an owned private socket and pinned native identity
      instead of fabricated HERDR_ENV. Both projects passed exact-commit CI.
      At 17:50:39 EDT, delivered test mail automatically started the existing
      Codex glob and Grok difz sessions; activity observed at 17:50:41.
      Codex replied through email at 17:51:07. Full evidence is retained in
      unix_mail_redux/PLAN.md and docs/HERDR_MAIL.md.

- [x] Migrate active messaging guidance and notification helper from tmux to
      Herdr (Peter, 2026-09-10). Preserve durable-first delivery, exact recipient
      resolution and the advisory human-draft race. Test the control-call surface,
      missing session context, notification failures and terminal-input warnings.
      Completed 2026-09-10 EDT. Red/green tests cover Herdr call ordering,
      identity lookup, context refusal, failures and advisory wakes. Full suite,
      skill validation and Nix package/check pass. Live Herdr showed an argument
      ordering mismatch with help; title-first notification syntax is now tested
      and worked live. No changes to running agent conversations or plugin caches.

- [x] Convert the historical terminal-input blocker into an advisory that
      allows an explicitly authorized, inspect-first wake after durable note
      delivery. Update the skill, docs, installed Codex wiring, and behavioral
      tests. Curiosity poke: pane inspection and input cannot be atomic, so an
      attached human can still type during the gap; keep that race visible.
      Completed 2026-08-27 00:16 EDT. RED proved all five risky command forms
      exited 2; GREEN proves they now warn and exit 0 while unrelated tmux
      automation stays silent. `./test`, `nix flake check -L`, `./build`,
      ShellCheck, and the skill validator pass. A live empty-prompt wake of the
      `validate_gui` Grok also succeeded through the active Codex adapter.
- [x] Define and test the `llmsend/v1` metadata contract, then make every new
      sender-produced note end in `.frontmatter.md`. Keep direct legacy `*.md`
      notes discoverable until inboxes drain naturally.
  - Curiosity poke: sender-controlled priority and tags may help triage, but
    must never grant authority or bypass the recipient's own ordering rules.
  - Completed 2026-08-14 14:43 EDT: new notes use explicit `---json` framing;
    monitors and hooks retain direct legacy `*.md` discovery.
- [x] Add an atomic, collision-safe note writer with an injectable datetime,
      JSON-safe metadata, and stdin body support.
  - Curiosity poke: two senders can choose the same date, sender, and subject;
    collision handling must never overwrite either note.
  - Completed 2026-08-14 14:43 EDT: `write-note` uses `jq` for JSON escaping,
    atomic hard-link publication, and deterministic collision suffixes.
- [x] Teach recipients to inspect metadata before bodies, update the plugin
      package and documentation, validate the skill, and run all local and Nix
      checks before committing.
  - Curiosity poke: installed Claude/Codex copies are hard links today, but the
    release still needs a version bump and session/plugin reload instructions.
  - Completed 2026-08-14 14:43 EDT: repository and Nix suites, Codex skill
    validation, strict Claude plugin validation, and plugin 0.3.0 update pass.
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

# PLAN

Completed work and its validation evidence are preserved in [docs/PLAN_LOG.md](docs/PLAN_LOG.md).

## Current

- [x] Document and verify immediate native Codex thread-tool delivery with explicit recipient acknowledgement; distinguish tool availability, scheduled adapters and terminal fallback; full suite and skill validation pass (done 2026-10-23 10:37 EDT; context: skills/llmsend/references/native-codex.md).
- [x] Ship persistent hourly reminders with full suite, Nix package/checks and validators passing; preserve immediate notifications (done 2026-10-14 17:34 EDT; 71c3514; context: skills/llmsend/references/reminders.md).
- [x] Verify the stale-draft fallback boundary: current Herdr captures cannot recover an exact editor buffer; mutation remains disabled, with 59/60/61-second regression coverage (done 2026-10-14 EDT; context: skills/llmsend/references/reminders.md).
- [ ] Coordinate one declarative reminder runtime and verify a single recipient readback, runtime health and next-due status before marking deployment complete (context: skills/llmsend/references/reminders.md).
- [x] Recognize the observed Codex shortcut footer without accepting unknown lifecycle states or weakening draft/resize protections; full suite and Nix package/test checks pass (done 2026-10-09 23:38 EDT; context: docs/plan_context/codex-shortcut-footer.md).
- [x] Review outstanding documentation and housekeeping; full suite, Nix build/checks, skill/plugin validation and plan lint passed (done 2026-09-27 16:06 EDT).
- [x] Clarify human-versus-agent routing in the shared skill (done 2026-09-16; retained history in docs/PLAN_LOG.md).
- [x] Recognize unboxed Codex prompts and explain deferred wakes (done 2026-09-10 EDT; f9e92aa).

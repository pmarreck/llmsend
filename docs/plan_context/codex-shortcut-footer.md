# Codex shortcut footer compatibility

Read-only visible ANSI captures on 2026-10-09 show Codex 0.160.1 and
0.162.1 adding `← for agents · ? for shortcuts` below the Context status
line. The former unboxed-composer parser rejected every nonblank row there.

`tests/fixtures/codex_shortcut_composer.lua` preserves the observed composer
and styling, replacing only private status path/name with a generic project.
The additional row may be recognized only as that exact bottom footer. Other
text, partial/wrapped footers and extra rows must remain unrecognized.

Recognizing a composer does not prove the lifecycle is idle. Both captured
panes independently reported `agent_status: unknown`; one also lacked its
native conversation identity in Herdr's agent discovery response. These are
separate blockers. No agent input, lifecycle override or metadata repair is
authorized by this compatibility change. The helper still requires a known
native identity, idle/done lifecycle, unscrolled viewport, stable geometry and
two stable empty composer observations. App-owned hooks remain the safe route
when a recipient is already taking turns; durable delivery alone cannot wake
an idle agent whose lifecycle cannot be classified.

## Validation

The observed fixture first failed with `expected empty, got unknown`. After the
narrow parser change, the complete `nix develop -c ./test` passed, including
185 pure parser/sequencer assertions. Cases cover solid and wrapped drafts,
duplicate/partial/wrapped/extra footer text, geometry changes, and non-idle
lifecycle states. `nix develop -c ./build --no-link` and the sandboxed
`checks.x86_64-linux.test` also passed. No live agent was typed into to test
this change; synthetic adapter checks do not prove delivery to a live client.

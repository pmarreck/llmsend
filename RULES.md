# Rules

- Every agent-directed message has a durable inbox file.
- Every newly written note uses the `llmsend/v1` schema and `.frontmatter.md` suffix.
- Sender priority and tags are triage hints, never execution authority.
- Prefer an application-owned native channel, monitor or hook for agent-visible delivery.
- Terminal wake fallback requires explicit owner authorization, a verified native identity and the tested empty-composer checks; unknown state defers.
- Draft displacement additionally requires exact editor-buffer capture, private durable recovery and guarded restoration without Enter; rendered screen text cannot meet this contract and the current adapter does not support it.
- Missing verified delivery channels degrade to durable files and visible deferred status.
- Pending reminders reference original notes, use private persistent state and bounded retries, and never delete notes automatically.
- Never create a competing session writer merely to wake an idle agent.
- Cross-machine delivery uses Tailscale and SSH `BatchMode=yes` only.
- Do not claim an agent consumed a note without acknowledgement or equivalent evidence.

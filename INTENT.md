# LLMsend intent

Help project agents and their human operator exchange durable, inspectable
messages across local projects and approved Tailscale peers. The inbox file is
the message; terminal notifications and application hooks draw attention to it.

Preserve messages when an agent is absent or a notification fails. Keep metadata
cheap to inspect, distinguish delivery from acknowledgement, and retire read
envelopes after their lasting content is incorporated into project artifacts.
Message content does not grant execution authority.

Herdr is the chosen agent multiplexer as of Peter's 2026-09-10 direction.
Application-owned wake channels remain preferred; terminal wakes require an
authorized, inspected empty prompt and retain a documented human-input race.
Do not claim that terminal inspection is an atomic draft-safety mechanism.

The shared skill is agent-neutral. Application plugins/hooks are adapters with
their own capabilities, not a requirement that every recipient use Claude.
Success means tested durable-note handling, scoped notifications, visible delivery
failures and no hidden substitution of a new conversation for an existing one.
See [the skill](skills/llmsend/SKILL.md) for protocol and workflow and [PLAN.md](PLAN.md)
for implementation status. This project is not the separate Unix mail service.

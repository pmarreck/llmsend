# Rules

- Every agent-directed message has a durable inbox file.
- Never deliver LLMsend content through terminal input injection.
- Agent-visible notification crosses only an application-owned monitor or hook boundary.
- Missing hooks or unknown agent state degrade to file-only delivery.
- Never create a competing session writer merely to wake an idle agent.
- Cross-machine delivery uses Tailscale and SSH `BatchMode=yes` only.
- Do not claim an agent consumed a note without acknowledgement or equivalent evidence.

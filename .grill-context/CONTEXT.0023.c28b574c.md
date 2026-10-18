---
fragment: c28b574c
generation: 0023
branch: gg-topics
---

+ Transcript
  The file in which an Agent's own CLI stores one conversation. Muxify reads it and never writes it.
  avoid: log, history, session file
  under: Agents

+ Entry
  One message, tool call or tool result in an Agent's conversation, with an index that never changes. A turn holds many Entries.
  avoid: line, record, event, turn, message (when you mean the Entry)
  under: Agents

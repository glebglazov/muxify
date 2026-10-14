---
fragment: topic-unread
generation: 0021
branch: gg-topics
---

~ Unread
  A Topic explicitly marked with Mark Unread, or an Agent with a done, failed or blocked update that the user has not marked read. Topic Unread is saved independently of Agents and remains when they exit. With Manual Read, updates stay Unread until Mark Read or Mark All as Read. Without Manual Read, a new visit to a Window or Topic clears Unread; continued viewing preserves an explicit mark. A Topic mark is not an Agent Status and does not add to an Agent count. Snooze hides its mark without clearing it.
  was: An Agent with a done, failed or blocked update that the user has not marked read, or that the user marked with Mark Unread.
  avoid: unseen, new

~ Mark Read
  An Action that clears the Topic Unread mark and Unread for Agents in its target. Its Command and direct shortcut use the Active Topic, or the current Session when there is no Active Topic. It is available for every Topic, with or without Agents. A blocked Agent keeps its blocked Notification until its Status changes.
  was: An Action that clears Unread for the Agents in its target.

~ Mark Unread
  An Action that marks any Topic as Unread, with or without Agents. It also marks read Agents with done, failed or blocked Status as Unread. Its Command and direct shortcut use the Active Topic, or the current Session when there is no Active Topic. Its row Action uses the selected Topic, Session, Window or Agent.
  was: An Action that marks read Agents with done, failed or blocked Status as Unread.

~ Mark All as Read
  A Command that clears Unread for all Topics and Agents in the Active Environment, including hidden, Snoozed and Settled Topics.
  was: A Command that clears Unread for all Agents in the Active Environment.

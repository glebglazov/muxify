---
fragment: 6886b67c
generation: 0019
branch: gg-topics
---

~ Unread
  An Agent with a done, failed or blocked update that the user has not marked read. With Manual Read, the update becomes Unread even while the user looks at its Window and stays Unread until Mark Read; without Manual Read, looking at its Window or entering its Topic makes it read, and updates in the Window being viewed do not become Unread.
  was: An Agent that reached done, failed or blocked while the user wasn't looking at its Window. Looking at its Window, or going into its Topic, makes it read.
  avoid: unseen, new

+ Manual Read
  The default behavior in which visiting a Window or Topic does not clear Unread, and Agent updates become Unread even while the user looks at their Window. The user can turn it off in the Config to restore automatic reading.
  under: Agents

+ Mark Read
  An Action that clears Unread for the Agents in its target. Its Command and direct shortcut act on all Agents in the Active Topic, or all Agents in the current Session when there is no Active Topic; a blocked Agent keeps its blocked Notification until its Status changes.
  avoid: mark unread, dismiss Status
  under: Agents

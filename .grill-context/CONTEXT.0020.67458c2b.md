---
fragment: 67458c2b
generation: 0020
branch: gg-topics
---

~ Unread
  An Agent with a done, failed or blocked update that the user has not marked read, or that the user marked with Mark Unread. With Manual Read, updates become Unread even while the user looks at their Window and stay Unread until Mark Read or Mark All as Read. Without Manual Read, a new visit to the Window or Topic clears Unread; continued viewing preserves an explicit Mark Unread and does not make new updates Unread.
  was: An Agent with a done, failed or blocked update that the user has not marked read. With Manual Read, the update becomes Unread even while the user looks at its Window and stays Unread until Mark Read; without Manual Read, looking at its Window or entering its Topic makes it read, and updates in the Window being viewed do not become Unread.
  avoid: unseen, new

+ Mark Unread
  An Action that marks read Agents with done, failed or blocked Status as Unread. Its Command and direct shortcut use the Active Topic, or the current Session when there is no Active Topic. Its row Action uses the selected Topic, Session, Window or Agent.
  under: Agents

+ Mark All as Read
  A Command that clears Unread for all Agents in the Active Environment.
  under: Agents

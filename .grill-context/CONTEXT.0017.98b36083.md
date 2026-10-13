---
fragment: 98b36083
generation: 0017
branch: gg-topics
---

+ Lock
  To keep a No Topic Session in the Topics list as a card with a number, in the order of the Topics, until the user Unlocks it, the Session ends, or the Session goes into a Topic.
  avoid: pin, keep, dock, sticky
  under: Topics

+ Locked Session
  A No Topic Session that the user Locked. It has a card among the Topics, but it is not a Topic: it cannot be Settled, Snoozed, Pinned or Forgotten.
  avoid: kept Session, pinned Session, Topic (when you mean the Session)
  under: Topics

+ Unlock
  To end a Lock. The Session stays, as a No Topic Session.
  avoid: unpin, release
  under: Topics

~ Zen
  A time when every open Topic except one is Snoozed, so the user can work on that one Topic. Locked Sessions are hidden too, and the Agents of No Topic show no Notification mark. It ends at its time or when the user ends it, and then each Topic it Snoozed comes back as it was before.
  was: A time when every open Topic except one is Snoozed, so the user can work on that one Topic. The Agents of No Topic show no Notification mark too. It ends at its time or when the user ends it, and then each Topic it Snoozed comes back as it was before.
  avoid: focus, focus mode, do not disturb, mass snooze

~ Next Topic
  The Topic or Locked Session that Muxify opens after the user Snoozes or Settles the Active Topic: the row below it in the Topics list, else the row above it, else No Topic.
  was: The Topic that Muxify opens after the user Snoozes or Settles the Active Topic: the one below it in the Topics list, else the one above it, else No Topic.
  avoid: following Topic, previous Topic, last Topic

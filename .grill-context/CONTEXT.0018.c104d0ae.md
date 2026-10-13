---
fragment: c104d0ae
generation: 0018
branch: gg-topics
---

~ Notification
  A mark that Muxify shows because an Agent is Unread, or is blocked, such as the mark on its Topic. Its type is the Status: done, failed or blocked.
  was: A mark that Muxify shows because an Agent is Unread, such as the mark on its Topic. Its type is the Status the Agent reached: done, failed or blocked.
  avoid: alert, badge, Unread (when you mean the mark)

+ Working mark
  The gray, moving mark that shows an Agent is working. It is not a Notification, and it is never Unread.
  avoid: spinner, activity indicator, working dot, pulse
  under: Agents

+ Agent mark
  A Working mark or a Notification. Each kind has one meaning, one shape family and one colour on every card, row and Command Palette result.
  avoid: indicator, status dot, status color, marker
  under: Agents

~ Snooze
  To hide an open Topic until a time, or until you unsnooze it. Its Sessions and Agents keep running, but its Agents show no Notification until it comes back.
  was: To hide an open Topic until a time, or until you unsnooze it. Its Sessions and Agents keep running.
  avoid: hide, park, defer, archive

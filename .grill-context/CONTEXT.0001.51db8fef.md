---
fragment: 51db8fef
generation: 0001
branch: master
---

~ Session
  A tmux session. Sessions group Windows in the Sidebar. Outside Topics there is usually one per Project; a Topic has at most one in each Project.
  was: A tmux session, usually one per project. Sessions group Windows in the Sidebar.
  avoid: project, workspace

+ Project
  A directory that the Config's projects list names. It gives a Topic's Session its directory and the first part of its name.
  avoid: repo, workspace, Session (when you mean the directory)
  under: Topics

+ Topic
  One thing the user wants to get done, such as "Fix reward drop bug in GS". It owns at most one Session in each Project it touches, and it is open or Settled.
  avoid: task, project, workspace, thread
  under: Topics

+ Home Project
  The Project a Topic starts in. Its first Session opens there.
  avoid: base, root, main repo
  under: Topics

+ Untitled Topic
  A Topic that has no title yet. A rename or a title suggested from its Agents gives it one.
  avoid: draft, scratch, temp Topic
  under: Topics

+ Settle
  To mark a Topic as done. It leaves the Sidebar, its Sessions are killed or leave the Topic, and its record stays so that it can be reopened.
  avoid: close, archive, resolve, complete
  under: Topics

+ Dormant
  An open Topic that has no live Sessions, for example after a tmux restart. It stays in the Sidebar until you reopen or Settle it.
  avoid: inactive, sleeping, suspended
  under: Topics

+ Snooze
  To hide an open Topic until a time, or until you unsnooze it. Its Sessions and Agents keep running.
  avoid: hide, park, defer, archive
  under: Topics

~ Unread
  An Agent that reached done, failed or blocked while the user wasn't looking at its Window. Looking at its Window, or going into its Topic, makes it read.
  was: An Agent that reached done, failed or blocked while the user wasn't looking at its Window. Looking at the Window makes it read.
  avoid: unseen, new

+ Notification
  A mark that Muxify shows because an Agent is Unread, such as the mark on its Topic. Its type is the Status the Agent reached: done, failed or blocked.
  avoid: alert, badge, Unread (when you mean the mark)
  under: Agents

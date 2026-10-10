---
fragment: d909945d
generation: 0002
branch: gg-topics
---

~ Project
  A directory that the Config's projects list names. It gives a Topic's Session its directory and the first part of its name. When the directory is a repository with several Worktrees, the repository is one Project, not one Project per Worktree.
  was: A directory that the Config's projects list names. It gives a Topic's Session its directory and the first part of its name.
  avoid: repo, workspace, Session (when you mean the directory)

+ Worktree
  One checkout of a Project's repository at its own path, such as a folder inside a bare repository's folder. A Topic's Session in a Project uses one Worktree, and no other open Topic can use it.
  avoid: checkout, clone, Project (when you mean one checkout)
  under: Topics

+ Active Topic
  The Topic of the Window the user looks at, or No Topic when that Window belongs to no Topic.
  avoid: current Topic, selected Topic, focused Topic
  under: Topics

+ Unsnooze
  To end a Snooze before its time, so the Topic goes back to the Topics list. Nothing changes in tmux.
  avoid: restore, wake, resume
  under: Topics

+ Reopen
  To bring a Settled Topic back to the Topics list and create its remembered Sessions again.
  avoid: restore, unsettle, resume
  under: Topics

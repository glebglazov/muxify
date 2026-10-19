---
fragment: 2d631102
generation: 0024
branch: gg-topics
---

~ Dormant
  An open Topic that has no live Sessions but remembers Sessions, for example after a tmux restart or a Kill Session. It stays Dormant in the Sidebar until the user goes to it, which Reopens it, or Settles it.
  was: An open Topic that has no live Sessions, for example after a tmux restart. It stays Dormant in the Sidebar until the user goes to it, which Reopens it, or Settles it.
  avoid: inactive, sleeping, suspended

+ Empty
  An open Topic that has no live Session and remembers no Session: the user removed its last Session or Window from it, or moved it to another Topic. Going to it offers Add a Project; nothing is Reopened.
  avoid: Dormant (when it remembers no Session), blank, cleared
  under: Topics

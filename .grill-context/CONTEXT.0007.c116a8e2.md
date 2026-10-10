---
fragment: c116a8e2
generation: 0007
branch: gg-topics
---

~ Project
  A folder that the Config's projects.paths names, or one found below such a folder, where the user opens Sessions. It gives a Topic's Session its directory and the first part of its name. When the folder is a repository with several Worktrees, the repository is one Project, not one Project per Worktree.
  was: A directory that the Config's projects list names. It gives a Topic's Session its directory and the first part of its name. When the directory is a repository with several Worktrees, the repository is one Project, not one Project per Worktree.
  avoid: repo, workspace, Session Path, project directory, Session (when you mean the folder)

- Session Path

- Switcher

+ Command Palette
  A named search, opened by its own keybinding, over the Sources selected in it, whose highlighted result the user acts on. Each palette opens with its own Sources selected; the others can be selected too.
  avoid: switcher, launcher, finder, sessionizer, Go to Topic
  under: Layout

+ Source
  One kind of thing a Command Palette searches: Topics, Sessions (with the Projects that have no Session yet), Windows or Agents.
  avoid: provider, category, section
  under: Layout

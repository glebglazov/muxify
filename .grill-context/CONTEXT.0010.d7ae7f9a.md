---
fragment: d7ae7f9a
generation: 0010
branch: gg-topics
---

+ Next Topic
  The Topic that Muxify opens after the user Snoozes or Settles the Active Topic: the one below it in the Topics list, else the one above it, else No Topic.
  avoid: following Topic, previous Topic, last Topic
  under: Topics

~ Command Palette
  A named search, opened by its own keybinding, over the Sources selected in it, whose highlighted result the user acts on or, for a Command, runs. Each palette opens with its own Sources selected; the others can be selected too.
  was: A named search, opened by its own keybinding, over the Sources selected in it, whose highlighted result the user acts on. Each palette opens with its own Sources selected; the others can be selected too.
  avoid: switcher, launcher, finder, sessionizer, Go to Topic

~ Source
  One kind of thing a Command Palette searches: Topics, Sessions (a row for each Project with the Sessions in it, and a row for each Session outside every Project), Windows, Agents or Commands.
  was: One kind of thing a Command Palette searches: Topics, Sessions (a row for each Project with the Sessions in it, and a row for each Session outside every Project), Windows or Agents.
  avoid: provider, category, section

+ Action
  Something the user does to one Topic, Session, Window, Pane, Agent or Tab, such as Jump To, Snooze, Rename or Settle. Every Action runs in the palette's view, whichever way the user starts it.
  avoid: command (when you mean an Action on a thing), operation, menu item
  under: Layout

+ Command
  Something Muxify does that acts on no Topic, Session, Window, Pane, Agent or Tab, such as New Topic or Reload Config. The Commands Source lists the Commands.
  avoid: Action (when nothing is acted on), menu item, operation
  under: Layout

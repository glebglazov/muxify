---
fragment: 307a80c2
generation: 0014
branch: gg-topics
---

~ Focus
  Where keyboard input goes in an App Window: the Terminal, the Browser or a Command Palette. One of them has Focus at a time.
  was: Showing one of a Window's Terminal and Browser alone, with the Sidebar hidden, until Focus ends; it never changes the toggles. Where keyboard input goes is "the keyboard" (the keyboard is in the Terminal), never "focus".
  avoid: the keyboard (when you mean where input goes), active side, first responder

+ Maximize
  Showing one of a Window's Terminal and Browser alone, with the Sidebar hidden, until the user restores the Window; it never changes the toggles.
  avoid: focus, zoom (tmux zooms a Pane), solo, full screen
  under: Layout

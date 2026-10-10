---
fragment: 50f742ff
generation: 0011
branch: gg-topics
---

+ Format
  A Config string with #{…} placeholders that sets a Sidebar line or a Window row part from the Topic, Session, Window or Pane that the row shows. Muxify expands it, not tmux. Titles and Summaries give plain text. Window left and right parts can also give the current app icon or macOS SF Symbols.
  avoid: template, pattern, label string, tmux format (when you mean ours)
  under: Configuration

+ Summary
  The line under the title of a closed Topic or Session card, or under the title of a Window or Pane row. It shows only when its Format gives text.
  avoid: subtitle, details, description, second line
  under: Layout

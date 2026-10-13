# Agent marks mean one thing everywhere

An Agent mark is a Working mark or a Notification. Each kind has one meaning and one colour on every Sidebar card, Pane row, Agents row and Command Palette result. One shared type decides the mark for an Agent or a group of Agents, and every surface draws from that type. The Working mark is gray and moves, because it asks nothing of the user. A Notification is blue for done (only while Unread), orange for blocked (while the Agent is blocked) and red for failed (only while Unread). A read, done Agent has no mark. Each row has one mark. `ui.agent_colors` (`working`, `done`, `blocked`, `failed`; a macOS system colour name or `#RRGGBB`) changes a colour for every surface at once. `ui.pulse` stops the motion of every Working mark. `notifications.*_enabled` turns off a Notification type on every surface. A Snoozed Topic, and No Topic while Zen is on, show no Notification anywhere. A Working mark still shows on the Agent's own Pane row.

We record this because the Sidebar and the Command Palette have used two sets before, and the change was lost one day after it was made. `8df4172` put both on one set. Then `c031499` brought back blue for working and green for done in the Sidebar. After that, blue meant "busy" in one place and "finished, go and look" in the other.

## Considered Options

- **A set for each surface.** Rejected: the same Agent showed a different colour in the Sidebar and in the Palette. The user cannot read the marks.
- **Green for done, and keep it after the user reads the Agent.** Rejected: done is the resting state. A quiet Sidebar becomes mostly green, and an Unread mark no longer stands out.
- **The system accent colour for Unread.** Rejected: the accent colour is also the selection colour, and the user can set it to orange or red, which then looks like blocked or failed.
- **Blocked and failed both orange.** Rejected: blocked needs an answer, and failed needs the user to look at the error.
- **A key that hides the Working mark.** Rejected: it is the only sign that an Agent is busy. `ui.pulse: false` already stops its motion.

## Consequences

- The terminal bell is not an Agent mark. It shows as a gray bell symbol, and its colour is not configurable.
- A colour from `ui.agent_colors` replaces the default on every surface. The Command Palette's ANSI theme does not change Agent marks.

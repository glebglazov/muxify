# A palette step can choose several rows, and every Snooze is a Snooze of a set

"Snooze Topics…" Snoozes several Topics until one time. It adds a fourth kind of palette step to the three in [ADR 0014](0014-every-action-runs-in-the-palettes-view.md): **choose rows**. The step lists rows with a mark on each. Space in an empty field or ⇥ marks the highlighted row, ⌘A marks every row that the filter shows, and ↩ goes on with the marked rows, or with the highlighted row when nothing is marked. The marks stay when the filter changes. Snooze Topic is the same flow with a set of one Topic, and it starts at the "until" step. ⌫ in the empty "until" field goes back to the choose step with the set still marked. So every way into Snooze, from Commands, a direct key, a palette row or the Sidebar, goes through one route and one write.

## Considered Options

- **Marks in every search (as Tab in fzf).** ⌃Space would mark Topics in Go to…, and ⌘K and the row keys would then act on the marked set. Rejected: nothing shows that the key exists, every Action must then say what it does with many rows, and Esc would first clear the marks and only then close.
- **Chips in the search field.** ↩ would add the highlighted Topic as a chip and clear the query. Rejected: one search for each Topic is slow when the user wants most of them, and ↩ and ⌫ would each get a second meaning in one step.
- **Every Topic starts marked, and the user marks the ones to keep.** Rejected: that is almost Zen, and ↩ by reflex would Snooze everything.
- **A Snooze of one Topic keeps its own flow.** Rejected: two routes would drift, and a single Snooze could not grow into a Snooze of several Topics.

## Consequences

- The choose step has two groups: **Visible**, the Topics in the Topics list now, and **Already Snoozed**. Settled Topics are not in it. The Active Topic starts marked.
- The time the user chooses is written on every marked Topic, also when a Topic is already Snoozed until later. The "until" step names each Snooze that becomes shorter. Zen does not do this ([ADR 0009](0009-zen-remembers-the-snoozes-it-changed.md)): Zen does not ask about each Topic, so it never makes a Snooze shorter. Here the user marked each Topic.
- A Snooze of a set keeps no record and has no undo. ADR 0009 rejected a bulk Snooze with no record only because "End Zen" must find the Topics that Zen changed. Nothing here ends early, so the user Unsnoozes a Topic as for any other Snooze.
- When the Active Topic is in the set, Muxify opens the Next Topic outside the set.
- Later Actions on several rows, such as Mark Read or Settle, use this step kind and do not need a new ADR.

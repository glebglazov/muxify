# A pick step collects Topics and Tags as chips, and Snooze Topics starts with it

Snooze Topics… used the "choose rows" step of [ADR 0020](0020-a-palette-step-can-choose-several-rows.md): a mark on each row, Space or ⇥ to mark, ⌘A to mark all shown rows, and ↩ to go on. The marked set showed only as marks in the list, and a filter hid the marked rows. With no mark, ↩ went on with the highlighted row, which was the first Tag. So one ↩ by reflex Snoozed every Topic of that Tag.

We replace "choose rows" with a new kind of palette step: **pick**. The search field holds the picked Topics and Tags as chips, as the Tag field of Edit Tags holds Tags. The rows are suggestions: Tags, then Topics, then Already Snoozed. ↩ on a row picks it: the row becomes a chip, leaves the list, and the query clears. A Tag chip names every Topic that has the Tag, so a Topic that a picked Tag names stays in the list, dim, with "in #tag". The set is the Topics that the chips name, once each, in Topics list order. To go on, the user chooses the first row, "→ Snooze N Topics…". It shows only when the query is empty and one or more chips exist. For a query that is not a Tag, the last row, "＋ All N matches for “query”", picks every Topic that the query matches. In the pick step, ↩ only picks: it never Snoozes.

The chip keys are the same in every field with chips: ← at the start of the text selects the last chip, ← and → move the selection, → after the last chip puts the caret back, ⌫ removes the selected chip and selects the chip to its left, ⌦ removes it and selects the chip to its right, and a letter puts the caret back and types. ⌫ in the empty field removes the last chip.

## Considered Options

- **Keep "choose rows" for Snooze.** Rejected: the marked set was not visible, and ↩ by reflex could Snooze all the Topics of a Tag.
- **"Chips in the search field"**, rejected in ADR 0020, and **"Chips in the Snooze search field"**, rejected in [ADR 0024](0024-tags-come-from-the-topic-records.md). We turn both over. They were rejected because one search for each Topic is slow when the user wants most of them, and because ↩ and ⌫ would each get a second meaning. A Tag chip and the query row pick many Topics with one ↩, so the step is not slow. ↩ has one meaning, pick, and the way on is a row, not a second meaning of ↩. ⌫ has the meaning that it has in Edit Tags.
- **↩ in an empty query goes on.** Rejected: a highlighted row would then mean "pick" or "go on" by the state of the query.
- **⌘↩ goes on, and ↩ always picks.** Rejected: nothing in the list shows that the key exists.
- **Keep "choose rows" for other Actions on several rows.** Rejected: two steps for one job would drift. "choose rows" has no other user, so it goes away.

## Consequences

- Later Actions on several Topics, such as Mark Read or Settle, use the pick step and do not need a new ADR.
- Snooze Topic still starts at the "until" step with its Topic. ⌫ in the empty "until" field goes back to the pick step with the chips kept, so Snooze Topic can grow into a Snooze of several Topics.
- "Snooze its Topics…" on a Tag row of Go to… opens the pick step with that Tag as a chip.
- The "until" step and the Snooze write are the same as in ADR 0020: one time for the whole set, and the step names each Snooze that gets shorter.

# Tags come from the Topic records, and a Snooze by Tag is a Snooze of a set

A Topic can have Tags, such as `#backend`. Each Topic record keeps its own Tags in the field `tags`. There is no separate list of Tags. Muxify suggests the Tags that are on the Topic records now, A→Z, so a Tag goes away when the user Forgets the last Topic that has it. A Settled Topic keeps its record, so its Tags stay. A Tag is lower case, with letters, digits and `-` only, so the suggestions have no near-duplicates.

The user adds a Tag by typing `#` in a palette field (ADR [0014](0014-every-action-runs-in-the-palettes-view.md)). In New Topic, a word that starts with `#` is a Tag, not part of the title. The rows then show the Tags that match, and ⇥ or ↩ makes the Tag a chip. A space after a complete Tag also makes it a chip. "Edit Tags…" uses one field that holds the Topic's Tags as chips: ⌫ removes a chip, and ↩ writes the result. To Snooze by Tag, the user picks a Tag row in the Snooze Topics pick step (ADR [0025](0025-a-pick-step-collects-topics-and-tags-as-chips.md)). The Tag chip names every Topic that has the Tag. The result is a usual Snooze of a set, with no record.

## Considered Options

- **A list of Tags in its own file.** Rejected: the list must then be kept the same as the records. A Tag with no Topic would stay in the suggestions after Forget.
- **A choose-rows step for Tags in New Topic.** Rejected: it adds a step to every New Topic, also when the user wants no Tag. With `#`, a Topic with no Tag is made as before.
- **Chips in the Snooze search field.** Rejected for the same reason as in ADR 0020: ↩ and ⌫ would get a second meaning in the choose step. Chips are used only in a field whose value is the Tags.
- **One Tag for each Topic.** Rejected: a Topic can be in two groups, such as `#backend` and `#release`.
- **A Snoozed Tag that stays as a rule.** A Topic that gets the Tag later would also be hidden. Rejected: this is a second kind of Snooze beside `snoozed_until`, with a record to keep, as Zen has (ADR [0009](0009-zen-remembers-the-snoozes-it-changed.md)). It is not clear what a Topic with two Tags does when only one is Snoozed.
- **Filter by `#tag`, then ⌘A.** Rejected: the user must know ⌘A, and the set is not visible as one row.

## Consequences

- The pick step of Snooze Topics ([ADR 0025](0025-a-pick-step-collects-topics-and-tags-as-chips.md)) has three sections: **Tags**, **Topics** and **Already Snoozed**. ↩ on a Tag row makes the Tag a chip, which names all its Topics. This turns over the option "Chips in the Snooze search field" below.
- A Topic that gets a Tag after a Snooze by Tag is not Snoozed.
- In Snooze Topics and Go to…, `#` in the query matches Tags, not words in titles.
- The Sidebar does not show Tags on the Topic cards. Only the Active Topic's card shows a badge with the number of Tags. Pointing to the badge lists them, and a click opens Edit Tags.
- The CLI changes Tags through the Topic service (ADR [0010](0010-the-cli-runs-topic-requests-through-muxifycore.md)), as for the other Topic requests.
- A Tag change takes only the record lock, as a Snooze does (ADR [0010](0010-the-cli-runs-topic-requests-through-muxifycore.md)). It writes one key of one record.
- In a field with chips, ⌫ in the empty field removes the last chip. When there is no chip, ⌫ goes back one step, as ADR [0014](0014-every-action-runs-in-the-palettes-view.md) says.
- In every field with chips, ← and → select a chip, and ⌫ and ⌦ remove the selected chip (ADR 0025).
- Go to… lists the Tags after the Topics, only for a query that is not empty. A Tag is not a place: it is a filter that leads to places. ↩ on a Tag row makes it a filter chip ("Go to… › #backend"), and the list then shows only the Topics with the Tag: open, Snoozed and Settled. ⌫ in the empty field removes the chip. ⌘K on a Tag row offers "Snooze its Topics…".
- The Active Topic's Tags badge is in the title line of its card, before the pin, on one centre line with the title and the pin.

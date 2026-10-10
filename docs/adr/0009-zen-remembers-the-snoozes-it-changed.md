# Zen remembers the Snoozes it changed

Zen Snoozes every open Topic except the one it keeps, until one time. It does this with ordinary Snoozes on the Topic records. It also writes one record, `$XDG_STATE_HOME/muxify/zen.json`, beside the Topic records (ADR 0006). That record holds the kept Topic, the end time, and each Topic that Zen changed with the Snooze time that Topic had before. Zen never makes a Snooze shorter. A Topic that was already Snoozed past the end time, or until the user unsnoozes it, is not changed and is not in the record. When the user ends Zen early, Muxify puts back the earlier Snooze time on each Topic in the record, or unsnoozes it when that time is past. It skips a Topic whose Snooze the user changed during Zen. When Zen reaches its end time, the usual wake unsnoozes the Topics, and Muxify removes the record.

## Considered Options

- **A bulk Snooze with no record.** Rejected: "End Zen" could not tell the Topics that Zen Snoozed from the Topics the user Snoozed for other reasons. It would then wake the wrong Topics, or make the user Unsnooze each Topic.
- **A Zen mark on each Topic record.** Rejected: the earlier Snooze time must be stored somewhere too, and a single record gives one place to read and to remove when Zen ends.

## Consequences

- There is at most one Zen at a time. While Zen is on, the Zen action ends Zen.
- Zen always keeps a Topic. No Topic is not a Topic, so while No Topic is the Active Topic, "Zen…" is disabled and the `zen_mode` key does nothing. "End Zen" is always available.
- No Topic has no record, so Zen cannot Snooze it. Zen quiets it in the Sidebar's model instead: while Zen is on, No Topic's Agents show no Notification mark or working dot on any card or Switcher row, and are not in the Agents section, in Topics mode and in Sessions mode. Unread does not change, so the marks come back when Zen ends.
- Zen does not change which No Topic Sessions the Sidebar shows. With or without Zen, the Topic list has no No Topic group. It shows one card after the open Topics, for the No Topic Session of the selected Window, and no card while the Active Topic is a Topic. Sessions mode still lists every Session. The Switcher still reaches every No Topic Session, through its Project row or its Session row.
- A Topic made during Zen is not Snoozed. Going to a Zen-Snoozed Topic through the Switcher keeps its Snooze, as for any Snooze.
- When the user Settles the kept Topic, Zen ends.

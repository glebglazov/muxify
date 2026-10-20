import AppKit
import MuxifyCore

/// A key that can act on the chips of a palette field.
enum ChipKey: Equatable {
    case left(caretAtStart: Bool)
    case right
    case deleteBackward(textIsEmpty: Bool)
    case deleteForward
    /// A key that returns the caret to the text: a character for the text, or a move to another row.
    case toText

    /// Nil for a key that never acts on chips, such as ↑ or a key with ⌘.
    init?(_ trigger: KeyTrigger, caretAtStart: Bool, textIsEmpty: Bool) {
        switch (trigger.key, trigger.modifiers) {
        case (.special(.left), []): self = .left(caretAtStart: caretAtStart)
        case (.special(.right), []): self = .right
        case (.special(.backspace), []): self = .deleteBackward(textIsEmpty: textIsEmpty)
        case (.special(.delete), []): self = .deleteForward
        case (.character, let modifiers) where modifiers.subtracting(.shift).isEmpty: self = .toText
        default: return nil
        }
    }
}

/// The chips of a palette field, in the order the user made them, and the selected one. A nil selection means
/// the caret is in the text. Tag fields and the pick step hold their chips in this one model, so the chip keys
/// work the same in each.
struct ChipField<Chip: Equatable>: Equatable {
    var chips: [Chip]
    var selection: Int? = nil

    /// The field after `key`, or nil when the key is not for the chips and the text takes it.
    func receiving(_ key: ChipKey) -> ChipField? {
        var next = self
        switch (key, selection) {
        case (.left, let index?): next.selection = max(0, index - 1)
        case (.left(caretAtStart: true), nil) where !chips.isEmpty: next.selection = chips.count - 1
        case (.right, let index?): next.selection = index + 1 < chips.count ? index + 1 : nil
        case (.deleteBackward, let index?):
            next.chips.remove(at: index)
            next.selection = index > 0 ? index - 1 : nil
        case (.deleteBackward(textIsEmpty: true), nil) where !chips.isEmpty:
            next.chips.removeLast()
        case (.deleteForward, let index?):
            next.chips.remove(at: index)
            next.selection = index < next.chips.count ? index : nil
        case (.toText, _?): next.selection = nil
        default: return nil
        }
        return next
    }

    /// Adds `chip` once, and puts the caret back in the text.
    mutating func append(_ chip: Chip) {
        if !chips.contains(chip) { chips.append(chip) }
        selection = nil
    }
}

extension PaletteFlow {
    /// The step after a chip key; nil when the step has no chips or the key is not for them.
    func receiving(_ key: ChipKey) -> PaletteFlow? {
        switch self {
        case .text(.tags(var field)):
            guard let chips = field.chipField.receiving(key) else { return nil }
            field.chipField = chips
            return .text(.tags(field))
        case .snooze(var draft) where draft.step == .pick:
            guard let chips = draft.chipField.receiving(key) else { return nil }
            draft.chipField = chips
            return .snooze(draft)
        default:
            return nil
        }
    }
}

/// A chip as the search field shows it.
struct FieldChip: Identifiable {
    enum Kind { case tag, topic }
    /// The accessibility identifier.
    let id: String
    let title: String
    let kind: Kind
    var count: Int? = nil
    var isSelected = false
}

extension CommandPalette {
    /// True when the key acted on the chips. The highlighted row stays.
    @discardableResult
    func receiveChipKey(_ key: ChipKey) -> Bool {
        guard let next = flow?.receiving(key) else { return false }
        let highlighted = selectedID
        replaceFlow(next)
        selectedID = highlighted
        return true
    }

    /// A chip key from the keyboard. A typed character returns the caret to the end of the text first, and then the
    /// field takes it, so the call returns false.
    func handleChipKey(_ trigger: KeyTrigger, editor: NSTextView) -> Bool {
        let caret = editor.selectedRange()
        guard let key = ChipKey(trigger, caretAtStart: caret.location == 0 && caret.length == 0, textIsEmpty: query.isEmpty),
              receiveChipKey(key) else { return false }
        guard key == .toText else { return true }
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        return false
    }

    /// The chips of the step, or the Tag filter of a search.
    var fieldChips: [FieldChip] {
        switch presentation {
        case .search(_, let tag?)?:
            return [FieldChip(id: "palette-tag-" + tag.name, title: tag.description, kind: .tag)]
        case .flow(.text(.tags(let field)))?:
            return field.chipField.chips.enumerated().map { index, tag in
                FieldChip(id: "palette-tag-" + tag.name, title: tag.description, kind: .tag, isSelected: index == field.chipField.selection)
            }
        case .flow(.snooze(let draft))? where draft.step == .pick:
            let topics = pickableTopics
            return draft.chipField.chips.enumerated().map { index, chip in
                let isSelected = index == draft.chipField.selection
                switch chip {
                case .tag(let tag):
                    return FieldChip(id: "palette-tag-" + tag.name, title: tag.description, kind: .tag,
                                     count: PickChip.topicIDs([chip], in: topics).count, isSelected: isSelected)
                case .topic(let id):
                    return FieldChip(id: "palette-topic-" + id, title: topicTitle(id: id), kind: .topic, isSelected: isSelected)
                }
            }
        default:
            return []
        }
    }
}

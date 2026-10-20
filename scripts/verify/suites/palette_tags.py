"""Tags on Topics: `#` in New Topic, Edit Tags with chips, and no Tags in the Sidebar.

The driver cannot type keys. A check opens Commands from its View menu item. In a field that takes Tags, the
search field's Toggle Choice action is what Tab calls on a Tag row, Accept is what Return calls, Space is what
the space key does before the field takes it, and Back is what Backspace in the empty field calls
(UI/PaletteFlow.swift, UI/CommandPalette.swift). Select Previous Chip, Select Next Chip, Remove Selected Chip
Backward and Remove Selected Chip Forward are what Left at the text start, Right, Backspace and Forward Delete on a
chip call (UI/PaletteChips.swift).

Run from the repo root after `make build`:
    python3 -m unittest -v scripts.verify.suites.palette_tags
"""

import unittest

from scripts.verify.palette_fixture import PaletteFixture
from scripts.verify.sandbox import remove_topic, wait


class PaletteTags(PaletteFixture):
    def type(self, query):
        self.s.act('set', 'palette-search', query)
        return self.s.wait_rows(lambda rs: self.s.row('palette-search', rs).get('accessibilityValue', '') == query,
                                'the field did not take %r' % query)

    def field(self, rs):
        return self.s.row('palette-search', rs).get('accessibilityValue', '')

    def chips(self, rs):
        return [key[len('palette-tag-'):] for key in self.s.ids(rs) if key.startswith('palette-tag-')]

    def selected_chip(self, rs):
        return next((key[len('palette-tag-'):] for key in self.s.ids(rs)
                     if key.startswith('palette-tag-') and self.s.row(key, rs).get('accessibilityValue') == 'selected'), None)

    def wait_chips(self, chips, selected, message):
        return self.s.wait_rows(lambda rs: self.chips(rs) == chips and self.selected_chip(rs) == selected,
                                '%s: want the chips %s with %s selected' % (message, chips, selected))

    def tag_rows(self, rs):
        return [key[len('palette-row-'):] for key in self.s.ids(rs) if key.startswith('palette-row-tag-') or key == 'palette-row-new-tag']

    def new_topic(self):
        self.run_command('New Topic')
        self.s.wait_rows(lambda rs: 'New Topic' in self.text('palette-breadcrumb', rs), 'New Topic did not open')

    def edit_tags(self, name, order, tags):
        """Edit Tags for a new Active Topic with `tags`; returns the dump once the chips show."""
        self.select(self.topic(name, order, session=True, tags=tags))
        self.run_command('Edit Tags…')
        return self.s.wait_rows(lambda rs: name + ' › Edit Tags' in self.text('palette-breadcrumb', rs) and self.chips(rs) == sorted(tags),
                                'Edit Tags did not open with the Tags %s as chips' % sorted(tags))

    def test_a_lone_hash_in_new_topic_suggests_every_tag_on_the_records_settled_ones_too(self):
        self.topic('nt-open', 1, tags=['release', 'backend'])
        self.topic('nt-settled', 2, tags=['writing'], settled_at='2026-01-01T00:00:00Z')
        self.new_topic()
        self.type('Ship it #')
        self.s.wait_rows(lambda rs: self.tag_rows(rs) == ['tag-backend', 'tag-release', 'tag-writing'],
                         'a lone # does not show every Tag on the records, Settled ones too, A→Z')

    def test_letters_after_hash_filter_the_suggestions_and_offer_a_new_tag(self):
        self.topic('nt-filter', 3, tags=['release', 'backend'])
        self.new_topic()
        self.type('Ship it #re')
        rs = self.s.wait_rows(lambda rs: self.tag_rows(rs) == ['tag-release', 'new-tag'], 'the rows did not filter for #re')
        self.assertIn('makes a chip', self.text('palette-note', rs))

    def test_return_on_a_tag_row_makes_a_chip_and_takes_the_draft_out_of_the_field(self):
        self.topic('nt-return', 4, tags=['release'])
        self.new_topic()
        self.type('Ship it #rel')
        self.s.wait_rows(lambda rs: self.tag_rows(rs)[:1] == ['tag-release'], 'the Tag row did not show first')
        self.s.act('action', 'palette-search', 'Accept')
        rs = self.s.wait_rows(lambda rs: self.chips(rs) == ['release'] and not self.tag_rows(rs),
                              'Return on the highlighted Tag row did not make a chip')
        self.assertEqual(self.field(rs), 'Ship it ', 'the chip did not take the draft out of the field')

    def test_tab_on_new_tag_makes_a_chip_of_a_tag_that_no_record_has(self):
        self.new_topic()
        self.type('Ship #fresh')
        self.s.wait_rows(lambda rs: self.tag_rows(rs) == ['new-tag'], 'a Tag that no record has did not offer New Tag')
        self.s.act('action', 'palette-search', 'Toggle Choice')
        self.s.wait_rows(lambda rs: self.chips(rs) == ['fresh'], 'Tab on New Tag did not make a chip')

    def test_a_space_after_a_tag_word_in_new_topic_makes_a_chip(self):
        self.new_topic()
        self.type('Ship #Quick')
        self.s.act('action', 'palette-search', 'Space')
        rs = self.s.wait_rows(lambda rs: self.chips(rs) == ['quick'], 'a space after #Quick did not make the chip #quick')
        self.assertEqual(self.field(rs), 'Ship ', 'the chip did not take the Tag word out of the field')

    def test_the_new_topic_note_names_the_title_and_the_tags(self):
        self.new_topic()
        self.type('Ship it #one #two ')
        self.s.wait_rows(lambda rs: 'Title: Ship it · Tags: #one #two' in self.text('palette-note', rs),
                         'the note does not name the title and the Tags')

    def test_return_in_new_topic_writes_the_title_and_the_tags(self):
        before = {record['id'] for record in self.records()}
        self.new_topic()
        self.type('Ship it #fresh')
        self.s.act('action', 'palette-search', 'Space')
        self.s.wait_rows(lambda rs: self.chips(rs) == ['fresh'], 'a space did not make a chip')
        self.type('Ship it #more ')
        self.s.act('action', 'palette-search', 'Accept')
        made = wait(lambda: next((record for record in self.records() if record['id'] not in before), None),
                    'New Topic did not write a record')
        self.addCleanup(remove_topic, self.topics/(made['id'] + '.json'))
        self.assertEqual((made.get('title'), made.get('tags')), ('Ship it', ['fresh', 'more']), made)
        self.s.wait_rows(lambda rs: 'Add a Project' in self.text('palette-breadcrumb', rs), 'New Topic did not go on to Add a Project')
        self.s.act('action', 'palette-search', 'Close')

    def test_edit_tags_opens_with_the_tags_of_the_active_topic_as_chips(self):
        self.edit_tags('ed-open', 11, ['ops', 'backend'])

    def test_back_in_an_empty_edit_tags_field_removes_the_last_chip(self):
        self.edit_tags('ed-back', 12, ['ops', 'backend'])
        self.s.act('action', 'palette-search', 'Back')
        rs = self.s.wait_rows(lambda rs: self.chips(rs) == ['backend'], 'Backspace in the empty field did not remove the last chip')
        self.assertIn('Removes: #ops', self.text('palette-note', rs))

    def test_a_space_after_a_word_in_edit_tags_makes_a_chip_that_back_removes_whole(self):
        self.edit_tags('ed-space', 13, ['backend'])
        self.type('QA')
        self.s.act('action', 'palette-search', 'Space')
        rs = self.s.wait_rows(lambda rs: self.chips(rs) == ['backend', 'qa'], 'a space after QA did not make the chip #qa')
        self.assertEqual(self.field(rs), '', 'the chip did not take the word out of the field')
        self.s.act('action', 'palette-search', 'Back')
        self.s.wait_rows(lambda rs: self.chips(rs) == ['backend'], 'Backspace did not remove the new chip whole')

    def test_return_in_edit_tags_writes_the_chips_and_the_typed_tags(self):
        self.edit_tags('ed-write', 14, ['ops', 'backend'])
        self.type('qa')
        self.s.act('action', 'palette-search', 'Space')
        self.s.wait_rows(lambda rs: self.chips(rs) == ['backend', 'ops', 'qa'], 'a space did not make a chip')
        self.type('#Docs ')
        self.s.act('action', 'palette-search', 'Accept')
        self.s.wait_rows(lambda rs: not self.s.has('palette-search', rs), 'Return did not save and close')
        wait(lambda: self.record('ed-write').get('tags') == ['backend', 'docs', 'ops', 'qa'],
             'Edit Tags did not write the Tags: %s' % self.record('ed-write'))

    def test_an_empty_edit_tags_field_removes_every_tag(self):
        self.edit_tags('ed-empty', 15, ['ops', 'backend'])
        self.s.act('action', 'palette-search', 'Back')
        self.s.act('action', 'palette-search', 'Back')
        self.s.wait_rows(lambda rs: not self.chips(rs) and 'ed-empty › Edit Tags' in self.text('palette-breadcrumb', rs),
                         'Backspace did not remove every chip and keep the step')
        self.s.act('action', 'palette-search', 'Accept')
        self.s.wait_rows(lambda rs: not self.s.has('palette-search', rs), 'Return did not save and close')
        wait(lambda: 'tags' not in self.record('ed-empty'), 'an empty field did not remove every Tag: %s' % self.record('ed-empty'))

    def test_chip_keys_in_edit_tags_select_and_remove_tags_and_return_writes_the_rest(self):
        self.edit_tags('ed-keys', 16, ['alpha', 'bravo', 'charlie'])
        self.s.act('action', 'palette-search', 'Select Previous Chip')
        self.wait_chips(['alpha', 'bravo', 'charlie'], 'charlie', 'Left at the text start did not select the last chip')
        self.s.act('action', 'palette-search', 'Remove Selected Chip Forward')
        self.wait_chips(['alpha', 'bravo'], None, 'Forward Delete on the last chip did not remove it and put the caret back')
        self.s.act('action', 'palette-search', 'Select Previous Chip')
        self.s.act('action', 'palette-search', 'Select Previous Chip')
        self.wait_chips(['alpha', 'bravo'], 'alpha', 'Left did not move the selection to the left')
        self.s.act('action', 'palette-search', 'Select Next Chip')
        self.wait_chips(['alpha', 'bravo'], 'bravo', 'Right did not move the selection to the right')
        self.s.act('action', 'palette-search', 'Remove Selected Chip Backward')
        rs = self.wait_chips(['alpha'], 'alpha', 'Backspace on a chip did not remove it and select the chip to its left')
        self.assertIn('Removes: #bravo #charlie', self.text('palette-note', rs))
        self.s.act('action', 'palette-search', 'Remove Selected Chip Backward')
        self.wait_chips([], None, 'Backspace on the first chip did not remove it and put the caret back')
        self.s.act('action', 'palette-search', 'Accept')
        self.s.wait_rows(lambda rs: not self.s.has('palette-search', rs), 'Return did not save and close')
        wait(lambda: 'tags' not in self.record('ed-keys'), 'Edit Tags did not write the chips that stay: %s' % self.record('ed-keys'))

    def test_chip_keys_in_new_topic_select_a_tag_and_typing_puts_the_caret_back(self):
        self.new_topic()
        self.type('Ship #one')
        self.s.act('action', 'palette-search', 'Space')
        self.wait_chips(['one'], None, 'a space did not make the chip #one')
        self.type('Ship #two')
        self.s.act('action', 'palette-search', 'Space')
        self.wait_chips(['one', 'two'], None, 'a space did not make the chip #two')
        self.s.act('action', 'palette-search', 'Select Previous Chip')
        self.wait_chips(['one', 'two'], 'two', 'Left at the text start did not select the last chip')
        self.type('Ship it')
        self.wait_chips(['one', 'two'], None, 'typing did not put the caret back in the text')
        self.s.act('action', 'palette-search', 'Select Previous Chip')
        self.s.act('action', 'palette-search', 'Remove Selected Chip Backward')
        rs = self.wait_chips(['one'], 'one', 'Backspace on a chip did not remove it and select the chip to its left')
        self.assertEqual(self.field(rs), 'Ship it', 'a chip key changed the text')
        self.s.act('action', 'palette-search', 'Close')

    def test_the_active_topic_card_shows_no_tags(self):
        self.select(self.topic('no-badge', 21, session=True, tags=['ops']))
        rs = self.s.wait_rows(lambda rs: self.s.has('topic-no-badge', rs), 'the Active Topic has no card')
        shown = [r.get('accessibilityIdentifier', '') for r in rs if '#ops' in r.get('accessibilityLabel', '')
                 or r.get('accessibilityIdentifier', '').startswith('tags-badge')]
        self.assertEqual(shown, [], 'the Sidebar shows the Topic\'s Tags')


if __name__ == '__main__':
    unittest.main()

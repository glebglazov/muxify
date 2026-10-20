"""Every Snooze goes through one palette flow: a pick step of Topic and Tag chips, then one time for the whole set.

The driver cannot type keys. A check opens Commands from its View menu item, and starts Snooze again
through the Snoozed row's accessibility action (GroupedTopicRow in UI/SidebarView.swift). In the pick step,
Accept and Back are what Return and Backspace in the empty field call. Select Previous Chip, Select Next Chip,
Remove Selected Chip Backward and Select Next Row are what Left at the text start, Right, Backspace on a chip and Down call
(UI/CommandPaletteView.swift, UI/PaletteChips.swift).

Run from the repo root after `make build`:
    python3 -m unittest -v scripts.verify.suites.palette_snooze_topics
"""

import datetime
import subprocess
import unittest

from scripts.verify.palette_fixture import PaletteFixture
from scripts.verify.sandbox import DEBUG_APP, frame, wait

CLI = DEBUG_APP/'Contents/Resources/bin/muxify'

LATER = '2099-01-01T00:00:00Z'


class PaletteSnoozeTopics(PaletteFixture):
    def filter(self, query):
        self.s.act('set', 'palette-search', query)
        self.s.wait_rows(lambda rs: self.s.row('palette-search', rs).get('accessibilityValue', '') == query,
                         'the pick step did not take the query %r' % query)

    def chips(self, rs):
        """The chips in the field, in order: `#tag` for a Tag, the id for a Topic, and `*` after the selected one."""
        out = []
        for row in rs:
            key = row.get('accessibilityIdentifier', '')
            mark = '*' if row.get('accessibilityValue') == 'selected' else ''
            if key.startswith('palette-tag-'):
                out.append('#' + key[len('palette-tag-'):] + mark)
            elif key.startswith('palette-topic-'):
                out.append(key[len('palette-topic-'):] + mark)
        return out

    def wait_chips(self, chips, message):
        return self.s.wait_rows(lambda rs: self.chips(rs) == chips, '%s: want the chips %s' % (message, chips))

    def wait_step(self, crumb):
        return self.s.wait_rows(lambda rs: crumb in self.text('palette-breadcrumb', rs) and self.s.has('palette-note', rs),
                                'the step %r did not show' % crumb)

    def open_pick(self):
        self.run_command('Snooze Topics…')
        return self.wait_step('Snooze Topics › pick')

    def pick(self, query, chips):
        """Types `query`, presses Return on the highlighted row, and waits for `chips` and an empty query."""
        self.filter(query)
        self.s.act('action', 'palette-search', 'Accept')
        return self.s.wait_rows(lambda rs: self.chips(rs) == chips and self.s.row('palette-search', rs).get('accessibilityValue', '') == '',
                                'Return on the row for %r did not make the chips %s and clear the query' % (query, chips))

    def test_snooze_again_with_an_earlier_time_writes_it_and_names_the_shorter_snooze(self):
        s = self.s
        self.topic('snz-again', 1, snoozed_until=LATER)
        rs = s.wait_rows(lambda rs: s.has('snoozed-topics', rs), 'the Snoozed group did not show')
        if s.row('snoozed-topics', rs).get('accessibilityValue') != 'expanded':
            s.act('press', 'snoozed-topics')
        s.wait_rows(lambda rs: s.has('topic-snz-again', rs), 'the Snoozed Topic did not show')
        s.act('action', 'topic-snz-again', 'Snooze again…')
        rs = s.wait_rows(lambda rs: s.has('palette-row-0', rs) and s.has('palette-note', rs), 'the "until" step did not show its note')
        self.assertIn('snz-again › Snooze › until', self.text('palette-breadcrumb', rs))
        self.assertIn('Gets shorter: snz-again', self.text('palette-note', rs), 'the note does not name the shorter Snooze')
        s.act('press', 'palette-row-0')
        s.wait_rows(lambda rs: not s.has('palette-search', rs), 'Snooze did not close the palette')
        stored = wait(lambda: (lambda value: value if value != LATER else None)(self.record('snz-again').get('snoozed_until')),
                      'the earlier time was not written', seconds=10)
        until = datetime.datetime.strptime(stored, '%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc)
        self.assertLess(until, datetime.datetime(2099, 1, 1, tzinfo=datetime.timezone.utc), stored)

    def test_the_pick_step_starts_with_no_chip_and_lists_tags_then_topics_then_already_snoozed(self):
        s = self.s
        self.topic('pk-alpha', 11, tags=['pkfirst'])
        self.topic('pk-snoozed', 12, snoozed_until=LATER)
        self.topic('pk-settled', 13, settled_at='2026-01-01T00:00:00Z')
        self.select(self.topic('pk-active', 14, session=True))
        rs = self.open_pick()
        self.assertEqual(self.chips(rs), [], 'the pick step started with a chip')
        self.assertFalse(s.has('palette-row-snooze-picked', rs), 'the go-on row shows with no chip')
        ids = s.ids(rs)
        self.assertLess(ids.index('palette-section-tags'), ids.index('palette-section-topics'), ids)
        self.assertLess(ids.index('palette-section-topics'), ids.index('palette-section-snoozed'), ids)
        self.assertTrue(s.has('palette-row-topic-pk-snoozed', rs), 'a Snoozed Topic is not listed')
        self.assertFalse(s.has('palette-row-topic-pk-settled', rs), 'a Settled Topic is listed')

    def test_return_picks_the_highlighted_row_as_a_chip_and_the_row_leaves_the_list(self):
        s = self.s
        self.topic('rp-one', 21)
        self.topic('rp-two', 22)
        self.open_pick()
        rs = self.pick('rp-one', ['rp-one'])
        self.assertFalse(s.has('palette-row-topic-rp-one', rs), 'the picked Topic is still a row')
        self.assertIn('→ Snooze 1 Topic…', self.text('palette-row-snooze-picked', rs))
        self.assertIn('selected', self.text('palette-row-snooze-picked', rs), 'the go-on row is not the first row')
        self.assertIn('Snoozes: rp-one', self.text('palette-note', rs))
        self.assertIn('Snooze Topics › pick', self.text('palette-breadcrumb', rs), 'Return on a row left the pick step')
        self.assertIsNone(self.record('rp-one').get('snoozed_until'), 'Return on a row Snoozed')

    def test_a_picked_tag_keeps_its_topics_dim_with_the_tag_and_return_on_a_tag_never_snoozes(self):
        s = self.s
        self.topic('pt-one', 31, tags=['ptag'])
        self.topic('pt-two', 32, tags=['ptag'])
        self.topic('pt-none', 33)
        self.open_pick()
        rs = self.pick('#ptag', ['#ptag'])
        for name in ('pt-one', 'pt-two'):
            self.assertIn('in #ptag', self.text('palette-row-topic-' + name, rs), name)
            self.assertIn('covered', self.s.row('palette-row-topic-' + name, rs).get('accessibilityValue', ''), name)
        self.assertNotIn('covered', self.s.row('palette-row-topic-pt-none', rs).get('accessibilityValue', ''))
        self.assertFalse(s.has('palette-row-tag-ptag', rs), 'the picked Tag is still a row')
        self.assertIn('→ Snooze 2 Topics…', self.text('palette-row-snooze-picked', rs))
        self.assertTrue(all(self.record(name).get('snoozed_until') is None for name in ('pt-one', 'pt-two')),
                        'Return on a Tag row Snoozed its Topics')

    def test_the_query_row_picks_every_topic_that_the_query_matches(self):
        s = self.s
        self.topic('qr-one', 41, title='qr-one qrpair')
        self.topic('qr-two', 42, title='qr-two qrpair')
        self.topic('qr-other', 43)
        self.open_pick()
        self.filter('qrpair')
        rs = s.wait_rows(lambda rs: s.has('palette-row-pick-all', rs), 'the query row did not show')
        self.assertIn('＋ All 2 matches for “qrpair”', self.text('palette-row-pick-all', rs))
        s.act('press', 'palette-row-pick-all')
        self.wait_chips(['qr-one', 'qr-two'], 'the query row did not pick every match')

    def test_chip_keys_select_and_remove_the_picked_chips(self):
        s = self.s
        for index, name in enumerate(['ck-one', 'ck-two', 'ck-three']):
            self.topic(name, 51 + index)
        self.open_pick()
        self.pick('ck-one', ['ck-one'])
        self.pick('ck-two', ['ck-one', 'ck-two'])
        self.pick('ck-three', ['ck-one', 'ck-two', 'ck-three'])
        s.act('action', 'palette-search', 'Select Previous Chip')
        self.wait_chips(['ck-one', 'ck-two', 'ck-three*'], 'Left at the text start did not select the last chip')
        s.act('action', 'palette-search', 'Select Previous Chip')
        self.wait_chips(['ck-one', 'ck-two*', 'ck-three'], 'Left did not select the chip to the left')
        s.act('action', 'palette-search', 'Remove Selected Chip Backward')
        rs = self.wait_chips(['ck-one*', 'ck-three'], 'Backspace on a chip did not remove it and select the chip to its left')
        self.assertTrue(s.has('palette-row-topic-ck-two', rs), 'the removed Topic did not come back as a row')
        s.act('action', 'palette-search', 'Select Next Chip')
        s.act('action', 'palette-search', 'Select Next Chip')
        self.wait_chips(['ck-one', 'ck-three'], 'Right after the last chip did not put the caret back')
        s.act('action', 'palette-search', 'Select Previous Chip')
        self.wait_chips(['ck-one', 'ck-three*'], 'Left at the text start did not select the last chip again')
        s.act('action', 'palette-search', 'Select Next Row')
        self.wait_chips(['ck-one', 'ck-three'], 'Down to another row did not put the caret back')

    def test_a_snooze_by_tag_writes_one_time_on_its_topics_and_no_other_field(self):
        tagged = ['tgsnooze-one', 'tgsnooze-two', 'tgsnooze-three']
        self.topic(tagged[0], 61, tags=['tgsnooze'])
        self.topic(tagged[1], 62, tags=['tgsnooze', 'other'])
        self.topic(tagged[2], 63, tags=['tgsnooze'], snoozed_until=LATER)
        self.topic('tgsnooze-none', 64)
        self.select(self.topic('tgsnooze-active', 65, session=True))
        self.open_pick()
        self.pick('#tgsnooze', ['#tgsnooze'])
        self.s.act('action', 'palette-search', 'Accept')
        self.wait_step('3 Topics › Snooze › until')
        self.s.act('press', 'palette-row-0')
        self.s.wait_rows(lambda rs: not self.s.has('palette-search', rs), 'Snooze did not close the palette')
        names = tagged + ['tgsnooze-none', 'tgsnooze-active']
        times = {name: self.record(name).get('snoozed_until') for name in names}
        self.assertEqual(len({times[name] for name in tagged}), 1, times)
        self.assertNotIn(times['tgsnooze-one'], (None, LATER), times)
        self.assertIsNone(times['tgsnooze-none'], times)
        self.assertIsNone(times['tgsnooze-active'], 'a Topic with no chip was Snoozed: %s' % times)
        self.assertEqual(sorted(self.record('tgsnooze-one')), ['home_project', 'id', 'order', 'sessions', 'slug', 'snoozed_until', 'tags', 'title'],
                         'a Snooze by Tag writes a usual Snooze and no other field')

    def test_snooze_topics_writes_one_time_on_the_set_names_the_shorter_snooze_and_opens_the_next_topic_outside_it(self):
        s = self.s
        self.topic('nx-a', 71, session=True)
        active = self.topic('nx-b', 72, session=True)
        self.topic('nx-c', 73)
        after = self.topic('nx-d', 74, session=True)
        self.topic('nx-f', 76, snoozed_until=LATER)
        self.select(active)
        self.open_pick()
        self.pick('nx-b', ['nx-b'])
        self.pick('nx-f', ['nx-b', 'nx-f'])
        rs = self.pick('nx-c', ['nx-b', 'nx-f', 'nx-c'])
        self.assertIn('Snoozes: nx-b, nx-c, nx-f', self.text('palette-note', rs), 'the note does not name the set in list order')
        self.assertIn('Then opens: nx-d', self.text('palette-note', rs), 'the pick step does not name the Next Topic')
        s.act('action', 'palette-search', 'Accept')
        rs = self.wait_step('3 Topics › Snooze › until')
        note = self.text('palette-note', rs)
        self.assertIn('Snoozes: nx-b, nx-c, nx-f', note)
        self.assertIn('Gets shorter: nx-f', note)
        self.assertIn('Then opens: nx-d', note, 'the Next Topic skips the rows that leave the list with the set')
        s.act('press', 'palette-row-0')
        s.wait_rows(lambda rs: not s.has('palette-search', rs), 'Snooze did not close the palette')
        s.wait_shown(after)
        times = {name: self.record(name).get('snoozed_until') for name in ['nx-a', 'nx-b', 'nx-c', 'nx-d', 'nx-f']}
        self.assertEqual(len({times['nx-b'], times['nx-c'], times['nx-f']}), 1, times)
        self.assertNotIn(times['nx-f'], (None, LATER), 'the shorter Snooze was not written: %s' % times)
        self.assertIsNone(times['nx-a'], times)
        self.assertIsNone(times['nx-d'], times)

    def test_back_in_the_until_step_goes_back_to_pick_with_the_chips_kept(self):
        self.topic('bk-one', 81, tags=['bktag'])
        self.topic('bk-two', 82)
        self.open_pick()
        self.pick('#bktag', ['#bktag'])
        self.pick('bk-two', ['#bktag', 'bk-two'])
        self.s.act('action', 'palette-search', 'Accept')
        self.wait_step('2 Topics › Snooze › until')
        self.s.act('action', 'palette-search', 'Back')
        rs = self.wait_step('Snooze Topics › pick')
        self.assertEqual(self.chips(rs), ['#bktag', 'bk-two'], 'Back did not keep the chips')

    def test_snooze_topic_starts_at_until_and_back_opens_pick_with_its_topic_as_a_chip(self):
        s = self.s
        self.select(self.topic('st-one', 91, session=True))
        self.run_command('Snooze Topic')
        rs = self.wait_step('st-one › Snooze › until')
        self.assertTrue(s.has('palette-row-never', rs), 'the "until" step has no times')
        self.assertIn('⌫ goes back to pick', self.text('palette-note', rs))
        s.act('action', 'palette-search', 'Back')
        rs = self.wait_step('Snooze Topics › pick')
        self.assertEqual(self.chips(rs), ['st-one'], 'Back did not open pick with the Topic as a chip')
        s.act('action', 'palette-search', 'Accept')
        self.wait_step('st-one › Snooze › until')
        s.act('action', 'palette-search', 'Close')
        s.wait_rows(lambda rs: not s.has('palette-search', rs), 'Close did not close the palette')
        self.assertIsNone(self.record('st-one').get('snoozed_until'), 'Close after the steps Snoozed the Topic')

    def test_topic_snooze_from_the_cli_moves_the_topic_to_snoozed_and_keeps_its_session(self):
        s = self.s
        window = self.topic('cli-snz', 41, session=True)
        rs = s.wait_rows(lambda rs: s.has('topic-cli-snz', rs), 'the open Topic did not show')
        self.assertFalse(s.has('unsnooze-topic-cli-snz', rs), 'the Topic was Snoozed before the command')
        pane = s.tmux('display-message', '-p', '-t', window, '#{pane_id}')
        result = subprocess.run([str(CLI), 'topic', 'snooze', 'tomorrow', '--pane', pane], env=s.env,
                                capture_output=True, text=True, timeout=30)
        self.assertEqual((result.returncode, result.stdout, result.stderr), (0, 'cli-snz\n', ''))
        rs = s.wait_rows(lambda rs: s.has('snoozed-topics', rs), 'the Snoozed group did not show')
        if s.row('snoozed-topics', rs).get('accessibilityValue') != 'expanded':
            s.act('press', 'snoozed-topics')
        s.wait_rows(lambda rs: s.has('unsnooze-topic-cli-snz', rs), 'the Topic did not move to Snoozed')
        self.assertEqual(s.tmux('show-options', '-qv', '-t', '=cli-snz:', '@muxify_topic'), 'cli-snz', 'the Session left the Topic')

    def test_topic_snooze_and_unsnooze_from_the_cli_move_several_topics_and_back(self):
        s = self.s
        self.topic('cli-a', 42)
        self.topic('cli-b', 43)
        s.wait_rows(lambda rs: s.has('topic-cli-a', rs) and s.has('topic-cli-b', rs), 'the open Topics did not show')
        def cli(*args):
            result = subprocess.run([str(CLI), 'topic', *args], env=s.env, capture_output=True, text=True, timeout=30)
            return (result.returncode, result.stdout, result.stderr)
        self.assertEqual(cli('snooze', 'tomorrow', '--topic', 'cli-a', '--topic', 'cli-b'), (0, 'cli-a\ncli-b\n', ''))
        rs = s.wait_rows(lambda rs: s.has('snoozed-topics', rs), 'the Snoozed group did not show')
        if s.row('snoozed-topics', rs).get('accessibilityValue') != 'expanded':
            s.act('press', 'snoozed-topics')
        s.wait_rows(lambda rs: s.has('unsnooze-topic-cli-a', rs) and s.has('unsnooze-topic-cli-b', rs),
                    'the Topics did not move to Snoozed')
        self.assertEqual(cli('unsnooze', '--topic', 'cli-a', '--topic', 'cli-b'), (0, 'cli-a\ncli-b\n', ''))
        s.wait_rows(lambda rs: s.has('topic-cli-a', rs) and s.has('topic-cli-b', rs) and not s.has('unsnooze-topic-cli-a', rs)
                    and not s.has('unsnooze-topic-cli-b', rs), 'the Topics did not move back to the open Topics')
        self.assertIsNone(self.record('cli-a').get('snoozed_until'), 'Unsnooze left the Snooze in the record')

    def test_topics_whose_snooze_ends_at_its_time_come_back_at_the_bottom_in_their_earlier_order(self):
        s = self.s
        past = '2000-01-01T00:00:00Z'
        self.topic('wake-b', 50, snoozed_until=past)
        self.topic('wake-a', 51, snoozed_until=past)
        self.topic('wake-c', 52)
        wait(lambda: all(self.record(name).get('snoozed_until') is None for name in ('wake-a', 'wake-b')),
             'the app did not wake the due Topics')
        orders = {name: self.record(name).get('order') for name in ('wake-a', 'wake-b', 'wake-c')}
        self.assertLess(orders['wake-c'], orders['wake-b'], orders)
        self.assertLess(orders['wake-b'], orders['wake-a'], orders)
        names = ['wake-a', 'wake-b', 'wake-c']
        def shown(rs):
            return all(s.has('topic-' + name, rs) for name in names) and \
                sorted(names, key=lambda name: -frame(s.row('topic-' + name, rs))[1]) == ['wake-c', 'wake-b', 'wake-a']
        s.wait_rows(shown, 'the Topics list did not show the woken Topics below wake-c in their earlier order')

if __name__ == '__main__':
    unittest.main()

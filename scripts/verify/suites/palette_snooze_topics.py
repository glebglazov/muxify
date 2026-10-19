"""Every Snooze goes through one palette flow: a set of Topics, then one time for the whole set.

The driver cannot type keys. A check opens Commands from its View menu item, and starts Snooze again
through the Snoozed row's accessibility action (GroupedTopicRow in UI/SidebarView.swift). In the choose
step, the search field's Toggle Choice action is what Space in an empty field and Tab call, Mark Shown is
what Cmd-A calls (UI/PaletteChooseRows.swift), and Accept and Back are what Return and Backspace call.

Run from the repo root after `make build`:
    python3 -m unittest -v scripts.verify.suites.palette_snooze_topics
"""

import datetime
import json
import subprocess
import unittest

from scripts.verify.sandbox import DEBUG_APP, Sandbox, wait

CLI = DEBUG_APP/'Contents/Resources/bin/muxify'

SHELL = '/bin/zsh -f'
LATER = '2099-01-01T00:00:00Z'


class PaletteSnoozeTopics(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.s = s = Sandbox(__name__.rsplit('.', 1)[-1])
        cls.addClassCleanup(s.teardown)
        cls.project = s.root/'projects/snooze'
        cls.project.mkdir(parents=True)
        cls.topics = s.root/'state/muxify/topics'
        cls.topics.mkdir(parents=True, exist_ok=True)
        (s.root/'config/muxify/config.yaml').write_text('sessions:\n  paths:\n    - path: ' + str(cls.project) + '\n')
        cls.base = s.tmux('new-session', '-d', '-P', '-F', '#{window_id}', '-s', 'base', '-c', str(cls.project), SHELL)
        s.tmux('set-option', '-g', 'detach-on-destroy', 'off')
        s.launch(['-sidebarVisible', 'YES', '-sessionsVisible', 'YES'])

    def setUp(self):
        if self.s.has('palette-search'):
            self.s.act('action', 'palette-search', 'Close')
        if self.s.row('sidebar-view-topics').get('accessibilityValue') != 'selected':
            self.s.act('press', 'sidebar-view-topics')
        self.select(self.base)

    def select(self, window):
        for client in self.s.tmux('list-clients', '-F', '#{client_tty} #{client_control_mode}').splitlines():
            if client.endswith(' 0'):
                self.s.tmux('switch-client', '-c', client.split()[0], '-t', window)
        self.s.wait_shown(window)

    def topic(self, name, order, session=False, **fields):
        """A Topic record, and with `session` a live Session in it; returns that Session's Window."""
        path = self.topics/(name + '.json')
        path.write_text(json.dumps(dict(dict(id=name, title=name, slug=name, home_project=str(self.project), order=order), **fields)))
        self.addCleanup(path.unlink, missing_ok=True)
        if not session:
            return None
        window = self.s.tmux('new-session', '-d', '-P', '-F', '#{window_id}', '-s', name, '-c', str(self.project), SHELL)
        self.addCleanup(self.s.tmux_ok, 'kill-session', '-t', name)
        self.s.tmux('set-option', '-t', name, '@muxify_topic', name)
        self.addCleanup(self.select, self.base)
        return window

    def record(self, name):
        return json.loads((self.topics/(name + '.json')).read_text())

    def text(self, key, rs):
        row = self.s.row(key, rs)
        return row.get('accessibilityLabel', '') + row.get('accessibilityValue', '')

    def run_command(self, title):
        wait(lambda: self.s.driver('press', 'Commands')['pressed'], 'Commands did not open')
        self.s.wait_rows(lambda rs: self.s.has('palette-search', rs), 'the Commands field did not show')
        self.s.act('focus', 'palette-search')
        self.s.act('set', 'palette-search', title)
        key = 'palette-row-command-' + title
        self.s.wait_rows(lambda rs: self.s.has(key, rs), title + ' was missing from Commands')
        self.s.act('press', key)

    def filter(self, query):
        self.s.act('set', 'palette-search', query)
        self.s.wait_rows(lambda rs: self.s.row('palette-search', rs).get('accessibilityValue', '') == query,
                         'the choose step did not take the filter %r' % query)

    def is_marked(self, name, rs):
        return 'marked' in self.s.row('palette-row-topic-' + name, rs).get('accessibilityValue', '').split(', ')

    def wait_marked(self, names, among, message):
        """The note counts every mark; the rows that the filter shows tell which ones are marked."""
        def holds(rs):
            shown = [name for name in among if self.s.has('palette-row-topic-' + name, rs)]
            return (shown and all(self.is_marked(name, rs) == (name in names) for name in shown)
                    and self.text('palette-note', rs).startswith('%d marked' % len(names)))
        return self.s.wait_rows(holds, '%s: want %s marked among %s' % (message, sorted(names), sorted(among)))

    def wait_step(self, crumb):
        return self.s.wait_rows(lambda rs: crumb in self.text('palette-breadcrumb', rs) and self.s.has('palette-note', rs),
                                'the step %r did not show' % crumb)

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


    def test_choose_step_marks_with_space_tab_and_cmd_a_and_keeps_the_marks_when_the_filter_changes(self):
        s = self.s
        among = ['mk-alpha', 'mk-bravo', 'mk-charlie', 'mk-delta', 'mk-foxtrot']
        self.topic('mk-alpha', 11)
        self.topic('mk-charlie', 13)
        self.topic('mk-delta', 14, title='mk-delta mkpair')
        self.topic('mk-foxtrot', 16, snoozed_until=LATER)
        self.topic('mk-settled', 17, settled_at='2026-01-01T00:00:00Z')
        self.select(self.topic('mk-bravo', 12, session=True, title='mk-bravo mkpair'))
        self.run_command('Snooze Topics…')
        rs = self.wait_marked(['mk-bravo'], among, 'the choose step did not start with the Active Topic marked')
        self.assertIn('Snooze Topics › choose', self.text('palette-breadcrumb', rs))
        self.assertTrue(s.has('palette-section-visible', rs) and s.has('palette-section-snoozed', rs), s.ids(rs))
        self.assertTrue(s.has('palette-row-topic-mk-foxtrot', rs), 'a Snoozed Topic is not listed')
        self.assertFalse(s.has('palette-row-topic-mk-settled', rs), 'a Settled Topic is listed')

        self.filter('mk-charlie')
        s.act('action', 'palette-search', 'Toggle Choice')
        self.wait_marked(['mk-bravo', 'mk-charlie'], among, 'Tab with a filter did not mark the highlighted row')
        self.filter('mkpair')
        s.act('action', 'palette-search', 'Mark Shown')
        self.wait_marked(['mk-bravo', 'mk-charlie', 'mk-delta'], among, 'Cmd-A did not mark every shown row')
        s.act('action', 'palette-search', 'Mark Shown')
        self.wait_marked(['mk-charlie'], among, 'Cmd-A did not unmark the shown rows when all were marked')
        s.act('press', 'palette-mark-shown')
        self.wait_marked(['mk-bravo', 'mk-charlie', 'mk-delta'], among, 'Mark all shown did not mark every shown row')

        self.filter('')
        rs = self.wait_marked(['mk-bravo', 'mk-charlie', 'mk-delta'], among, 'the marks did not stay when the filter changed')
        first = next(key for key in s.ids(rs) if key.startswith('palette-row-topic-'))[len('palette-row-topic-'):]
        before = self.is_marked(first, rs)
        s.act('action', 'palette-search', 'Toggle Choice')
        s.wait_rows(lambda rs: self.is_marked(first, rs) != before, 'Space in the empty field did not change the highlighted row')
        s.act('action', 'palette-search', 'Close')

    def test_snooze_topics_writes_one_time_on_the_set_names_the_shorter_snooze_and_opens_the_next_topic_outside_it(self):
        s = self.s
        self.topic('nx-a', 21, session=True)
        active = self.topic('nx-b', 22, session=True)
        self.topic('nx-c', 23)
        after = self.topic('nx-d', 24, session=True)
        self.topic('nx-f', 26, snoozed_until=LATER)
        self.select(active)
        self.run_command('Snooze Topics…')
        among = ['nx-a', 'nx-b', 'nx-c', 'nx-d', 'nx-f']
        self.wait_marked(['nx-b'], among, 'the choose step did not start with the Active Topic marked')
        for name in ['nx-c', 'nx-f']:
            self.filter(name)
            s.act('action', 'palette-search', 'Toggle Choice')
        self.filter('')
        rs = self.wait_marked(['nx-b', 'nx-c', 'nx-f'], among, 'the set was not marked')
        self.assertIn('Then opens: nx-d', self.text('palette-note', rs), 'the choose step does not name the Next Topic')
        s.act('action', 'palette-search', 'Accept')
        rs = self.wait_step('3 Topics › Snooze › until')
        note = self.text('palette-note', rs)
        self.assertIn('Snoozes: nx-b, nx-c, nx-f', note)
        self.assertIn('Gets shorter: nx-f', note)
        self.assertIn('Then opens: nx-d', note, 'the Next Topic skips the rows that leave the list with the set')
        s.act('press', 'palette-row-0')
        s.wait_rows(lambda rs: not s.has('palette-search', rs), 'Snooze did not close the palette')
        s.wait_shown(after)
        times = {name: self.record(name).get('snoozed_until') for name in among}
        self.assertEqual(len({times['nx-b'], times['nx-c'], times['nx-f']}), 1, times)
        self.assertNotIn(times['nx-f'], (None, LATER), 'the shorter Snooze was not written: %s' % times)
        self.assertIsNone(times['nx-a'], times)
        self.assertIsNone(times['nx-d'], times)

    def test_snooze_topic_starts_at_until_and_back_goes_to_the_choose_step_with_the_set_marked(self):
        s = self.s
        self.select(self.topic('st-one', 31, session=True))
        self.run_command('Snooze Topic')
        rs = self.wait_step('st-one › Snooze › until')
        self.assertTrue(s.has('palette-row-never', rs), 'the "until" step has no times')
        self.assertIn('⌫ to mark more Topics', self.text('palette-note', rs))
        s.act('action', 'palette-search', 'Back')
        rs = self.wait_step('Snooze Topics › choose')
        self.assertTrue(self.is_marked('st-one', rs), 'Back did not keep the set marked')
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

if __name__ == '__main__':
    unittest.main()

"""Commands start Actions on the current item and retain Back to search."""

import json
import unittest

from scripts.verify.sandbox import Sandbox, wait


class PaletteCurrentCommands(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.s = s = Sandbox(__name__.rsplit('.', 1)[-1])
        cls.addClassCleanup(s.teardown)
        cls.project = s.root/'projects/commands'
        cls.project.mkdir(parents=True)
        cls.topics = s.root/'state/muxify/topics'
        cls.topics.mkdir(parents=True, exist_ok=True)
        (s.root/'config/muxify/config.yaml').write_text('sessions:\n  paths:\n    - path: ' + str(cls.project) + '\n')
        cls.base = s.tmux('new-session', '-d', '-P', '-F', '#{window_id}', '-s', 'base', '-c', str(cls.project), '/bin/zsh -f')
        s.tmux('set-option', '-g', 'detach-on-destroy', 'off')
        s.launch(['-sidebarVisible', 'YES', '-sessionsVisible', 'YES'])

    def setUp(self):
        if self.s.has('palette-search'):
            self.s.act('action', 'palette-search', 'Close')
        self.select(self.base)

    def select(self, window):
        for client in self.s.tmux('list-clients', '-F', '#{client_tty} #{client_control_mode}').splitlines():
            if client.endswith(' 0'):
                self.s.tmux('switch-client', '-c', client.split()[0], '-t', window)
        self.s.wait_shown(window)

    def search(self, title):
        wait(lambda: self.s.driver('press', 'Commands')['pressed'], 'Commands did not open')
        self.s.wait_rows(lambda rs: self.s.has('palette-search', rs), 'Commands field did not show')
        self.s.act('focus', 'palette-search')
        self.s.act('set', 'palette-search', title)
        self.s.wait_rows(lambda rs: self.s.row('palette-search', rs).get('accessibilityValue') == title,
                         'Commands did not keep the query')

    def run_command(self, title):
        self.search(title)
        key = 'palette-row-command-' + title
        self.s.wait_rows(lambda rs: self.s.has(key, rs), title + ' was missing from Commands')
        self.s.act('press', key)

    def breadcrumb(self, rs):
        row = self.s.row('palette-breadcrumb', rs)
        return row.get('accessibilityLabel', '') + row.get('accessibilityValue', '')

    def back(self, title):
        self.s.act('action', 'palette-search', 'Back')
        self.s.wait_rows(lambda rs: self.s.row('palette-search', rs).get('accessibilityValue') == title
                         and not self.s.has('palette-breadcrumb', rs), 'Back did not restore ' + title)
        self.s.act('action', 'palette-search', 'Close')

    def topic(self, name):
        path = self.topics/(name + '.json')
        path.write_text(json.dumps(dict(id=name, title=name, slug=name, home_project=str(self.project))))
        self.addCleanup(path.unlink, missing_ok=True)
        window = self.s.tmux('new-session', '-d', '-P', '-F', '#{window_id}', '-s', name,
                             '-c', str(self.project), '/bin/zsh -f')
        self.addCleanup(self.s.tmux_ok, 'kill-session', '-t', name)
        self.s.tmux('set-option', '-t', name, '@muxify_topic', name)
        self.s.wait_rows(lambda rs: self.s.has('topic-' + name, rs), 'Topic did not appear')
        self.select(window)
        self.addCleanup(self.select, self.base)
        return path

    def test_move_scopes_keep_back_and_cancel_without_tmux_changes(self):
        before = self.s.tmux('list-panes', '-a', '-F', '#{session_id} #{window_id} #{pane_id}')
        for scope in ['Pane', 'Window', 'Session']:
            title = 'Move ' + scope
            self.run_command(title)
            self.s.wait_rows(lambda rs: self.breadcrumb(rs).startswith(scope + ' '), 'Wrong scope for ' + title)
            self.back(title)
        self.assertEqual(self.s.tmux('list-panes', '-a', '-F', '#{session_id} #{window_id} #{pane_id}'), before)
        self.assertEqual(list(self.topics.glob('*.json')), [])

    def test_topic_steps_keep_back_and_cancel_without_writes(self):
        path = self.topic('current-commands')
        before = path.read_text()
        for title, step in [('Add a Project', 'Add a Project'), ('Snooze Topic', 'Snooze'),
                            ('Settle Topic', 'Settle'), ('Zen', 'Zen'), ('Forget Topic', 'Forget'), ('Rename Topic', 'Rename')]:
            self.run_command(title)
            self.s.wait_rows(lambda rs: step in self.breadcrumb(rs), title + ' did not open its step')
            if title == 'Rename Topic':
                # Rename starts with the title in the field, and Back works only in an empty field.
                self.s.act('set', 'palette-search', '')
            if title == 'Snooze Topic':
                self.s.act('action', 'palette-search', 'Back')
                self.s.wait_rows(lambda rs: 'Snooze Topics › choose' in self.breadcrumb(rs), 'Back did not go to the choose step')
            self.back(title)
        after = json.loads(path.read_text())
        original = json.loads(before)
        for key in ['title', 'snoozed_until', 'settled_at']:
            self.assertEqual(after.get(key), original.get(key), key + ' changed on Cancel')
        self.assertFalse((self.s.root/'state/muxify/zen.json').exists())

    def remembered(self, path):
        """Waits until the app records the Topic's live Session, so that a removal has something to forget."""
        wait(lambda: json.loads(path.read_text()).get('sessions'), 'the Topic did not remember its Session')

    def assert_empty_topic(self, name, path, sessions):
        self.assertEqual(json.loads(path.read_text()).get('sessions'), [], 'the Topic still remembers the Session')
        card = self.s.wait_rows(lambda rs: 'Empty' in self.s.row('topic-' + name, rs).get('accessibilityValue', ''),
                                'the Topic card does not show Empty')
        self.assertNotIn('Dormant', self.s.row('topic-' + name, card).get('accessibilityValue', ''))
        self.s.act('press', 'topic-' + name)
        self.s.wait_rows(lambda rs: self.s.has('empty-topic-add-project', rs), 'going to the Topic did not offer Add a Project')
        self.assertEqual(self.s.tmux('list-sessions', '-F', '#{session_name}').split(), sessions, 'going to the Topic made a Session')

    def test_remove_session_from_topic_leaves_the_topic_empty_and_the_session_live(self):
        path = self.topic('remove-empty')
        self.remembered(path)
        self.run_command('Remove Session from Topic')
        self.s.wait_rows(lambda rs: not self.s.has('palette-search', rs), 'Remove Session from Topic did not close Commands')
        wait(lambda: self.s.tmux('show-options', '-qv', '-t', 'remove-empty', '@muxify_topic') == '',
             'the Session is still in the Topic')
        self.assert_empty_topic('remove-empty', path, self.s.tmux('list-sessions', '-F', '#{session_name}').split())

    def test_command_return_on_remove_session_from_topic_kills_the_session_after_a_confirm_step(self):
        path = self.topic('remove-kill')
        self.remembered(path)
        self.search('Remove Session from Topic')
        self.s.wait_rows(lambda rs: 'Remove and Kill' in (self.s.row('palette-note', rs).get('accessibilityLabel', '')
                                                         + self.s.row('palette-note', rs).get('accessibilityValue', '')),
                         'the note does not show the ⌘↩ variant')
        self.s.act('action', 'palette-search', 'Confirm')
        self.s.wait_rows(lambda rs: 'Remove from Topic and Kill' in self.breadcrumb(rs) and self.s.has('palette-row-kill-session', rs),
                         '⌘↩ did not open the Kill confirm step')
        self.assertEqual(self.s.tmux_ok('has-session', '-t', '=remove-kill').returncode, 0, 'the confirm step killed the Session')
        self.s.act('action', 'palette-search', 'Confirm')
        wait(lambda: self.s.tmux_ok('has-session', '-t', '=remove-kill').returncode != 0, 'Remove and Kill did not kill the Session')
        self.assert_empty_topic('remove-kill', path, self.s.tmux('list-sessions', '-F', '#{session_name}').split())

    def test_commands_omit_unavailable_topic_and_tab_actions(self):
        for title in ['Add a Project', 'Snooze Topic', 'Settle Topic', 'Zen', 'Move Pane with Active Tab',
                      'Remove Session from Topic', 'Forget Topic', 'Rename Topic']:
            self.search(title)
            self.assertFalse(self.s.has('palette-row-command-' + title), title + ' had no target')
            self.s.act('action', 'palette-search', 'Close')

    def test_end_zen_is_available_in_no_topic_and_closes_commands(self):
        self.topic('zen-current-command')
        self.run_command('Zen')
        self.s.wait_rows(lambda rs: self.s.has('palette-row-never', rs), 'Zen presets did not show')
        self.s.act('press', 'palette-row-never')
        self.s.wait_rows(lambda rs: not self.s.has('palette-search', rs), 'Zen did not close')
        self.select(self.base)
        self.run_command('End Zen')
        self.s.wait_rows(lambda rs: not self.s.has('palette-search', rs), 'End Zen did not close Commands')
        self.search('End Zen')
        self.assertFalse(self.s.has('palette-row-command-End Zen'), 'Zen remained active')
        self.s.act('action', 'palette-search', 'Close')

    def test_layout_commands_show_their_shortcut_and_change_the_window(self):
        self.search('Maximize Terminal')
        key = 'palette-row-command-Maximize Terminal'
        rs = self.s.wait_rows(lambda rs: self.s.has(key, rs), 'Maximize Terminal was missing from Commands')
        row = self.s.row(key, rs)
        self.assertIn('⌥⌘J', row.get('accessibilityLabel', '') + row.get('accessibilityValue', ''),
                      'Maximize Terminal does not show its shortcut: %s' % row)
        self.s.act('action', 'palette-search', 'Close')
        self.run_command('Show Browser')
        self.s.wait_rows(lambda rs: not self.s.has('palette-search', rs), 'Show Browser did not close Commands')
        wait(lambda: self.s.tmux('show-options', '-wqv', '-t', self.base, '@muxify_browser') == 'on',
             'Show Browser did not turn the Browser toggle on')
        self.run_command('Hide Browser')
        wait(lambda: self.s.tmux('show-options', '-wqv', '-t', self.base, '@muxify_browser') == '',
             'Hide Browser did not turn the Browser toggle off')

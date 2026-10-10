"""The header's panel toggles and Focus: what a Window shows of its Sidebar, Terminal and Browser.

Run from the repo root after `make build`:
    python3 -m unittest -v scripts.verify.suites.panels
"""

import re
import time
import unittest

from scripts.verify.sandbox import Sandbox, wait

SHELL = '/bin/zsh -f'
PAGE = 'data:text/html,panels'
PANELS = {'sidebar-panel': 'sidebar', 'terminal-panel': 'terminal', 'browser-panel': 'browser'}
# The app reads tmux once per second.
SETTLE = 2.0


class Panels(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.s = s = Sandbox(__name__.rsplit('.', 1)[-1])
        cls.addClassCleanup(s.teardown)
        cls.session = s.tmux('new-session', '-d', '-P', '-F', '#{session_id}', '-s', 'panels', '-x', '200', '-y', '50', SHELL)
        s.launch(['-sidebarVisible', 'YES', '-sessionsVisible', 'YES'])
        wait(lambda: '0' in s.tmux('list-clients', '-F', '#{client_control_mode}').split(), 'the app attached no tmux client')

    def setUp(self):
        self.window = self.new_window(self.id().rsplit('.', 1)[-1][:24])

    def new_window(self, name, tabs=True):
        """A Window that shows its Terminal and, with tabs, its Browser, selected with the Sidebar shown."""
        # One tmux call, so the app never reads the Window without its Browser options.
        options = [arg for option, value in [('@muxify_tabs', PAGE), ('@muxify_active_tab', '0'), ('@muxify_browser', 'on')]
                   for arg in (';', 'set-option', '-w', '-t', 'panels:' + name, option, value)] if tabs else []
        self.s.tmux('new-window', '-d', '-t', self.session + ':', '-n', name, SHELL, *options)
        window = self.s.tmux('display-message', '-p', '-t', 'panels:' + name, '#{window_id}')
        self.select_window(window)
        if self.s.row('toggle-sidebar').get('accessibilityValue') == 'off':
            self.s.act('press', 'toggle-sidebar')
        self.wait_panels({'sidebar', 'terminal', 'browser'} if tabs else {'sidebar', 'terminal'},
                         'the new Window %s does not show its panels' % window)
        return window

    def select_window(self, window):
        """Moves the app's tmux client to the Window, as tmux navigation does."""
        for tty in self.s.tmux('list-clients', '-F', '#{client_tty} #{client_control_mode}').split('\n'):
            if tty.endswith(' 0'):
                self.s.tmux('switch-client', '-c', tty.split()[0], '-t', window)
        self.s.wait_shown(window)

    def panels(self, rs=None):
        return {name for key, name in PANELS.items() if self.s.has(key, rs)}

    def wait_panels(self, expected, message):
        return self.s.wait_rows(lambda rs: self.panels(rs) == expected,
                                '%s: shows %s, not %s' % (message, sorted(self.panels()), sorted(expected)))

    def option(self, name):
        return self.s.tmux('show-options', '-wqv', '-t', self.window, name)

    def wait_options(self, expected, message):
        """The app writes its state onto the tmux Window a moment after the change."""
        wait(lambda: all(self.option(name) == value for name, value in expected.items()),
             '%s: %s' % (message, {name: self.option(name) for name in expected}))

    def client_width(self):
        widths = self.s.tmux('list-clients', '-F', '#{client_control_mode} #{client_width}').split('\n')
        return [line.split()[1] for line in widths if line.startswith('0 ')]

    def test_terminal_toggle_hides_the_terminal_and_the_browser_fills_its_room(self):
        self.s.act('press', 'toggle-terminal')
        rs = self.wait_panels({'sidebar', 'browser'}, 'the Terminal toggle did not hide the Terminal')
        _, sidebar_right = horizontal(self.s.row('sidebar-panel', rs))
        browser_left, _ = horizontal(self.s.row('browser-panel', rs))
        self.assertLess(abs(browser_left - sidebar_right), 3,
                        'the Browser starts at %.0f, not at the Sidebar edge %.0f' % (browser_left, sidebar_right))
        self.wait_options({'@muxify_browser': 'only'}, 'the tmux Window does not say the Browser is alone')
        self.s.act('press', 'toggle-terminal')
        self.wait_panels({'sidebar', 'terminal', 'browser'}, 'the Terminal toggle did not show the Terminal again')

    def test_browser_toggle_does_nothing_while_the_browser_is_the_only_side(self):
        self.s.act('press', 'toggle-terminal')
        self.wait_panels({'sidebar', 'browser'}, 'the Terminal toggle did not hide the Terminal')
        self.s.driver('press', 'toggle-browser')
        self.s.driver('press', 'Hide Browser')
        time.sleep(SETTLE)
        self.assertEqual(self.panels(), {'sidebar', 'browser'}, 'the Browser toggle hid the only side shown')
        self.s.act('press', 'toggle-terminal')

    def test_focus_hides_the_sidebar_and_the_other_side_and_a_second_press_restores_both(self):
        self.s.act('press', 'Focus Browser')
        self.wait_panels({'browser'}, 'Focus Browser did not show the Browser alone')
        self.wait_options({'@muxify_focus': 'browser', '@muxify_browser': 'on'},
                          'the tmux Window does not keep the toggles with Focus on the Browser')
        self.s.act('press', 'toggle-focus')
        self.wait_panels({'sidebar', 'terminal', 'browser'}, 'ending Focus did not show what the toggles say')
        self.wait_options({'@muxify_focus': ''}, 'Focus stayed on the tmux Window')

    def test_focus_on_a_hidden_browser_shows_it_alone_with_a_blank_tab_until_focus_ends(self):
        self.window = self.new_window('hidden-browser', tabs=False)
        self.s.act('press', 'Focus Browser')
        self.wait_panels({'browser'}, 'Focus Browser did not show the hidden Browser alone')
        self.s.act('press', 'Focus Browser')
        self.wait_panels({'sidebar', 'terminal'}, 'ending Focus did not hide the Browser again')
        self.wait_options({'@muxify_tabs': ''}, 'the blank Tab stayed after Focus ended')

    def test_a_toggle_during_focus_keeps_what_is_on_screen_then_applies(self):
        self.s.act('press', 'Focus Terminal')
        self.wait_panels({'terminal'}, 'Focus Terminal did not show the Terminal alone')
        self.s.act('press', 'toggle-sidebar')
        self.wait_panels({'sidebar', 'terminal'}, 'the Sidebar toggle during Focus did not keep the Terminal alone')
        self.wait_options({'@muxify_browser': '', '@muxify_focus': ''},
                          'the toggles on the tmux Window are not the Terminal alone without Focus')

    def test_focus_belongs_to_its_window(self):
        other = self.new_window('focus-other')
        self.select_window(self.window)
        self.s.act('press', 'Focus Terminal')
        self.wait_panels({'terminal'}, 'Focus Terminal did not hide the Sidebar')
        self.select_window(other)
        self.wait_panels({'sidebar', 'terminal', 'browser'}, 'a Window without Focus does not show the Sidebar')
        self.select_window(self.window)
        self.wait_panels({'terminal'}, 'the Window in Focus did not hide the Sidebar again')
        self.s.act('press', 'toggle-focus')
        self.wait_panels({'sidebar', 'terminal', 'browser'}, 'ending Focus did not show what the toggles say')

    def test_the_tmux_client_keeps_its_width_while_the_terminal_is_hidden(self):
        time.sleep(SETTLE)
        before = self.client_width()
        self.s.act('press', 'toggle-terminal')
        self.wait_panels({'sidebar', 'browser'}, 'the Terminal toggle did not hide the Terminal')
        time.sleep(SETTLE)
        self.assertEqual(self.client_width(), before, 'tmux resized the client while the Terminal is hidden')
        self.s.act('press', 'toggle-terminal')
        self.wait_panels({'sidebar', 'terminal', 'browser'}, 'the Terminal toggle did not show the Terminal again')
        time.sleep(SETTLE)
        self.assertEqual(self.client_width(), before, 'tmux resized the client when the Terminal came back')


def horizontal(row):
    """(left, right) of a dump row's accessibilityFrame, in screen points."""
    x, _, width, _ = map(float, re.findall(r'-?[\d.]+', row['accessibilityFrame']))
    return x, x + width


if __name__ == '__main__':
    unittest.main()

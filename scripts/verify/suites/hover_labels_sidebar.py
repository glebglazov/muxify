"""Hover labels on the Sidebar's Window rows: after the pointer rests on a row, a label opens over it with the full
title, when the row cuts it off, and the Window's place under it. The next row's label opens at once.

The driver's `hover` gives the app's hover tracking a pointer position without moving the real pointer.

Run from the repo root after `make build`:
    python3 -m unittest -v scripts.verify.suites.hover_labels_sidebar
"""

import time
import unittest

from scripts.verify.sandbox import Sandbox, wait

SHELL = '/bin/zsh -f'
LONG = 'a-window-name-far-too-long-for-any-sidebar-row-to-show-whole'


class HoverLabelsSidebar(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.s = s = Sandbox(__name__.rsplit('.', 1)[-1])
        cls.addClassCleanup(s.teardown)
        project = s.root/'projects/alpha'
        project.mkdir(parents=True)
        (s.root/'config/muxify/config.yaml').write_text('sessions:\n  paths:\n    - path: ' + str(project) + '\n')
        s.tmux('new-session', '-d', '-s', 'base', '-n', LONG, '-c', str(project), SHELL)
        s.tmux('new-window', '-d', '-t', 'base:', '-n', 'short', '-c', str(project), SHELL)
        cls.long, cls.short = s.tmux('list-windows', '-t', 'base:', '-F', '#{window_id}').split()
        cls.places = {window: s.tmux('display-message', '-p', '-t', window, '#{session_name}:#{window_index}')
                      for window in (cls.long, cls.short)}
        s.launch(['-sidebarVisible', 'YES', '-sessionsVisible', 'YES', '-agentsVisible', 'YES', '-sidebarWorkView', 'Topics'])
        s.wait_rows(lambda rs: s.has('topic-window-' + cls.long, rs) and s.has('topic-window-' + cls.short, rs),
                    'the Window rows do not show')

    def setUp(self):
        # The Agents header has no label; resting there past the cool-down makes the next label wait its delay.
        self.s.act('hover', 'agents-header')
        time.sleep(0.5)

    def label(self, rs):
        """The texts of the open hover label, nil when none is open."""
        ids = self.s.ids(rs)
        if 'hover-label' not in ids:
            return None
        start = ids.index('hover-label') + 1
        texts = []
        for row in rs[start:]:
            if row.get('accessibilityRole') == 'AXWindow':
                break
            text = row.get('accessibilityValue') or row.get('accessibilityLabel')
            if row.get('accessibilityRole') == 'AXStaticText' and text:
                texts.append(text)
        return texts

    def test_a_cut_off_title_opens_whole_with_the_windows_place_after_a_rest(self):
        self.s.act('hover', 'topic-window-' + self.long)
        time.sleep(0.2)
        self.assertIsNone(self.label(self.s.rows()), 'the label opened before the pointer rested')
        rs = self.s.wait_rows(lambda rs: self.label(rs), 'no hover label', seconds=5)
        texts = self.label(rs)
        self.assertEqual(texts[0], LONG, 'the label does not show the full title: %s' % texts)
        self.assertTrue(texts[1].startswith(self.places[self.long] + ' — '), 'the label does not show the place: %s' % texts)

    def test_a_title_that_fits_shows_only_the_windows_place(self):
        self.s.act('hover', 'topic-window-' + self.short)
        texts = self.label(self.s.wait_rows(lambda rs: self.label(rs), 'no hover label', seconds=5))
        self.assertEqual(len(texts), 1, 'the label repeats a title that fits: %s' % texts)
        self.assertTrue(texts[0].startswith(self.places[self.short] + ' — '), texts)

    def test_the_next_row_opens_its_label_at_once(self):
        self.s.act('hover', 'topic-window-' + self.long)
        self.s.wait_rows(lambda rs: self.label(rs), 'no hover label', seconds=5)
        start = time.monotonic()
        self.s.act('hover', 'topic-window-' + self.short)
        rs = self.s.wait_rows(lambda rs: (self.label(rs) or [''])[0].startswith(self.places[self.short]),
                              'the label did not move to the next row', seconds=5)
        self.assertLess(time.monotonic() - start, 0.35, 'the next row waited for its label: %s' % self.label(rs))


if __name__ == '__main__':
    unittest.main()

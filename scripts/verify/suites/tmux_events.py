"""The tmux control client that tells the app about tmux changes.

Run from the repo root after `make build`:
    python3 -m unittest -v scripts.verify.suites.tmux_events
"""

import os
import signal
import threading
import time
import unittest

from scripts.verify.sandbox import Sandbox, alive, wait

# tmux 3.7c keeps a control client whose input closes while the server writes
# notifications to it, and then its server cannot exit. A flood of Window
# renames across the kill makes that race likely.
RENAMERS = 16


class TmuxEvents(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.s = s = Sandbox(__name__.rsplit('.', 1)[-1])
        cls.addClassCleanup(s.teardown)
        # No tmux server at launch: the app starts one with its own Session.
        s.launch()

    def control_clients(self):
        listing = self.s.tmux_ok('list-clients', '-F', '#{client_pid} #{client_control_mode}').stdout.split('\n')
        return [int(line.split()[0]) for line in listing if line.endswith(' 1')]

    def rename_until(self, stop):
        n = 0
        while not stop.is_set():
            n += 1
            self.s.tmux_ok('rename-window', '-t', 'main', 'w%d' % n)

    def test_control_client_exits_when_app_is_killed(self):
        client = wait(lambda: (self.control_clients() or [None])[0], 'app did not start a tmux control client')
        server = int(self.s.tmux('display-message', '-p', '#{pid}'))
        stop = threading.Event()
        renamers = [threading.Thread(target=self.rename_until, args=(stop,)) for _ in range(RENAMERS)]
        for renamer in renamers:
            renamer.start()
        time.sleep(.3)

        os.kill(self.s.pid, signal.SIGKILL)
        wait(lambda: not alive(self.s.pid), 'app %d still runs after SIGKILL' % self.s.pid, seconds=5)
        time.sleep(1)
        stop.set()
        for renamer in renamers:
            renamer.join()

        wait(lambda: not alive(client), 'control client %d still runs after the app was killed' % client, seconds=5)
        self.s.tmux_ok('kill-server')
        wait(lambda: not alive(server), 'tmux server %d still runs after kill-server' % server, seconds=5)


if __name__ == '__main__':
    unittest.main()

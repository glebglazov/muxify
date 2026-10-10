"""Runs verify suites side by side, one process per suite, and reports each when it ends.

Each suite has its own Sandbox, so suites do not share a tmux server or an app. The full
unittest output of a suite goes to BASE/<suite>/last-run.log; a suite that fails prints it here too.

    python3 scripts/verify/run.py [suite ...]

Without a suite it runs every suite in suites/. The exit status is 1 when a suite fails.
"""

import pathlib
import subprocess
import sys
import time

REPO = pathlib.Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))

from scripts.verify.sandbox import BASE  # noqa: E402

SUITES = REPO/'scripts/verify/suites'


def main(names):
    names = names or sorted(path.stem for path in SUITES.glob('*.py'))
    unknown = [name for name in names if not (SUITES/(name + '.py')).is_file()]
    if unknown:
        sys.exit('no suite %s in %s' % (', '.join(unknown), SUITES))

    start = time.monotonic()
    running = {}
    for name in names:
        log = BASE/name/'last-run.log'
        log.parent.mkdir(parents=True, exist_ok=True)
        with open(log, 'w') as handle:
            process = subprocess.Popen([sys.executable, '-m', 'unittest', '-v', 'scripts.verify.suites.' + name],
                                       cwd=REPO, stdout=handle, stderr=subprocess.STDOUT)
        running[process] = (name, log)

    failed = []
    while running:
        for process in [process for process in running if process.poll() is not None]:
            name, log = running.pop(process)
            print('%-6s %-25s %4.0f s  %s' % ('ok' if process.returncode == 0 else 'FAILED', name,
                                              time.monotonic() - start, log), flush=True)
            if process.returncode != 0:
                failed.append(name)
                print(log.read_text(errors='replace'), flush=True)
        time.sleep(.2)

    print('%d suites in %.0f s, %s' % (len(names), time.monotonic() - start,
                                       'failed: ' + ', '.join(failed) if failed else 'all passed'))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

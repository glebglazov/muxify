"""Runs verify suites side by side, one process per suite, and reports each when it ends.

Each suite has its own Sandbox, so suites do not share a tmux server or an app. The full
unittest output of a suite goes to LOGS/<suite>/last-run.log; a suite that fails prints it here too.

    python3 scripts/verify/run.py [suite ...]

Without a suite it runs every suite in suites/. At most JOBS suites run at the same time; set
MUXIFY_VERIFY_JOBS to change that. A suite that fails runs again alone after the others. It is
FLAKY when it passes then, and its first output stays in LOGS/<suite>/first-run.log. The exit
status is 1 when a suite fails again.
"""

import os
import pathlib
import subprocess
import sys
import time

REPO = pathlib.Path(__file__).resolve().parents[2]
SUITES = REPO/'scripts/verify/suites'
# Inside the checkout, so a run in another checkout or worktree cannot truncate or move these logs.
LOGS = REPO/'build/verify'
# Each suite runs its own app, and each app starts tmux every second. With all 30 suites at once on a
# 12-core Mac, a process start took 30 times longer and checks failed by chance; 10 at once was faster.
JOBS = 10


def run(names, jobs, start):
    """Runs the suites, `jobs` at a time; the names of those that failed."""
    waiting = list(names)
    running = {}
    failed = []
    while waiting or running:
        while waiting and len(running) < jobs:
            name = waiting.pop(0)
            log = LOGS/name/'last-run.log'
            log.parent.mkdir(parents=True, exist_ok=True)
            with open(log, 'w') as handle:
                process = subprocess.Popen([sys.executable, '-m', 'unittest', '-v', 'scripts.verify.suites.' + name],
                                           cwd=REPO, stdout=handle, stderr=subprocess.STDOUT)
            running[process] = (name, log)
        for process in [process for process in running if process.poll() is not None]:
            name, log = running.pop(process)
            print('%-6s %-25s %4.0f s  %s' % ('ok' if process.returncode == 0 else 'FAILED', name,
                                              time.monotonic() - start, log), flush=True)
            if process.returncode != 0:
                failed.append(name)
                print(log.read_text(errors='replace'), flush=True)
        time.sleep(.2)
    return failed


def main(names):
    names = names or sorted(path.stem for path in SUITES.glob('*.py'))
    unknown = [name for name in names if not (SUITES/(name + '.py')).is_file()]
    if unknown:
        sys.exit('no suite %s in %s' % (', '.join(unknown), SUITES))

    start = time.monotonic()
    failed = run(names, int(os.environ.get('MUXIFY_VERIFY_JOBS') or JOBS), start)
    if failed:
        print('running again alone: ' + ', '.join(failed), flush=True)
        for name in failed:
            (LOGS/name/'last-run.log').replace(LOGS/name/'first-run.log')
    still = run(failed, 1, start)
    flaky = [name for name in failed if name not in still]

    print('%d suites in %.0f s, %s' % (len(names), time.monotonic() - start, '; '.join(
        ['failed: ' + ', '.join(still)] * bool(still) + ['FLAKY: ' + ', '.join(flaky)] * bool(flaky)) or 'all passed'))
    return 1 if still else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))

import argparse
import ipaddress
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile


def main(kind):
    parser = argparse.ArgumentParser(prog=f"{kind}test", description=f"Run tcp-{kind}-test against an explicit IPv4 target")
    parser.add_argument("target", type=ipaddress.IPv4Address, help="IPv4 address of the lab server")
    parser.add_argument("--parallel", type=int, default=1, metavar="N", help="Run N copies concurrently (default: 1)")
    args = parser.parse_args(sys.argv[2:])
    if not 1 <= args.parallel <= 256:
        parser.error("parallel must be between 1 and 256")

    command = [f"/usr/local/bin/tcp-{kind}-test", str(args.target)]
    if args.parallel == 1:
        os.execv(command[0], command)

    logs = Path(tempfile.mkdtemp(prefix=f"tcp-{kind}-"))
    print(f"Starting {args.parallel} runs; logs: {logs}", flush=True)
    children = []

    def interrupted(signum, _frame):
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        for index in range(1, args.parallel + 1):
            with (logs / f"run_{index}.log").open("wb") as log:
                children.append(subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT))
        failed = 0
        for index, child in enumerate(children, 1):
            code = child.wait()
            print(f"Run {index} exited with status {code}", flush=True)
            failed += code != 0
        return int(bool(failed))
    finally:
        for child in children:
            if child.poll() is None:
                child.terminate()
        for child in children:
            child.wait()


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1]))
    except OSError as error:
        print(error, file=sys.stderr)
        sys.exit(1)

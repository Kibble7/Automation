#!/usr/bin/env python3
"""Small wrapper around ansible-playbook so automation can be driven from Python.

Examples:
    python python/run_playbook.py ping
    python python/run_playbook.py maintenance_message -e maintenance_date="Sunday 9pm"
    python python/run_playbook.py shutdown -e delay_minutes=15
"""
import argparse
import subprocess
import sys
from pathlib import Path

ANSIBLE_DIR = Path(__file__).resolve().parent.parent / "ansible"
PLAYBOOK_DIR = ANSIBLE_DIR / "playbooks"


def main() -> int:
    parser = argparse.ArgumentParser(description="Run an Ansible playbook from this repo")
    parser.add_argument("playbook", help="Playbook name without .yml (e.g. ping)")
    parser.add_argument("-e", "--extra-vars", action="append", default=[],
                        help="Extra variable key=value (repeatable)")
    parser.add_argument("--limit", help="Limit to a host or group (e.g. server01)")
    parser.add_argument("--no-become-prompt", action="store_true",
                        help="Skip the sudo password prompt (-K)")
    args = parser.parse_args()

    playbook = PLAYBOOK_DIR / f"{args.playbook}.yml"
    if not playbook.is_file():
        available = ", ".join(sorted(p.stem for p in PLAYBOOK_DIR.glob("*.yml")))
        print(f"Playbook not found: {playbook.name}. Available: {available}", file=sys.stderr)
        return 2

    cmd = ["ansible-playbook", str(playbook)]
    if not args.no_become_prompt:
        cmd.append("-K")
    if args.limit:
        cmd += ["--limit", args.limit]
    for var in args.extra_vars:
        cmd += ["-e", var]

    # Run from ansible/ so ansible.cfg and the inventory are picked up.
    return subprocess.run(cmd, cwd=ANSIBLE_DIR).returncode


if __name__ == "__main__":
    sys.exit(main())

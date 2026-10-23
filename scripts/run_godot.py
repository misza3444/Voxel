#!/usr/bin/env python3
"""Fail CI on engine/script errors even when Godot exits with status zero."""
import argparse
import re
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--expect')
parser.add_argument('--timeout', type=int, default=120)
parser.add_argument('command', nargs=argparse.REMAINDER)
args = parser.parse_args()
command = args.command[1:] if args.command[:1] == ['--'] else args.command
if not command:
    parser.error('provide a command after --')
try:
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, errors='replace', timeout=args.timeout)
except subprocess.TimeoutExpired as error:
    print(error.stdout.decode(errors='replace') if isinstance(error.stdout, bytes) else error.stdout or '')
    sys.exit('ERROR: Godot timed out')
print(result.stdout)
output = re.sub(r'\x1b\[[0-9;]*m', '', result.stdout)
failed = result.returncode != 0 or re.search(r'(?m)^\s*(?:SCRIPT ERROR:|ERROR:|Parse Error:)', output)
if args.expect and args.expect not in output:
    print('ERROR: missing success marker:', args.expect)
    failed = True
sys.exit(1 if failed else 0)

#!/usr/bin/env python3
"""Sanity-check the portable Windows artifact without running it."""
import os
import struct
import sys
from pathlib import Path

def main() -> int:
    if len(sys.argv) != 2:
        print('Usage: check_windows_exe.py path-to-VoxelForge.exe', file=sys.stderr)
        return 2
    exe = Path(sys.argv[1])
    if not exe.is_file() or exe.stat().st_size < 1024 * 1024:
        print('ERROR: Export missing or too small', file=sys.stderr)
        return 1
    with exe.open('rb') as f:
        if f.read(2) != b'MZ':
            print('ERROR: Not a Windows executable (MZ)', file=sys.stderr)
            return 1
        f.seek(0x3c)
        pe_offset = struct.unpack('<I', f.read(4))[0]
        f.seek(pe_offset)
        if f.read(4) != b'PE\0\0':
            print('ERROR: Missing PE header', file=sys.stderr)
            return 1
        arch = struct.unpack('<H', f.read(2))[0]
        if arch != 0x8664:
            print(f'ERROR: Unsupported architecture: {arch:04X}', file=sys.stderr)
            return 1
    print(f'PASS: Windows x86_64 EXE: {exe} ({exe.stat().st_size:,} bytes)')
    return 0

if __name__ == '__main__':
    sys.exit(main())

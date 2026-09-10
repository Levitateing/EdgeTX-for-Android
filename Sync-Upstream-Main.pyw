#!/usr/bin/env python3
"""Double-click launcher: open a console and sync EdgeTX main to origin/main."""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parent
SCRIPT = APP_ROOT / "scripts" / "sync_upstream_main.py"
CREATE_NEW_CONSOLE = getattr(subprocess, "CREATE_NEW_CONSOLE", 0x00000010)


def _python_console_exe() -> str:
    exe = sys.executable
    if exe.lower().endswith("pythonw.exe"):
        return exe[:-len("pythonw.exe")] + "python.exe"
    return exe


def _show_error(message: str) -> None:
    try:
        import ctypes

        ctypes.windll.user32.MessageBoxW(0, message[:2000], "Sync Upstream Main", 0x10)
    except Exception:
        pass


def main() -> int:
    if not SCRIPT.is_file():
        _show_error(f"Missing script:\n{SCRIPT}")
        return 1

    python = _python_console_exe()
    if not Path(python).is_file():
        _show_error(f"Python console executable not found:\n{python}")
        return 1

    subprocess.Popen(
        [python, str(SCRIPT)],
        cwd=APP_ROOT,
        creationflags=CREATE_NEW_CONSOLE,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

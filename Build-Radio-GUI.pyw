#!/usr/bin/env python3
"""Launch EdgeTX radio firmware build GUI without a console window."""
import os
import subprocess
import sys

APP_ROOT = os.path.dirname(os.path.abspath(__file__))
SCRIPTS = os.path.join(APP_ROOT, "scripts")
CREATE_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0x08000000)


def _show_error(message: str) -> None:
    try:
        import ctypes

        ctypes.windll.user32.MessageBoxW(0, message[:2000], "EdgeTX Radio Build GUI", 0x10)
    except Exception:
        pass


def run_ps(script_name: str) -> int:
    system_root = os.environ.get("SystemRoot", r"C:\Windows")
    ps_exe = os.path.join(system_root, "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
    script = os.path.join(SCRIPTS, script_name)
    cmd = [
        ps_exe,
        "-NoProfile",
        "-STA",
        "-ExecutionPolicy",
        "Bypass",
        "-WindowStyle",
        "Hidden",
        "-File",
        script,
    ]
    result = subprocess.run(
        cmd,
        cwd=APP_ROOT,
        creationflags=CREATE_NO_WINDOW,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        if not detail:
            detail = f"{script_name} exited with code {result.returncode}"
        _show_error(detail)
    return result.returncode


def main() -> int:
    os.chdir(APP_ROOT)
    rc = run_ps("ensure-radio-gui-utf8.ps1")
    if rc != 0:
        return rc
    return run_ps("Build-Radio-Gui.ps1")


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Reset official EdgeTX main tree to origin/main (keeps radio/src/targets/android/)."""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parent.parent
REPO_ROOT = APP_ROOT.parent.parent.parent.parent
OVERLAY_BACKUP = APP_ROOT / ".overlay-backup"
ANDROID_UNTRACKED = "radio/src/targets/android/"


@dataclass(frozen=True)
class Check:
    name: str
    path: Path
    pattern: str
    must_match: bool


CHECKS = (
    Check(
        "lv_img_buf.h uses 11-bit w/h",
        REPO_ROOT / "radio/src/thirdparty/lvgl/src/draw/lv_img_buf.h",
        r"w\s*:\s*11",
        True,
    ),
    Check(
        "radio/src/CMakeLists.txt has no ANDROID",
        REPO_ROOT / "radio/src/CMakeLists.txt",
        "ANDROID",
        False,
    ),
    Check(
        "yaml_datastructs.cpp has no PCBANDROID",
        REPO_ROOT / "radio/src/storage/yaml/yaml_datastructs.cpp",
        "PCBANDROID",
        False,
    ),
    Check(
        "convert-gfx.py has no targets/android",
        REPO_ROOT / "tools/convert-gfx.py",
        "targets/android",
        False,
    ),
    Check(
        "root CMakeLists.txt has no NOT ANDROID guard",
        REPO_ROOT / "CMakeLists.txt",
        "NOT ANDROID",
        False,
    ),
)


def find_git() -> str:
    env_git = os.environ.get("EDGE_TX_GIT")
    if env_git and Path(env_git).is_file():
        return env_git
    for candidate in (
        r"C:\Program Files\Git\bin\git.exe",
        r"C:\Program Files (x86)\Git\bin\git.exe",
    ):
        if Path(candidate).is_file():
            return candidate
    found = shutil.which("git")
    if found:
        return found
    raise RuntimeError("git.exe not found. Install Git or set EDGE_TX_GIT.")


def run_git(git: str, args: list[str], *, what_if: bool = False) -> str:
    display = "git " + " ".join(args)
    if what_if:
        print(f"[WhatIf] {display}")
        return ""
    result = subprocess.run(
        [git, *args],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "").strip()
        raise RuntimeError(f"git failed ({result.returncode}): {display}\n{detail}")
    return (result.stdout or "").strip()


def overlay_backup_active() -> bool:
    manifest = OVERLAY_BACKUP / "manifest.json"
    if not manifest.is_file():
        return False
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return False
    return bool(data.get("active"))


def restore_overlay(*, what_if: bool = False) -> None:
    restore_ps1 = APP_ROOT / "scripts" / "restore-overlay.ps1"
    if not restore_ps1.is_file():
        raise RuntimeError(f"Missing overlay restore script: {restore_ps1}")

    if what_if:
        print("[WhatIf] restore-overlay.ps1")
        return

    ps_exe = Path(os.environ.get("SystemRoot", r"C:\Windows")) / "System32/WindowsPowerShell/v1.0/powershell.exe"
    cmd = [
        str(ps_exe),
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        str(restore_ps1),
    ]
    result = subprocess.run(cmd, cwd=APP_ROOT, check=False)
    if result.returncode != 0:
        raise RuntimeError(f"restore-overlay.ps1 failed ({result.returncode})")


def file_matches(path: Path, pattern: str) -> bool:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False
    return re.search(pattern, text) is not None


def verify(git: str) -> int:
    print()
    print("=== Verification ===")
    failed = 0

    for check in CHECKS:
        if not check.path.is_file():
            print(f"FAIL {check.name} (missing file)")
            failed += 1
            continue
        hit = file_matches(check.path, check.pattern)
        ok = hit if check.must_match else not hit
        print(f"{'OK  ' if ok else 'FAIL'} {check.name}")
        if not ok:
            failed += 1

    if overlay_backup_active():
        print("FAIL overlay backup still active (.overlay-backup/)")
        failed += 1
    else:
        print("OK   no overlay backup residue")

    status_lines = run_git(git, ["status", "--short"]).splitlines()
    dirty = []
    for line in status_lines:
        normalized = line.replace("\\", "/")
        if normalized.startswith("?? ") and ANDROID_UNTRACKED in normalized:
            continue
        dirty.append(line)

    if not dirty:
        print("OK   git status clean (only targets/android/ may be untracked)")
    else:
        print("FAIL git status not clean:")
        for line in dirty[:20]:
            print(f"     {line}")
        if len(dirty) > 20:
            print(f"     ... and {len(dirty) - 20} more")
        failed += 1

    head = run_git(git, ["log", "-1", "--oneline"])
    print()
    print(f"HEAD: {head}")
    return failed


def sync(*, skip_fetch: bool = False, what_if: bool = False) -> None:
    git = find_git()

    print("=== Sync upstream main ===")
    print(f"Repo: {REPO_ROOT}")
    print()

    if overlay_backup_active():
        print("Active overlay backup detected; restoring first...")
        restore_overlay(what_if=what_if)

    branch = "main" if what_if else run_git(git, ["branch", "--show-current"])
    if branch != "main":
        print(f"WARNING: current branch is '{branch}' (expected main). Proceeding anyway.")

    if not skip_fetch:
        print("Fetching origin/main...")
        run_git(git, ["fetch", "origin", "main"], what_if=what_if)

    print("Resetting tracked files to origin/main...")
    run_git(git, ["reset", "--hard", "origin/main"], what_if=what_if)

    print("Refreshing submodules...")
    run_git(
        git,
        ["submodule", "update", "--init", "--recursive", "--force"],
        what_if=what_if,
    )

    if what_if:
        print()
        print("[WhatIf] sync complete")
        return

    failed = verify(git)
    if failed:
        raise RuntimeError(f"Upstream sync verification failed ({failed} check(s)).")

    print()
    print(
        "Upstream main is clean. Android platform code under "
        "radio/src/targets/android/ is preserved."
    )


def pause() -> None:
    if not sys.stdin or not sys.stdin.isatty():
        return
    try:
        input("\nPress Enter to close...")
    except EOFError:
        pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Reset EdgeTX main tree to origin/main (keeps targets/android/)."
    )
    parser.add_argument(
        "--skip-fetch",
        action="store_true",
        help="Only reset to local origin/main without fetching remote.",
    )
    parser.add_argument(
        "--what-if",
        action="store_true",
        help="Print planned git commands without changing files.",
    )
    parser.add_argument(
        "--no-pause",
        action="store_true",
        help="Do not wait for Enter at the end.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        sync(skip_fetch=args.skip_fetch, what_if=args.what_if)
    except Exception as exc:
        print()
        print(f"ERROR: {exc}")
        if not args.no_pause:
            pause()
        return 1
    if not args.no_pause:
        pause()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

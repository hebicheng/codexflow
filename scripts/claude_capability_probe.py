#!/usr/bin/env python3
"""
Probe local Claude Code CLI capabilities for CodexFlow integration planning.

Usage:
  python3 scripts/claude_capability_probe.py
  python3 scripts/claude_capability_probe.py --bin /custom/path/claude
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any


@dataclass
class CommandResult:
    ok: bool
    code: int
    stdout: str
    stderr: str
    duration_ms: int


def run_command(args: list[str], timeout_sec: int = 20) -> CommandResult:
    started = time.time()
    try:
        completed = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=timeout_sec,
            check=False,
        )
    except FileNotFoundError:
        return CommandResult(False, 127, "", "binary not found", int((time.time() - started) * 1000))
    except subprocess.TimeoutExpired:
        return CommandResult(False, 124, "", "timeout", int((time.time() - started) * 1000))

    return CommandResult(
        ok=completed.returncode == 0,
        code=completed.returncode,
        stdout=completed.stdout.strip(),
        stderr=completed.stderr.strip(),
        duration_ms=int((time.time() - started) * 1000),
    )


def try_parse_json_line(output: str) -> dict[str, Any] | None:
    if not output:
        return None
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    for line in reversed(lines):
        try:
            parsed = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict):
            return parsed
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bin", default="claude", help="Claude CLI binary path (default: claude)")
    args = parser.parse_args()

    binary = args.bin
    binary_path = shutil.which(binary) if "/" not in binary else binary

    report: dict[str, Any] = {
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
        "binary": binary,
        "binary_path": binary_path or "",
        "checks": {},
        "summary": {},
    }

    version_result = run_command([binary, "--version"])
    report["checks"]["version"] = {
        "ok": version_result.ok,
        "code": version_result.code,
        "stdout": version_result.stdout,
        "stderr": version_result.stderr,
        "duration_ms": version_result.duration_ms,
    }

    print_json_result = run_command([binary, "-p", "--output-format", "json", "say ok"])
    print_json_payload = try_parse_json_line(print_json_result.stdout)
    report["checks"]["print_json"] = {
        "ok": print_json_result.ok,
        "code": print_json_result.code,
        "stdout": print_json_result.stdout,
        "stderr": print_json_result.stderr,
        "duration_ms": print_json_result.duration_ms,
        "parsed": print_json_payload,
    }

    stream_json_result = run_command(
        [
            binary,
            "-p",
            "--verbose",
            "--output-format",
            "stream-json",
            "--include-partial-messages",
            "say ok",
        ]
    )
    stream_first_lines = stream_json_result.stdout.splitlines()[:10]
    report["checks"]["stream_json"] = {
        "ok": stream_json_result.ok,
        "code": stream_json_result.code,
        "stdout_first_lines": stream_first_lines,
        "stderr": stream_json_result.stderr,
        "duration_ms": stream_json_result.duration_ms,
    }

    logged_in = False
    login_reason = ""
    if isinstance(print_json_payload, dict):
        result_text = str(print_json_payload.get("result", ""))
        is_error = bool(print_json_payload.get("is_error", False))
        if "not logged in" in result_text.lower():
            logged_in = False
            login_reason = "not_logged_in"
        elif not is_error:
            logged_in = True
            login_reason = "ok"
        else:
            login_reason = "print_json_error"
    else:
        login_reason = "no_json_payload"

    report["summary"] = {
        "installed": version_result.ok,
        "logged_in": logged_in,
        "login_reason": login_reason,
        "supports_print_json": isinstance(print_json_payload, dict),
        "supports_stream_json": len(stream_first_lines) > 0,
    }

    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

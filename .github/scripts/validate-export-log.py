"""Distinguish a nonfatal Godot export shutdown diagnostic from real build errors.

Only a completed, successful export may ignore this exact Godot engine cleanup
warning. Other errors and nonzero Godot exit codes remain fatal in build-godot.sh.
"""

import re
import sys
from pathlib import Path

ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*m")
ERROR = re.compile(r"^\s*(?:SCRIPT ERROR|ERROR):")
LEAK_ERROR = "ERROR: 1 resources still in use at exit (run with --verbose for details)."
LEAK_WARNING = "WARNING: ObjectDB instances leaked at exit (run with --verbose for details)."


def only_shutdown_resource_leak(log: str) -> bool:
    lines = [ANSI_ESCAPE.sub("", line).strip() for line in log.splitlines()]
    packed = [i for i, line in enumerate(lines) if "[ DONE ]" in line and "savepack" in line]
    warnings = [i for i, line in enumerate(lines) if line == LEAK_WARNING]
    errors = [(i, line) for i, line in enumerate(lines) if ERROR.match(line)]
    if len(packed) != 1 or len(warnings) != 1 or len(errors) != 1:
        return False
    error_index, error_text = errors[0]
    return (
        error_text == LEAK_ERROR
        and packed[0] < warnings[0] < error_index
        and not any(line and not line.startswith("at:") for line in lines[error_index + 1 :])
    )


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: validate-export-log.py LOGFILE")
    try:
        log_text = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
    except OSError as error:
        raise SystemExit(str(error))
    raise SystemExit(0 if only_shutdown_resource_leak(log_text) else 1)

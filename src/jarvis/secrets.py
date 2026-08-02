"""Minimal secrets access.

Secrets live in the process environment or in `.env.local` at the project
root (gitignored). They are never logged, never stored in config files or the
voice manifest, and never echoed back in CLI output.
"""

from __future__ import annotations

import os
from pathlib import Path


def load_env_local(project_root: Path) -> None:
    """Load KEY=VALUE lines from .env.local into os.environ (no overwrite)."""
    env_file = project_root / ".env.local"
    if not env_file.is_file():
        return
    for raw_line in env_file.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key, value = key.strip(), value.strip().strip("'\"")
        if key and value and key not in os.environ:
            os.environ[key] = value


def get_secret(name: str) -> str | None:
    value = os.environ.get(name)
    return value if value else None

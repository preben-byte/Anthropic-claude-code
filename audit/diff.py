from __future__ import annotations

import argparse
import difflib
import json
import sys
from pathlib import Path


def _load(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8", errors="replace")
    if path.suffix == ".json":
        try:
            text = json.dumps(json.loads(text), indent=2, sort_keys=True, ensure_ascii=False)
        except json.JSONDecodeError:
            pass
    return text.splitlines(keepends=True)


def diff_files(baseline: Path, current: Path) -> int:
    a = _load(baseline)
    b = _load(current)
    delta = list(
        difflib.unified_diff(
            a, b, fromfile=str(baseline), tofile=str(current), n=3
        )
    )
    if not delta:
        print(f"OK: {current} matches {baseline}")
        return 0
    sys.stdout.writelines(delta)
    return 1


def main() -> None:
    p = argparse.ArgumentParser(description="Diff a config file against its baseline")
    p.add_argument("baseline", type=Path)
    p.add_argument("current", type=Path)
    args = p.parse_args()
    sys.exit(diff_files(args.baseline, args.current))


if __name__ == "__main__":
    main()

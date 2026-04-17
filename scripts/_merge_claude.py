#!/usr/bin/env python3
"""CLAUDE.md 마커 기반 병합 유틸.

사용:
    _merge_claude.py <target_path> <content_file> [--force]

동작 규칙:
  1. target 이 없으면 마커 블록으로 새 파일을 생성한다.
  2. 마커가 있으면 마커 사이 내용만 교체한다 (사용자 커스텀 구간 보존).
  3. 마커가 없고 target 이 이미 존재하면:
       - 기본: 기존 파일 하단에 마커 블록을 추가.
       - --force: 전체 덮어쓰기 (마커 블록만 남김).

마커:
    <!-- agent-cairn:start -->
    ...관리 영역...
    <!-- agent-cairn:end -->
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

_START = "<!-- agent-cairn:start -->"
_END = "<!-- agent-cairn:end -->"


def _wrap(content: str) -> str:
    body = content.strip("\n")
    return f"{_START}\n{body}\n{_END}\n"


def merge(existing: str | None, new_content: str, force: bool) -> str:
    if existing is None:
        return _wrap(new_content)

    start_idx = existing.find(_START)
    end_idx = existing.find(_END)

    if start_idx != -1 and end_idx != -1 and end_idx > start_idx:
        before = existing[:start_idx]
        after = existing[end_idx + len(_END) :]
        return before + _wrap(new_content) + after

    if force:
        return _wrap(new_content)

    # 마커 없음 + 기존 파일 있음 → 하단에 append
    if not existing.endswith("\n"):
        existing += "\n"
    return existing + "\n" + _wrap(new_content)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("target")
    parser.add_argument("content_file")
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()

    target = Path(args.target)
    content = Path(args.content_file).read_text(encoding="utf-8")
    existing = target.read_text(encoding="utf-8") if target.exists() else None

    merged = merge(existing, content, args.force)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(merged, encoding="utf-8")

    status = "created" if existing is None else "updated"
    print(f"  [{status}] {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

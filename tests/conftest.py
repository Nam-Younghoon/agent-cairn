"""pytest 공통 설정 — .claude/hooks 를 import 가능하게 한다."""
from __future__ import annotations

import sys
from pathlib import Path

_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(_ROOT / ".claude" / "hooks"))

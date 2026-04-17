#!/usr/bin/env python3
"""Bash 툴 호출에 대한 위험 명령 차단 훅.

하네스 PreToolUse 훅으로 등록되어 stdin 으로 훅 페이로드(JSON)를 받는다.
금지 패턴에 매칭되면 exit 2 + stderr 로 차단 사유를 출력한다.

독립 테스트 가능하도록 모든 판정 로직은 `evaluate(command)` 에 모여 있다.
단위 테스트는 tests/test_block_dangerous.py 참조.
"""
from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass


@dataclass(frozen=True)
class Decision:
    allow: bool
    reason: str = ""


# --- 금지 패턴 정의 ---------------------------------------------------------
#
# 모든 패턴은 대소문자 무시(re.IGNORECASE)로 컴파일.
# 이유: Windows·일부 셸·alias 에서 대문자 플래그가 인식되는 경우를 방어.
#       또한 rm -Rf (BSD/GNU rm 공통) 는 실제로 작동하는 치명적 변형.
#
# 알려진 한계(false positive): `echo "rm -rf ..."` 처럼 위험 명령 문자열을
# 단순 출력하는 경우도 차단된다. 안전을 위한 허용 가능한 과차단.

_FLAGS = re.IGNORECASE

# rm -rf 계열: -r/-f 플래그가 어떤 순서로든 결합된 경우.
# 같은 플래그 덩어리 내에 verbose(-v) 등 다른 문자가 섞여도 차단.
_RM_RECURSIVE_FORCE = re.compile(
    r"(?:^|[^a-zA-Z0-9])rm\s+-[a-zA-Z]*"
    r"(?:r[a-zA-Z]*f|f[a-zA-Z]*r)"
    r"[a-zA-Z]*(?:\s|$)",
    _FLAGS,
)

# git push --force / -f (단, --force-with-lease 는 허용)
_GIT_PUSH = re.compile(r"(?:^|[^a-zA-Z0-9])git\s+push\b", _FLAGS)
_GIT_FORCE_FLAG = re.compile(r"\s(?:-f|--force)(?:\s|$)", _FLAGS)

# git reset --hard
_GIT_RESET_HARD = re.compile(
    r"(?:^|[^a-zA-Z0-9])git\s+reset\s+(?:\S+\s+)*--hard\b", _FLAGS
)

# git clean -f 계열
_GIT_CLEAN_FORCE = re.compile(
    r"(?:^|[^a-zA-Z0-9])git\s+clean\b.*\s-[a-zA-Z]*f", _FLAGS
)

# sudo / chmod 777 / curl|sh 등 흔한 원클릭 장애 유발 패턴
_SUDO = re.compile(r"(?:^|[^a-zA-Z0-9])sudo\s+", _FLAGS)
_CHMOD_777 = re.compile(
    r"(?:^|[^a-zA-Z0-9])chmod\s+(?:-r\s+)?777\b", _FLAGS
)
_PIPE_TO_SHELL = re.compile(
    r"(?:curl|wget)\s.+\|\s*(?:sudo\s+)?(?:sh|bash|zsh)\b", _FLAGS
)

# DROP DATABASE — 환경 무관 차단
_DROP_DATABASE = re.compile(r"drop\s+database\b", _FLAGS)

# 운영 DB 스키마 변경 (ALTER/DROP TABLE + prod/production 식별자 동시 포함)
_ALTER_OR_DROP_TABLE = re.compile(r"(?:drop|alter)\s+table\b", _FLAGS)
_PROD_IDENTIFIER = re.compile(r"prod(?:uction)?", _FLAGS)


def evaluate(command: str) -> Decision:
    """주어진 Bash 명령 문자열에 대한 허용/차단 판정을 반환."""
    if not command:
        return Decision(allow=True)

    if _RM_RECURSIVE_FORCE.search(command):
        return Decision(False, "rm -rf 계열 명령은 하네스 규정에 의해 금지됩니다.")

    if _GIT_PUSH.search(command) and _GIT_FORCE_FLAG.search(command):
        return Decision(
            False,
            "git force push 는 금지됩니다. 필요한 경우 --force-with-lease 를 사용하세요.",
        )

    if _GIT_RESET_HARD.search(command):
        return Decision(False, "git reset --hard 는 금지됩니다.")

    if _GIT_CLEAN_FORCE.search(command):
        return Decision(False, "git clean -f 계열은 금지됩니다. 필요한 파일을 복구할 수 없습니다.")

    if _SUDO.search(command):
        return Decision(False, "sudo 사용은 금지됩니다. 로컬 권한이 필요한 작업은 사용자에게 위임하세요.")

    if _CHMOD_777.search(command):
        return Decision(False, "chmod 777 은 금지됩니다. 최소 권한 원칙을 지키세요.")

    if _PIPE_TO_SHELL.search(command):
        return Decision(False, "curl|wget 를 sh/bash 로 파이프하는 패턴은 금지됩니다.")

    if _DROP_DATABASE.search(command):
        return Decision(False, "DROP DATABASE 는 금지됩니다.")

    if _ALTER_OR_DROP_TABLE.search(command) and _PROD_IDENTIFIER.search(command):
        return Decision(
            False,
            "운영 DB 대상 스키마 변경(DROP/ALTER TABLE)은 금지됩니다. 마이그레이션 도구를 사용하세요.",
        )

    return Decision(allow=True)


def _read_hook_payload() -> dict:
    try:
        raw = sys.stdin.read()
    except Exception:
        return {}
    if not raw.strip():
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {}


def main() -> int:
    payload = _read_hook_payload()
    tool_input = payload.get("tool_input") or {}
    command = tool_input.get("command", "") or ""

    decision = evaluate(command)
    if decision.allow:
        return 0

    sys.stderr.write(f"[하네스 차단] {decision.reason}\n")
    sys.stderr.write(f"명령: {command}\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())

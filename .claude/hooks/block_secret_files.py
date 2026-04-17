#!/usr/bin/env python3
"""Write/Edit 툴 호출에 대한 시크릿 파일·시크릿 내용 차단 훅.

다음을 차단한다.
  1. 보호 대상 경로에 대한 Write/Edit (.env, .env.production 등. .env.example 은 허용)
  2. 작성하려는 content 에 시크릿 패턴(.claude/patterns/secrets.yaml) 이 포함된 경우

YAML 파싱은 표준 라이브러리만으로 구현한다 (PyYAML 의존 제거).
"""
from __future__ import annotations

import json
import os
import re
import sys
from dataclasses import dataclass
from pathlib import Path


# --- 시크릿 파일 경로 차단 ---------------------------------------------------

# 경로가 시크릿 환경파일로 해석되는지 판단. .env.example / .env.template 은 허용.
_PROTECTED_ENV_NAME = re.compile(
    r"(?:^|/)\.env(?:\.(?:local|production|prod|staging|development|dev|test))?$"
)
_ALLOWED_ENV_SUFFIX = re.compile(r"\.env\.(?:example|sample|template)$")


def is_protected_path(path: str) -> bool:
    if not path:
        return False
    if _ALLOWED_ENV_SUFFIX.search(path):
        return False
    return bool(_PROTECTED_ENV_NAME.search(path))


# tests/ 디렉토리의 테스트 파일은 시크릿 패턴을 고의로 포함할 수 있다 (픽스쳐).
# 따라서 content 스캔을 면제한다. 단, 경로 자체가 `.env` 류면 위 `is_protected_path`
# 로 여전히 차단되므로 실 시크릿 파일을 tests/ 아래 두어도 보호된다.
_TEST_PATH = re.compile(
    r"(?:^|/)tests?/(?:.*?/)?test[_-]?[^/]*\.(?:py|ts|tsx|js|jsx|dart)$"
)


def is_test_fixture_path(path: str) -> bool:
    if not path:
        return False
    normalized = path.replace("\\", "/")
    return bool(_TEST_PATH.search(normalized))


# --- 시크릿 패턴 로딩 --------------------------------------------------------

@dataclass(frozen=True)
class SecretPattern:
    name: str
    regex: re.Pattern


def _patterns_file() -> Path:
    base = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())
    return Path(base) / ".claude" / "patterns" / "secrets.yaml"


def _parse_simple_yaml(text: str) -> list[dict]:
    """매우 단순한 YAML 파서.

    지원 형식: secrets.yaml 의 리스트 스타일만.
        patterns:
          - name: ...
            regex: "..."
    따옴표 제거·이스케이프 해석 포함. 일반 YAML 용도로는 사용하지 말 것.
    """
    items: list[dict] = []
    current: dict | None = None
    in_patterns = False
    for raw_line in text.splitlines():
        line = raw_line.rstrip()
        if not line or line.lstrip().startswith("#"):
            continue
        if line.startswith("patterns:"):
            in_patterns = True
            continue
        if not in_patterns:
            continue
        stripped = line.lstrip()
        indent = len(line) - len(stripped)
        if stripped.startswith("- "):
            if current:
                items.append(current)
            current = {}
            rest = stripped[2:]
            if ":" in rest:
                k, _, v = rest.partition(":")
                current[k.strip()] = _unquote(v.strip())
        elif current is not None and indent >= 4 and ":" in stripped:
            k, _, v = stripped.partition(":")
            current[k.strip()] = _unquote(v.strip())
    if current:
        items.append(current)
    return items


def _unquote(value: str) -> str:
    if len(value) >= 2 and value[0] == value[-1] and value[0] in ("'", '"'):
        inner = value[1:-1]
        if value[0] == '"':
            return bytes(inner, "utf-8").decode("unicode_escape")
        return inner
    return value


def load_patterns() -> list[SecretPattern]:
    path = _patterns_file()
    if not path.exists():
        return []
    try:
        items = _parse_simple_yaml(path.read_text(encoding="utf-8"))
    except OSError:
        return []
    patterns: list[SecretPattern] = []
    for item in items:
        name = item.get("name")
        regex = item.get("regex")
        if not name or not regex:
            continue
        try:
            patterns.append(SecretPattern(name=name, regex=re.compile(regex)))
        except re.error:
            sys.stderr.write(f"[경고] 잘못된 시크릿 정규식 무시: {name}\n")
    return patterns


def find_secret(content: str, patterns: list[SecretPattern]) -> SecretPattern | None:
    if not content:
        return None
    for pattern in patterns:
        if pattern.regex.search(content):
            return pattern
    return None


# --- 훅 진입점 ---------------------------------------------------------------

def _extract_target(tool_input: dict) -> tuple[str, str]:
    """tool_input 에서 (파일 경로, 작성 내용) 을 추출. Edit 의 new_string 도 검사."""
    path = tool_input.get("file_path") or tool_input.get("path") or ""
    content = (
        tool_input.get("content")
        or tool_input.get("new_string")
        or tool_input.get("text")
        or ""
    )
    return path, content


def main() -> int:
    try:
        payload = json.loads(sys.stdin.read() or "{}")
    except json.JSONDecodeError:
        return 0

    tool_name = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}
    path, content = _extract_target(tool_input)

    if is_protected_path(path):
        sys.stderr.write(
            "[하네스 차단] 시크릿 환경파일에 대한 직접 쓰기는 금지됩니다: "
            f"{path}\n환경변수는 .env.example 에만 예시 키를 기록하고 실제 값은 로컬/시크릿 매니저에서 주입하세요.\n"
        )
        return 2

    # 테스트 파일은 시크릿 패턴 픽스쳐를 허용 (content 스캔 면제)
    if is_test_fixture_path(path):
        return 0

    secret = find_secret(content, load_patterns())
    if secret:
        sys.stderr.write(
            f"[하네스 차단] 작성하려는 내용에 시크릿으로 추정되는 값이 포함되어 있습니다: {secret.name}\n"
            f"대상 파일: {path or '<unknown>'}\n"
            "환경변수/시크릿 매니저로 이동시키거나, 의도적 예시라면 플레이스홀더로 대체하세요.\n"
        )
        return 2

    _ = tool_name  # 현재는 매처로 이미 필터됨
    return 0


if __name__ == "__main__":
    sys.exit(main())

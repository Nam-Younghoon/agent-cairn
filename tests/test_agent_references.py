"""서브에이전트 참조 정합성 테스트.

하네스는 문서(슬래시 커맨드·CLI 어댑터)가 서브에이전트를 **이름으로** 호출한다.
정의가 사라졌는데 문서가 남으면 컴파일 에러 없이 조용히 깨지므로,
"정의 집합 == 참조 집합" 을 회귀 테스트로 고정한다.
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parent.parent

# 네이티브 위임으로 폐기된 에이전트. 어떤 하네스 자산에서도 참조되면 안 된다.
DEPRECATED_AGENTS = {"parallel-explorer"}

# Claude Code 빌트인이거나 애초에 에이전트가 아닌 kebab-case 토큰 (오탐 흡수).
ALLOWED_NON_HARNESS = {
    # Claude Code 빌트인 서브에이전트
    "general-purpose",
    "code-reviewer",
    "statusline-setup",
    "claude-code-guide",
    # 에이전트가 아닌 토큰 — 'agent' 가 들어간 줄에 우연히 등장한다
    "agent-cairn",
}

# 참조를 검사할 하네스 자산.
# 제외 대상: CHANGELOG.md 와 .claude/VERSION_NOTES.md 는 '변경 이력' 을 담으므로 과거 이름 언급이
# 정당하고, __docs/ 는 브랜치 전용 작업 문서라 배포물이 아니다.
SCAN_GLOBS = (
    "CLAUDE.md",
    "GEMINI.md",
    "README.md",
    ".claude/commands/*.md",
    ".claude/agents/*.md",
    ".codex/prompts/*.md",
    ".gemini/commands/*.toml",
    "scripts/*.sh",  # 단, CLEANUP_SCRIPTS 는 제외 (_scan_files 참조)
    "templates/*/CLAUDE.md",
    "templates/__docs/*.md",
)

_AGENT_TOKEN = re.compile(r"`([a-z][a-z0-9]*(?:-[a-z0-9]+)+)`")


# 폐기 자산을 "삭제하기 위해" 이름으로 지목해야 하는 정리 스크립트.
# 지시문이 아니라 마이그레이션 코드이므로 잔존 참조 검사에서 제외한다.
CLEANUP_SCRIPTS = {"scripts/migrate-consumers.sh"}


def _scan_files() -> list[Path]:
    files: list[Path] = []
    for pattern in SCAN_GLOBS:
        files.extend(sorted(_ROOT.glob(pattern)))
    return [
        f for f in files
        if f.is_file() and str(f.relative_to(_ROOT)) not in CLEANUP_SCRIPTS
    ]


def _defined_agents() -> set[str]:
    names: set[str] = set()
    for agent_file in sorted((_ROOT / ".claude" / "agents").glob("*.md")):
        for line in agent_file.read_text(encoding="utf-8").splitlines():
            if line.startswith("name:"):
                names.add(line.split(":", 1)[1].strip())
                break
    return names


@pytest.mark.parametrize("deprecated", sorted(DEPRECATED_AGENTS))
def test_deprecated_agent_is_not_referenced(deprecated: str) -> None:
    """폐기된 에이전트 이름이 하네스 자산 어디에도 남아 있으면 안 된다."""
    offenders = []
    for path in _scan_files():
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if deprecated in line:
                offenders.append(f"{path.relative_to(_ROOT)}:{lineno}")
    assert not offenders, (
        f"폐기된 에이전트 '{deprecated}' 참조가 남아 있습니다:\n  "
        + "\n  ".join(offenders)
    )


def test_deprecated_agent_definition_is_removed() -> None:
    """폐기된 에이전트의 정의 파일이 남아 있으면 안 된다."""
    for deprecated in DEPRECATED_AGENTS:
        assert not (_ROOT / ".claude" / "agents" / f"{deprecated}.md").exists(), (
            f".claude/agents/{deprecated}.md 가 아직 존재합니다."
        )


def test_every_referenced_agent_is_defined() -> None:
    """에이전트를 언급하는 줄의 kebab-case 토큰은 모두 정의되어 있어야 한다.

    정의 집합(`.claude/agents/`)에도 허용 목록에도 없는 토큰은 전부 dangling 으로 본다.
    빌트인이나 에이전트가 아닌 토큰이 걸리면 `ALLOWED_NON_HARNESS` 에 추가해 흡수한다.
    """
    defined = _defined_agents()
    assert defined, ".claude/agents/ 에서 에이전트 정의를 찾지 못했습니다."

    known = defined | ALLOWED_NON_HARNESS
    dangling = []
    for path in _scan_files():
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if "에이전트" not in line and "agent" not in line.lower():
                continue
            # 커맨드/스킬(`/name`)·파일 경로는 '/' 나 '.' 때문에 애초에 매칭되지 않는다.
            for token in _AGENT_TOKEN.findall(line):
                if token in known:
                    continue
                dangling.append(f"{path.relative_to(_ROOT)}:{lineno} -> {token}")
    assert not dangling, (
        "정의되지 않은 에이전트 참조 (오탐이면 ALLOWED_NON_HARNESS 에 추가):\n  "
        + "\n  ".join(dangling)
    )

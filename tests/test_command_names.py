"""슬래시 커맨드 이름 충돌 회귀 테스트.

하네스 커맨드가 Claude Code 내장 커맨드와 이름이 겹치면, 공식 문서상
로컬 터미널 세션에서 **커스텀이 내장을 가린다**. 에러 없이 조용히 덮어쓰므로
사람이 알아채기 어렵다. 그래서 이름 충돌을 테스트로 고정한다.

`BUILTIN_COMMANDS` 는 설치된 Claude Code 번들에서 추출한 스냅샷이다.
CLI 가 올라가면 내장 커맨드가 늘어나므로 주기적으로 갱신해야 한다.
갱신 방법과 점검 주기는 `.claude/VERSION_NOTES.md` §3 참조.
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parent.parent

# Claude Code 2.1.312 번들에서 추출 (2026-10-29).
#   strings -a <bundle> | grep -oE 'type:"(local-jsx|local|prompt)",name:"[a-z][a-z0-9-]*"' \
#     | sed -E 's/.*name:"([a-z0-9-]+)"/\1/' | sort -u
BUILTIN_COMMANDS = frozenset({
    "add-dir", "advisor", "agents", "artifacts",
    "auto-mode-setup", "autocompact", "autofix-pr", "background",
    "branch", "brief", "btw", "bug",
    "cd", "clear", "cloud-plugins", "color",
    "compact", "config", "context", "copy",
    "daemon", "design-consent", "design-login", "design-revoke",
    "desktop", "diff", "effort", "exit",
    "export", "extra-usage", "fast", "feedback",
    "focus", "fork", "goal", "heapdump",
    "help", "hooks", "ide", "import",
    "init", "insights", "install", "install-github-app",
    "install-slack-app", "list-agents", "login", "logout",
    "loops", "mcp", "memory", "mobile",
    "model", "output-style", "passes", "pause-memory",
    "permissions", "plan", "plugin", "powerup",
    "privacy-settings", "pro-trial-expired", "radio", "rate-limit-options",
    "recap", "reload-plugins", "reload-skills", "remote-control",
    "remote-env", "rename", "restart", "resume",
    "scroll-speed", "session", "setup-bedrock", "setup-vertex",
    "skill-doctor", "skills", "status", "stickers",
    "stop", "subtask", "tasks", "team-onboarding",
    "teleport", "terminal-setup", "theme", "tui",
    "ultraplan", "ultrareview", "upgrade", "usage",
    "usage-credits", "version", "voice", "web-setup",
    "wellbeing", "workflow-launch-exec", "workflows",
})

# 하네스 커맨드가 정의된 위치 — 세 CLI 가 같은 이름 집합을 가져야 한다.
COMMAND_SOURCES = {
    "claude": (".claude/commands", "*.md"),
    "codex": (".codex/prompts", "*.md"),
    "gemini": (".gemini/commands", "*.toml"),
}


def _command_names(cli: str) -> set[str]:
    directory, pattern = COMMAND_SOURCES[cli]
    return {command_path.stem for command_path in sorted((_ROOT / directory).glob(pattern))}


@pytest.mark.parametrize("cli", sorted(COMMAND_SOURCES))
def test_no_collision_with_builtin_commands(cli: str) -> None:
    """하네스 커맨드 이름이 Claude Code 내장 커맨드와 겹치면 안 된다."""
    names = _command_names(cli)
    assert names, f"{cli} 커맨드를 찾지 못했습니다."

    collisions = sorted(names & BUILTIN_COMMANDS)
    assert not collisions, (
        f"{cli} 커맨드가 Claude Code 내장 커맨드와 이름이 겹칩니다: {collisions}\n"
        "커스텀이 내장을 가리므로 이름을 바꾸세요 (.claude/VERSION_NOTES.md §3 참조)."
    )


def test_command_names_match_across_clis() -> None:
    """세 CLI 의 커맨드 이름 집합이 동일해야 한다 (한쪽만 이름을 바꾸는 사고 방지)."""
    sets = {cli: _command_names(cli) for cli in COMMAND_SOURCES}
    reference = sets["claude"]
    mismatched = {cli: sorted(names ^ reference) for cli, names in sets.items() if names != reference}
    assert not mismatched, f"CLI 간 커맨드 이름 불일치 (claude 기준 차집합): {mismatched}"


# 개명으로 폐기된 커맨드 이름. 배포 자산에 남아 있으면 안 된다.
# 개명할 때마다 구 이름을 여기 추가한다.
DEPRECATED_COMMAND_NAMES = {"plan"}

# 이력을 기술하는 문서는 과거 이름 언급이 정당하므로 제외한다.
_HISTORY_FILES = {"CHANGELOG.md", ".claude/VERSION_NOTES.md"}

_SCAN_GLOBS = (
    "README.md", "CLAUDE.md", "GEMINI.md",
    ".claude/commands/*.md", ".claude/agents/*.md",
    ".codex/prompts/*.md", ".gemini/commands/*.toml",
    "scripts/*.sh",
    "templates/*/CLAUDE.md", "templates/__docs/*.md", "templates/__docs/*.json",
)


def _is_asset_line(line: str) -> bool:
    """셸 스크립트에서 배포 자산 경로를 다루는 줄인지."""
    return "copy_file" in line or "for cmd in" in line or '"."' in line.replace(" ", "") or (
        line.lstrip().startswith('".') and line.rstrip().endswith('"')
    )


def _stale_patterns(name: str) -> list[re.Pattern[str]]:
    """구 이름의 참조 형태. 상태 파일(plan.json 계열)은 일부러 제외한다."""
    return [
        re.compile(rf"/{name}(?![-\w.])"),          # 슬래시 커맨드: /plan
        re.compile(rf"/{name}\.(?:md|toml)\b"),     # 커맨드 파일 경로: commands/plan.md
        re.compile(rf"[{{,]{name}[,}}]"),            # 중괄호 확장형: {discuss,plan,...}
    ]


@pytest.mark.parametrize("deprecated", sorted(DEPRECATED_COMMAND_NAMES))
def test_deprecated_command_name_is_not_referenced(deprecated: str) -> None:
    """개명 전 커맨드 이름이 배포 자산에 남아 있으면 안 된다.

    일괄 치환은 한 가지 표기만 잡고 나머지를 놓치기 쉽다 (슬래시형은 바꿨는데
    중괄호 확장형 `{discuss,plan,...}` 은 남는 식). 표기별로 모두 검사한다.
    """
    patterns = _stale_patterns(deprecated)
    offenders = []
    for pattern_glob in _SCAN_GLOBS:
        for path in sorted(_ROOT.glob(pattern_glob)):
            rel = str(path.relative_to(_ROOT))
            if not path.is_file() or rel in _HISTORY_FILES:
                continue
            is_shell = path.suffix == ".sh"
            for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                # 셸 스크립트는 자산 경로 줄만 본다. 사용자 안내 문구는 구본 파일명을
                # 적어야 하므로(마이그레이션 안내) 검사 대상이 아니다.
                if is_shell and not _is_asset_line(line):
                    continue
                if any(regex.search(line) for regex in patterns):
                    offenders.append(f"{rel}:{lineno}")
    assert not offenders, (
        f"개명 전 커맨드 이름 '{deprecated}' 참조가 남아 있습니다:\n  "
        + "\n  ".join(offenders)
    )

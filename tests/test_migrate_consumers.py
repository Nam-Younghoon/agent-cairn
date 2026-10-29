"""scripts/migrate-consumers.sh 동작 테스트.

하네스를 설치한 소비 프로젝트의 `.claude/` 는 gitignore 대상이라
`install.sh`(추가 전용)나 직접 `cp` 로는 **개명·폐기된 구본이 지워지지 않는다**.
구본이 남으면 내장 슬래시 커맨드를 계속 가리므로 별도 마이그레이션이 필요하다.
"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parent.parent
_SCRIPT = _ROOT / "scripts" / "migrate-consumers.sh"

# 개명·폐기로 버려진 자산. 소비 프로젝트에서 제거 대상이다.
DEPRECATED_ASSETS = (
    ".claude/commands/plan.md",
    ".claude/agents/parallel-explorer.md",
)


def _make_consumer(root: Path, name: str) -> Path:
    """하네스가 설치된 것처럼 보이는 가짜 소비 프로젝트."""
    project = root / name
    (project / ".claude" / "commands").mkdir(parents=True)
    (project / ".claude" / "agents").mkdir(parents=True)
    (project / ".claude" / "commands" / "discuss.md").write_text("old discuss\n", encoding="utf-8")
    for asset in DEPRECATED_ASSETS:
        (project / asset).write_text("old\n", encoding="utf-8")
    (project / ".claude" / "settings.local.json").write_text('{"local": true}\n', encoding="utf-8")
    return project


def _run(root: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["bash", str(_SCRIPT), "--root", str(root), *args],
        capture_output=True, text=True, check=False,
    )


@pytest.fixture()
def workspace(tmp_path: Path) -> Path:
    _make_consumer(tmp_path, "app-one")
    _make_consumer(tmp_path, "app-two")

    # 워크트리 안의 미끼 — 스캔이 파고들면 안 된다
    decoy = tmp_path / "app-one" / ".claude" / "worktrees" / "wt" / ".claude" / "commands"
    decoy.mkdir(parents=True)
    (decoy / "plan.md").write_text("decoy\n", encoding="utf-8")

    # 하네스 미설치 디렉토리
    (tmp_path / "not-a-consumer" / "src").mkdir(parents=True)

    # 하네스 레포 자신
    self_repo = tmp_path / "agent-cairn" / ".claude" / "commands"
    self_repo.mkdir(parents=True)
    (self_repo / "discuss.md").write_text("self\n", encoding="utf-8")
    return tmp_path


def test_dry_run_is_default_and_changes_nothing(workspace: Path) -> None:
    """--apply 없이는 아무것도 바꾸지 않는다. 14개 레포를 한 번에 건드리므로 기본값이 안전해야 한다."""
    result = _run(workspace)

    assert result.returncode == 0, result.stderr
    for project in ("app-one", "app-two"):
        for asset in DEPRECATED_ASSETS:
            assert (workspace / project / asset).exists(), f"{project}/{asset} 가 dry-run 에서 삭제됨"
        assert not (workspace / project / ".claude" / "commands" / "plan-steps.md").exists()


def test_dry_run_reports_only_harness_consumers(workspace: Path) -> None:
    """하네스 설치본만 대상으로 보고하고, 미설치 디렉토리와 하네스 레포 자신은 제외한다."""
    output = _run(workspace).stdout

    assert "app-one" in output
    assert "app-two" in output
    assert "not-a-consumer" not in output
    assert "agent-cairn" not in output


def test_apply_removes_deprecated_and_deploys_current(workspace: Path) -> None:
    result = _run(workspace, "--apply")
    assert result.returncode == 0, result.stderr

    for project in ("app-one", "app-two"):
        base = workspace / project
        for asset in DEPRECATED_ASSETS:
            assert not (base / asset).exists(), f"{project}/{asset} 가 제거되지 않음"
        assert (base / ".claude" / "commands" / "plan-steps.md").exists()
        assert (base / ".claude" / "VERSION_NOTES.md").exists()


def test_apply_preserves_local_settings(workspace: Path) -> None:
    """settings.local.json 은 사용자 로컬 상태라 절대 덮어쓰지 않는다."""
    _run(workspace, "--apply")

    local = workspace / "app-one" / ".claude" / "settings.local.json"
    assert local.exists()
    assert json.loads(local.read_text(encoding="utf-8")) == {"local": True}


def test_apply_does_not_touch_worktrees(workspace: Path) -> None:
    """.claude/worktrees/ 안에는 별도 체크아웃이 들어 있다. 스캔도 수정도 하면 안 된다."""
    _run(workspace, "--apply")

    decoy = workspace / "app-one" / ".claude" / "worktrees" / "wt" / ".claude" / "commands" / "plan.md"
    assert decoy.exists(), "워크트리 내부 파일이 삭제됨"


def test_apply_backs_up_before_removing(workspace: Path) -> None:
    """소비 프로젝트의 .claude 는 gitignore 대상이라 삭제가 git 으로 복구되지 않는다."""
    _run(workspace, "--apply")

    backups = list((workspace / "app-one" / ".claude").glob(".migrate-backup-*"))
    assert backups, "백업 디렉토리가 생성되지 않음"
    assert (backups[0] / "commands" / "plan.md").exists(), "백업에 구본이 들어 있지 않음"


def test_apply_is_idempotent(workspace: Path) -> None:
    """재실행해도 실패하지 않는다 (이미 정리된 프로젝트가 섞여 있을 수 있다)."""
    assert _run(workspace, "--apply").returncode == 0
    second = _run(workspace, "--apply")
    assert second.returncode == 0, second.stderr

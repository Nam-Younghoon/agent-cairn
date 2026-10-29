"""하네스 자산이 .gitignore 에 걸려 커밋 불가가 되는 사고를 막는 회귀 테스트.

`__docs/` 규칙은 경로 어디에 있든 `__docs` 디렉토리를 배제한다. 그런데 하네스는
문서 템플릿을 `templates/__docs/` (레포 자신) 와 `.claude|.codex|.gemini/templates/__docs/`
(소비자 프로젝트) 로 배포한다. 둘이 충돌하면 **install.sh 는 복사에 성공하고
test-harness 는 "파일이 있다" 고 통과하는데, 정작 팀원이 커밋할 수 없다.**
clone 한 동료에게는 plan 스키마도 문서 템플릿도 없는 상태가 된다.

배제 자체는 유지해야 한다 — 브랜치 전용 작업 문서가 리모트로 새는 것을 막는 장치다.
그래서 "배제는 그대로 두고 배포 자산만 되살리는" 화이트리스트가 맞는지를 여기서 고정한다.
"""
from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

_ROOT = Path(__file__).resolve().parent.parent

# 소비자 프로젝트에 배포되는 문서 템플릿 경로. install.sh 가 CLI 별로 복사한다.
DEPLOYED_TEMPLATE_DIRS = (
    ".claude/templates/__docs",
    ".codex/templates/__docs",
    ".gemini/templates/__docs",
)

# 배포되는 템플릿 파일 이름 (대표값).
TEMPLATE_FILES = ("plan.schema.json", "plan.example.json", "PRD.md")


def is_ignored(repo: Path, relative_path: str) -> bool:
    """`git check-ignore` 로 판정한다. 추론하지 않고 git 에게 직접 묻는다."""
    result = subprocess.run(
        ["git", "-C", str(repo), "check-ignore", "-q", "--no-index", relative_path],
        capture_output=True,
    )
    if result.returncode not in (0, 1):
        pytest.fail(f"git check-ignore 실패: {result.stderr.decode()}")
    return result.returncode == 0


@pytest.fixture
def consumer_repo(tmp_path: Path) -> Path:
    """gitignore.partial 만 적용한 가짜 소비자 프로젝트.

    install.sh 를 타지 않고 **배포물 자체**를 검증한다 — 설치 경로가 바뀌어도
    규칙의 의미는 변하지 않아야 하기 때문이다.
    """
    subprocess.run(["git", "init", "-q", str(tmp_path)], check=True)
    partial = (_ROOT / "templates/gitignore.partial").read_text(encoding="utf-8")
    (tmp_path / ".gitignore").write_text(partial, encoding="utf-8")
    return tmp_path


@pytest.mark.parametrize("template_dir", DEPLOYED_TEMPLATE_DIRS)
@pytest.mark.parametrize("filename", TEMPLATE_FILES)
def test_배포된_문서_템플릿은_커밋할_수_있어야_한다(
    consumer_repo: Path, template_dir: str, filename: str
) -> None:
    path = f"{template_dir}/{filename}"
    assert not is_ignored(consumer_repo, path), (
        f"{path} 가 ignore 된다 — install.sh 가 복사해도 팀원이 커밋할 수 없다"
    )


def test_브랜치_작업_문서는_여전히_배제되어야_한다(consumer_repo: Path) -> None:
    """화이트리스트가 과하면 작업 문서가 리모트로 샌다. 배제는 유지돼야 한다."""
    for path in ("__docs/PRD.md", "__docs/plan.json", "__docs/ADR.md"):
        assert is_ignored(consumer_repo, path), f"{path} 가 배제되지 않는다 — 유출 위험"


def test_중첩_프로젝트의_작업_문서도_배제되어야_한다(consumer_repo: Path) -> None:
    """모노레포에서 앱 디렉토리 안에 만들어진 __docs/ 도 새면 안 된다."""
    assert is_ignored(consumer_repo, "apps/api/__docs/PRD.md")


@pytest.mark.parametrize("filename", TEMPLATE_FILES)
def test_하네스_레포_자신의_템플릿도_커밋할_수_있어야_한다(filename: str) -> None:
    """이 레포의 templates/__docs/ 는 추적 중인 배포 원본이다.

    ignore 에 걸리면 `git add` 가 0 이 아닌 코드를 반환해, `&&` 로 이어 붙인 커밋이
    조용히 건너뛰어진다.
    """
    path = f"templates/__docs/{filename}"
    assert (_ROOT / path).exists(), f"전제가 깨졌다 — {path} 가 없다"
    assert not is_ignored(_ROOT, path), f"{path} 가 ignore 된다"

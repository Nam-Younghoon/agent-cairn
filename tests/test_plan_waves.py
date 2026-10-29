"""wave 계산기 단위 테스트.

`/execute` 가 `plan.json` 의 독립 스텝을 병렬로 돌리려면 "지금 동시에 띄워도 되는
스텝 집합"을 정확히 뽑아야 한다. 이 판정을 LLM 추론에 맡기면 틀려도 조용히 지나가고
두 워커가 같은 파일을 밟는 사고로만 드러난다. 그래서 판정을 실행 가능한 코드로 빼내
여기서 고정한다.

wave 규칙:
  ready = status 가 pending 이고 depends_on 이 모두 completed 인 스텝
  wave  = ready 중 touches 가 서로 겹치지 않는 최대 집합 (id 오름차순 탐욕 선택)

touches 가 없거나 빈 스텝은 "무엇을 건드릴지 모름" 이므로 **단독 실행**한다.
덕분에 touches 가 없는 과거 plan.json 은 자동으로 기존 순차 동작으로 퇴화한다.
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from plan_waves import (
    atomic_write_plan,
    compute_wave,
    find_dependency_cycles,
    paths_conflict,
    ready_step_ids,
    update_step,
)

_ROOT = Path(__file__).resolve().parent.parent


def make_step(step_id: int, **overrides: object) -> dict:
    """테스트용 스텝 한 개. 기본값은 pending + 의존성 없음."""
    step = {
        "id": step_id,
        "title": f"스텝 {step_id}",
        "status": "pending",
        "depends_on": [],
        "touches": [f"src/file-{step_id}.ts"],
    }
    step.update(overrides)
    return step


def make_plan(*steps: dict) -> dict:
    return {
        "version": 1,
        "branch": "feat/sample",
        "type": "feat",
        "title": "샘플",
        "created_at": "2026-10-29T00:00:00Z",
        "status": "in_progress",
        "steps": list(steps),
    }


# ---------------------------------------------------------------- paths_conflict


@pytest.mark.parametrize(
    "left,right",
    [
        ("src/a.ts", "src/a.ts"),               # 완전 동일
        ("./src/a.ts", "src/a.ts"),             # 선행 ./ 정규화
        ("src/a.ts", "src//a.ts"),              # 중복 슬래시 정규화
        ("src/auth", "src/auth/login.ts"),      # 디렉토리가 파일을 포함
        ("src/auth/", "src/auth/login.ts"),     # 후행 슬래시 디렉토리 표기
        ("src/auth/login.ts", "src/auth"),      # 반대 방향도 대칭
    ],
)
def test_겹치는_경로는_충돌로_판정한다(left: str, right: str) -> None:
    assert paths_conflict(left, right) is True


@pytest.mark.parametrize(
    "left,right",
    [
        ("src/a.ts", "src/b.ts"),
        ("src/auth", "src/authz"),              # 접두사 문자열이지만 경로 경계가 다르다
        ("src/auth/login.ts", "src/user/login.ts"),
        ("docs/README.md", "src/README.md"),
    ],
)
def test_겹치지_않는_경로는_충돌이_아니다(left: str, right: str) -> None:
    assert paths_conflict(left, right) is False


# ---------------------------------------------------------------- ready_step_ids


def test_의존성이_없는_pending_은_모두_ready() -> None:
    plan = make_plan(make_step(1), make_step(2), make_step(3))
    assert ready_step_ids(plan) == [1, 2, 3]


def test_미완료_의존성이_있으면_ready_가_아니다() -> None:
    plan = make_plan(make_step(1), make_step(2, depends_on=[1]))
    assert ready_step_ids(plan) == [1]


def test_의존성이_completed_면_해제된다() -> None:
    plan = make_plan(
        make_step(1, status="completed"),
        make_step(2, depends_on=[1]),
    )
    assert ready_step_ids(plan) == [2]


@pytest.mark.parametrize("blocking", ["in_progress", "error", "blocked"])
def test_의존성이_completed_가_아닌_어떤_상태여도_막는다(blocking: str) -> None:
    plan = make_plan(
        make_step(1, status=blocking),
        make_step(2, depends_on=[1]),
    )
    assert ready_step_ids(plan) == []


@pytest.mark.parametrize("own_status", ["in_progress", "completed", "error", "blocked"])
def test_pending_이_아닌_스텝은_ready_가_아니다(own_status: str) -> None:
    plan = make_plan(make_step(1, status=own_status))
    assert ready_step_ids(plan) == []


def test_존재하지_않는_의존성_id_는_ready_로_보지_않는다() -> None:
    """오타난 depends_on 을 '없는 의존성' 으로 오인해 성급히 실행하면 안 된다."""
    plan = make_plan(make_step(1, depends_on=[99]))
    assert ready_step_ids(plan) == []


# ---------------------------------------------------------------- compute_wave


def test_독립이고_touches_가_겹치지_않으면_한_웨이브로_묶인다() -> None:
    plan = make_plan(make_step(1), make_step(2), make_step(3))
    assert compute_wave(plan) == [1, 2, 3]


def test_의존성_체인은_한_번에_하나씩만_돈다() -> None:
    plan = make_plan(
        make_step(1),
        make_step(2, depends_on=[1]),
        make_step(3, depends_on=[2]),
    )
    assert compute_wave(plan) == [1]


def test_체인이_진행되면_다음_웨이브가_열린다() -> None:
    plan = make_plan(
        make_step(1, status="completed"),
        make_step(2, depends_on=[1]),
        make_step(3, depends_on=[2]),
    )
    assert compute_wave(plan) == [2]


def test_touches_가_겹치면_id_가_작은_쪽만_웨이브에_든다() -> None:
    plan = make_plan(
        make_step(1, touches=["src/auth/login.ts"]),
        make_step(2, touches=["src/auth/login.ts"]),
        make_step(3, touches=["src/user/profile.ts"]),
    )
    assert compute_wave(plan) == [1, 3]


def test_디렉토리_단위_touches_충돌도_직렬화한다() -> None:
    plan = make_plan(
        make_step(1, touches=["src/auth/"]),
        make_step(2, touches=["src/auth/login.ts"]),
    )
    assert compute_wave(plan) == [1]


def test_touches_가_없는_스텝은_단독으로_실행한다() -> None:
    """무엇을 건드릴지 모르는 스텝은 다른 워커와 같이 띄울 수 없다."""
    plan = make_plan(
        {"id": 1, "title": "레거시", "status": "pending", "depends_on": []},
        make_step(2),
    )
    assert compute_wave(plan) == [1]


def test_touches_가_빈_배열이어도_단독_실행이다() -> None:
    plan = make_plan(make_step(1, touches=[]), make_step(2))
    assert compute_wave(plan) == [1]


def test_touches_없는_스텝이_뒤에_있으면_이번_웨이브에서_제외된다() -> None:
    plan = make_plan(
        make_step(1),
        make_step(2, touches=[]),
        make_step(3),
    )
    assert compute_wave(plan) == [1, 3]


def test_touches_없는_plan_전체는_기존_순차_동작으로_퇴화한다() -> None:
    plan = make_plan(
        {"id": 1, "title": "a", "status": "pending", "depends_on": []},
        {"id": 2, "title": "b", "status": "pending", "depends_on": []},
    )
    assert compute_wave(plan) == [1]


def test_의존성과_touches_충돌이_섞인_경우() -> None:
    """1 완료 → 2·3·4 해제. 2 와 4 가 같은 파일을 만지므로 4 는 다음 웨이브로."""
    plan = make_plan(
        make_step(1, status="completed", touches=["src/schema.ts"]),
        make_step(2, depends_on=[1], touches=["src/auth/login.ts"]),
        make_step(3, depends_on=[1], touches=["src/user/profile.ts"]),
        make_step(4, depends_on=[1], touches=["src/auth/login.ts", "src/other.ts"]),
        make_step(5, depends_on=[4], touches=["src/final.ts"]),
    )
    assert compute_wave(plan) == [2, 3]


def test_여러_touches_중_하나만_겹쳐도_충돌이다() -> None:
    plan = make_plan(
        make_step(1, touches=["src/a.ts", "src/shared.ts"]),
        make_step(2, touches=["src/b.ts", "src/shared.ts"]),
    )
    assert compute_wave(plan) == [1]


def test_모두_완료되면_빈_웨이브() -> None:
    plan = make_plan(make_step(1, status="completed"), make_step(2, status="completed"))
    assert compute_wave(plan) == []


def test_순환_의존성은_빈_웨이브를_낸다() -> None:
    plan = make_plan(
        make_step(1, depends_on=[2]),
        make_step(2, depends_on=[1]),
    )
    assert compute_wave(plan) == []


def test_순환_의존성을_진단할_수_있다() -> None:
    plan = make_plan(
        make_step(1, depends_on=[2]),
        make_step(2, depends_on=[1]),
        make_step(3),
    )
    cycles = find_dependency_cycles(plan)
    assert cycles, "순환이 있는데 감지하지 못했다"
    assert {1, 2} <= set(cycles[0])
    assert 3 not in cycles[0]


def test_순환이_없으면_진단_결과가_비어_있다() -> None:
    plan = make_plan(make_step(1), make_step(2, depends_on=[1]))
    assert find_dependency_cycles(plan) == []


# ---------------------------------------------------------------- 상태 쓰기


def test_update_step_은_지정한_필드만_바꾼다(tmp_path) -> None:
    plan = make_plan(make_step(1), make_step(2))
    path = tmp_path / "plan.json"
    atomic_write_plan(path, plan)

    update_step(path, 1, status="completed", commit="abc1234")

    saved = json.loads(path.read_text(encoding="utf-8"))
    assert saved["steps"][0]["status"] == "completed"
    assert saved["steps"][0]["commit"] == "abc1234"
    assert saved["steps"][0]["title"] == "스텝 1"
    assert saved["steps"][1] == plan["steps"][1], "다른 스텝이 변경되었다"


def test_update_step_은_error_log_에_누적한다(tmp_path) -> None:
    plan = make_plan(make_step(1))
    path = tmp_path / "plan.json"
    atomic_write_plan(path, plan)

    update_step(path, 1, status="error", error="첫 실패")
    update_step(path, 1, status="error", error="두 번째 실패")

    saved = json.loads(path.read_text(encoding="utf-8"))
    messages = [entry["message"] for entry in saved["steps"][0]["error_log"]]
    assert messages == ["첫 실패", "두 번째 실패"]
    assert saved["steps"][0]["retries"] == 2


def test_update_step_은_없는_스텝에_대해_실패한다(tmp_path) -> None:
    path = tmp_path / "plan.json"
    atomic_write_plan(path, make_plan(make_step(1)))
    with pytest.raises(KeyError):
        update_step(path, 99, status="completed")


def test_atomic_write_는_임시파일을_남기지_않는다(tmp_path) -> None:
    path = tmp_path / "plan.json"
    atomic_write_plan(path, make_plan(make_step(1)))
    leftovers = [p.name for p in tmp_path.iterdir() if p.name != "plan.json"]
    assert leftovers == [], f"임시 파일이 남았다: {leftovers}"


def test_템플릿_스키마에_touches_가_정의되어_있다() -> None:
    schema = json.loads(
        (_ROOT / "templates/__docs/plan.schema.json").read_text(encoding="utf-8")
    )
    step_properties = schema["properties"]["steps"]["items"]["properties"]
    assert "touches" in step_properties, "스키마에 touches 가 없다"
    assert step_properties["touches"]["type"] == "array"


def test_템플릿_예시의_모든_스텝이_touches_를_선언한다() -> None:
    """예시가 touches 를 비워두면 '안 적어도 된다' 는 잘못된 신호를 준다."""
    plan = json.loads(
        (_ROOT / "templates/__docs/plan.example.json").read_text(encoding="utf-8")
    )
    missing = [s["id"] for s in plan["steps"] if not s.get("touches")]
    assert missing == [], f"touches 가 빠진 예시 스텝: {missing}"


def test_템플릿_예시가_실제로_병렬_웨이브를_보여준다() -> None:
    """진행 중인 스텝 2 가 끝나면 3·4 가 동시에 떠야 예시로서 값을 한다."""
    plan = json.loads(
        (_ROOT / "templates/__docs/plan.example.json").read_text(encoding="utf-8")
    )
    for step in plan["steps"]:
        if step["id"] == 2:
            step["status"] = "completed"
    assert compute_wave(plan) == [3, 4]


def test_atomic_write_는_기존_내용을_깨지_않는다(tmp_path) -> None:
    """쓰기 도중 파싱 불가 상태가 노출되면 안 되므로 rename 으로 교체한다."""
    path = tmp_path / "plan.json"
    atomic_write_plan(path, make_plan(make_step(1)))
    first = path.read_text(encoding="utf-8")

    atomic_write_plan(path, make_plan(make_step(1), make_step(2)))
    second = path.read_text(encoding="utf-8")

    assert json.loads(first)["steps"] != json.loads(second)["steps"]
    assert second.endswith("\n")

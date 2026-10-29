#!/usr/bin/env python3
"""plan.json 의 wave 계산기 겸 단일 기록기.

`/execute` 가 독립 스텝을 병렬로 돌리려면 두 가지가 필요하다.

1. **지금 동시에 띄워도 되는 스텝 집합(wave)** — 의존성과 파일 충돌을 모두 만족하는 집합.
2. **plan.json 에 대한 단일 쓰기 경로** — 워커 워크트리마다 사본이 갈라지면 상태가 깨지므로
   오케스트레이터만 이 스크립트를 통해 쓴다.

두 책임을 LLM 추론에 맡기지 않고 코드로 고정한 이유는, 틀려도 조용히 지나가고
"두 워커가 같은 파일을 밟았다" 는 사고로만 드러나기 때문이다 (ADR-022).

세 CLI(Claude / Codex / Gemini) 가 같은 스크립트를 호출하므로 표준 라이브러리만 쓴다.

사용법:
    python3 scripts/plan_waves.py wave     [--plan __docs/plan.json] [--max N]
    python3 scripts/plan_waves.py validate [--plan __docs/plan.json]
    python3 scripts/plan_waves.py set <id> --status completed [--commit SHA]
                                           [--artifact PATH]... [--error MSG]
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

DEFAULT_PLAN_PATH = Path("__docs/plan.json")

# 이 상태의 스텝만 새로 띄울 수 있다.
RUNNABLE_STATUS = "pending"
# 의존성이 해제되었다고 인정하는 유일한 상태.
SATISFIED_STATUS = "completed"


# --------------------------------------------------------------------- 경로 비교


def normalize_touch(path: str) -> str:
    """touches 항목을 비교 가능한 형태로 정규화한다.

    `./src/a.ts`, `src//a.ts`, `src/a.ts/` 를 모두 `src/a.ts` 로 맞춘다.
    글롭은 지원하지 않는다 — 글롭끼리의 교집합 판정은 일반적으로 결정 불가라
    "겹치지 않는다" 는 오답을 낼 위험이 크기 때문이다. 구체 경로나 디렉토리만 적는다.
    """
    cleaned = path.strip().replace("\\", "/")
    while cleaned.startswith("./"):
        cleaned = cleaned[2:]
    segments = [seg for seg in cleaned.split("/") if seg not in ("", ".")]
    return "/".join(segments)


def paths_conflict(left: str, right: str) -> bool:
    """두 경로가 같은 대상을 건드리는지 — 동일하거나 한쪽이 다른 쪽의 상위 디렉토리면 충돌."""
    a = normalize_touch(left)
    b = normalize_touch(right)
    if not a or not b:
        return True  # 빈 경로는 범위를 알 수 없으므로 보수적으로 충돌 취급
    if a == b:
        return True
    return a.startswith(b + "/") or b.startswith(a + "/")


def _touches(step: dict[str, Any]) -> list[str]:
    raw = step.get("touches") or []
    return [normalize_touch(p) for p in raw if normalize_touch(p)]


def _conflicts_with_any(candidate: list[str], claimed: list[str]) -> bool:
    return any(paths_conflict(c, t) for c in candidate for t in claimed)


# --------------------------------------------------------------------- 의존성


def _steps_by_id(plan: dict[str, Any]) -> dict[int, dict[str, Any]]:
    return {int(step["id"]): step for step in plan.get("steps", [])}


def ready_step_ids(plan: dict[str, Any]) -> list[int]:
    """지금 착수 가능한 스텝 id 를 오름차순으로 반환.

    `depends_on` 에 적힌 id 가 plan 에 없으면 **해제된 것으로 보지 않는다**.
    오타난 의존성을 "의존성 없음" 으로 오인해 성급히 실행하는 쪽이 더 위험하다.
    """
    index = _steps_by_id(plan)
    ready: list[int] = []
    for step_id in sorted(index):
        step = index[step_id]
        if step.get("status") != RUNNABLE_STATUS:
            continue
        deps = step.get("depends_on") or []
        if all(
            int(dep) in index and index[int(dep)].get("status") == SATISFIED_STATUS
            for dep in deps
        ):
            ready.append(step_id)
    return ready


def find_dependency_cycles(plan: dict[str, Any]) -> list[list[int]]:
    """`depends_on` 그래프의 순환을 모두 찾는다 (Tarjan SCC).

    순환이 있으면 해당 스텝들은 영원히 ready 가 되지 않아 wave 가 조용히 비어버린다.
    `/execute` 가 "할 일이 없다" 와 "계획이 깨졌다" 를 구분하려면 진단이 필요하다.
    """
    index = _steps_by_id(plan)
    order: dict[int, int] = {}
    low: dict[int, int] = {}
    on_stack: set[int] = set()
    stack: list[int] = []
    cycles: list[list[int]] = []
    counter = 0

    def strongconnect(node: int) -> None:
        nonlocal counter
        order[node] = low[node] = counter
        counter += 1
        stack.append(node)
        on_stack.add(node)
        for dep in index[node].get("depends_on") or []:
            dep = int(dep)
            if dep not in index:
                continue
            if dep not in order:
                strongconnect(dep)
                low[node] = min(low[node], low[dep])
            elif dep in on_stack:
                low[node] = min(low[node], order[dep])
        if low[node] == order[node]:
            component: list[int] = []
            while True:
                member = stack.pop()
                on_stack.discard(member)
                component.append(member)
                if member == node:
                    break
            is_self_loop = node in {int(d) for d in (index[node].get("depends_on") or [])}
            if len(component) > 1 or is_self_loop:
                cycles.append(sorted(component))

    for step_id in sorted(index):
        if step_id not in order:
            strongconnect(step_id)
    return cycles


# --------------------------------------------------------------------- wave


def compute_wave(plan: dict[str, Any], max_size: int | None = None) -> list[int]:
    """동시에 띄울 스텝 id 집합을 id 오름차순 탐욕 선택으로 고른다.

    `touches` 가 비었거나 없는 스텝은 무엇을 건드릴지 알 수 없으므로 **단독 실행**한다.
    그래서 `touches` 가 아직 없는 과거 plan.json 은 자동으로 기존 순차 동작으로 퇴화한다.
    """
    index = _steps_by_id(plan)
    selected: list[int] = []
    claimed: list[str] = []

    for step_id in ready_step_ids(plan):
        touches = _touches(index[step_id])
        if not touches:
            # 범위 미상 — 첫 후보면 혼자 돌고, 아니면 다음 웨이브로 미룬다.
            if not selected:
                return [step_id]
            continue
        if _conflicts_with_any(touches, claimed):
            continue
        selected.append(step_id)
        claimed.extend(touches)
        if max_size is not None and len(selected) >= max_size:
            break

    return selected


def wave_report(plan: dict[str, Any], max_size: int | None = None) -> dict[str, Any]:
    """오케스트레이터가 한 번에 읽을 수 있도록 wave 와 진단을 함께 담아 반환."""
    index = _steps_by_id(plan)
    ready = ready_step_ids(plan)
    wave = compute_wave(plan, max_size=max_size)
    pending = [sid for sid, s in index.items() if s.get("status") == RUNNABLE_STATUS]
    cycles = find_dependency_cycles(plan)
    return {
        "wave_ids": wave,
        "wave": [index[sid] for sid in wave],
        "ready_ids": ready,
        "pending_count": len(pending),
        # 범위 미상이라 혼자 도는 경우 — 워커를 띄우지 않고 인라인 실행해도 된다.
        "solo": len(wave) == 1 and not _touches(index[wave[0]]) if wave else False,
        # 남은 pending 이 있는데 wave 가 비면 계획이 막힌 것이다.
        "stalled": bool(pending) and not wave,
        "cycles": cycles,
    }


# --------------------------------------------------------------------- 상태 쓰기


def load_plan(path: Path | str) -> dict[str, Any]:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def atomic_write_plan(path: Path | str, plan: dict[str, Any]) -> None:
    """같은 디렉토리에 임시 파일로 쓴 뒤 rename 으로 교체한다.

    rename 은 같은 파일시스템 안에서 원자적이므로, 중간에 죽어도 plan.json 이
    반쯤 쓰인 파싱 불가 상태로 남지 않는다.
    """
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    payload = json.dumps(plan, indent=2, ensure_ascii=False) + "\n"

    handle = tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=str(target.parent),
        prefix=f".{target.name}.",
        suffix=".tmp",
        delete=False,
    )
    try:
        with handle as fh:
            fh.write(payload)
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(handle.name, target)
    except BaseException:
        Path(handle.name).unlink(missing_ok=True)
        raise


def update_step(
    path: Path | str,
    step_id: int,
    *,
    status: str | None = None,
    commit: str | None = None,
    artifacts: list[str] | None = None,
    touches: list[str] | None = None,
    error: str | None = None,
) -> dict[str, Any]:
    """스텝 한 개의 지정된 필드만 바꾸고 원자적으로 저장한다.

    `error` 가 주어지면 `error_log` 에 누적하고 `retries` 를 올린다 — 재시도 3회 규칙
    (CLAUDE.md §3.3) 의 카운터를 사람이 세지 않게 하기 위함이다.
    """
    target = Path(path)
    plan = load_plan(target)
    index = _steps_by_id(plan)
    if int(step_id) not in index:
        raise KeyError(f"plan.json 에 스텝 id {step_id} 가 없다")

    step = index[int(step_id)]
    if status is not None:
        step["status"] = status
    if commit is not None:
        step["commit"] = commit
    if artifacts is not None:
        step["artifacts"] = artifacts
    if touches is not None:
        step["touches"] = touches
    if error is not None:
        log = step.setdefault("error_log", [])
        log.append(
            {
                "at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "message": error,
            }
        )
        step["retries"] = int(step.get("retries", 0)) + 1

    atomic_write_plan(target, plan)
    return step


# --------------------------------------------------------------------- CLI


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="plan.json wave 계산기 / 단일 기록기")
    sub = parser.add_subparsers(dest="command", required=True)

    wave = sub.add_parser("wave", help="동시에 띄울 수 있는 스텝 집합을 JSON 으로 출력")
    wave.add_argument("--plan", default=str(DEFAULT_PLAN_PATH))
    wave.add_argument(
        "--max",
        type=int,
        default=None,
        help="한 웨이브의 최대 스텝 수 (동시 실행 상한에 맞춘다)",
    )

    validate = sub.add_parser("validate", help="의존성 순환·누락 의존성·touches 누락 점검")
    validate.add_argument("--plan", default=str(DEFAULT_PLAN_PATH))

    setter = sub.add_parser("set", help="스텝 한 개의 상태를 원자적으로 갱신")
    setter.add_argument("step_id", type=int)
    setter.add_argument("--plan", default=str(DEFAULT_PLAN_PATH))
    setter.add_argument("--status")
    setter.add_argument("--commit")
    setter.add_argument("--artifact", action="append", dest="artifacts")
    setter.add_argument("--touch", action="append", dest="touches")
    setter.add_argument("--error")

    return parser


def _validate(plan: dict[str, Any]) -> dict[str, Any]:
    index = _steps_by_id(plan)
    missing_deps: list[dict[str, Any]] = []
    missing_touches: list[int] = []
    for step_id in sorted(index):
        step = index[step_id]
        for dep in step.get("depends_on") or []:
            if int(dep) not in index:
                missing_deps.append({"step": step_id, "missing_dependency": int(dep)})
        if not _touches(step):
            missing_touches.append(step_id)
    cycles = find_dependency_cycles(plan)
    return {
        "ok": not (missing_deps or cycles),
        "cycles": cycles,
        "missing_dependencies": missing_deps,
        # touches 가 없어도 동작은 한다 — 다만 그 스텝은 병렬화되지 않는다.
        "steps_without_touches": missing_touches,
    }


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    plan_path = Path(args.plan)

    if not plan_path.exists():
        print(f"plan.json 을 찾을 수 없다: {plan_path}", file=sys.stderr)
        return 2

    if args.command == "wave":
        report = wave_report(load_plan(plan_path), max_size=args.max)
        print(json.dumps(report, indent=2, ensure_ascii=False))
        return 1 if report["stalled"] else 0

    if args.command == "validate":
        result = _validate(load_plan(plan_path))
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return 0 if result["ok"] else 1

    if args.command == "set":
        step = update_step(
            plan_path,
            args.step_id,
            status=args.status,
            commit=args.commit,
            artifacts=args.artifacts,
            touches=args.touches,
            error=args.error,
        )
        print(json.dumps(step, indent=2, ensure_ascii=False))
        return 0

    return 2


if __name__ == "__main__":
    raise SystemExit(main())

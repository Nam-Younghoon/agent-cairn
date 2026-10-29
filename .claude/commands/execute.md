---
description: plan.json 의 다음 스텝을 실행 (TDD → 구현 → lint/build → 커밋)
argument-hint: [next | all | parallel | <stepId>]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent, Skill
---

# /execute — plan.json 기반 스텝 실행

`$ARGUMENTS` 에 따라 동작:
- `next` (기본): 다음 실행 가능한 스텝 **한 개**만 수행
- `<stepId>`: 특정 스텝 id 수행
- `all`: 차단 상태가 될 때까지 **웨이브 단위**로 연속 수행
- `parallel`: 다음 웨이브 **한 번**만 병렬 수행하고 멈춘다 (병렬 동작 확인용)

> **모델 선택 가이드**: `all` 처럼 여러 스텝을 연속 자율 실행할 때의 모델 전환 권장안은
> `.claude/VERSION_NOTES.md` 를 참조한다. 모델 라인업은 자주 바뀌므로 커맨드 본문에 고정하지 않는다.

## 선조건 확인
1. `__docs/plan.json` 존재 확인. 없으면 `/plan-steps` 을 먼저 돌리도록 안내.
2. `status` 가 `planning` 이면 `in_progress` 로 전환하고 그대로 진행.
3. 작업 트리가 clean 한지 확인한다. 병렬 모드는 커밋되지 않은 변경이 있으면 시작하지 않는다 —
   워커가 고정할 베이스 커밋이 불분명해지기 때문이다.

---

## 실행 단위 — 웨이브

`/execute` 는 스텝을 **웨이브** 단위로 돈다. 웨이브는 "지금 동시에 띄워도 안전한 스텝 집합" 이다.

- **ready** = `status` 가 `pending` 이고 `depends_on` 이 전부 `completed`
- **wave** = ready 중 `touches` 가 서로 겹치지 않는 최대 집합

이 판정은 추론하지 말고 **반드시 스크립트로 계산한다**. 의존성·경로 충돌 판정을 눈으로 하면
틀려도 조용히 지나가고, 두 워커가 같은 파일을 밟는 사고로만 드러난다 (ADR-022).

```bash
python3 scripts/plan_waves.py wave --plan __docs/plan.json --max 4
```

출력 해석:

| 키 | 의미 | 대응 |
| --- | --- | --- |
| `wave_ids` | 이번에 띄울 스텝 id | 비어 있지 않으면 실행 |
| `solo` | `true` 면 `touches` 미상이라 단독 실행 | 워커를 띄우지 말고 **메인 세션에서 인라인 실행** |
| `stalled` | `pending` 이 남았는데 wave 가 빈 상태 | 계획이 막힌 것이다. `cycles` 를 보고 사용자에게 보고 후 중단 |
| `cycles` | 의존성 순환 | 사용자에게 보고. 자동 수정하지 않는다 |

`--max` 는 한 웨이브의 상한이다. 기본 4 에서 시작하고, 게이트(빌드·테스트)가 무거운
프로젝트면 낮춘다.

> `python3` 가 없는 환경이면 **병렬 모드를 포기하고 `next` 를 반복한다**. 추론으로 웨이브를
> 흉내내지 않는다 — 틀린 병렬 실행이 순차 실행보다 훨씬 비싸다.

---

## A. 웨이브 실행 (병렬)

`wave_ids` 가 2개 이상이고 `solo` 가 `false` 일 때의 경로다.

### A-1. 베이스 커밋 고정
현재 HEAD 의 전체 SHA 를 구한다. 이것이 **이번 웨이브 모든 워커의 베이스**다.

```bash
git rev-parse HEAD
```

> 워커 워크트리는 **저장소 기본 브랜치의 tip** 에서 시작하지, 지금 작업 브랜치의 HEAD 에서
> 시작하지 않는다. 그냥 두면 워커가 앞선 스텝 커밋이 없는 베이스에서 작업해 빌드가 깨진다.
> 게다가 그 기본 브랜치는 실행 중에 움직일 수 있다. 그래서 베이스를 **명시적으로 고정**한다 (ADR-022).

### A-2. 상태 전환
웨이브의 각 스텝을 `in_progress` 로 바꾼다. `plan.json` 쓰기는 **항상 이 스크립트로만** 한다.

```bash
python3 scripts/plan_waves.py set <id> --status in_progress --plan __docs/plan.json
```

### A-3. 워커 기동 — 한 메시지에 전부
웨이브의 각 스텝마다 `Agent` 를 **하나의 메시지 안에서 동시에** 호출한다
(`subagent_type: "general-purpose"`, `isolation: "worktree"`). 메시지를 나눠 보내면 직렬이 된다.

워커 워크트리에는 `__docs/` 가 **존재하지 않는다** (gitignore 대상). 즉 워커는 `plan.json` 을
읽을 수도 쓸 수도 없다 — 상태 단일 쓰기가 규칙이 아니라 물리적 사실이다. 그러므로 스텝 명세를
**프롬프트에 인라인으로 실어 보낸다**.

각 워커 프롬프트에 반드시 포함할 것:

1. **베이스 고정 지시** — 첫 동작으로 아래를 실행하게 한다. `<BASE_SHA>` 는 A-1 의 값.
   ```
   git branch --show-current   (이 값을 BRANCH 라 하자)
   git switch -C <BRANCH> <BASE_SHA>
   ```
2. **스텝 명세** — `title`, `description`, `touches`, 완료 기준. 관련 PRD/ADR 발췌.
3. **범위 제약** — `touches` 에 선언된 경로 **밖은 수정 금지**. 다른 워커가 그 파일을 동시에 고치고 있다.
4. **파이프라인** — 아래 C~G 를 워커 안에서 수행하고, 스텝당 **커밋 1개**로 끝낸다.
5. **금지** — `__docs/` 를 만들지 않는다. push 하지 않는다. 다른 브랜치로 전환하지 않는다.
6. **셸 사용법** — 워크트리 격리 세션은 **복합 셸 명령을 거부**한다. 명령을 `&&` 로 체이닝하지
   말고 한 줄에 하나씩 실행하라고 지시한다.
7. **반환 형식** — 산문 보고 대신 아래만 반환하게 한다.
   ```
   STEP_ID=<id>
   STATUS=<completed|error|blocked>
   COMMIT=<full sha 또는 none>
   BRANCH=<워커 브랜치 이름>
   ARTIFACTS=<수정한 파일 경로들>
   ERROR=<실패 시 원인 요약, 아니면 none>
   ```

### A-4. 회수 — 워커 커밋을 작업 브랜치로
모든 워커가 끝나면, **보고를 믿지 말고 실제 커밋을 확인한 뒤** 하나씩 가져온다.
워커 보고는 모델 출력이지 검증된 사실이 아니다.

```bash
git log --oneline <BASE_SHA>..<워커 브랜치>
git cherry-pick <BASE_SHA>..<워커 브랜치>
```

- 모든 워커가 같은 베이스 위에 있으므로 **cherry-pick 으로 통일**한다. 선형 히스토리가 유지된다.
- `touches` 가 겹치지 않으므로 충돌은 원칙적으로 나지 않는다.
  **충돌이 났다면 `touches` 선언이 틀렸다는 뜻이다.** 자동으로 봉합하지 말고
  `git cherry-pick --abort` 후 해당 스텝을 `error` 로 기록하고 사용자에게 보고한다.

### A-5. 상태 기록
회수에 성공한 스텝만 `completed` 로 기록한다.

```bash
python3 scripts/plan_waves.py set <id> --status completed --commit <sha> --artifact <path> --plan __docs/plan.json
```

실패한 스텝은 `--status error --error "<원인>"` 으로 기록한다. `retries` 는 스크립트가 올린다.

### A-6. 뒷정리
커밋을 남긴 워커의 워크트리와 브랜치는 **자동으로 정리되지 않는다** (ADR-022 실측 #3).
회수가 끝난 뒤 직접 제거한다.

```bash
git worktree remove --force .claude/worktrees/agent-<agentId>
git branch -D worktree-agent-<agentId>
```

### A-7. 다음 웨이브
- `all`: 웨이브를 다시 계산해 반복. 에러/블록이 하나라도 생기면 멈춘다.
- `parallel`: 한 웨이브만 돌고 종료.

---

## B. 단일 스텝 실행 (순차)

`next`, `<stepId>`, 또는 웨이브가 1개이거나 `solo` 인 경우의 경로다.
워커를 띄우지 않고 **메인 세션에서 직접** 수행한다. 워크트리 왕복 비용이 이득보다 크다.

### C. 컨텍스트 수집
- 빌트인 `Explore` 서브에이전트를 병렬로 호출하여 스텝이 건드릴 기존 파일·인터페이스·테스트를 파악한다.
- 관련 `__docs/ARCHITECTURE.md`, `__docs/ADR.md` 가 있으면 **먼저 읽는다**.

### D. TDD — 실패 테스트 작성
- `tdd-tester` 서브에이전트를 호출해 스텝의 완료 기준에 해당하는 테스트를 먼저 작성하게 한다.
- 테스트가 **반드시 실패**하는 상태임을 확인. 통과하면 설계가 의미 없음.

### E. 구현
- 테스트를 통과시키는 최소한의 코드를 작성한다.
- 과도한 추상화·주변 리팩터링 금지. `touches` 에 선언한 범위를 넘지 않는다.

### F. 검증
- Node (Express/Next.js): `npm run build && npm run lint && npm run test` (또는 `vitest`/`jest`)
- NestJS: `npm run build && npm run lint && npm run test`
- Flutter: `dart format . && flutter analyze && flutter test`
- SpringBoot: `./gradlew build test` (Spotless 도입 시 `./gradlew spotlessCheck` 추가)
- 하나라도 실패하면 재시도 루프로 진입.

### F-2. 재시도 루프 (자동)
- 동일 스텝의 실패는 **최대 3회**까지 자동 재시도한다.
- 재시도 시 이전 실패 메시지를 `error_log` 에 append 하고(`set --error`), 다음 시도의 추론에 활용.
- 3회 이후에도 실패하면 스텝을 `error` 상태로 두고 사용자에게 보고 → 중단.
- 외부 요인(API 키 누락, 네트워크 불가, 권한 부족 등) 은 **재시도하지 않고** 즉시 `blocked` 로 기록하고 사용자 개입 요청.

### G. 리뷰 게이트 (2단)
일반 품질과 하네스 규정을 **서로 다른 주체**가 본다. 중복 리뷰를 피하기 위한 분리다 (ADR-020).

1. **`/code-review`** (Claude Code 빌트인 스킬) — 버그·중복·에러 처리·가독성 등 일반 품질.
   변경 규모가 작으면 기본 effort, 핵심 로직이면 `high` 로 올린다.
2. **`pre-commit-reviewer`** 서브에이전트 — 네이티브가 알 수 없는 **하네스 규정만** 검증
   (시크릿/`.env.example` 동반 갱신, TDD 준수, `any` 금지, 스텝 범위 이탈).
   1번 결과 요약을 함께 전달해 같은 지적을 반복하지 않게 한다.

둘 중 하나라도 `BLOCK` 이면 F-2 로 돌아가 동일 사이클 반복 (재시도 카운트 공유).

> `/code-review` 를 쓸 수 없는 환경이면 `.claude/VERSION_NOTES.md` §1 의 폴백(`pre-commit-reviewer` 에 일반 품질 항목 한시 복원)을 따른다.

워커가 이 단계를 수행할 때는 `/code-review` 대신 **워커 자신이 변경분을 재검토**한다 —
서브에이전트 안에서 스킬 중첩 호출은 비용 대비 이득이 낮다. `pre-commit-reviewer` 호출은
회수 후 오케스트레이터가 **웨이브 전체 diff** 에 대해 한 번 수행한다.

### H. 커밋
- 커밋 메시지: `<type>: <스텝 제목>` + 본문에 "왜" 와 주요 변경.
- 커밋 SHA 를 plan.json 의 해당 스텝 `commit` 필드에 기록 (`set --commit`).
- `artifacts` 에 주요 변경 파일 목록 기록 (`set --artifact`).
- `status` 를 `completed` 로 전환.

---

## 종료 후 보고
아래 요약을 사용자에게 제시.

```
## 이번 /execute 결과
- 실행한 웨이브: [<id>, <id>] (병렬) 또는 <id> (단독)
- 스텝별 상태: <id>=completed(<sha>) / <id>=error(<원인>)
- 회수 방식: cherry-pick / 인라인 커밋
- 남은 pending: <n>
- 다음 웨이브 후보: [<id>, ...]
```

## 금지
- plan.json 을 건너뛰고 즉흥적으로 다른 파일을 수정하지 않는다.
- **`plan.json` 을 직접 편집하지 않는다.** 모든 쓰기는 `plan_waves.py set` 을 통한다.
  워커는 쓰기는커녕 읽지도 못한다 — 그 상태를 유지한다.
- 웨이브를 추론으로 계산하지 않는다. 스크립트 출력만 신뢰한다.
- 워커 보고만 믿고 `completed` 로 기록하지 않는다. 실제 커밋을 확인한다.
- 실패 테스트를 "약화" 해서 통과시키지 않는다.
- 하나의 스텝에서 여러 기능을 한꺼번에 처리하지 않는다.
- push 는 이 커맨드에서 하지 않는다. `/ship` 이 담당.

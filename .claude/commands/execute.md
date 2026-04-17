---
description: plan.json 의 다음 스텝을 실행 (TDD → 구현 → lint/build → 커밋)
argument-hint: [next | all | <stepId>]
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Agent
---

# /execute — plan.json 기반 스텝 실행

`$ARGUMENTS` 에 따라 동작:
- `next` (기본): 다음 실행 가능한 스텝 **한 개**만 수행
- `<stepId>`: 특정 스텝 id 수행
- `all`: 차단 상태가 될 때까지 연속 수행

## 선조건 확인
1. `__docs/plan.json` 존재 확인. 없으면 `/plan` 을 먼저 돌리도록 안내.
2. `status` 가 `planning` 이면 `in_progress` 로 전환하고 그대로 진행.
3. 대상 스텝 결정:
   - `next`: `status == "pending"` 이고 `depends_on` 의 모든 스텝이 `completed` 인 것 중 id 가 가장 작은 것.
   - `all`: 같은 조건으로 반복. 에러/블록 발생 시 멈춤.

## 실행 파이프라인 (각 스텝)

### A. 스텝 로드
- plan.json 의 해당 스텝 `status` 를 `in_progress` 로 변경하고 저장.

### B. 컨텍스트 수집 (병렬)
- `parallel-explorer` 서브에이전트를 병렬로 호출하여 스텝이 건드릴 기존 파일·인터페이스·테스트를 빠르게 파악한다.
- 관련 `__docs/ARCHITECTURE.md`, `__docs/ADR.md` 가 있으면 **먼저 읽는다**.

### C. TDD — 실패 테스트 작성
- `tdd-tester` 서브에이전트를 호출해 스텝의 완료 기준에 해당하는 테스트를 먼저 작성하게 한다.
- 테스트가 **반드시 실패**하는 상태임을 확인. 통과하면 설계가 의미 없음.

### D. 구현
- 테스트를 통과시키는 최소한의 코드를 작성한다.
- 과도한 추상화·주변 리팩터링 금지. 스텝 범위를 넘지 않는다.

### E. 검증
- Node: `npm run build && npm run lint && npm run test` (또는 `vitest`/`jest`)
- Flutter: `dart format . && flutter analyze && flutter test`
- 하나라도 실패하면 재시도 루프로 진입.

### F. 재시도 루프 (자동)
- 동일 스텝의 실패는 **최대 3회**까지 자동 재시도한다.
- 재시도 시 이전 실패 메시지를 `error_log` 에 append 하고, 다음 시도의 추론에 활용.
- 3회 이후에도 실패하면 스텝을 `error` 상태로 두고 사용자에게 보고 → 중단.
- 외부 요인(API 키 누락, 네트워크 불가, 권한 부족 등) 은 **재시도하지 않고** 즉시 `blocked` 로 기록하고 사용자 개입 요청.

### G. 리뷰 게이트
- `pre-commit-reviewer` 서브에이전트를 호출해 변경분을 검토.
- `BLOCK` 판정 시 F 로 돌아가 동일 사이클 반복 (재시도 카운트 공유).

### H. 커밋
- 커밋 메시지: `<type>: <스텝 제목>` + 본문에 "왜" 와 주요 변경.
- 커밋 SHA 를 plan.json 의 해당 스텝 `commit` 필드에 기록.
- `artifacts` 에 주요 변경 파일 목록 기록.
- `status` 를 `completed` 로 전환.

### I. 다음 스텝
- 인자가 `all` 이면 선조건 재평가 후 반복.
- 아니면 여기서 종료하고 요약을 사용자에게 보고.

## 종료 후 보고
아래 요약을 사용자에게 제시.

```
## 이번 /execute 결과
- 실행한 스텝: <id> <title>
- 상태: completed / error / blocked
- 커밋: <sha>
- 다음 후보: <id> <title>
```

## 금지
- plan.json 을 건너뛰고 즉흥적으로 다른 파일을 수정하지 않는다.
- 실패 테스트를 "약화" 해서 통과시키지 않는다.
- 하나의 스텝에서 여러 기능을 한꺼번에 처리하지 않는다.
- push 는 이 커맨드에서 하지 않는다. `/ship` 이 담당.

# /execute — plan.json 기반 스텝 실행

이 프롬프트는 Codex CLI 에서 `/execute [next|all|parallel|<stepId>]` 호출 시 Claude Code 의 동명 슬래시 커맨드와 **동일한 흐름**으로 동작합니다. 슬래시 바인딩이 미확정인 경우 `@.codex/prompts/execute.md 의 절차를 따라 next|all|<id> 로 진행해주세요` 같이 파일 참조로 사용하세요.

인자(`$ARGUMENTS`):
- `next` (기본): 다음 실행 가능한 스텝 **한 개**만 수행
- `<stepId>`: 특정 스텝 id 수행
- `all`: 차단 상태가 될 때까지 **웨이브 단위**로 연속 수행
- `parallel`: 다음 웨이브 **한 번**만 병렬 수행하고 멈춘다

> **Claude 판과의 비대칭 (의도된 것)**: Claude Code 에는 `Agent(isolation: "worktree")` 로
> 워커를 띄우는 네이티브 수단이 있지만 Codex 에는 없다. 그래서 병렬 실행은
> `## 인라인 가이드 — 웨이브 병렬 실행 (셸 fan-out)` 의 `git worktree` + `codex exec`
> 경로로 수행한다. 이 섹션을 Claude 판과 1:1 로 맞추려 하지 말 것.

## 선조건 확인
1. `__docs/plan.json` 존재 확인. 없으면 `/plan-steps` 을 먼저 돌리도록 안내.
2. `status` 가 `planning` 이면 `in_progress` 로 전환하고 그대로 진행.
3. 작업 트리가 clean 한지 확인. 병렬 모드는 커밋되지 않은 변경이 있으면 시작하지 않는다 —
   워커가 고정할 베이스 커밋이 불분명해지기 때문이다.
4. 대상 결정:
   - `next` / `<stepId>`: 아래 **실행 파이프라인** 을 그 스텝 하나에 대해 수행.
   - `all` / `parallel`: 아래 **웨이브 계산** 으로 집합을 구한 뒤 인라인 가이드로 병렬 수행.

## 웨이브 계산

`/execute` 의 실행 단위는 **웨이브** — "지금 동시에 띄워도 안전한 스텝 집합" 이다.

- **ready** = `status` 가 `pending` 이고 `depends_on` 이 전부 `completed`
- **wave** = ready 중 `touches` 가 서로 겹치지 않는 최대 집합

이 판정은 추론하지 말고 **반드시 스크립트로 계산한다**. 의존성·경로 충돌 판정을 눈으로 하면
틀려도 조용히 지나가고, 두 워커가 같은 파일을 밟는 사고로만 드러난다 (ADR-022).

```bash
python3 scripts/plan_waves.py wave --plan __docs/plan.json --max 3
```

| 키 | 의미 | 대응 |
| --- | --- | --- |
| `wave_ids` | 이번에 띄울 스텝 id | 2개 이상이면 병렬, 1개면 인라인 순차 |
| `solo` | `true` 면 `touches` 미상이라 단독 실행 | 워커를 띄우지 말고 이 세션에서 직접 수행 |
| `stalled` | `pending` 이 남았는데 wave 가 빈 상태 | 계획이 막힌 것이다. `cycles` 를 보고 사용자에게 보고 후 중단 |
| `cycles` | 의존성 순환 | 사용자에게 보고. 자동 수정하지 않는다 |

> **`scripts/plan_waves.py` 나 `python3` 가 없으면 병렬 모드를 포기하고 `next` 를 반복한다.**
> 추론으로 웨이브를 흉내내지 않는다 — 틀린 병렬 실행이 순차 실행보다 훨씬 비싸다.

`wave_ids` 가 2개 이상이면 **아래 `## 인라인 가이드 — 웨이브 병렬 실행 (셸 fan-out)` 절차를
직접 수행**한다. 1개이거나 `solo` 면 아래 실행 파이프라인을 이 세션에서 그대로 수행한다.

`plan.json` 쓰기는 **항상** 아래로만 한다. 손으로 편집하지 않는다.

```bash
python3 scripts/plan_waves.py set <id> --status <상태> [--commit <sha>] [--artifact <path>] [--error "<원인>"] --plan __docs/plan.json
```

## 실행 파이프라인 (각 스텝)

### A. 스텝 로드
- 해당 스텝 `status` 를 `in_progress` 로 변경 (`set --status in_progress`).

### B. 컨텍스트 수집
- **아래 `## 인라인 가이드 — 병렬 탐색` 절차를 직접 수행**하여 스텝이 건드릴 기존 파일·인터페이스·테스트를 빠르게 파악한다.
- 관련 `__docs/ARCHITECTURE.md`, `__docs/ADR.md` 가 있으면 **먼저 읽는다**.

### C. TDD — 실패 테스트 작성
- **아래 `## 인라인 가이드 — 실패 테스트 선 작성` 절차를 직접 수행**하여 스텝의 완료 기준에 해당하는 테스트를 먼저 작성한다.
- 테스트가 **반드시 실패**하는 상태임을 확인. 통과하면 설계가 의미 없음.

### D. 구현
- 테스트를 통과시키는 최소한의 코드를 작성한다.
- 과도한 추상화·주변 리팩터링 금지. 스텝 범위를 넘지 않는다.

### E. 검증
- Node (Express/Next.js): `npm run build && npm run lint && npm run test` (또는 `vitest`/`jest`)
- NestJS: `npm run build && npm run lint && npm run test`
- Flutter: `dart format . && flutter analyze && flutter test`
- SpringBoot: `./gradlew build test` (Spotless 도입 시 `./gradlew spotlessCheck` 추가)
- 하나라도 실패하면 재시도 루프로 진입.

### F. 재시도 루프 (자동)
- 동일 스텝의 실패는 **최대 3회**까지 자동 재시도한다.
- 재시도 시 이전 실패 메시지를 `error_log` 에 append 하고, 다음 시도의 추론에 활용.
- 3회 이후에도 실패하면 스텝을 `error` 상태로 두고 사용자에게 보고 → 중단.
- 외부 요인(API 키 누락, 네트워크 불가, 권한 부족 등) 은 **재시도하지 않고** 즉시 `blocked` 로 기록하고 사용자 개입 요청.

### G. 리뷰 게이트
- **아래 `## 인라인 가이드 — 커밋 전 리뷰` 절차를 직접 수행**하여 변경분을 검토한다.
- `BLOCK` 판정 시 F 로 돌아가 동일 사이클 반복 (재시도 카운트 공유).

### H. 커밋
- 커밋 메시지: `<type>: <스텝 제목>` + 본문에 "왜" 와 주요 변경.
- 커밋 SHA 와 변경 파일을 기록 (`set --commit <sha> --artifact <path>`).
- `status` 를 `completed` 로 전환.

### I. 다음 스텝
- 인자가 `all` 이면 웨이브를 재계산 후 반복.
- 아니면 여기서 종료하고 요약을 사용자에게 보고.

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
- 웨이브를 추론으로 계산하지 않는다. 스크립트 출력만 신뢰한다.
- 워커 보고만 믿고 `completed` 로 기록하지 않는다. 실제 커밋을 확인한다.
- 실패 테스트를 "약화" 해서 통과시키지 않는다.
- 하나의 스텝에서 여러 기능을 한꺼번에 처리하지 않는다.
- push 는 이 커맨드에서 하지 않는다. `/ship` 이 담당.

---

## 인라인 가이드 — 병렬 탐색

Claude 세션의 빌트인 `Explore` 에이전트를 Codex 세션에서 대체하는 절차. **사실만 수집**, 추측·제안 금지.

### 절차
1. 질문을 분해해 **독립적인 검색 쿼리 목록**을 만든다.
2. `glob`/`grep`/`rg`/`fd` 를 **병렬로 실행**한다. 한 파일 통째 읽기 전 패턴 검색 우선.
3. 확인된 사실만 `path:line` 형식으로 기록.

### 출력 포맷
```
## 핵심 답
<2~3문장 요약>

## 근거
- <path>:<line> — <인용 또는 요약>
```

### 금지
- 탐색 단계에서 코드 수정·파일 생성·장황한 배경 설명
- 탐색 진행 중 사용자에게 질문 (불명확한 부분은 탐색 종료 후 메인 흐름에서 처리)

---

## 인라인 가이드 — 실패 테스트 선 작성

Claude 의 `tdd-tester` 에이전트를 Codex 세션에서 대체하는 절차. **테스트만 작성**, 구현체는 다음 단계(D)에서 작성.

### 작업 순서
1. `__docs/PRD.md` 와 관련 `__docs/ARCHITECTURE.md` 를 **먼저 읽는다**. 없으면 사용자에게 요구사항을 질문.
2. 기존 테스트 규약을 확인한다.
   - Node: `package.json` devDependencies 에서 `vitest` 또는 `jest` 확인 → 둘 다 없으면 `vitest` 기본.
   - Flutter: `test/` 디렉토리와 `pubspec.yaml` 의 `flutter_test` 확인.
3. 완료 기준(PRD 체크리스트) 항목별로 테스트 케이스를 설계한다.
   - 성공 경로(golden path) + 경계값 + 실패 경로를 각각 분리.
   - 이름은 "무엇을/어떤 조건에서/어떻게 되어야 하는가" 가 드러나도록.
4. 테스트 파일만 작성한다. **구현체는 건드리지 않는다**. 필요 최소한의 타입/인터페이스만 정의.
5. 테스트를 실행해 **반드시 실패**하는지 확인한다. 실패 이유가 "존재하지 않는 모듈" 또는 "의도한 단언 미충족" 중 하나여야 한다.

### 출력 포맷 (자신에게 기록용)
```
## 작성한 테스트 파일
- <경로>: <설명>

## 실행 명령
<예: npx vitest run path/to/test>

## 현재 실패 상태
- <테스트 이름>: <실패 이유>

## 구현 시 주의점
- <PRD 와 테스트에서 도출된 제약>
```

### 금지
- 이 단계에서 구현체(소스 코드) 수정
- 테스트가 통과하도록 단언 약화
- 목(mock) 남용 — 외부 I/O 만 목 대체
- Node 테스트에서 `any` 타입 사용

---

## 인라인 가이드 — 커밋 전 리뷰

Claude 의 `pre-commit-reviewer` 에이전트를 Codex 세션에서 대체하는 절차. **변경된 파일만** 검토. PASS 판정 남발 금지.

> **Claude 쪽과 1:1 동기화하지 말 것.** Claude 세션은 `/code-review` 빌트인 스킬이 일반 품질을,
> `pre-commit-reviewer` 서브에이전트가 하네스 규정을 나눠 본다(ADR-020). Codex 에는 대응 네이티브
> 스킬이 없으므로 **이 인라인 가이드가 일반 품질 + 하네스 규정을 모두** 담당한다. 항목을 덜어내지 않는다.

### 점검 항목

**A. 하네스 규정**
1. `any` 타입이 TypeScript 변경분에 새로 들어갔는가?
2. 하드코딩된 시크릿/토큰/URL/DB 자격증명이 있는가? — Codex 세션은 `.env`·시크릿 차단 훅이 없으므로 **특히 엄격하게 본다**.
3. 새 환경변수를 추가했다면 `.env.example` 도 함께 갱신되었는가?
4. 의미 불분명한 줄임말 변수/함수명이 있는가?
5. 테스트 없이 로직이 추가되었는가? (테스트 파일 변경이 함께 있어야 함)
6. `__docs/` 가 `.gitignore` 에 포함되어 있는가?

**B. 린트/빌드**
1. Node (Express/Next.js): `npm run lint` 및 `npm run build` 실행. 실패 시 즉시 BLOCK.
2. NestJS: `npm run build && npm run lint && npm run test` 실행. 실패 시 즉시 BLOCK.
3. Flutter: `flutter analyze` 실행. 경고 존재 시 BLOCK.
4. SpringBoot: `./gradlew build test` 실행. Spotless 도입 시 `./gradlew spotlessCheck` 추가. 실패 시 즉시 BLOCK.
5. 해당 스크립트가 없으면 이유와 함께 건너뛰었음을 보고.

**C. 기본 품질**
1. 같은 로직이 3회 이상 복붙되었는가? (과도한 추상화는 금지, 단순 중복만 지적)
2. 에러 처리 누락 또는 과도한 try/catch 가 있는가?
3. 주석이 "무엇" 을 설명하는 불필요 주석인가? ("왜" 만 허용)

### 출력 포맷
```
## 판정
PASS | BLOCK

## BLOCK 사유 (있을 때만)
- [A-1] `src/foo.ts:42` any 사용
- [B-2] flutter analyze 경고 3건

## 경고 (통과는 하되 확인 권장)
- ...

## 실행한 명령과 결과
- npm run lint: ✅ exit 0
- npm run build: ❌ exit 1 (상세 로그 요약)
```

### 금지
- 스타일 취향 지적 (규정·품질 이슈만)
- 리뷰 단계에서 직접 수정 — 발견한 사항은 구현 단계로 되돌려 처리

---

## 인라인 가이드 — 웨이브 병렬 실행 (셸 fan-out)

Claude Code 는 `Agent(isolation: "worktree")` 로 워커를 띄우지만 Codex 에는 대응물이 없다.
그래서 **워크트리를 직접 만들고 헤드리스 세션을 백그라운드로 띄우는** 경로를 쓴다.
비대칭은 의도된 것이다 (ADR-022).

### 전제
- `git worktree` 가 쓸 수 있을 것. `.git` 은 워크트리 간에 공유되므로 워커 커밋은
  fetch/push 없이 메인 저장소에서 바로 보인다.
- 작업 트리가 clean 할 것.
- 실패하면 **조용히 순차로 되돌아간다**. 병렬은 최적화일 뿐이고, 어설픈 병렬은 순차보다 비싸다.

### 절차

**1. 베이스 커밋 고정**

```bash
git rev-parse HEAD
```

이 전체 SHA 가 이번 웨이브 모든 워커의 베이스다. 워커 워크트리를 만들 때 **명시적으로
이 SHA 를 지정**한다. 기본값에 맡기면 기본 브랜치 tip 에서 시작해, 앞선 스텝 커밋이 없는
베이스 위에서 작업하게 된다.

**2. 웨이브의 스텝마다 워크트리 생성**

```bash
git worktree add .worktrees/step-<id> -b exec/step-<id> <BASE_SHA>
```

`.worktrees/` 는 `.gitignore` 대상이다. `__docs/` 도 gitignore 대상이므로 **워커 워크트리에는
`plan.json` 이 아예 없다** — 상태 단일 쓰기가 규칙이 아니라 물리적 사실이 된다.
따라서 스텝 명세는 워커 프롬프트에 **인라인으로 실어 보낸다**.

**3. 상태 전환 (오케스트레이터만)**

```bash
python3 scripts/plan_waves.py set <id> --status in_progress --plan __docs/plan.json
```

**4. 헤드리스 워커 기동 — 백그라운드로 동시에**

워크트리마다 하나씩, **백그라운드로 한꺼번에** 띄운다. 순서대로 기다리면 병렬이 아니다.

```bash
cd .worktrees/step-<id> && codex exec "<워커 프롬프트>" > ../../.worktrees/step-<id>.log 2>&1 &
```

워커 프롬프트에 반드시 포함할 것:

1. **스텝 명세** — `title`, `description`, `touches`, 완료 기준. 관련 PRD/ADR 발췌.
2. **범위 제약** — `touches` 에 선언된 경로 **밖은 수정 금지**. 다른 워커가 그 파일을 동시에 고치고 있다.
3. **파이프라인** — 본 프롬프트의 C~H 를 수행하고 스텝당 **커밋 1개**로 끝낼 것.
4. **금지** — `__docs/` 를 만들지 않는다. push 하지 않는다. 다른 브랜치로 전환하지 않는다.
   `plan.json` 을 찾지 않는다 (없는 것이 정상이다).
5. **반환 형식** — 로그 마지막 줄에 아래를 출력하게 한다.
   ```
   STEP_ID=<id> STATUS=<completed|error|blocked> COMMIT=<full sha 또는 none>
   ```

**5. 대기**

```bash
wait
```

**6. 회수 — 워커 커밋을 작업 브랜치로**

워커 로그는 모델 출력이지 검증된 사실이 아니다. **로그를 믿지 말고 실제 커밋을 확인**한 뒤
가져온다.

```bash
git log --oneline <BASE_SHA>..exec/step-<id>
git cherry-pick <BASE_SHA>..exec/step-<id>
```

- 모든 워커가 같은 베이스 위에 있으므로 **cherry-pick 으로 통일**한다. 선형 히스토리가 유지된다.
- `touches` 가 겹치지 않으므로 충돌은 원칙적으로 나지 않는다.
  **충돌이 났다면 `touches` 선언이 틀렸다는 뜻이다.** 자동으로 봉합하지 말고
  `git cherry-pick --abort` 후 해당 스텝을 `error` 로 기록하고 사용자에게 보고한다.

**7. 상태 기록 (오케스트레이터만)**

회수에 성공한 스텝만 `completed` 로 기록한다.

```bash
python3 scripts/plan_waves.py set <id> --status completed --commit <sha> --artifact <path> --plan __docs/plan.json
```

실패한 스텝은 `--status error --error "<원인>"` 으로 기록한다. `retries` 는 스크립트가 올린다.

**8. 뒷정리**

```bash
git worktree remove --force .worktrees/step-<id>
git branch -D exec/step-<id>
```

### 금지
- 워커를 전경(foreground)으로 하나씩 돌리지 않는다. 그건 병렬이 아니다.
- 워커에게 `plan.json` 을 복사해 주지 않는다. 사본이 갈라지면 상태가 깨진다.
- 워커 로그의 자기보고만으로 `completed` 를 기록하지 않는다.
- 워크트리를 남기지 않는다. 커밋이 있는 워크트리는 자동 정리되지 않는다.

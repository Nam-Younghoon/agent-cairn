# /ship — 출고 (dev 동기화 → push → PR)

이 프롬프트는 Codex CLI 에서 `/ship` 호출 시 Claude Code 의 동명 슬래시 커맨드와 **동일한 흐름**으로 동작합니다. 슬래시 바인딩이 미확정인 경우 `@.codex/prompts/ship.md 의 절차를 따라 진행해주세요` 같이 파일 참조로 사용하세요.

인자: 없음.

모든 스텝이 `completed` 인 상태에서 호출. 미완료가 있으면 중단.

## 1단계. 선조건 검증
- `__docs/plan.json` 의 모든 스텝이 `completed`. 아니면 어떤 스텝이 남아있는지 알려주고 중단.
- working tree 가 clean. 아니면 사용자에게 커밋되지 않은 변경을 먼저 처리하도록 요청.
- 현재 브랜치가 `plan.branch` 와 동일.

## 2단계. 최종 검증
- 전체 테스트·린트·빌드를 한 번 더 돌린다 (각 스텝에서 통과했어도 종합적으로 한 번 더).
- 실패 시 **아래 `## 인라인 가이드 — 커밋 전 리뷰` 절차를 수행**하여 원인을 요약하고 사용자에게 보고 후 중단.

## 3단계. dev 최신화
```
git fetch origin
```
- `dev` 브랜치 최신 커밋을 확인.
- `origin/dev` 와 현재 브랜치의 divergence 를 `git log --left-right --oneline origin/dev...HEAD` 로 확인.

### 충돌 없을 때
- `git rebase origin/dev` (또는 팀 합의에 따라 merge).
- 테스트·린트·빌드 재실행.

### 충돌 있을 때 — **반드시 사용자 승인 필요**
아래 순서를 엄격히 따른다.
1. `git rebase origin/dev` 를 시도해 충돌 발생 시점을 확인.
2. 충돌 파일별로 다음을 요약해 사용자에게 공유:
   - 파일 경로
   - 양쪽(HEAD / origin/dev) 변경 요약
   - 어느 쪽을 택할지, 혹은 병합 방식에 대한 제안
3. **사용자 승인 없이 충돌을 독자 해결하지 않는다.**
4. 승인 후 해결 → `git add` → `git rebase --continue` → 테스트·린트·빌드 재실행.

## 4단계. push
- `git push --force-with-lease origin <branch>` 로 push (rebase 했을 수 있음).
- 단순 fast-forward 면 `--force-with-lease` 없이 `git push`.

## 5단계. PR 생성
```
gh pr create --base dev --head <branch> \
  --title "<type>: <title>" \
  --body "$(<PR 본문 생성>)"
```

PR 본문은 `__docs/PRD.md` 와 `plan.json` 으로부터 자동 생성:

```
## 요약
<PRD 배경 1~2문장>

## 변경 내역
<plan.json steps[*].title 리스트>

## 테스트
- [x] 단위 테스트 통과
- [x] 린트 통과
- [x] 빌드 통과

## 체크리스트
(프로젝트 .github/PULL_REQUEST_TEMPLATE.md 의 체크리스트 그대로)

## 관련
- PRD: (본문 요약 링크 — __docs 는 gitignore 이므로 PR 에는 포함하지 않음)
```

## 6단계. plan.json 마무리
- `status` 를 `shipped` 로 전환.
- 사용자에게 PR URL 과 요약 보고.

## 금지
- 사용자 승인 없이 충돌을 해결하지 않는다.
- 실패한 테스트·린트·빌드 상태로 push 하지 않는다.
- `--force` (lease 없는) push 는 Claude 훅에 의해 차단됨. Codex 세션은 훅이 없으므로 사용자가 직접 이 규칙을 엄격히 지킨다. 우회 시도 금지.
- `__docs/` 디렉토리의 파일은 **커밋·푸시하지 않는다** (브랜치 로컬 전용).

---

## 인라인 가이드 — 커밋 전 리뷰

Claude 의 `pre-commit-reviewer` 에이전트를 Codex 세션에서 대체하는 절차. 최종 검증 실패 시 원인 분석에도 사용.

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
- 이 단계에서 직접 수정 — 발견한 사항은 사용자 보고 또는 이전 단계로 회송

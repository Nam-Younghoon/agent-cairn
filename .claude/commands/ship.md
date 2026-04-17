---
description: 완료된 작업을 dev 로 동기화하고 push 후 PR 생성
argument-hint: (인자 없음)
allowed-tools: Read, Write, Edit, Bash, Agent
---

# /ship — 출고 (dev 동기화 → push → PR)

모든 스텝이 `completed` 인 상태에서 호출. 미완료가 있으면 중단.

## 1단계. 선조건 검증
- `__docs/plan.json` 의 모든 스텝이 `completed`. 아니면 어떤 스텝이 남아있는지 알려주고 중단.
- working tree 가 clean. 아니면 사용자에게 커밋되지 않은 변경을 먼저 처리하도록 요청.
- 현재 브랜치가 `plan.branch` 와 동일.

## 2단계. 최종 검증
- 전체 테스트·린트·빌드를 한 번 더 돌린다 (각 스텝에서 통과했어도 종합적으로 한 번 더).
- 실패 시 `pre-commit-reviewer` 서브에이전트에게 분석 위임 → 사용자에게 보고 후 중단.

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
- `--force` (lease 없는) push 는 훅에 의해 차단됨. 우회 시도 금지.
- `__docs/` 디렉토리의 파일은 **커밋·푸시하지 않는다** (브랜치 로컬 전용).

---
description: 지정된 PR 번호의 변경사항을 4단계로 상세 리뷰하고 사이드 이펙트를 분석. PASS|BLOCK 판정 후 사용자 승인 시 PR 코멘트 게시.
argument-hint: <PR번호> [추가 메시지]
allowed-tools: Bash, Read, Write, Edit, Grep, Agent
---

# /pr-reviewer — Pull Request 상세 리뷰

입력: $ARGUMENTS

이 커맨드는 `/discuss → /plan → /execute → /ship` 파이프라인과 **독립된 별도 트랙**입니다. 이미 올라온 PR 을 대상으로 동작하며, 브랜치 분기·코드 수정·커밋을 수행하지 않습니다.

## 서브에이전트 호출 흐름 (요약)
- **`pr-reviewer`**: 컨텍스트 수집·요구사항 검증·사이드 이펙트 분석·전사 재검수 전 과정을 수행. 본 커맨드의 핵심.
- 다른 서브에이전트(`parallel-explorer`, `tdd-tester`, `pre-commit-reviewer`)는 본 커맨드에서 호출하지 **않는다**.

---

## 1단계. 인자 파싱
- `$ARGUMENTS` 를 공백 기준으로 분할.
  - 첫 토큰 = PR 번호 (필수). 숫자가 아니면 사용법을 출력하고 중단.
  - 나머지 토큰 = 사용자 추가 메시지 (선택). 비어 있으면 빈 문자열.
- `$ARGUMENTS` 에 `--repo` 플래그가 포함되어 있으면 **즉시 중단** 한다. 본 사이클은 현재 디렉토리 origin 만 지원한다 (ADR-010). 안내 메시지: "외부 레포 리뷰는 미지원입니다. 해당 레포로 cd 후 다시 호출해 주세요."
- 둘을 변수로 보관하고, 사용자에게 "PR #<번호> 리뷰를 시작합니다" 한 줄 알림.

## 2단계. 사전 검증

다음을 **순서대로** 확인하고, 하나라도 실패하면 명확한 안내 메시지와 함께 중단한다.

1. 현재 디렉토리가 git 레포인지: `git rev-parse --show-toplevel`
2. `gh` CLI 가용성: `gh --version` (없으면 `https://cli.github.com` 안내)
3. `gh` 인증 상태: `gh auth status` (실패 시 `gh auth login` 안내)
4. 현재 디렉토리의 origin 이 GitHub 레포인지: `gh repo view --json url` 가 성공해야 함
5. 지정된 PR 번호가 실제로 존재하는지 + 상태가 `open` 인지:
   - `gh pr view <번호> --json number,state,headRefOid` 로 메타 수집 (실패 메시지 그대로 전달)
   - `state` 값을 확인: `OPEN` 이 아니면(`CLOSED`/`MERGED`) line-level 코멘트 게시가 실패할 수 있음을 사용자에게 안내하고, "그래도 로컬 리뷰만 진행할까요?" 컨펌. 거절 시 중단, 승인 시 6단계의 게시 옵션을 dry-run 으로 강제.
   - `headRefOid` 는 7-1 단계에서 `commit_id` 로 사용하므로 변수에 보관.

## 3단계. 리뷰 수행 — `pr-reviewer` 서브에이전트 호출

**`pr-reviewer` 서브에이전트를 호출**해 4단계 리뷰를 위임한다. 호출 프롬프트에 다음을 명시적으로 전달:

- PR 번호
- 사용자 추가 메시지 (있다면 그대로 포함)
- 작업 디렉토리 = 현재 git 레포
- 보고서는 **마크다운 본문** 으로 반환할 것 (서브에이전트는 파일을 직접 쓰지 않는다 — 권한 없음)
- 콘솔용 **요약 한 줄** 도 함께 반환할 것

서브에이전트는 `gh pr view`, `gh pr diff`, Read, Grep, Glob 만으로 작업을 완수한다. 본 커맨드는 그 반환값을 받아 다음 단계로 진행한다.

## 4단계. 보고서 저장

서브에이전트가 반환한 마크다운 본문을 **`__docs/pr-review-<PR번호>.md`** 로 저장한다.
- 디렉토리 없으면 생성.
- 동일 PR 을 재리뷰한 경우 **덮어쓴다** (ADR-012).
- 저장 전, 보고서 본문에 시크릿 후보(`password=`, `secret=`, `token=`, `Bearer `, `AKIA`, JWT 패턴 등) 가 마스킹되지 않은 채 남아 있는지 grep 으로 한 번 더 확인. 발견 시 마스킹하거나 사용자에게 보고 후 중단.

## 5단계. 콘솔 요약 출력

서브에이전트가 반환한 요약 한 줄을 콘솔에 출력하고, 보고서 경로를 함께 안내한다.

```
판정: PASS | BLOCK  /  BLOCK <N>건, WARNING <M>건  /  주요 사유: <한 줄>
보고서: __docs/pr-review-<PR번호>.md
```

## 6단계. PR 코멘트 게시 컨펌 (사용자 승인 필수)

사용자에게 다음을 묻는다.

```
이 리뷰 결과를 PR #<번호> 에 코멘트로 게시할까요?
  - BLOCK 사유는 해당 라인에 line-level 코멘트로 남깁니다 (gh api)
  - 종합 코멘트는 PR 일반 코멘트로 게시합니다 (gh pr comment)
  옵션: yes / no / dry-run (게시할 문구만 보여주고 실제 게시는 보류)
```

- `no` 또는 거절: 로컬 보고서 경로만 안내하고 종료.
- `dry-run`: 게시할 문구(line-level 본문 + 종합 코멘트 본문)를 콘솔에 출력하고 종료.
- `yes`: 7단계로.

## 7단계. PR 코멘트 게시 (gh CLI)

### 7-1. Line-level 코멘트 (BLOCK 사유)

판정이 BLOCK 이면, 보고서의 BLOCK 항목별로 `gh api` 를 호출해 해당 파일/라인에 코멘트를 남긴다.

**쉘 인젝션 방지**: 본문에는 사용자/AI 가 작성한 마크다운이 포함되므로 `"`, 백틱, `$()`, 개행이 들어갈 수 있다. 절대 `-f body="..."` 로 인라인 전달하지 말고, **임시 파일에 본문을 쓴 뒤 `-F body=@<임시파일>` 로 전달**한다.

```
# 각 BLOCK 항목별로 반복
TMP=$(mktemp)
printf '%s' "<사유 + 권장 수정 본문>" > "$TMP"
gh api repos/<owner>/<repo>/pulls/<번호>/comments \
  -F body=@"$TMP" \
  -f commit_id="<PR head SHA>" \
  -f path="<파일 경로>" \
  -F line=<번호> \
  -f side="RIGHT"
rm -f "$TMP"
```

- `<owner>/<repo>` 는 `gh repo view --json nameWithOwner -q .nameWithOwner` 로 추출.
- `<PR head SHA>` 는 2단계에서 보관한 `headRefOid` 사용.
- 한 BLOCK 사유당 한 번씩 호출. 실패 시 사용자에게 보고하고 다음 항목 진행.

판정이 PASS 면 7-1 은 건너뛴다.

### 7-2. 종합 코멘트 (`gh pr comment`)

**쉘 인젝션 방지 + 길이 제한 (GitHub 65,536자) 회피**를 위해 항상 `--body-file` 로 파일을 직접 전달한다. PASS 와 BLOCK 모두 임시 파일에 본문을 작성한 뒤 호출.

```
TMP=$(mktemp)
# PASS / BLOCK 본문을 "$TMP" 에 작성 (아래 규칙)
gh pr comment <번호> --body-file "$TMP"
rm -f "$TMP"
```

본문 규칙:
- **PASS**: 정확히 다음 한 줄을 게시한다.
  ```
  코드 리뷰는 통과입니다. 실기기 테스트 진행 후 Merge 진행해도 좋습니다.
  ```
  WARNING 항목이 1건 이상이면 위 한 줄 뒤에 빈 줄을 두고 `### 권고 사항` 섹션으로 WARNING 요약을 한 문단 추가.
- **BLOCK**: 다음 형식으로 게시한다.
  ```
  ## 코드 리뷰 결과: BLOCK

  <BLOCK 사유 요약 3~5줄>

  ### BLOCK 항목
  - [<카테고리>] <path>:<line> — <사유>
  - ...

  ### 권장 후속 조치
  - <조치 1>
  - <조치 2>

  상세 line-level 코멘트는 변경 파일에 별도 게시되었습니다.
  ```

### 7-3. 결과 보고

게시 성공/실패 개수를 사용자에게 한 줄로 보고하고 종료.

```
PR #<번호> 코멘트 게시 완료: line-level <N>건, 종합 1건
```

---

## 금지
- 사용자 승인 없이 PR 코멘트를 게시하지 않는다 (ADR-009).
- 리뷰 결과를 git 커밋·푸시 형태로 만들지 않는다 (본 커맨드는 로컬 산출물 + PR 코멘트만 다룬다).
- 시크릿 원문 값을 보고서·PR 코멘트에 노출하지 않는다 (마스킹 필수).
- 본 커맨드가 다루는 PR 의 코드를 직접 수정하지 않는다.
- 외부 레포(현재 디렉토리 origin 외)는 본 사이클 비지원. `--repo` 옵션이 지정되어도 거절한다 (ADR-010).
- `gh pr review --approve` / `gh pr merge` 등 머지·승인 액션을 수행하지 않는다. 머지 결정은 사람의 몫이다.
- 보고서 파일을 `__docs/` 외부에 저장하지 않는다 (`.gitignore` 보호 보장).
- `gh pr comment --body "..."` 또는 `gh api -f body="..."` 처럼 코멘트 본문을 **인라인 문자열로 전달하지 않는다**. 항상 `--body-file <파일>` 또는 `-F body=@<파일>` 로 파일을 통해 전달한다 (쉘 인젝션 + 길이 제한 회피).

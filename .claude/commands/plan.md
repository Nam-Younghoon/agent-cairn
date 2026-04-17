---
description: PRD 를 읽어 실행 가능한 스텝으로 분해하고 __docs/plan.json 생성
argument-hint: (인자 없음 — 현재 브랜치의 PRD.md 기준)
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(git status), Bash(git branch:*), Agent
---

# /plan — PRD → 실행 가능한 스텝 분해

이 커맨드는 `/discuss` 가 만든 `__docs/PRD.md` 를 기준으로 구현을 작은 단위로 쪼개어 `__docs/plan.json` 을 생성합니다.
이 파일은 `/execute` 와 `/ship` 이 상태를 주고받는 **단일 진실 원천**입니다.

## 1단계. 선조건 확인
- 현재 브랜치가 `dev` 가 아님을 확인한다. 맞다면 사용자에게 먼저 `/discuss` 를 돌리라고 안내.
- `__docs/PRD.md` 가 존재하는지 확인. 없으면 중단하고 `/discuss` 를 권장.
- `__docs/plan.json` 이 이미 있고 `status != planning` 이면 덮어쓰지 말고 사용자에게 확인.

## 2단계. 병렬 탐색 (존재하는 구조 파악)
필요시 **`parallel-explorer` 서브에이전트를 병렬로 호출**해 아래를 1~3 꼭지로 빠르게 수집.
- 이번 기능이 들어갈 계층/모듈 위치
- 기존 유사 기능의 컨벤션 (있다면)
- 영향받는 파일·의존성

## 3단계. 스텝 분해 규칙
PRD의 완료 기준 체크리스트 항목과 1:1 또는 1:N 매핑이 되도록 스텝을 설계한다.

- 스텝은 **한 개의 독립 커밋**으로 끝나야 한다 (롤백 가능성 확보).
- 스텝은 **가능한 한 TDD 사이클 하나** (실패 테스트 → 구현 → 통과) 로 완결한다.
- 의존성이 없는 스텝은 `depends_on` 을 비워두고, 병렬 실행 대상으로 삼는다.
- 문서·인프라·앱 코드가 섞인 경우 `scope` 로 구분한다.

예시 스텝 표현:

```json
{
  "id": 3,
  "title": "사용자 로그인 입력 스키마 추가",
  "description": "zod 스키마로 username/password 검증. 잘못된 값은 400 반환.",
  "scope": "backend",
  "depends_on": [1, 2],
  "status": "pending"
}
```

## 4단계. plan.json 생성
`.claude/templates/__docs/plan.schema.json` 스키마를 따르는 `__docs/plan.json` 파일을 생성한다.
실제 값이 채워진 참고 예시는 `.claude/templates/__docs/plan.example.json` 를 참조.

최소 스켈레톤:

```json
{
  "version": 1,
  "branch": "<현재 브랜치>",
  "type": "<feat|fix|...>",
  "title": "<PRD 제목>",
  "created_at": "<ISO 8601>",
  "status": "planning",
  "prd_path": "__docs/PRD.md",
  "steps": [
    { "id": 1, "title": "...", "scope": "...", "status": "pending", "depends_on": [] }
  ]
}
```

## 5단계. 요약 출력 및 사용자 승인
생성된 스텝 목록을 표 형태로 사용자에게 보여주고, 다음을 묻는다.

- 스텝 분해가 적절한가?
- 누락된 완료 기준이 있는가?
- 순서/의존성이 맞는가?

승인 후 `plan.json` 의 `status` 를 `in_progress` 로 바꿀지, 아니면 사용자 확인 후 `/execute` 가 그때 전환할지는 다음 커맨드에 위임한다 (여기서는 `planning` 상태로 저장).

## 금지
- 이 커맨드에서 **실제 코드 수정을 시작하지 않는다**. 오로지 문서·계획 파일만 쓴다.
- PRD 에 없는 완료 기준을 임의로 추가하지 않는다. 필요하면 사용자에게 묻고 PRD 를 먼저 갱신.
- plan.json 에 민감 값(비밀번호, URL 등) 을 넣지 않는다.

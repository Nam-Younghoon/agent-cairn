# 버전 민감 지침 (Claude Code 네이티브 의존성)

하네스는 중복 구현을 줄이기 위해 일부 역할을 **Claude Code 빌트인 자산에 위임**한다(ADR-020).
위임은 곧 가용성 의존이므로, 버전에 따라 깨질 수 있는 지침을 이 파일 한 곳에 모은다.
커맨드·에이전트 본문에는 모델명이나 빌트인 이름을 고정하지 않고 **여기를 참조**한다.

- **최종 확인일**: 2026-10-29
- **점검 주기**: Claude Code 메이저 업데이트 시, 또는 `/discuss` 에서 하네스 자체를 손댈 때.
  이때 §3 의 내장 커맨드 스냅샷도 함께 갱신한다.

---

## 1. 하네스가 의존하는 네이티브 자산

| 네이티브 자산 | 쓰이는 곳 | 없을 때 폴백 |
| --- | --- | --- |
| `Explore` 서브에이전트 (빌트인) | `/discuss` 4단계, `/plan-steps` 2단계, `/execute` B단계의 컨텍스트 수집 | 메인 세션에서 `Glob`/`Grep` 를 직접 병렬 호출. 한 파일 통째 읽기 전 패턴 검색 우선 |
| `/code-review` 스킬 (빌트인) | `/execute` G단계 1번, `/ship` 2단계 실패 분석 | `pre-commit-reviewer` 에 일반 품질 항목(중복·에러 처리·가독성)을 한시적으로 복원 |
| `claude --worktree <name>` | CLAUDE.md §2.7 멀티 세션 격리 | `scripts/worktree.sh new <task>` (`install.sh --with-worktree` 필요) 또는 `git worktree add` |
| 플랜 모드 | `/plan-steps` 의 스텝 분해 보조 | `__docs/plan.json` 수동 작성. plan.json 이 단일 진실 원천이므로 기능 손실은 없다 |

> Codex / Gemini 세션에는 위 자산이 **없다**. `.codex/prompts/*.md` 와 `.gemini/commands/*.toml` 의
> `## 인라인 가이드` 섹션이 같은 역할을 직접 수행하므로, Claude 쪽을 슬림화했다고 해서
> 미러의 인라인 가이드를 덜어내면 안 된다.

---

## 2. 모델 배정

### 서브에이전트 기본값 (`.claude/agents/*.md` frontmatter)

| 에이전트 | 모델 | 근거 |
| --- | --- | --- |
| `tdd-tester` | sonnet | 테스트 설계는 판단이 필요하나 범위가 좁다 |
| `pre-commit-reviewer` | sonnet | 규정 위반 판정에 맥락 해석이 필요 |
| `pr-reviewer` | opus | 4단계 전사 재검수, 사이드 이펙트 추론 |

### `/execute all` 장기 자율 실행

여러 스텝을 연속 자율 실행할 때는 장기 에이전틱 수행에 강한 상위 모델로 **세션 모델을 전환**하는 편이 안정적이다.

```
/model <장기 실행용 모델>  →  /execute all  →  /model <기본 모델>
```

- 커맨드 프론트매터의 `model:` 은 인자별 조건 분기가 안 되고 override 가 해당 턴에만 적용되므로,
  다중 스텝 실행 내내 유지되지 않는다. **세션 모델 변경(`/model`)** 으로만 안정적으로 동작한다.
- `next` / `<stepId>` 같은 단발 실행에는 세션 기본 모델을 그대로 쓴다. 상위 티어는 비용이 크다.
- 구체적인 모델명은 라인업이 바뀌므로 여기에도 고정하지 않는다. 실행 시점의 `/model` 목록에서 고른다.

---

## 3. 슬래시 커맨드 이름 충돌

하네스 커맨드가 Claude Code 내장 커맨드와 이름이 같으면, 공식 문서상 **로컬 터미널 세션에서
커스텀이 내장을 가린다** (`code.claude.com/docs/en/skills.md` — "Resolve skills that share a name").
`.claude/commands/*.md` 는 스킬로 병합되어 동일 규칙을 받는다. 에러가 나지 않고 조용히 덮어쓰므로
사람이 알아채기 어렵다.

> 내장의 **alias 는 가려지지 않는다**. 예컨대 `/usage` 를 가려도 내장 alias `/cost` 는 내장이 실행된다.
> 다만 alias 가 없는 내장 커맨드는 가려지면 슬래시 경로가 완전히 사라진다.

### 과거 사례 — `/plan`

`/plan` 은 내장 커맨드(`Enable plan mode or view the current session plan`)였고 alias 가 없었다.
하네스가 `/plan` 을 점유하면 내장 플랜 모드의 슬래시 진입 경로가 사라졌다 (`Shift+Tab` 은 영향 없음).
2026-10-29 에 `/plan-steps` 로 개명해 해소했다.

### 점검 방법

`tests/test_command_names.py` 가 하네스 커맨드 이름과 내장 커맨드 스냅샷의 교집합을 검사하고,
세 CLI 의 커맨드 이름 집합이 동일한지도 확인한다. **내장 스냅샷은 수동 갱신 대상이다** —
CLI 메이저 업데이트 때 아래로 다시 뽑아 `BUILTIN_COMMANDS` 를 교체한다.

```bash
BIN=$(readlink -f "$(which claude)")
strings -a "$BIN" | grep -oE 'type:"(local-jsx|local|prompt)",name:"[a-z][a-z0-9-]*"' \
  | sed -E 's/.*name:"([a-z0-9-]+)"/\1/' | sort -u
```

---

## 4. 변경 이력

| 날짜 | 변경 |
| --- | --- |
| 2026-10-29 | 최초 작성. `parallel-explorer` 폐기 → `Explore` 위임, `/code-review` 2단 게이트 도입에 따른 의존성 정리 (ADR-020) |
| 2026-10-29 | §3 신설. 내장 `/plan` 과의 이름 충돌 확인 후 하네스 커맨드를 `/plan-steps` 로 개명 (ADR-021) |

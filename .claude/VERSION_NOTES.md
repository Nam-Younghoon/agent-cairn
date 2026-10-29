# 버전 민감 지침 (Claude Code 네이티브 의존성)

하네스는 중복 구현을 줄이기 위해 일부 역할을 **Claude Code 빌트인 자산에 위임**한다(ADR-020).
위임은 곧 가용성 의존이므로, 버전에 따라 깨질 수 있는 지침을 이 파일 한 곳에 모은다.
커맨드·에이전트 본문에는 모델명이나 빌트인 이름을 고정하지 않고 **여기를 참조**한다.

- **최종 확인일**: 2026-10-29
- **점검 주기**: Claude Code 메이저 업데이트 시, 또는 `/discuss` 에서 하네스 자체를 손댈 때

---

## 1. 하네스가 의존하는 네이티브 자산

| 네이티브 자산 | 쓰이는 곳 | 없을 때 폴백 |
| --- | --- | --- |
| `Explore` 서브에이전트 (빌트인) | `/discuss` 4단계, `/plan` 2단계, `/execute` B단계의 컨텍스트 수집 | 메인 세션에서 `Glob`/`Grep` 를 직접 병렬 호출. 한 파일 통째 읽기 전 패턴 검색 우선 |
| `/code-review` 스킬 (빌트인) | `/execute` G단계 1번, `/ship` 2단계 실패 분석 | `pre-commit-reviewer` 에 일반 품질 항목(중복·에러 처리·가독성)을 한시적으로 복원 |
| `claude --worktree <name>` | CLAUDE.md §2.7 멀티 세션 격리 | `scripts/worktree.sh new <task>` (`install.sh --with-worktree` 필요) 또는 `git worktree add` |
| 플랜 모드 | `/plan` 의 스텝 분해 보조 | `__docs/plan.json` 수동 작성. plan.json 이 단일 진실 원천이므로 기능 손실은 없다 |

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

## 3. 변경 이력

| 날짜 | 변경 |
| --- | --- |
| 2026-10-29 | 최초 작성. `parallel-explorer` 폐기 → `Explore` 위임, `/code-review` 2단 게이트 도입에 따른 의존성 정리 (ADR-020) |

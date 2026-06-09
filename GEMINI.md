# agent-cairn: 올인원 개발 하네스 (All-in-One Development Harness)

`agent-cairn`은 여러 기술 스택(Express, NestJS, Flutter, Next.js, SpringBoot)에 걸쳐 일관된 컨벤션, 안전장치 및 작업 파이프라인을 제공하기 위해 설계된 메타 프레임워크이자 개발 하네스입니다. Claude Code, OpenAI Codex CLI, Google Gemini CLI 세 가지 AI 코딩 에이전트를 활용한 협업 개발에 최적화되어 있으며, 세 CLI 가 **동일 이름·동일 흐름**의 슬래시 커맨드를 공유합니다.

## 프로젝트 개요

- **목적**: 백엔드, 웹, 모바일 프로젝트에 표준화된 개발 프로세스, 보안 훅(Hooks), 자동화 파이프라인을 주입합니다.
- **핵심 아키텍처**: 템플릿 기반 설치 방식을 통해 타깃 리포지토리에 설정 파일, Python 기반 안전 훅, 슬래시 커맨드 정의를 배포합니다. 세 CLI 의 공통 본문(`CLAUDE.md` / `AGENTS.md` / `GEMINI.md`)은 `<!-- agent-cairn:start --> … <!-- agent-cairn:end -->` 마커 기반으로 스마트 병합되어 동일하게 유지됩니다.
- **주요 기술 스택**:
  - **Shell (Bash)**: 설치 스크립트(`scripts/install.sh`), 워크트리 헬퍼(`scripts/worktree.sh`), 테스트 하네스.
  - **Python**: 안전장치 훅(`.claude/hooks/`) 및 테스트(`pytest`).
  - **Markdown / TOML**: 규약 문서와 슬래시 커맨드 로직 (Claude `.claude/commands/*.md`, Codex `.codex/prompts/*.md`, Gemini `.gemini/commands/*.toml`).

## 빌드 및 실행

### 개발 및 테스트
- **안전 훅 테스트**: `python3 -m pytest` (위험 명령 및 시크릿 유출 탐지 테스트 실행).
- **전체 회귀 테스트**: `./scripts/test-harness.sh` (설치 시나리오 및 마커 기반 파일 병합 검증).

### 사용법 (설치)
타깃 프로젝트에 하네스를 설치하려면 다음 명령을 실행합니다:
```bash
./scripts/install.sh --stack=<stack> --target=/path/to/project [--cli=claude,codex,gemini] [--with-spotless] [--with-worktree]
```
- **지원 스택**: `express`, `nextjs`, `flutter`, `nestjs`, `springboot`, `springboot-kotlin`.
- **CLI 어댑터**(`--cli`, 기본값 `claude`): `claude` | `codex` | `gemini` 중 하나 또는 콤마 결합. `gemini` 포함 시 루트 `GEMINI.md` + `.gemini/`(settings.json + commands/*.toml + templates) 를 배포합니다.
- **`--with-spotless`**: SpringBoot(Java/Kotlin) 스택에 Spotless 포매터 스니펫 배포(옵트인).
- **`--with-worktree`**: git worktree 멀티 세션 격리 자산(`.worktreeinclude` + `scripts/worktree.sh`) 배포(옵트인).

## 개발 컨벤션

### 1. 슬래시 커맨드 파이프라인
**신규 작업 파이프라인 (4단계)** — 각 단계는 사용자 승인 후 다음으로 진행합니다:
1.  `/discuss <설명>`: 요구사항 분석, 브랜치 생성 및 `__docs/` 내 문서 생성 (PRD, ARCHITECTURE, ADR). 브랜치는 `git switch -c <branch> origin/<base>` 로 생성해 워크트리에서도 안전합니다.
2.  `/plan`: 작업을 `__docs/plan.json`에 상세 단계별로 분해.
3.  `/execute [next|all]`: 각 단계별로 TDD → 구현 → 검증 → 커밋을 반복 수행.
4.  `/ship`: 최종 검증, `dev` 브랜치 동기화, Pull Request 생성, 워크트리 정리.

**PR 리뷰 트랙 (독립)**:
- `/pr-reviewer <PR번호> [추가 메시지]`: 지정된 PR 을 4단계(컨텍스트 수집 → 요구사항 검증 → 사이드 이펙트 분석 → 전사 재검수)로 리뷰하고 PASS|BLOCK 판정. 사용자 승인 시에만 PR 코멘트를 게시합니다.

> Gemini 세션에서는 위 커맨드가 `.gemini/commands/<name>.toml` 의 `prompt` 본문으로 정의됩니다. Claude 의 서브에이전트(parallel-explorer/tdd-tester/pre-commit-reviewer/pr-reviewer) 호출 지점은 `## 인라인 가이드` 섹션으로 치환되어 단일 세션에서 직접 수행됩니다.

### 2. 안전장치 (하드락)
위험 명령(`rm -rf`, `git push --force`, `git reset --hard`, `prod` 환경의 `DROP/ALTER TABLE`, Flyway/Liquibase 파괴 명령)과 시크릿(`.env` 쓰기, `.claude/patterns/secrets.yaml` 패턴)에 대한 보호는 **CLI 별로 강도가 다릅니다**:

| CLI | 보호 메커니즘 | 한계 |
| --- | --- | --- |
| **Claude Code** | `.claude/hooks/*.py` (PreToolUse) 가 **물리적으로 차단** | 우회 불가 — 가장 강력 |
| **Codex CLI** | `approval_policy="on-request"` + `sandbox_mode="workspace-write"` | 위 표는 사용자 승인 1회로 통과 가능. `.env` 자동 감지 없음 |
| **Gemini CLI** | `.gemini/settings.json` `"sandbox": true` (OS sandbox) + 본 문서 soft lock | 위 명령은 **행동 규칙으로만** 강제. `.env` 쓰기·프로젝트 내부 `rm -rf` 자동 차단 없음 |

> **Gemini 세션 주의**: 위험 명령·시크릿 쓰기는 자동 차단되지 않으므로 본 문서의 규칙을 엄격히 지키고, 커밋 전 `.gitignore` 와 시크릿 파일 검사를 수동으로 수행하세요.

### 3. 주요 실천 지침
- **TDD 필수**: 모든 구현은 반드시 실패하는 테스트 작성부터 시작해야 합니다.
- **작은 단위 커밋**: 계획된 각 단계는 깨끗하고 작은 단위의 커밋으로 이어져야 합니다.
- **문서 우선**: `/discuss` 및 `/plan`이 승인되기 전에는 코드 수정을 시작하지 않습니다.
- **브랜치 전략**: Conventional Commits를 기반으로 `<type>/<kebab-case-summary>` 형식을 따릅니다.

### 4. 워크트리 — 멀티 세션 격리
같은 레포에서 AI 세션을 **동시에 여러 개** 굴려 병렬 작업할 때는 세션마다 별도 git worktree(독립 HEAD/작업 트리)에서 시작합니다. 단일 디렉토리에서 여러 세션이 같은 HEAD 를 공유하면 `/discuss` 의 브랜치 전환이 서로 간섭하기 때문입니다.

- **Gemini / Codex**: `scripts/worktree.sh new <task> [base]` → `.worktrees/<task>` 생성 + `.worktreeinclude` 파일(.env 등) 승계 복사. 그 안에서 세션을 띄웁니다. (`install.sh --with-worktree` 로 설치된 프로젝트에서 사용)
- **Claude**: 네이티브 `claude --worktree <name>` 사용.
- **진입 후**: 평소처럼 `/discuss → /plan → /execute → /ship`. 정리는 `scripts/worktree.sh clean <task>` (또는 Claude 네이티브 자동 정리).
- 작업 하나만 직렬로 진행한다면 워크트리 없이 그대로 동작합니다.

## 주요 디렉토리 구조

- `__docs/`: 작업별 임시 문서 (Git 무시 대상).
- `.claude/`: Claude 전용 설정, 훅 및 커맨드 정의.
- `.codex/`: Codex 전용 프롬프트(`prompts/*.md`) 및 설정(`config.toml`).
- `.gemini/`: Gemini 전용 슬래시 커맨드(`commands/*.toml`) 및 설정(`settings.json`).
- `scripts/`: 설치(`install.sh`)·워크트리 헬퍼(`worktree.sh`)·테스트(`test-harness.sh`) 도구.
- `templates/`: 기본 템플릿 및 스택별 `CLAUDE.md` / 린트 설정 / `worktreeinclude.partial`.
- `tests/`: 안전 훅 및 회귀 테스트 케이스.

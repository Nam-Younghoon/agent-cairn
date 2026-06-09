# agent-cairn

여러 프레임워크를 위한 올인원 개발 하네스. **Claude Code**, **OpenAI Codex CLI**, **Google Gemini CLI** 를 동시 지원하며, 백엔드(Express·NestJS·SpringBoot Java·SpringBoot Kotlin)·웹(Next.js)·모바일(Flutter) 프로젝트에 동일한 컨벤션·프로세스·안전장치·파이프라인을 주입합니다. 세 CLI 에서 `/discuss /plan /execute /ship` 신규 작업 4-커맨드 파이프라인과 `/pr-reviewer` PR 리뷰 트랙이 동일하게 동작합니다 (Codex/Gemini 는 서브에이전트가 없어 **인라인 가이드**로 대체 — ADR-001/013).

## 핵심 구성

| 구성요소 | 위치 | 설명 |
| --- | --- | --- |
| 팀 규격 본문 | `CLAUDE.md` (Claude) / `AGENTS.md` (Codex) / `GEMINI.md` (Gemini, 동일 본문 복제) | 문서/개발 컨벤션, 업무 프로세스, 금지 행동 |
| 위험 명령 차단 훅 (Bash) | `.claude/hooks/block_dangerous.py` | 위험한 재귀 삭제·`git force push`·`git reset --hard`·`sudo`·`chmod 777`·`curl\|sh`·운영 DB 스키마 변경 등 차단 **(Claude 세션 전용)** |
| 시크릿 차단 훅 (Write/Edit) | `.claude/hooks/block_secret_files.py` | `.env` 등 시크릿 파일 쓰기, 시크릿 문자열이 포함된 파일 쓰기 차단 **(Claude 세션 전용)** |
| 시크릿 정규식 | `.claude/patterns/secrets.yaml` | AWS/GitHub/Slack/JWT/Stripe/Private Key/Kakao/NCP/Toss 등 27종 |
| Claude 슬래시 커맨드 | `.claude/commands/{discuss,plan,execute,ship,pr-reviewer}.md` | 신규 작업 4-커맨드 파이프라인 + PR 리뷰 트랙 |
| Codex 슬래시 커맨드 / 프롬프트 | `.codex/prompts/{discuss,plan,execute,ship,pr-reviewer}.md` | 동일 이름·동일 흐름. 서브에이전트 호출 지점을 `## 인라인 가이드` 섹션으로 치환 |
| Codex 기본 설정 | `.codex/config.toml` | `approval_policy="on-request"`, `sandbox_mode="workspace-write"`, `network_access=true` + 프로젝트 trust 승격 안내 |
| Gemini 슬래시 커맨드 | `.gemini/commands/{discuss,plan,execute,ship,pr-reviewer}.toml` | 동일 이름·동일 흐름. TOML 단일 파일 (description + prompt 인라인). 서브에이전트 호출 지점은 인라인 가이드로 치환 (ADR-013) |
| Gemini 기본 설정 | `.gemini/settings.json` | `{"sandbox": true}` — OS-level sandbox 권장값. 비활성화 시 위험 명령·시크릿 보호가 GEMINI.md soft lock 만 남음 (ADR-014) |
| 서브에이전트 (Claude) | `.claude/agents/{parallel-explorer,tdd-tester,pre-commit-reviewer,pr-reviewer}.md` | 탐색·TDD·리뷰·PR 리뷰 전용. Codex/Gemini 는 네이티브 미사용, 인라인 가이드로 대체 (ADR-001/013) |
| 스택별 CLAUDE.md | `templates/{express,nextjs,flutter,nestjs,springboot,springboot-kotlin}/CLAUDE.md` | 아키텍처·스크립트·테스트 정책 + 올바른 모양 예시. `--cli=codex,gemini` 포함 시 동일 본문이 스택 경로의 `AGENTS.md` / `GEMINI.md` 로도 복제 |
| 문서 템플릿 | `templates/__docs/` | PRD / ARCHITECTURE / ADR / UI_GUIDE / plan.schema.json |
| 린트/포매터 | `templates/node/`, `templates/nestjs/eslint.config.mjs`, `templates/flutter/analysis_options.yaml`, `templates/springboot{,-kotlin}/spotless.gradle.kts` | ESLint(flat) + Prettier, NestJS 전용 ESLint, analysis_options, Spotless(옵트인) |
| PR 템플릿 | `templates/github/PULL_REQUEST_TEMPLATE.md` | 하네스 체크리스트 포함. **CLI 무관** (Claude/Codex/Gemini 모두 공용) |
| 워크트리 격리 | `scripts/worktree.sh`, `templates/worktreeinclude.partial` | git worktree 멀티 세션 격리(옵트인 `--with-worktree`). Claude 는 네이티브 `--worktree`, Codex/Gemini 는 헬퍼 `new\|list\|clean` (ADR-016~019) |
| 설치 스크립트 | `scripts/install.sh` | `--cli` 로 Claude/Codex/Gemini 선택(혼용 가능), 단일·다중·모노레포 스택, 마커 기반 스마트 병합 |
| 셀프 테스트 | `scripts/test-harness.sh`, `tests/` | pytest + 설치 시나리오 회귀 (현재 PASS=310) |

## 슬래시 커맨드

### 신규 작업 파이프라인 (4-커맨드)

```
/discuss <설명>          PRD/ARCHITECTURE/ADR/(UI_GUIDE) 초안 + 브랜치 생성
       ↓ 사용자 승인
/plan                    __docs/plan.json 으로 스텝 분해 (의존성·스코프 포함)
       ↓ 사용자 승인
/execute [next|all|<id>] 스텝 단위로 Explore → TDD → 구현 → 검증(lint/build) → 리뷰 → 커밋
       ↓ 모든 스텝 completed
/ship                    전체 검증 → dev 최신화(충돌 시 컨펌) → push → gh pr create
```

### PR 리뷰 트랙 (독립)

```
/pr-reviewer <PR번호> [추가 메시지]
       ↓ gh CLI 사전 검증 (가용성·인증·origin·PR state)
       ↓ 4단계 리뷰 (컨텍스트 수집 → 요구사항 검증 → 사이드 이펙트 분석 → 전사 재검수)
       ↓ __docs/pr-review-<PR번호>.md 저장 + 콘솔 요약 (PASS|BLOCK)
       ↓ 사용자 컨펌 (yes/no/dry-run)
       ↓ PR 코멘트 게시: line-level (gh api) + 종합 (gh pr comment)
```

BLOCK 기준: 요구사항 미충족·로직 결함, 보안·시크릿 누출, 하네스 규약 위반(any 타입·하드코딩·네이밍 등). TDD 누락은 WARNING.

각 커맨드 내부에서 호출되는 서브에이전트:
- `parallel-explorer`: `/discuss`, `/plan`, `/execute` 의 초반 컨텍스트 수집.
- `tdd-tester`: `/execute` 의 C 단계 (실패 테스트 작성).
- `pre-commit-reviewer`: `/execute` 의 G 단계 (커밋 전 게이트), `/ship` 의 최종 검증.
- `pr-reviewer`: `/pr-reviewer` 의 리뷰 단계 (4단계 전 과정 위임, 읽기 전용).

## 설치

```bash
git clone <이 레포> /tmp/agent-cairn

# Claude Code 단독 (기본값, --cli 미지정)
/tmp/agent-cairn/scripts/install.sh --stack=express --target=/path/to/project

# Codex CLI 단독
/tmp/agent-cairn/scripts/install.sh --cli=codex --stack=express --target=/path/to/project

# Gemini CLI 단독
/tmp/agent-cairn/scripts/install.sh --cli=gemini --stack=express --target=/path/to/project

# Claude + Codex 혼용 (팀 내 CLI 혼용 시)
/tmp/agent-cairn/scripts/install.sh --cli=claude,codex --stack=nextjs --target=/path/to/project

# 3-way 혼용 (Claude + Codex + Gemini 동시)
/tmp/agent-cairn/scripts/install.sh --cli=claude,codex,gemini --stack=nextjs --target=/path/to/project

# 풀스택 개인 프로젝트 (여러 스택 동시)
/tmp/agent-cairn/scripts/install.sh --stack=express,nextjs,flutter --target=/path/to/project

# SpringBoot 에 포매터(Spotless) 옵트인 (Codex/Gemini 포함 혼용도 지원)
/tmp/agent-cairn/scripts/install.sh --cli=claude,codex,gemini --stack=springboot-kotlin --with-spotless --target=/path/to/project

# 모노레포 (앱별 경로, 3-way 동시)
/tmp/agent-cairn/scripts/install.sh \
  --cli=claude,codex,gemini \
  --stack='express:apps/api,nextjs:apps/web,flutter:apps/mobile,nestjs:apps/api-nest,springboot-kotlin:apps/api-kotlin' \
  --with-spotless \
  --target=/path/to/monorepo

# git worktree 멀티 세션 격리 자산 옵트인 (Codex/Gemini 헬퍼 + .worktreeinclude)
/tmp/agent-cairn/scripts/install.sh --stack=express --with-worktree --target=/path/to/project
```

옵션:
- `--cli=<list>` (기본값 `claude`): `claude | codex | gemini` 중 하나 또는 콤마 결합. `claude` 미포함 시 `.claude/` 와 `CLAUDE.md` 를 배포하지 않으며, `codex` 포함 시 `AGENTS.md` 와 `.codex/` 자산을, `gemini` 포함 시 `GEMINI.md` 와 `.gemini/` 자산을 추가 배포.
- `--stack=<spec>` (필수): `express | nextjs | flutter | nestjs | springboot | springboot-kotlin` 중 하나 또는 콤마 결합. 앱별 경로는 `<stack>:<path>` 로 지정.
- `--target=<경로>` (기본: 현재 디렉토리).
- `--force`: 기존 파일 덮어쓰기 허용 (CLAUDE.md/AGENTS.md 는 마커 구간만 덮어써도 되므로 대부분 불필요).
- `--with-spotless`: SpringBoot(Java/Kotlin) 스택에 Spotless 포매터 스니펫과 `.editorconfig` 를 배포. 기본은 포매터 없음. 리포 단위 전역 on/off.
- `--with-worktree`: git worktree 멀티 세션 격리 자산(`.worktreeinclude` + `scripts/worktree.sh`)을 배포. 기본은 미배포. 같은 레포에서 세션을 동시에 여러 개 굴려 병렬 작업할 때, Claude 는 `claude --worktree <name>`, Codex/Gemini 는 `scripts/worktree.sh new <task>` 로 세션마다 독립 워크트리를 만든다 (ADR-016~019).

설치 후 자동으로 수행되는 것 (`--cli` 값에 따라 분기):
1. **공통**: `.gitignore` 에 하네스 블록 추가 (`__docs/`, `.env`, `.codex/sessions/` 등), `.env.example` 배포, `.github/PULL_REQUEST_TEMPLATE.md` 배포, 스택별 린트/포매터 설정.
2. **Claude 포함 시**: `.claude/` (settings, hooks, patterns, commands, agents, templates/__docs) 배포 + `CLAUDE.md` 생성·마커 병합 (`<!-- agent-cairn:start -->` 안쪽만 교체, 바깥쪽 사용자 커스텀 보존). 모노레포 스택 경로에도 `CLAUDE.md` 생성.
3. **Codex 포함 시**: `.codex/config.toml` 와 `.codex/prompts/{discuss,plan,execute,ship,pr-reviewer}.md` 를 **루트 1회**만 배포, `AGENTS.md` 를 루트·모노레포 스택 경로에 `CLAUDE.md` 와 동일 본문으로 마커 병합. 종료 메시지에 `codex projects trust <target>` 안내 출력.
4. **Gemini 포함 시**: `.gemini/settings.json` 와 `.gemini/commands/{discuss,plan,execute,ship,pr-reviewer}.toml` 를 **루트 1회**만 배포, `GEMINI.md` 를 루트·모노레포 스택 경로에 동일 본문으로 마커 병합. 종료 메시지에 sandbox 권장값·슬래시 바인딩 fallback·하드락 비대칭 경고 출력.

### Codex 설치 후 할 일 (수동)

Codex CLI 는 **untrusted 프로젝트의 `.codex/config.toml` 을 로드하지 않습니다**. 최초 1회 프로젝트 신뢰 승격이 필요합니다.

```bash
# 옵션 A — Codex CLI UI 또는 명령어로 승격
codex projects trust /path/to/project

# 옵션 B — ~/.codex/config.toml 에 직접 블록 추가
[projects."/path/to/project"]
trust_level = "trusted"
```

그 뒤 Codex 세션에서 `/discuss <설명>` 을 호출했을 때 `.codex/prompts/discuss.md` 로 **자동 바인딩**되는지 확인하세요. 만약 자동 바인딩되지 않으면(Codex 공식 문서가 아직 커스텀 슬래시 경로를 명시하지 않음 — ADR-004 참고), `AGENTS.md` 에 아래 섹션을 추가해 파일 참조 fallback 으로 사용합니다.

```markdown
## 슬래시 커맨드 대체 — Codex
- `@.codex/prompts/discuss.md 의 절차를 따라 진행해주세요.`
- `@.codex/prompts/plan.md ...` / `@.codex/prompts/execute.md ...` / `@.codex/prompts/ship.md ...`
- `@.codex/prompts/pr-reviewer.md 의 절차를 따라 PR <번호> 를 리뷰해주세요.`
```

### Gemini 설치 후 할 일 (수동)

Gemini CLI 는 프로젝트 루트의 `GEMINI.md` 와 `.gemini/commands/<n>.toml` 을 컨텍스트·슬래시 커맨드 정의로 자동 인식합니다. 설치 직후 다음을 확인하세요.

1. **`.gemini/settings.json` 검토** — 기본값은 `{"sandbox": true}` 입니다. OS-level sandbox 가 호스트 시스템과 프로젝트 외부 쓰기를 차단하므로 가능한 한 유지하세요. 비활성화가 필요한 환경(예: 컨테이너 안에서 또 sandbox 가 작동 안 함)에서는 `false` 로 변경하고 사유를 팀에 공유합니다 — 위험 명령·시크릿 보호가 `GEMINI.md` 의 soft lock 만 남게 됩니다 (ADR-014).

2. **슬래시 커맨드 바인딩 확인** — Gemini 세션에서 `/discuss <설명>` 호출 시 `.gemini/commands/discuss.toml` 의 `prompt` 본문이 실행되는지 확인하세요. 자동 바인딩이 안 되면(본 사이클에서 실측 미수행 — Codex 의 ADR-004 와 평행) `GEMINI.md` 에 아래 fallback 섹션을 추가합니다.

```markdown
## 슬래시 커맨드 대체 — Gemini
- `@.gemini/commands/discuss.toml 의 prompt 절차에 따라 진행해주세요.`
- `@.gemini/commands/plan.toml ...` / `@.gemini/commands/execute.toml ...` / `@.gemini/commands/ship.toml ...`
- `@.gemini/commands/pr-reviewer.toml 의 prompt 절차에 따라 PR <번호> 를 리뷰해주세요.`
```

3. **하드락 비대칭 인지** — Gemini 세션에서는 `.env`/시크릿 자동 차단과 프로젝트 내부 위험 명령 자동 차단이 동작하지 않습니다. 보호는 OS sandbox + `GEMINI.md` §4 행동 규칙 두 계층뿐입니다 (ADR-014). 커밋 전 `git diff` 로 시크릿·`.env` 누출을 수동 검토하는 절차를 팀 내에서 약속하세요.

### 기존 설치 사용자 — 업데이트 유의사항

이미 `install.sh` 를 실행한 프로젝트에서는 `.gitignore` 에 `agent-cairn — 하네스 기본 규칙` 마커가 있으면 **Codex 선제 방어 블록이 자동 추가되지 않습니다**. 아래 블록을 `.gitignore` 에 수동 추가하거나, 기존 블록을 제거 후 `install.sh --cli=claude,codex ...` 을 재실행하세요.

```gitignore
.codex/sessions/
.codex/history*
.codex/cache/
.codex/*.log
.codex/config.local.toml
!.codex/config.toml
!.codex/prompts/
```

## 하드락 (훅이 자동 차단)

> **CLI 별 유효 범위 (필독)**
> 아래 하드락은 **Claude Code 세션에서만 물리적으로 차단**됩니다. **Codex CLI 세션**에서는 `.codex/config.toml` 의 `approval_policy="on-request"` + `sandbox_mode="workspace-write"` 로만 보호되어, 사용자가 승인을 누르면 동일 명령이 통과됩니다. **Gemini CLI 세션**에서는 `.gemini/settings.json` 의 `"sandbox": true` 로 호스트 시스템·프로젝트 외부 쓰기만 차단되고, 프로젝트 내부의 위험 명령·`.env` 쓰기는 `GEMINI.md` §4 의 에이전트 행동 규칙(soft lock) 에만 의존합니다 — 모델 준수에 깨질 수 있는 보호입니다. 특히 **`.env` / 시크릿 문자열 쓰기 차단** 은 Codex/Gemini 세션에서 감지되지 않습니다. Codex/Gemini 사용자는 커밋 전 수동으로 `git diff` 를 검토하고 `.env`/토큰 누출을 확인하세요.
>
> **approval_policy 의 실제 의미**: "on-request" 는 "매 명령마다 승인" 이 아니라 `sandbox_mode` 경계(프로젝트 밖 쓰기 등)를 넘을 때만 승인을 요청합니다. `network_access=true` 는 `npm install`·`git push`·`pip install` 같은 일상 작업이 매번 승인되는 피로감을 줄이기 위한 기본값입니다. 보수적으로 조정하려면 `.codex/config.toml` 에서 `network_access=false` 또는 `approval_policy="untrusted"` / `sandbox_mode="read-only"` 로 재정의하세요.

| 대상 | 차단 이유 |
| --- | --- |
| `rm -rf`, `rm -fr` 및 변형 | 데이터 유실 |
| `git push --force` / `-f` | 업스트림 히스토리 파괴 (`--force-with-lease` 는 허용) |
| `git reset --hard` | 로컬 변경 유실 |
| `git clean -f`, `-fd` | 미추적 파일 복구 불가 |
| `sudo ...` | 로컬 권한 변경 위험 |
| `chmod 777` / `-R 777` | 과도 권한 |
| `curl \| sh`, `wget \| bash` | 검증되지 않은 코드 실행 |
| `DROP DATABASE` | 환경 무관 |
| `DROP/ALTER TABLE` + `prod` 식별자 동시 포함 | 운영 DB 스키마 변경 |
| Flyway `clean` / `flywayClean` / `flyway:clean` | 마이그레이션 도구로 모든 DB 객체를 삭제하는 파괴 명령 |
| Liquibase `drop-all` / `dropAll` / `liquibase:dropAll` | 마이그레이션 도구로 관리 테이블을 전체 삭제 |
| `.env`, `.env.production`, `.env.prod`, `.env.staging` 쓰기 | 실 시크릿 유출 방지 (`.env.example/.sample/.template` 은 허용) |
| 시크릿 패턴 포함 쓰기 | `.claude/patterns/secrets.yaml` 매칭 시 |

모든 차단은 훅이 exit 2 + stderr 로 수행합니다. 프롬프트 약속이 아니라 물리적 차단입니다.

## 개발·테스트

```bash
# 훅 테스트
python3 -m pytest

# 전체 회귀 (pytest + 필수 파일 + install 시나리오 + 마커 병합)
./scripts/test-harness.sh
```

## 팀 내 확장

- **스택 추가**: `templates/<new-stack>/CLAUDE.md` 추가, `install.sh` 의 `validate_stack` 케이스 확장. 포매터 등 부가 자산을 옵션으로 두려면 `--with-<flag>` 스타일의 플래그를 추가하고 `install_<stack>_<feature>` 함수를 `HAS_PATH_SPEC` 분기에 연결한다 (예: SpringBoot `--with-spotless`).
- **규약 수정**: `CLAUDE.md` 본문 수정 후 각 프로젝트에서 `install.sh` 재실행(마커 안쪽만 교체됨).
- **시크릿 패턴 추가**: `.claude/patterns/secrets.yaml` 에 정규식 추가, `tests/test_block_secret_files.py` 에 테스트 케이스 추가.
- **새 위험 패턴 차단**: `.claude/hooks/block_dangerous.py` 의 `evaluate()` 에 규칙 추가 + `tests/test_block_dangerous.py` 에 케이스 추가.

## 제약과 주의사항

- 운영 DB 차단은 **휴리스틱** (명령 텍스트에 `prod`/`production` 키워드 동반 필요). 정식 보호는 네트워크 분리·IAM·읽기전용 커넥션이 담당해야 합니다.
- `/discuss` 는 `dev` 브랜치가 존재한다고 가정합니다. 초기 리포는 기준 브랜치를 수동 지정.
- 복사 배포 모델이므로 하네스 업데이트 후 각 프로젝트에 `install.sh` 재실행이 필요합니다. 마커 덕분에 사용자 커스텀은 보존됩니다.
- Codex 슬래시 커맨드 자동 바인딩은 공식 문서에 아직 명시되어 있지 않아 **본 사이클에서 실측을 수행하지 않았습니다** (ADR-004). 설치 후 위의 "Codex 설치 후 할 일" 절차로 수동 검증·필요 시 fallback 을 적용하세요.

## 후속 로드맵

- **Codex 훅 stable 승격 후 하드락 이중화** — `features.codex_hooks` 가 정식 기능이 되면 `.claude/hooks/*.py` 를 `.codex/hooks/` 로 이식해 두 세션에서 동일한 물리 차단을 제공 (ADR-002).
- **`.codex/agents/*.toml` 네이티브 서브에이전트 배포** — 인라인 가이드(현재) 대신 Codex 공식 서브에이전트 메커니즘을 쓰면 품질·컨텍스트 분리 개선 가능 (ADR-001).
- **슬래시 커맨드 자동 바인딩 실측 자동화 (Codex)** — `CODEX_CLI_AVAILABLE=1` opt-in 으로 `test-harness.sh` 가 실제 Codex 세션을 띄워 `/discuss` 바인딩을 검증 (ADR-004).
- **슬래시 커맨드 자동 바인딩 실측 자동화 (Gemini)** — `GEMINI_CLI_AVAILABLE=1` opt-in 으로 `.gemini/commands/<n>.toml` 자동 바인딩을 실측. Codex 트랙과 동일 패턴.
- **Gemini 훅 정식 지원 시 하드락 이중화** — Gemini CLI 가 PreToolUse 류 훅을 정식 지원하면 `.claude/hooks/*.py` 동등 자산을 `.gemini/hooks/` 로 이식, ADR-014 를 superseded 처리.

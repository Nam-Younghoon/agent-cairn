# agent-cairn

여러 프레임워크를 위한 올인원 개발 하네스. **Claude Code** 와 **OpenAI Codex CLI** 를 동시 지원하며, 백엔드(Express·NestJS·SpringBoot Java·SpringBoot Kotlin)·웹(Next.js)·모바일(Flutter) 프로젝트에 동일한 컨벤션·프로세스·안전장치·파이프라인을 주입합니다. 두 CLI 에서 `/discuss /plan /execute /ship` 4-커맨드 UX 는 동일하게 동작합니다 (Codex 는 서브에이전트가 없어 **인라인 가이드**로 대체 — ADR-001).

## 핵심 구성

| 구성요소 | 위치 | 설명 |
| --- | --- | --- |
| 팀 규격 본문 | `CLAUDE.md` (Claude) / `AGENTS.md` (Codex, 동일 본문 복제) | 문서/개발 컨벤션, 업무 프로세스, 금지 행동 |
| 위험 명령 차단 훅 (Bash) | `.claude/hooks/block_dangerous.py` | `rm -rf`·`git force push`·`git reset --hard`·`sudo`·`chmod 777`·`curl\|sh`·운영 DB 스키마 변경 등 차단 **(Claude 세션 전용)** |
| 시크릿 차단 훅 (Write/Edit) | `.claude/hooks/block_secret_files.py` | `.env` 등 시크릿 파일 쓰기, 시크릿 문자열이 포함된 파일 쓰기 차단 **(Claude 세션 전용)** |
| 시크릿 정규식 | `.claude/patterns/secrets.yaml` | AWS/GitHub/Slack/JWT/Stripe/Private Key 등 16종 |
| Claude 슬래시 커맨드 | `.claude/commands/{discuss,plan,execute,ship}.md` | 4-커맨드 파이프라인 |
| Codex 슬래시 커맨드 / 프롬프트 | `.codex/prompts/{discuss,plan,execute,ship}.md` | 동일 이름·동일 흐름. 서브에이전트 호출 지점을 `## 인라인 가이드` 섹션으로 치환 |
| Codex 기본 설정 | `.codex/config.toml` | `approval_policy="on-request"`, `sandbox_mode="workspace-write"`, `network_access=true` + 프로젝트 trust 승격 안내 |
| 서브에이전트 (Claude) | `.claude/agents/{parallel-explorer,tdd-tester,pre-commit-reviewer}.md` | 탐색·TDD·리뷰 전용. Codex 는 네이티브 미사용, 인라인 가이드로 대체 (ADR-001) |
| 스택별 CLAUDE.md | `templates/{express,nextjs,flutter,nestjs,springboot,springboot-kotlin}/CLAUDE.md` | 아키텍처·스크립트·테스트 정책 + 올바른 모양 예시. `--cli=codex` 시 동일 본문이 스택 경로의 `AGENTS.md` 로도 복제 |
| 문서 템플릿 | `templates/__docs/` | PRD / ARCHITECTURE / ADR / UI_GUIDE / plan.schema.json |
| 린트/포매터 | `templates/node/`, `templates/nestjs/eslint.config.mjs`, `templates/flutter/analysis_options.yaml`, `templates/springboot{,-kotlin}/spotless.gradle.kts` | ESLint(flat) + Prettier, NestJS 전용 ESLint, analysis_options, Spotless(옵트인) |
| PR 템플릿 | `templates/github/PULL_REQUEST_TEMPLATE.md` | 하네스 체크리스트 포함. **CLI 무관** (Claude/Codex 모두 공용) |
| 설치 스크립트 | `scripts/install.sh` | `--cli` 로 Claude/Codex 선택(혼용 가능), 단일·다중·모노레포 스택, 마커 기반 스마트 병합 |
| 셀프 테스트 | `scripts/test-harness.sh`, `tests/` | pytest + 설치 시나리오 회귀 (현재 PASS=167) |

## 4-커맨드 파이프라인

```
/discuss <설명>          PRD/ARCHITECTURE/ADR/(UI_GUIDE) 초안 + 브랜치 생성
       ↓ 사용자 승인
/plan                    __docs/plan.json 으로 스텝 분해 (의존성·스코프 포함)
       ↓ 사용자 승인
/execute [next|all|<id>] 스텝 단위로 Explore → TDD → 구현 → 검증(lint/build) → 리뷰 → 커밋
       ↓ 모든 스텝 completed
/ship                    전체 검증 → dev 최신화(충돌 시 컨펌) → push → gh pr create
```

각 커맨드 내부에서 호출되는 서브에이전트:
- `parallel-explorer`: `/discuss`, `/plan`, `/execute` 의 초반 컨텍스트 수집.
- `tdd-tester`: `/execute` 의 C 단계 (실패 테스트 작성).
- `pre-commit-reviewer`: `/execute` 의 G 단계 (커밋 전 게이트), `/ship` 의 최종 검증.

## 설치

```bash
git clone <이 레포> /tmp/agent-cairn

# Claude Code 단독 (기본값, --cli 미지정)
/tmp/agent-cairn/scripts/install.sh --stack=express --target=/path/to/project

# Codex CLI 단독
/tmp/agent-cairn/scripts/install.sh --cli=codex --stack=express --target=/path/to/project

# Claude + Codex 혼용 (팀 내 CLI 혼용 시)
/tmp/agent-cairn/scripts/install.sh --cli=claude,codex --stack=nextjs --target=/path/to/project

# 풀스택 개인 프로젝트 (여러 스택 동시)
/tmp/agent-cairn/scripts/install.sh --stack=express,nextjs,flutter --target=/path/to/project

# SpringBoot 에 포매터(Spotless) 옵트인 (Codex 포함 혼용도 지원)
/tmp/agent-cairn/scripts/install.sh --cli=claude,codex --stack=springboot-kotlin --with-spotless --target=/path/to/project

# 모노레포 (앱별 경로, Claude+Codex 동시)
/tmp/agent-cairn/scripts/install.sh \
  --cli=claude,codex \
  --stack='express:apps/api,nextjs:apps/web,flutter:apps/mobile,nestjs:apps/api-nest,springboot-kotlin:apps/api-kotlin' \
  --with-spotless \
  --target=/path/to/monorepo
```

옵션:
- `--cli=<list>` (기본값 `claude`): `claude | codex` 중 하나 또는 콤마 결합. `claude` 미포함 시 `.claude/` 와 `CLAUDE.md` 를 배포하지 않으며, `codex` 포함 시 `AGENTS.md` 와 `.codex/` 자산을 추가 배포.
- `--stack=<spec>` (필수): `express | nextjs | flutter | nestjs | springboot | springboot-kotlin` 중 하나 또는 콤마 결합. 앱별 경로는 `<stack>:<path>` 로 지정.
- `--target=<경로>` (기본: 현재 디렉토리).
- `--force`: 기존 파일 덮어쓰기 허용 (CLAUDE.md/AGENTS.md 는 마커 구간만 덮어써도 되므로 대부분 불필요).
- `--with-spotless`: SpringBoot(Java/Kotlin) 스택에 Spotless 포매터 스니펫과 `.editorconfig` 를 배포. 기본은 포매터 없음. 리포 단위 전역 on/off.

설치 후 자동으로 수행되는 것 (`--cli` 값에 따라 분기):
1. **공통**: `.gitignore` 에 하네스 블록 추가 (`__docs/`, `.env`, `.codex/sessions/` 등), `.env.example` 배포, `.github/PULL_REQUEST_TEMPLATE.md` 배포, 스택별 린트/포매터 설정.
2. **Claude 포함 시**: `.claude/` (settings, hooks, patterns, commands, agents, templates/__docs) 배포 + `CLAUDE.md` 생성·마커 병합 (`<!-- agent-cairn:start -->` 안쪽만 교체, 바깥쪽 사용자 커스텀 보존). 모노레포 스택 경로에도 `CLAUDE.md` 생성.
3. **Codex 포함 시**: `.codex/config.toml` 와 `.codex/prompts/{discuss,plan,execute,ship}.md` 를 **루트 1회**만 배포, `AGENTS.md` 를 루트·모노레포 스택 경로에 `CLAUDE.md` 와 동일 본문으로 마커 병합. 종료 메시지에 `codex projects trust <target>` 안내 출력.

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
```

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
> 아래 하드락은 **Claude Code 세션에서만 물리적으로 차단**됩니다. **Codex CLI 세션**에서는 `.codex/config.toml` 의 `approval_policy="on-request"` + `sandbox_mode="workspace-write"` 로만 보호되어, 사용자가 승인을 누르면 동일 명령이 통과됩니다. 특히 **`.env` / 시크릿 문자열 쓰기 차단** 은 Codex 세션에서 감지되지 않습니다. Codex 사용자는 커밋 전 수동으로 `git diff` 를 검토하고 `.env`/토큰 누출을 확인하세요.
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
- **슬래시 커맨드 자동 바인딩 실측 자동화** — `CODEX_CLI_AVAILABLE=1` opt-in 으로 `test-harness.sh` 가 실제 Codex 세션을 띄워 `/discuss` 바인딩을 검증 (ADR-004).
- **Gemini CLI 어댑터 지원** — `--cli=gemini` 추가. Gemini 의 `GEMINI.md` 와 `.gemini/commands/*.toml` 포팅.

# Changelog

본 하네스 자체의 변경 이력. Keep-a-Changelog 형식을 따르며, 각 릴리즈에 추가/변경/제거/수정을 명시한다.

## [Unreleased]

### 추가
- **Git worktree 기반 멀티 세션 격리 지원** — 같은 레포에서 AI 세션을 동시에 여러 개 굴릴 때 세션마다 독립 워크트리(독립 HEAD/작업 트리)에서 시작해 `/discuss` 의 HEAD 전환 간섭을 구조적으로 제거. 워크트리는 **세션 실행 시점**에 만들고 커맨드는 워크트리-세이프하게만 동작(ADR-016). ① 세 CLI(`/discuss`)의 브랜치 생성을 `git switch dev && git pull` → `git switch -c <branch> origin/<base>` 로 교체해 base 로컬 체크아웃을 제거, 메인 워크트리가 base 를 잡고 있어도 dual-checkout `fatal` 회피(ADR-017). ② 세 CLI(`/ship`)에 머지 후 워크트리 정리 7단계 추가(Claude 네이티브 자동 / `scripts/worktree.sh clean`). ③ `scripts/worktree.sh new|list|clean` 헬퍼 신설 — Codex/Gemini 용으로 Claude 네이티브 `--worktree` + `.worktreeinclude` 동작을 모사(base detached HEAD 워크트리 생성 + gitignore 파일 승계 복사, 시크릿 값 로그 비노출, task 경로 트래버설 가드). ④ `templates/worktreeinclude.partial`(`.env*` 승계 목록) + `.gitignore`/`gitignore.partial` 에 `.claude/worktrees/`·`.worktrees/` 블록. ⑤ `install.sh --with-worktree` 옵트인 플래그(`--with-spotless` 패턴 미러)로 `.worktreeinclude` + `scripts/worktree.sh` 배포. ⑥ 공용 본문에 §2.7 "워크트리 — 멀티 세션 격리" 절차를 추가해 CLAUDE/AGENTS/GEMINI 3-way 동일 분배. ⑦ ADR-016~019(생성 시점·워크트리-세이프 브랜치·멀티 CLI 분기·옵트인 배포) 등록. test-harness 4j~4o 섹션 신설로 회귀 통과: **PASS=310 / FAIL=0** (이전 269 → 310).
- **`/pr-reviewer` 슬래시 커맨드 신설** — 지정된 PR 번호를 4단계(컨텍스트 수집 → 요구사항 검증 → 사이드 이펙트 분석 → 전사 재검수) 로 깊게 리뷰하고 PASS|BLOCK 판정을 내리는 독립 트랙. `/discuss → /plan → /execute → /ship` 파이프라인과는 별도로 호출(`/pr-reviewer <PR번호> [추가 메시지]`). 결과는 `__docs/pr-review-<PR번호>.md` 로 저장되고 콘솔 요약이 출력되며, 사용자가 `yes/no/dry-run` 으로 승인할 때에만 PR 코멘트를 게시(BLOCK 사유는 `gh api` line-level, 종합은 `gh pr comment` — 두 호출 모두 임시 파일 + `--body-file` / `-F body=@<파일>` 로 쉘 인젝션·65,536자 제한 동시 회피). 외부 레포(`--repo` 옵션) 는 1단계에서 즉시 거절. BLOCK 기준은 요구사항 미충족·로직 결함 / 보안·시크릿 누출 / 하네스 규약 위반(any 타입, 시크릿 하드코딩, 줄임말 네이밍 등). TDD 누락은 WARNING 으로 분류해 PASS 와 양립.
- **`pr-reviewer` Claude 서브에이전트** (`.claude/agents/pr-reviewer.md`) — 위 커맨드의 4단계 리뷰를 메인 세션 컨텍스트에서 분리해 수행. `tools` 권한은 `Read, Glob, Grep, Bash` 로 한정 (Write/Edit/NotebookEdit 미포함). 코드 수정·PR 코멘트 게시·git 상태 변경은 명시적으로 금지하고, 모든 권장 수정은 보고서 텍스트로만 표현. 시크릿 후보(`password=`, `token=`, `Bearer `, AKIA, JWT 패턴 등) 는 보고서에 인용 시 `***MASKED***` 로 마스킹 의무화.
- **Codex `/pr-reviewer` 프롬프트** (`.codex/prompts/pr-reviewer.md`) — Claude 동명 커맨드와 동일 흐름을 단일 세션에서 수행. Claude 서브에이전트 호출 지점은 `## 인라인 가이드 — PR 리뷰` 섹션으로 치환. 상단에 Codex 세션 특수 조건(.env/시크릿 차단 훅 부재 → 본 흐름이 유일한 마스킹 안전망, `approval_policy="on-request"` 환경에서 `gh` 호출 시 승인 프롬프트 발생 가능) 을 안내.
- **install.sh 의 `/pr-reviewer` 자산 배포** — `--cli=claude` 분기에 `.claude/commands/pr-reviewer.md` 와 `.claude/agents/pr-reviewer.md` 를, `--cli=codex` 분기에 `.codex/prompts/pr-reviewer.md` 를 추가 배포. 모노레포 시나리오에서 Codex 프롬프트는 루트 1회만 배포되는 기존 패턴 그대로 유지.
- **test-harness.sh §4e-3 신규 섹션** — `/pr-reviewer` 자산의 배포·미배포 회귀 + 슬래시 커맨드 frontmatter argument-hint + 7단계/금지 섹션 존재 + Claude 슬래시 커맨드의 `allowed-tools` 화이트리스트(`Edit`/`NotebookEdit` 미포함) + Claude 서브에이전트의 `tools` 화이트리스트(`Write`/`Edit` 미포함) + Codex 인라인 가이드 섹션(`## 인라인 가이드 — PR 리뷰`) 존재를 모두 검증. 4e for 루프의 cmd 리스트(`discuss/plan/execute/ship`) 에도 `pr-reviewer` 를 추가해 prompts 존재·인라인 가이드 섹션·모노레포 미배포 검증이 자동 확장. 본 사이클 종료 시 회귀 통과: PASS=214 / FAIL=0.
- **루트 `CLAUDE.md` §3.1 / §3.2 / §5 갱신** — §3.1 의 흐름 다이어그램을 "4개 → 5개 슬래시 커맨드" 로 확장하고 PR 리뷰 트랙을 별도 블록으로 시각화. §3.2 서브에이전트 표에 `pr-reviewer` 행 추가. §5 Claude/Codex 참고 섹션의 자산 목록에 `pr-reviewer` 반영.

- **Google Gemini CLI 어댑터 지원** — `install.sh --cli` 허용값에 `gemini` 추가 (Claude/Codex 와 콤마 결합 가능, 3-way `--cli=claude,codex,gemini` 지원). `gemini` 포함 시 `GEMINI.md`(CLAUDE.md/AGENTS.md 와 동일 본문, 마커 병합 동일 적용), `.gemini/settings.json`(`{"sandbox": true}` 최소 키 — OS-level sandbox 권장값), `.gemini/commands/{discuss,plan,execute,ship,pr-reviewer}.toml`(Claude/Codex 와 **동일 이름·동일 흐름**, TOML 단일 파일에 `description` + `prompt = """..."""` 로 절차 본문을 인라인 임베드, Claude 서브에이전트 호출 지점은 `## 인라인 가이드` 섹션으로 치환) 을 타깃 루트에만 배포. ADR-013(슬래시 커맨드 TOML 단일 파일 채택), ADR-014(안전장치는 sandbox + soft lock 두 계층, LLM 셀프 grep 검증 기각), ADR-015(GEMINI.md 마커 병합 방식) 신규 등록.
- **모노레포 GEMINI.md 복제** — `--cli=gemini` + 모노레포 스택 스펙(`express:apps/api,...`) 에서 각 앱 경로에 동일 본문의 `GEMINI.md` 생성. `.gemini/settings.json`·`.gemini/commands/*.toml` 은 루트 1회만 배포 (Codex 와 동일 정책).
- **install.sh 마무리 안내 Gemini 분기** — `--cli=gemini` 포함 실행 시 stdout 에 sandbox 권장값 안내, 슬래시 커맨드 자동 바인딩 미검증 사유 + fallback(`@.gemini/commands/<n>.toml`), 하드락 비대칭 경고(위험 명령·`.env` 자동 차단 없음, sandbox + soft lock 만) 3가지 출력.
- **루트 `CLAUDE.md` §4 하드락 갱신 (3-CLI 매트릭스)** — Claude/Codex 2-tier 설명을 Claude/Codex/Gemini 3-tier 표로 확장. Gemini 행에 보호 메커니즘(sandbox + 본 표 soft lock), 자동 차단 범위(호스트·프로젝트 외부 쓰기), 한계(`.env`·프로젝트 내부 위험 명령 자동 차단 없음) 명시. 이 본문이 install.sh 의 merge 소스이므로 3-way 컨텍스트 파일에 동일하게 분배.
- **test-harness.sh §4i 신규 섹션 (GEMINI.md 루트 배포 + Gemini 자산)** — gemini-only / 3-way 혼용 / 모노레포 + Gemini / claude-only·codex-only 시 .gemini/ 부재 / 3-way 마커 본문 일치 (CLAUDE.md ↔ AGENTS.md ↔ GEMINI.md diff 빈 출력) / 각 `commands/*.toml` 의 인라인 가이드 섹션 존재 / `execute.toml` 의 탐색·TDD·리뷰 3종 가이드 존재 / `--cli=bogus` 거부 메시지에 `gemini` 토큰 포함 검증을 추가. 본 사이클 종료 시 회귀 통과: **PASS=269 / FAIL=0** (이전 214 → 269, 55건 증분).
- **README 갱신** — 핵심 구성 표에 Gemini 슬래시 커맨드·기본 설정·컨텍스트 파일 행 신설. 설치 예제에 `--cli=gemini` 단독·3-way 혼용 추가. 신규 섹션 "Gemini 설치 후 할 일 (수동)" — sandbox 검토·슬래시 바인딩 fallback·하드락 비대칭 인지 3가지 안내. 후속 로드맵에서 "Gemini CLI 어댑터 지원" 이관, 신규 항목 2건(슬래시 바인딩 실측 자동화 Gemini 트랙, Gemini 훅 정식 지원 시 하드락 이중화) 등록.

- **OpenAI Codex CLI 어댑터 지원** — `install.sh --cli=<list>` 플래그 신설(허용값 `claude`/`codex`, 콤마 결합, 기본값 `claude`). `codex` 포함 시 `AGENTS.md`(CLAUDE.md 와 동일 본문, 마커 병합 동일 적용), `.codex/config.toml`(ADR-005 기본값: `approval_policy="on-request"`, `sandbox_mode="workspace-write"`, `[sandbox_workspace_write] network_access=true`, 프로젝트 trust 승격 안내 주석), `.codex/prompts/{discuss,plan,execute,ship}.md`(Claude 커맨드와 **동일 이름·동일 흐름**, Claude 서브에이전트 3종 호출 지점을 `## 인라인 가이드 — 병렬 탐색 / 실패 테스트 선 작성 / 커밋 전 리뷰` 섹션으로 치환) 을 타깃 루트에만 배포.
- **모노레포 AGENTS.md 복제** — `--cli=codex` + 모노레포 스택 스펙(`express:apps/api,...`) 에서 각 앱 경로에 `CLAUDE.md` 와 동일 본문의 `AGENTS.md` 생성. `.codex/config.toml`, `.codex/prompts/` 는 루트 1회만 배포(Codex 가 git root 부터 walk).
- **`templates/gitignore.partial` 선제 방어 블록** — `.codex/sessions/`, `.codex/history*`, `.codex/cache/`, `.codex/*.log`, `.codex/config.local.toml` 배제 + `!.codex/config.toml`, `!.codex/prompts/` 화이트리스트. Codex 세션·히스토리·토큰이 실수로 커밋되는 사고를 선제 차단.
- **install.sh 마무리 안내 CLI 분기** — `--cli=codex` 포함 실행 시 stdout 에 `codex projects trust <target>` 과 `~/.codex/config.toml` 의 `[projects.<path>] trust_level="trusted"` 블록을 안내. Codex 세션에 Claude 훅이 없음을 별도 경고.
- **test-harness.sh 대폭 확장 (PASS=167)** — `--cli` 플래그(7종), AGENTS.md 루트 배포·마커 블록 diff·사용자 커스텀 보존, `.codex/config.toml` 키·기본값·gitignore 라인, `.codex/prompts/` 4종과 인라인 가이드 섹션, 스택별 AGENTS.md 복제(모노레포), Codex×NestJS / Codex×SpringBoot(Spotless) / 모노레포×Codex×Spotless, 멱등성(codex×2·claude→codex·codex→claude·마커 블록 본문 수렴) 시나리오 추가.

- **NestJS 스택 지원** — `templates/nestjs/CLAUDE.md` (모듈/컨트롤러/서비스/도메인/인프라 계층, class-validator + ValidationPipe, @RestControllerAdvice 오류 매핑, Jest + supertest 테스트 정책) 와 전용 `templates/nestjs/eslint.config.mjs` (no-floating-promises·no-misused-promises error, 데코레이터 parameter-properties 허용) 추가. 공용 `templates/node/` 와 별도 유지.
- **SpringBoot (Java) 스택 지원** — `templates/springboot/CLAUDE.md` (Java 21 + Spring Boot 3.x + Gradle Kotlin DSL, record 기반 도메인, Flyway 마이그레이션, JUnit5 + Mockito + Testcontainers). `install.sh --with-spotless` 옵트인 시 `spotless.gradle.kts` (google-java-format) 와 `.editorconfig` 가 배포된다.
- **SpringBoot (Kotlin) 스택 지원** — `templates/springboot-kotlin/CLAUDE.md` (Kotlin 1.9+ JVM 21, data class + sealed class, MockK). `--with-spotless` 옵트인 시 ktfmt 기반 스니펫 배포.
- **`install.sh --with-spotless` 옵트인 플래그** — SpringBoot 계열에서만 의미. 기본 off (포매터 미도입). 리포 단위 전역 on/off.
- **하네스 훅**: `flyway clean`, `./gradlew flywayClean`, `flyway:clean`, `liquibase drop-all`, `liquibase:dropAll` 등 운영 DB 파괴 명령을 `block_dangerous.py` 에서 물리적으로 차단. 중간 토큰은 `-<옵션>` 플래그로 제한해 문장 속 우연 매칭 방지.
- `scripts/test-harness.sh`: 신규 스택 3종의 필수 파일 체크, 단일/--with-spotless on/off/모노레포 혼합 시나리오, 잘못된 식별자(`spring-boot`) 거부 검증 추가. `run_scenario` 가 extra_args 를 받도록 확장.

### 변경
- `templates/flutter/CLAUDE.md` 아키텍처 개편 — 이름형 layer-first(`core/`, `config/`, `data/`, `domain/`, `features/`)를 번호형 레이어드 클린 아키텍처(`00_config`~`04_infra`, 단방향 의존 `01→02→03←04`, 배선은 `00_config/di` 에만)로 재작성해 의존 방향을 폴더 구조로 강제. 상태관리는 단일 스택으로 고정하지 않고 Riverpod(권장)/GetX/BLoC 개방(§2 에 라이브러리별 컨트롤러·DI 배치 가이드), 에러 처리·네트워크도 선택지로 유지. `analysis_options.yaml` 은 기술 비의존이라 변경 없음.
- `install.sh` 헤더 동작 설명을 CLI 별 조건부 배포로 정정 (`.claude/` 와 `CLAUDE.md` 는 `--cli` 에 `claude` 가 포함된 경우에만 배포).
- `install.sh --help` 출력을 고정 라인 수(`'1,30p'`) 대신 `set -euo` 센티넬 기반으로 변경 (헤더 주석 분량 변화에 자동 적응).
- `install.sh` 사용법 헤더와 마무리 안내에 신규 스택·`--with-spotless` 설명 반영.
- 루트 `CLAUDE.md` 의 린트/포매터 섹션에 NestJS·SpringBoot(Java/Kotlin) 규약 추가.
- 루트 `CLAUDE.md` "4. 하드락" 섹션에 **Claude 세션 전용** 표기 추가 — Codex 세션은 `approval_policy` / `sandbox_mode` 로만 보호됨을 명시.

### 유의사항 / 후속 이슈
- **Codex 세션 보안 비대칭**: Claude 훅의 위험 명령·**`.env`/시크릿 문자열 쓰기 차단** 은 **Claude 세션 전용**입니다. Codex 세션에서는 `approval_policy="on-request"` 로 샌드박스 경계를 넘을 때만 승인을 요구하며, 시크릿 문자열은 감지되지 않습니다. 시크릿·위험 명령을 다룰 때 각별히 주의하세요.
- **Gemini 세션 보안 비대칭**: Gemini 세션도 Claude 훅의 물리 차단을 받지 않습니다. 보호는 (1) `.gemini/settings.json` 의 OS-level sandbox(`"sandbox": true`) 와 (2) `GEMINI.md` §4 의 에이전트 행동 규칙(soft lock) 두 계층입니다. sandbox 는 호스트 시스템·프로젝트 외부 쓰기를 차단하지만, **프로젝트 내부의 위험 명령 (재귀 강제 삭제·강제 푸시·`.env` 쓰기 등)** 은 모델 준수에 의존하는 soft lock 만 남습니다. ADR-014 가 LLM 셀프 grep 검증을 신뢰 모델 안티패턴으로 기각했으므로, 위험 명령 정식 차단은 Gemini CLI 의 hooks 정식 지원 후 이중화로 처리될 예정.
- **`approval_policy` 의 실제 의미**: "매 명령 승인"이 아니라 샌드박스 경계(프로젝트 밖 쓰기 등)를 넘을 때만 승인. `network_access=true` 는 패키지 관리자·git 원격 연동의 승인 피로감을 줄이기 위한 기본값이며, 보수적으로 조정하려면 `.codex/config.toml` 에서 `false` / `"untrusted"` / `"read-only"` 로 재정의하세요.
- **Codex 슬래시 커맨드 자동 바인딩 미검증** (ADR-004): 사용자 로컬에 Codex CLI 가 없어 본 사이클에서 실측을 수행하지 않았습니다. 설치 후 `/discuss` 가 `.codex/prompts/discuss.md` 로 바인딩되는지 확인하고, 실패 시 `AGENTS.md` 에 `@.codex/prompts/discuss.md 의 절차를 따라 진행` 같은 파일 참조 섹션을 추가해 fallback 으로 사용하세요. 자동화·확정은 후속 이슈(`chore/codex-slash-command-binding-validation`) 로 이관.
- **Gemini 슬래시 커맨드 자동 바인딩 미검증** (Codex 의 ADR-004 와 평행): Gemini CLI 의 커스텀 슬래시 커맨드 자동 바인딩(`.gemini/commands/<n>.toml`)이 공식 사양 수준으로 확정되어 있지 않아 본 사이클에서 실측을 수행하지 않았습니다. 설치 후 `/discuss` 가 `.gemini/commands/discuss.toml` 의 `prompt` 본문으로 바인딩되는지 확인하고, 실패 시 `GEMINI.md` 에 `@.gemini/commands/discuss.toml 의 prompt 절차에 따라 진행` 파일 참조 섹션을 추가해 fallback 으로 사용하세요. 자동화는 후속 이슈(`chore/gemini-slash-command-binding-validation`) 로 이관.
- **기존 설치 사용자 업데이트**: `install.sh --cli=codex` 재실행 시 타깃 `.gitignore` 에 이미 `agent-cairn — 하네스 기본 규칙` 마커가 있으면 **Codex 방어 블록이 자동 추가되지 않습니다**. 해당 블록을 수동으로 `.gitignore` 에 추가하거나, 기존 마커 블록을 제거 후 `install.sh` 를 재실행하세요. Gemini 어댑터는 별도의 `.gemini/` gitignore 방어 블록을 추가하지 않습니다 (Codex 처럼 세션 캐시 파일 형식이 확정되지 않아 — 후속 사이클에서 보강 검토).
- **후속 로드맵**:
  - Codex 훅(`features.codex_hooks`) stable 승격 후 Claude 하드락 이중화.
  - `.codex/agents/*.toml` 네이티브 서브에이전트 배포 (현재는 인라인 가이드로 격하 — ADR-001).
  - `CODEX_CLI_AVAILABLE=1` opt-in 테스트로 슬래시 커맨드 자동 바인딩 검증 자동화 (Codex).
  - `GEMINI_CLI_AVAILABLE=1` opt-in 테스트로 슬래시 커맨드 자동 바인딩 검증 자동화 (Gemini).
  - Gemini 정식 hooks 도입 시 ADR-014 superseded 처리 + `.gemini/hooks/` 이식으로 하드락 이중화.
- **PR 템플릿 변경 없음** — `templates/github/PULL_REQUEST_TEMPLATE.md` 는 CLI 무관.

## [0.3.0] — 2026-04-17

### 변경
- **프로젝트 리네이밍**: `sw2-common-harness` → `agent-cairn`. 오픈소스 공개 준비.
- CLAUDE.md 병합 마커: `<!-- agent-cairn:start/end -->` → `<!-- agent-cairn:start/end -->`.
  이전 버전이 설치된 프로젝트는 `install.sh --force` 로 재설치 필요.
- 문서·스크립트의 프로젝트 참조 전부 갱신.

## [0.2.0] — 2026-04-17

### 추가
- `/plan`, `/execute`, `/ship` 슬래시 커맨드 — PRD 기반 스텝 분해·실행·출고 파이프라인.
- `__docs/plan.json` 스키마 (`templates/__docs/plan.schema.json`) — 스텝 상태 머신(pending/in_progress/completed/error/blocked)과 의존성·재시도 로그 구조.
- Python 훅 이식 (`block_dangerous.py`, `block_secret_files.py`) + pytest 단위·E2E 테스트 47건.
- 시크릿 정규식 모음(`.claude/patterns/secrets.yaml`) — AWS/GitHub/Slack/JWT/Stripe/Private Key 등 16종.
- `Write|Edit` 툴에 대한 PreToolUse 훅 — `.env`·운영 환경파일 직접 쓰기 차단, 시크릿 문자열 작성 차단.
- `scripts/_merge_claude.py` — CLAUDE.md 마커(`<!-- agent-cairn:start/end -->`) 기반 스마트 병합.
- `install.sh` 모노레포 지원 — `--stack=express:apps/api,nextjs:apps/web,flutter:apps/mobile` 형식.
- 각 슬래시 커맨드 내부에 서브에이전트 호출 흐름 명시.
- `__docs/` 템플릿 4종에 작성 지침(HTML 주석) 추가.
- 각 스택 CLAUDE.md 에 "올바른 모양" 코드 예시와 금지 패턴 추가.
- `permissions.deny` 확장: `git clean -f`, `sudo`, `chmod 777`, `curl|sh`, `.env` 쓰기 등.

### 변경
- 훅 실행 인터프리터 bash → python3.
- `CLAUDE.md` 업무 프로세스 섹션을 4-커맨드 파이프라인으로 재구성.
- `install.sh` 가 `templates/__docs/` 와 `plan.schema.json` 을 대상 프로젝트의 `.claude/templates/__docs/` 로 복사 (슬래시 커맨드가 Read 가능하도록).
- `/discuss`, `/plan` 에서 템플릿 참조 경로를 `.claude/templates/__docs/...` 로 수정.

### 수정
- **보안 버그**: `block_dangerous.py` 정규식이 `rm -Rf`, `rm -RF`, `rm -rfv`, `git push --FORCE` 같은 대소문자/verbose 변형을 놓치던 문제. 모든 패턴을 `re.IGNORECASE` 로 재컴파일하고 rm 플래그 덩어리에 추가 문자를 허용.
- `settings.json` 의 `permissions.deny` 에 잘못 포함되어 있던 `git push --force-with-lease --force-if-includes` 제거 (이는 안전한 조합).

### 보강 (부실 영역)
- `templates/__docs/plan.example.json` 추가 — `/plan` 이 참고할 실제 값 예시 (스키마만 있던 공백 보강).
- 시크릿 정규식에 한국/국제 서비스 패턴 추가: Azure Storage, Twilio, SendGrid, Kakao REST/JS Key, NCP Access/Secret Key, Toss Payments.
- `block_secret_files.py` 에 `tests/` 경로의 테스트 파일 content 스캔 면제 추가 (경로 스캔은 유지) — 테스트 픽스쳐가 패턴 매칭 문자열을 포함할 수 있어야 회귀 테스트 작성 가능.
- 하네스 레포 자체 `.gitignore` 신설 (`__pycache__`, `.pytest_cache`, `.claude/settings.local.json` 등).
- `requirements-dev.txt` 신설 — pytest 설치 가이드.
- 테스트 확장: 대소문자 플래그 변형 + 한국 서비스 시크릿 + 테스트 경로 면제. **최종 58건**.

### 제거
- `.claude/hooks/block-dangerous.sh` (Python 버전으로 대체).

## [0.1.0] — 2026-04-17

### 추가
- 초기 하네스 골격: 루트 CLAUDE.md, `/discuss` 슬래시 커맨드, 위험 명령 차단 훅(bash), 3종 서브에이전트(parallel-explorer, tdd-tester, pre-commit-reviewer).
- 스택 템플릿(express/nextjs/flutter) CLAUDE.md.
- `__docs/` 4종 문서 템플릿 (PRD/ARCHITECTURE/ADR/UI_GUIDE).
- Node용 ESLint + Prettier, Flutter용 analysis_options.yaml.
- `scripts/install.sh` 기본 단일 스택 설치.
- GitHub PR 템플릿.

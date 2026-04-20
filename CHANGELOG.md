# Changelog

본 하네스 자체의 변경 이력. Keep-a-Changelog 형식을 따르며, 각 릴리즈에 추가/변경/제거/수정을 명시한다.

## [Unreleased]

### 추가
- **NestJS 스택 지원** — `templates/nestjs/CLAUDE.md` (모듈/컨트롤러/서비스/도메인/인프라 계층, class-validator + ValidationPipe, @RestControllerAdvice 오류 매핑, Jest + supertest 테스트 정책) 와 전용 `templates/nestjs/eslint.config.mjs` (no-floating-promises·no-misused-promises error, 데코레이터 parameter-properties 허용) 추가. 공용 `templates/node/` 와 별도 유지.
- **SpringBoot (Java) 스택 지원** — `templates/springboot/CLAUDE.md` (Java 21 + Spring Boot 3.x + Gradle Kotlin DSL, record 기반 도메인, Flyway 마이그레이션, JUnit5 + Mockito + Testcontainers). `install.sh --with-spotless` 옵트인 시 `spotless.gradle.kts` (google-java-format) 와 `.editorconfig` 가 배포된다.
- **SpringBoot (Kotlin) 스택 지원** — `templates/springboot-kotlin/CLAUDE.md` (Kotlin 1.9+ JVM 21, data class + sealed class, MockK). `--with-spotless` 옵트인 시 ktfmt 기반 스니펫 배포.
- **`install.sh --with-spotless` 옵트인 플래그** — SpringBoot 계열에서만 의미. 기본 off (포매터 미도입). 리포 단위 전역 on/off.
- **하네스 훅**: `flyway clean`, `./gradlew flywayClean`, `flyway:clean`, `liquibase drop-all`, `liquibase:dropAll` 등 운영 DB 파괴 명령을 `block_dangerous.py` 에서 물리적으로 차단. 중간 토큰은 `-<옵션>` 플래그로 제한해 문장 속 우연 매칭 방지.
- `scripts/test-harness.sh`: 신규 스택 3종의 필수 파일 체크, 단일/--with-spotless on/off/모노레포 혼합 시나리오, 잘못된 식별자(`spring-boot`) 거부 검증 추가. `run_scenario` 가 extra_args 를 받도록 확장.

### 변경
- `install.sh` 사용법 헤더와 마무리 안내에 신규 스택·`--with-spotless` 설명 반영.
- 루트 `CLAUDE.md` 의 린트/포매터 섹션에 NestJS·SpringBoot(Java/Kotlin) 규약 추가.

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

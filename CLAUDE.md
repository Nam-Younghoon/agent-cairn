# 팀 공통 하네스 규격 (agent-cairn)

본 문서는 팀 전체 프로젝트(백엔드/웹/모바일)에 공통으로 적용되는 개발·협업 규격입니다.
프로젝트별 CLAUDE.md는 이 문서를 기준으로 확장합니다.

---

## 1. 문서 정리 컨벤션

모든 기능/버그 작업은 브랜치 최상단 `__docs/` 디렉토리에 아래 문서를 작성합니다.
`__docs/`는 브랜치 전용 작업 문서이므로 반드시 `.gitignore`에 포함되어 리모트로 푸시되지 않아야 합니다.

| 파일 | 목적 | 필수 여부 |
| --- | --- | --- |
| `__docs/PRD.md` | 버그/신규 기능의 배경·요구사항·완료 기준 | 필수 |
| `__docs/ARCHITECTURE.md` | 공통 기본 아키텍처와 이번 변경이 그 안에서 어디에 속하는지 | 구조 변경 시 |
| `__docs/ADR.md` | 채택한 결정과 대안·트레이드오프 | 비자명한 의사결정 시 |
| `__docs/UI_GUIDE.md` | 웹/앱 화면 흐름·컴포넌트·상태별 표시 | UI 변경 시 |

UI 요구사항은 분량이 적을 경우 `PRD.md` 내 섹션으로 통합 가능.

---

## 2. 개발 컨벤션

### 2.1 브랜치 전략
- 모든 작업은 `dev` 브랜치에서 분기하여 신규 브랜치에서 진행한다.
- 브랜치 이름: `<type>/<kebab-case-요약>` — type은 conventional commits 규칙을 따른다 (`feat`, `fix`, `chore`, `refactor`, `style`, `docs`, `design`, `test`).
- 예: `feat/login-error-handling`, `fix/user-500-on-login`.

### 2.2 TDD 필수
- **모든 구현은 테스트 코드 작성이 선행**되어야 한다. 실패하는 테스트 → 구현 → 통과 순.
- 테스트 통과 없이는 커밋 금지. 실패 시 커밋을 중단하고 버그를 수정한다.

### 2.3 커밋·롤백 가능성
- 연관 수정 단계별로 작은 단위 커밋을 생성하여 언제든 롤백 가능하게 한다.
- 복수 개의 독립 작업이 병렬로 진행될 때는 `git worktree`로 분리하여 진행한다.
- 커밋 메시지 형식: `type: 제목` + 본문. 본문에는 변경 의도와 주요 변경점을 상세히 기술한다.

```
feat: 사용자 프로필 이미지 업로드 추가

- S3 presigned URL 기반 업로드 구현
- 이미지 크롭/리사이즈 처리 추가
- 5MB 제한 적용
```

### 2.4 린트/포매터
- **Node.js (Express/Next.js)**: ESLint + Prettier. `npm run build && npm run lint`가 커밋 전 통과해야 한다.
- **NestJS**: 전용 `eslint.config.mjs` (공용 Node 설정과 별도). `no-floating-promises`, `no-misused-promises` 를 error 로 유지. 커밋 전 게이트는 동일하게 `npm run build && npm run lint && npm run test`.
- **Flutter**: `flutter analyze` + `dart format`. 경고 0 유지.
- **SpringBoot (Java/Kotlin)**: 포매터는 **기본 off**. 도입 팀은 하네스 설치 시 `install.sh --with-spotless` 를 옵트인하고 커밋 전 게이트에 `spotlessCheck` 를 포함시킨다. Java 는 google-java-format, Kotlin 은 ktfmt.
- TypeScript에서 `any` 금지 → `unknown` 또는 구체 타입 사용.

### 2.5 환경변수·시크릿
- 중요 정보(토큰, DB URL, 키 등)는 **반드시 환경변수로 관리**하고 코드에 하드코딩하지 않는다.
- 새 환경변수 추가 시 동일 커밋에 `.env.example`도 갱신한다.
- `.env`, `.env.local`, `.env.production` 등은 `.gitignore`에 포함.

### 2.6 네이밍
- 변수·함수명은 줄임말이 아닌 의미가 즉시 드러나는 이름을 사용한다.
  - 나쁨: `usrCnt`, `procData`, `h`
  - 좋음: `userCount`, `processUserSignup`, `orderHistory`
- 파일명: Node/Web은 kebab-case(컴포넌트는 PascalCase), Flutter는 snake_case.

---

## 3. 업무 프로세스

### 3.1 전체 흐름 (4개 슬래시 커맨드)

```
 /discuss <설명>   →  PRD/ARCHITECTURE/ADR/(UI_GUIDE) 초안 + 브랜치 생성
       ↓ 사용자 승인
 /plan             →  __docs/plan.json 으로 스텝 분해
       ↓ 사용자 승인
 /execute [next|all|<id>]  →  스텝 단위로 TDD → 구현 → 검증 → 커밋
       ↓ 모든 스텝 completed
 /ship             →  dev 최신화(충돌 시 컨펌) → push → gh pr create
```

각 커맨드의 상세 동작과 서브에이전트 호출 규약은 `.claude/commands/<name>.md` 를 참조한다.

### 3.2 서브에이전트 호출 규약

| 서브에이전트 | 호출 시점 | 금지 |
| --- | --- | --- |
| `parallel-explorer` | `/discuss`, `/plan`, `/execute` 의 초반 컨텍스트 수집 | 코드 수정, 사용자 질문 |
| `tdd-tester` | `/execute` 의 C 단계 (실패 테스트 작성) | 구현체 수정, 테스트 약화 |
| `pre-commit-reviewer` | `/execute` 의 G 단계 (커밋 직전), `/ship` 의 최종 검증 | 직접 수정 (위임만) |

### 3.3 에러 대응 규칙
- 동일 에러 해결을 최대 3회 재시도한다. 이전 실패 메시지를 `plan.json.steps[].error_log` 에 누적한다.
- 3회 이후에도 해결되지 않으면 사용자에게 상황·재현 절차·시도 내역을 공유하고 함께 해결한다.
- 재시도로 해결될 수 없는 외부 요인(API 키 누락, 권한 부족, 네트워크 불가 등) 은 즉시 `blocked` 상태로 기록하고 개입을 요청한다.

### 3.4 dev 최신화·충돌 정책
- **push 직전** 원격 `dev`에 변경이 있는지 확인한다.
- 충돌이 없으면 rebase/merge 후 push.
- 충돌이 있으면 충돌 파일·범위·양쪽 변경 의도를 요약해 사용자에게 공유하고, **컨펌을 받은 후**에만 병합 충돌을 해결한다.

---

## 4. 에이전트 금지 행동 (하드락)

아래 명령은 하네스 훅(`.claude/settings.json`의 `PreToolUse`)에 의해 **자동 차단**됩니다. 에이전트의 약속이 아니라 물리적 차단이며, 어떠한 우회 시도도 허용하지 않습니다.

> **CLI 별 유효 범위 (중요)**
> 이 하드락은 **Claude Code 세션에서만 물리적으로 차단**됩니다. **Codex CLI 세션**에서는 `.codex/config.toml` 의 `approval_policy="on-request"` + `sandbox_mode="workspace-write"` 조합(+ `network_access=true`)으로만 보호되며, 아래 금지 대상을 사용자 승인 한 번으로 통과시킬 수 있습니다. 특히 **`.env`/시크릿 문자열 쓰기 차단** 은 Codex 세션에서 감지되지 않으므로, Codex 에서 시크릿을 다룰 때는 각별히 주의하고 커밋 전 `.gitignore` 와 `block_secret_files.py` 동등 검사를 수동으로 수행하세요. 자세한 배경은 `__docs/ADR-002.md` / `__docs/ADR-005.md` 참조.

| 금지 대상 | 차단 대상 명령 예시 |
| --- | --- |
| 재귀 강제 삭제 | `rm -rf …`, `rm -fr …` |
| 운영 DB 스키마 변경 | 명령 내 `DROP TABLE` 또는 `ALTER TABLE` + `prod` / `production` 식별자 동시 포함 |
| Flyway 파괴 명령 | `flyway clean`, `./gradlew flywayClean`, `flyway:clean` 등 (모든 DB 객체 삭제) |
| Liquibase 파괴 명령 | `liquibase drop-all`, `liquibase dropAll`, `liquibase:dropAll` 등 (관리 테이블 전체 삭제) |
| 강제 푸시 | `git push --force`, `git push -f` (`--force-with-lease`는 허용) |
| 하드 리셋 | `git reset --hard` |

신규 기능 개발 중 DB 스키마 변경은 **마이그레이션 도구**(Prisma Migrate, TypeORM Migration, Flyway, Liquibase 등)의 **안전한 서브커맨드**(`migrate`, `update`, `info`, `validate`)로만 수행하며, 운영 DB에 직접 ad-hoc SQL 을 실행하거나 `clean`/`drop-all` 같은 파괴 커맨드를 호출하지 않습니다.

---

## 5. 참고

### Claude Code
- `.claude/commands/discuss.md` — `/discuss` 슬래시 커맨드 정의
- `.claude/agents/` — 병렬 탐색·TDD·리뷰 전용 서브에이전트
- `.claude/hooks/`, `.claude/patterns/secrets.yaml` — 위험 명령 / 시크릿 쓰기 하드락

### Codex CLI (ADR-001, ADR-004, ADR-005)
- `.codex/prompts/{discuss,plan,execute,ship}.md` — Claude 커맨드와 동일 이름·동일 흐름.
  Claude 서브에이전트(parallel-explorer/tdd-tester/pre-commit-reviewer) 호출 지점을
  `## 인라인 가이드 —` 섹션으로 치환해 Codex 단일 세션에서 직접 수행.
- `.codex/config.toml` — `approval_policy="on-request"` + `sandbox_mode="workspace-write"` +
  `network_access=true` 기본값. 보수 모드 재정의 예시 주석 포함.
- 슬래시 커맨드 자동 바인딩은 본 사이클에서 실측하지 않음. 실패 시 `AGENTS.md` 에
  `@.codex/prompts/<name>.md 의 절차를 따라 진행` 같은 파일 참조로 fallback 가능.

### 공통
- `templates/` — 프로젝트 유형별 시작 템플릿 (Claude `CLAUDE.md` 와 Codex `AGENTS.md` 공용 본문)
- `scripts/install.sh` — 신규 프로젝트에 하네스 주입. `--cli=<list>` 로 배포 대상 CLI 선택 (기본값 `claude`, `claude,codex` 혼용 가능)

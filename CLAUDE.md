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

### 2.7 워크트리 — 멀티 세션 격리
한 레포에서 여러 AI 세션을 **동시에** 굴려 병렬 작업할 때는, 세션마다 별도 git worktree(독립 HEAD/작업 트리)에서 시작한다. 단일 디렉토리에서 여러 세션이 같은 HEAD 를 공유하면 `/discuss` 의 브랜치 전환이 서로 간섭하기 때문이다(ADR-016). 워크트리는 **세션 실행 시점에** 만든다 — 커맨드는 이미 격리된 곳에서 도는 것만 책임진다.

- **세션 띄우기 (작업 하나만이면 생략 가능 — 단일 디렉토리에서도 동작 호환)**
  - **Claude Code**: `claude --worktree <name>` — `.claude/worktrees/<name>/` 에 워크트리 생성, `.worktreeinclude` 파일 자동 복사, 종료 시 자동 정리.
  - **Codex / Gemini**: `scripts/worktree.sh new <task> [base]` → `.worktrees/<task>` 생성 + `.worktreeinclude` 승계 복사. 그 안에서 세션을 띄운다.
    > 이 헬퍼는 `install.sh --with-worktree` 로 설치한 프로젝트에만 존재한다. 없으면 `install.sh --with-worktree` 를 다시 실행하거나 `git worktree add` 를 직접 사용한다.
- **진입 후**: 평소처럼 `/discuss → /plan → /execute → /ship`. `/discuss` 는 `git switch -c <branch> origin/<base>` 로 base 를 로컬 체크아웃하지 않아 워크트리에서도 dual-checkout `fatal` 이 없다(ADR-017).
- **`/new` 재사용**: 한 워크트리에서 작업을 마치면(`/ship` 또는 커밋해 clean 상태로 둔 뒤) `/new` 로 대화만 비우고 다음 작업을 맡겨도 된다. `/new` 는 git 상태를 건드리지 않으므로 **다음 작업 시작 전 워크트리가 clean 한지 확인**한다.
- **정리**: PR 머지 후 `/ship` 7단계 안내대로 워크트리를 제거한다(Claude 네이티브 자동 / `scripts/worktree.sh clean <task>`).
- `.claude/worktrees/`·`.worktrees/` 는 `.gitignore` 에 포함되어 추적되지 않는다.

---

## 3. 업무 프로세스

### 3.1 전체 흐름 (5개 슬래시 커맨드)

**신규 작업 파이프라인 (4개)**

```
 /discuss <설명>   →  PRD/ARCHITECTURE/ADR/(UI_GUIDE) 초안 + 브랜치 생성
       ↓ 사용자 승인
 /plan             →  __docs/plan.json 으로 스텝 분해
       ↓ 사용자 승인
 /execute [next|all|<id>]  →  스텝 단위로 TDD → 구현 → 검증 → 커밋
       ↓ 모든 스텝 completed
 /ship             →  dev 최신화(충돌 시 컨펌) → push → gh pr create
```

**PR 리뷰 트랙 (독립)**

```
 /pr-reviewer <PR번호> [추가 메시지]
       ↓ gh CLI 사전 검증 (가용성·인증·origin·PR state)
       ↓ 4단계 리뷰 (컨텍스트 수집 → 요구사항 검증 → 사이드 이펙트 분석 → 전사 재검수)
       ↓ __docs/pr-review-<PR번호>.md 저장 + 콘솔 요약 (PASS|BLOCK)
       ↓ 사용자 컨펌 (yes/no/dry-run)
       ↓ PR 코멘트 게시: line-level (gh api) + 종합 (gh pr comment)
```

각 커맨드의 상세 동작과 서브에이전트 호출 규약은 `.claude/commands/<name>.md` 를 참조한다.

### 3.2 서브에이전트 호출 규약

| 서브에이전트 | 호출 시점 | 금지 |
| --- | --- | --- |
| `parallel-explorer` | `/discuss`, `/plan`, `/execute` 의 초반 컨텍스트 수집 | 코드 수정, 사용자 질문 |
| `tdd-tester` | `/execute` 의 C 단계 (실패 테스트 작성) | 구현체 수정, 테스트 약화 |
| `pre-commit-reviewer` | `/execute` 의 G 단계 (커밋 직전), `/ship` 의 최종 검증 | 직접 수정 (위임만) |
| `pr-reviewer` | `/pr-reviewer` 의 리뷰 단계 (4단계 전 과정 위임) | 코드 수정, PR 코멘트 게시, git 상태 변경 |

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

본 섹션의 표는 **모든 CLI 세션에서 금지되는 명령 패턴**을 정의합니다. Claude Code 세션에서는 하네스 훅(`.claude/settings.json`의 `PreToolUse`)이 이를 **물리적으로 차단** 합니다 — 에이전트의 약속이 아니라 차단이며, 어떠한 우회 시도도 허용하지 않습니다. Codex / Gemini 세션은 OS 샌드박스와 본 표를 따르는 soft lock 두 계층으로 보호되며, 어떤 세션에서도 아래 명령은 호출해서는 안 됩니다.

> **CLI 별 유효 범위 (중요)**
>
> | CLI | 보호 메커니즘 | 자동 차단 범위 | 한계 |
> | --- | --- | --- | --- |
> | **Claude Code** | `.claude/hooks/*.py` (PreToolUse) | 본 표 전체 + `.env`/시크릿 문자열 쓰기 | 훅 우회 불가 — 가장 강력 |
> | **Codex CLI** | `approval_policy="on-request"` + `sandbox_mode="workspace-write"` | 샌드박스 경계를 넘는 쓰기·네트워크 | 본 표는 사용자 승인 1회로 통과 가능. `.env`/시크릿 문자열 쓰기 자동 감지 없음 |
> | **Gemini CLI** | `.gemini/settings.json` `"sandbox": true` + 본 표(soft lock) | 호스트 시스템·프로젝트 외부 쓰기 | 본 표는 행동 규칙으로만 강제. `.env`/시크릿 쓰기·프로젝트 내부 `rm -rf` 자동 차단 없음 |
>
> 자세한 배경은 `__docs/ADR.md` 의 ADR-002·005(Codex), ADR-013~015(Gemini) 를 참조하세요. Codex / Gemini 세션에서 시크릿이나 위험 명령을 다룰 때는 각별히 주의하고, 커밋 전 `.gitignore` 와 `block_secret_files.py` 동등 검사를 수동으로 수행하세요.

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
- `.claude/commands/pr-reviewer.md` — `/pr-reviewer` 슬래시 커맨드 정의 (PR 리뷰 트랙)
- `.claude/agents/` — 병렬 탐색·TDD·리뷰 전용 서브에이전트 (`parallel-explorer`, `tdd-tester`, `pre-commit-reviewer`, `pr-reviewer`)
- `.claude/hooks/`, `.claude/patterns/secrets.yaml` — 위험 명령 / 시크릿 쓰기 하드락

### Codex CLI (ADR-001, ADR-004, ADR-005)
- `.codex/prompts/{discuss,plan,execute,ship,pr-reviewer}.md` — Claude 커맨드와 동일 이름·동일 흐름.
  Claude 서브에이전트(parallel-explorer/tdd-tester/pre-commit-reviewer/pr-reviewer) 호출 지점을
  `## 인라인 가이드 —` 섹션으로 치환해 Codex 단일 세션에서 직접 수행.
- `.codex/config.toml` — `approval_policy="on-request"` + `sandbox_mode="workspace-write"` +
  `network_access=true` 기본값. 보수 모드 재정의 예시 주석 포함.
- 슬래시 커맨드 자동 바인딩은 본 사이클에서 실측하지 않음. 실패 시 `AGENTS.md` 에
  `@.codex/prompts/<name>.md 의 절차를 따라 진행` 같은 파일 참조로 fallback 가능.

### Gemini CLI (ADR-013, ADR-014, ADR-015)
- `.gemini/commands/{discuss,plan,execute,ship,pr-reviewer}.toml` — Claude/Codex 와 동일 이름·동일 흐름.
  TOML 단일 파일에 `description = "..."` + `prompt = """..."""` 두 키만 두고, `prompt` 본문에
  Codex 의 `.codex/prompts/<n>.md` 와 동일한 절차를 인라인 임베드 (ADR-013). Claude 서브에이전트
  호출 지점은 Codex 와 동일하게 `## 인라인 가이드 —` 섹션으로 치환.
- `.gemini/settings.json` — `{"sandbox": true}` 최소 키. Gemini CLI 의 OS-level sandbox 권장값.
  비활성화 시 위험 명령·`.env` 보호가 GEMINI.md §4 soft lock 만 남음 (ADR-014).
- 슬래시 커맨드 자동 바인딩은 본 사이클에서 실측하지 않음. 실패 시 `GEMINI.md` 에
  `@.gemini/commands/<n>.toml 의 prompt 절차에 따라 진행` 같은 파일 참조로 fallback 가능.
- 안전장치 정책: LLM 셀프 grep 검증은 신뢰 모델 안티패턴으로 기각 (ADR-014). 향후 Gemini hooks
  정식 지원 시 `.gemini/hooks/` 로 이중화하고 ADR-014 를 superseded 처리할 예정.

### 공통
- `templates/` — 프로젝트 유형별 시작 템플릿 (Claude `CLAUDE.md` 와 Codex `AGENTS.md` 공용 본문)
- `scripts/install.sh` — 신규 프로젝트에 하네스 주입. `--cli=<list>` 로 배포 대상 CLI 선택 (기본값 `claude`, `claude,codex` 혼용 가능). `--with-worktree` 로 워크트리 격리 자산 옵트인 배포.
- `scripts/worktree.sh`, `templates/worktreeinclude.partial` — git worktree 멀티 세션 격리(§2.7). Claude 네이티브 `--worktree` / Codex·Gemini 헬퍼 `new|list|clean` (ADR-016~019)

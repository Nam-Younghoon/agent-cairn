# agent-cairn

여러 프레임워크를 위한 올인원 개발 하네스. 현재는 Claude Code 기반으로 백엔드(Express)·웹(Next.js)·모바일(Flutter) 프로젝트에 동일한 컨벤션·프로세스·안전장치·파이프라인을 주입합니다.

## 핵심 구성

| 구성요소 | 위치 | 설명 |
| --- | --- | --- |
| 팀 규격 본문 | `CLAUDE.md` | 문서/개발 컨벤션, 업무 프로세스, 금지 행동 |
| 위험 명령 차단 훅 (Bash) | `.claude/hooks/block_dangerous.py` | `rm -rf`·`git force push`·`git reset --hard`·`sudo`·`chmod 777`·`curl\|sh`·운영 DB 스키마 변경 등 차단 |
| 시크릿 차단 훅 (Write/Edit) | `.claude/hooks/block_secret_files.py` | `.env` 등 시크릿 파일 쓰기, 시크릿 문자열이 포함된 파일 쓰기 차단 |
| 시크릿 정규식 | `.claude/patterns/secrets.yaml` | AWS/GitHub/Slack/JWT/Stripe/Private Key 등 16종 |
| 슬래시 커맨드 | `.claude/commands/{discuss,plan,execute,ship}.md` | 4-커맨드 파이프라인 |
| 서브에이전트 | `.claude/agents/{parallel-explorer,tdd-tester,pre-commit-reviewer}.md` | 탐색·TDD·리뷰 전용 |
| 스택별 CLAUDE.md | `templates/{express,nextjs,flutter}/CLAUDE.md` | 아키텍처·스크립트·테스트 정책 + 올바른 모양 예시 |
| 문서 템플릿 | `templates/__docs/` | PRD / ARCHITECTURE / ADR / UI_GUIDE / plan.schema.json |
| 린트/포매터 | `templates/node/`, `templates/flutter/analysis_options.yaml` | ESLint(flat) + Prettier, analysis_options |
| PR 템플릿 | `templates/github/PULL_REQUEST_TEMPLATE.md` | 하네스 체크리스트 포함 |
| 설치 스크립트 | `scripts/install.sh` | 단일·다중·모노레포 스택 지원, 마커 기반 스마트 병합 |
| 셀프 테스트 | `scripts/test-harness.sh`, `tests/` | pytest + 설치 시나리오 회귀 검사 |

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

# 단일 스택
/tmp/agent-cairn/scripts/install.sh --stack=express --target=/path/to/project

# 한 프로젝트에 여러 스택 (예: 풀스택 개인 프로젝트)
/tmp/agent-cairn/scripts/install.sh --stack=express,nextjs,flutter --target=/path/to/project

# 모노레포 (앱별 경로)
/tmp/agent-cairn/scripts/install.sh \
  --stack='express:apps/api,nextjs:apps/web,flutter:apps/mobile' \
  --target=/path/to/monorepo
```

옵션:
- `--stack=<spec>` (필수): 위 세 가지 중 하나.
- `--target=<경로>` (기본: 현재 디렉토리).
- `--force`: 기존 파일 덮어쓰기 허용 (CLAUDE.md 는 마커 구간만 덮어써도 되므로 대부분 불필요).

설치 후 자동으로 수행되는 것:
1. `.claude/` (settings, hooks, patterns, commands, agents) 배포.
2. `CLAUDE.md` 생성 또는 **마커 기반 병합** — `<!-- agent-cairn:start -->` 안쪽만 교체, 바깥쪽 사용자 커스텀 보존.
3. `.gitignore` 에 하네스 블록 추가 (`__docs/`, `.env` 등).
4. `.env.example` 배포.
5. 스택별 린트/포매터 설정 배포.
6. `.github/PULL_REQUEST_TEMPLATE.md` 배포.

## 하드락 (훅이 자동 차단)

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

- **스택 추가**: `templates/<new-stack>/CLAUDE.md` 추가, `install.sh` 의 `validate_stack` 케이스 확장.
- **규약 수정**: `CLAUDE.md` 본문 수정 후 각 프로젝트에서 `install.sh` 재실행(마커 안쪽만 교체됨).
- **시크릿 패턴 추가**: `.claude/patterns/secrets.yaml` 에 정규식 추가, `tests/test_block_secret_files.py` 에 테스트 케이스 추가.
- **새 위험 패턴 차단**: `.claude/hooks/block_dangerous.py` 의 `evaluate()` 에 규칙 추가 + `tests/test_block_dangerous.py` 에 케이스 추가.

## 제약과 주의사항

- 운영 DB 차단은 **휴리스틱** (명령 텍스트에 `prod`/`production` 키워드 동반 필요). 정식 보호는 네트워크 분리·IAM·읽기전용 커넥션이 담당해야 합니다.
- `/discuss` 는 `dev` 브랜치가 존재한다고 가정합니다. 초기 리포는 기준 브랜치를 수동 지정.
- 복사 배포 모델이므로 하네스 업데이트 후 각 프로젝트에 `install.sh` 재실행이 필요합니다. 마커 덕분에 사용자 커스텀은 보존됩니다.

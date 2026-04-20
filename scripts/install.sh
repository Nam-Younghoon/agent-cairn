#!/usr/bin/env bash
# agent-cairn 설치 스크립트
#
# 사용법:
#   ./scripts/install.sh --stack=<stack-spec> [--target=<repo-root>] [--force] [--with-spotless]
#
# stack-spec 형식:
#   1) 단일 스택            : --stack=express
#   2) 모노레포(한 루트 다중): --stack=express,nextjs,flutter,nestjs
#   3) 모노레포(앱별 경로)   : --stack=express:apps/api,nestjs:apps/api-nest,springboot:apps/api-java
#
# 지원 스택: express | nextjs | flutter | nestjs | springboot | springboot-kotlin
#
# 옵션:
#   --cli=<list>    : 배포할 CLI 어댑터 (claude | codex, 콤마 결합 가능).
#                     기본값: claude. 예: --cli=codex 또는 --cli=claude,codex
#   --with-spotless : SpringBoot(Java/Kotlin) 스택에 Spotless 포매터 스니펫과
#                     .editorconfig 를 배포한다. 기본은 포매터 없음.
#
# 동작:
#   - --cli 에 명시된 CLI 어댑터 자산만 --target (리포지토리 루트) 에 설치한다.
#     · claude 포함 시: .claude/ 자산 + 루트 CLAUDE.md
#     · codex 포함 시: 루트 AGENTS.md (+ 이후 스텝에서 .codex/)
#   - 스택 스펙에 경로가 있으면 해당 경로에도 CLAUDE.md 와 스택별 린트 설정을 추가 설치.
#   - CLAUDE.md/AGENTS.md 는 <!-- agent-cairn:start --> ... <!-- agent-cairn:end -->
#     마커 기반으로 스마트 병합된다. 사용자가 마커 밖에 추가한 내용은 보존된다.

set -euo pipefail

STACK_SPEC=""
TARGET="$(pwd)"
FORCE=0
WITH_SPOTLESS=0
CLI_SPEC="claude"  # 기본값. 허용값: claude | codex (콤마 결합 가능)

for arg in "$@"; do
  case $arg in
    --stack=*)       STACK_SPEC="${arg#*=}" ;;
    --target=*)      TARGET="${arg#*=}" ;;
    --cli=*)         CLI_SPEC="${arg#*=}" ;;
    --force)         FORCE=1 ;;
    --with-spotless) WITH_SPOTLESS=1 ;;
    -h|--help)
      # 헤더 주석만 출력: set -euo 라인을 만나면 종료
      sed -n '/^set -euo/q;p' "$0"
      exit 0
      ;;
    *)
      echo "알 수 없는 옵션: $arg" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$STACK_SPEC" ]]; then
  echo "오류: --stack=<stack-spec> 를 지정해야 합니다." >&2
  exit 1
fi

# --cli 파싱 + 허용값 검증
if [[ -z "${CLI_SPEC// /}" ]]; then
  echo "오류: --cli 값이 비어 있습니다. (허용: claude, codex / 콤마 결합)" >&2
  exit 1
fi
IFS=',' read -r -a CLIS <<< "$CLI_SPEC"
for cli in "${CLIS[@]}"; do
  case "$cli" in
    claude|codex) ;;
    "")
      echo "오류: --cli 값에 빈 항목이 포함되어 있습니다." >&2
      exit 1
      ;;
    *)
      echo "오류: 지원하지 않는 --cli 값: '$cli' (허용: claude, codex)" >&2
      exit 1
      ;;
  esac
done

# 이후 스텝에서 CLI 별 배포 분기에 사용.
has_cli() {
  local needle="$1"
  for c in "${CLIS[@]}"; do
    [[ "$c" == "$needle" ]] && return 0
  done
  return 1
}

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$TARGET"
TARGET="$(cd "$TARGET" && pwd)"
FORCE_FLAG=""
[[ $FORCE -eq 1 ]] && FORCE_FLAG="--force"

echo "[install] harness=$HARNESS_DIR"
echo "[install] target=$TARGET"
echo "[install] stack-spec=$STACK_SPEC"
echo "[install] cli=${CLIS[*]}"
echo "[install] with-spotless=$([[ $WITH_SPOTLESS -eq 1 ]] && echo on || echo off)"

# ---- 유틸 ------------------------------------------------------------------

copy_file() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -e "$dst" && $FORCE -ne 1 ]]; then
    echo "  [skip] 존재함: $dst"
    return
  fi
  cp "$src" "$dst"
  echo "  [copy] $dst"
}

append_if_missing() {
  local src_block_file="$1" dst="$2" marker="$3"
  if [[ -f "$dst" ]] && grep -qF "$marker" "$dst"; then
    echo "  [skip] 이미 포함된 블록: $dst"
    return
  fi
  mkdir -p "$(dirname "$dst")"
  printf '\n' >> "$dst"
  cat "$src_block_file" >> "$dst"
  echo "  [append] $dst"
}

validate_stack() {
  case "$1" in
    express|nextjs|flutter|nestjs|springboot|springboot-kotlin) ;;
    *)
      echo "오류: 지원하지 않는 stack: $1" >&2
      exit 1
      ;;
  esac
}

install_node_lint() {
  local dst_dir="$1"
  copy_file "$HARNESS_DIR/templates/node/eslint.config.mjs" "$dst_dir/eslint.config.mjs"
  copy_file "$HARNESS_DIR/templates/node/.prettierrc.json"  "$dst_dir/.prettierrc.json"
  copy_file "$HARNESS_DIR/templates/node/.prettierignore"   "$dst_dir/.prettierignore"
}

install_nestjs_lint() {
  # NestJS 는 공용 node 린트 대신 전용 eslint.config.mjs 를 사용한다.
  local dst_dir="$1"
  copy_file "$HARNESS_DIR/templates/nestjs/eslint.config.mjs" "$dst_dir/eslint.config.mjs"
  copy_file "$HARNESS_DIR/templates/node/.prettierrc.json"    "$dst_dir/.prettierrc.json"
  copy_file "$HARNESS_DIR/templates/node/.prettierignore"     "$dst_dir/.prettierignore"
}

install_flutter_lint() {
  local dst_dir="$1"
  copy_file "$HARNESS_DIR/templates/flutter/analysis_options.yaml" "$dst_dir/analysis_options.yaml"
}

install_springboot_spotless() {
  # Java 템플릿의 Spotless 스니펫 + .editorconfig. --with-spotless 가 켜진 경우만 호출.
  local dst_dir="$1"
  copy_file "$HARNESS_DIR/templates/springboot/spotless.gradle.kts" "$dst_dir/spotless.gradle.kts"
  copy_file "$HARNESS_DIR/templates/springboot/.editorconfig"       "$dst_dir/.editorconfig"
}

install_springboot_kotlin_spotless() {
  # Kotlin 템플릿의 Spotless 스니펫 + .editorconfig. --with-spotless 가 켜진 경우만 호출.
  local dst_dir="$1"
  copy_file "$HARNESS_DIR/templates/springboot-kotlin/spotless.gradle.kts" "$dst_dir/spotless.gradle.kts"
  copy_file "$HARNESS_DIR/templates/springboot-kotlin/.editorconfig"       "$dst_dir/.editorconfig"
}

merge_claude() {
  local target_file="$1" source_file="$2"
  python3 "$HARNESS_DIR/scripts/_merge_claude.py" "$target_file" "$source_file" $FORCE_FLAG
}

# ---- 1) 루트 공통 자산 (CLI 무관: .gitignore / .env.example / PR 템플릿) ----

echo "[install] 루트 공통 자산 배포"

copy_file "$HARNESS_DIR/templates/github/PULL_REQUEST_TEMPLATE.md" "$TARGET/.github/PULL_REQUEST_TEMPLATE.md"

append_if_missing "$HARNESS_DIR/templates/gitignore.partial" \
                  "$TARGET/.gitignore" \
                  "agent-cairn — 하네스 기본 규칙"

if [[ ! -f "$TARGET/.env.example" || $FORCE -eq 1 ]]; then
  copy_file "$HARNESS_DIR/templates/env.example" "$TARGET/.env.example"
fi

# ---- 1a) Claude 전용 자산 (.claude/) ---------------------------------------
# CLIS 에 claude 가 포함된 경우에만 배포.

if has_cli claude; then
  echo "[install] .claude/ 자산 배포 (Claude)"

  copy_file "$HARNESS_DIR/.claude/settings.json"                   "$TARGET/.claude/settings.json"
  copy_file "$HARNESS_DIR/.claude/hooks/block_dangerous.py"        "$TARGET/.claude/hooks/block_dangerous.py"
  copy_file "$HARNESS_DIR/.claude/hooks/block_secret_files.py"     "$TARGET/.claude/hooks/block_secret_files.py"
  copy_file "$HARNESS_DIR/.claude/patterns/secrets.yaml"           "$TARGET/.claude/patterns/secrets.yaml"
  copy_file "$HARNESS_DIR/.claude/commands/discuss.md"             "$TARGET/.claude/commands/discuss.md"
  copy_file "$HARNESS_DIR/.claude/commands/plan.md"                "$TARGET/.claude/commands/plan.md"
  copy_file "$HARNESS_DIR/.claude/commands/execute.md"             "$TARGET/.claude/commands/execute.md"
  copy_file "$HARNESS_DIR/.claude/commands/ship.md"                "$TARGET/.claude/commands/ship.md"
  copy_file "$HARNESS_DIR/.claude/agents/tdd-tester.md"            "$TARGET/.claude/agents/tdd-tester.md"
  copy_file "$HARNESS_DIR/.claude/agents/parallel-explorer.md"     "$TARGET/.claude/agents/parallel-explorer.md"
  copy_file "$HARNESS_DIR/.claude/agents/pre-commit-reviewer.md"   "$TARGET/.claude/agents/pre-commit-reviewer.md"

  # 슬래시 커맨드가 참조하는 문서 템플릿. 대상 프로젝트 안에서 Read 가능해야 한다.
  copy_file "$HARNESS_DIR/templates/__docs/PRD.md"                "$TARGET/.claude/templates/__docs/PRD.md"
  copy_file "$HARNESS_DIR/templates/__docs/ARCHITECTURE.md"       "$TARGET/.claude/templates/__docs/ARCHITECTURE.md"
  copy_file "$HARNESS_DIR/templates/__docs/ADR.md"                "$TARGET/.claude/templates/__docs/ADR.md"
  copy_file "$HARNESS_DIR/templates/__docs/UI_GUIDE.md"           "$TARGET/.claude/templates/__docs/UI_GUIDE.md"
  copy_file "$HARNESS_DIR/templates/__docs/plan.schema.json"      "$TARGET/.claude/templates/__docs/plan.schema.json"
  copy_file "$HARNESS_DIR/templates/__docs/plan.example.json"     "$TARGET/.claude/templates/__docs/plan.example.json"
fi

# ---- 1b) Codex 전용 자산 (.codex/) ------------------------------------------
# CLIS 에 codex 가 포함된 경우에만 배포. 타깃 리포지토리 루트에만 1회 배포한다
# (Codex 는 git root 부터 walk 하므로 모노레포 앱 경로에는 중복 배포하지 않음).

if has_cli codex; then
  echo "[install] .codex/ 자산 배포 (Codex)"
  copy_file "$HARNESS_DIR/.codex/config.toml"         "$TARGET/.codex/config.toml"
  copy_file "$HARNESS_DIR/.codex/prompts/discuss.md"  "$TARGET/.codex/prompts/discuss.md"
  copy_file "$HARNESS_DIR/.codex/prompts/plan.md"     "$TARGET/.codex/prompts/plan.md"
  copy_file "$HARNESS_DIR/.codex/prompts/execute.md"  "$TARGET/.codex/prompts/execute.md"
  copy_file "$HARNESS_DIR/.codex/prompts/ship.md"     "$TARGET/.codex/prompts/ship.md"
fi

# ---- 2) 스택 스펙 파싱 -----------------------------------------------------

IFS=',' read -r -a STACK_ENTRIES <<< "$STACK_SPEC"

declare -a STACKS
declare -a PATHS
ANY_NODE=0
ANY_NESTJS=0
ANY_FLUTTER=0
ANY_SPRING_JAVA=0
ANY_SPRING_KOTLIN=0
HAS_PATH_SPEC=0

for entry in "${STACK_ENTRIES[@]}"; do
  entry_trimmed="$(echo "$entry" | xargs)"  # trim
  if [[ "$entry_trimmed" == *:* ]]; then
    stack="${entry_trimmed%%:*}"
    sub_path="${entry_trimmed#*:}"
    HAS_PATH_SPEC=1
  else
    stack="$entry_trimmed"
    sub_path=""
  fi
  validate_stack "$stack"
  STACKS+=("$stack")
  PATHS+=("$sub_path")
  case "$stack" in
    express|nextjs)     ANY_NODE=1 ;;
    nestjs)             ANY_NESTJS=1 ;;
    flutter)            ANY_FLUTTER=1 ;;
    springboot)         ANY_SPRING_JAVA=1 ;;
    springboot-kotlin)  ANY_SPRING_KOTLIN=1 ;;
  esac
done

# ---- 3) 루트 규약 문서 병합 (CLI 별 타깃) ---------------------------------

echo "[install] 루트 규약 문서 병합"

tmp_root_content="$(mktemp)"
{
  cat "$HARNESS_DIR/CLAUDE.md"
  # 경로 지정이 없으면(단일 루트 또는 다중 스택 한 프로젝트) 스택 규격을 함께 병합.
  if [[ $HAS_PATH_SPEC -eq 0 ]]; then
    for stack in "${STACKS[@]}"; do
      echo
      echo "---"
      echo
      cat "$HARNESS_DIR/templates/$stack/CLAUDE.md"
    done
  else
    # 모노레포: 각 앱 경로를 색인만 해둠.
    echo
    echo "---"
    echo
    echo "## 이 리포의 앱 배치"
    for i in "${!STACKS[@]}"; do
      echo "- \`${PATHS[$i]}\` — ${STACKS[$i]}"
    done
    echo
    echo "앱별 세부 규격은 해당 디렉토리의 CLAUDE.md 를 참조한다."
  fi
} > "$tmp_root_content"

# Claude: CLAUDE.md / Codex: AGENTS.md — 동일 본문을 CLI 별 타깃에 분배
if has_cli claude; then
  merge_claude "$TARGET/CLAUDE.md" "$tmp_root_content"
fi
if has_cli codex; then
  merge_claude "$TARGET/AGENTS.md" "$tmp_root_content"
fi
rm -f "$tmp_root_content"

# ---- 4) 스택별 설치 --------------------------------------------------------

if [[ $HAS_PATH_SPEC -eq 0 ]]; then
  # 루트 1곳에 린트/포매터 설정 설치
  if [[ $ANY_NODE -eq 1 ]]; then
    install_node_lint "$TARGET"
  elif [[ $ANY_NESTJS -eq 1 ]]; then
    # NestJS 만 설치하는 경우 전용 eslint.config.mjs 를 사용한다.
    install_nestjs_lint "$TARGET"
  fi
  [[ $ANY_FLUTTER -eq 1 ]] && install_flutter_lint "$TARGET"
  if [[ $WITH_SPOTLESS -eq 1 ]]; then
    [[ $ANY_SPRING_JAVA -eq 1 ]]   && install_springboot_spotless "$TARGET"
    [[ $ANY_SPRING_KOTLIN -eq 1 ]] && install_springboot_kotlin_spotless "$TARGET"
  fi
else
  # 모노레포: 경로별 CLAUDE.md/AGENTS.md + 경로별 린트/포매터 설정
  for i in "${!STACKS[@]}"; do
    stack="${STACKS[$i]}"
    sub_path="${PATHS[$i]}"
    app_dir="$TARGET/$sub_path"
    mkdir -p "$app_dir"
    echo "[install] 앱 설치 ($stack → $sub_path)"
    if has_cli claude; then
      merge_claude "$app_dir/CLAUDE.md" "$HARNESS_DIR/templates/$stack/CLAUDE.md"
    fi
    if has_cli codex; then
      merge_claude "$app_dir/AGENTS.md" "$HARNESS_DIR/templates/$stack/CLAUDE.md"
    fi
    case "$stack" in
      express|nextjs)     install_node_lint "$app_dir" ;;
      nestjs)             install_nestjs_lint "$app_dir" ;;
      flutter)            install_flutter_lint "$app_dir" ;;
      springboot)
        [[ $WITH_SPOTLESS -eq 1 ]] && install_springboot_spotless "$app_dir"
        ;;
      springboot-kotlin)
        [[ $WITH_SPOTLESS -eq 1 ]] && install_springboot_kotlin_spotless "$app_dir"
        ;;
    esac
  done
fi

# ---- 5) 마무리 안내 --------------------------------------------------------

cat <<EOF

[install] 완료.
EOF

if has_cli claude; then
  cat <<EOF

[Claude Code] 다음 단계:
  1. 프로젝트를 열고 Claude Code 를 실행합니다.
  2. /discuss <작업 내용> 으로 요구사항 논의를 시작합니다.
  3. 승인 후 /plan → /execute → /ship 순으로 진행합니다.
EOF
fi

if has_cli codex; then
  cat <<EOF

[Codex CLI] 다음 단계:
  1. 프로젝트를 Codex CLI 로 엽니다. 최초 1회 프로젝트 신뢰 승격이 필요합니다:
       codex projects trust $TARGET
     또는 ~/.codex/config.toml 에 다음 블록을 추가하세요:
       [projects."$TARGET"]
       trust_level = "trusted"
  2. /discuss <작업 내용> 으로 요구사항 논의를 시작합니다.
     슬래시 커맨드가 자동 바인딩되지 않으면 @.codex/prompts/discuss.md 의 절차를 따르도록 요청해주세요.
  3. 승인 후 /plan → /execute → /ship 순으로 진행합니다.
  * Codex 세션은 Claude 훅의 rm -rf / .env·시크릿 차단이 적용되지 않습니다.
    승인 정책(on-request)과 샌드박스(workspace-write)로만 보호되므로 각별히 주의하세요.
EOF
fi

cat <<EOF

의존성 설치 (스택별):
EOF
if [[ $ANY_NODE -eq 1 ]]; then
  echo "  Node:     npm i -D eslint typescript-eslint @eslint/js eslint-config-prettier prettier vitest"
fi
if [[ $ANY_NESTJS -eq 1 ]]; then
  echo "  NestJS:   npm i -D eslint typescript-eslint @eslint/js eslint-config-prettier prettier jest @nestjs/testing"
fi
if [[ $ANY_FLUTTER -eq 1 ]]; then
  echo "  Flutter:  dev_dependencies 에 flutter_lints 추가 후 flutter pub get"
fi
if [[ $ANY_SPRING_JAVA -eq 1 || $ANY_SPRING_KOTLIN -eq 1 ]]; then
  echo "  SpringBoot: Gradle Kotlin DSL 기본. 커밋 전 게이트: ./gradlew build test"
  if [[ $WITH_SPOTLESS -eq 1 ]]; then
    echo "              Spotless 옵트인 활성화 — 게이트에 spotlessCheck 를 포함하세요."
  fi
fi
echo
echo "훅 테스트: python3 -m pytest (하네스 레포에서)"
echo

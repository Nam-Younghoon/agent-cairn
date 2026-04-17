#!/usr/bin/env bash
# agent-cairn 설치 스크립트
#
# 사용법:
#   ./scripts/install.sh --stack=<stack-spec> [--target=<repo-root>] [--force]
#
# stack-spec 형식:
#   1) 단일 스택            : --stack=express
#   2) 모노레포(한 루트 다중): --stack=express,nextjs,flutter
#   3) 모노레포(앱별 경로)   : --stack=express:apps/api,nextjs:apps/web,flutter:apps/mobile
#
# 동작:
#   - .claude/ 와 루트 CLAUDE.md 는 항상 --target (리포지토리 루트) 에 설치.
#   - 스택 스펙에 경로가 있으면 해당 경로에도 CLAUDE.md 와 스택별 린트 설정을 추가 설치.
#   - CLAUDE.md 는 <!-- agent-cairn:start --> ... <!-- agent-cairn:end --> 마커 기반으로
#     스마트 병합된다. 사용자가 마커 밖에 추가한 내용은 보존된다.

set -euo pipefail

STACK_SPEC=""
TARGET="$(pwd)"
FORCE=0

for arg in "$@"; do
  case $arg in
    --stack=*)  STACK_SPEC="${arg#*=}" ;;
    --target=*) TARGET="${arg#*=}" ;;
    --force)    FORCE=1 ;;
    -h|--help)
      sed -n '1,25p' "$0"
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

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$TARGET"
TARGET="$(cd "$TARGET" && pwd)"
FORCE_FLAG=""
[[ $FORCE -eq 1 ]] && FORCE_FLAG="--force"

echo "[install] harness=$HARNESS_DIR"
echo "[install] target=$TARGET"
echo "[install] stack-spec=$STACK_SPEC"

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
    express|nextjs|flutter) ;;
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

install_flutter_lint() {
  local dst_dir="$1"
  copy_file "$HARNESS_DIR/templates/flutter/analysis_options.yaml" "$dst_dir/analysis_options.yaml"
}

merge_claude() {
  local target_file="$1" source_file="$2"
  python3 "$HARNESS_DIR/scripts/_merge_claude.py" "$target_file" "$source_file" $FORCE_FLAG
}

# ---- 1) 루트 공통 자산 (.claude/, .gitignore, .env.example, .github/) -----

echo "[install] 루트 공통 자산 배포"

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

copy_file "$HARNESS_DIR/templates/github/PULL_REQUEST_TEMPLATE.md" "$TARGET/.github/PULL_REQUEST_TEMPLATE.md"

append_if_missing "$HARNESS_DIR/templates/gitignore.partial" \
                  "$TARGET/.gitignore" \
                  "agent-cairn — 하네스 기본 규칙"

if [[ ! -f "$TARGET/.env.example" || $FORCE -eq 1 ]]; then
  copy_file "$HARNESS_DIR/templates/env.example" "$TARGET/.env.example"
fi

# ---- 2) 스택 스펙 파싱 -----------------------------------------------------

IFS=',' read -r -a STACK_ENTRIES <<< "$STACK_SPEC"

declare -a STACKS
declare -a PATHS
ANY_NODE=0
ANY_FLUTTER=0
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
    express|nextjs) ANY_NODE=1 ;;
    flutter)        ANY_FLUTTER=1 ;;
  esac
done

# ---- 3) 루트 CLAUDE.md 병합 ------------------------------------------------

echo "[install] 루트 CLAUDE.md 병합"

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

merge_claude "$TARGET/CLAUDE.md" "$tmp_root_content"
rm -f "$tmp_root_content"

# ---- 4) 스택별 설치 --------------------------------------------------------

if [[ $HAS_PATH_SPEC -eq 0 ]]; then
  # 루트 1곳에 린트 설정 설치
  [[ $ANY_NODE -eq 1 ]]    && install_node_lint "$TARGET"
  [[ $ANY_FLUTTER -eq 1 ]] && install_flutter_lint "$TARGET"
else
  # 모노레포: 경로별 CLAUDE.md + 경로별 린트 설정
  for i in "${!STACKS[@]}"; do
    stack="${STACKS[$i]}"
    sub_path="${PATHS[$i]}"
    app_dir="$TARGET/$sub_path"
    mkdir -p "$app_dir"
    echo "[install] 앱 설치 ($stack → $sub_path)"
    merge_claude "$app_dir/CLAUDE.md" "$HARNESS_DIR/templates/$stack/CLAUDE.md"
    case "$stack" in
      express|nextjs) install_node_lint "$app_dir" ;;
      flutter)        install_flutter_lint "$app_dir" ;;
    esac
  done
fi

# ---- 5) 마무리 안내 --------------------------------------------------------

cat <<EOF

[install] 완료.

다음 단계:
  1. 프로젝트를 열고 Claude Code 를 실행합니다.
  2. /discuss <작업 내용> 으로 요구사항 논의를 시작합니다.
  3. 승인 후 /plan → /execute → /ship 순으로 진행합니다.

의존성 설치 (스택별):
EOF
if [[ $ANY_NODE -eq 1 ]]; then
  echo "  Node:     npm i -D eslint typescript-eslint @eslint/js eslint-config-prettier prettier vitest"
fi
if [[ $ANY_FLUTTER -eq 1 ]]; then
  echo "  Flutter:  dev_dependencies 에 flutter_lints 추가 후 flutter pub get"
fi
echo
echo "훅 테스트: python3 -m pytest (하네스 레포에서)"
echo

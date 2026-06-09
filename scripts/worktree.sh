#!/usr/bin/env bash
# agent-cairn — git worktree 헬퍼 (Codex/Gemini 용; Claude 는 네이티브 `claude --worktree` 사용)
#
# 멀티 세션 격리를 위해 세션 실행 *전에* 워크트리를 만든다(ADR-016/018).
# Claude Code 네이티브 `--worktree` + `.worktreeinclude` 동작을 모사한다.
#
# 사용법:
#   scripts/worktree.sh new <task> [base]   # .worktrees/<task> 워크트리 생성 + .worktreeinclude 승계
#   scripts/worktree.sh list                # 현재 워크트리 목록
#   scripts/worktree.sh clean <task>        # .worktrees/<task> 워크트리 제거
#
# new 이후:
#   cd .worktrees/<task> 로 이동해 codex/gemini 세션을 띄우고 /discuss 로 작업 브랜치를 만든다.
#   (워크트리는 base 의 detached HEAD 로 시작하며, 실제 브랜치는 /discuss 가 origin/<base> 기반으로 생성)

set -euo pipefail

# 항상 git 최상위 디렉토리 기준으로 동작
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "오류: git 저장소 안에서 실행하세요." >&2
  exit 1
}
cd "$REPO_ROOT"

WORKTREE_DIR=".worktrees"
INCLUDE_FILE=".worktreeinclude"
DEFAULT_BASES=(dev main master)

usage() {
  cat >&2 <<'EOF'
사용법:
  worktree.sh new <task> [base]   새 워크트리 생성 (.worktrees/<task>)
  worktree.sh list                워크트리 목록
  worktree.sh clean <task>        워크트리 제거 (.worktrees/<task>)
EOF
}

# 기준 ref 해석: origin/<base> 우선, 없으면 로컬 <base>. (없으면 비정상 종료)
resolve_base_ref() {
  local base="$1"
  if git rev-parse --verify --quiet "origin/$base" >/dev/null; then
    echo "origin/$base"
    return 0
  fi
  if git rev-parse --verify --quiet "$base" >/dev/null; then
    echo "$base"
    return 0
  fi
  return 1
}

# .worktreeinclude 에 나열된 gitignore 파일을 새 워크트리로 복사.
# 시크릿 값은 출력하지 않고 경로만 보고한다.
copy_includes() {
  local dest="$1"
  [[ -f "$INCLUDE_FILE" ]] || return 0
  local raw path src
  while IFS= read -r raw || [[ -n "$raw" ]]; do
    path="${raw%%#*}"                          # 주석 제거
    path="${path#"${path%%[![:space:]]*}"}"    # 앞 공백 트림
    path="${path%"${path##*[![:space:]]}"}"    # 뒤 공백 트림
    [[ -z "$path" ]] && continue
    # REPO_ROOT 밖으로 새는 항목 거부 (방어 심층 — .worktreeinclude 는 git-tracked 이나 안전망)
    if [[ "$path" == /* || "$path" == *..* ]]; then
      echo "  경고: 위험한 항목 건너뜀(절대경로/상위참조): $path" >&2
      continue
    fi
    # glob 패턴 확장 (매칭 없으면 건너뜀). 항목은 공백 없는 경로/글롭 전제.
    # shellcheck disable=SC2086
    for src in $path; do
      [[ -e "$src" ]] || continue
      mkdir -p "$dest/$(dirname "$src")"
      cp -R "$src" "$dest/$src"
      echo "  승계: $src"
    done
  done < "$INCLUDE_FILE"
}

# task 이름이 .worktrees/ 밖으로 새지 않도록 검증 (영문·숫자·하이픈·언더스코어만 허용)
validate_task() {
  local task="$1"
  if [[ ! "$task" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "오류: task 이름은 영문·숫자·하이픈(-)·언더스코어(_)만 허용합니다: '$task'" >&2
    exit 1
  fi
}

cmd_new() {
  local task="${1:-}" base="${2:-}"
  if [[ -z "$task" ]]; then
    echo "오류: 작업 이름이 필요합니다. (worktree.sh new <task> [base])" >&2
    exit 1
  fi
  validate_task "$task"
  local path="$WORKTREE_DIR/$task"
  if [[ -e "$path" ]]; then
    echo "오류: '$path' 가 이미 존재합니다." >&2
    exit 1
  fi

  # 원격이 있으면 최신화 (실패해도 로컬 기준으로 진행)
  if git remote get-url origin >/dev/null 2>&1; then
    git fetch origin --quiet || echo "경고: git fetch 실패 — 로컬 기준으로 진행합니다." >&2
  fi

  # 기준 브랜치 후보 결정
  local candidates=()
  if [[ -n "$base" ]]; then
    candidates=("$base")
  else
    candidates=("${DEFAULT_BASES[@]}")
  fi

  local start=""
  local b
  for b in "${candidates[@]}"; do
    if start="$(resolve_base_ref "$b")"; then
      break
    fi
    start=""
  done
  if [[ -z "$start" ]]; then
    echo "오류: 기준 브랜치를 찾을 수 없습니다 (시도: ${candidates[*]} / origin/*)." >&2
    echo "      base 인자로 명시하세요: worktree.sh new $task <base>" >&2
    exit 1
  fi

  # base 의 detached HEAD 로 워크트리 생성 — 실제 작업 브랜치는 /discuss 가 만든다
  git worktree add --detach "$path" "$start" >/dev/null
  echo "워크트리 생성: $path  (기준 $start, detached HEAD)"
  copy_includes "$path"
  echo
  echo "다음 단계:"
  echo "  cd $path"
  echo "  codex 또는 gemini 세션을 띄운 뒤 /discuss 로 작업 브랜치를 생성하세요."
}

cmd_list() {
  git worktree list
}

cmd_clean() {
  local task="${1:-}"
  if [[ -z "$task" ]]; then
    echo "오류: 작업 이름이 필요합니다. (worktree.sh clean <task>)" >&2
    exit 1
  fi
  validate_task "$task"
  local path="$WORKTREE_DIR/$task"
  if [[ ! -d "$path" ]]; then
    echo "오류: 워크트리 '$path' 가 없습니다. 현재 목록:" >&2
    git worktree list >&2
    exit 1
  fi
  # 워크트리는 .worktreeinclude 로 승계한 gitignore 파일(.env 등 untracked)을 담으므로
  # --force 없이는 git 이 제거를 거부한다. 의도된 동작이므로 강제 제거한다.
  echo "주의: --force 제거 — '$path' 안의 untracked 파일(승계된 .env 등)도 함께 삭제됩니다."
  git worktree remove --force "$path"
  echo "워크트리 제거: $path"
}

case "${1:-}" in
  new)   shift; cmd_new "$@" ;;
  list)  cmd_list ;;
  clean) shift; cmd_clean "$@" ;;
  -h|--help|help|"") usage; exit 1 ;;
  *) echo "오류: 알 수 없는 서브커맨드 '$1'" >&2; usage; exit 1 ;;
esac

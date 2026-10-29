#!/usr/bin/env bash
# 소비 프로젝트의 하네스 자산 마이그레이션.
#
# 왜 필요한가:
#   install.sh 의 copy_file 은 **추가만** 하고 삭제하지 않는다. canonical `.claude/` 를
#   직접 cp 로 전파하는 경우도 마찬가지다. 그래서 개명·폐기된 구본이 소비 프로젝트에
#   그대로 남고, 남아 있는 한 Claude Code 내장 슬래시 커맨드를 계속 가린다(ADR-021).
#   이 스크립트는 신본 배포와 구본 삭제를 한 쌍으로 수행한다.
#
# 사용법:
#   scripts/migrate-consumers.sh [--root <dir>] [--apply]
#     --root <dir>  스캔할 상위 디렉토리 (기본 ~/Documents/GitHub)
#     --apply       실제 적용. 생략하면 dry-run (기본값)
#
# 안전장치:
#   - dry-run 이 기본. 14개 이상의 레포를 한 번에 건드리므로 기본값이 안전해야 한다.
#   - 소비 프로젝트의 .claude 는 gitignore 대상이라 git 으로 복구되지 않는다.
#     삭제 전 프로젝트 안에 .claude/.migrate-backup-<타임스탬프>/ 로 백업한다.
#   - settings.json / settings.local.json 은 건드리지 않는다. 프로젝트별 커스텀이
#     들어 있을 수 있고, 이 스크립트의 범위는 개명·폐기 자산 정리다.
#   - .claude/worktrees/ 안에는 별도 체크아웃이 들어 있다. 정확한 경로만 다루므로
#     그 안으로 내려가지 않는다.

set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$HOME/Documents/GitHub"
APPLY=0

# 개명·폐기로 버려진 자산 (프로젝트 루트 기준 상대 경로).
# 자산을 또 개명하면 여기에 구 이름을 추가한다.
DEPRECATED_ASSETS=(
  ".claude/commands/plan.md"
  ".claude/agents/parallel-explorer.md"
  ".codex/prompts/plan.md"
  ".gemini/commands/plan.toml"
)

# 하네스 설치 여부 판별 기준. 이 파일이 있으면 하네스 소비 프로젝트로 본다.
HARNESS_MARKER=".claude/commands/discuss.md"

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//' | head -n -1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)   ROOT="$2"; shift 2 ;;
    --root=*) ROOT="${1#*=}"; shift ;;
    --apply)  APPLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "알 수 없는 옵션: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! -d "$ROOT" ]]; then
  echo "스캔 루트가 없습니다: $ROOT" >&2
  exit 2
fi

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
scanned=0
targets=0
removed_total=0

# canonical 자산을 대상 프로젝트로 복사. .DS_Store / __pycache__ 는 제외.
deploy_dir() {
  local src="$1" dest="$2"
  [[ -d "$src" ]] || return 0
  mkdir -p "$dest"
  local file base
  for file in "$src"/*; do
    [[ -f "$file" ]] || continue
    base="$(basename "$file")"
    case "$base" in
      .DS_Store|*.pyc) continue ;;
    esac
    cp "$file" "$dest/$base"
  done
}

echo "스캔 루트: $ROOT"
if [[ $APPLY -eq 1 ]]; then
  echo "모드: APPLY (실제 적용)"
else
  echo "모드: DRY-RUN (변경 없음 — 적용하려면 --apply)"
fi
echo

for project in "$ROOT"/*/; do
  project="${project%/}"
  name="$(basename "$project")"

  # 하네스 레포 자신은 배포 원본이지 소비 프로젝트가 아니다.
  [[ "$name" == "agent-cairn" ]] && continue
  [[ "$project" == "$HARNESS_DIR" ]] && continue

  scanned=$((scanned + 1))
  [[ -f "$project/$HARNESS_MARKER" ]] || continue
  targets=$((targets + 1))

  echo "▸ $name"

  # --- 폐기 자산 수집
  found=()
  for asset in "${DEPRECATED_ASSETS[@]}"; do
    [[ -f "$project/$asset" ]] && found+=("$asset")
  done

  if [[ ${#found[@]} -gt 0 ]]; then
    for asset in "${found[@]}"; do
      echo "    삭제  $asset"
    done
  else
    echo "    삭제  (없음 — 이미 정리됨)"
  fi

  if [[ $APPLY -eq 0 ]]; then
    echo "    배포  .claude/{commands,agents,hooks,patterns}, VERSION_NOTES.md, templates/__docs"
    echo
    continue
  fi

  # --- 백업 후 삭제 (.claude 는 gitignore 대상 → git 복구 불가)
  if [[ ${#found[@]} -gt 0 ]]; then
    backup="$project/.claude/.migrate-backup-$TIMESTAMP"
    for asset in "${found[@]}"; do
      # .claude 자산은 .claude 기준 상대 경로로, 그 외 CLI 자산은 원래 경로 그대로 보관
      rel="${asset#.claude/}"
      mkdir -p "$backup/$(dirname "$rel")"
      cp "$project/$asset" "$backup/$rel"
      rm "$project/$asset"
      removed_total=$((removed_total + 1))
    done
    echo "    백업  .claude/.migrate-backup-$TIMESTAMP/"
  fi

  # --- 신본 배포 (settings.json 계열은 제외)
  deploy_dir "$HARNESS_DIR/.claude/commands" "$project/.claude/commands"
  deploy_dir "$HARNESS_DIR/.claude/agents"   "$project/.claude/agents"
  deploy_dir "$HARNESS_DIR/.claude/hooks"    "$project/.claude/hooks"
  deploy_dir "$HARNESS_DIR/.claude/patterns" "$project/.claude/patterns"
  cp "$HARNESS_DIR/.claude/VERSION_NOTES.md" "$project/.claude/VERSION_NOTES.md"
  deploy_dir "$HARNESS_DIR/templates/__docs" "$project/.claude/templates/__docs"

  # Codex / Gemini 는 해당 CLI 가 설치된 프로젝트에만
  [[ -d "$project/.codex/prompts" ]]   && deploy_dir "$HARNESS_DIR/.codex/prompts"   "$project/.codex/prompts"
  [[ -d "$project/.gemini/commands" ]] && deploy_dir "$HARNESS_DIR/.gemini/commands" "$project/.gemini/commands"

  echo "    배포  완료"
  echo
done

echo "―――――――――――――――――――――――"
echo "스캔한 디렉토리: $scanned"
echo "하네스 소비 프로젝트: $targets"
if [[ $APPLY -eq 1 ]]; then
  echo "제거한 폐기 자산: $removed_total"
else
  echo "(dry-run — 변경 없음. 적용하려면 --apply)"
fi

#!/usr/bin/env bash
# 하네스 자체 회귀 테스트.
#   1) pytest 로 훅 단위/E2E 테스트 실행
#   2) install.sh 를 3가지 시나리오(단일/다중/모노레포) 로 임시 디렉토리에 설치해 검증
#   3) 필수 파일·템플릿 존재 확인
#
# 배포 전 또는 PR 전 이 스크립트가 통과해야 함.

set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HARNESS_DIR"

PASS=0
FAIL=0
ok()   { echo "  [ok]   $*"; PASS=$((PASS + 1)); }
fail() { echo "  [FAIL] $*"; FAIL=$((FAIL + 1)); }

echo "===== 1) pytest (훅 단위/E2E) ====="
if python3 -m pytest -q; then
  ok "pytest 전체 통과"
else
  fail "pytest 실패"
fi

echo
echo "===== 2) 필수 파일 체크 ====="
required=(
  "CLAUDE.md"
  "README.md"
  "CHANGELOG.md"
  ".claude/settings.json"
  ".claude/hooks/block_dangerous.py"
  ".claude/hooks/block_secret_files.py"
  ".claude/patterns/secrets.yaml"
  ".claude/commands/discuss.md"
  ".claude/commands/plan.md"
  ".claude/commands/execute.md"
  ".claude/commands/ship.md"
  ".claude/agents/parallel-explorer.md"
  ".claude/agents/tdd-tester.md"
  ".claude/agents/pre-commit-reviewer.md"
  "templates/express/CLAUDE.md"
  "templates/nextjs/CLAUDE.md"
  "templates/flutter/CLAUDE.md"
  "templates/flutter/analysis_options.yaml"
  "templates/node/eslint.config.mjs"
  "templates/node/.prettierrc.json"
  "templates/node/.prettierignore"
  "templates/__docs/PRD.md"
  "templates/__docs/ARCHITECTURE.md"
  "templates/__docs/ADR.md"
  "templates/__docs/UI_GUIDE.md"
  "templates/__docs/plan.schema.json"
  "templates/__docs/plan.example.json"
  "templates/github/PULL_REQUEST_TEMPLATE.md"
  "templates/gitignore.partial"
  "templates/env.example"
  "scripts/install.sh"
  "scripts/_merge_claude.py"
)
for f in "${required[@]}"; do
  if [[ -f "$f" ]]; then
    ok "$f"
  else
    fail "누락: $f"
  fi
done

echo
echo "===== 3) install.sh 문법 ====="
if bash -n scripts/install.sh; then
  ok "bash -n install.sh"
else
  fail "install.sh 문법 오류"
fi

echo
echo "===== 4) install.sh 시나리오 ====="
TS="$(date +%s)"
scenarios=(
  "express:/tmp/ht-st-$TS-single"
  "express,nextjs,flutter:/tmp/ht-st-$TS-multi"
  "express:apps/api,nextjs:apps/web,flutter:apps/mobile:/tmp/ht-st-$TS-mono"
)

run_scenario() {
  local spec="$1" target="$2" label="$3"
  mkdir -p "$target"
  if bash scripts/install.sh --stack="$spec" --target="$target" >/dev/null 2>&1; then
    ok "install $label"
  else
    fail "install $label 실패"
    return
  fi
  if [[ ! -f "$target/CLAUDE.md" ]]; then
    fail "$label: CLAUDE.md 미생성"
  fi
  if ! grep -q 'agent-cairn:start' "$target/CLAUDE.md"; then
    fail "$label: 병합 마커 미포함"
  fi
  # 타겟 프로젝트에서 슬래시 커맨드가 Read 할 템플릿 존재 여부
  for tpl in PRD.md ARCHITECTURE.md ADR.md UI_GUIDE.md plan.schema.json plan.example.json; do
    if [[ ! -f "$target/.claude/templates/__docs/$tpl" ]]; then
      fail "$label: .claude/templates/__docs/$tpl 미설치"
    fi
  done
  # hook + patterns
  for f in \
      .claude/hooks/block_dangerous.py \
      .claude/hooks/block_secret_files.py \
      .claude/patterns/secrets.yaml; do
    if [[ ! -f "$target/$f" ]]; then
      fail "$label: $f 미설치"
    fi
  done
}

run_scenario "express" "/tmp/ht-st-$TS-single" "single(express)"
run_scenario "express,nextjs,flutter" "/tmp/ht-st-$TS-multi" "multi(express,nextjs,flutter)"
run_scenario "express:apps/api,nextjs:apps/web,flutter:apps/mobile" "/tmp/ht-st-$TS-mono" "mono(apps/*)"

echo
echo "===== 5) 스마트 병합 — 사용자 커스텀 보존 ====="
TARGET="/tmp/ht-st-$TS-merge"
mkdir -p "$TARGET"
printf '# 내 커스텀\n\n마커 밖 사용자 문구\n' > "$TARGET/CLAUDE.md"
bash scripts/install.sh --stack=express --target="$TARGET" >/dev/null 2>&1
if grep -q "마커 밖 사용자 문구" "$TARGET/CLAUDE.md"; then
  ok "마커 밖 사용자 컨텐츠 보존됨"
else
  fail "사용자 컨텐츠 유실"
fi
# 두 번째 설치 — 마커 블록만 교체되고 사용자 문구 유지
bash scripts/install.sh --stack=express --target="$TARGET" >/dev/null 2>&1
if grep -q "마커 밖 사용자 문구" "$TARGET/CLAUDE.md"; then
  ok "재설치 후에도 사용자 컨텐츠 보존"
else
  fail "재설치 시 사용자 컨텐츠 유실"
fi

echo
echo "===== 요약 ====="
echo "  PASS=$PASS  FAIL=$FAIL"
if [[ $FAIL -gt 0 ]]; then
  exit 1
fi

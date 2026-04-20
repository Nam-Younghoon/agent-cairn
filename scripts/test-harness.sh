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
  "templates/nestjs/CLAUDE.md"
  "templates/nestjs/eslint.config.mjs"
  "templates/springboot/CLAUDE.md"
  "templates/springboot/spotless.gradle.kts"
  "templates/springboot/.editorconfig"
  "templates/springboot-kotlin/CLAUDE.md"
  "templates/springboot-kotlin/spotless.gradle.kts"
  "templates/springboot-kotlin/.editorconfig"
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
  ".codex/config.toml"
  ".codex/prompts/discuss.md"
  ".codex/prompts/plan.md"
  ".codex/prompts/execute.md"
  ".codex/prompts/ship.md"
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
  local spec="$1" target="$2" label="$3" extra_args="${4:-}"
  mkdir -p "$target"
  # shellcheck disable=SC2086
  if bash scripts/install.sh --stack="$spec" --target="$target" $extra_args >/dev/null 2>&1; then
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

assert_file_exists() {
  local label="$1" path="$2"
  if [[ -f "$path" ]]; then
    ok "$label: $path 존재"
  else
    fail "$label: $path 미생성"
  fi
}

assert_file_missing() {
  local label="$1" path="$2"
  if [[ ! -e "$path" ]]; then
    ok "$label: $path 미생성 (기대)"
  else
    fail "$label: $path 가 생성되어선 안 됨"
  fi
}

run_scenario "express" "/tmp/ht-st-$TS-single" "single(express)"
run_scenario "express,nextjs,flutter" "/tmp/ht-st-$TS-multi" "multi(express,nextjs,flutter)"
run_scenario "express:apps/api,nextjs:apps/web,flutter:apps/mobile" "/tmp/ht-st-$TS-mono" "mono(apps/*)"

# 신규 스택: 단일 설치
run_scenario "nestjs" "/tmp/ht-st-$TS-nestjs" "single(nestjs)"
assert_file_exists "single(nestjs)" "/tmp/ht-st-$TS-nestjs/eslint.config.mjs"

run_scenario "springboot" "/tmp/ht-st-$TS-sb-java" "single(springboot)"
assert_file_missing "single(springboot) no-spotless" "/tmp/ht-st-$TS-sb-java/spotless.gradle.kts"
assert_file_missing "single(springboot) no-spotless" "/tmp/ht-st-$TS-sb-java/.editorconfig"

run_scenario "springboot-kotlin" "/tmp/ht-st-$TS-sb-kt" "single(springboot-kotlin)"
assert_file_missing "single(springboot-kotlin) no-spotless" "/tmp/ht-st-$TS-sb-kt/spotless.gradle.kts"

# --with-spotless 옵트인: Java + Kotlin 동시 설치
run_scenario "springboot,springboot-kotlin" "/tmp/ht-st-$TS-sb-opt" \
  "multi(springboot,springboot-kotlin) --with-spotless" "--with-spotless"
assert_file_exists "with-spotless" "/tmp/ht-st-$TS-sb-opt/spotless.gradle.kts"
assert_file_exists "with-spotless" "/tmp/ht-st-$TS-sb-opt/.editorconfig"
if grep -q "google-java-format\|googleJavaFormat\|ktfmt" "/tmp/ht-st-$TS-sb-opt/spotless.gradle.kts"; then
  ok "with-spotless: spotless.gradle.kts 본문에 포매터 식별 문자열 포함"
else
  fail "with-spotless: spotless.gradle.kts 본문이 비었거나 포매터 식별 불가"
fi

# 모노레포 + --with-spotless: 각 앱 경로에 언어별 스니펫 배포
MONO_DIR="/tmp/ht-st-$TS-mono-opt"
run_scenario \
  "springboot:apps/api-java,springboot-kotlin:apps/api-kotlin,nestjs:apps/api-nest" \
  "$MONO_DIR" \
  "mono(springboot Java/Kotlin + nestjs) --with-spotless" \
  "--with-spotless"
assert_file_exists "mono --with-spotless (Java)"   "$MONO_DIR/apps/api-java/spotless.gradle.kts"
assert_file_exists "mono --with-spotless (Kotlin)" "$MONO_DIR/apps/api-kotlin/spotless.gradle.kts"
assert_file_missing "mono NestJS no-spotless"      "$MONO_DIR/apps/api-nest/spotless.gradle.kts"
assert_file_exists "mono NestJS 전용 eslint"       "$MONO_DIR/apps/api-nest/eslint.config.mjs"
if grep -q "ktfmt" "$MONO_DIR/apps/api-kotlin/spotless.gradle.kts"; then
  ok "mono Kotlin: ktfmt 포함"
else
  fail "mono Kotlin: ktfmt 누락"
fi
if grep -q "googleJavaFormat" "$MONO_DIR/apps/api-java/spotless.gradle.kts"; then
  ok "mono Java: googleJavaFormat 포함"
else
  fail "mono Java: googleJavaFormat 누락"
fi

# 잘못된 식별자는 거부해야 한다
INVALID_DIR="/tmp/ht-st-$TS-invalid"
mkdir -p "$INVALID_DIR"
if bash scripts/install.sh --stack=spring-boot --target="$INVALID_DIR" >/dev/null 2>&1; then
  fail "invalid stack(spring-boot) 가 잘못 통과됨"
else
  ok "invalid stack(spring-boot) 거부 확인"
fi

echo
echo "===== 4b) --cli 플래그 파싱 ====="
# --cli 미지정: 기본값 claude 로 로그 출력
CLI_DEFAULT_DIR="/tmp/ht-st-$TS-cli-default"
mkdir -p "$CLI_DEFAULT_DIR"
if out="$(bash scripts/install.sh --stack=express --target="$CLI_DEFAULT_DIR" 2>&1)"; then
  if grep -q "cli=claude" <<< "$out"; then
    ok "cli 기본값 claude 로그 노출"
  else
    fail "cli 기본값 로그 누락"
  fi
else
  fail "--cli 미지정 설치 실패"
fi

# --cli=codex 단독 — 파싱만 성공해야 함 (자산 배포는 이후 스텝)
CLI_CODEX_DIR="/tmp/ht-st-$TS-cli-codex"
mkdir -p "$CLI_CODEX_DIR"
if out="$(bash scripts/install.sh --cli=codex --stack=express --target="$CLI_CODEX_DIR" 2>&1)"; then
  ok "--cli=codex 파싱 통과"
  if grep -q "cli=codex" <<< "$out"; then
    ok "--cli=codex 로그 노출"
  else
    fail "--cli=codex 로그 누락"
  fi
else
  fail "--cli=codex 가 정상 종료되지 않음"
fi

# --cli 콤마 결합 — claude,codex
CLI_MULTI_DIR="/tmp/ht-st-$TS-cli-multi"
mkdir -p "$CLI_MULTI_DIR"
if out="$(bash scripts/install.sh --cli=claude,codex --stack=express --target="$CLI_MULTI_DIR" 2>&1)"; then
  ok "--cli=claude,codex 파싱 통과"
  if grep -Eq "cli=claude[, ]codex" <<< "$out"; then
    ok "--cli=claude,codex 로그 노출"
  else
    fail "--cli=claude,codex 로그 누락"
  fi
else
  fail "--cli=claude,codex 가 정상 종료되지 않음"
fi

# --cli=bogus — 비정상 종료
CLI_INVALID_DIR="/tmp/ht-st-$TS-cli-invalid"
mkdir -p "$CLI_INVALID_DIR"
if bash scripts/install.sh --cli=bogus --stack=express --target="$CLI_INVALID_DIR" >/dev/null 2>&1; then
  fail "--cli=bogus 가 잘못 통과됨"
else
  ok "--cli=bogus 거부 확인"
fi

# --cli= (빈 값) — 비정상 종료 + 친절한 에러 메시지
CLI_EMPTY_DIR="/tmp/ht-st-$TS-cli-empty"
mkdir -p "$CLI_EMPTY_DIR"
if err="$(bash scripts/install.sh --cli= --stack=express --target="$CLI_EMPTY_DIR" 2>&1)"; then
  fail "--cli= (빈값) 이 잘못 통과됨"
else
  if grep -q "unbound variable" <<< "$err"; then
    fail "--cli= (빈값) 이 unbound variable 로 터짐 (친절한 메시지 아님)"
  else
    ok "--cli= (빈값) 거부 + 친절한 에러 메시지"
  fi
fi

# --help 출력에 --cli 언급
if bash scripts/install.sh --help 2>&1 | grep -q -- "--cli"; then
  ok "--help 에 --cli 설명 포함"
else
  fail "--help 에 --cli 설명 누락"
fi

echo
echo "===== 4c) AGENTS.md 루트 배포 + CLI 조건부 배포 ====="

# 마커 블록만 뽑아 비교하는 헬퍼
extract_marker_block() {
  # stdin 파일 경로 → stdout 마커 블록 내용
  awk '/<!-- agent-cairn:start -->/,/<!-- agent-cairn:end -->/' "$1"
}

# (A) --cli=codex 단독: AGENTS.md 존재, CLAUDE.md 부재, .claude/ 부재
CODEX_ONLY_DIR="/tmp/ht-st-$TS-codex-only"
mkdir -p "$CODEX_ONLY_DIR"
if bash scripts/install.sh --cli=codex --stack=express --target="$CODEX_ONLY_DIR" >/dev/null 2>&1; then
  ok "--cli=codex 단독 설치 성공"
else
  fail "--cli=codex 단독 설치 실패"
fi
assert_file_exists "codex-only: AGENTS.md" "$CODEX_ONLY_DIR/AGENTS.md"
assert_file_missing "codex-only: CLAUDE.md 부재" "$CODEX_ONLY_DIR/CLAUDE.md"
assert_file_missing "codex-only: .claude/settings.json 부재" "$CODEX_ONLY_DIR/.claude/settings.json"
if grep -q "agent-cairn:start" "$CODEX_ONLY_DIR/AGENTS.md" 2>/dev/null; then
  ok "codex-only: AGENTS.md 마커 블록 포함"
else
  fail "codex-only: AGENTS.md 마커 블록 누락"
fi

# (B) --cli=claude,codex 혼용: 양쪽 존재 + 마커 블록 본문 일치
MIX_DIR="/tmp/ht-st-$TS-mix"
mkdir -p "$MIX_DIR"
if bash scripts/install.sh --cli=claude,codex --stack=express --target="$MIX_DIR" >/dev/null 2>&1; then
  ok "--cli=claude,codex 혼용 설치 성공"
else
  fail "--cli=claude,codex 혼용 설치 실패"
fi
assert_file_exists "mix: CLAUDE.md" "$MIX_DIR/CLAUDE.md"
assert_file_exists "mix: AGENTS.md" "$MIX_DIR/AGENTS.md"
assert_file_exists "mix: .claude/settings.json" "$MIX_DIR/.claude/settings.json"
if [[ -f "$MIX_DIR/CLAUDE.md" && -f "$MIX_DIR/AGENTS.md" ]]; then
  if diff <(extract_marker_block "$MIX_DIR/CLAUDE.md") \
          <(extract_marker_block "$MIX_DIR/AGENTS.md") > /dev/null; then
    ok "mix: CLAUDE.md ↔ AGENTS.md 마커 블록 일치"
  else
    fail "mix: CLAUDE.md ↔ AGENTS.md 마커 블록 불일치"
  fi
fi

# (C) 기존 AGENTS.md 에 사용자 커스텀이 마커 바깥에 있을 때 보존
PRESERVE_DIR="/tmp/ht-st-$TS-agents-preserve"
mkdir -p "$PRESERVE_DIR"
printf '# 내 AGENTS 커스텀\n\n마커 밖 AGENTS 사용자 문구\n' > "$PRESERVE_DIR/AGENTS.md"
bash scripts/install.sh --cli=codex --stack=express --target="$PRESERVE_DIR" >/dev/null 2>&1
if grep -q "마커 밖 AGENTS 사용자 문구" "$PRESERVE_DIR/AGENTS.md"; then
  ok "AGENTS.md 마커 밖 사용자 컨텐츠 보존"
else
  fail "AGENTS.md 마커 밖 사용자 컨텐츠 유실"
fi
# 재실행 — 마커 블록만 갱신되고 커스텀 유지
bash scripts/install.sh --cli=codex --stack=express --target="$PRESERVE_DIR" >/dev/null 2>&1
if grep -q "마커 밖 AGENTS 사용자 문구" "$PRESERVE_DIR/AGENTS.md"; then
  ok "AGENTS.md 재설치 후에도 사용자 컨텐츠 보존"
else
  fail "AGENTS.md 재설치 시 사용자 컨텐츠 유실"
fi

echo
echo "===== 4d) .codex/config.toml + gitignore 선제 방어 ====="

# 재사용: CODEX_ONLY_DIR 는 4c 에서 생성됨 (--cli=codex --stack=express)
assert_file_exists "codex-only: .codex/config.toml" "$CODEX_ONLY_DIR/.codex/config.toml"

# 핵심 키 3종 포함
for key in "approval_policy" "sandbox_mode" "network_access"; do
  if grep -q "^$key" "$CODEX_ONLY_DIR/.codex/config.toml" 2>/dev/null; then
    ok "codex-only config.toml: '$key' 키 포함"
  else
    fail "codex-only config.toml: '$key' 키 누락"
  fi
done

# 기본값 검증 (하네스 기본 권장값 고정)
if grep -q 'approval_policy *= *"on-request"' "$CODEX_ONLY_DIR/.codex/config.toml"; then
  ok "codex-only: approval_policy=on-request"
else
  fail "codex-only: approval_policy 기본값 불일치"
fi
if grep -q 'sandbox_mode *= *"workspace-write"' "$CODEX_ONLY_DIR/.codex/config.toml"; then
  ok "codex-only: sandbox_mode=workspace-write"
else
  fail "codex-only: sandbox_mode 기본값 불일치"
fi
if grep -q 'network_access *= *true' "$CODEX_ONLY_DIR/.codex/config.toml"; then
  ok "codex-only: network_access=true"
else
  fail "codex-only: network_access 기본값 불일치"
fi

# .gitignore 에 Codex 선제 방어 블록 포함
for line in ".codex/sessions/" ".codex/history" ".codex/cache/" ".codex/config.local.toml"; do
  if grep -qF "$line" "$CODEX_ONLY_DIR/.gitignore" 2>/dev/null; then
    ok "codex-only .gitignore: '$line' 포함"
  else
    fail "codex-only .gitignore: '$line' 누락"
  fi
done
# 화이트리스트 주석 확인
if grep -qF '!.codex/config.toml' "$CODEX_ONLY_DIR/.gitignore" 2>/dev/null; then
  ok "codex-only .gitignore: '!.codex/config.toml' 예외 포함"
else
  fail "codex-only .gitignore: '!.codex/config.toml' 예외 누락"
fi

# --cli=claude 단독 시 .codex/ 부재
CLAUDE_ONLY_DIR="/tmp/ht-st-$TS-claude-only"
mkdir -p "$CLAUDE_ONLY_DIR"
bash scripts/install.sh --cli=claude --stack=express --target="$CLAUDE_ONLY_DIR" >/dev/null 2>&1
assert_file_missing "claude-only: .codex/config.toml 부재" "$CLAUDE_ONLY_DIR/.codex/config.toml"

# 모노레포 + --cli=codex: 앱 경로에 .codex/ 부재 (루트에만 배포)
CODEX_MONO_DIR="/tmp/ht-st-$TS-codex-mono"
mkdir -p "$CODEX_MONO_DIR"
bash scripts/install.sh --cli=codex --stack=express:apps/api,nextjs:apps/web \
  --target="$CODEX_MONO_DIR" >/dev/null 2>&1
assert_file_exists "codex-mono: root .codex/config.toml" "$CODEX_MONO_DIR/.codex/config.toml"
assert_file_missing "codex-mono: apps/api/.codex/config.toml 부재" "$CODEX_MONO_DIR/apps/api/.codex/config.toml"
assert_file_missing "codex-mono: apps/web/.codex/config.toml 부재" "$CODEX_MONO_DIR/apps/web/.codex/config.toml"

echo
echo "===== 4e) .codex/prompts/*.md 배포 + 인라인 가이드 ====="

# 4d 에서 이미 생성된 CODEX_ONLY_DIR 재사용
for cmd in discuss plan execute ship; do
  assert_file_exists "codex-only: prompts/$cmd.md" "$CODEX_ONLY_DIR/.codex/prompts/$cmd.md"
done

# 각 프롬프트에 인라인 가이드 섹션 최소 1개 포함
for cmd in discuss plan execute ship; do
  if grep -q "^## 인라인 가이드" "$CODEX_ONLY_DIR/.codex/prompts/$cmd.md" 2>/dev/null; then
    ok "codex-only: prompts/$cmd.md 에 인라인 가이드 섹션 포함"
  else
    fail "codex-only: prompts/$cmd.md 에 인라인 가이드 섹션 누락"
  fi
done

# execute.md 는 탐색/TDD/리뷰 3종 모두 포함해야 함
exec_md="$CODEX_ONLY_DIR/.codex/prompts/execute.md"
for guide in "병렬 탐색" "실패 테스트 선 작성" "커밋 전 리뷰"; do
  if grep -qF "## 인라인 가이드 — $guide" "$exec_md" 2>/dev/null; then
    ok "codex-only: execute.md 의 '$guide' 가이드 포함"
  else
    fail "codex-only: execute.md 의 '$guide' 가이드 누락"
  fi
done

# 모노레포 시나리오: 앱 경로에 prompts 중복 배포되지 않음
for cmd in discuss plan execute ship; do
  assert_file_missing "codex-mono: apps/api/.codex/prompts/$cmd.md 부재" \
    "$CODEX_MONO_DIR/apps/api/.codex/prompts/$cmd.md"
done

# --cli=claude 단독 시 .codex/prompts 부재
assert_file_missing "claude-only: .codex/prompts/discuss.md 부재" \
  "$CLAUDE_ONLY_DIR/.codex/prompts/discuss.md"

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

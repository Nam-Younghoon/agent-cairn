"""block_secret_files.py 단위 테스트."""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

from block_secret_files import (  # noqa: E402
    _parse_simple_yaml,
    find_secret,
    is_protected_path,
    load_patterns,
)


# --- 경로 판정 ---------------------------------------------------------------

@pytest.mark.parametrize(
    "path",
    [
        ".env",
        ".env.production",
        ".env.prod",
        ".env.staging",
        "apps/api/.env",
        "apps/api/.env.production",
        "/abs/path/.env.local",
    ],
)
def test_blocks_env_files(path: str) -> None:
    assert is_protected_path(path)


@pytest.mark.parametrize(
    "path",
    [
        ".env.example",
        ".env.sample",
        ".env.template",
        "apps/api/.env.example",
        "config/environment.ts",
        "README.md",
        "",
    ],
)
def test_allows_example_and_non_env_files(path: str) -> None:
    assert not is_protected_path(path)


# --- YAML 파서 ---------------------------------------------------------------

def test_parse_simple_yaml_basic() -> None:
    text = """
patterns:
  - name: Foo
    regex: "A+"
  - name: Bar
    regex: 'B{3}'
"""
    items = _parse_simple_yaml(text)
    assert items == [
        {"name": "Foo", "regex": "A+"},
        {"name": "Bar", "regex": "B{3}"},
    ]


# --- 시크릿 매칭 -------------------------------------------------------------

def test_find_secret_detects_aws_key() -> None:
    patterns = load_patterns()
    assert patterns, "패턴 파일을 찾지 못함"
    hit = find_secret("const key = 'AKIAIOSFODNN7EXAMPLE'", patterns)
    assert hit is not None
    assert "AWS" in hit.name


def test_find_secret_detects_github_pat() -> None:
    patterns = load_patterns()
    hit = find_secret("token=ghp_1234567890abcdef1234567890abcdef1234", patterns)
    assert hit is not None
    assert "GitHub" in hit.name


def test_find_secret_detects_private_key() -> None:
    patterns = load_patterns()
    content = "-----BEGIN RSA PRIVATE KEY-----\nMIIE...\n"
    hit = find_secret(content, patterns)
    assert hit is not None


def test_find_secret_ignores_clean_code() -> None:
    patterns = load_patterns()
    content = "export function add(a: number, b: number) { return a + b; }"
    assert find_secret(content, patterns) is None


def test_find_secret_detects_kakao_rest_key() -> None:
    patterns = load_patterns()
    hit = find_secret(
        "const KAKAO_REST_API_KEY = 'abcdef0123456789abcdef0123456789';",
        patterns,
    )
    assert hit is not None
    assert "Kakao" in hit.name


def test_find_secret_detects_ncp_secret() -> None:
    patterns = load_patterns()
    content = 'NCP_SECRET_KEY="abcdef0123456789abcdef0123456789abcdef01"'
    hit = find_secret(content, patterns)
    assert hit is not None
    assert "Naver" in hit.name


def test_find_secret_detects_toss_secret() -> None:
    patterns = load_patterns()
    hit = find_secret("apiKey: 'test_sk_abcdefghijklmnopqrstuvwxyz'", patterns)
    assert hit is not None
    assert "Toss" in hit.name


def test_test_fixture_path_exemption() -> None:
    from block_secret_files import is_test_fixture_path
    assert is_test_fixture_path("tests/test_block_secret_files.py")
    assert is_test_fixture_path("src/feature/tests/test_login.ts")
    assert is_test_fixture_path("apps/api/tests/test_auth.py")
    # 테스트 외부 파일은 면제 대상 아님
    assert not is_test_fixture_path("src/config.ts")
    assert not is_test_fixture_path("src/auth.py")
    # tests/ 안이지만 test_ 접두어가 없으면 면제 안 함 (헬퍼 파일 등은 보호)
    assert not is_test_fixture_path("tests/fixtures.py")


# --- E2E: 훅 실행 ------------------------------------------------------------

def _run_hook(tool_name: str, tool_input: dict) -> subprocess.CompletedProcess[str]:
    hook = Path(__file__).resolve().parent.parent / ".claude" / "hooks" / "block_secret_files.py"
    payload = json.dumps({"tool_name": tool_name, "tool_input": tool_input})
    env = {
        **os.environ,
        "CLAUDE_PROJECT_DIR": str(Path(__file__).resolve().parent.parent),
    }
    return subprocess.run(
        [sys.executable, str(hook)],
        input=payload,
        capture_output=True,
        text=True,
        check=False,
        env=env,
    )


def test_e2e_blocks_env_file_write() -> None:
    result = _run_hook("Write", {"file_path": ".env.production", "content": "DB=x"})
    assert result.returncode == 2
    assert "시크릿 환경파일" in result.stderr


def test_e2e_allows_env_example_write() -> None:
    result = _run_hook(
        "Write",
        {"file_path": ".env.example", "content": "DATABASE_URL=\nJWT_SECRET=\n"},
    )
    assert result.returncode == 0


def test_e2e_blocks_secret_in_content() -> None:
    result = _run_hook(
        "Write",
        {
            "file_path": "src/config.ts",
            "content": "const AWS = 'AKIAIOSFODNN7EXAMPLE';",
        },
    )
    assert result.returncode == 2
    assert "시크릿으로 추정" in result.stderr


def test_e2e_allows_clean_content() -> None:
    result = _run_hook(
        "Write",
        {"file_path": "src/util.ts", "content": "export const PI = 3.14;"},
    )
    assert result.returncode == 0

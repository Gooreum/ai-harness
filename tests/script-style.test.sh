#!/usr/bin/env bash
# 스크립트 공통 실수를 찾는다.
# - "$이름을"처럼 변수 바로 뒤에 한글이 오면, 로케일에 따라 bash가 한글 바이트까지 변수 이름으로 읽어
#   "unbound variable"로 멈춘다(2026-11-06 e2e의 "$destination_label을"). "${이름}을"로 쓴다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
cd "$here/.."

files="$(ls template/scripts/harness/* plugin/hooks/*.sh scripts/detect scripts/init scripts/sync)"
# shellcheck disable=SC2086
found="$(LC_ALL=C grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^ -~]' $files || true)"
assert_eq "변수 바로 뒤에 한글을 붙이지 않는다 (\${이름}으로 쓴다)" "" "$found"

finish

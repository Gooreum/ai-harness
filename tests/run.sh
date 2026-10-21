#!/usr/bin/env bash
# tests/*.test.sh를 모두 실행한다. 하나라도 실패하면 0이 아닌 코드로 끝난다.
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
status=0
for t in "$here"/*.test.sh; do
  bash "$t" || status=1
done
exit "$status"

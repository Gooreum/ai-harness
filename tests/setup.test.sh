#!/usr/bin/env bash
# setup: 설정을 정하는 안내만 내고 파일은 쓰지 않는지, 찾은 명령·추천 검사·생성 파일 단서를 보여 주는지 검사한다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
t="$here/../template/scripts/harness"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

p="$work/app"
mkdir -p "$p/scripts/harness" "$p/.harness"
cp "$t/lib.sh" "$t/setup" "$t/common-checks.json" "$p/scripts/harness/"
echo '{"schemaVersion":2}' > "$p/.harness/project.json"
echo '{"scripts":{"test":"jest","typecheck":"tsc"},"devDependencies":{"jest":"29"}}' > "$p/package.json"
touch "$p/pnpm-lock.yaml"
(cd "$p" && git init -q -b main)
has() { case "$out" in *"$1"*) echo yes ;; *) echo no ;; esac; }

out="$(cd "$p" && scripts/harness/setup)"
assert_eq "파일을 쓰지 않는다" "no" "$([ -f "$p/.harness/checks.json" ] && echo yes || echo no)"
assert_eq "찾은 명령을 보여 준다 (패키지 관리자 반영)" "yes" "$(has "pnpm test")"
assert_eq "근거를 보여 준다" "yes" "$(has "package.json scripts.typecheck")"
assert_eq "jest면 바뀐 파일 관련 테스트 명령도 보여 준다" "yes" "$(has "npx jest --findRelatedTests")"
assert_eq "공통 추천 검사(review)를 보여 준다" "yes" "$(has "review")"
assert_eq "생성 파일·보호할 파일을 묻게 한다" "yesyes" "$(has "자동 생성 파일")$(has "Edit(<글롭>)")"
assert_eq "단서가 없으면 없다고 한다" "yes" "$(has "단서:
  (없다)")"
assert_eq "사용자에게 묻게 한다" "yes" "$(has "AskUserQuestion")"
assert_eq "record로 돌리게 한다" "yes" "$(has "scripts/harness/record test")"
assert_eq "E2E가 없으면 둘지 묻게 한다" "yesyes" "$(has "E2E):
  (찾지 못했다")$(has "테스트(E2E)가 없습니다. 둘까요?")"
mkdir -p "$p/.maestro"
out="$(cd "$p" && scripts/harness/setup)"
assert_eq "Maestro 시나리오가 있으면 E2E 단서로 보여 준다" "yes" "$(has ".maestro/ (Maestro 시나리오)")"
rmdir "$p/.maestro"

assert_eq "위키 단계 지시가 없으면 둘지 묻게 한다" "yesyes" "$(has "위키) 단계 지시:
  없다")$(has "⑥ 위키 단계 지시가 없으면")"
assert_eq "추천 위키 지시는 common-checks.json에 있다" "plan implement finish" "$(jq -r '.stages | keys_unsorted | join(" ")' "$p/scripts/harness/common-checks.json")"
echo '{"schemaVersion":1,"checks":[]}' > "$p/.harness/checks.json"
out="$(cd "$p" && scripts/harness/setup)"
assert_eq "이미 있으면 바꿀 부분만 묻게 한다" "yes" "$(has "이미 검사 목록이 있다")"
jq --slurpfile c "$p/scripts/harness/common-checks.json" '. + {stages: $c[0].stages}' "$p/.harness/checks.json" > "$work/c.json" && mv "$work/c.json" "$p/.harness/checks.json"
out="$(cd "$p" && scripts/harness/setup)"
assert_eq "위키 지시가 이미 있으면 그렇다고 한다" "yes" "$(has "이미 있다 (checks.json의 stages)")"
echo '{"schemaVersion":1,"checks":[],"wiki":false}' > "$p/.harness/checks.json"
out="$(cd "$p" && scripts/harness/setup)"
assert_eq "위키를 끄기로 했으면 그렇다고 한다" "yes" "$(has "쓰지 않기로 했다")"

rm "$p/package.json" "$p/.harness/checks.json"
out="$(cd "$p" && scripts/harness/setup)"
assert_eq "찾은 것이 없으면 사용자에게 묻게 한다" "yes" "$(has "찾지 못했다")"
assert_eq "찾은 명령이 없어도 E2E 단서 확인이 실패하지 않는다" "yes" "$(has "앱을 띄워 확인하는 테스트(E2E):")"

mkdir -p "$p/App.xcodeproj"
out="$(cd "$p" && scripts/harness/setup)"
assert_eq "Xcode 프로젝트면 pbxproj를 막을지 묻게 한다" "yes" "$(has "project.pbxproj는 손으로 고치면")"
touch "$p/Project.swift"
out="$(cd "$p" && scripts/harness/setup)"
assert_eq "Tuist면 생성물 글롭을 단서로 보여 준다" "yes" "$(has "*.xcodeproj/*, *.xcworkspace/*")"
rm -rf "$p/App.xcodeproj" "$p/Project.swift"

echo '{"dependencies":{"expo":"52"}}' > "$p/package.json"
printf 'ios/\n' > "$p/.gitignore"
out="$(cd "$p" && scripts/harness/setup)"
assert_eq "Expo가 무시하는 ios/는 생성물 단서로 보여 준다" "yes|no" "$(has "prebuild 생성물일 수 있다: ios/*")|$(has "android/*")"
rm "$p/package.json" "$p/.gitignore"

mkdir -p "$p/tests" && touch "$p/tests/run.sh" "$p/tests/a.bats" "$p/Package.swift"
out="$(cd "$p" && scripts/harness/setup)"
assert_eq "tests/run.sh를 찾는다" "yes" "$(has "bash tests/run.sh")"
assert_eq "bats 파일을 찾는다" "yes" "$(has "bats -r .")"
assert_eq "Swift 패키지는 swift test를 찾는다" "yes" "$(has "swift test")"
mkdir -p "$p/scripts/ios" && printf '#!/bin/sh\n' > "$p/scripts/ios/unit-test" && chmod +x "$p/scripts/ios/unit-test" && touch "$p/scripts/ios/lib.sh"
out="$(cd "$p" && scripts/harness/setup)"
assert_eq "저장소 스크립트를 찾고 하네스 것·source용은 뺀다" "yes|no|no" "$(has "scripts/ios/unit-test")|$(has "scripts/ios/lib.sh")|$(has "  - passed ")"

finish

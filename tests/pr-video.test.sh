#!/usr/bin/env bash
# scripts/harness/pr-video: 이번 작업에서 찍은 영상만 골라 PR에 올릴 크기로 바꾼다.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
. "$here/lib.sh"
prv="$here/../template/scripts/harness/pr-video"
work="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$work"' EXIT

p="$work/app"
mkdir -p "$p/.harness/out" "$p/.harness/state"
echo '{"schemaVersion":2}' > "$p/.harness/project.json"
(cd "$p" && git init -q -b main)
o="$p/.harness/out"

run() { (cd "$p" && "$prv" "$@" 2>&1) && echo "rc=0" || echo "rc=$?"; }

assert_eq "영상이 없으면 출력 없이 0" "rc=0" "$(run)"

touch -t 202601010100 "$p/.harness/state/task.started"
echo x > "$o/e2e.mp4"
touch -t 202601010000 "$o/e2e.mp4"
assert_eq "작업을 시작하기 전 영상은 고르지 않는다" "rc=0" "$(run)"

touch -t 202601010200 "$o/e2e.mp4"
out="$(run)"
assert_eq "영상이 아니면 변환 실패로 2" "rc=2" "$(printf '%s\n' "$out" | sed -n '$p')"
assert_eq "  어느 파일인지 알린다" "harness: 영상 변환 실패: $o/e2e.mp4 (avconvert --preset Preset960x540)" "$(printf '%s\n' "$out" | sed -n 1p)"

# 실제 변환은 시험용 영상을 만들 수 있을 때만 본다(ffmpeg는 macOS 기본 도구가 아니다).
if command -v ffmpeg > /dev/null 2>&1 && command -v avconvert > /dev/null 2>&1; then
  ffmpeg -v error -y -f lavfi -i testsrc=duration=3:size=1206x2622:rate=30 -c:v libx264 -pix_fmt yuv420p "$o/e2e.mp4"
  cp "$o/e2e.mp4" "$o/e2e-before.mp4"
  out="$(run)"
  assert_eq "수정 전을 먼저, 탭으로 제목과 경로" "$(printf '수정 전\t%s\n수정 후\t%s\nrc=0' "$o/pr-video/e2e-before.mp4" "$o/pr-video/e2e.mp4")" "$out"
  assert_eq "  H.264로 바꾼다" "h264" "$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$o/pr-video/e2e.mp4")"

  rm "$o/e2e-before.mp4"
  avconvert --source "$o/e2e.mp4" --preset Preset640x480 --output "$work/small.mp4" --replace > /dev/null 2>&1
  small="$(stat -f %z "$work/small.mp4")"
  out="$(HARNESS_PR_VIDEO_LIMIT=$((small * 7 / 10)) run)"
  assert_eq "줄여도 크면 같은 길이로 나눈다" "$(printf '수정 후 (1/3)\t%s\n수정 후 (2/3)\t%s\n수정 후 (3/3)\t%s\nrc=0' "$o/pr-video/e2e-1.mp4" "$o/pr-video/e2e-2.mp4" "$o/pr-video/e2e-3.mp4")" "$out"
  [ ! -e "$o/pr-video/e2e-before.mp4" ] && gone=yes || gone=no
  assert_eq "  지난 결과는 지운다" "yes" "$gone"
fi

finish

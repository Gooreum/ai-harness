#!/usr/bin/env bash
# 지금 단계에서 할 일(지시 글)을 출력한다. stage-context.sh(작업을 시작할 때)와 stop-gate.sh(단계를 넘길 때)가 같이 부른다.
# 인자: task.json 경로, checks.json 경로(없거나 JSON이 아니면 빈 값), 프로젝트 루트
#
# 글은 stage-text.jq가 만든다. 이 스크립트는 jq가 못 하는 파일 읽기만 한다.
#   - stages.<단계>.prompt_file이 있으면 프로젝트 안의 그 파일을 읽어 지시에 붙인다(ai-bouncer의 prompt_file, ADR 0030).
#     에이전트가 읽지 않고 넘어갈 수 없게 하려고 훅이 내용을 그대로 넣는다.
#   - 파일이 없거나 프로젝트 밖 경로면 내용 대신 그 사실을 지시에 넣는다. 막지는 않는다.
set -uo pipefail

state="$1"
checks="${2:-}"
root="$3"
here="$(dirname "$0")"
flows="$(cat "$here/flows.json" 2> /dev/null)" || exit 1
conf='{}'
[ -z "$checks" ] || conf="$(cat "$checks" 2> /dev/null)" || conf='{}'

stage="$(jq -r '.stage // ""' "$state" 2> /dev/null)" || stage=""
pf="$(jq -r --arg s "$stage" '.stages[$s].prompt_file // empty' <<< "$conf" 2> /dev/null)" || pf=""
doc=""
doc_err=""
if [ -n "$pf" ]; then
  case "/$pf/" in
    //* | */../*) doc_err="프로젝트 안의 상대 경로가 아니다" ;;
    *)
      if [ ! -f "$root/$pf" ]; then
        doc_err="파일이 없다"
      else
        # 링크가 프로젝트 밖을 가리키면 읽지 않는다. 링크를 따라간 실제 경로가 프로젝트 안인지 본다.
        real="$root/$pf"
        hops=0
        while [ -L "$real" ] && [ "$hops" -lt 20 ]; do
          link="$(readlink "$real")"
          case "$link" in /*) real="$link" ;; *) real="$(dirname "$real")/$link" ;; esac
          hops=$((hops + 1))
        done
        real="$(cd "$(dirname "$real")" 2> /dev/null && pwd -P)/$(basename "$real")"
        case "$real" in
          "$(cd "$root" && pwd -P)"/*) doc="$(cat "$real")" ;;
          *) doc_err="프로젝트 안의 상대 경로가 아니다" ;;
        esac
      fi
      ;;
  esac
fi

jq -r --argjson flows "$flows" --slurpfile conf <(printf '%s' "$conf") \
  --arg pf "$pf" --arg doc "$doc" --arg doc_err "$doc_err" \
  -f "$here/stage-text.jq" "$state"

# 테스트 공용 함수. 각 *.test.sh가 source한다.
# 통과는 개수만 세고, 실패만 자세히 출력한다.

TESTS_PASSED=0
TESTS_FAILED=0

# assert_eq 이름 기대값 실제값
assert_eq() {
  if [ "$2" = "$3" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf '  실패: %s\n    기대: %s\n    실제: %s\n' "$1" "$2" "$3"
  fi
}

# finish — 파일별 한 줄 요약을 출력하고, 실패가 있으면 1을 반환한다.
finish() {
  printf '%s: 통과 %d, 실패 %d\n' "$(basename "$0")" "$TESTS_PASSED" "$TESTS_FAILED"
  [ "$TESTS_FAILED" -eq 0 ]
}

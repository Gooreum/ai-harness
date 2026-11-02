<!-- Claude Code는 v2.1.277부터 AGENTS.md를 직접 읽지만, 그보다 낮은 버전과 CLAUDE.md가 있는 경우를 위해 import한다. -->
@AGENTS.md

## 하네스 작업 전 필수 확인 (생략 금지)

이 저장소에서 하네스를 바꾸는 작업(코드·스크립트·template·plugin·문서)을 시작하기 전에 **매번** 아래 세 가지를 직접 열어 읽는다.
기억이나 요약에 기대지 않는다. 질문에 답만 하는 경우는 해당 없다.

1. **발표 전문** — 여기어때 안드로이드 팀(강래민·백다연) "Workflow AX 적용기" (DroidKnights 2026). 하네스 설계 기준이다(ADR 0005).
   - 발표 전사: `docs/talk/workflow-ax-transcript.md`
   - 슬라이드와 발표자 노트: `docs/talk/workflow-ax-slides-notes.txt` (수치·용어는 전사보다 이쪽이 정확하다)
   - 두 파일은 git에 올리지 않는 로컬 사본이다. 없으면 원본을 읽는다.
     - 전사: <https://claude.ai/artifact/SK8EowGXyMV4x2hSCMNi8t>의 "발표 전문" 탭 (Claude Docs 커넥터 `read`·`export`)
     - 슬라이드: <https://claude.ai/artifact/KBRFrrtvkB8RUB2TJFVGaP>
     - 원본도 읽을 수 없으면 작업을 멈추고 사용자에게 알린다.
2. **로드맵** — `docs/roadmap.md`의 해당 단위(할 일·완료 기준)와 "만들지 않는 것" 목록.
3. 작업 단위와 관련된 발표 부분을 찾아 설계에 반영한다. 발표 내용과 다르게 만들려면 이유를 ADR에 남긴다.

작업 계획이나 첫 보고에 **"확인한 자료"** 한 줄을 적는다. 읽은 파일과 발표의 어느 부분(소제목·슬라이드 번호)을 근거로 했는지 쓴다. 이 줄이 없으면 확인하지 않은 것으로 본다.

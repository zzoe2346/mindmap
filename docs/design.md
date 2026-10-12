# 화면 기준

확인일 2026-10-12. 참고: 꼬꼬무와 배우자의 docs/design.md.

Apple 공식 근거:
- https://developer.apple.com/design/human-interface-guidelines/toolbars
- https://developer.apple.com/design/human-interface-guidelines/keyboards
- https://developer.apple.com/design/human-interface-guidelines/undo-and-redo
- https://developer.apple.com/documentation/appkit/nsdocument
- https://developer.apple.com/documentation/appkit/nsdocument/autosavesinplace

표준 AppKit 창, 메뉴, 툴바와 SwiftUI 속성 패널을 사용한다. 캔버스는 문서 편집에 맞춘 AppKit 뷰다.
본문은 불투명한 시스템 배경으로 읽기 쉽게 유지하고 기본 시스템 툴바 재질에 맡긴다.
토픽과 관계선 선택은 색과 테두리로 구분한다. 관계선 편집은 선택했을 때 속성을 공개한다.
삭제, 편집, 연결과 확대 명령을 메뉴에 표시하고 단축키를 제공한다.
네이티브 텍스트 편집기로 한글 조합과 붙여넣기를 처리한다.
글자 크기는 14~28pt, 테마는 시스템/밝게/어둡게를 제공한다.
실제 화면 검사와 제한 사항은 qa.md에 별도로 기록한다.

## XMind 실제 화면 참고

2026-10-12 사용자가 연 Chrome의 XMind 문서를 읽기 전용으로 관찰했다.
- 긴 설명이 여러 줄로 표시되는 오른쪽 방향 트리와 색상 가지.
- 선택 테두리, 가지 끝의 접기 버튼, 오른쪽 속성 패널.
- 컨텍스트 메뉴의 토픽 편집/삭제/접기와 관계선 도구 설명.
- 관계선 ⇧⌘R, 접기 ⌘/ 단축키.
이 조작을 자체 데이터 모델과 네이티브 화면으로 구현한다. 웹 앱의 코드나 자산을 복사하지 않는다.
기존 맵 변경 없이 선택과 속성 패널, 메뉴만 확인했다. 실제 연결 완료/곡선 편집은 관찰하지 않았으므로
그 부분은 사용자 요구에 맞춰 독립적으로 설계한다.

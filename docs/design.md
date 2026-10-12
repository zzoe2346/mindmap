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

## 편집 UX와 홈

2026-10-12 설치된 XMind의 홈 카드와 편집 화면을 직접 확인했다. 같은 날 사용자 승인을 받아 구현했다.

- 토픽 중앙은 새 부모, 상하 가장자리와 인접 빈 공간은 형제 삽입 위치로 해석한다.
- 초록색 부모 강조와 파란 삽입 선을 구분한다. 드래그 중 반투명 제목 또는 선택 수를 표시한다.
- Command 또는 Shift 클릭으로 다중 선택하고, 한 번의 이동은 한 번의 실행 취소로 기록한다.
- 선택 상태의 문자 입력은 새 제목 입력을 시작한다. 더블클릭은 누른 위치에서 기존 텍스트를 편집한다.
- AppKit NSTextView를 실제 first responder로 사용한다. 직접 한글 조합기를 재구현하지 않는다.
- 텍스트 편집과 캔버스 렌더링에 같은 시스템 글꼴과 크기, 안쪽 여백을 적용한다.
- 편집 토픽의 위치를 유지하면서 주변 트리를 다시 배치한다. 너비는 자동 또는 120~600pt로 조절한다.
- 홈은 왼쪽 최근 문서/즐겨찾기, 상단 검색/새 문서, 본문 미리보기 카드로 구성한다.
- 속성 패널의 중복 추가/연결 버튼을 줄이고 토픽 너비와 관계선 설정에 집중한다.

Apple 공식 API를 확인해 적용한 근거:
- https://developer.apple.com/documentation/appkit/nstextinputclient : 시스템 입력 체계를 사용하고 조합 중 Enter/Tab/Esc를 가로채지 않는다.
- https://developer.apple.com/documentation/appkit/nsdocumentcontroller/recentdocumenturls : OS 최근 문서와 자체 보관한 경로로 홈 목록을 구성한다.
- 설치 SDK의 NSDocument.h renameDocument: : 홈 이름 변경은 네이티브 문서 이름 변경 UI에 위임한다.

## 홈 앱 아이콘 통일

2026-10-12 사용자 요청으로 홈 이름 옆의 별도 SF Symbol을 앱 아이콘으로 교체했다.
원본 비율의 32pt 이미지로 앱과 홈이 같은 아이콘을 사용한다. Composer 적용 전에는 NSApplication.applicationIconImage를 읽었으며, 현재는 번들의 컴파일된 AppIcon.icns를 직접 읽는다.
앱 이름이 옆에 있으므로 장식 이미지는 접근성 읽기에서 제외한다.
근거: https://developer.apple.com/documentation/appkit/nsapplication/applicationiconimage

## Icon Composer 적용 (2026-10-12)

기존 가지 심볼을 SVG 레이어로 옮겼다. 중심 생각을 전경 그룹, 세 가지를 배경 그룹으로 구성해 겹치는 부분을 가리고 Liquid Glass, 그림자와 반투명 효과를 적용했다. macOS Default, Dark, Mono는 Icon Composer에서 제공한다. 흰 배경을 사용한다.

앱은 actool의 AppIcon.icns와 Assets.car, CFBundleIconName을 사용하고 홈은 번들의 AppIcon.icns를 직접 읽어 시스템 아이콘 캐시가 오래된 이미지를 반환하는 경우에도 현재 자산을 표시한다. 리소스를 읽을 수 없을 때만 applicationIconImage를 대체 이미지로 사용한다. 공개용 이미지는 같은 Composer 렌더링의 외곽 투명을 흰색으로 채워 표 배경이 이미지 안으로 비치지 않게 한다. 시스템 아이콘용 모서리와 투명 처리는 네이티브 자산에 맡긴다.

근거: [Apple: Creating your app icon using Icon Composer](https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer), [Create icons with Icon Composer](https://developer.apple.com/videos/play/wwdc2025/361/). SVG 레이어와 하나의 .icon 문서에서 플랫폼별 외형을 생성하는 방식을 적용했다. 로컬 Xcode의 ictool --help와 actool 컴파일 결과로 인자를 확인했다.

홈 이미지 로딩 근거: https://developer.apple.com/documentation/appkit/nsimage/init(contentsof:)

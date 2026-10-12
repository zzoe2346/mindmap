# 구조와 저장 계약

- MindmapCore: 버전이 있는 Codable 값 모델, 트리 변경과 무결성 검증, 자동 배치.
- MindmapApp: NSDocument 문서 수명과 저장, 메인 액터 편집 세션, AppKit 캔버스, SwiftUI 속성 패널.
- JSON 문서에 토픽 UUID/부모 UUID/순서/가지 방향/접힘, 관계 UUID/양끝/설명/화살표/곡률을 저장한다.
- formatVersion=1. 단일 루트, 유일 ID, 부모 존재, 모든 노드 연결, 순환 금지, 관계 양끝 존재를 로드 시 검증한다.
- 문서 변경마다 NSUndoManager에 이전 값 스냅샷을 등록한다. 드래그와 제목 편집은 완료 시 한 번 반영한다.
- NSDocument의 autosavesInPlace와 autosavesDrafts를 사용한다. 저장 위치를 정하기 전 초안도 시스템 복구에 참여한다.
- 저장은 NSDocument의 안전한 쓰기 경로에 맡긴다. 읽기 실패는 사용자 오류로 표시하며 기존 문서를 교체하지 않는다.
- 선택과 줌/팬은 창 상태, 토픽 글자 크기와 테마는 앱 설정이다. 캔버스 배치는 토픽 트리에서 계산한다.

# 개발

Swift 6, macOS 26 이상, Xcode의 macOS SDK가 필요합니다. 외부 패키지나 서버는 없습니다.
시스템 xcode-select를 바꾸지 않고 스크립트 내부에서만 Xcode 경로를 선택합니다.

```sh
./scripts/format.sh
./scripts/check.sh
./scripts/package.sh
```

check는 Swift 포맷 strict 검사, Core와 App의 테스트, Release 빌드, ad-hoc 서명 검증을 수행합니다.
결과는 dist/mindmap.app입니다. 개발자 인증서/공증을 통한 외부 배포 패키지가 아닌 개인 로컬 실행용입니다.
빌드 도구의 캐시와 dSYM 생성이 제한된 샌드박스에서는 빌드 권한이 필요할 수 있습니다.

Sources/MindmapCore는 트리와 관계선, 직렬화, 배치를 담당하고 Sources/MindmapApp은 네이티브 편집기를 담당합니다.
앱 식별자는 com.jeongseonghun.mindmap, 문서 형식 버전은 1입니다. 표시 이름 변경 시 이 식별자와 문서 호환성을 보존합니다.
Tests는 순환 방지, 가지 삭제, 접힘, 배치, 저장 왕복, 손상 파일 거부, 실제 NSUndoManager의 복구를 검사합니다.

스크린샷은 CUA로 실행 중인 앱 창을 캡처합니다. QA 앱은 work/qa에 별도 번들 식별자로 생성해 테스트했습니다.
개인 문서와 임시 빌드, QA 산출물은 Git에서 제외합니다.

아이콘을 재생성하려면 toolchain.sh를 읽은 셸에서 다음을 실행합니다.

```sh
xcrun swift -module-cache-path .build/module-cache scripts/icon.swift work/AppIcon.iconset AppResources/AppIcon.icns
```

import AppKit

@main
struct MindmapMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) { buildMenus() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSDocumentController.shared.autosavingDelay = 2
        if NSDocumentController.shared.documents.isEmpty { NSDocumentController.shared.newDocument(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSDocumentController.shared.newDocument(nil) }
        return true
    }
    private func buildMenus() {
        let main = NSMenu()
        NSApp.mainMenu = main
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem()
            main.addItem(item)
            let result = NSMenu(title: title)
            item.submenu = result
            return result
        }
        func item(
            _ menu: NSMenu, _ title: String, _ action: Selector, _ key: String = "",
            _ modifiers: NSEvent.ModifierFlags = .command
        ) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            menu.addItem(item)
        }
        let app = menu("mindmap")
        item(app, "mindmap 정보", #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        app.addItem(.separator())
        item(app, "mindmap 가리기", #selector(NSApplication.hide(_:)), "h")
        app.addItem(.separator())
        item(app, "mindmap 종료", #selector(NSApplication.terminate(_:)), "q")
        let file = menu("파일")
        item(file, "새 마인드맵", #selector(NSDocumentController.newDocument(_:)), "n")
        item(file, "열기…", #selector(NSDocumentController.openDocument(_:)), "o")
        file.addItem(.separator())
        item(file, "저장", #selector(NSDocument.save(_:)), "s")
        item(file, "다른 이름으로 저장…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift])
        file.addItem(.separator())
        item(file, "창 닫기", #selector(NSWindow.performClose(_:)), "w")
        let edit = menu("편집")
        item(edit, "실행 취소", Selector(("undo:")), "z")
        item(edit, "다시 실행", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        item(edit, "잘라내기", #selector(NSText.cut(_:)), "x")
        item(edit, "복사", #selector(NSText.copy(_:)), "c")
        item(edit, "붙여넣기", #selector(NSText.paste(_:)), "v")
        item(edit, "전체 선택", #selector(NSText.selectAll(_:)), "a")
        let topic = menu("토픽")
        item(topic, "하위 토픽 추가", #selector(EditorController.addChildTopic(_:)), "\t", [])
        item(topic, "형제 토픽 추가", #selector(EditorController.addSibling(_:)), "\r", [])
        item(topic, "제목 편집", #selector(EditorController.editTopic(_:)), "\r", .command)
        item(topic, "선택 항목 삭제", #selector(EditorController.deleteItem(_:)), "\u{8}", [])
        topic.addItem(.separator())
        item(topic, "관계선 연결", #selector(EditorController.connect(_:)), "r", [.command, .shift])
        item(topic, "가지 접기/펼치기", #selector(EditorController.fold(_:)), "/")
        let view = menu("보기")
        item(view, "확대", #selector(EditorController.zoomIn(_:)), "=")
        item(view, "축소", #selector(EditorController.zoomOut(_:)), "-")
        item(view, "전체 보기", #selector(EditorController.fit(_:)), "0")
        item(view, "실제 크기", #selector(EditorController.actualSize(_:)), "1")
        view.addItem(.separator())
        item(view, "속성 패널 보기/가리기", #selector(EditorController.toggleInspector(_:)), "i", [.command, .option])
        let window = menu("윈도우")
        NSApp.windowsMenu = window
        item(window, "최소화", #selector(NSWindow.performMiniaturize(_:)), "m")
        item(window, "확대/축소", #selector(NSWindow.performZoom(_:)))
        let help = menu("도움말")
        let guide = NSMenuItem(title: "mindmap 사용법", action: #selector(showHelp(_:)), keyEquivalent: "?")
        guide.target = self
        help.addItem(guide)
    }
    @objc func showHelp(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "mindmap 사용법"
        alert.informativeText =
            "토픽 선택 후 Tab: 하위 추가\nEnter: 형제 추가\n더블 클릭 또는 ⌘Enter: 제목 편집\n편집 중 Enter: 완료 / ⇧Enter: 줄바꿈\n⌘/: 가지 접기와 펼치기\n⇧⌘R: 관계선 연결 후 대상 클릭\n관계선 선택: 설명, 화살표, 곡률 변경\n드래그: 다른 토픽에 놓아 부모 변경\n빈 공간 드래그 또는 트랙패드: 화면 이동\n핀치 또는 ⌘+/−: 확대와 축소\n⌘0: 전체 보기\n⌘S: 저장 / ⌘Z: 실행 취소\n\n파일은 Mac에만 저장됩니다."
        alert.runModal()
    }
}

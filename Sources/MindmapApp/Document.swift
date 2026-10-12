import AppKit
import Combine
import MindmapCore

@MainActor final class EditorSession: ObservableObject {
    @Published var map = MindMap()
    @Published var selectedTopic: UUID?
    @Published var selectedTopics: Set<UUID> = []
    @Published var selectedRelation: UUID?
    @Published var connectingFrom: UUID?
    @Published var zoom: Double = 1
    @Published var message = "Tab: 하위 추가    Enter: 형제 추가    더블 클릭: 편집"
    @Published var fontSize: Double =
        UserDefaults.standard.double(forKey: "fontSize") == 0
        ? 17 : UserDefaults.standard.double(forKey: "fontSize")
    @Published var theme = UserDefaults.standard.string(forKey: "theme") ?? "system"
    weak var document: MindmapDocument?
    weak var canvas: MapCanvas?
    func selectTopic(_ id: UUID) {
        selectedTopics = [id]
        selectedTopic = id
        selectedRelation = nil
    }
    func selectRelation(_ id: UUID) {
        selectedRelation = id
        selectedTopic = nil
        selectedTopics = []
    }
    func change(_ name: String, _ update: (inout MindMap) -> Void) {
        var copy = map
        update(&copy)
        guard copy != map else { return }
        do {
            try copy.validate()
            document?.apply(copy, name: name)
        } catch { document?.presentError(error) }
    }
    func add(child: Bool) {
        if !child, connectingFrom != nil, let selectedTopic {
            connect(to: selectedTopic)
            return
        }
        canvas?.finishEditing()
        guard let id = selectedTopic, let topic = map.topic(id) else { return }
        var newID: UUID?
        change(child ? "하위 토픽 추가" : "형제 토픽 추가") { map in
            newID = map.addChild(to: child ? id : (topic.parentID ?? id), after: child ? nil : id)
        }
        if let newID {
            selectTopic(newID)
            canvas?.rebuild()
            canvas?.reveal(newID)
            canvas?.beginEditing()
        }
    }
    func deleteSelection() {
        canvas?.finishEditing()
        if let edge = selectedRelation {
            change("관계선 삭제") { $0.relationships.removeAll { $0.id == edge } }
            selectedRelation = nil
        } else if let id = selectedTopic, let parent = map.topic(id)?.parentID {
            let roots = map.selectionRoots(selection)
            change("토픽 삭제") { map in for root in roots { map.remove(root) } }
            selectTopic(parent)
        }
        canvas?.window?.makeFirstResponder(canvas)
    }
    func toggleFold() {
        guard let id = selectedTopic, !map.children(id).isEmpty else { return }
        change("가지 접기/펼치기") { map in
            if let index = map.topics.firstIndex(where: { $0.id == id }) {
                map.topics[index].collapsed.toggle()
            }
        }
    }
    func beginRelationship() {
        canvas?.finishEditing()
        guard let id = selectedTopic else { return }
        connectingFrom = id
        message = "대상 토픽을 클릭하거나 방향키로 선택 후 Enter를 누르세요. Esc로 취소합니다."
        canvas?.window?.makeFirstResponder(canvas)
    }
    func cancelConnecting() {
        connectingFrom = nil
        message = "Tab: 하위 추가    Enter: 형제 추가    더블 클릭: 편집"
    }
    func connect(to id: UUID) {
        guard let source = connectingFrom, source != id else { return }
        var result: UUID?
        change("관계선 추가") { result = $0.connect(source, id) }
        cancelConnecting()
        if let result { selectRelation(result) }
    }
    func updateRelation(_ name: String, _ update: (inout Relationship) -> Void) {
        guard let id = selectedRelation else { return }
        change(name) { map in
            if let index = map.relationships.firstIndex(where: { $0.id == id }) {
                update(&map.relationships[index])
            }
        }
    }
    func applyPreferences() {
        UserDefaults.standard.set(fontSize, forKey: "fontSize")
        UserDefaults.standard.set(theme, forKey: "theme")
        canvas?.window?.appearance =
            theme == "light"
            ? NSAppearance(named: .aqua) : theme == "dark" ? NSAppearance(named: .darkAqua) : nil
        canvas?.rebuild()
    }
}

@objc(MindmapDocument)
final class MindmapDocument: NSDocument {
    let session = EditorSession()
    let libraryID = UUID()
    override var fileURL: URL? {
        didSet {
            if let fileURL {
                Task { @MainActor [weak self] in
                    LibraryStore.shared.relocated(from: oldValue, to: fileURL, draftID: self?.libraryID)
                }
            }
        }
    }
    override init() {
        super.init()
        session.document = self
        session.selectedTopic = session.map.root.id
        hasUndoManager = true
        fileType = "com.jeongseonghun.mindmap.document"
    }
    override class var readableTypes: [String] { ["com.jeongseonghun.mindmap.document"] }
    override class var writableTypes: [String] { readableTypes }
    override class func isNativeType(_ type: String) -> Bool { type == "com.jeongseonghun.mindmap.document" }
    nonisolated override func fileNameExtension(
        forType typeName: String, saveOperation: NSDocument.SaveOperationType
    ) -> String? { "mindmap" }
    nonisolated override class var autosavesInPlace: Bool { true }
    nonisolated override class var autosavesDrafts: Bool { true }
    override func data(ofType typeName: String) throws -> Data {
        try (session.canvas?.mapForSaving ?? session.map).encoded()
    }
    nonisolated override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool { false }
    override func read(from data: Data, ofType typeName: String) throws {
        let decoded = try MindMap.decode(data)
        // Concurrent document reading is disabled below; AppKit invokes this on its main thread.
        MainActor.assumeIsolated {
            session.map = decoded
            session.selectedTopic = decoded.root.id
            session.selectedRelation = nil
        }
    }
    func apply(_ value: MindMap, name: String) {
        let previous = session.map
        undoManager?.registerUndo(withTarget: self) { target in target.apply(previous, name: name) }
        undoManager?.setActionName(name)
        session.map = value
        session.selectedTopics.formIntersection(value.visibleIDs())
        if let id = session.selectedTopic, !value.visibleIDs().contains(id) {
            session.selectTopic(value.root.id)
        }
        if let id = session.selectedRelation, !value.relationships.contains(where: { $0.id == id }) {
            session.selectedRelation = nil
        }
        // NSDocument observes its undo manager to track changes and schedule autosaves.
    }
    override func makeWindowControllers() {
        let editor = EditorController(session: session)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 760, height: 520)
        window.contentViewController = editor
        window.title = "mindmap"
        window.center()
        let controller = NSWindowController(window: window)
        addWindowController(controller)
        editor.configureToolbar(window)
        window.makeFirstResponder(editor.canvas)
        session.applyPreferences()
    }
    override func save(_ sender: Any?) {
        session.canvas?.finishEditing()
        super.save(sender)
    }
    override func canClose(
        withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?,
        contextInfo: UnsafeMutableRawPointer?
    ) {
        session.canvas?.finishEditing()
        super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
    }
}

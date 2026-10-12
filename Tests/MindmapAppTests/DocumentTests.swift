import AppKit
import Foundation
import MindmapCore
import Testing

@testable import MindmapApp

@Test @MainActor func documentUndoRedoRestoresDeletedBranchAndRelation() throws {
    let document = MindmapDocument()
    let manager = try #require(document.undoManager)
    manager.groupsByEvent = false
    var map = MindMap()
    let child = try required(map.addChild(to: map.root.id, title: "보존할 한글"))
    map.connect(map.root.id, child)
    perform(document) { document.apply(map, name: "초기 맵") }
    manager.removeAllActions()
    var removed = map
    removed.remove(child)
    perform(document) { document.apply(removed, name: "토픽 삭제") }
    #expect(document.session.map.topics.count == 1)
    manager.undo()
    #expect(document.session.map == map)
    manager.redo()
    #expect(document.session.map == removed)
    manager.undo()
    let data = try document.data(ofType: "com.jeongseonghun.mindmap.document")
    #expect(try MindMap.decode(data) == map)
}
@Test @MainActor func failedReadPreservesOpenDocument() throws {
    let document = MindmapDocument()
    let original = document.session.map
    #expect(throws: (any Error).self) {
        try document.read(from: Data("invalid".utf8), ofType: "com.jeongseonghun.mindmap.document")
    }
    #expect(document.session.map == original)
}
@Test @MainActor func keyboardRelationshipAndUndo() throws {
    let document = MindmapDocument()
    document.undoManager?.groupsByEvent = false
    var map = MindMap()
    let child = try required(map.addChild(to: map.root.id))
    perform(document) { document.apply(map, name: "준비") }
    document.session.selectTopic(map.root.id)
    document.session.beginRelationship()
    document.session.selectTopic(child)
    perform(document) { document.session.add(child: false) }
    #expect(document.session.map.topics.count == 2)
    #expect(document.session.map.relationships.count == 1)
    #expect(document.session.connectingFrom == nil)
    document.undoManager?.undo()
    #expect(document.session.map.relationships.isEmpty)
}
private func required<T>(_ value: T?) throws -> T { try #require(value) }

@MainActor private func perform(_ document: MindmapDocument, action: () -> Void) {
    document.undoManager?.beginUndoGrouping()
    action()
    document.undoManager?.endUndoGrouping()
}

@Test @MainActor func dropZonesDistinguishReorderAndReparent() throws {
    let document = MindmapDocument()
    let session = document.session
    let a = try #require({ session.map.addChild(to: session.map.root.id, title: "첫째") }())
    let b = try #require({ session.map.addChild(to: session.map.root.id, title: "둘째") }())
    let canvas = MapCanvas(session: session)
    session.selectTopic(a)
    let rect = try #require(canvas.frames[b])
    let center = try #require(canvas.dropPlacement(at: CGPoint(x: rect.midX, y: rect.midY)))
    #expect(center.parent == b)
    #expect(center.lineY == nil)
    let above = try #require(canvas.dropPlacement(at: CGPoint(x: rect.midX, y: rect.minY - 8)))
    #expect(above.parent == session.map.root.id)
    #expect(above.before == b)
    #expect(above.lineY != nil)
    session.selectTopic(session.map.root.id)
    #expect(canvas.dropPlacement(at: CGPoint(x: rect.midX, y: rect.midY)) == nil)
}
@Test @MainActor func liveEditingSnapshotSavesAndCancelRestoresOriginal() throws {
    let document = MindmapDocument()
    let canvas = MapCanvas(session: document.session)
    document.session.selectTopic(document.session.map.root.id)
    canvas.beginEditing()
    canvas.replaceEditorText("작성 중 한글\n아직 확정하지 않은 문장")
    let saved = try MindMap.decode(document.data(ofType: "com.jeongseonghun.mindmap.document"))
    #expect(saved.root.title == "작성 중 한글\n아직 확정하지 않은 문장")
    #expect(document.session.map.root.title == "중심 주제")
    canvas.finishEditing(commit: false)
    #expect(
        try MindMap.decode(document.data(ofType: "com.jeongseonghun.mindmap.document")).root.title == "중심 주제")
}
@Test @MainActor func multiMoveUndoRestoresOrderAndParent() throws {
    let document = MindmapDocument()
    document.undoManager?.groupsByEvent = false
    let session = document.session
    let a = try #require({ session.map.addChild(to: session.map.root.id, title: "A") }())
    let b = try #require({ session.map.addChild(to: session.map.root.id, title: "B") }())
    let c = try #require({ session.map.addChild(to: session.map.root.id, title: "C") }())
    let original = session.map
    session.selectedTopic = a
    session.selectedTopics = [a, b]
    perform(document) { session.change("두 가지 이동") { $0.move([a, b], to: c) } }
    #expect(session.map.children(c).map(\.id) == [a, b])
    document.undoManager?.undo()
    #expect(session.map == original)
    document.undoManager?.redo()
    #expect(session.map.children(c).map(\.id) == [a, b])
}

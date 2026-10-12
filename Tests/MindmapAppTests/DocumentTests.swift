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

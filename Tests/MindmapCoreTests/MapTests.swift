import Foundation
import Testing

@testable import MindmapCore

@Test func editingAndRoundTripPreservesKoreanAndRelationships() throws {
    var map = MindMap(title: "공부할 내용")
    let first = try required(map.addChild(to: map.root.id, title: "긴 한글 설명\n두 번째 줄과 😀"))
    let second = try required(map.addChild(to: map.root.id, title: "다른 가지"))
    let child = try required(map.addChild(to: first, title: "하위"))
    let edge = try required(map.connect(child, second))
    map.relationships[0].label = "서로 영향을 줌"
    map.relationships[0].arrow = .both
    map.relationships[0].bend = -125
    map.layout = .balanced
    let reopened = try MindMap.decode(map.encoded())
    #expect(reopened == map)
    #expect(reopened.relationships[0].id == edge)
}
@Test func deletingBranchRemovesOnlyIncidentRelationships() throws {
    var map = MindMap()
    let a = try required(map.addChild(to: map.root.id))
    let b = try required(map.addChild(to: a))
    let c = try required(map.addChild(to: map.root.id))
    map.connect(b, c)
    map.connect(map.root.id, c)
    let snapshot = map
    map.remove(a)
    #expect(map.topics.count == 2)
    #expect(map.relationships.count == 1)
    #expect(map.relationships.first?.source == map.root.id)
    try map.validate()
    map = snapshot
    #expect(map.topics.count == 4)
    #expect(map.relationships.count == 2)
    map.remove(map.root.id)
    #expect(map == snapshot)
}
@Test func reparentRejectsCyclesAndExpandsDestination() throws {
    var map = MindMap()
    let a = try required(map.addChild(to: map.root.id))
    let b = try required(map.addChild(to: a))
    let c = try required(map.addChild(to: map.root.id))
    #expect({ !map.reparent(a, to: b) }())
    #expect({ !map.reparent(map.root.id, to: b) }())
    #expect({ !map.reparent(a, to: a) }())
    map.topics[3].collapsed = true
    #expect({ map.reparent(b, to: c) }())
    #expect(map.topic(b)?.parentID == c)
    #expect(map.topic(c)?.collapsed == false)
    try map.validate()
}
@Test func foldingPreservesHiddenRelationsAndNewChildExpands() throws {
    var map = MindMap()
    let a = try required(map.addChild(to: map.root.id))
    let b = try required(map.addChild(to: a))
    map.connect(map.root.id, b)
    map.topics[1].collapsed = true
    #expect(!map.visibleIDs().contains(b))
    #expect(map.relationships.count == 1)
    map.addChild(to: a)
    #expect(map.visibleIDs().contains(b))
}
@Test func insertionAndDuplicateRelationship() throws {
    var map = MindMap()
    let a = try required(map.addChild(to: map.root.id, title: "첫째"))
    let b = try required(map.addChild(to: map.root.id, title: "셋째"))
    let c = try required(map.addChild(to: map.root.id, title: "둘째", after: a))
    #expect(map.children(map.root.id).map(\.id) == [a, c, b])
    #expect({ map.connect(a, b) == map.connect(b, a) }())
    #expect({ map.connect(a, a) == nil }())
    #expect(map.relationships.count == 1)
}
@Test func corruptDocumentsAreRejected() throws {
    let original = MindMap()
    var invalid = original
    invalid.formatVersion = 2
    #expect(throws: (any Error).self) { try invalid.validate() }
    invalid = original
    invalid.topics.append(invalid.root)
    #expect(throws: (any Error).self) { try invalid.validate() }
    invalid = original
    invalid.topics[0].parentID = UUID()
    #expect(throws: (any Error).self) { try invalid.validate() }
    invalid = original
    invalid.relationships = [Relationship(source: original.root.id, target: UUID())]
    #expect(throws: (any Error).self) { try invalid.validate() }
    #expect(throws: (any Error).self) { try MindMap.decode(Data("not json".utf8)) }
    #expect(try MindMap.decode(original.encoded()) == original)
}
@Test func disconnectedCycleIsRejected() {
    var map = MindMap()
    let a = UUID()
    let b = UUID()
    map.topics += [Topic(id: a, parentID: b, title: "a"), Topic(id: b, parentID: a, title: "b")]
    #expect(throws: (any Error).self) { try map.validate() }
}
@Test func layoutHasNoOverlapsAndHonorsFoldingAndDirection() throws {
    var map = MindMap()
    for index in 0..<12 {
        let id = try required(map.addChild(to: map.root.id, title: "주제 \(index)"))
        for _ in 0..<4 { map.addChild(to: id) }
    }
    var sizes: [UUID: MapRect] = [:]
    for (index, node) in map.topics.enumerated() {
        sizes[node.id] = MapRect(width: Double(100 + index % 3 * 80), height: Double(48 + index % 4 * 35))
    }
    for mode in MapLayout.allCases {
        map.layout = mode
        let frames = TreeLayout.frames(for: map, sizes: sizes)
        #expect(frames.count == map.topics.count)
        let rects = Array(frames.values)
        for i in rects.indices {
            for j in rects.indices where j > i {
                let a = rects[i]
                let b = rects[j]
                #expect(
                    !(a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height
                        && a.y + a.height > b.y))
            }
        }
        if mode == .right { #expect(frames.filter { $0.key != map.root.id }.values.allSatisfy { $0.x > 0 }) }
    }
    map.topics[1].collapsed = true
    let frames = TreeLayout.frames(for: map, sizes: sizes)
    #expect(frames.count == map.visibleIDs().count)
}
@Test func documentDepthLimitProtectsLayout() throws {
    var map = MindMap()
    var last = map.root.id
    for _ in 0..<151 { last = try required(map.addChild(to: last)) }
    #expect(throws: (any Error).self) { try map.validate() }
}

private func required<T>(_ value: T?) throws -> T { try #require(value) }

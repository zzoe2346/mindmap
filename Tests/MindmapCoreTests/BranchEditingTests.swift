import Foundation
import Testing

@testable import MindmapCore

@Test func reorderPreservesBranchAndRelationshipsAcrossSave() throws {
    var map = MindMap()
    let a = try #require({ map.addChild(to: map.root.id, title: "A") }())
    let b = try #require({ map.addChild(to: map.root.id, title: "B") }())
    let c = try #require({ map.addChild(to: map.root.id, title: "C") }())
    let child = try #require({ map.addChild(to: c, title: "C 하위") }())
    map.connect(child, a)
    let relations = map.relationships
    #expect({ map.move([c], to: map.root.id, before: b) }())
    #expect(map.children(map.root.id).map(\.id) == [a, c, b])
    #expect(map.topic(child)?.parentID == c)
    #expect(map.relationships == relations)
    #expect(try MindMap.decode(map.encoded()) == map)
}
@Test func multipleNestedSelectionsMoveOnceAndRejectCycle() throws {
    var map = MindMap()
    let a = try #require({ map.addChild(to: map.root.id) }())
    let b = try #require({ map.addChild(to: a) }())
    let c = try #require({ map.addChild(to: map.root.id) }())
    let target = try #require({ map.addChild(to: map.root.id) }())
    let old = map
    #expect({ !map.move([a, c], to: b) }())
    #expect(map == old)
    #expect({ map.move([a, b, c], to: target, side: -1) }())
    #expect(map.children(target).map(\.id) == [a, c])
    #expect(map.topic(b)?.parentID == a)
    #expect(map.topic(b)?.side == -1)
    try map.validate()
}
@Test func movingToOwnSiblingAnchorIsRejectedAtomically() throws {
    var map = MindMap()
    let a = try #require({ map.addChild(to: map.root.id) }())
    let b = try #require({ map.addChild(to: a) }())
    let old = map
    #expect({ !map.move([a], to: map.root.id, before: a) }())
    #expect({ !map.move([a], to: map.root.id, before: b) }())
    #expect(map == old)
}
@Test func clipboardRemapsIDsAndCopiesOnlyInternalRelationships() throws {
    var map = MindMap()
    let a = try #require({ map.addChild(to: map.root.id, title: "복사") }())
    let b = try #require({ map.addChild(to: a, title: "자식") }())
    map.connect(a, b)
    map.connect(b, map.root.id)
    map.topics[1].textWidth = 420
    let data = try map.branchArchive([a, b])
    let inserted = try map.pasteBranches(data, to: map.root.id)
    #expect(inserted.count == 1)
    #expect(inserted[0] != a)
    #expect(map.topic(inserted[0])?.textWidth == 420)
    #expect(map.children(inserted[0]).count == 1)
    #expect(map.relationships.count == 3)
    #expect(map.relationships.last?.source == inserted[0])
    try map.validate()
}
@Test func invalidClipboardDoesNotMutateDestination() throws {
    var fragment = MindMap()
    let child = try #require({ fragment.addChild(to: fragment.root.id) }())
    fragment.connect(fragment.root.id, child)
    let payload = try fragment.encoded()
    var destination = MindMap()
    let old = destination
    #expect(throws: (any Error).self) { try destination.pasteBranches(payload, to: destination.root.id) }
    #expect(destination == old)
}
@Test func legacyDocumentsWithoutWidthStillLoad() throws {
    let map = MindMap(title: "옛 문서")
    let data = try map.encoded()
    let decoded = try MindMap.decode(data)
    #expect(decoded.root.textWidth == nil)
    var invalid = decoded
    invalid.topics[0].textWidth = -10
    #expect(throws: (any Error).self) { try invalid.validate() }
}

import Foundation

extension MindMap {
    /// Removes nested selections, preserving document order for stable multi-branch moves.
    public func selectionRoots(_ ids: Set<UUID>) -> [UUID] {
        topics.filter { node in
            guard ids.contains(node.id) else { return false }
            var parent = node.parentID
            while let id = parent {
                if ids.contains(id) { return false }
                parent = topic(id)?.parentID
            }
            return true
        }.map(\.id)
    }

    @discardableResult
    public mutating func move(_ ids: Set<UUID>, to parent: UUID, before anchor: UUID? = nil, side: Int? = nil)
        -> Bool
    {
        let roots = selectionRoots(ids)
        guard side.map({ [-1, 1].contains($0) }) ?? true, !roots.isEmpty,
            roots.allSatisfy({ canReparent($0, to: parent) }),
            anchor.map({ topic($0)?.parentID == parent && !roots.contains($0) }) ?? true
        else { return false }
        let old = self
        let rootSet = Set(roots)
        var moved = topics.filter { rootSet.contains($0.id) }
        let direction = side ?? topic(parent)?.side ?? 1
        for index in moved.indices {
            moved[index].parentID = parent
            moved[index].side = direction
        }
        topics.removeAll { rootSet.contains($0.id) }
        let insertion = anchor.flatMap { id in topics.firstIndex { $0.id == id } } ?? topics.endIndex
        topics.insert(contentsOf: moved, at: insertion)
        let movedTree = roots.reduce(into: Set<UUID>()) { $0.formUnion(descendants($1).union([$1])) }
        for index in topics.indices {
            if movedTree.contains(topics[index].id) { topics[index].side = direction }
            if topics[index].id == parent { topics[index].collapsed = false }
        }
        return self != old
    }

    /// A regular validated map with a synthetic root serves as the clipboard envelope.
    public func branchArchive(_ ids: Set<UUID>) throws -> Data {
        let roots = selectionRoots(ids)
        let included = roots.reduce(into: Set<UUID>()) { $0.formUnion(descendants($1).union([$1])) }
        var archive = MindMap(title: "복사한 가지")
        let envelope = archive.root.id
        archive.topics += topics.filter { included.contains($0.id) }.map { item in
            var copy = item
            if roots.contains(item.id) { copy.parentID = envelope }
            return copy
        }
        archive.relationships = relationships.filter {
            included.contains($0.source) && included.contains($0.target)
        }
        return try archive.encoded()
    }

    @discardableResult
    public mutating func pasteBranches(_ data: Data, to parent: UUID, before anchor: UUID? = nil) throws
        -> [UUID]
    {
        guard let destination = topic(parent) else { return [] }
        let archive = try MindMap.decode(data)
        let items = archive.topics.filter { $0.id != archive.root.id }
        let identities = Dictionary(uniqueKeysWithValues: items.map { ($0.id, UUID()) })
        guard
            archive.relationships.allSatisfy({ identities[$0.source] != nil && identities[$0.target] != nil })
        else { throw MapError.invalid("복사한 가지의 연결 정보가 올바르지 않습니다.") }
        let roots = archive.children(archive.root.id).compactMap { identities[$0.id] }
        var copy = self
        let insertion =
            anchor.flatMap { id in copy.topics.firstIndex { $0.id == id && $0.parentID == parent } }
            ?? copy.topics.endIndex
        copy.topics.insert(
            contentsOf: items.map { item in
                var node = item
                node.id = identities[item.id]!
                node.parentID = item.parentID.flatMap { identities[$0] } ?? parent
                node.side = destination.side
                return node
            }, at: insertion)
        copy.relationships += archive.relationships.map { item in
            var edge = item
            edge.id = UUID()
            edge.source = identities[item.source]!
            edge.target = identities[item.target]!
            return edge
        }
        if let index = copy.topics.firstIndex(where: { $0.id == parent }) {
            copy.topics[index].collapsed = false
        }
        try copy.validate()
        self = copy
        return roots
    }
}

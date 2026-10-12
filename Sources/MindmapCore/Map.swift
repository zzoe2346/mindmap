import Foundation

public struct Topic: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var parentID: UUID?
    public var title: String
    public var collapsed: Bool
    public var side: Int
    public init(
        id: UUID = UUID(), parentID: UUID? = nil, title: String, collapsed: Bool = false, side: Int = 1
    ) {
        self.id = id
        self.parentID = parentID
        self.title = title
        self.collapsed = collapsed
        self.side = side
    }
}

public enum Arrow: String, Codable, CaseIterable, Sendable {
    case none, forward, backward, both
    public var title: String {
        switch self {
        case .none: "없음"
        case .forward: "끝에 화살표"
        case .backward: "시작에 화살표"
        case .both: "양쪽 화살표"
        }
    }
}
public enum MapLayout: String, Codable, CaseIterable, Sendable {
    case right, balanced
    public var title: String { self == .right ? "오른쪽으로" : "양쪽으로" }
}
public struct Relationship: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var source: UUID
    public var target: UUID
    public var label: String
    public var arrow: Arrow
    public var bend: Double
    public init(
        id: UUID = UUID(), source: UUID, target: UUID, label: String = "", arrow: Arrow = .forward,
        bend: Double = 70
    ) {
        self.id = id
        self.source = source
        self.target = target
        self.label = label
        self.arrow = arrow
        self.bend = bend
    }
}
public enum MapError: Error, LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self {
        case .invalid(let reason): "문서를 열 수 없습니다. \(reason) 원본 파일은 변경하지 않았습니다."
        }
    }
}
public struct MindMap: Codable, Equatable, Sendable {
    public var formatVersion: Int = 1
    public var topics: [Topic]
    public var relationships: [Relationship] = []
    public var layout: MapLayout = .right
    public init(title: String = "중심 주제") { topics = [Topic(title: title)] }
    public var root: Topic { topics.first(where: { $0.parentID == nil }) ?? topics[0] }
    public func topic(_ id: UUID) -> Topic? { topics.first { $0.id == id } }
    public func children(_ id: UUID) -> [Topic] { topics.filter { $0.parentID == id } }
    public func descendants(_ id: UUID) -> Set<UUID> {
        var result = Set<UUID>()
        var queue = [id]
        while let next = queue.popLast() {
            for child in children(next) where result.insert(child.id).inserted { queue.append(child.id) }
        }
        return result
    }
    public func visibleIDs() -> Set<UUID> {
        var visible = Set<UUID>()
        var queue = [root.id]
        while let id = queue.popLast() {
            guard visible.insert(id).inserted, let item = topic(id), !item.collapsed else { continue }
            queue.append(contentsOf: children(id).map(\.id))
        }
        return visible
    }
    public mutating func addChild(to parent: UUID, title: String = "새 토픽", after sibling: UUID? = nil)
        -> UUID?
    {
        guard let parentTopic = topic(parent) else { return nil }
        let side = parent == root.id ? (children(parent).count.isMultiple(of: 2) ? 1 : -1) : parentTopic.side
        let item = Topic(parentID: parent, title: title, side: side)
        if let sibling, let index = topics.firstIndex(where: { $0.id == sibling }) {
            topics.insert(item, at: index + 1)
        } else {
            topics.append(item)
        }
        if let index = topics.firstIndex(where: { $0.id == parent }) { topics[index].collapsed = false }
        return item.id
    }
    public mutating func remove(_ id: UUID) {
        guard id != root.id else { return }
        let removed = descendants(id).union([id])
        topics.removeAll { removed.contains($0.id) }
        relationships.removeAll { removed.contains($0.source) || removed.contains($0.target) }
    }
    public func canReparent(_ id: UUID, to parent: UUID) -> Bool {
        id != root.id && id != parent && topic(id) != nil && topic(parent) != nil
            && !descendants(id).contains(parent)
    }
    @discardableResult public mutating func reparent(_ id: UUID, to parent: UUID) -> Bool {
        guard canReparent(id, to: parent), let index = topics.firstIndex(where: { $0.id == id }),
            topics[index].parentID != parent
        else { return false }
        topics[index].parentID = parent
        if let p = topics.firstIndex(where: { $0.id == parent }) { topics[p].collapsed = false }
        return true
    }
    @discardableResult public mutating func connect(_ source: UUID, _ target: UUID) -> UUID? {
        guard source != target, topic(source) != nil, topic(target) != nil else { return nil }
        if let existing = relationships.first(where: {
            ($0.source == source && $0.target == target) || ($0.source == target && $0.target == source)
        }) {
            return existing.id
        }
        let relation = Relationship(source: source, target: target)
        relationships.append(relation)
        return relation.id
    }
    public func validate() throws {
        guard formatVersion == 1 else { throw MapError.invalid("지원하지 않는 문서 버전입니다.") }
        guard !topics.isEmpty, topics.count <= 10000, topics.filter({ $0.parentID == nil }).count == 1 else {
            throw MapError.invalid("중심 토픽 구성이 올바르지 않습니다.")
        }
        let ids = Set(topics.map(\.id))
        guard ids.count == topics.count else { throw MapError.invalid("중복된 토픽이 있습니다.") }
        for topic in topics {
            guard topic.title.count <= 100000, [-1, 1].contains(topic.side) else {
                throw MapError.invalid("토픽 값이 올바르지 않습니다.")
            }
            if let parent = topic.parentID, !ids.contains(parent) { throw MapError.invalid("상위 토픽이 없습니다.") }
        }
        // Reachability from the only root also rejects detached cycles in a single-parent tree.
        guard descendants(root.id).count == topics.count - 1 else {
            throw MapError.invalid("토픽 연결에 순환 또는 끊어진 가지가 있습니다.")
        }
        guard Set(relationships.map(\.id)).count == relationships.count else {
            throw MapError.invalid("중복된 관계선이 있습니다.")
        }
        for edge in relationships {
            guard ids.contains(edge.source), ids.contains(edge.target), edge.source != edge.target,
                edge.bend.isFinite, abs(edge.bend) <= 500, edge.label.count <= 10000
            else { throw MapError.invalid("관계선 값이 올바르지 않습니다.") }
        }
        // Bound recursive UI layout depth for externally supplied documents.
        var queue: [(UUID, Int)] = [(root.id, 0)]
        while let (id, depth) = queue.popLast() {
            guard depth <= 150 else { throw MapError.invalid("가지 깊이는 150단계까지 지원합니다.") }
            queue.append(contentsOf: children(id).map { ($0.id, depth + 1) })
        }
    }
    public static func decode(_ data: Data) throws -> MindMap {
        guard data.count <= 50_000_000 else { throw MapError.invalid("문서가 50MB를 초과합니다.") }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        return value
    }
    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

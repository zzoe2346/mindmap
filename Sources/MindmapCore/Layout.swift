import Foundation

public struct MapRect: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public init(x: Double = 0, y: Double = 0, width: Double = 140, height: Double = 48) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
public enum TreeLayout {
    public static func frames(for map: MindMap, sizes: [UUID: MapRect]) -> [UUID: MapRect] {
        let adjacency = Dictionary(grouping: map.topics.filter { $0.parentID != nil }, by: { $0.parentID })
        func children(_ id: UUID) -> [Topic] { adjacency[id] ?? [] }
        var heights: [UUID: Double] = [:]
        func measure(_ topic: Topic) -> Double {
            let own = sizes[topic.id]?.height ?? 48
            let kids = topic.collapsed ? [] : children(topic.id)
            let total = kids.map(measure).reduce(0, +) + Double(max(0, kids.count - 1)) * 22
            let height = max(own, total)
            heights[topic.id] = height
            return height
        }
        _ = measure(map.root)
        var frames: [UUID: MapRect] = [:]
        let rootSize = sizes[map.root.id] ?? MapRect()
        frames[map.root.id] = MapRect(
            x: -rootSize.width / 2, y: -rootSize.height / 2, width: rootSize.width, height: rootSize.height)
        func place(_ topic: Topic, edgeX: Double, centerY: Double, side: Int) {
            let size = sizes[topic.id] ?? MapRect()
            let x = side == 1 ? edgeX + 64 : edgeX - 64 - size.width
            frames[topic.id] = MapRect(
                x: x, y: centerY - size.height / 2, width: size.width, height: size.height)
            guard !topic.collapsed else { return }
            let kids = children(topic.id)
            let total = kids.map { heights[$0.id] ?? 48 }.reduce(0, +) + Double(max(0, kids.count - 1)) * 22
            var cursor = centerY - total / 2
            for child in kids {
                let h = heights[child.id] ?? 48
                place(child, edgeX: side == 1 ? x + size.width : x, centerY: cursor + h / 2, side: side)
                cursor += h + 22
            }
        }
        guard !map.root.collapsed else { return frames }
        for side in [-1, 1] {
            let kids = children(map.root.id).filter { map.layout == .right ? side == 1 : $0.side == side }
            let total = kids.map { heights[$0.id] ?? 48 }.reduce(0, +) + Double(max(0, kids.count - 1)) * 30
            var cursor = -total / 2
            for child in kids {
                let h = heights[child.id] ?? 48
                place(child, edgeX: Double(side) * rootSize.width / 2, centerY: cursor + h / 2, side: side)
                cursor += h + 30
            }
        }
        return frames
    }
}

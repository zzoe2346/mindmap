import AppKit
import MindmapCore

extension EditorSession {
    var selection: Set<UUID> {
        selectedTopics.isEmpty ? Set([selectedTopic].compactMap { $0 }) : selectedTopics
    }
    func toggleSelection(_ id: UUID) {
        var value = selection
        if value.contains(id) { value.remove(id) } else { value.insert(id) }
        selectedTopics = value
        selectedTopic = value.contains(id) ? id : map.topics.first(where: { value.contains($0.id) })?.id
        selectedRelation = nil
    }
    func moveSelection(direction: Int) {
        canvas?.finishEditing()
        let roots = map.selectionRoots(selection)
        guard let first = roots.first, let parent = map.topic(first)?.parentID,
            roots.allSatisfy({ map.topic($0)?.parentID == parent })
        else { return }
        let siblings = map.children(parent).map(\.id)
        let positions = siblings.indices.filter { roots.contains(siblings[$0]) }
        guard let low = positions.min(), let high = positions.max() else { return }
        let anchor: UUID?
        if direction < 0 {
            guard low > 0 else { return }
            anchor = siblings[low - 1]
        } else {
            guard high + 1 < siblings.count else { return }
            anchor = high + 2 < siblings.count ? siblings[high + 2] : nil
        }
        let ids = selection
        change("토픽 순서 변경") { $0.move(ids, to: parent, before: anchor, side: $0.topic(first)?.side) }
        canvas?.rebuild()
        canvas?.reveal(first)
    }
    func outdent() {
        canvas?.finishEditing()
        guard let id = selectedTopic, let parent = map.topic(id)?.parentID,
            let grandparent = map.topic(parent)?.parentID
        else { return }
        let siblings = map.children(grandparent).map(\.id)
        let index = siblings.firstIndex(of: parent)!
        let anchor = index + 1 < siblings.count ? siblings[index + 1] : nil
        let ids = selection
        change("한 단계 밖으로 이동") { $0.move(ids, to: grandparent, before: anchor, side: $0.topic(parent)?.side) }
    }
}

extension MapCanvas {
    static var branchPasteboardType: NSPasteboard.PasteboardType {
        .init("com.jeongseonghun.mindmap.branches")
    }
    @objc func copy(_ sender: Any?) {
        finishEditing()
        do {
            let data = try session.map.branchArchive(session.selection)
            let board = NSPasteboard.general
            board.clearContents()
            board.setData(data, forType: Self.branchPasteboardType)
            board.setString(
                session.map.selectionRoots(session.selection).compactMap { session.map.topic($0)?.title }
                    .joined(separator: "\n"), forType: .string)
        } catch { session.document?.presentError(error) }
    }
    @objc func cut(_ sender: Any?) {
        guard !session.selection.contains(session.map.root.id) else { return }
        copy(sender)
        session.deleteSelection()
    }
    @objc func paste(_ sender: Any?) {
        finishEditing()
        guard let parent = session.selectedTopic else { return }
        if let data = NSPasteboard.general.data(forType: Self.branchPasteboardType) {
            insertArchive(data, parent: parent)
        } else if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
            beginEditing()
            replaceEditorText(text)
        }
    }
    override func selectAll(_ sender: Any?) {
        session.selectedTopics = session.map.visibleIDs().subtracting([session.map.root.id])
        session.selectedTopic = session.map.topics.first { session.selectedTopics.contains($0.id) }?.id
        session.selectedRelation = nil
    }
    @objc func duplicateBranches(_ sender: Any?) {
        finishEditing()
        guard let id = session.map.selectionRoots(session.selection).last,
            let parent = session.map.topic(id)?.parentID
        else { return }
        do {
            let data = try session.map.branchArchive(session.selection)
            let siblings = session.map.children(parent).map(\.id)
            let index = siblings.firstIndex(of: id)!
            insertArchive(
                data, parent: parent, before: index + 1 < siblings.count ? siblings[index + 1] : nil)
        } catch { session.document?.presentError(error) }
    }
    private func insertArchive(_ data: Data, parent: UUID, before anchor: UUID? = nil) {
        do {
            var map = session.map
            let ids = try map.pasteBranches(data, to: parent, before: anchor)
            session.change("가지 붙여넣기") { $0 = map }
            session.selectedTopics = Set(ids)
            session.selectedTopic = ids.first
            rebuild()
            if let id = ids.first { reveal(id) }
        } catch { session.document?.presentError(error) }
    }
}

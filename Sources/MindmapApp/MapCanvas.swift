import AppKit
import Combine
import MindmapCore

@MainActor final class TopicTextView: NSTextView {
    private let textUndoManager = UndoManager()
    override var undoManager: UndoManager? { textUndoManager }
    var commit: (() -> Void)?
    var cancel: (() -> Void)?
    var addChild: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        // Let the input method finish composition before interpreting editor commands.
        if !hasMarkedText() {
            if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
                commit?()
                return
            }
            if event.keyCode == 53 {
                cancel?()
                return
            }
            if event.keyCode == 48 {
                commit?()
                addChild?()
                return
            }
        }
        super.keyDown(with: event)
    }
}
// The Objective-C accessibility callback forwards only an immutable Sendable action.
final class TopicAccessibilityElement: NSAccessibilityElement {
    let onPress: @MainActor @Sendable () -> Void
    init(onPress: @escaping @MainActor @Sendable () -> Void) {
        self.onPress = onPress
        super.init()
    }
    override func accessibilityPerformPress() -> Bool {
        let action = onPress
        Task { @MainActor in action() }
        return true
    }
}
@MainActor final class MapCanvas: NSView, NSTextViewDelegate {
    let session: EditorSession
    var frames: [UUID: CGRect] = [:]
    private var pan = CGPoint.zero
    private var subscriptions = Set<AnyCancellable>()
    private var mouseStart = CGPoint.zero
    private var originalPan = CGPoint.zero
    private var draggingTopic: UUID?
    private var dropTarget: UUID?
    private var dragged = false
    private var bending = false
    private var bendPreview: Double?
    private var editor: TopicTextView?
    private var editingID: UUID?
    private var relationSamples: [UUID: [CGPoint]] = [:]
    private var relationLabels: [UUID: CGRect] = [:]
    private var foldButtons: [UUID: CGRect] = [:]
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    init(session: EditorSession) {
        self.session = session
        super.init(frame: .zero)
        session.canvas = self
        setAccessibilityRole(.group)
        setAccessibilityLabel("마인드맵 캔버스")
        session.$map.sink { [weak self] _ in DispatchQueue.main.async { self?.rebuild() } }.store(
            in: &subscriptions)
        session.objectWillChange.sink { [weak self] in DispatchQueue.main.async { self?.needsDisplay = true }
        }.store(in: &subscriptions)
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func world(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - bounds.midX - pan.x) / session.zoom, y: (p.y - bounds.midY - pan.y) / session.zoom)
    }
    func screen(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * session.zoom + bounds.midX + pan.x, y: p.y * session.zoom + bounds.midY + pan.y)
    }
    private func screenRect(_ r: CGRect) -> CGRect {
        CGRect(
            origin: screen(r.origin),
            size: CGSize(width: r.width * session.zoom, height: r.height * session.zoom))
    }
    func rebuild() {
        var sizes: [UUID: MapRect] = [:]
        for topic in session.map.topics {
            let font = nodeFont(topic)
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            let measured = (topic.title as NSString).boundingRect(
                with: NSSize(width: 300, height: 100000),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font, .paragraphStyle: style])
            sizes[topic.id] = MapRect(
                width: max(topic.parentID == nil ? 160 : 100, ceil(measured.width) + 36),
                height: max(48, ceil(measured.height) + 26))
        }
        frames = TreeLayout.frames(for: session.map, sizes: sizes).mapValues {
            CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
        }
        needsDisplay = true
        updateAccessibility()
    }
    private func nodeFont(_ topic: Topic) -> NSFont {
        .systemFont(
            ofSize: session.fontSize + (topic.parentID == nil ? 3 : 0),
            weight: topic.parentID == nil ? .semibold : .regular)
    }
    private func color(_ id: UUID) -> NSColor {
        var node = session.map.topic(id)
        while let parent = node?.parentID, parent != session.map.root.id { node = session.map.topic(parent) }
        let index = session.map.children(session.map.root.id).firstIndex(where: { $0.id == node?.id }) ?? 0
        return [NSColor.systemIndigo, .systemTeal, .systemOrange, .systemPurple, .systemBlue, .systemPink][
            index % 6]
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: bounds.midX + pan.x, y: bounds.midY + pan.y)
        context.scaleBy(x: session.zoom, y: session.zoom)
        drawBranches()
        relationSamples.removeAll()
        relationLabels.removeAll()
        foldButtons.removeAll()
        for edge in session.map.relationships { drawRelation(edge) }
        for topic in session.map.topics {
            guard let r = frames[topic.id] else { continue }
            let tint = color(topic.id)
            let root = topic.parentID == nil
            let selected = session.selectedTopic == topic.id
            let path = NSBezierPath(roundedRect: r, xRadius: root ? 14 : 9, yRadius: root ? 14 : 9)
            (root ? NSColor.labelColor : tint.withAlphaComponent(0.08)).setFill()
            path.fill()
            if selected || dropTarget == topic.id || session.connectingFrom == topic.id {
                (dropTarget == topic.id ? NSColor.systemGreen : NSColor.controlAccentColor).setStroke()
                path.lineWidth = 2.5
                path.stroke()
            } else if !root {
                tint.withAlphaComponent(0.25).setStroke()
                path.lineWidth = 1
                path.stroke()
            }
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key: Any] = [
                .font: nodeFont(topic),
                .foregroundColor: root ? NSColor.textBackgroundColor : NSColor.labelColor,
                .paragraphStyle: style,
            ]
            (topic.title as NSString).draw(in: r.insetBy(dx: 18, dy: 13), withAttributes: attributes)
            if !session.map.children(topic.id).isEmpty {
                let left = r.midX < 0 && topic.parentID != nil
                let button = CGRect(x: left ? r.minX - 22 : r.maxX + 5, y: r.midY - 9, width: 18, height: 18)
                foldButtons[topic.id] = button
                NSColor.textBackgroundColor.setFill()
                NSBezierPath(ovalIn: button).fill()
                tint.withAlphaComponent(0.65).setStroke()
                NSBezierPath(ovalIn: button).stroke()
                let label = topic.collapsed ? "+" : "−"
                (label as NSString).draw(
                    in: button.offsetBy(dx: 4, dy: 0),
                    withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: tint])
            }
        }
        context.restoreGState()
        if session.map.topics.count == 1 {
            let text = "생각 하나에서 시작하세요\n토픽을 더블 클릭해 이름을 바꾸고 Tab으로 가지를 펼쳐보세요."
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            (text as NSString).draw(
                in: CGRect(x: 30, y: bounds.height - 100, width: bounds.width - 60, height: 64),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: style,
                ])
        }
    }
    private func drawBranches() {
        for topic in session.map.topics {
            guard let parent = topic.parentID, let a = frames[parent], let b = frames[topic.id] else {
                continue
            }
            let right = b.midX > a.midX
            let start = CGPoint(x: right ? a.maxX : a.minX, y: a.midY)
            let end = CGPoint(x: right ? b.minX : b.maxX, y: b.midY)
            let path = NSBezierPath()
            path.move(to: start)
            let mid = (start.x + end.x) / 2
            path.curve(
                to: end, controlPoint1: CGPoint(x: mid, y: start.y), controlPoint2: CGPoint(x: mid, y: end.y))
            color(topic.id).withAlphaComponent(0.65).setStroke()
            path.lineWidth = 2
            path.stroke()
        }
    }
    private func boundary(_ rect: CGRect, toward p: CGPoint) -> CGPoint {
        let dx = p.x - rect.midX
        let dy = p.y - rect.midY
        let scale = min(rect.width / 2 / max(abs(dx), 0.001), rect.height / 2 / max(abs(dy), 0.001))
        return CGPoint(x: rect.midX + dx * scale, y: rect.midY + dy * scale)
    }
    private func geometry(_ edge: Relationship, bend: Double) -> (CGPoint, CGPoint, CGPoint)? {
        guard let a = frames[edge.source], let b = frames[edge.target] else { return nil }
        let dx = b.midX - a.midX
        let dy = b.midY - a.midY
        let length = max(hypot(dx, dy), 1)
        let control = CGPoint(
            x: (a.midX + b.midX) / 2 - dy / length * bend * 2,
            y: (a.midY + b.midY) / 2 + dx / length * bend * 2)
        return (boundary(a, toward: control), control, boundary(b, toward: control))
    }
    private func quadratic(_ a: CGPoint, _ c: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(
            x: (1 - t) * (1 - t) * a.x + 2 * (1 - t) * t * c.x + t * t * b.x,
            y: (1 - t) * (1 - t) * a.y + 2 * (1 - t) * t * c.y + t * t * b.y)
    }
    private func drawRelation(_ edge: Relationship) {
        let selected = edge.id == session.selectedRelation
        guard let (a, c, b) = geometry(edge, bend: selected ? (bendPreview ?? edge.bend) : edge.bend) else {
            return
        }
        let samples = (0...80).map { quadratic(a, c, b, Double($0) / 80) }
        relationSamples[edge.id] = samples
        let path = NSBezierPath()
        path.move(to: a)
        path.curve(
            to: b, controlPoint1: CGPoint(x: a.x + (c.x - a.x) * 2 / 3, y: a.y + (c.y - a.y) * 2 / 3),
            controlPoint2: CGPoint(x: b.x + (c.x - b.x) * 2 / 3, y: b.y + (c.y - b.y) * 2 / 3))
        let tint = selected ? NSColor.controlAccentColor : NSColor.systemOrange
        tint.setStroke()
        path.lineWidth = selected ? 2.5 : 1.8
        let dash: [CGFloat] = [6, 4]
        path.setLineDash(dash, count: 2, phase: 0)
        path.stroke()
        if edge.arrow == .forward || edge.arrow == .both { arrow(at: b, from: c, color: tint) }
        if edge.arrow == .backward || edge.arrow == .both { arrow(at: a, from: c, color: tint) }
        let middle = samples[40]
        if !edge.label.isEmpty {
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineBreakMode = .byWordWrapping
            let attr: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: session.fontSize - 2), .foregroundColor: tint,
                .paragraphStyle: style,
            ]
            let size = (edge.label as NSString).boundingRect(
                with: NSSize(width: 230, height: 10000), options: [.usesLineFragmentOrigin], attributes: attr
            ).size
            let r = CGRect(
                x: middle.x - size.width / 2 - 8, y: middle.y - size.height / 2 - 5, width: size.width + 16,
                height: size.height + 10)
            relationLabels[edge.id] = r
            NSColor.textBackgroundColor.setFill()
            NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6).fill()
            (edge.label as NSString).draw(in: r.insetBy(dx: 8, dy: 5), withAttributes: attr)
        }
        if selected {
            let handle = CGRect(x: middle.x - 6, y: middle.y - 6, width: 12, height: 12)
            tint.setFill()
            NSBezierPath(ovalIn: handle).fill()
        }
    }
    private func arrow(at point: CGPoint, from: CGPoint, color: NSColor) {
        let angle = atan2(point.y - from.y, point.x - from.x)
        let length = 11.0
        let path = NSBezierPath()
        path.move(to: point)
        path.line(
            to: CGPoint(x: point.x - length * cos(angle - 0.45), y: point.y - length * sin(angle - 0.45)))
        path.move(to: point)
        path.line(
            to: CGPoint(x: point.x - length * cos(angle + 0.45), y: point.y - length * sin(angle + 0.45)))
        color.setStroke()
        path.lineWidth = 2
        path.stroke()
    }
    private func topicAt(_ point: CGPoint) -> UUID? {
        session.map.topics.reversed().first { frames[$0.id]?.contains(point) == true }?.id
    }
    override func mouseDown(with event: NSEvent) {
        finishEditing()
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        let w = world(p)
        mouseStart = p
        originalPan = pan
        dragged = false
        draggingTopic = nil
        dropTarget = nil
        bending = false
        if let id = session.selectedRelation, let samples = relationSamples[id],
            hypot(samples[40].x - w.x, samples[40].y - w.y) < 12 / session.zoom
        {
            bending = true
            return
        }
        if let (id, _) = foldButtons.first(where: { $0.value.contains(w) }) {
            session.selectTopic(id)
            session.toggleFold()
            return
        }
        if let id = topicAt(w) {
            if session.connectingFrom != nil {
                session.connect(to: id)
                return
            }
            session.selectTopic(id)
            draggingTopic = id
            if event.clickCount == 2 {
                draggingTopic = nil
                beginEditing()
            }
            return
        }
        for edge in session.map.relationships.reversed() {
            if relationLabels[edge.id]?.contains(w) == true
                || relationSamples[edge.id]?.contains(where: {
                    hypot($0.x - w.x, $0.y - w.y) < 8 / session.zoom
                }) == true
            {
                session.selectRelation(edge.id)
                return
            }
        }
        session.cancelConnecting()
        session.selectedRelation = nil
    }
    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard hypot(p.x - mouseStart.x, p.y - mouseStart.y) > 4 else { return }
        dragged = true
        if bending, let id = session.selectedRelation,
            let edge = session.map.relationships.first(where: { $0.id == id }), let a = frames[edge.source],
            let b = frames[edge.target]
        {
            let w = world(p)
            let dx = b.midX - a.midX
            let dy = b.midY - a.midY
            let length = max(hypot(dx, dy), 1)
            bendPreview = min(
                500,
                max(
                    -500,
                    ((w.x - (a.midX + b.midX) / 2) * (-dy) + (w.y - (a.midY + b.midY) / 2) * dx) / length))
        } else if let id = draggingTopic {
            dropTarget = topicAt(world(p)).flatMap { session.map.canReparent(id, to: $0) ? $0 : nil }
            session.message = dropTarget == nil ? "다른 토픽 위에 놓으면 그 아래로 이동합니다." : "놓으면 초록색 토픽의 하위로 이동합니다."
        } else {
            pan = CGPoint(x: originalPan.x + p.x - mouseStart.x, y: originalPan.y + p.y - mouseStart.y)
        }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if bending, let bendPreview {
            session.updateRelation("관계선 곡률 변경") { $0.bend = bendPreview }
        } else if dragged, let id = draggingTopic, let target = dropTarget {
            session.change("토픽 이동") { $0.reparent(id, to: target) }
        }
        draggingTopic = nil
        dropTarget = nil
        bending = false
        bendPreview = nil
        dragged = false
        if session.connectingFrom == nil { session.cancelConnecting() }
        needsDisplay = true
        updateAccessibility()
    }
    override func scrollWheel(with event: NSEvent) {
        finishEditing()
        if event.modifierFlags.contains(.command) {
            setZoom(session.zoom * exp(-event.scrollingDeltaY / 150))
        } else {
            let factor = event.hasPreciseScrollingDeltas ? 1.0 : 12.0
            pan.x += event.scrollingDeltaX * factor
            pan.y += event.scrollingDeltaY * factor
            needsDisplay = true
        }
    }
    override func magnify(with event: NSEvent) { setZoom(session.zoom * (1 + event.magnification)) }
    func setZoom(_ scale: Double) {
        finishEditing()
        session.zoom = min(3, max(0.15, scale))
        needsDisplay = true
        updateAccessibility()
    }
    func fitAll() {
        finishEditing()
        rebuild()
        guard var all = frames.values.first else { return }
        for frame in frames.values { all = all.union(frame) }
        // Include curved relationship extents, even if they sit outside the topic bounds.
        for edge in session.map.relationships {
            if let (a, c, b) = geometry(edge, bend: edge.bend) {
                for index in 0...20 {
                    let p = quadratic(a, c, b, Double(index) / 20)
                    all = all.union(CGRect(x: p.x - 20, y: p.y - 20, width: 40, height: 40))
                }
            }
        }
        session.zoom = min(
            1.3,
            max(
                0.15,
                min((bounds.width - 100) / max(all.width, 1), (bounds.height - 100) / max(all.height, 1))))
        pan = CGPoint(x: -all.midX * session.zoom, y: -all.midY * session.zoom)
        needsDisplay = true
        updateAccessibility()
    }
    func reveal(_ id: UUID) {
        guard let frame = frames[id] else { return }
        let r = screenRect(frame)
        if !bounds.insetBy(dx: 40, dy: 40).contains(r) {
            pan = CGPoint(x: -frame.midX * session.zoom, y: -frame.midY * session.zoom)
        }
        needsDisplay = true
    }
    func beginEditing() {
        finishEditing()
        guard let id = session.selectedTopic, let topic = session.map.topic(id), let rect = frames[id] else {
            return
        }
        reveal(id)
        let r = screenRect(rect).insetBy(dx: 5, dy: 5)
        let field = TopicTextView(frame: r)
        field.string = topic.title
        field.font = .systemFont(ofSize: session.fontSize * session.zoom)
        field.textColor = .labelColor
        field.backgroundColor = .textBackgroundColor
        field.isRichText = false
        field.allowsUndo = true
        field.isAutomaticQuoteSubstitutionEnabled = false
        field.isVerticallyResizable = true
        field.isHorizontallyResizable = false
        field.textContainerInset = NSSize(width: 8, height: 6)
        field.textContainer?.widthTracksTextView = true
        field.delegate = self
        field.setAccessibilityLabel("토픽 제목 편집")
        field.wantsLayer = true
        field.layer?.cornerRadius = 5
        field.layer?.borderWidth = 1
        field.layer?.borderColor = NSColor.controlAccentColor.cgColor
        field.commit = { [weak self] in self?.finishEditing() }
        field.cancel = { [weak self] in self?.finishEditing(commit: false) }
        field.addChild = { [weak self] in self?.session.add(child: true) }
        editingID = id
        editor = field
        addSubview(field)
        setAccessibilityChildren([field])
        window?.makeFirstResponder(field)
        field.selectAll(nil)
    }
    func textDidChange(_ notification: Notification) {
        guard let editor, let container = editor.textContainer, let manager = editor.layoutManager else {
            return
        }
        manager.ensureLayout(for: container)
        editor.setFrameSize(
            NSSize(width: editor.frame.width, height: max(40, manager.usedRect(for: container).height + 16)))
    }
    func textDidEndEditing(_ notification: Notification) { finishEditing() }
    func finishEditing(commit: Bool = true) {
        guard let field = editor, let id = editingID else { return }
        editor = nil
        editingID = nil
        let title = field.string.trimmingCharacters(in: .whitespacesAndNewlines)
        field.delegate = nil
        field.removeFromSuperview()
        updateAccessibility()
        if commit && !title.isEmpty {
            session.change("제목 편집") { map in
                if let index = map.topics.firstIndex(where: { $0.id == id }) {
                    map.topics[index].title = title
                }
            }
        }
        window?.makeFirstResponder(self)
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 48: session.add(child: true)
        case 36: session.add(child: false)
        case 51, 117: session.deleteSelection()
        case 53: session.cancelConnecting()
        case 49: beginEditing()
        case 123, 124, 125, 126: navigate(event.keyCode)
        default: super.keyDown(with: event)
        }
    }
    private func navigate(_ code: UInt16) {
        guard let id = session.selectedTopic, let current = frames[id] else { return }
        let candidates = frames.filter { other, rect in
            guard other != id else { return false }
            switch code {
            case 123: return rect.midX < current.midX - 10
            case 124: return rect.midX > current.midX + 10
            case 125: return rect.midY > current.midY + 10
            default: return rect.midY < current.midY - 10
            }
        }
        let winner = candidates.min { a, b in
            func score(_ r: CGRect) -> Double {
                let dx = abs(r.midX - current.midX)
                let dy = abs(r.midY - current.midY)
                return code == 123 || code == 124 ? dx + dy * 3 : dy + dx * 3
            }
            return score(a.value) < score(b.value)
        }
        if let id = winner?.key {
            session.selectTopic(id)
            reveal(id)
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        finishEditing()
        if let id = topicAt(world(convert(event.locationInWindow, from: nil))) { session.selectTopic(id) }
        let menu = NSMenu()
        for (title, action) in [
            ("하위 토픽 추가", #selector(EditorController.addChildTopic(_:))),
            ("형제 토픽 추가", #selector(EditorController.addSibling(_:))),
            ("제목 편집", #selector(EditorController.editTopic(_:))),
            ("관계선 연결", #selector(EditorController.connect(_:))),
            ("가지 접기/펼치기", #selector(EditorController.fold(_:))),
            ("선택 항목 삭제", #selector(EditorController.deleteItem(_:))),
        ] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        }
        return menu
    }
    private func updateAccessibility() {
        let elements = session.map.topics.compactMap { topic -> TopicAccessibilityElement? in
            guard let rect = frames[topic.id] else { return nil }
            let element = TopicAccessibilityElement { [weak self] in
                if self?.session.connectingFrom != nil {
                    self?.session.connect(to: topic.id)
                } else {
                    self?.session.selectTopic(topic.id)
                }
                self?.reveal(topic.id)
                self?.window?.makeFirstResponder(self)
            }
            element.setAccessibilityRole(.button)
            element.setAccessibilityEnabled(true)
            element.setAccessibilityLabel(topic.title)
            element.setAccessibilityHelp("선택 후 Tab으로 하위 토픽을 추가합니다.")
            element.setAccessibilityParent(self)
            if let window {
                element.setAccessibilityFrame(window.convertToScreen(convert(screenRect(rect), to: nil)))
            }
            return element
        }
        setAccessibilityChildren(elements)
    }
}

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
    var pan = CGPoint.zero
    private var restoredViewport = false
    private var subscriptions = Set<AnyCancellable>()
    private var mouseStart = CGPoint.zero
    private var originalPan = CGPoint.zero
    private var draggingTopic: UUID?
    private var dropTarget: UUID?
    private var dropPlacement: DropPlacement?
    private var dragPoint = CGPoint.zero
    private var editingChanged = false
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
        let displayMap = mapForSaving
        let oldFrame = editingID.flatMap { frames[$0] }
        for topic in displayMap.topics {
            let font = nodeFont(topic)
            let style = NSMutableParagraphStyle()
            style.lineBreakMode = .byWordWrapping
            let measured = (topic.title as NSString).boundingRect(
                with: NSSize(width: topic.textWidth ?? 300, height: 100000),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font, .paragraphStyle: style])
            sizes[topic.id] = MapRect(
                width: topic.textWidth.map { $0 + 36 }
                    ?? max(topic.parentID == nil ? 160 : 100, ceil(measured.width) + 36),
                height: max(48, ceil(measured.height) + 26))
        }
        frames = TreeLayout.frames(for: displayMap, sizes: sizes).mapValues {
            CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height)
        }
        if let id = editingID, let frame = frames[id], let oldFrame {
            pan.x += (oldFrame.minX - frame.minX) * session.zoom
            pan.y += (oldFrame.minY - frame.minY) * session.zoom
            editor?.frame = screenRect(frame)
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
            let selected = session.selection.contains(topic.id)
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
            if topic.id != editingID {
                (topic.title as NSString).draw(in: r.insetBy(dx: 18, dy: 13), withAttributes: attributes)
            }
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
        drawDragPreview()
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
    struct DropPlacement {
        var parent: UUID
        var before: UUID?
        var side: Int
        var lineY: CGFloat?
        var lineFrame: CGRect?
    }
    func dropPlacement(at p: CGPoint) -> DropPlacement? {
        let roots = session.map.selectionRoots(session.selection)
        guard !roots.isEmpty, !roots.contains(session.map.root.id) else { return nil }
        let excluded = roots.reduce(into: Set<UUID>()) {
            $0.formUnion(session.map.descendants($1).union([$1]))
        }
        let candidates = frames.filter {
            !excluded.contains($0.key) && $0.value.insetBy(dx: -28, dy: -20).contains(p)
        }
        guard let (id, rect) = candidates.min(by: { abs($0.value.midY - p.y) < abs($1.value.midY - p.y) }),
            let topic = session.map.topic(id)
        else { return nil }
        if let parent = topic.parentID,
            p.y < rect.minY + min(12, rect.height * 0.25) || p.y > rect.maxY - min(12, rect.height * 0.25)
        {
            let before = p.y < rect.midY
            let siblings = session.map.children(parent).filter { !roots.contains($0.id) }
            guard let index = siblings.firstIndex(where: { $0.id == id }),
                roots.allSatisfy({ session.map.canReparent($0, to: parent) })
            else { return nil }
            return DropPlacement(
                parent: parent,
                before: before ? id : (index + 1 < siblings.count ? siblings[index + 1].id : nil),
                side: topic.side, lineY: before ? rect.minY - 9 : rect.maxY + 9, lineFrame: rect)
        }
        guard rect.contains(p), roots.allSatisfy({ session.map.canReparent($0, to: id) }) else { return nil }
        let side =
            id == session.map.root.id && session.map.layout == .balanced
            ? (p.x < rect.midX ? -1 : 1) : topic.side
        return DropPlacement(parent: id, side: side)
    }
    private func drawDragPreview() {
        guard dragged, let id = draggingTopic, let topic = session.map.topic(id) else { return }
        if let placement = dropPlacement, let y = placement.lineY, let r = placement.lineFrame {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: r.minX - 8, y: y))
            path.line(to: CGPoint(x: r.maxX + 8, y: y))
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 3 / session.zoom
            path.stroke()
        }
        let ghost = CGRect(x: dragPoint.x + 16, y: dragPoint.y + 16, width: 190, height: 44)
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: ghost, xRadius: 8, yRadius: 8).fill()
        let label = session.selection.count > 1 ? "\(session.selection.count)개 토픽 이동" : topic.title
        (label as NSString).draw(
            in: ghost.insetBy(dx: 10, dy: 10),
            withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor])
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, !restoredViewport else { return }
        restoredViewport = true
        if let path = session.document?.fileURL?.path,
            let values = UserDefaults.standard.array(forKey: "viewport:" + path) as? [Double],
            values.count == 3, values.allSatisfy({ $0.isFinite })
        {
            session.zoom = min(3, max(0.15, values[0]))
            pan = CGPoint(x: values[1], y: values[2])
        }
        rebuild()
    }
    func persistViewport() {
        guard let path = session.document?.fileURL?.path else { return }
        UserDefaults.standard.set([session.zoom, pan.x, pan.y], forKey: "viewport:" + path)
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
        dropPlacement = nil
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
            if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift) {
                session.toggleSelection(id)
            } else if !session.selection.contains(id) {
                session.selectTopic(id)
            }
            draggingTopic = id
            if event.clickCount == 2 {
                draggingTopic = nil
                beginEditing(selectAll: false)
                editor?.mouseDown(with: event)
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
        } else if draggingTopic != nil {
            if p.x < 28 { pan.x += 12 }
            if p.x > bounds.width - 28 { pan.x -= 12 }
            if p.y < 28 { pan.y += 12 }
            if p.y > bounds.height - 28 { pan.y -= 12 }
            dragPoint = world(p)
            dropPlacement = dropPlacement(at: dragPoint)
            dropTarget = dropPlacement?.lineY == nil ? dropPlacement?.parent : nil
            session.message =
                dropPlacement == nil
                ? "옮길 수 있는 토픽이나 토픽 사이에 놓으세요. Esc로 취소합니다."
                : (dropTarget == nil ? "파란 선 위치로 순서를 변경합니다." : "초록색 토픽 아래로 이동합니다.")
        } else {
            pan = CGPoint(x: originalPan.x + p.x - mouseStart.x, y: originalPan.y + p.y - mouseStart.y)
        }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if bending, let bendPreview {
            session.updateRelation("관계선 곡률 변경") { $0.bend = bendPreview }
        } else if dragged, draggingTopic != nil, let placement = dropPlacement {
            let ids = session.selection
            session.change("토픽 이동") {
                $0.move(ids, to: placement.parent, before: placement.before, side: placement.side)
            }
        }
        if !dragged, let id = draggingTopic, event.modifierFlags.intersection([.command, .shift]).isEmpty {
            session.selectTopic(id)
        }
        draggingTopic = nil
        dropTarget = nil
        dropPlacement = nil
        bending = false
        bendPreview = nil
        dragged = false
        if session.connectingFrom == nil { session.cancelConnecting() }
        needsDisplay = true
        updateAccessibility()
        persistViewport()
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
        persistViewport()
        updateAccessibility()
    }
    override func magnify(with event: NSEvent) { setZoom(session.zoom * (1 + event.magnification)) }
    func setZoom(_ scale: Double) {
        finishEditing()
        let oldZoom = session.zoom
        session.zoom = min(3, max(0.15, scale))
        pan.x *= session.zoom / oldZoom
        pan.y *= session.zoom / oldZoom
        persistViewport()
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
        persistViewport()
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
    func beginEditing(selectAll: Bool = true) {
        finishEditing()
        guard let id = session.selectedTopic, let topic = session.map.topic(id), let rect = frames[id] else {
            return
        }
        reveal(id)
        let r = screenRect(rect)
        let field = TopicTextView(frame: r)
        field.string = topic.title
        let font = nodeFont(topic)
        field.font = NSFont(descriptor: font.fontDescriptor, size: font.pointSize * session.zoom)
        field.textColor = topic.parentID == nil ? .textBackgroundColor : .labelColor
        field.backgroundColor = topic.parentID == nil ? .labelColor : .textBackgroundColor
        field.isRichText = false
        field.allowsUndo = true
        field.isAutomaticQuoteSubstitutionEnabled = false
        field.isVerticallyResizable = true
        field.isHorizontallyResizable = false
        field.textContainerInset = NSSize(width: 18 * session.zoom, height: 13 * session.zoom)
        field.textContainer?.lineFragmentPadding = 0
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
        editingChanged = false
        editingID = id
        editor = field
        addSubview(field)
        setAccessibilityChildren([field])
        window?.makeFirstResponder(field)
        if selectAll { field.selectAll(nil) }
        needsDisplay = true
    }
    func textDidChange(_ notification: Notification) {
        editingChanged = true
        // Data snapshots include the live buffer without splitting a title edit into many undo steps.
        session.document?.updateChangeCount(.changeDone)
        rebuild()
    }
    var mapForSaving: MindMap {
        var map = session.map
        if let editor, let id = editingID, let index = map.topics.firstIndex(where: { $0.id == id }) {
            map.topics[index].title = editor.string.isEmpty ? "새 토픽" : editor.string
        }
        return map
    }
    func replaceEditorText(_ text: String) {
        editor?.string = text
        textDidChange(Notification(name: NSText.didChangeNotification))
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
        if editingChanged { session.document?.updateChangeCount(.changeDone) }
        editingChanged = false
        rebuild()
        window?.makeFirstResponder(self)
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 48: session.add(child: true)
        case 36: session.add(child: false)
        case 51, 117: session.deleteSelection()
        case 53:
            session.cancelConnecting()
            draggingTopic = nil
            dropTarget = nil
            dropPlacement = nil
            dragged = false
            needsDisplay = true
        case 49: beginEditing()
        case 123, 124, 125, 126: navigate(event.keyCode)
        default:
            if !event.modifierFlags.intersection([.command, .control]).isEmpty {
                super.keyDown(with: event)
                return
            }
            if let text = event.characters, !text.isEmpty,
                text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
            {
                beginEditing()
                editor?.keyDown(with: event)
            } else {
                super.keyDown(with: event)
            }
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
        if let id = topicAt(world(convert(event.locationInWindow, from: nil))),
            !session.selection.contains(id)
        {
            session.selectTopic(id)
        }
        let menu = NSMenu()
        for (title, action) in [
            ("하위 토픽 추가", #selector(EditorController.addChildTopic(_:))),
            ("형제 토픽 추가", #selector(EditorController.addSibling(_:))),
            ("제목 편집", #selector(EditorController.editTopic(_:))),
            ("관계선 연결", #selector(EditorController.connect(_:))),
            ("가지 접기/펼치기", #selector(EditorController.fold(_:))),
            ("가지 복사", #selector(copy(_:))),
            ("가지 붙여넣기", #selector(paste(_:))),
            ("가지 복제", #selector(duplicateBranches(_:))),
            ("위로 이동", #selector(EditorController.moveTopicUp(_:))),
            ("아래로 이동", #selector(EditorController.moveTopicDown(_:))),
            ("한 단계 밖으로", #selector(EditorController.outdent(_:))),
            ("선택 항목 삭제", #selector(EditorController.deleteItem(_:))),
        ] {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        }
        return menu
    }
    private func updateAccessibility() {
        if let editor {
            setAccessibilityChildren([editor])
            return
        }
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

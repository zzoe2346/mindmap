import AppKit
import Combine
import SwiftUI

@MainActor final class EditorController: NSViewController, NSToolbarDelegate, NSUserInterfaceValidations {
    let session: EditorSession
    let canvas: MapCanvas
    private var inspector: NSView!
    private var inspectorWidth: NSLayoutConstraint!
    private var status: NSTextField!
    private var subscriptions = Set<AnyCancellable>()
    init(session: EditorSession) {
        self.session = session
        self.canvas = MapCanvas(session: session)
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1240, height: 760))
        canvas.translatesAutoresizingMaskIntoConstraints = false
        inspector = NSHostingView(rootView: InspectorView(session: session))
        inspector.translatesAutoresizingMaskIntoConstraints = false
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        status = NSTextField(labelWithString: "")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.translatesAutoresizingMaskIntoConstraints = false
        status.lineBreakMode = .byTruncatingTail
        let bottom = NSBox()
        bottom.boxType = .separator
        bottom.translatesAutoresizingMaskIntoConstraints = false
        for child in [canvas, inspector!, divider, bottom, status!] { view.addSubview(child) }
        inspectorWidth = inspector.widthAnchor.constraint(equalToConstant: 280)
        NSLayoutConstraint.activate([
            canvas.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            canvas.topAnchor.constraint(equalTo: view.topAnchor),
            canvas.bottomAnchor.constraint(equalTo: bottom.topAnchor),
            canvas.trailingAnchor.constraint(equalTo: divider.leadingAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.topAnchor.constraint(equalTo: view.topAnchor),
            divider.bottomAnchor.constraint(equalTo: bottom.topAnchor),
            inspector.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            inspector.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inspector.topAnchor.constraint(equalTo: view.topAnchor),
            inspector.bottomAnchor.constraint(equalTo: bottom.topAnchor), inspectorWidth,
            bottom.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottom.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottom.heightAnchor.constraint(equalToConstant: 1),
            bottom.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -7),
            status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            status.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -7),
            status.heightAnchor.constraint(equalToConstant: 16),
        ])
        session.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.updateStatus() }
        }.store(in: &subscriptions)
        updateStatus()
    }
    func updateStatus() {
        status?.stringValue =
            "\(session.map.topics.count)개 토픽   \(session.map.relationships.count)개 관계선     |     \(Int(session.zoom * 100))%     |     \(session.message)"
        view.window?.toolbar?.validateVisibleItems()
    }
    private var editingText: Bool { view.window?.firstResponder is NSTextView }
    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(addChildTopic(_:)), #selector(addSibling(_:)), #selector(editTopic(_:)),
            #selector(connect(_:)):
            return session.selectedTopic != nil && !editingText
        case #selector(fold(_:)):
            return session.selectedTopic.map { !session.map.children($0).isEmpty } ?? false
        case #selector(deleteItem(_:)):
            return !editingText
                && (session.selectedRelation != nil
                    || session.selectedTopic.map { $0 != session.map.root.id } == true)
        default: return true
        }
    }
    @objc func addChildTopic(_ sender: Any?) { session.add(child: true) }
    @objc func addSibling(_ sender: Any?) { session.add(child: false) }
    @objc func editTopic(_ sender: Any?) { canvas.beginEditing() }
    @objc func deleteItem(_ sender: Any?) { session.deleteSelection() }
    @objc func connect(_ sender: Any?) { session.beginRelationship() }
    @objc func fold(_ sender: Any?) { session.toggleFold() }
    @objc func zoomIn(_ sender: Any?) { canvas.setZoom(session.zoom * 1.2) }
    @objc func zoomOut(_ sender: Any?) { canvas.setZoom(session.zoom / 1.2) }
    @objc func fit(_ sender: Any?) { canvas.fitAll() }
    @objc func actualSize(_ sender: Any?) { canvas.setZoom(1) }
    @objc func toggleInspector(_ sender: Any?) {
        canvas.finishEditing()
        inspector.isHidden.toggle()
        inspectorWidth.constant = inspector.isHidden ? 0 : 280
    }
    func configureToolbar(_ window: NSWindow) {
        let toolbar = NSToolbar(identifier: "MindmapToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        window.toolbar = toolbar
        window.toolbarStyle = .unified
    }
    private let identifiers = ["child", "sibling", "connect", "fold", "fit", "inspector"]
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        identifiers.map { .init($0) } + [.flexibleSpace]
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [
            .init("child"), .init("sibling"), .init("connect"), .init("fold"), .flexibleSpace, .init("fit"),
            .init("inspector"),
        ]
    }
    func toolbar(
        _ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        let definitions: [String: (String, String, Selector)] = [
            "child": ("하위 토픽", "plus.square.on.square", #selector(addChildTopic(_:))),
            "sibling": ("형제 토픽", "plus.rectangle", #selector(addSibling(_:))),
            "connect": ("관계선", "arrow.triangle.branch", #selector(connect(_:))),
            "fold": ("접기/펼치기", "rectangle.compress.vertical", #selector(fold(_:))),
            "fit": ("전체 보기", "arrow.up.left.and.arrow.down.right", #selector(fit(_:))),
            "inspector": ("속성", "sidebar.right", #selector(toggleInspector(_:))),
        ]
        guard let (label, symbol, action) = definitions[id.rawValue] else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = label
        item.paletteLabel = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.target = self
        item.action = action
        item.toolTip = label
        return item
    }
}

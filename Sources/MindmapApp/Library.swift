import AppKit
import Combine
import MindmapCore
import SwiftUI

struct LibraryItem: Identifiable {
    var id: String
    var url: URL?
    var document: MindmapDocument?
    var title: String
    var map: MindMap?
    var modified: Date
    var unavailable: Bool
}

@MainActor final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()
    @Published var items: [LibraryItem] = []
    @Published var favorites = Set(UserDefaults.standard.stringArray(forKey: "library.favorites") ?? [])
    func relocated(from oldURL: URL?, to url: URL, draftID: UUID?) {
        let defaults = UserDefaults.standard
        let moved = oldURL.map { $0 != url && !FileManager.default.fileExists(atPath: $0.path) } ?? false
        let oldKey = moved ? oldURL?.path : (oldURL == nil ? draftID?.uuidString : nil)
        if let oldKey, favorites.remove(oldKey) != nil {
            favorites.insert(url.path)
            defaults.set(Array(favorites), forKey: "library.favorites")
        }
        if moved, let oldURL {
            var ignored = Set(defaults.stringArray(forKey: "library.movedPaths") ?? [])
            ignored.insert(oldURL.path)
            defaults.set(Array(ignored), forKey: "library.movedPaths")
            if let viewport = defaults.array(forKey: "viewport:" + oldURL.path) {
                defaults.set(viewport, forKey: "viewport:" + url.path)
            }
        }
        record(url)
    }
    func record(_ url: URL) {
        guard url.pathExtension == "mindmap" else { return }
        var paths = UserDefaults.standard.stringArray(forKey: "library.paths") ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        UserDefaults.standard.set(Array(paths.prefix(100)), forKey: "library.paths")
    }
    func refresh() {
        let documents = NSDocumentController.shared.documents.compactMap { $0 as? MindmapDocument }
        let paths =
            (NSDocumentController.shared.recentDocumentURLs.map(\.path)
                + (UserDefaults.standard.stringArray(forKey: "library.paths") ?? [])
                + documents.compactMap { $0.fileURL?.path })
        let ignored = Set(UserDefaults.standard.stringArray(forKey: "library.movedPaths") ?? [])
        let unique = Array(Set(paths)).filter {
            $0.hasSuffix(".mindmap") && (!ignored.contains($0) || FileManager.default.fileExists(atPath: $0))
        }
        var entries = unique.map { path -> LibraryItem in
            let url = URL(fileURLWithPath: path)
            let document = documents.first { $0.fileURL?.standardizedFileURL == url.standardizedFileURL }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            var map = document?.session.canvas?.mapForSaving ?? document?.session.map
            if map == nil, let size = values?.fileSize, size <= 16_000_000 {
                map = (try? Data(contentsOf: url)).flatMap { try? MindMap.decode($0) }
            }
            return LibraryItem(
                id: path, url: url, document: document, title: url.deletingPathExtension().lastPathComponent,
                map: map, modified: values?.contentModificationDate ?? .distantPast, unavailable: map == nil)
        }
        entries += documents.filter { $0.fileURL == nil }.map { doc in
            LibraryItem(
                id: doc.libraryID.uuidString, document: doc, title: doc.session.map.root.title,
                map: doc.session.canvas?.mapForSaving ?? doc.session.map, modified: Date(), unavailable: false
            )
        }
        items = entries.sorted { $0.modified > $1.modified }
    }
    func toggleFavorite(_ item: LibraryItem) {
        if favorites.contains(item.id) { favorites.remove(item.id) } else { favorites.insert(item.id) }
        UserDefaults.standard.set(Array(favorites), forKey: "library.favorites")
    }
    func open(_ item: LibraryItem, action: ((MindmapDocument) -> Void)? = nil) {
        if let document = item.document {
            document.showWindows()
            action?(document)
            return
        }
        guard let url = item.url else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { document, _, error in
            if let error { NSApp.presentError(error) }
            if let document = document as? MindmapDocument { action?(document) }
        }
    }
    func duplicate(_ item: LibraryItem) {
        guard let map = item.document?.session.canvas?.mapForSaving ?? item.document?.session.map ?? item.map
        else { return }
        let document = MindmapDocument()
        document.session.map = map
        document.session.selectTopic(map.root.id)
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
        document.updateChangeCount(.changeDone)
        refresh()
    }
}

@MainActor final class HomeWindowController: NSWindowController {
    static let shared = HomeWindowController()
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 740),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "mindmap — 홈"
        window.minSize = NSSize(width: 760, height: 520)
        window.contentView = NSHostingView(rootView: HomeView(store: .shared))
        window.center()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func show() {
        LibraryStore.shared.refresh()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct HomeView: View {
    @ObservedObject var store: LibraryStore
    @State private var search = ""
    @State private var favoritesOnly = false
    private var visibleItems: [LibraryItem] {
        store.items.filter { item in
            (!favoritesOnly || store.favorites.contains(item.id))
                && (search.isEmpty || item.title.localizedStandardContains(search)
                    || (item.map?.topics.contains { $0.title.localizedStandardContains(search) } ?? false))
        }
    }
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Label("mindmap", systemImage: "point.3.connected.trianglepath.dotted").font(.title2.bold())
                    .padding(.vertical, 22)
                Button {
                    favoritesOnly = false
                } label: {
                    Label("최근 문서", systemImage: "clock").frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10).background(
                            !favoritesOnly ? Color.accentColor.opacity(0.13) : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
                }
                Button {
                    favoritesOnly = true
                } label: {
                    Label("즐겨찾기", systemImage: "star").frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10).background(
                            favoritesOnly ? Color.accentColor.opacity(0.13) : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
                }
                Divider().padding(.vertical, 8)
                Button {
                    NSDocumentController.shared.openDocument(nil)
                } label: {
                    Label("파일 열기", systemImage: "folder").padding(10)
                }
                Spacer()
                Text("생각을 연결하는 나만의 공간\n문서는 이 Mac에 저장됩니다.").font(.caption).foregroundStyle(.secondary)
                    .lineSpacing(4)
            }.buttonStyle(.plain).padding(20).frame(width: 190).frame(maxHeight: .infinity).background(
                Color(nsColor: .windowBackgroundColor))
            Divider()
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(favoritesOnly ? "즐겨찾기" : "최근 문서").font(.largeTitle.bold())
                        Text("다시 이어가고 싶은 생각을 골라보세요.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        NSDocumentController.shared.newDocument(nil)
                    } label: {
                        Label("새 마인드맵", systemImage: "plus")
                    }.buttonStyle(.borderedProminent).controlSize(.large)
                }
                TextField("제목이나 토픽 검색", text: $search).textFieldStyle(.roundedBorder).accessibilityLabel(
                    "홈 문서 검색")
                if visibleItems.isEmpty {
                    ContentUnavailableView(
                        search.isEmpty ? "생각 하나에서 시작하세요" : "검색 결과가 없습니다",
                        systemImage: search.isEmpty ? "square.stack" : "magnifyingglass",
                        description: Text(
                            search.isEmpty ? "새 마인드맵을 만들거나 저장한 파일을 열어보세요." : "다른 제목이나 토픽으로 검색해보세요."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320))], spacing: 22) {
                            ForEach(visibleItems) { item in
                                VStack(alignment: .leading, spacing: 10) {
                                    Button {
                                        store.open(item)
                                    } label: {
                                        MapThumbnail(map: item.map).frame(height: 146).frame(
                                            maxWidth: .infinity
                                        ).background(
                                            Color(nsColor: .textBackgroundColor),
                                            in: RoundedRectangle(cornerRadius: 12)
                                        ).overlay(
                                            RoundedRectangle(cornerRadius: 12).stroke(
                                                Color.secondary.opacity(0.18)))
                                    }.buttonStyle(.plain).accessibilityLabel("\(item.title) 열기")
                                    HStack {
                                        Text(item.title).font(.headline).lineLimit(1)
                                        Spacer()
                                        Button {
                                            store.toggleFavorite(item)
                                        } label: {
                                            Image(
                                                systemName: store.favorites.contains(item.id)
                                                    ? "star.fill" : "star")
                                        }.buttonStyle(.plain).foregroundStyle(
                                            store.favorites.contains(item.id) ? .orange : .secondary
                                        ).accessibilityLabel("\(item.title) 즐겨찾기")
                                    }
                                    Text(
                                        item.unavailable
                                            ? "파일을 찾거나 읽을 수 없습니다"
                                            : item.url == nil
                                                ? "저장 전 초안"
                                                : item.modified.formatted(
                                                    date: .abbreviated, time: .shortened)
                                    ).font(.caption).foregroundStyle(.secondary)
                                }.contextMenu {
                                    Button("열기") { store.open(item) }
                                    Button("이름 변경") {
                                        store.open(item) {
                                            $0.perform(NSSelectorFromString("renameDocument:"), with: nil)
                                        }
                                    }
                                    Button("복제") { store.duplicate(item) }.disabled(item.map == nil)
                                    Button(store.favorites.contains(item.id) ? "즐겨찾기 해제" : "즐겨찾기") {
                                        store.toggleFavorite(item)
                                    }
                                    if let url = item.url {
                                        Button("Finder에서 보기") {
                                            NSWorkspace.shared.activateFileViewerSelecting([url])
                                        }
                                    }
                                }
                            }
                        }.padding(.bottom, 20)
                    }
                }
                Spacer(minLength: 0)
            }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity).background(
                Color(nsColor: .controlBackgroundColor))
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            store.refresh()
        }
    }
}

struct MapThumbnail: View {
    let map: MindMap?
    var body: some View {
        Canvas { context, size in
            guard let map else { return }
            let sizes = Dictionary(
                uniqueKeysWithValues: map.topics.map { ($0.id, MapRect(width: 150, height: 48)) })
            let frames = TreeLayout.frames(for: map, sizes: sizes)
            let rects = frames.values.map { CGRect(x: $0.x, y: $0.y, width: $0.width, height: $0.height) }
            guard var all = rects.first else { return }
            for rect in rects { all = all.union(rect) }
            let scale = min((size.width - 28) / all.width, (size.height - 28) / all.height, 0.8)
            context.translateBy(x: size.width / 2 - all.midX * scale, y: size.height / 2 - all.midY * scale)
            context.scaleBy(x: scale, y: scale)
            for topic in map.topics {
                guard let frame = frames[topic.id] else { continue }
                let rect = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
                if let parent = topic.parentID, let from = frames[parent] {
                    var line = Path()
                    line.move(to: CGPoint(x: from.midX, y: from.midY))
                    line.addLine(to: CGPoint(x: frame.midX, y: frame.midY))
                    context.stroke(line, with: .color(.accentColor.opacity(0.5)), lineWidth: 2)
                }
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 9),
                    with: .color(
                        topic.parentID == nil ? .accentColor : Color(nsColor: .windowBackgroundColor)))
                context.draw(
                    Text(String(topic.title.prefix(16))).font(.system(size: 13)).foregroundColor(
                        topic.parentID == nil ? .white : .primary), in: rect.insetBy(dx: 8, dy: 10))
            }
        }.accessibilityHidden(true)
    }
}

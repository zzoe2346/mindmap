import MindmapCore
import SwiftUI

struct InspectorView: View {
    @ObservedObject var session: EditorSession
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("속성").font(.title3.weight(.semibold))
                    Spacer()
                    Image(systemName: "slider.horizontal.3").foregroundStyle(.secondary)
                }
                if let id = session.selectedRelation,
                    let edge = session.map.relationships.first(where: { $0.id == id })
                {
                    RelationshipInspector(session: session, edge: edge).id(id)
                } else if let id = session.selectedTopic, let topic = session.map.topic(id) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(topic.parentID == nil ? "중심 토픽" : "토픽", systemImage: "circle.hexagongrid")
                            .foregroundStyle(.secondary)
                        Text(topic.title).font(.system(size: 17, weight: .medium)).lineLimit(8).textSelection(
                            .enabled)
                        Button("제목 편집") { session.canvas?.beginEditing() }.buttonStyle(.bordered)
                        if session.selection.count > 1 {
                            Text("\(session.selection.count)개 토픽 선택됨").foregroundStyle(.tint)
                        }
                        Text("토픽 너비").font(.callout)
                        Slider(
                            value: Binding(
                                get: { topic.textWidth ?? 300 },
                                set: { value in
                                    session.canvas?.finishEditing()
                                    session.change("토픽 너비 변경") { map in
                                        if let index = map.topics.firstIndex(where: { $0.id == id }) {
                                            map.topics[index].textWidth = value
                                        }
                                    }
                                }), in: 120...600, step: 20
                        ).accessibilityLabel("토픽 너비")
                        Button("너비 자동 맞춤") {
                            session.change("토픽 너비 자동 맞춤") { map in
                                if let index = map.topics.firstIndex(where: { $0.id == id }) {
                                    map.topics[index].textWidth = nil
                                }
                            }
                        }
                        if session.connectingFrom != nil {
                            Text("캔버스에서 연결할 토픽을 클릭하세요.").font(.callout).foregroundStyle(.tint)
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    Text("마인드맵").font(.headline)
                    Picker(
                        "가지 배치",
                        selection: Binding(
                            get: { session.map.layout },
                            set: { value in
                                session.change("가지 배치 변경") { $0.layout = value }
                                session.canvas?.rebuild()
                                session.canvas?.fitAll()
                            })
                    ) {
                        ForEach(MapLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    HStack {
                        Text("글자 크기")
                        Spacer()
                        Text("\(Int(session.fontSize)) pt").foregroundStyle(.secondary)
                    }
                    Slider(value: $session.fontSize, in: 14...28, step: 1).accessibilityLabel("토픽 글자 크기")
                        .onChange(of: session.fontSize) { session.applyPreferences() }
                    Picker("화면", selection: $session.theme) {
                        Text("시스템").tag("system")
                        Text("밝게").tag("light")
                        Text("어둡게").tag("dark")
                    }.onChange(of: session.theme) { session.applyPreferences() }
                }
                if !session.map.relationships.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("관계선 \(session.map.relationships.count)").font(.headline)
                        ForEach(session.map.relationships) { edge in
                            Button {
                                session.selectRelation(edge.id)
                                session.canvas?.reveal(edge.source)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(edge.label.isEmpty ? "이름 없는 관계선" : edge.label).font(
                                        .callout.weight(.medium))
                                    Text(
                                        "\(session.map.topic(edge.source)?.title ?? "") → \(session.map.topic(edge.target)?.title ?? "")"
                                    ).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(9)
                                    .background(
                                        session.selectedRelation == edge.id
                                            ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Divider()
                VStack(alignment: .leading, spacing: 7) {
                    Text("빠른 조작").font(.headline)
                    shortcut("하위 토픽", "Tab")
                    shortcut("형제 토픽", "Enter")
                    shortcut("관계선", "⇧⌘R")
                    shortcut("접기와 펼치기", "⌘/")
                    shortcut("전체 보기", "⌘0")
                    shortcut("토픽 찾기", "⌘F")
                    shortcut("가지 복제", "⌘D")
                    shortcut("순서 이동", "⌥⌘↑ ↓")
                    Text("토픽 중앙에 놓으면 하위로, 가장자리나 사이에 놓으면 순서가 바뀝니다. ⌘ 클릭으로 여러 토픽을 선택하세요.").font(.caption)
                        .foregroundStyle(
                            .secondary
                        ).padding(.top, 5)
                }
            }.padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    private func shortcut(_ title: String, _ keys: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(keys).monospaced()
        }.font(.caption).foregroundStyle(.secondary)
    }
}
struct RelationshipInspector: View {
    @ObservedObject var session: EditorSession
    let edge: Relationship
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("관계선", systemImage: "arrow.triangle.branch").foregroundStyle(.secondary)
            Text(
                "\(session.map.topic(edge.source)?.title ?? "") → \(session.map.topic(edge.target)?.title ?? "")"
            ).font(.callout).lineLimit(4)
            TextField(
                "관계 설명",
                text: Binding(
                    get: { edge.label },
                    set: { value in session.updateRelation("관계 설명 편집") { $0.label = value } }),
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder).lineLimit(1...5).accessibilityLabel("관계 설명")
            Picker(
                "화살표",
                selection: Binding(
                    get: { edge.arrow },
                    set: { value in session.updateRelation("화살표 변경") { $0.arrow = value } })
            ) {
                ForEach(Arrow.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            HStack {
                Text("곡률")
                Spacer()
                Text("\(Int(edge.bend))").foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { edge.bend },
                    set: { value in
                        session.updateRelation("관계선 곡률 변경") { $0.bend = value }
                    }), in: -500...500, step: 5
            ).accessibilityLabel("관계선 곡률")
            Text("선 가운데의 파란 점을 드래그해 곡선을 조절할 수도 있어요.").font(.caption).foregroundStyle(.secondary)
            Button("관계선 삭제", role: .destructive) { session.deleteSelection() }
        }
    }
}

import AppKit
import Foundation
import SwiftUI

enum WhoAmISection: String, CaseIterable, Identifiable {
    case card = "Card"
    case rewind = "Rewind"
    case identity = "Identity"
    case connectors = "Connectors"
    case reports = "Reports"
    case evidence = "Evidence"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .card: return "person.text.rectangle"
        case .rewind: return "clock.arrow.circlepath"
        case .identity: return "person.crop.square"
        case .connectors: return "point.3.connected.trianglepath.dotted"
        case .reports: return "doc.text"
        case .evidence: return "checkmark.seal"
        }
    }
}

private struct SetupResponse: Decodable {
    let ready: Bool
    let state: String
    let profile: OwnerProfile?
    let personalModel: PersonalModelStatus?
}

private struct OwnerProfile: Decodable {
    let modelId: String?
    let displayName: String?
    let handle: String?
    let tagline: String?
}

private struct PersonalModelStatus: Decodable {
    let installed: Bool?
    let initialized: Bool?
    let buildStatus: String?
    let connection: String?
}

private struct BootstrapResponse: Decodable {
    let modelId: String
    let revision: Int
    let snapshot: PersonalModelSnapshot
}

struct PersonalModelSnapshot: Decodable {
    let model: ModelIdentity
    let authorization: AuthorizationSnapshot?
    let card: CardSnapshot?
    let personalModel: PersonalModelSummary?
    let now: NowSnapshot?
    let time: TimeSnapshot?
    let identity: IdentitySnapshot?
    let connectors: [ConnectorSnapshot]?
    let reports: [ReportSnapshot]?
}

struct ModelIdentity: Decodable {
    let id: String
    let displayName: String
    let handle: String
    let memberNumber: String?
    let sinceYear: Int?
    let status: String?
}

struct AuthorizationSnapshot: Decodable {
    let viewerMode: String?
    let scopes: [String]?
}

struct CardSnapshot: Decodable {
    let monthYear: String?
    let tagline: String?
    let publicUrl: String?
    let material: String?
    let glyph: [Bool]?
}

struct PersonalModelSummary: Decodable {
    let memoryCount: Int?
    let root: String?
    let updatedAt: String?
    let faces: [FaceSnapshot]?
}

struct FaceSnapshot: Decodable, Identifiable {
    let id: String
    let text: String
    let observations: Int?
    let confidence: Double?
    let evidenceRefs: [String]?
}

struct NowSnapshot: Decodable {
    let items: [NowItem]?
}

struct NowItem: Decodable, Identifiable {
    let id: String
    let kind: String
    let title: String
    let why: String?
    let when: String?
    let dayId: String?
}

struct TimeSnapshot: Decodable {
    let days: [DaySnapshot]?
}

struct DaySnapshot: Decodable, Identifiable {
    let id: String
    let title: String?
    let portrait: String?
    let letter: String?
    let events: [EventSnapshot]?
}

struct EventSnapshot: Decodable, Identifiable {
    let id: String
    let time: String?
    let title: String
    let detail: String?
    let app: String?
    let evidenceRef: String?
}

struct IdentitySnapshot: Decodable {
    let description: String?
    let dailyLine: String?
    let weeklyLetter: [String]?
}

struct ConnectorSnapshot: Decodable, Identifiable {
    let id: String
    let name: String
    let product: String?
    let status: String?
    let sessionId: String?
}

struct ReportSnapshot: Decodable, Identifiable {
    let id: String
    let modelId: String?
    let connectorId: String?
    let title: String
    let summary: String?
    let updatedAt: String?
    let readCount: Int?
    let evidenceCount: Int?
    let sections: [ReportSection]?
    let evidenceRefs: [String]?
}

struct ReportSection: Decodable, Identifiable {
    let kind: String?
    let title: String
    let body: String

    var id: String { "\(kind ?? "section"):\(title)" }
}

struct SearchResponse: Decodable {
    let results: [SearchResult]?
}

struct SearchResult: Decodable, Identifiable {
    let id: String?
    let title: String?
    let text: String?
    let score: Double?

    var stableID: String { id ?? "\(title ?? ""):\(text ?? "")" }
}

struct AskResponse: Decodable {
    let answer: String
}

private struct ConnectorsResponse: Decodable {
    let connectors: [ConnectorSnapshot]
}

private struct ReportsResponse: Decodable {
    let reports: [ReportSnapshot]
}

private struct OperationResponse: Decodable {
    let ok: Bool
}

private struct EvidenceEnvelope: Decodable {
    let evidence: EvidenceSnapshot
}

struct EvidenceSnapshot: Decodable {
    let modelId: String
    let reference: String
    let content: JSONValue
    let receipt: String?
    let capturedAt: String?
}

indirect enum JSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { throw NativeAPIError.invalidResponse }
    }

    var readableText: String {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.formatted()
        case .bool(let value): return value ? "true" : "false"
        case .null: return "—"
        case .array(let values): return values.map(\.readableText).joined(separator: "\n")
        case .object(let values):
            return values.keys.sorted().map { key in
                "\(key): \(values[key]?.readableText ?? "—")"
            }.joined(separator: "\n")
        }
    }
}

private struct EmptyResponse: Decodable {
    let ok: Bool
}

private struct APIErrorResponse: Decodable {
    let error: String?
}

private enum NativeAPIError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Personal Model 返回了无法识别的数据。"
        case .server(let message):
            return message
        }
    }
}

@MainActor
final class PersonalModelAppState: ObservableObject {
    @Published var selectedSection: WhoAmISection = .card
    @Published private(set) var snapshot: PersonalModelSnapshot?
    @Published private(set) var setupState = "loading"
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published var searchQuery = ""
    @Published private(set) var searchResults: [SearchResult] = []
    @Published var question = ""
    @Published private(set) var answer = ""
    @Published private(set) var connectors: [ConnectorSnapshot] = []
    @Published private(set) var reports: [ReportSnapshot] = []
    @Published private(set) var selectedEvidence: EvidenceSnapshot?
    @Published private(set) var connectingConnector = ""
    @Published private(set) var isCorrecting = false
    @Published private(set) var correctionSaved = false
    @Published var isAskOpen = false

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
    }

    var modelStatusLabel: String {
        guard let snapshot else {
            switch setupState {
            case "profile_required": return "需要创建 Card"
            case "not_installed": return "需要安装 Personal Model"
            case "onboarding_required": return "需要完成权限设置"
            default: return "正在连接"
            }
        }
        return "\(snapshot.model.displayName) · 已连接"
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let setup: SetupResponse = try await request(path: "api/setup/status")
            setupState = setup.state
            guard setup.ready else { return }
            let bootstrap: BootstrapResponse = try await request(path: "api/model/bootstrap")
            snapshot = bootstrap.snapshot
            connectors = bootstrap.snapshot.connectors ?? []
            reports = bootstrap.snapshot.reports ?? []
            setupState = "ready"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveProfile(displayName: String, handle: String) async {
        do {
            let _: SetupResponse = try await request(
                path: "api/setup/profile",
                method: "POST",
                json: ["displayName": displayName, "handle": handle]
            )
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func launchPersonalModelSetup() async {
        do {
            let _: EmptyResponse = try await request(
                path: "api/setup/personal-model",
                method: "POST",
                json: [:]
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func search() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        do {
            let response: SearchResponse = try await request(
                path: "api/model/search",
                method: "POST",
                json: ["query": query]
            )
            searchResults = response.results ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func ask() async {
        let value = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do {
            let response: AskResponse = try await request(
                path: "api/model/ask",
                method: "POST",
                json: ["question": value]
            )
            answer = response.answer
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func connect(_ connectorId: String) async {
        guard connectingConnector.isEmpty else { return }
        connectingConnector = connectorId
        defer { connectingConnector = "" }
        do {
            let encoded = connectorId.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed
            ) ?? connectorId
            let _: OperationResponse = try await request(
                path: "api/model/connectors/\(encoded)/connect",
                method: "POST",
                json: [:]
            )
            let response: ConnectorsResponse = try await request(
                path: "api/model/connectors"
            )
            connectors = response.connectors
            let reportResponse: ReportsResponse = try await request(path: "api/model/reports")
            reports = reportResponse.reports
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func connectAll() async {
        let pending = connectors.filter {
            $0.status != "connected" && $0.status != "missing"
        }
        for connector in pending {
            await connect(connector.id)
        }
    }

    func loadEvidence(_ reference: String) async {
        do {
            let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
            let encoded = reference.addingPercentEncoding(withAllowedCharacters: allowed) ?? reference
            let response: EvidenceEnvelope = try await request(
                path: "api/model/evidence/\(encoded)"
            )
            selectedEvidence = response.evidence
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func closeEvidence() {
        selectedEvidence = nil
    }

    func correct(_ correction: String) async {
        let value = correction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        isCorrecting = true
        correctionSaved = false
        defer { isCorrecting = false }
        do {
            let _: OperationResponse = try await request(
                path: "api/model/correct",
                method: "POST",
                json: ["correction": value]
            )
            correctionSaved = true
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func shareCard() {
        guard let snapshot else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            "\(snapshot.model.displayName) · \(snapshot.card?.tagline ?? "Personal Model")\n\(snapshot.card?.publicUrl ?? snapshot.model.id)",
            forType: .string
        )
    }

    func dismissError() {
        errorMessage = nil
    }

    private func request<Response: Decodable>(
        path: String,
        method: String = "GET",
        json: [String: String]? = nil
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw NativeAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NativeAPIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
            throw NativeAPIError.server(apiError?.error ?? "Personal Model 暂时不可用。")
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}

struct WhoAmIRootView: View {
    @StateObject private var state: PersonalModelAppState

    init(state: PersonalModelAppState) {
        _state = StateObject(wrappedValue: state)
    }

    var body: some View {
        ZStack {
            WhoAmIBackground()
            VStack(spacing: 0) {
                NativeTopBar(state: state)
                Group {
                    if let snapshot = state.snapshot {
                        NativeSectionContent(state: state, snapshot: snapshot)
                    } else {
                        NativeSetupView(state: state)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let evidence = state.selectedEvidence {
                NativeEvidenceDetail(state: state, evidence: evidence)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .task { await state.load() }
        .alert(
            "Who Am I",
            isPresented: Binding(
                get: { state.errorMessage != nil },
                set: { presented in
                    if !presented { state.dismissError() }
                }
            )
        ) {
            Button("重新连接") { Task { await state.load() } }
            Button("关闭", role: .cancel) { state.dismissError() }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}

private struct WhoAmIBackground: View {
    var body: some View {
        Color.clear.ignoresSafeArea()
    }
}

private struct NativeTopBar: View {
    @ObservedObject var state: PersonalModelAppState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "asterisk")
                .font(.system(size: 12, weight: .medium))
            Text("Who Am I")
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Circle()
                .fill(state.snapshot == nil ? Color.orange : Color.green)
                .frame(width: 6, height: 6)
            Text(state.modelStatusLabel)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Menu {
                ForEach(WhoAmISection.allCases) { section in
                    Button {
                        state.selectedSection = section
                    } label: {
                        Label(section.rawValue, systemImage: section.symbol)
                    }
                }
                Divider()
                Button("刷新 Personal Model") { Task { await state.load() } }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 20)
            }
            .menuStyle(.borderlessButton)
            Text("as of now")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }
}

private struct NativeSectionContent: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot

    @ViewBuilder
    var body: some View {
        switch state.selectedSection {
        case .card:
            NativeCardHome(state: state, snapshot: snapshot)
        case .rewind:
            NativeRewindView(state: state, snapshot: snapshot)
        case .identity:
            NativeIdentityView(snapshot: snapshot)
        case .connectors:
            NativeConnectorsView(state: state, snapshot: snapshot)
        case .reports:
            NativeReportsView(state: state, snapshot: snapshot)
        case .evidence:
            NativeEvidenceView(state: state, snapshot: snapshot)
        }
    }
}

private struct NativeCardHome: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                NativeHeroCard(state: state, snapshot: snapshot)
                NativeNowPanel(state: state, snapshot: snapshot)
            }
            .padding(.vertical, 56)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct NativeHeroCard: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot
    @State private var flipped = false
    @State private var drag = CGSize.zero
    @State private var correction = ""
    @State private var copied = false

    private var glyph: [Bool] {
        let source = snapshot.card?.glyph ?? []
        return source.count == 25 ? source : Array(repeating: true, count: 25)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.10, green: 0.11, blue: 0.16), .black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.28), radius: 28, y: 20)
            front
                .opacity(flipped ? 0 : 1)
                .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
            back
                .opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(flipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
        }
        .frame(width: 430, height: 270)
        .rotation3DEffect(
            .degrees(Double(drag.width / 45)),
            axis: (x: -drag.height / 80, y: 1, z: 0),
            perspective: 0.45
        )
        .offset(x: drag.width * 0.08, y: drag.height * 0.04)
        .animation(.spring(response: 0.46, dampingFraction: 0.82), value: flipped)
        .animation(.interactiveSpring(), value: drag)
        .accessibilityLabel("\(snapshot.model.displayName) Personal Model Card")
        .accessibilityHint("点击或横向滑动翻转 Card")
    }

    private var front: some View {
        VStack {
                HStack {
                    Text("№ \(snapshot.model.memberNumber ?? "001")")
                    Spacer()
                    Text(snapshot.card?.monthYear ?? "AS OF NOW")
                }
                .font(.system(size: 8.5, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(.white.opacity(0.36))
                Spacer()
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(5), spacing: 3), count: 5), spacing: 3) {
                    ForEach(Array(glyph.enumerated()), id: \.offset) { _, isOn in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(isOn ? Color.white : Color.white.opacity(0.16))
                            .frame(width: 5, height: 5)
                    }
                }
                .frame(width: 38)
                Text(snapshot.model.handle)
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .shadow(color: .white.opacity(0.16), radius: 7)
                    .padding(.top, 10)
                Spacer()
                HStack(alignment: .bottom) {
                    Text("IDENTITY\nPERSONAL MODEL")
                    Spacer()
                    Text("ONE OF ONE\n\(snapshot.card?.publicUrl ?? snapshot.model.id)")
                        .multilineTextAlignment(.trailing)
                }
                .font(.system(size: 8.5, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.48))
        }
        .padding(28)
        .contentShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        .gesture(cardGesture)
    }

    private var back: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("PERSONAL MODEL · EVIDENCE")
                Spacer()
                Text("\(snapshot.personalModel?.memoryCount ?? 0) memories")
                Button {
                    flipped = false
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle")
                }
                .buttonStyle(.plain)
            }
            .font(.system(size: 8.5, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(.white.opacity(0.45))
            Text(snapshot.personalModel?.root ?? snapshot.card?.tagline ?? "Personal Model")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(3)
            if let face = snapshot.personalModel?.faces?.first {
                Button {
                    if let reference = face.evidenceRefs?.first {
                        Task { await state.loadEvidence(reference) }
                    }
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.seal")
                        Text(face.text).lineLimit(2)
                    }
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.72))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                TextField("告诉 Personal Model 哪里不准确…", text: $correction)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .onSubmit { Task { await state.correct(correction) } }
                Button(state.isCorrecting ? "写入中" : "Correct") {
                    Task { await state.correct(correction) }
                }
                .disabled(correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isCorrecting)
                Button(copied ? "Copied" : "Share") {
                    state.shareCard()
                    copied = true
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.78))
        }
        .padding(26)
    }

    private var cardGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag = $0.translation }
            .onEnded { value in
                if abs(value.translation.width) > 90 ||
                    (abs(value.translation.width) < 6 && abs(value.translation.height) < 6) {
                    flipped = true
                }
                drag = .zero
            }
    }
}

private struct NativeNowPanel: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search memories…", text: $state.searchQuery)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { Task { await state.search() } }
                Button {
                    searchFocused = true
                } label: {
                    EmptyView()
                }
                .keyboardShortcut("k", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                Button {
                    withAnimation(.spring(response: 0.32)) {
                        state.isAskOpen.toggle()
                    }
                } label: {
                    Label("Ask", systemImage: "sparkles")
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                Divider().frame(height: 26)
                Button("Rewind") { state.selectedSection = .rewind }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            Divider()

            if state.isAskOpen {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "sparkles")
                        TextField("Ask your Personal Model…", text: $state.question)
                            .textFieldStyle(.plain)
                            .onSubmit { Task { await state.ask() } }
                        Button("Ask") { Task { await state.ask() } }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                    if !state.answer.isEmpty {
                        Text(state.answer)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(16)
                .background(Color.accentColor.opacity(0.05))
                Divider()
            }

            if state.searchResults.isEmpty {
                ForEach(snapshot.now?.items ?? []) { item in
                    NativeNowRow(item: item)
                    Divider().padding(.leading, 20)
                }
            } else {
                ForEach(state.searchResults, id: \.stableID) { result in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(result.title ?? "Memory")
                            .font(.system(size: 14, weight: .semibold))
                        Text(result.text ?? "")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    Divider().padding(.leading, 20)
                }
            }

            HStack {
                Text("不是待办，只是时间留下的线索")
                Spacer()
                Text("\(snapshot.personalModel?.memoryCount ?? 0) memories")
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .padding(16)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.15), radius: 26, y: 18)
    }
}

private struct NativeNowRow: View {
    let item: NowItem

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: item.kind == "future" ? "circle" : "record.circle")
                .frame(width: 28, height: 28)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            Text(item.kind.uppercased())
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.system(size: 14, weight: .semibold))
                Text(item.why ?? "")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(item.when ?? "")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 64)
    }
}

private struct NativeIdentityView: View {
    let snapshot: PersonalModelSnapshot

    var body: some View {
        NativePaper {
            VStack(alignment: .leading, spacing: 30) {
                HStack {
                    Text("\(snapshot.model.displayName)'s space  /  Identity")
                    Spacer()
                    Text("updated by Personal Model · as of now")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 20) {
                    Text("IDENTITY")
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(.secondary)
                    Text(snapshot.model.displayName)
                        .font(.system(size: 48, weight: .bold))
                    Text(snapshot.identity?.description ?? snapshot.card?.tagline ?? "")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 18) {
                    NativeGlyph(glyph: snapshot.card?.glyph ?? [])
                    VStack(alignment: .leading, spacing: 5) {
                        Text(snapshot.model.displayName).font(.system(size: 22, weight: .semibold))
                        Text(snapshot.card?.tagline ?? "Personal Model")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("model online", systemImage: "circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .overlay(Capsule().stroke(Color.black.opacity(0.1)))
                }
                .padding(24)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.09)))
                Divider()
                HStack(alignment: .top, spacing: 56) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("TODAY · 一句")
                            .font(.system(size: 9, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(.secondary)
                        Text("今天的你").font(.system(size: 26, weight: .medium))
                        Text(snapshot.identity?.dailyLine ?? "")
                            .font(.system(size: 17))
                            .lineSpacing(8)
                    }
                    .frame(maxWidth: 280, alignment: .leading)
                    VStack(alignment: .leading, spacing: 13) {
                        Text("LETTER · THIS WEEK")
                            .font(.system(size: 9, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(.secondary)
                        ForEach(snapshot.identity?.weeklyLetter ?? [], id: \.self) { line in
                            Text(line)
                                .font(.system(size: 15))
                                .padding(.bottom, 11)
                                .overlay(alignment: .bottom) { Divider() }
                        }
                    }
                }
            }
        }
    }
}

private struct NativeRewindView: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot
    @State private var selectedDay: DaySnapshot?
    @State private var graphMode = false

    var body: some View {
        NativePaper(maxWidth: 980) {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    Text("search memories…").foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    Text("时间 · REWIND")
                        .font(.system(size: 26, weight: .bold))
                    Spacer()
                    Picker("Rewind 视图", selection: $graphMode) {
                        Text("Calendar").tag(false)
                        Text("Graph").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
                if graphMode {
                    NativeMemoryGraph(snapshot: snapshot) { reference in
                        Task { await state.loadEvidence(reference) }
                    }
                } else {
                    HStack(alignment: .top, spacing: 28) {
                    VStack(spacing: 0) {
                        ForEach(snapshot.time?.days ?? []) { day in
                            Button {
                                selectedDay = day
                            } label: {
                                HStack(alignment: .top, spacing: 14) {
                                    Text(day.id)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 90, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(day.title ?? day.id)
                                            .font(.system(size: 15, weight: .semibold))
                                        Text(day.portrait ?? "")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Text("\(day.events?.count ?? 0) moments")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.vertical, 16)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    Divider()
                    VStack(alignment: .leading, spacing: 14) {
                        Text("最近回绕的事")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        let day = selectedDay ?? snapshot.time?.days?.first
                        Text(day?.portrait ?? "等待 Personal Model 记录新的时间片段。")
                            .font(.system(size: 14))
                            .lineSpacing(6)
                        ForEach(day?.events ?? []) { event in
                            Button {
                                if let reference = event.evidenceRef {
                                    Task { await state.loadEvidence(reference) }
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                Text("\(event.time ?? "—") · \(event.app ?? "Personal Model")")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(event.title).font(.system(size: 13, weight: .semibold))
                                Text(event.detail ?? "")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                    if event.evidenceRef != nil {
                                        Label("Evidence", systemImage: "checkmark.seal")
                                            .font(.system(size: 9))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, 8)
                        }
                    }
                    .frame(width: 250, alignment: .topLeading)
                    }
                }
            }
        }
    }
}

private struct NativeMemoryGraph: View {
    let snapshot: PersonalModelSnapshot
    let openEvidence: (String) -> Void

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    for index in 0..<(snapshot.personalModel?.faces?.count ?? 0) {
                        let angle = Double(index) / Double(max(1, snapshot.personalModel?.faces?.count ?? 1)) * .pi * 2
                        let point = CGPoint(
                            x: center.x + cos(angle) * min(size.width, size.height) * 0.31,
                            y: center.y + sin(angle) * min(size.width, size.height) * 0.31
                        )
                        var path = Path()
                        path.move(to: center)
                        path.addLine(to: point)
                        context.stroke(path, with: .color(.black.opacity(0.14)), lineWidth: 1)
                    }
                }
                Circle()
                    .fill(Color.black)
                    .frame(width: 90, height: 90)
                    .overlay {
                        Text(snapshot.model.handle)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                ForEach(Array((snapshot.personalModel?.faces ?? []).enumerated()), id: \.element.id) { index, face in
                    let angle = Double(index) / Double(max(1, snapshot.personalModel?.faces?.count ?? 1)) * .pi * 2
                    Button {
                        if let reference = face.evidenceRefs?.first { openEvidence(reference) }
                    } label: {
                        Text(face.text)
                            .font(.system(size: 10.5))
                            .lineLimit(3)
                            .frame(width: 130)
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: proxy.size.width / 2 + cos(angle) * min(proxy.size.width, proxy.size.height) * 0.31,
                        y: proxy.size.height / 2 + sin(angle) * min(proxy.size.width, proxy.size.height) * 0.31
                    )
                }
            }
        }
        .frame(minHeight: 420)
    }
}

private struct NativeConnectorsView: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot

    private var connectors: [ConnectorSnapshot] {
        state.connectors.isEmpty ? (snapshot.connectors ?? []) : state.connectors
    }

    var body: some View {
        NativePaper {
            VStack(alignment: .leading, spacing: 26) {
                Text("CONNECTORS")
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.secondary)
                Text("连接你的 Personal Model")
                    .font(.system(size: 34, weight: .bold))
                Text("每个连接都绑定当前模型与当前授权，不会读取另一位用户的数据。")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                NativeConnectorSwipe(state: state, connectors: connectors)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                    ForEach(connectors) { connector in
                        HStack(spacing: 16) {
                            RoundedRectangle(cornerRadius: 13)
                                .fill(Color.black)
                                .frame(width: 48, height: 48)
                                .overlay {
                                    Text(String(connector.name.prefix(1)))
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundStyle(.white)
                                }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(connector.product ?? connector.name)
                                    .font(.system(size: 16, weight: .semibold))
                                Text(connector.status ?? "available")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if connector.status == "connected" {
                                Label("Connected", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.green)
                            } else {
                                Button(state.connectingConnector == connector.id ? "Connecting…" : "Connect") {
                                    Task { await state.connect(connector.id) }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(
                                    connector.status == "missing" ||
                                    !state.connectingConnector.isEmpty
                                )
                            }
                        }
                        .padding(20)
                        .background(Color.black.opacity(0.018), in: RoundedRectangle(cornerRadius: 18))
                        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.08)))
                    }
                }
            }
        }
    }
}

private struct NativeConnectorSwipe: View {
    @ObservedObject var state: PersonalModelAppState
    let connectors: [ConnectorSnapshot]
    @State private var offset: CGFloat = 0

    private var done: Bool {
        !connectors.isEmpty && connectors.allSatisfy {
            $0.status == "connected" || $0.status == "missing"
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.black.opacity(0.06))
            HStack {
                Spacer()
                Text(done ? "Agents 已连接" : "向右滑动，连接可用 Agents")
                Image(systemName: done ? "checkmark" : "chevron.right.2")
                Spacer()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            Circle()
                .fill(done ? Color.green : Color.black)
                .frame(width: 42, height: 42)
                .overlay {
                    Image(systemName: done ? "checkmark" : "arrow.right")
                        .foregroundStyle(.white)
                }
                .offset(x: offset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            guard !done else { return }
                            offset = min(max(0, value.translation.width), 300)
                        }
                        .onEnded { value in
                            if value.translation.width > 180 {
                                Task { await state.connectAll() }
                            }
                            withAnimation(.spring(response: 0.35)) { offset = 0 }
                        }
                )
        }
        .padding(5)
        .frame(height: 52)
    }
}

private struct NativeReportsView: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot
    @State private var expandedReport: String?

    private var reports: [ReportSnapshot] {
        state.reports.isEmpty ? (snapshot.reports ?? []) : state.reports
    }

    var body: some View {
        NativePaper {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Text("AGENT REPORTS")
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(.secondary)
                    Text("Agents 带回来的理解")
                        .font(.system(size: 34, weight: .bold))
                    ForEach(reports) { report in
                        VStack(alignment: .leading, spacing: 15) {
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    expandedReport = expandedReport == report.id ? nil : report.id
                                }
                            } label: {
                                HStack {
                                    Text(report.title).font(.system(size: 19, weight: .semibold))
                                    Spacer()
                                    Text(report.connectorId?.uppercased() ?? "AGENT")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Image(systemName: expandedReport == report.id ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 10))
                                }
                            }
                            .buttonStyle(.plain)
                            Text(report.summary ?? "")
                                .font(.system(size: 14))
                                .foregroundStyle(.secondary)
                            if expandedReport == report.id {
                                ForEach(report.sections ?? []) { section in
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(section.title).font(.system(size: 13, weight: .semibold))
                                        Text(section.body)
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }
                                    .padding(.top, 8)
                                }
                                HStack {
                                    ForEach(report.evidenceRefs ?? [], id: \.self) { reference in
                                        Button {
                                            Task { await state.loadEvidence(reference) }
                                        } label: {
                                            Label("Evidence", systemImage: "checkmark.seal")
                                        }
                                        .buttonStyle(.borderless)
                                        .font(.system(size: 10))
                                    }
                                }
                            }
                        }
                        .padding(22)
                        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.black.opacity(0.09)))
                    }
                }
            }
        }
    }
}

private struct NativeEvidenceView: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot

    private var evidence: [(String, String)] {
        var rows: [(String, String)] = []
        for face in snapshot.personalModel?.faces ?? [] {
            for reference in face.evidenceRefs ?? [] {
                rows.append((reference, face.text))
            }
        }
        for report in snapshot.reports ?? [] {
            for reference in report.evidenceRefs ?? [] {
                rows.append((reference, report.title))
            }
        }
        return rows
    }

    var body: some View {
        NativePaper {
            VStack(alignment: .leading, spacing: 25) {
                Text("EVIDENCE")
                    .font(.system(size: 9, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.secondary)
                Text("这张 Card 为什么这样理解你")
                    .font(.system(size: 34, weight: .bold))
                Text("Evidence 只显示当前 Personal Model 的引用。切换模型会建立新的会话和授权边界。")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                VStack(spacing: 0) {
                    ForEach(Array(evidence.enumerated()), id: \.offset) { index, row in
                        Button {
                            Task { await state.loadEvidence(row.0) }
                        } label: {
                            HStack(alignment: .top, spacing: 18) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(row.1).font(.system(size: 14, weight: .medium))
                                Text(row.0)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(Color.green)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 15)
                        Divider()
                    }
                }
            }
        }
    }
}

private struct NativeEvidenceDetail: View {
    @ObservedObject var state: PersonalModelAppState
    let evidence: EvidenceSnapshot

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture { state.closeEvidence() }
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("EVIDENCE", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    Spacer()
                    Button {
                        state.closeEvidence()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
                Text(evidence.reference)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                ScrollView {
                    Text(evidence.content.readableText)
                        .font(.system(size: 14))
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                HStack {
                    Text("Model · \(evidence.modelId)")
                    Spacer()
                    Text(evidence.capturedAt ?? "由 Personal Model 验证")
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
            }
            .padding(28)
            .frame(width: 560, height: 430)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.3), radius: 44, y: 24)
        }
    }
}

private struct NativeSetupView: View {
    @ObservedObject var state: PersonalModelAppState
    @State private var displayName = ""
    @State private var handle = ""

    var body: some View {
        VStack(spacing: 22) {
            NativeGlyph(glyph: Array(repeating: true, count: 25))
            Text(setupTitle).font(.system(size: 28, weight: .bold))
            Text(setupDetail)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            if state.setupState == "profile_required" {
                VStack(spacing: 12) {
                    TextField("你的名字", text: $displayName)
                    TextField("@handle", text: $handle)
                    Button("创建我的 Personal Card") {
                        Task { await state.saveProfile(displayName: displayName, handle: handle) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .textFieldStyle(.roundedBorder)
                .frame(width: 340)
            } else if state.setupState == "not_installed" || state.setupState == "onboarding_required" {
                Button("打开 Personal Model 设置") {
                    Task { await state.launchPersonalModelSetup() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                ProgressView().controlSize(.large)
            }
        }
        .padding(52)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.75)))
        .shadow(color: .black.opacity(0.16), radius: 30, y: 18)
    }

    private var setupTitle: String {
        switch state.setupState {
        case "profile_required": return "创建你的 Personal Card"
        case "not_installed": return "初始化 Personal Model"
        case "onboarding_required": return "完成本机权限设置"
        default: return "正在连接你的 Personal Model"
        }
    }

    private var setupDetail: String {
        switch state.setupState {
        case "profile_required": return "这张 Card 只属于当前 Mac 用户。名字可以稍后修改，模型数据不会与其他用户混用。"
        case "not_installed": return "Who Am I 会在本机安装固定版本的 Personal Model 后端。"
        case "onboarding_required": return "请允许 Accessibility 与 Screen Recording，让模型开始形成属于你的记忆。"
        default: return "Personal Model 和 Card 数据只保存在这台 Mac。"
        }
    }
}

private struct NativePaper<Content: View>: View {
    let maxWidth: CGFloat
    @ViewBuilder let content: Content

    init(maxWidth: CGFloat = 1120, @ViewBuilder content: () -> Content) {
        self.maxWidth = maxWidth
        self.content = content()
    }

    var body: some View {
        content
            .padding(38)
            .frame(maxWidth: maxWidth, maxHeight: 760, alignment: .topLeading)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.22), radius: 34, y: 22)
            .padding(42)
    }
}

private struct NativeGlyph: View {
    let glyph: [Bool]

    private var normalized: [Bool] {
        glyph.count == 25 ? glyph : Array(repeating: true, count: 25)
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(6), spacing: 3), count: 5), spacing: 3) {
            ForEach(Array(normalized.enumerated()), id: \.offset) { _, isOn in
                RoundedRectangle(cornerRadius: 1)
                    .fill(isOn ? Color.white : Color.white.opacity(0.18))
                    .frame(width: 6, height: 6)
            }
        }
        .padding(14)
        .frame(width: 72, height: 72)
        .background(Color(red: 0.11, green: 0.11, blue: 0.13), in: RoundedRectangle(cornerRadius: 17))
    }
}

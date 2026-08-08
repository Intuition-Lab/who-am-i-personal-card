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

enum NativeRequestPhase: Equatable {
    case idle
    case loading
    case success
    case empty
    case insufficient
    case failure
}

private enum NativeTruthKind {
    case recorded
    case inference
    case generated
    case suggestion

    var label: String {
        switch self {
        case .recorded: return "记录事实"
        case .inference: return "Personal Model 推断"
        case .generated: return "生成内容"
        case .suggestion: return "延续建议"
        }
    }

    var symbol: String {
        switch self {
        case .recorded: return "checkmark.seal"
        case .inference: return "brain.head.profile"
        case .generated: return "text.badge.sparkles"
        case .suggestion: return "arrow.right.circle"
        }
    }

    var color: Color {
        switch self {
        case .recorded: return .green
        case .inference: return .blue
        case .generated: return .purple
        case .suggestion: return .orange
        }
    }

    static func resolve(_ rawValue: String?, fallback: NativeTruthKind) -> NativeTruthKind {
        switch rawValue?.lowercased() {
        case "record", "recorded", "recorded_fact", "fact", "evidence": return .recorded
        case "inference", "inferred", "model_inference", "face": return .inference
        case "generated", "generation", "summary", "report": return .generated
        case "suggestion", "continuation", "future": return .suggestion
        default: return fallback
        }
    }
}

private struct NativeTruthMetadata {
    let kind: NativeTruthKind
    let source: String?
    let timeRange: String?
    let confidence: Double?

    var detail: String {
        var values: [String] = []
        if let source = source?.trimmedNonEmpty { values.append("来源：\(source)") }
        if let timeRange = timeRange?.trimmedNonEmpty { values.append(timeRange) }
        if let confidence, confidence.isFinite {
            let percentage = Int((min(1, max(0, confidence)) * 100).rounded())
            values.append("置信度 \(percentage)%")
        }
        return values.joined(separator: " · ")
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private func compactDateLabel(_ value: String?) -> String? {
    guard let value = value?.trimmedNonEmpty else { return nil }
    let parser = ISO8601DateFormatter()
    guard let date = parser.date(from: value) else { return value }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
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
    let isPublished: Bool?
    let publicationStatus: String?

    var isConfirmedPublished: Bool {
        if isPublished == true { return true }
        return ["published", "public", "live"].contains(publicationStatus?.lowercased() ?? "")
    }
}

struct PersonalModelSummary: Decodable {
    let memoryCount: Int?
    let root: String?
    let updatedAt: String?
    let faces: [FaceSnapshot]?
    let source: String?
    let timeRange: String?
}

struct FaceSnapshot: Decodable, Identifiable {
    let id: String
    let text: String
    let observations: Int?
    let confidence: Double?
    let evidenceRefs: [String]?
    let source: String?
    let timeRange: String?
    let contentType: String?
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
    let source: String?
    let timeRange: String?
    let confidence: Double?
    let contentType: String?
    let evidenceRef: String?
    let evidenceRefs: [String]?

    var allEvidenceRefs: [String] {
        var references = evidenceRefs ?? []
        if let evidenceRef, !references.contains(evidenceRef) { references.append(evidenceRef) }
        return references
    }

    var isFutureLike: Bool {
        let combined = "\(kind) \(title) \(when ?? "")".lowercased()
        return kind.lowercased() == "future" || combined.contains("明天") || combined.contains("tomorrow")
    }

    var hasReliableSuggestionSource: Bool {
        !allEvidenceRefs.isEmpty || (source?.trimmedNonEmpty != nil && timeRange?.trimmedNonEmpty != nil)
    }

    var displayTitle: String {
        guard isFutureLike else { return title }
        return title
            .replacingOccurrences(of: "明天", with: "接下来")
            .replacingOccurrences(
                of: #"(?<!\d)\d{1,2}(?::\d{2})?(?:\s*[AP]M)?\s*[·:：-]?\s*"#,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmedNonEmpty ?? "基于近期活动的延续建议"
    }
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
    let source: String?
    let timeRange: String?
}

struct EventSnapshot: Decodable, Identifiable {
    let id: String
    let time: String?
    let title: String
    let detail: String?
    let app: String?
    let evidenceRef: String?
    let source: String?
    let timeRange: String?
    let confidence: Double?
    let contentType: String?
}

struct IdentitySnapshot: Decodable {
    let description: String?
    let dailyLine: String?
    let weeklyLetter: [String]?
    let source: String?
    let timeRange: String?
    let confidence: Double?
    let contentType: String?
    let evidenceRefs: [String]?
}

struct ConnectorSnapshot: Decodable, Identifiable {
    let id: String
    let name: String
    let product: String?
    let status: String?
    let sessionId: String?
    let installed: Bool?
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
    let source: String?
    let timeRange: String?
    let confidence: Double?
    let contentType: String?

    var hasSubstantiveData: Bool {
        if !(evidenceRefs ?? []).isEmpty || (evidenceCount ?? 0) > 0 { return true }
        return (sections ?? []).contains { section in
            guard let body = section.body.trimmedNonEmpty else { return false }
            let normalized = body.lowercased()
            return !normalized.contains("connected to")
                && normalized != "connector activity recorded."
        }
    }
}

struct ReportSection: Decodable, Identifiable {
    let kind: String?
    let title: String
    let body: String

    var id: String { "\(kind ?? "section"):\(title)" }
}

struct SearchResponse: Decodable {
    let results: [SearchResult]?
    let sufficientEvidence: Bool?
    let evidenceRefs: [String]?
    let source: String?
    let timeRange: String?
}

struct SearchResult: Decodable, Identifiable {
    let id: String?
    let title: String?
    let text: String?
    let score: Double?
    let kind: String?
    let source: String?
    let timeRange: String?
    let capturedAt: String?
    let confidence: Double?
    let contentType: String?
    let evidenceRef: String?
    let evidenceRefs: [String]?

    var stableID: String { id ?? "\(title ?? ""):\(text ?? "")" }

    var allEvidenceRefs: [String] {
        var references = evidenceRefs ?? []
        if let evidenceRef, !references.contains(evidenceRef) { references.append(evidenceRef) }
        return references
    }
}

struct AskResponse: Decodable {
    let answer: String
    let results: [SearchResult]?
    let evidence: [SearchResult]?
    let evidenceRefs: [String]?
    let sufficientEvidence: Bool?
    let source: String?
    let timeRange: String?
    let confidence: Double?

    var supportingResults: [SearchResult] {
        var seen = Set<String>()
        return ((results ?? []) + (evidence ?? [])).filter { seen.insert($0.stableID).inserted }
    }

    var allEvidenceRefs: [String] {
        var seen = Set<String>()
        return ((evidenceRefs ?? []) + supportingResults.flatMap(\.allEvidenceRefs))
            .filter { seen.insert($0).inserted }
    }
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
    let source: String?
    let timeRange: String?
    let expiresAt: String?
    let status: String?
    let valid: Bool?

    var isAvailable: Bool {
        if valid == false { return false }
        if ["expired", "invalid", "revoked", "stale"].contains(status?.lowercased() ?? "") {
            return false
        }
        if let expiresAt, let expiry = ISO8601DateFormatter().date(from: expiresAt), expiry <= Date() {
            return false
        }
        return true
    }
}

private extension FaceSnapshot {
    func truthMetadata(updatedAt: String?) -> NativeTruthMetadata {
        let observationLabel = observations.map { "Personal Model · \($0) 条记录" }
        return NativeTruthMetadata(
            kind: NativeTruthKind.resolve(contentType, fallback: .inference),
            source: source ?? observationLabel ?? "Personal Model",
            timeRange: timeRange ?? compactDateLabel(updatedAt).map { "截至 \($0)" },
            confidence: confidence
        )
    }
}

private extension NowItem {
    var truthMetadata: NativeTruthMetadata {
        let fallback: NativeTruthKind = isFutureLike
            ? .suggestion
            : allEvidenceRefs.isEmpty ? .inference : .recorded
        return NativeTruthMetadata(
            kind: NativeTruthKind.resolve(contentType, fallback: fallback),
            source: source ?? (allEvidenceRefs.isEmpty ? "Personal Model" : "近期活动记录"),
            timeRange: timeRange ?? (isFutureLike ? "基于近期活动" : dayId),
            confidence: confidence
        )
    }
}

private extension EventSnapshot {
    func truthMetadata(day: DaySnapshot?) -> NativeTruthMetadata {
        let fallback: NativeTruthKind = evidenceRef == nil ? .inference : .recorded
        return NativeTruthMetadata(
            kind: NativeTruthKind.resolve(contentType, fallback: fallback),
            source: source ?? app ?? (evidenceRef == nil ? "Personal Model" : "活动记录"),
            timeRange: timeRange ?? day?.timeRange ?? day?.id,
            confidence: confidence
        )
    }
}

private extension SearchResult {
    var truthMetadata: NativeTruthMetadata {
        let normalizedKind = kind?.lowercased() ?? ""
        let fallback: NativeTruthKind
        if normalizedKind == "event" && !allEvidenceRefs.isEmpty {
            fallback = .recorded
        } else if normalizedKind == "report" {
            fallback = .generated
        } else if normalizedKind == "future" {
            fallback = .suggestion
        } else {
            fallback = .inference
        }
        return NativeTruthMetadata(
            kind: NativeTruthKind.resolve(contentType, fallback: fallback),
            source: source ?? (allEvidenceRefs.isEmpty ? "Personal Model" : "模型记录"),
            timeRange: timeRange ?? compactDateLabel(capturedAt),
            confidence: confidence
        )
    }
}

private extension IdentitySnapshot {
    var truthMetadata: NativeTruthMetadata {
        NativeTruthMetadata(
            kind: NativeTruthKind.resolve(contentType, fallback: .generated),
            source: source ?? "Personal Model",
            timeRange: timeRange ?? "基于近期记录",
            confidence: confidence
        )
    }
}

private extension ReportSnapshot {
    var truthMetadata: NativeTruthMetadata {
        NativeTruthMetadata(
            kind: NativeTruthKind.resolve(contentType, fallback: .generated),
            source: source ?? connectorId ?? "Connector",
            timeRange: timeRange ?? compactDateLabel(updatedAt),
            confidence: confidence
        )
    }
}

private extension AskResponse {
    var truthMetadata: NativeTruthMetadata {
        NativeTruthMetadata(
            kind: .generated,
            source: source ?? "Personal Model",
            timeRange: timeRange ?? "基于当前检索结果",
            confidence: confidence
        )
    }
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
    let code: String?
}

private enum NativeAPIError: LocalizedError {
    case invalidResponse
    case server(status: Int, code: String?, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Personal Model 返回了无法识别的数据。"
        case .server(_, _, let message):
            return message
        }
    }

    var statusCode: Int? {
        if case .server(let status, _, _) = self { return status }
        return nil
    }

    var code: String? {
        if case .server(_, let code, _) = self { return code }
        return nil
    }
}

@MainActor
final class PersonalModelAppState: ObservableObject {
    @Published var selectedSection: WhoAmISection = .card
    @Published private(set) var snapshot: PersonalModelSnapshot?
    @Published private(set) var setupState = "loading"
    @Published private(set) var setupErrorMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published var searchQuery = ""
    @Published private(set) var searchResults: [SearchResult] = []
    @Published private(set) var searchPhase: NativeRequestPhase = .idle
    @Published private(set) var searchErrorMessage: String?
    @Published var question = ""
    @Published private(set) var answer = ""
    @Published private(set) var askResponse: AskResponse?
    @Published private(set) var askPhase: NativeRequestPhase = .idle
    @Published private(set) var askErrorMessage: String?
    @Published private(set) var connectors: [ConnectorSnapshot] = []
    @Published private(set) var connectorErrorMessage: String?
    @Published private(set) var reports: [ReportSnapshot] = []
    @Published private(set) var selectedEvidence: EvidenceSnapshot?
    @Published private(set) var selectedEvidenceReference = ""
    @Published private(set) var evidencePhase: NativeRequestPhase = .idle
    @Published private(set) var evidenceErrorMessage: String?
    @Published private(set) var connectingConnector = ""
    @Published private(set) var correctionPhase: NativeRequestPhase = .idle
    @Published private(set) var correctionMessage: String?
    @Published var isAskOpen = false

    private let baseURL: URL
    private let session: URLSession
    private var personalModelStatus: PersonalModelStatus?

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
            case "unauthorized": return "未授权"
            case "backend_unavailable": return "本机服务未启动"
            case "model_forming": return "正在形成模型"
            default: return "正在连接"
            }
        }
        if authorizationLimited { return "\(snapshot.model.displayName) · 未授权" }
        if isModelForming { return "\(snapshot.model.displayName) · 正在形成模型" }
        return "\(snapshot.model.displayName) · 已连接"
    }

    var isModelForming: Bool {
        let buildStatus = personalModelStatus?.buildStatus?.lowercased() ?? ""
        let building = ["not_built", "building", "forming", "empty"].contains(buildStatus)
        return building || (snapshot?.personalModel?.memoryCount ?? 0) == 0
    }

    var authorizationLimited: Bool {
        guard let authorization = snapshot?.authorization else {
            return setupState == "unauthorized"
        }
        let mode = authorization.viewerMode?.lowercased() ?? ""
        return ["unauthorized", "denied", "none"].contains(mode)
            || authorization.scopes?.isEmpty == true
    }

    var isCorrecting: Bool { correctionPhase == .loading }

    var substantiveReports: [ReportSnapshot] {
        reports.filter(\.hasSubstantiveData)
    }

    var hasEvidencePresentation: Bool {
        evidencePhase == .loading || evidencePhase == .failure || selectedEvidence != nil
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        setupErrorMessage = nil
        defer { isLoading = false }
        do {
            let setup: SetupResponse = try await request(path: "api/setup/status")
            setupState = setup.state
            personalModelStatus = setup.personalModel
            guard setup.ready else { return }
            let bootstrap: BootstrapResponse = try await request(path: "api/model/bootstrap")
            snapshot = bootstrap.snapshot
            connectors = bootstrap.snapshot.connectors ?? []
            reports = bootstrap.snapshot.reports ?? []
            setupState = "ready"
        } catch {
            if snapshot == nil {
                setupState = setupState(for: error)
                setupErrorMessage = error.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
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
        let query = searchQuery.trimmedNonEmpty ?? ""
        guard !query.isEmpty else {
            searchResults = []
            searchPhase = .idle
            searchErrorMessage = nil
            return
        }
        searchResults = []
        searchPhase = .loading
        searchErrorMessage = nil
        do {
            let response: SearchResponse = try await request(
                path: "api/model/search",
                method: "POST",
                json: ["query": query]
            )
            searchResults = response.results ?? []
            if searchResults.isEmpty {
                searchPhase = .empty
            } else if response.sufficientEvidence == false
                        || !searchResults.contains(where: { !$0.allEvidenceRefs.isEmpty }) {
                searchPhase = .insufficient
            } else {
                searchPhase = .success
            }
        } catch {
            searchPhase = .failure
            searchErrorMessage = error.localizedDescription
        }
    }

    func ask() async {
        let value = question.trimmedNonEmpty ?? ""
        guard !value.isEmpty else { return }
        answer = ""
        askResponse = nil
        askPhase = .loading
        askErrorMessage = nil
        do {
            let response: AskResponse = try await request(
                path: "api/model/ask",
                method: "POST",
                json: ["question": value]
            )
            askResponse = response
            answer = response.answer
            if response.sufficientEvidence == false || response.allEvidenceRefs.isEmpty {
                askPhase = .insufficient
            } else {
                askPhase = .success
            }
        } catch {
            askPhase = .failure
            askErrorMessage = error.localizedDescription
        }
    }

    func connect(_ connectorId: String) async {
        guard connectingConnector.isEmpty else { return }
        connectingConnector = connectorId
        connectorErrorMessage = nil
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
            connectorErrorMessage = error.localizedDescription
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
        selectedEvidence = nil
        selectedEvidenceReference = reference
        evidencePhase = .loading
        evidenceErrorMessage = nil
        do {
            let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
            let encoded = reference.addingPercentEncoding(withAllowedCharacters: allowed) ?? reference
            let response: EvidenceEnvelope = try await request(
                path: "api/model/evidence/\(encoded)"
            )
            guard response.evidence.isAvailable else {
                evidencePhase = .failure
                evidenceErrorMessage = "这条 Evidence 已失效，不能再作为当前结论的依据。"
                return
            }
            selectedEvidence = response.evidence
            evidencePhase = .success
        } catch {
            evidencePhase = .failure
            if let apiError = error as? NativeAPIError,
               apiError.statusCode == 404 || apiError.statusCode == 410 {
                evidenceErrorMessage = "这条 Evidence 已失效或不再属于当前模型。"
            } else {
                evidenceErrorMessage = error.localizedDescription
            }
        }
    }

    func closeEvidence() {
        selectedEvidence = nil
        selectedEvidenceReference = ""
        evidencePhase = .idle
        evidenceErrorMessage = nil
    }

    func correct(_ correction: String) async {
        let value = correction.trimmedNonEmpty ?? ""
        guard !value.isEmpty else { return }
        correctionPhase = .loading
        correctionMessage = nil
        do {
            let _: OperationResponse = try await request(
                path: "api/model/correct",
                method: "POST",
                json: ["correction": value]
            )
            correctionPhase = .success
            correctionMessage = "更正已写入。Personal Model 会以你的说明为准。"
            await load()
        } catch {
            correctionPhase = .failure
            correctionMessage = "未能保存更正：\(error.localizedDescription)"
        }
    }

    func resetCorrectionStatus() {
        guard correctionPhase != .loading else { return }
        correctionPhase = .idle
        correctionMessage = nil
    }

    func copyCard() {
        guard let snapshot else { return }
        var lines = [
            snapshot.model.displayName,
            snapshot.model.handle,
            snapshot.card?.tagline ?? "Personal Model",
        ]
        if snapshot.card?.isConfirmedPublished == true,
           let publicURL = snapshot.card?.publicUrl?.trimmedNonEmpty {
            lines.append(publicURL)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
    }

    func dismissError() {
        errorMessage = nil
    }

    private func setupState(for error: Error) -> String {
        guard let apiError = error as? NativeAPIError else { return "backend_unavailable" }
        if apiError.statusCode == 401 || apiError.statusCode == 403
            || ["SCOPE_DENIED", "UNAUTHORIZED", "AUTHORIZATION_REQUIRED"].contains(apiError.code ?? "") {
            return "unauthorized"
        }
        return "backend_unavailable"
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
            throw NativeAPIError.server(
                status: http.statusCode,
                code: apiError?.code,
                message: apiError?.error ?? "Personal Model 暂时不可用。"
            )
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
                        VStack(spacing: 0) {
                            if state.authorizationLimited {
                                NativeStatusBanner(
                                    symbol: "lock.trianglebadge.exclamationmark",
                                    title: "尚未授权读取 Personal Model",
                                    detail: "当前内容可能不完整。请在 Personal Model 设置中恢复授权后刷新。",
                                    tint: .orange
                                )
                            } else if state.isModelForming {
                                NativeStatusBanner(
                                    symbol: "circle.dotted",
                                    title: "Personal Model 正在形成",
                                    detail: "已有界面可以使用；推断、报告和建议会在积累到可靠记录后出现。",
                                    tint: .blue
                                )
                            }
                            NativeSectionContent(state: state, snapshot: snapshot)
                        }
                    } else {
                        NativeSetupView(state: state)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if state.hasEvidencePresentation {
                NativeEvidencePresentation(state: state)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .accessibilityElement(children: .contain)
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

private struct NativeStatusBanner: View {
    let symbol: String
    let title: String
    let detail: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(tint.opacity(0.08))
        .accessibilityElement(children: .combine)
    }
}

private struct NativeTruthBadge: View {
    let metadata: NativeTruthMetadata

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 7) { contents }
            VStack(alignment: .leading, spacing: 3) { contents }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var contents: some View {
        Label(metadata.kind.label, systemImage: metadata.kind.symbol)
            .foregroundStyle(metadata.kind.color)
        if !metadata.detail.isEmpty {
            Text(metadata.detail)
        }
    }
}

private struct NativeInlineState: View {
    let symbol: String
    let title: String
    let detail: String
    var tint: Color = .secondary

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(width: 26)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}

private struct NativeTopBar: View {
    @ObservedObject var state: PersonalModelAppState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "asterisk")
                .font(.caption.weight(.medium))
            Text("Who Am I")
                .font(.caption.weight(.semibold))
            Spacer()
            Circle()
                .fill(
                    state.snapshot == nil || state.authorizationLimited
                        ? Color.orange
                        : state.isModelForming ? Color.blue : Color.green
                )
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(state.modelStatusLabel)
                .font(.caption)
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
                    .font(.caption)
                    .frame(width: 24, height: 20)
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("切换页面与刷新")
            Text("as of now")
                .font(.caption2.monospaced())
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

    private var cardLocator: String {
        if snapshot.card?.isConfirmedPublished == true,
           let publicURL = snapshot.card?.publicUrl?.trimmedNonEmpty {
            return "PUBLISHED\n\(publicURL)"
        }
        return "LOCAL CARD\n\(snapshot.model.id)"
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
        .accessibilityHint("按空格、点击或横向滑动翻转 Card")
    }

    private var front: some View {
        Button {
            flipped = true
        } label: {
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
                    Text(cardLocator)
                        .multilineTextAlignment(.trailing)
                }
                .font(.system(size: 8.5, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(.white.opacity(0.48))
            }
            .padding(28)
            .contentShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
        }
        .buttonStyle(.plain)
        .simultaneousGesture(cardGesture)
        .accessibilityLabel("翻转 \(snapshot.model.displayName) 的 Card")
        .accessibilityHint("显示模型依据、更正与复制操作")
    }

    private var back: some View {
        VStack(alignment: .leading, spacing: 9) {
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
                .accessibilityLabel("翻回 Card 正面")
            }
            .font(.system(size: 8.5, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(.white.opacity(0.45))
            Text(snapshot.personalModel?.root ?? snapshot.card?.tagline ?? "Personal Model")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(3)
            if let face = snapshot.personalModel?.faces?.first {
                VStack(alignment: .leading, spacing: 4) {
                    let metadata = face.truthMetadata(updatedAt: snapshot.personalModel?.updatedAt)
                    Text(face.text)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.76))
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(metadata.kind.label)
                        if !metadata.detail.isEmpty { Text(metadata.detail).lineLimit(1) }
                        if let reference = face.evidenceRefs?.first {
                            Button {
                                Task { await state.loadEvidence(reference) }
                            } label: {
                                Label("Evidence", systemImage: "checkmark.seal")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("打开这条推断的 Evidence")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer(minLength: 0)
            if let message = state.correctionMessage {
                Label(
                    message,
                    systemImage: state.correctionPhase == .success
                        ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(.caption2)
                .foregroundStyle(state.correctionPhase == .success ? .green : .orange)
                .lineLimit(2)
                .accessibilityLabel(message)
            }
            HStack(spacing: 8) {
                TextField("告诉 Personal Model 哪里不准确…", text: $correction)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    .onSubmit { Task { await state.correct(correction) } }
                    .onChange(of: correction) { _ in state.resetCorrectionStatus() }
                    .accessibilityLabel("更正 Personal Model")
                Button(state.isCorrecting ? "写入中" : "Correct") {
                    Task { await state.correct(correction) }
                }
                .disabled(correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isCorrecting)
                .accessibilityLabel(state.isCorrecting ? "正在保存更正" : "保存更正")
                Button(copied ? "已复制" : "复制卡片") {
                    state.copyCard()
                    copied = true
                }
                .accessibilityHint("复制 Card 文本；未确认公开发布时不会包含公开链接")
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.78))
        }
        .padding(26)
    }

    private var cardGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { drag = $0.translation }
            .onEnded { value in
                if abs(value.translation.width) > 90 {
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
    @FocusState private var askFocused: Bool

    private var visibleNowItems: [NowItem] {
        (snapshot.now?.items ?? []).filter { item in
            !item.isFutureLike || item.hasReliableSuggestionSource
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search memories…", text: $state.searchQuery)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { Task { await state.search() } }
                    .accessibilityLabel("搜索 Personal Model 记忆")
                if state.searchPhase == .loading {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("正在搜索")
                }
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
                    askFocused = state.isAskOpen
                } label: {
                    Label("Ask", systemImage: "sparkles")
                }
                .buttonStyle(.plain)
                .font(.callout.weight(.medium))
                Divider().frame(height: 26)
                Button("Rewind") { state.selectedSection = .rewind }
                    .buttonStyle(.plain)
                    .font(.callout.weight(.medium))
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
                            .focused($askFocused)
                            .onSubmit { Task { await state.ask() } }
                            .accessibilityLabel("向 Personal Model 提问")
                        if state.askPhase == .loading {
                            ProgressView().controlSize(.small)
                                .accessibilityLabel("正在查找依据并生成回答")
                        }
                        Button(state.askPhase == .loading ? "回答中…" : "Ask") {
                            Task { await state.ask() }
                        }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .keyboardShortcut(.return, modifiers: [.command])
                            .disabled(
                                state.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || state.askPhase == .loading
                            )
                    }
                    switch state.askPhase {
                    case .loading:
                        NativeInlineState(
                            symbol: "sparkles",
                            title: "正在查找依据",
                            detail: "回答会把直接记录、模型推断与生成文字分开显示。",
                            tint: .blue
                        )
                    case .failure:
                        VStack(alignment: .leading, spacing: 8) {
                            NativeInlineState(
                                symbol: "exclamationmark.triangle",
                                title: "这次没有回答成功",
                                detail: state.askErrorMessage ?? "Personal Model 暂时不可用。",
                                tint: .orange
                            )
                            Button("重试 Ask") { Task { await state.ask() } }
                                .buttonStyle(.bordered)
                        }
                    case .success, .insufficient:
                        if let response = state.askResponse {
                            NativeAskAnswer(
                                state: state,
                                response: response,
                                isEvidenceInsufficient: state.askPhase == .insufficient
                            )
                        }
                    case .idle, .empty:
                        EmptyView()
                    }
                }
                .padding(16)
                .background(Color.accentColor.opacity(0.05))
                Divider()
            }

            switch state.searchPhase {
            case .idle:
                if visibleNowItems.isEmpty {
                    NativeInlineState(
                        symbol: "circle.dotted",
                        title: "Personal Model 正在形成",
                        detail: "有可靠的近期活动后，这里会显示记录和有来源的延续建议。",
                        tint: .blue
                    )
                } else {
                    ForEach(visibleNowItems) { item in
                        NativeNowRow(item: item) { reference in
                            Task { await state.loadEvidence(reference) }
                        }
                        Divider().padding(.leading, 20)
                    }
                }
            case .loading:
                NativeInlineState(
                    symbol: "magnifyingglass",
                    title: "正在搜索记忆",
                    detail: "只会显示当前模型与当前授权范围内的内容。",
                    tint: .blue
                )
            case .empty:
                NativeInlineState(
                    symbol: "magnifyingglass",
                    title: "没有找到相关内容",
                    detail: "换一个更具体的词，或使用 Ask 让 Personal Model 查找相近记录。"
                )
            case .failure:
                VStack(alignment: .leading, spacing: 8) {
                    NativeInlineState(
                        symbol: "exclamationmark.triangle",
                        title: "搜索暂时不可用",
                        detail: state.searchErrorMessage ?? "请稍后重试。",
                        tint: .orange
                    )
                    Button("重试搜索") { Task { await state.search() } }
                        .buttonStyle(.bordered)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            case .insufficient:
                NativeInlineState(
                    symbol: "questionmark.diamond",
                    title: "相关，但 Evidence 不足",
                    detail: "以下内容可能是模型推断或生成内容，不能当作已记录事实。",
                    tint: .orange
                )
                ForEach(state.searchResults, id: \.stableID) { result in
                    NativeSearchResultRow(state: state, result: result)
                    Divider().padding(.leading, 20)
                }
            case .success:
                ForEach(state.searchResults, id: \.stableID) { result in
                    NativeSearchResultRow(state: state, result: result)
                    Divider().padding(.leading, 20)
                }
            }

            HStack {
                Text("不是待办，只是时间留下的线索")
                Spacer()
                Text("\(snapshot.personalModel?.memoryCount ?? 0) memories")
            }
            .font(.caption)
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

private struct NativeAskAnswer: View {
    @ObservedObject var state: PersonalModelAppState
    let response: AskResponse
    let isEvidenceInsufficient: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isEvidenceInsufficient {
                NativeInlineState(
                    symbol: "questionmark.diamond",
                    title: "Evidence 不足",
                    detail: "这段回答可作为探索线索，不能当作已经记录的事实。",
                    tint: .orange
                )
            }
            Text(response.answer)
                .font(.body)
                .foregroundStyle(.primary)
                .lineSpacing(4)
                .textSelection(.enabled)
            NativeTruthBadge(metadata: response.truthMetadata)
            ForEach(response.supportingResults, id: \.stableID) { result in
                NativeSearchResultRow(state: state, result: result, compact: true)
            }
            let detachedReferences = response.allEvidenceRefs.filter { reference in
                !response.supportingResults.flatMap(\.allEvidenceRefs).contains(reference)
            }
            if !detachedReferences.isEmpty {
                HStack(spacing: 8) {
                    ForEach(detachedReferences, id: \.self) { reference in
                        Button {
                            Task { await state.loadEvidence(reference) }
                        } label: {
                            Label("Evidence", systemImage: "checkmark.seal")
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("打开回答 Evidence \(reference)")
                    }
                }
            }
        }
    }
}

private struct NativeSearchResultRow: View {
    @ObservedObject var state: PersonalModelAppState
    let result: SearchResult
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(result.title ?? "Memory")
                .font(.headline)
            if let text = result.text?.trimmedNonEmpty {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 2 : 4)
                    .textSelection(.enabled)
            }
            NativeTruthBadge(metadata: result.truthMetadata)
            if !result.allEvidenceRefs.isEmpty {
                HStack(spacing: 8) {
                    ForEach(result.allEvidenceRefs, id: \.self) { reference in
                        Button {
                            Task { await state.loadEvidence(reference) }
                        } label: {
                            Label("Evidence", systemImage: "checkmark.seal")
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .accessibilityLabel("打开 \(result.title ?? "搜索结果") 的 Evidence")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 12 : 16)
        .background(compact ? Color.black.opacity(0.025) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
    }
}

private struct NativeNowRow: View {
    let item: NowItem
    let openEvidence: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: item.isFutureLike ? "arrow.right.circle" : "record.circle")
                .frame(width: 28, height: 28)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
            Text(item.isFutureLike ? "SUGGEST" : item.kind.uppercased())
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.displayTitle).font(.headline)
                if let why = item.why?.trimmedNonEmpty {
                    Text(why)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                NativeTruthBadge(metadata: item.truthMetadata)
                if let reference = item.allEvidenceRefs.first {
                    Button {
                        openEvidence(reference)
                    } label: {
                        Label("Evidence", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            Spacer()
            if !item.isFutureLike, let when = item.when?.trimmedNonEmpty {
                Text(when)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(minHeight: 64)
        .accessibilityElement(children: .contain)
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
                    Text("由 Personal Model 生成 · as of now")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 20) {
                    Text("IDENTITY")
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(.secondary)
                    Text(snapshot.model.displayName)
                        .font(.largeTitle.bold())
                    if let description = snapshot.identity?.description?.trimmedNonEmpty {
                        Text(description)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Personal Model 还没有形成可展示的身份描述。")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    NativeTruthBadge(
                        metadata: snapshot.identity?.truthMetadata
                            ?? NativeTruthMetadata(
                                kind: .generated,
                                source: "Personal Model",
                                timeRange: "尚未产生",
                                confidence: nil
                            )
                    )
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
                        if let dailyLine = snapshot.identity?.dailyLine?.trimmedNonEmpty {
                            Text(dailyLine)
                                .font(.body)
                                .lineSpacing(8)
                            NativeTruthBadge(
                                metadata: snapshot.identity?.truthMetadata
                                    ?? NativeTruthMetadata(
                                        kind: .generated,
                                        source: "Personal Model",
                                        timeRange: "基于近期记录",
                                        confidence: nil
                                    )
                            )
                        } else {
                            Text("正在形成，积累到足够记录后出现。")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: 280, alignment: .leading)
                    VStack(alignment: .leading, spacing: 13) {
                        Text("LETTER · THIS WEEK")
                            .font(.system(size: 9, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(.secondary)
                        if (snapshot.identity?.weeklyLetter ?? []).isEmpty {
                            Text("本周尚未产生可靠的回顾。")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(snapshot.identity?.weeklyLetter ?? [], id: \.self) { line in
                                Text(line)
                                    .font(.body)
                                    .padding(.bottom, 11)
                                    .overlay(alignment: .bottom) { Divider() }
                            }
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
                    TextField("search memories…", text: $state.searchQuery)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            state.selectedSection = .card
                            Task { await state.search() }
                        }
                        .accessibilityLabel("搜索 Rewind 记忆")
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
                    if (snapshot.personalModel?.faces ?? []).isEmpty {
                        NativeInlineState(
                            symbol: "circle.dotted",
                            title: "关系图正在形成",
                            detail: "出现带来源的 Personal Model 推断后，这里会展示它们与记录的关系。",
                            tint: .blue
                        )
                    } else {
                        NativeMemoryGraph(snapshot: snapshot) { reference in
                            Task { await state.loadEvidence(reference) }
                        }
                    }
                } else {
                    HStack(alignment: .top, spacing: 28) {
                    VStack(spacing: 0) {
                        if (snapshot.time?.days ?? []).isEmpty {
                            NativeInlineState(
                                symbol: "clock.arrow.circlepath",
                                title: "还没有可回绕的记录",
                                detail: "第一次使用后，可靠的活动记录会按天出现在这里。"
                            )
                        } else {
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
                    }
                    .frame(maxWidth: .infinity)
                    Divider()
                    VStack(alignment: .leading, spacing: 14) {
                        Text("最近回绕的事")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                        let day = selectedDay ?? snapshot.time?.days?.first
                        Text(day?.portrait ?? "等待 Personal Model 记录新的时间片段。")
                            .font(.body)
                            .lineSpacing(6)
                        if day?.portrait?.trimmedNonEmpty != nil {
                            NativeTruthBadge(
                                metadata: NativeTruthMetadata(
                                    kind: .generated,
                                    source: day?.source ?? "Personal Model",
                                    timeRange: day?.timeRange ?? day?.id,
                                    confidence: nil
                                )
                            )
                        }
                        ForEach(day?.events ?? []) { event in
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(event.time ?? "—") · \(event.app ?? "Personal Model")")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(event.title).font(.headline)
                                if let detail = event.detail?.trimmedNonEmpty {
                                    Text(detail)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                                NativeTruthBadge(metadata: event.truthMetadata(day: day))
                                if let reference = event.evidenceRef {
                                    Button {
                                        Task { await state.loadEvidence(reference) }
                                    } label: {
                                        Label("Evidence", systemImage: "checkmark.seal")
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.caption)
                                    .accessibilityLabel("打开 \(event.title) 的 Evidence")
                                }
                            }
                            .padding(.vertical, 8)
                            .accessibilityElement(children: .contain)
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
                        VStack(spacing: 4) {
                            Text(face.text)
                                .font(.caption)
                                .lineLimit(3)
                            Text("Personal Model 推断")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                            .frame(width: 130)
                            .padding(10)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .disabled(face.evidenceRefs?.first == nil)
                    .accessibilityLabel("Personal Model 推断：\(face.text)")
                    .accessibilityHint(face.evidenceRefs?.first == nil ? "没有可打开的 Evidence" : "打开 Evidence")
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

    private func hasReport(for connector: ConnectorSnapshot) -> Bool {
        state.substantiveReports.contains { $0.connectorId == connector.id }
    }

    var body: some View {
        NativePaper {
            VStack(alignment: .leading, spacing: 26) {
                Text("CONNECTORS")
                    .font(.caption2.monospaced())
                    .tracking(3)
                    .foregroundStyle(.secondary)
                Text("连接你的 Personal Model")
                    .font(.largeTitle.bold())
                Text("每个连接都绑定当前模型与当前授权，不会读取另一位用户的数据。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                if let message = state.connectorErrorMessage {
                    NativeInlineState(
                        symbol: "exclamationmark.triangle",
                        title: "Connector 连接失败",
                        detail: message,
                        tint: .orange
                    )
                }
                NativeConnectorSwipe(state: state, connectors: connectors)
                if connectors.isEmpty {
                    NativeInlineState(
                        symbol: "point.3.connected.trianglepath.dotted",
                        title: "尚未发现 Connector",
                        detail: "安装支持的 Agent 后刷新；连接完成前不会生成报告。"
                    )
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 300), spacing: 18)],
                    spacing: 18
                ) {
                    ForEach(connectors) { connector in
                        HStack(alignment: .top, spacing: 16) {
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
                                Text(connectorStatusDetail(connector))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if connector.status == "connected" && !hasReport(for: connector) {
                                    Text("已连接，但尚未产生有实质数据的报告")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if connector.status == "connected" {
                                Label("Connected", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.green)
                            } else if connector.status == "missing" || connector.installed == false {
                                Label("未安装", systemImage: "shippingbox")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
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
                        .accessibilityElement(children: .contain)
                    }
                }
            }
        }
    }

    private func connectorStatusDetail(_ connector: ConnectorSnapshot) -> String {
        switch connector.status?.lowercased() {
        case "connected": return "已连接到当前 Personal Model"
        case "missing": return "本机未安装，当前无法连接"
        case "available": return "已安装，可以连接"
        case "connecting": return "正在连接"
        default: return "等待检测安装状态"
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
            Button {
                guard !done else { return }
                Task { await state.connectAll() }
            } label: {
                HStack {
                    Spacer()
                    Text(done ? "可用 Agents 已处理" : "滑动或按下，连接可用 Agents")
                    Image(systemName: done ? "checkmark" : "chevron.right.2")
                    Spacer()
                }
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(done || connectors.isEmpty || !state.connectingConnector.isEmpty)
            .accessibilityLabel(done ? "可用 Agents 已处理" : "连接全部可用 Agents")
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
                .accessibilityHidden(true)
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
        state.substantiveReports
    }

    var body: some View {
        NativePaper {
            VStack(alignment: .leading, spacing: 26) {
                    Text("AGENT REPORTS")
                        .font(.caption2.monospaced())
                        .tracking(3)
                        .foregroundStyle(.secondary)
                    Text("Agents 带回来的理解")
                        .font(.largeTitle.bold())
                    if reports.isEmpty {
                        NativeInlineState(
                            symbol: "doc.badge.clock",
                            title: "报告尚未产生",
                            detail: connectedReportDetail
                        )
                    }
                    ForEach(reports) { report in
                        VStack(alignment: .leading, spacing: 15) {
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    expandedReport = expandedReport == report.id ? nil : report.id
                                }
                            } label: {
                                HStack {
                                    Text(report.title).font(.title3.weight(.semibold))
                                    Spacer()
                                    Text(report.connectorId?.uppercased() ?? "AGENT")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    Image(systemName: expandedReport == report.id ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 10))
                                }
                            }
                            .buttonStyle(.plain)
                            if let summary = report.summary?.trimmedNonEmpty {
                                Text(summary)
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                            NativeTruthBadge(metadata: report.truthMetadata)
                            if expandedReport == report.id {
                                ForEach(report.sections ?? []) { section in
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(section.title).font(.headline)
                                        Text(section.body)
                                            .font(.callout)
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
                                        .accessibilityLabel("打开 \(report.title) 的 Evidence")
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

    private var connectedReportDetail: String {
        let connected = state.connectors.filter { $0.status == "connected" }
        if connected.isEmpty {
            return "先连接已安装的 Connector。只有带回实质数据后，这里才会显示报告。"
        }
        return "\(connected.map(\.name).joined(separator: "、")) 已连接，但还没有带回可展示的实质数据。"
    }
}

private struct NativeEvidenceView: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot

    private var evidence: [(reference: String, title: String, metadata: NativeTruthMetadata)] {
        var rows: [(reference: String, title: String, metadata: NativeTruthMetadata)] = []
        var seen = Set<String>()
        for face in snapshot.personalModel?.faces ?? [] {
            for reference in face.evidenceRefs ?? [] {
                if seen.insert(reference).inserted {
                    rows.append((
                        reference,
                        face.text,
                        face.truthMetadata(updatedAt: snapshot.personalModel?.updatedAt)
                    ))
                }
            }
        }
        for day in snapshot.time?.days ?? [] {
            for event in day.events ?? [] {
                if let reference = event.evidenceRef, seen.insert(reference).inserted {
                    rows.append((reference, event.title, event.truthMetadata(day: day)))
                }
            }
        }
        for report in state.substantiveReports {
            for reference in report.evidenceRefs ?? [] {
                if seen.insert(reference).inserted {
                    rows.append((reference, report.title, report.truthMetadata))
                }
            }
        }
        return rows
    }

    var body: some View {
        NativePaper {
            VStack(alignment: .leading, spacing: 25) {
                Text("EVIDENCE")
                    .font(.caption2.monospaced())
                    .tracking(3)
                    .foregroundStyle(.secondary)
                Text("这张 Card 为什么这样理解你")
                    .font(.largeTitle.bold())
                Text("Evidence 只显示当前 Personal Model 的引用。切换模型会建立新的会话和授权边界。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                if evidence.isEmpty {
                    NativeInlineState(
                        symbol: "checkmark.seal",
                        title: "尚无可核验 Evidence",
                        detail: "模型正在形成。没有引用的推断和生成内容不会在这里伪装成记录事实。"
                    )
                }
                VStack(spacing: 0) {
                    ForEach(Array(evidence.enumerated()), id: \.offset) { index, row in
                        Button {
                            Task { await state.loadEvidence(row.reference) }
                        } label: {
                            HStack(alignment: .top, spacing: 18) {
                            Text(String(format: "%02d", index + 1))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(row.title).font(.headline)
                                Text(row.reference)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                NativeTruthBadge(metadata: row.metadata)
                            }
                            Spacer()
                            Image(systemName: "doc.text.magnifyingglass")
                                .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("打开 Evidence：\(row.title)")
                        .padding(.vertical, 15)
                        Divider()
                    }
                }
            }
        }
    }
}

private struct NativeEvidencePresentation: View {
    @ObservedObject var state: PersonalModelAppState

    @ViewBuilder
    var body: some View {
        if let evidence = state.selectedEvidence {
            NativeEvidenceDetail(state: state, evidence: evidence)
        } else {
            ZStack {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { state.closeEvidence() }
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Label(
                            state.evidencePhase == .loading ? "正在验证 Evidence" : "Evidence 不可用",
                            systemImage: state.evidencePhase == .loading
                                ? "checkmark.seal" : "exclamationmark.triangle.fill"
                        )
                        .font(.headline)
                        Spacer()
                        Button {
                            state.closeEvidence()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("关闭 Evidence")
                    }
                    Text(state.selectedEvidenceReference)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if state.evidencePhase == .loading {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("正在确认这条引用仍属于当前模型与授权范围。")
                                .font(.body)
                        }
                        .accessibilityElement(children: .combine)
                    } else {
                        NativeInlineState(
                            symbol: "link.badge.plus",
                            title: "这条 Evidence 已失效",
                            detail: state.evidenceErrorMessage ?? "引用不存在或不再属于当前模型。",
                            tint: .orange
                        )
                        HStack {
                            Button("重新验证") {
                                let reference = state.selectedEvidenceReference
                                Task { await state.loadEvidence(reference) }
                            }
                            .buttonStyle(.borderedProminent)
                            Button("关闭") { state.closeEvidence() }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(28)
                .frame(width: 520)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 22))
                .shadow(color: .black.opacity(0.3), radius: 44, y: 24)
                .accessibilityElement(children: .contain)
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
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("关闭 Evidence")
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
                    Text(evidence.source?.trimmedNonEmpty ?? "Model · \(evidence.modelId)")
                    Spacer()
                    Text(
                        evidence.timeRange?.trimmedNonEmpty
                            ?? compactDateLabel(evidence.capturedAt)
                            ?? "当前模型引用"
                    )
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
            }
            .padding(28)
            .frame(width: 560, height: 430)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.3), radius: 44, y: 24)
            .accessibilityElement(children: .contain)
        }
    }
}

private struct NativeSetupView: View {
    @ObservedObject var state: PersonalModelAppState
    @State private var displayName = ""
    @State private var handle = ""
    @FocusState private var displayNameFocused: Bool

    var body: some View {
        VStack(spacing: 22) {
            NativeGlyph(glyph: Array(repeating: true, count: 25))
            Text(setupTitle).font(.title.bold())
            Text(setupDetail)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            if state.setupState == "profile_required" {
                Label("第一次使用", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                VStack(spacing: 12) {
                    TextField("你的名字", text: $displayName)
                        .focused($displayNameFocused)
                        .accessibilityLabel("你的名字")
                    TextField("@handle", text: $handle)
                        .accessibilityLabel("Card handle")
                    Button("创建我的 Personal Card") {
                        Task { await state.saveProfile(displayName: displayName, handle: handle) }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .textFieldStyle(.roundedBorder)
                .frame(width: 340)
                .onAppear { displayNameFocused = true }
            } else if ["not_installed", "onboarding_required", "unauthorized"].contains(state.setupState) {
                Button("打开 Personal Model 设置") {
                    Task { await state.launchPersonalModelSetup() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            } else if state.setupState == "backend_unavailable" {
                VStack(spacing: 10) {
                    if let message = state.setupErrorMessage?.trimmedNonEmpty {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                    }
                    Button("重新连接本机服务") { Task { await state.load() } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            } else if state.setupState == "model_forming" {
                VStack(spacing: 10) {
                    ProgressView().controlSize(.large)
                    Button("刷新形成进度") { Task { await state.load() } }
                        .buttonStyle(.bordered)
                }
            } else {
                ProgressView().controlSize(.large)
                    .accessibilityLabel("正在连接 Personal Model")
            }
        }
        .padding(52)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.75)))
        .shadow(color: .black.opacity(0.16), radius: 30, y: 18)
        .accessibilityElement(children: .contain)
    }

    private var setupTitle: String {
        switch state.setupState {
        case "profile_required": return "创建你的 Personal Card"
        case "not_installed": return "初始化 Personal Model"
        case "onboarding_required": return "完成本机权限设置"
        case "unauthorized": return "Personal Model 尚未授权"
        case "backend_unavailable": return "本机服务未启动"
        case "model_forming": return "Personal Model 正在形成"
        default: return "正在连接你的 Personal Model"
        }
    }

    private var setupDetail: String {
        switch state.setupState {
        case "profile_required": return "这张 Card 只属于当前 Mac 用户。名字可以稍后修改，模型数据不会与其他用户混用。"
        case "not_installed": return "Who Am I 会在本机安装固定版本的 Personal Model 后端。"
        case "onboarding_required": return "请允许 Accessibility 与 Screen Recording，让模型开始形成属于你的记忆。"
        case "unauthorized": return "Who Am I 无法读取当前模型。请在设置中恢复授权，之后再刷新。"
        case "backend_unavailable": return "Who Am I 没有连接到只在本机运行的 Personal Model 服务。"
        case "model_forming": return "已经完成连接，但还没有足够记录形成可靠的推断和报告。"
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
        ScrollView {
            content
                .padding(38)
                .frame(maxWidth: maxWidth, alignment: .topLeading)
                .background(
                    Color(nsColor: .textBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 22)
                )
                .shadow(color: .black.opacity(0.22), radius: 34, y: 22)
                .padding(42)
                .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .contain)
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

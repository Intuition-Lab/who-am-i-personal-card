import AppKit
import Foundation
import SwiftUI

let whoAmIVisualQAOpaque = ProcessInfo.processInfo.environment["WHOAMI_VISUAL_QA_OPAQUE"] == "1"
let whoAmIVisualQAActive =
    ProcessInfo.processInfo.environment["WHOAMI_VISUAL_QA_ACTIVE"] == "1"
    || whoAmIVisualQAOpaque

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
    let fractionalParser = ISO8601DateFormatter()
    fractionalParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let regularParser = ISO8601DateFormatter()
    guard let date = fractionalParser.date(from: value) ?? regularParser.date(from: value) else {
        return value
    }
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
    @Published var isShareOpen = false
    @Published var isMemorySkyOpen = false
    @Published var isConnectorDockOpen = false
    @Published var isRewindDayOpen = false
    @Published var rewindDayRequest: String?
    @Published var shareHighlight: String?
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
    @Published var searchFocusRequest = 0

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

    func openRewind(dayID: String?) {
        rewindDayRequest = dayID?.trimmedNonEmpty
        selectedSection = .rewind
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

    func saveProfile(
        displayName: String,
        handle: String,
        tagline: String,
        description: String
    ) async {
        do {
            let _: SetupResponse = try await request(
                path: "api/setup/profile",
                method: "POST",
                json: [
                    "displayName": displayName,
                    "handle": handle,
                    "tagline": tagline,
                    "description": description,
                ]
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

    func openSearch() {
        selectedSection = .card
        isShareOpen = false
        isMemorySkyOpen = false
        isConnectorDockOpen = false
        isAskOpen = false
        searchFocusRequest += 1
    }

    func openAsk() {
        selectedSection = .card
        isShareOpen = false
        isMemorySkyOpen = false
        isConnectorDockOpen = false
        isAskOpen = true
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

    @discardableResult
    func handleEscape() -> Bool {
        if hasEvidencePresentation {
            closeEvidence()
            return true
        }
        if isShareOpen {
            isShareOpen = false
            return true
        }
        if isMemorySkyOpen {
            isMemorySkyOpen = false
            return true
        }
        if isConnectorDockOpen {
            isConnectorDockOpen = false
            return true
        }
        if isAskOpen {
            isAskOpen = false
            return true
        }
        if selectedSection != .card {
            selectedSection = .card
            return true
        }
        return false
    }

    func openShare(highlight: String? = nil) {
        shareHighlight = highlight?.trimmedNonEmpty
        isShareOpen = true
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
                        }
                        NativeSectionContent(state: state, snapshot: snapshot)
                    }
                } else {
                    NativeSetupView(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(
                !state.isMemorySkyOpen
                    && !state.isShareOpen
                    && !state.hasEvidencePresentation
            )
            .accessibilityHidden(
                state.isMemorySkyOpen
                    || state.isShareOpen
                    || state.hasEvidencePresentation
            )
            if state.selectedSection != .card
                && !state.isShareOpen
                && !state.isMemorySkyOpen
                && !state.isRewindDayOpen {
                NativeReturnToCard(state: state)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 18)
            }
            if let snapshot = state.snapshot, state.isMemorySkyOpen {
                NativeMemorySky(state: state, snapshot: snapshot)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
            if let snapshot = state.snapshot, state.isShareOpen {
                NativeShareView(state: state, snapshot: snapshot)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
            if state.hasEvidencePresentation {
                NativeEvidencePresentation(state: state)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            if let message = state.correctionMessage {
                NativeCorrectionToast(
                    message: message,
                    isFailure: state.correctionPhase == .failure,
                    memoryCount: state.snapshot?.personalModel?.memoryCount ?? 0
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(24)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .task(id: message) {
                    try? await Task.sleep(nanoseconds: 3_200_000_000)
                    state.resetCorrectionStatus()
                }
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
    @ViewBuilder
    var body: some View {
        if whoAmIVisualQAOpaque {
            LinearGradient(
                colors: [
                    Color(red: 0.56, green: 0.61, blue: 0.71),
                    Color(red: 0.66, green: 0.65, blue: 0.62),
                    Color(red: 0.79, green: 0.75, blue: 0.69),
                    Color(red: 0.89, green: 0.86, blue: 0.82),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                RadialGradient(
                    colors: [.white.opacity(0.34), .clear],
                    center: .topTrailing,
                    startRadius: 30,
                    endRadius: 620
                )
            )
            .ignoresSafeArea()
        } else {
            Color.clear.ignoresSafeArea()
        }
    }
}

private struct NativeReturnToCard: View {
    @ObservedObject var state: PersonalModelAppState

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                state.selectedSection = .card
            }
        } label: {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.24), Color.black.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 22, height: 14)
                Text("回到卡").font(.callout.weight(.semibold))
                Text("esc")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(.black.opacity(0.82), in: Capsule())
            .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .accessibilityLabel("回到 Personal Card")
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

private struct NativeCorrectionToast: View {
    let message: String
    let isFailure: Bool
    let memoryCount: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.12, green: 0.12, blue: 0.14), .black],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            ForEach(0..<16, id: \.self) { index in
                Circle()
                    .fill(.white.opacity(index.isMultiple(of: 4) ? 0.34 : 0.15))
                    .frame(width: index.isMultiple(of: 5) ? 2.2 : 1.1)
                    .offset(
                        x: -105 + stableUnit("toast-\(index)", salt: 19) * 210,
                        y: -40 + stableUnit("toast-\(index)", salt: 47) * 80
                    )
                    .accessibilityHidden(true)
            }
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: isFailure ? "exclamationmark.triangle.fill" : "sparkle")
                    .foregroundStyle(isFailure ? .orange : .mint)
                VStack(alignment: .leading, spacing: 5) {
                    Text(isFailure ? "更正没有写入" : "+1 颗星")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(message)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.52))
                        .lineLimit(2)
                    if !isFailure {
                        Text("Personal Model · \(memoryCount) memories · 已重新读取")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.white.opacity(0.34))
                    }
                }
            }
            .padding(15)
        }
        .frame(width: 250)
        .frame(minHeight: 92)
        .shadow(color: .black.opacity(0.42), radius: 28, y: 18)
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
            NativeIdentityView(state: state, snapshot: snapshot)
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
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: 26) {
                        NativeHeroCard(state: state, snapshot: snapshot)
                        NativeNowPanel(state: state, snapshot: snapshot)
                        if state.isConnectorDockOpen {
                            NativeConnectorDock(state: state, snapshot: snapshot)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 28)
                .padding(.bottom, 44)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct NativeCardMaterial {
    let top: Color
    let bottom: Color
    let name: Color
    let corner: Color
    let detail: Color
    let glyphOn: Color
    let glyphOff: Color
    let isLight: Bool

    static func resolve(_ rawValue: String?) -> NativeCardMaterial {
        switch rawValue?.lowercased() {
        case "ceramic":
            return NativeCardMaterial(
                top: Color(red: 0.98, green: 0.98, blue: 0.96),
                bottom: Color(red: 0.91, green: 0.90, blue: 0.87),
                name: Color(red: 0.50, green: 0.49, blue: 0.46),
                corner: Color.black.opacity(0.48),
                detail: Color(red: 0.34, green: 0.33, blue: 0.31),
                glyphOn: Color(red: 0.54, green: 0.53, blue: 0.50),
                glyphOff: Color.black.opacity(0.05),
                isLight: true
            )
        case "klein":
            return NativeCardMaterial(
                top: Color(red: 0.20, green: 0.31, blue: 0.94),
                bottom: Color(red: 0.10, green: 0.17, blue: 0.66),
                name: Color(red: 0.07, green: 0.11, blue: 0.48),
                corner: Color.white.opacity(0.58),
                detail: Color.white.opacity(0.90),
                glyphOn: Color.white.opacity(0.94),
                glyphOff: Color.white.opacity(0.14),
                isLight: false
            )
        case "graphite":
            return NativeCardMaterial(
                top: Color(red: 0.12, green: 0.12, blue: 0.14),
                bottom: Color(red: 0.035, green: 0.035, blue: 0.045),
                name: Color(red: 0.045, green: 0.045, blue: 0.055),
                corner: Color.white.opacity(0.42),
                detail: Color.white.opacity(0.78),
                glyphOn: Color.white.opacity(0.94),
                glyphOff: Color.white.opacity(0.10),
                isLight: false
            )
        default:
            return NativeCardMaterial(
                top: Color(red: 0.29, green: 0.29, blue: 0.32),
                bottom: Color(red: 0.14, green: 0.14, blue: 0.16),
                name: Color(red: 0.12, green: 0.12, blue: 0.15),
                corner: Color.white.opacity(0.42),
                detail: Color.white.opacity(0.80),
                glyphOn: Color.black.opacity(0.68),
                glyphOff: Color.white.opacity(0.07),
                isLight: false
            )
        }
    }
}

private struct NativeCardStar: Identifiable {
    let id: Int
    let x: Double
    let y: Double
    let size: Double
    let opacity: Double
    let isBlue: Bool

    var isBright: Bool { size > 2 }
}

private struct NativeHeroCard: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot
    @State private var flipped = false
    @State private var drag = CGSize.zero
    @State private var hoverLocation: CGPoint?
    @State private var correction = ""
    @State private var selectedFaceID: String?
    @State private var rootSelected = false

    private var glyph: [Bool] {
        let source = snapshot.card?.glyph ?? []
        return source.count == 25 ? source : Array(repeating: true, count: 25)
    }

    private var material: NativeCardMaterial {
        NativeCardMaterial.resolve(snapshot.card?.material)
    }

    private var materialKey: String {
        snapshot.card?.material?.lowercased() ?? "titanium"
    }

    private var cardStars: [NativeCardStar] {
        let clusters: [(x: Double, y: Double, radius: Double, count: Int)] = [
            (28, 40, 16, 34),
            (66, 56, 14, 26),
            (46, 72, 11, 18),
            (76, 26, 9, 12),
        ]
        var stars: [NativeCardStar] = []
        for (clusterIndex, cluster) in clusters.enumerated() {
            for index in 0..<cluster.count {
                let angle = (Double(index) * 137.5 + Double(clusterIndex) * 40)
                    * .pi / 180
                let hash = (Int64(index) * 2_654_435_761) % 97
                let radius = cluster.radius * sqrt(Double(hash) / 97)
                let rank = (index * 7 + clusterIndex * 13) % 11
                let isBlue = rank == 0 && index.isMultiple(of: 3)
                let isDim = rank == 1 || rank == 2
                let size = isBlue ? 3 : (!isDim && index.isMultiple(of: 5) ? 2.5 : 1.6)
                stars.append(
                    NativeCardStar(
                        id: stars.count,
                        x: cluster.x + cos(angle) * radius,
                        y: cluster.y + sin(angle) * radius * 0.8,
                        size: size,
                        opacity: isDim ? 0.3 : 0.75,
                        isBlue: isBlue
                    )
                )
            }
        }
        return stars
    }

    private var hoverTiltX: Double {
        guard let hoverLocation else { return 0 }
        return (0.5 - hoverLocation.y / (430 / 1.586)) * 5
    }

    private var hoverTiltY: Double {
        guard let hoverLocation else { return 0 }
        return (hoverLocation.x / 430 - 0.5) * 6
    }

    private var glareCenter: UnitPoint {
        guard let hoverLocation else { return UnitPoint(x: 0.3, y: 0.2) }
        return UnitPoint(
            x: min(1, max(0, hoverLocation.x / 430)),
            y: min(1, max(0, hoverLocation.y / (430 / 1.586)))
        )
    }

    private var cardLocator: String {
        if snapshot.card?.isConfirmedPublished == true,
           let publicURL = snapshot.card?.publicUrl?.trimmedNonEmpty {
            return "ONE OF ONE\n\(publicURL)"
        }
        return "ONE OF ONE\nLOCAL · \(snapshot.model.id.suffix(8))"
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [material.top, material.bottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            materialKey == "ceramic"
                                ? Color.white.opacity(0.88)
                                : Color(red: 0.36, green: 0.48, blue: 1.0)
                                    .opacity(materialKey == "graphite" ? 0.14 : 0.08),
                            .clear,
                        ],
                        center: UnitPoint(x: 0.18, y: -0.10),
                        startRadius: 0,
                        endRadius: 275
                    )
                )
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.32),
                            .init(
                                color: .white.opacity(material.isLight ? 0.24 : 0.045),
                                location: 0.42
                            ),
                            .init(color: .clear, location: 0.54),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    material.isLight
                        ? Color.black.opacity(0.05)
                        : Color.white.opacity(0.08),
                    lineWidth: 1
                )
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(material.isLight ? 0.36 : 0.10), lineWidth: 1)
                .padding(1)
            front
                .opacity(flipped ? 0 : 1)
                .rotation3DEffect(.degrees(flipped ? 180 : 0), axis: (x: 0, y: 1, z: 0))
                .allowsHitTesting(!flipped)
                .accessibilityHidden(flipped)
            back
                .opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(flipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                .allowsHitTesting(flipped)
                .accessibilityHidden(!flipped)
        }
        .frame(width: 430, height: 430 / 1.586)
        .shadow(
            color: materialKey == "klein"
                ? Color(red: 0.12, green: 0.20, blue: 0.72).opacity(0.42)
                : Color.black.opacity(material.isLight ? 0.20 : 0.42),
            radius: 34,
            y: 25
        )
        .rotation3DEffect(
            .degrees(Double(drag.width / 45) + hoverTiltY),
            axis: (x: -drag.height / 80, y: 1, z: 0),
            perspective: 0.45
        )
        .rotation3DEffect(
            .degrees(hoverTiltX),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.45
        )
        .offset(x: drag.width * 0.08, y: drag.height * 0.04)
        .animation(.spring(response: 0.46, dampingFraction: 0.82), value: flipped)
        .animation(.interactiveSpring(), value: drag)
        .animation(.easeOut(duration: 0.18), value: hoverLocation)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): hoverLocation = point
            case .ended: hoverLocation = nil
            }
        }
        .focusable()
        .onMoveCommand { direction in
            guard flipped else { return }
            let faces = snapshot.personalModel?.faces ?? []
            guard !faces.isEmpty else { return }
            let current = selectedFaceID.flatMap { id in faces.firstIndex(where: { $0.id == id }) } ?? -1
            switch direction {
            case .left, .up:
                selectedFaceID = faces[(current - 1 + faces.count) % faces.count].id
                rootSelected = false
            case .right, .down:
                selectedFaceID = faces[(current + 1) % faces.count].id
                rootSelected = false
            default:
                break
            }
        }
    }

    private var front: some View {
        ZStack {
            VStack {
                HStack {
                    Text("№ \(snapshot.model.memberNumber ?? "001")")
                    Spacer()
                    Text(snapshot.card?.monthYear ?? "AS OF NOW")
                }
                .font(.system(size: 8.5, design: .monospaced))
                .tracking(2.2)
                .foregroundStyle(material.corner)
                Spacer()
                HStack(alignment: .bottom) {
                    Text("IDENTITY\nPERSONAL MODEL")
                    Spacer()
                    Text(cardLocator)
                        .multilineTextAlignment(.trailing)
                }
                .font(.system(size: 8.5, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(material.corner)
            }
            VStack(spacing: 17) {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(4.5), spacing: 2),
                        count: 5
                    ),
                    spacing: 2
                ) {
                    ForEach(Array(glyph.enumerated()), id: \.offset) { _, isOn in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(isOn ? material.glyphOn : material.glyphOff)
                            .frame(width: 4.5, height: 4.5)
                    }
                }
                .frame(width: 31)
                Text(snapshot.model.handle)
                    .font(.system(size: 34, weight: .medium, design: .default))
                    .tracking(2.9)
                    .foregroundStyle(material.name)
                    .shadow(color: .white.opacity(0.16), radius: 7)
            }
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.13), .clear],
                        center: glareCenter,
                        startRadius: 0,
                        endRadius: 230
                    )
                )
                .opacity(hoverLocation == nil ? 0 : 1)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 24)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture { flipped = true }
        .simultaneousGesture(cardGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { flipped = true }
        .accessibilityLabel("\(snapshot.model.displayName) Personal Model Card")
        .accessibilityHint("按空格、点击或横向滑动翻转 Card")
    }

    private var back: some View {
        GeometryReader { proxy in
            ZStack {
                Canvas { context, size in
                    for star in cardStars where !star.isBright {
                        let point = CGPoint(
                            x: size.width * star.x / 100,
                            y: size.height * star.y / 100
                        )
                        let rect = CGRect(
                            x: point.x - star.size / 2,
                            y: point.y - star.size / 2,
                            width: star.size,
                            height: star.size
                        )
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(material.detail.opacity(star.opacity))
                        )
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                let faces = snapshot.personalModel?.faces ?? []
                ForEach(cardStars.filter(\.isBright)) { star in
                    let face = faces.isEmpty ? nil : faces[star.id % faces.count]
                    Button {
                        guard let face else { return }
                        withAnimation(.easeOut(duration: 0.18)) {
                            selectedFaceID = selectedFaceID == face.id ? nil : face.id
                            rootSelected = false
                        }
                    } label: {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        star.isBlue
                                            ? Color(red: 0.56, green: 0.65, blue: 1.0)
                                            : material.detail,
                                        (star.isBlue
                                            ? Color(red: 0.56, green: 0.65, blue: 1.0)
                                            : material.detail).opacity(0.42),
                                        .clear,
                                    ],
                                    center: .center,
                                    startRadius: 1.8,
                                    endRadius: 9
                                )
                            )
                            .frame(width: 20, height: 20)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: proxy.size.width * star.x / 100,
                        y: proxy.size.height * star.y / 100
                    )
                    .disabled(face == nil)
                    .accessibilityLabel(
                        face.map { "Personal Model 推断：\($0.text)" }
                            ?? "Personal Model 星点"
                    )
                }
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        rootSelected.toggle()
                        selectedFaceID = nil
                    }
                } label: {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white, .blue.opacity(0.65), .clear],
                                center: .center,
                                startRadius: 1,
                                endRadius: 14
                            )
                        )
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.44)
                .accessibilityLabel("ROOT · 我是谁")

                VStack {
                    HStack {
                        Button("✦ 展开星空") {
                            withAnimation(.spring(response: 0.32)) { state.isMemorySkyOpen = true }
                        }
                        .buttonStyle(.plain)
                        .tracking(1.35)
                        Spacer()
                        Button("AS OF NOW") {
                            selectedFaceID = nil
                            rootSelected = false
                            flipped = false
                        }
                        .buttonStyle(.plain)
                        .tracking(2.05)
                        .accessibilityLabel("翻回 Card 正面")
                    }
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(material.corner)
                    Spacer()
                    if rootSelected {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("ROOT · 我是谁")
                                    .font(.system(size: 7.5, design: .monospaced))
                                    .tracking(1.6)
                                    .foregroundStyle(material.corner)
                                Spacer()
                                Text("← → 巡星")
                                    .font(.system(size: 7.5, design: .monospaced))
                                    .foregroundStyle(material.corner)
                                Button { rootSelected = false } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain)
                            }
                            Text(snapshot.personalModel?.root?.trimmedNonEmpty ?? "Personal Model 正在形成对你的长期理解。")
                                .font(.system(size: 13.5, design: .serif))
                                .lineSpacing(4)
                                .foregroundStyle(material.isLight ? Color.black.opacity(0.88) : Color.white.opacity(0.92))
                                .lineLimit(3)
                            HStack(spacing: 10) {
                                Text("Personal Model · 当前快照")
                                Spacer()
                                Button("改写") {
                                    correction = snapshot.personalModel?.root?.trimmedNonEmpty ?? ""
                                }
                                Button("行动") { state.selectedSection = .connectors }
                                Button("分享 ↗") {
                                    state.openShare(highlight: snapshot.personalModel?.root)
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(material.isLight ? Color.black.opacity(0.52) : Color.white.opacity(0.52))
                            if !correction.isEmpty {
                                HStack(spacing: 7) {
                                    TextField("不对的话，改写它", text: $correction)
                                        .textFieldStyle(.plain)
                                        .font(.caption)
                                        .foregroundStyle(material.isLight ? Color.black : Color.white)
                                        .onSubmit { Task { await state.correct(correction) } }
                                    Button(state.isCorrecting ? "写入中" : "⏎") {
                                        Task { await state.correct(correction) }
                                    }
                                    .disabled(state.isCorrecting)
                                }
                                .padding(.horizontal, 9)
                                .frame(height: 27)
                                .background(
                                    material.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                            }
                        }
                        .padding(13)
                        .background(
                            material.isLight ? Color.white.opacity(0.88) : Color.black.opacity(0.72),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(material.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.11))
                        )
                    }
                    if let selectedFace = (snapshot.personalModel?.faces ?? []).first(where: { $0.id == selectedFaceID }) {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text("PERSONAL MODEL · INFERENCE")
                                    .font(.system(size: 7.5, design: .monospaced))
                                    .tracking(1.6)
                                .foregroundStyle(material.corner)
                                Spacer()
                                Text("← → 巡星")
                                    .font(.system(size: 7.5, design: .monospaced))
                                    .foregroundStyle(material.corner)
                                Button { selectedFaceID = nil } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain)
                            }
                            Text(selectedFace.text)
                                .font(.system(size: 13.5, design: .serif))
                                .lineSpacing(4)
                                .foregroundStyle(material.isLight ? Color.black.opacity(0.88) : Color.white.opacity(0.92))
                                .lineLimit(3)
                            let metadata = selectedFace.truthMetadata(updatedAt: snapshot.personalModel?.updatedAt)
                            HStack(spacing: 10) {
                                Text(metadata.kind.label)
                                if !metadata.detail.isEmpty { Text(metadata.detail).lineLimit(1) }
                                Spacer()
                                if let reference = selectedFace.evidenceRefs?.first {
                                    Button("出处") { Task { await state.loadEvidence(reference) } }
                                }
                                Button("改写") { correction = selectedFace.text }
                                Button("行动") { state.selectedSection = .connectors }
                                Button("分享 ↗") { state.openShare(highlight: selectedFace.text) }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(material.isLight ? Color.black.opacity(0.52) : Color.white.opacity(0.52))
                            if !correction.isEmpty {
                                HStack(spacing: 7) {
                                    TextField("不对的话，改写它", text: $correction)
                                        .textFieldStyle(.plain)
                                        .font(.caption)
                                        .foregroundStyle(material.isLight ? Color.black : Color.white)
                                        .onSubmit { Task { await state.correct(correction) } }
                                    Button(state.isCorrecting ? "写入中" : "⏎") {
                                        Task { await state.correct(correction) }
                                    }
                                    .disabled(state.isCorrecting)
                                }
                                .padding(.horizontal, 9)
                                .frame(height: 27)
                                .background(
                                    material.isLight ? Color.black.opacity(0.06) : Color.white.opacity(0.08),
                                    in: RoundedRectangle(cornerRadius: 7)
                                )
                            }
                        }
                        .padding(13)
                        .background(
                            material.isLight ? Color.white.opacity(0.88) : Color.black.opacity(0.72),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(material.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.11))
                        )
                    }
                    HStack(alignment: .bottom) {
                        Text("№ \(snapshot.model.memberNumber ?? "001")")
                            .font(.system(size: 19, weight: .medium))
                            .tracking(1.7)
                        Spacer()
                        Text("\(snapshot.personalModel?.memoryCount ?? 0) MEMORIES")
                            .font(.system(size: 8.5, design: .monospaced))
                            .tracking(1.7)
                    }
                    .foregroundStyle(material.corner)
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 26)
            }
        }
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

    private var nowDateLabel: String {
        snapshot.card?.monthYear?.trimmedNonEmpty
            ?? snapshot.personalModel?.updatedAt.flatMap(compactDateLabel)
            ?? "AS OF NOW"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 20, height: 20)
                TextField("搜索你记得的事…", text: $state.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .regular))
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
                Divider().frame(height: 26)
                Button {
                    withAnimation(.spring(response: 0.32)) {
                        state.isMemorySkyOpen = true
                    }
                } label: {
                    Text("✦ 巡星")
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityLabel("展开 Memory Sky")
                Button {
                    withAnimation(.spring(response: 0.32)) {
                        state.isConnectorDockOpen.toggle()
                    }
                } label: {
                    Text("Swipe your card")
                        .font(.system(size: 8.5, design: .monospaced))
                        .tracking(0.4)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.black.opacity(0.11), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .frame(height: 58)
            Divider()

            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("Now")
                    .font(.caption.weight(.semibold))
                Text("过去 · 现在 · 未来")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(nowDateLabel.uppercased())
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 13)
            .padding(.bottom, 7)

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
                        NativeNowRow(item: item) {
                            state.openRewind(dayID: item.dayId)
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
                Button("时间") { state.selectedSection = .rewind }
                    .buttonStyle(.plain)
                if visibleNowItems.contains(where: \.isFutureLike) {
                    Button("看看接下来 ›") { state.selectedSection = .rewind }
                        .buttonStyle(.plain)
                }
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(16)
        }
        .background {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .fill(
                            Color(red: 0.965, green: 0.965, blue: 0.957)
                                .opacity(0.28)
                        )
                }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Color.white.opacity(0.7), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.15), radius: 26, y: 18)
        .onChange(of: state.searchFocusRequest) { _ in
            searchFocused = true
        }
    }
}

private struct NativeConnectorDock: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot

    private var connectors: [ConnectorSnapshot] {
        state.connectors.isEmpty ? (snapshot.connectors ?? []) : state.connectors
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(connectorSummary)
                    .font(.system(size: 25, weight: .bold))
                Text("没有捕获到的事，不会写成已调用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Swipe your card →") { state.selectedSection = .connectors }
                    .buttonStyle(.borderless)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 130), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(connectors) { connector in
                    Button {
                        if connector.status == "connected" {
                            state.selectedSection = .reports
                        } else if connector.status != "missing" {
                            Task { await state.connect(connector.id) }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color.black.opacity(0.08))
                                .frame(width: 26, height: 26)
                                .overlay(Text(String(connector.name.prefix(1))).font(.caption.weight(.bold)))
                            Text(connector.name).font(.caption.weight(.semibold))
                            if connector.status == "connected" {
                                Circle().fill(.green).frame(width: 5, height: 5)
                            } else {
                                Text(connector.status == "missing" ? "未安装" : "+")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: Capsule())
                        .overlay(Capsule().stroke(Color.black.opacity(0.07)))
                    }
                    .buttonStyle(.plain)
                    .disabled(connector.status == "missing")
                }
            }
            if connectors.isEmpty {
                NativeInlineState(
                    symbol: "point.3.connected.trianglepath.dotted",
                    title: "还没有发现可连接的 Agent",
                    detail: "安装支持 MCP 的 Agent 后刷新；Who Am I 不会伪造连接记录。"
                )
            }
            HStack {
                Text("Personal Model · \(snapshot.personalModel?.memoryCount ?? 0) 条记忆")
                Spacer()
                Text("仅在本机读取 · 127.0.0.1")
            }
            .font(.caption2.monospaced())
            .foregroundStyle(.tertiary)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.66)))
        .shadow(color: .black.opacity(0.12), radius: 22, y: 14)
    }

    private var connectorSummary: String {
        let connected = connectors.filter { $0.status == "connected" }.count
        if connectors.isEmpty { return "还没有 Agent 戴上这张卡" }
        return connected == 0 ? "把卡刷给你的 Agents" : "\(connected) 个 Agent 正在戴着你的卡"
    }
}

private struct NativeShareView: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot
    @State private var copied = false
    @State private var saved = false

    private var shareText: String {
        var lines = [
            snapshot.model.displayName,
            snapshot.model.handle,
            snapshot.card?.tagline ?? "Personal Model",
        ]
        if let highlight = state.shareHighlight?.trimmedNonEmpty {
            lines.append(highlight)
        }
        if snapshot.card?.isConfirmedPublished == true,
           let publicURL = snapshot.card?.publicUrl?.trimmedNonEmpty {
            lines.append(publicURL)
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RadialGradient(
                    colors: [Color(red: 0.10, green: 0.10, blue: 0.12), .black],
                    center: .top,
                    startRadius: 10,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.85
                )
                .ignoresSafeArea()
                ForEach(0..<44, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(index.isMultiple(of: 7) ? 0.42 : 0.16))
                        .frame(
                            width: index.isMultiple(of: 9) ? 2.4 : 1.2,
                            height: index.isMultiple(of: 9) ? 2.4 : 1.2
                        )
                        .position(
                            x: stableUnit("share-\(index)", salt: 19) * proxy.size.width,
                            y: stableUnit("share-\(index)", salt: 53) * proxy.size.height
                        )
                        .accessibilityHidden(true)
                }
                VStack(spacing: 18) {
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                state.isShareOpen = false
                                state.shareHighlight = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("关闭分享卡")
                    }
                    NativeSharePoster(snapshot: snapshot, highlight: state.shareHighlight)
                        .frame(width: 360, height: 470)
                    HStack(spacing: 10) {
                        Button(copied ? "已复制" : "复制卡片") {
                            state.copyCard()
                            copied = true
                        }
                        ShareLink(item: shareText) {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                        Button(saved ? "已保存" : "存为图片") {
                            saved = saveSharePoster(snapshot: snapshot, highlight: state.shareHighlight)
                        }
                        Button("Identity") {
                            state.isShareOpen = false
                            state.selectedSection = .identity
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .foregroundStyle(.white)
                    Text(
                        snapshot.card?.isConfirmedPublished == true
                            ? "PUBLIC CUT · SAME MODEL"
                            : "BETA SHARE · COPY OR SAVE LOCALLY"
                    )
                    .font(.caption2.monospaced())
                    .tracking(1.4)
                    .foregroundStyle(.white.opacity(0.34))
                }
                .padding(22)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct NativeSharePoster: View {
    let snapshot: PersonalModelSnapshot
    let highlight: String?

    private var material: NativeCardMaterial {
        NativeCardMaterial.resolve(snapshot.card?.material)
    }

    private var doing: String {
        let item = (snapshot.now?.items ?? []).first { !$0.isFutureLike }
        return item?.displayTitle ?? snapshot.card?.tagline ?? "Personal Model 正在形成"
    }

    private var thinking: String {
        snapshot.personalModel?.root?.trimmedNonEmpty
            ?? snapshot.identity?.dailyLine?.trimmedNonEmpty
            ?? "还没有足够依据形成可展示的判断"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("№ \(snapshot.model.memberNumber ?? "001")")
                Spacer()
                Text("ONE OF ONE")
            }
            .font(.system(size: 8, design: .monospaced))
            .tracking(2.1)
            .foregroundStyle(material.corner)
            NativeGlyph(glyph: snapshot.card?.glyph ?? [])
                .scaleEffect(0.62, anchor: .topLeading)
                .frame(width: 48, height: 48)
                .padding(.top, 24)
            Text(
                highlight?.trimmedNonEmpty
                    ?? snapshot.identity?.description?.trimmedNonEmpty
                    ?? snapshot.card?.tagline
                    ?? "Personal Model"
            )
                .font(.system(size: 22, weight: .regular, design: .serif))
                .lineSpacing(7)
                .foregroundStyle(material.isLight ? Color.black.opacity(0.86) : material.detail)
                .padding(.top, 18)
                .lineLimit(4)
            Spacer()
            Text(snapshot.model.handle)
                .font(.system(size: 34, weight: .medium, design: .rounded))
                .foregroundStyle(material.name)
            Text("IDENTITY · PERSONAL MODEL")
                .font(.system(size: 8.5, design: .monospaced))
                .tracking(2)
                .foregroundStyle(material.corner)
                .padding(.top, 7)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 7) {
                GridRow {
                    Text("在做").foregroundStyle(material.corner)
                    Text(doing).lineLimit(1)
                }
                GridRow {
                    Text("在想").foregroundStyle(material.corner)
                    Text(thinking).lineLimit(2)
                }
            }
            .font(.caption)
            .foregroundStyle(material.detail)
            .padding(.top, 16)
            Divider()
                .overlay(material.isLight ? Color.black.opacity(0.12) : Color.white.opacity(0.18))
                .padding(.top, 16)
            HStack {
                Text(snapshot.card?.isConfirmedPublished == true ? "PUBLIC CUT" : "LOCAL CARD")
                Spacer()
                Text(snapshot.card?.monthYear ?? "AS OF NOW")
            }
            .font(.system(size: 7.5, design: .monospaced))
            .tracking(1.6)
            .foregroundStyle(material.corner)
            .padding(.top, 11)
        }
        .padding(26)
        .background(
            LinearGradient(
                colors: [material.top, material.bottom],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    material.isLight ? Color.black.opacity(0.07) : Color.white.opacity(0.13),
                    lineWidth: 0.7
                )
        )
        .shadow(color: .black.opacity(0.45), radius: 36, y: 22)
    }
}

@MainActor
private func saveSharePoster(snapshot: PersonalModelSnapshot, highlight: String?) -> Bool {
    let renderer = ImageRenderer(
        content: NativeSharePoster(snapshot: snapshot, highlight: highlight)
            .frame(width: 720, height: 940)
            .padding(48)
            .background(Color.black)
    )
    renderer.scale = 2
    guard
        let image = renderer.nsImage,
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let data = bitmap.representation(using: .png, properties: [:])
    else { return false }

    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.canCreateDirectories = true
    panel.nameFieldStringValue = "Who Am I · \(snapshot.model.displayName).png"
    guard panel.runModal() == .OK, let destination = panel.url else { return false }
    do {
        try data.write(to: destination, options: .atomic)
        return true
    } catch {
        return false
    }
}

private enum NativeSkyMode: String, CaseIterable, Identifiable {
    case constellation = "星座"
    case dust = "星尘"
    case time = "时间"

    var id: String { rawValue }
}

private struct NativeConstellationTheme: Identifiable {
    let id: Int
    let face: FaceSnapshot
    let x: CGFloat
    let y: CGFloat
    let size: Int
    let color: Color
}

private struct NativeConstellationStar: Identifiable {
    let id: String
    let themeIndex: Int?
    let title: String
    let detail: String
    let source: String
    let reference: String?
    let x: CGFloat
    let y: CGFloat
    let timeX: CGFloat
    let timeY: CGFloat
    let age: CGFloat
    let isBright: Bool
    let isBig: Bool
    let isAmbient: Bool
}

private struct NativeMemorySky: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot
    @State private var mode: NativeSkyMode = .constellation
    @State private var selectedStar: NativeConstellationStar?
    @State private var threeD = false
    @State private var skyTilt = CGSize.zero
    @State private var skyCorrection = ""

    private let positions: [(CGFloat, CGFloat)] = [
        (0.38, 0.42),
        (0.68, 0.24),
        (0.67, 0.66),
        (0.22, 0.24),
        (0.18, 0.64),
        (0.85, 0.46),
    ]

    private let themeColors: [Color] = [
        Color(red: 0.42, green: 0.45, blue: 0.58),
        Color(red: 0.40, green: 0.50, blue: 0.45),
        Color(red: 0.55, green: 0.42, blue: 0.35),
        Color(red: 0.32, green: 0.33, blue: 0.36),
        Color(red: 0.44, green: 0.39, blue: 0.53),
        Color(red: 0.43, green: 0.50, blue: 0.58),
    ]

    private var themes: [NativeConstellationTheme] {
        Array((snapshot.personalModel?.faces ?? []).prefix(6).enumerated()).map {
            index, face in
            NativeConstellationTheme(
                id: index,
                face: face,
                x: positions[index].0,
                y: positions[index].1,
                size: max(4, 16 - index * 2),
                color: themeColors[index]
            )
        }
    }

    private var skyStars: [NativeConstellationStar] {
        var output: [NativeConstellationStar] = []
        for theme in themes {
            for index in 0..<theme.size {
                let angle = (Double(index) * 137.5 + Double(theme.id) * 61)
                    * .pi / 180
                let hash = (Int64(index) * 2_654_435_761) % 97
                let radius = CGFloat(theme.id == 0 ? 0.13 : 0.09)
                    * sqrt(CGFloat(hash) / 97)
                let age = CGFloat((index * 5 + theme.id * 3) % 28)
                let timeAngle = CGFloat((index * 89 + theme.id * 137) % 360)
                    * .pi / 180
                let timeRadius = 0.07 + age / 28 * 0.34
                let bright = index == 0 || index % 4 == 1
                output.append(
                    NativeConstellationStar(
                        id: "theme:\(theme.id):\(index)",
                        themeIndex: theme.id,
                        title: "Personal Model 推断",
                        detail: theme.face.text,
                        source: theme.face.source ?? "Personal Model",
                        reference: bright ? theme.face.evidenceRefs?.first : nil,
                        x: theme.x + cos(angle) * radius,
                        y: theme.y + sin(angle) * radius * 0.85,
                        timeX: 0.5 + cos(timeAngle) * timeRadius,
                        timeY: 0.46 + sin(timeAngle) * timeRadius * 0.8,
                        age: age,
                        isBright: bright,
                        isBig: index == 0,
                        isAmbient: false
                    )
                )
            }
        }
        for index in 0..<18 {
            output.append(
                NativeConstellationStar(
                    id: "ambient:\(index)",
                    themeIndex: nil,
                    title: "",
                    detail: "",
                    source: "",
                    reference: nil,
                    x: CGFloat((index * 137) % 99) / 100 + 0.005,
                    y: CGFloat((index * 71) % 92) / 100 + 0.04,
                    timeX: CGFloat((index * 137) % 99) / 100 + 0.005,
                    timeY: CGFloat((index * 71) % 92) / 100 + 0.04,
                    age: 20,
                    isBright: false,
                    isBig: false,
                    isAmbient: true
                )
            )
        }
        return output
    }

    private var rootStar: NativeConstellationStar {
        NativeConstellationStar(
            id: "root",
            themeIndex: nil,
            title: "ROOT · 我是谁",
            detail: snapshot.personalModel?.root?.trimmedNonEmpty
                ?? "Personal Model 正在形成对你的长期理解。",
            source: "Personal Model · 当前快照",
            reference: nil,
            x: 0.5,
            y: 0.45,
            timeX: 0.5,
            timeY: 0.46,
            age: 0,
            isBright: true,
            isBig: true,
            isAmbient: false
        )
    }

    private var focusedThemeIndex: Int? { selectedStar?.themeIndex }

    private var legend: String {
        switch mode {
        case .constellation:
            return "星 = 记忆段 · 线 = 同一件事 · 星座 = 主题"
        case .dust:
            return "只看密度 — 颜色是主题，哪里亮，日子就长在哪里"
        case .time:
            return "由内向外 = 从最近到更早 · 新记忆亮，旧记忆暗"
        }
    }

    private var memoryCountLabel: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: snapshot.personalModel?.memoryCount ?? 0))
            ?? "0"
    }

    private var liveLabel: String {
        snapshot.model.status?.lowercased() == "online"
            ? "LIVE · 本机模型"
            : "本机模型"
    }

    private func position(
        for star: NativeConstellationStar,
        in size: CGSize
    ) -> CGPoint {
        let x = mode == .time ? star.timeX : star.x
        let y = mode == .time ? star.timeY : star.y
        return CGPoint(x: x * size.width, y: y * size.height)
    }

    private func color(for star: NativeConstellationStar) -> Color {
        guard let index = star.themeIndex, themes.indices.contains(index) else {
            return Color(red: 0.92, green: 0.93, blue: 0.98)
        }
        return themes[index].color
    }

    private func opacity(for star: NativeConstellationStar) -> Double {
        guard
            let focusedThemeIndex,
            let starTheme = star.themeIndex,
            focusedThemeIndex != starTheme
        else { return 1 }
        return 0.16
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RadialGradient(
                    colors: [
                        Color(red: 0.082, green: 0.082, blue: 0.106),
                        Color(red: 0.031, green: 0.031, blue: 0.043),
                    ],
                    center: UnitPoint(x: 0.5, y: 0),
                    startRadius: 0,
                    endRadius: max(proxy.size.width, proxy.size.height) * 1.1
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedStar = nil
                    skyCorrection = ""
                }

                RadialGradient(
                    colors: [
                        Color(red: 0.47, green: 0.55, blue: 0.86).opacity(0.07),
                        .clear,
                    ],
                    center: UnitPoint(x: 0.5, y: 0.42),
                    startRadius: 0,
                    endRadius: min(proxy.size.width, proxy.size.height) * 0.70
                )
                .allowsHitTesting(false)

                if mode != .time {
                    ForEach(themes) { theme in
                        Ellipse()
                            .fill(
                                RadialGradient(
                                    colors: [theme.color.opacity(0.13), .clear],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 100
                                )
                            )
                            .frame(
                                width: CGFloat(theme.size) * 14 + 90,
                                height: CGFloat(theme.size) * 10 + 70
                            )
                            .blur(radius: 6)
                            .position(
                                x: theme.x * proxy.size.width,
                                y: theme.y * proxy.size.height
                            )
                            .allowsHitTesting(false)
                    }
                }

                constellation(in: proxy.size)
                    .rotation3DEffect(
                        .degrees(threeD ? Double(skyTilt.height / 12) : 0),
                        axis: (x: 1, y: 0, z: 0),
                        perspective: 0.45
                    )
                    .rotation3DEffect(
                        .degrees(threeD ? Double(-skyTilt.width / 12) : 0),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.45
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if threeD { skyTilt = value.translation }
                            }
                            .onEnded { _ in
                                withAnimation(.spring(response: 0.4)) { skyTilt = .zero }
                            }
                    )

                topControls

                footer

                if let selectedStar {
                    VStack {
                        Spacer()
                        starPanel(selectedStar)
                            .frame(width: min(480, proxy.size.width * 0.88))
                            .padding(.bottom, 52)
                    }
                }

                VStack {
                    Spacer()
                    returnToCard.padding(.bottom, 18)
                }
            }
        }
        .ignoresSafeArea()
        .focusable()
        .onMoveCommand(perform: moveSelection)
        .onExitCommand {
            withAnimation(.easeOut(duration: 0.2)) { state.isMemorySkyOpen = false }
        }
        .accessibilityElement(children: .contain)
    }

    private func constellation(in size: CGSize) -> some View {
        ZStack {
            Canvas { context, canvasSize in
                guard mode == .constellation else { return }
                let root = CGPoint(x: canvasSize.width * 0.5, y: canvasSize.height * 0.45)
                for theme in themes {
                    let hubs = skyStars.filter {
                        $0.themeIndex == theme.id && $0.isBright
                    }.prefix(5)
                    var previous = root
                    for (index, hub) in hubs.enumerated() {
                        let point = position(for: hub, in: canvasSize)
                        var path = Path()
                        path.move(to: previous)
                        path.addLine(to: point)
                        let isFocused = focusedThemeIndex == theme.id
                        let isDimmed = focusedThemeIndex != nil && !isFocused
                        context.stroke(
                            path,
                            with: .color(
                                theme.color.opacity(
                                    isDimmed ? 0.05 : isFocused ? 0.85 : 0.30
                                )
                            ),
                            lineWidth: index == 0 ? 0.65 : isFocused ? 1.35 : 0.82
                        )
                        previous = point
                    }
                }
            }

            ForEach(skyStars) { star in
                skyStar(star)
                    .position(position(for: star, in: size))
                    .opacity(opacity(for: star))
                    .animation(.easeInOut(duration: 0.65), value: mode)
                    .animation(.easeOut(duration: 0.28), value: selectedStar?.id)
            }

            Button {
                selectedStar = rootStar
                skyCorrection = ""
            } label: {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                .white,
                                Color(red: 0.78, green: 0.82, blue: 1.0).opacity(0.50),
                                Color(red: 0.78, green: 0.82, blue: 1.0).opacity(0.14),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 1,
                            endRadius: 14
                        )
                    )
                    .frame(width: 30, height: 30)
                    .shadow(
                        color: selectedStar?.id == "root"
                            ? Color(red: 0.78, green: 0.82, blue: 1.0).opacity(0.40)
                            : .clear,
                        radius: 12
                    )
            }
            .buttonStyle(.plain)
            .position(
                x: size.width * 0.5,
                y: size.height * (mode == .time ? 0.46 : 0.45)
            )
            .accessibilityLabel("ROOT · 我是谁")

            if mode == .constellation {
                ForEach(themes) { theme in
                    Button {
                        selectedStar = skyStars.first {
                            $0.themeIndex == theme.id && $0.isBright
                        }
                        skyCorrection = ""
                    } label: {
                        VStack(spacing: 2) {
                            Text(theme.face.text)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(theme.color)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .shadow(color: .black.opacity(0.9), radius: 5, y: 1)
                            Text("\(theme.face.observations ?? 0) observations")
                                .font(.system(size: 8.5, design: .monospaced))
                                .tracking(0.7)
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        .frame(width: 260)
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: theme.x * size.width,
                        y: (theme.y - (theme.id == 0 ? 0.17 : 0.12)) * size.height
                    )
                    .opacity(
                        focusedThemeIndex == nil || focusedThemeIndex == theme.id
                            ? 1
                            : 0.15
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func skyStar(_ star: NativeConstellationStar) -> some View {
        let tint = color(for: star)
        if star.isBright {
            Button {
                selectedStar = star
                skyCorrection = ""
            } label: {
                Circle()
                    .fill(
                        RadialGradient(
                            stops: [
                                .init(color: tint.opacity(0.96 - Double(star.age / 80)), location: 0.16),
                                .init(color: tint.opacity(0.42), location: 0.30),
                                .init(color: tint.opacity(0.10), location: 0.62),
                                .init(color: .clear, location: 1),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 11
                        )
                    )
                    .frame(width: 22, height: 22)
                    .overlay {
                        if selectedStar?.id == star.id {
                            Circle().stroke(tint.opacity(0.70), lineWidth: 1)
                        }
                    }
                    .shadow(
                        color: selectedStar?.id == star.id ? tint.opacity(0.40) : .clear,
                        radius: 10
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(star.title)：\(star.detail)")
        } else {
            Circle()
                .fill(
                    tint.opacity(
                        star.isAmbient ? 0.30 : Double(0.4 + (1 - star.age / 28) * 0.5)
                    )
                )
                .frame(
                    width: star.isAmbient ? 1.3 : 2,
                    height: star.isAmbient ? 1.3 : 2
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var topControls: some View {
        VStack {
            ZStack(alignment: .top) {
                HStack {
                    Text("MEMORY SKY · \(memoryCountLabel) · \(liveLabel)")
                        .font(.system(size: 9.5, design: .monospaced))
                        .tracking(2.1)
                        .foregroundStyle(.white.opacity(0.40))
                    Spacer()
                    Button(threeD ? "2D" : "3D ⤢") {
                        withAnimation(.spring(response: 0.35)) {
                            threeD.toggle()
                            skyTilt = .zero
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9.5, design: .monospaced))
                    .tracking(2.1)
                    .foregroundStyle(.white.opacity(0.50))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                HStack(spacing: 2) {
                    ForEach(NativeSkyMode.allCases) { candidate in
                        Button {
                            withAnimation(.easeInOut(duration: 0.24)) { mode = candidate }
                        } label: {
                            Text(candidate.rawValue)
                                .font(.system(size: 11.5, weight: mode == candidate ? .semibold : .regular))
                                .foregroundStyle(mode == candidate ? Color.black : Color.white.opacity(0.60))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 5)
                                .background(
                                    mode == candidate ? Color.white.opacity(0.96) : .clear,
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(.white.opacity(0.07), in: Capsule())
                .padding(.top, 14)
            }
            Spacer()
        }
        .allowsHitTesting(true)
    }

    private var footer: some View {
        VStack {
            Spacer()
            HStack(alignment: .bottom) {
                Text(legend)
                    .foregroundStyle(.white.opacity(0.40))
                Spacer(minLength: 170)
                Text("亮星可点 · ← → 巡星 · 点星座名查看模型推断")
                    .foregroundStyle(.white.opacity(0.30))
                    .multilineTextAlignment(.trailing)
            }
            .font(.system(size: 9.5, design: .monospaced))
            .tracking(0.9)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .allowsHitTesting(false)
    }

    private func starPanel(_ star: NativeConstellationStar) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(star.title.uppercased())
                    .tracking(2.7)
                Spacer()
                Text("← → 巡星")
                    .tracking(0.5)
                Button("×") {
                    selectedStar = nil
                    skyCorrection = ""
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
            }
            .font(.system(size: 8.5, design: .monospaced))
            .foregroundStyle(.white.opacity(0.45))
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) {
                Rectangle().fill(.white.opacity(0.10)).frame(height: 1)
            }

            Text(star.detail)
                .font(.system(size: 13.5, design: .serif))
                .lineSpacing(6)
                .foregroundStyle(.white.opacity(0.96))
                .padding(.top, 11)
                .lineLimit(5)

            HStack(alignment: .firstTextBaseline, spacing: 11) {
                Text(
                    [star.source, star.reference]
                        .compactMap { $0?.trimmedNonEmpty }
                        .joined(separator: " · ")
                )
                .lineLimit(1)
                Spacer()
                if let reference = star.reference {
                    Button("出处") { Task { await state.loadEvidence(reference) } }
                } else {
                    Text("尚无 Evidence")
                        .foregroundStyle(.orange.opacity(0.82))
                }
                Button("改写") { skyCorrection = star.detail }
                Button("行动") {
                    state.isMemorySkyOpen = false
                    state.selectedSection = .connectors
                }
                Button("分享 ↗") { state.openShare(highlight: star.detail) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.white.opacity(0.45))
            .padding(.top, 12)

            if !skyCorrection.isEmpty {
                HStack(spacing: 8) {
                    TextField("不对的话，改写它 ⏎", text: $skyCorrection)
                        .textFieldStyle(.plain)
                        .foregroundStyle(.white)
                        .onSubmit { Task { await state.correct(skyCorrection) } }
                    Button(state.isCorrecting ? "写入中…" : "写入") {
                        Task { await state.correct(skyCorrection) }
                    }
                    .disabled(state.isCorrecting)
                }
                .font(.system(size: 11.5))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.14)))
                .padding(.top, 9)
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 14)
        .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.60), radius: 28, y: 16)
    }

    private var returnToCard: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { state.isMemorySkyOpen = false }
        } label: {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.28, green: 0.28, blue: 0.31), Color(red: 0.14, green: 0.14, blue: 0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 20, height: 13)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(.white.opacity(0.24), lineWidth: 0.5))
                Text("回到卡")
                    .font(.system(size: 12.5, weight: .medium))
                Text("esc")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }
            .foregroundStyle(.white.opacity(0.96))
            .padding(.leading, 12)
            .padding(.trailing, 18)
            .padding(.vertical, 8)
            .background(.black.opacity(0.84), in: Capsule())
            .shadow(color: .black.opacity(0.50), radius: 17, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("回到 Personal Card")
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let candidates = skyStars.filter(\.isBright)
        guard !candidates.isEmpty else { return }
        let current = selectedStar.flatMap { selected in
            candidates.firstIndex(where: { $0.id == selected.id })
        } ?? -1
        switch direction {
        case .left, .up:
            selectedStar = candidates[(current - 1 + candidates.count) % candidates.count]
        case .right, .down:
            selectedStar = candidates[(current + 1) % candidates.count]
        default:
            break
        }
        skyCorrection = ""
    }
}

private func stableUnit(_ value: String, salt: UInt64) -> CGFloat {
    var hash: UInt64 = 14_695_981_039_346_656_037 ^ salt
    for byte in value.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return CGFloat(hash % 10_000) / 10_000
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
    let openItem: () -> Void

    private var kindLabel: String {
        let normalized = item.kind.lowercased()
        if item.isFutureLike || ["future", "suggestion", "未来"].contains(normalized) {
            return "未来"
        }
        if ["past", "rewind", "回溯", "过去"].contains(normalized) {
            return "过去"
        }
        if ["present", "continue", "继续", "现在"].contains(normalized) {
            return "现在"
        }
        return item.kind
    }

    private var kindMarker: String {
        switch kindLabel {
        case "过去": return "↶"
        case "未来": return "○"
        default: return "—"
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            NativeActivityIcon(text: "\(item.title) \(item.why ?? "")")
                .frame(width: 34, alignment: .leading)
            HStack(spacing: 5) {
                Text(kindMarker)
                    .font(.system(size: 15, design: .serif))
                Text(kindLabel)
                    .font(.system(size: 10.5))
            }
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayTitle)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                if let why = item.why?.trimmedNonEmpty {
                    Text(why)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if !item.isFutureLike, let when = item.when?.trimmedNonEmpty {
                Text(when)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture(perform: openItem)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { openItem() }
        .accessibilityElement(children: .contain)
        .accessibilityHint(
            [item.truthMetadata.kind.label, item.truthMetadata.detail]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        )
    }
}

private struct NativeActivityIcon: View {
    let text: String

    private var icon: NSImage? {
        let lower = text.lowercased()
        let fileName: String
        if lower.contains("google chrome") || lower.contains("chrome") {
            fileName = "chrome.png"
        } else if lower.contains("chatgpt") || lower.contains("codex") {
            fileName = "chatgpt.png"
        } else if lower.contains("wechat") || lower.contains("微信") {
            fileName = "wechat.png"
        } else if lower.contains("feishu") || lower.contains("lark") || lower.contains("飞书") {
            fileName = "lark.png"
        } else if lower.contains("claude") {
            fileName = "claude.png"
        } else if lower.contains("terminal") || lower.contains("终端") {
            fileName = "terminal.png"
        } else if lower.contains("finder") || lower.contains("访达") {
            fileName = "finder.png"
        } else if lower.contains("notes") || lower.contains("备忘录") {
            fileName = "notes.png"
        } else if lower.contains("coast") {
            fileName = "coast.png"
        } else {
            return nil
        }
        if let resourceURL = Bundle.main.resourceURL {
            let bundledPath = resourceURL
                .appendingPathComponent("AppIcons", isDirectory: true)
                .appendingPathComponent(fileName)
                .path
            if let image = NSImage(contentsOfFile: bundledPath) {
                return image
            }
        }
        guard let root = Bundle.main.object(
            forInfoDictionaryKey: "WhoAmIProductRoot"
        ) as? String else { return nil }
        let productPath = URL(fileURLWithPath: root, isDirectory: true)
            .appendingPathComponent(
                "apps/personal-card/assets/app-icons",
                isDirectory: true
            )
            .appendingPathComponent(fileName)
            .path
        return NSImage(contentsOfFile: productPath)
    }

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.black.opacity(0.035))
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.58), lineWidth: 1.4)
                            .frame(width: 9, height: 9)
                    )
            }
        }
        .frame(width: 29, height: 29)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.black.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.07), radius: 2, y: 1)
        .accessibilityHidden(true)
    }
}

private struct NativeIdentityView: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot
    @State private var selectedLine: String?
    @State private var editingProfile = false
    @State private var profileName = ""
    @State private var profileHandle = ""
    @State private var profileTagline = ""
    @State private var profileDescription = ""

    var body: some View {
        NativePaper {
            VStack(alignment: .leading, spacing: 30) {
                HStack {
                    Text("\(snapshot.model.displayName)'s space  /  Identity")
                    Spacer()
                    Text("由 Personal Model 生成 · as of now")
                    Button("编辑身份") { beginEditingProfile() }
                        .buttonStyle(.borderless)
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
                            Button {
                                selectedLine = selectedLine == dailyLine ? nil : dailyLine
                            } label: {
                                Text(dailyLine)
                                    .font(.body)
                                    .lineSpacing(8)
                                    .underline(selectedLine == dailyLine, color: .primary.opacity(0.6))
                                    .multilineTextAlignment(.leading)
                            }
                            .buttonStyle(.plain)
                            if selectedLine == dailyLine {
                                Button("划线分享 ↗") {
                                    copyText(dailyLine)
                                    state.openShare(highlight: dailyLine)
                                }
                                .buttonStyle(.borderless)
                                .font(.caption)
                            }
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
                                VStack(alignment: .leading, spacing: 7) {
                                    Button {
                                        selectedLine = selectedLine == line ? nil : line
                                    } label: {
                                        Text(line)
                                            .font(.body)
                                            .underline(selectedLine == line, color: .primary.opacity(0.6))
                                            .multilineTextAlignment(.leading)
                                    }
                                    .buttonStyle(.plain)
                                    if selectedLine == line {
                                        Button("划线分享 ↗") {
                                            copyText(line)
                                            state.openShare(highlight: line)
                                        }
                                        .buttonStyle(.borderless)
                                        .font(.caption)
                                    }
                                }
                                .padding(.bottom, 11)
                                .overlay(alignment: .bottom) { Divider() }
                            }
                        }
                    }
                }
                HStack {
                    Text("SAME MODEL · PRIVATE INSIDE / PUBLIC OUTSIDE")
                        .font(.caption2.monospaced())
                        .tracking(1.3)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("回到分享卡") { state.openShare() }
                        .buttonStyle(.borderless)
                }
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: $editingProfile) {
            VStack(alignment: .leading, spacing: 16) {
                Text("这张卡应该是谁？")
                    .font(.title2.weight(.semibold))
                Text("只修改当前 Mac 用户的 Card 身份，不会删除 Personal Model、Rewind 或 Evidence。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("你的名字", text: $profileName)
                TextField("@handle", text: $profileHandle)
                TextField("一句话：你正在做什么", text: $profileTagline)
                TextField("简单介绍你自己", text: $profileDescription)
                HStack {
                    Button("取消", role: .cancel) { editingProfile = false }
                    Spacer()
                    Button("保存为我的 Card") {
                        Task {
                            await state.saveProfile(
                                displayName: profileName,
                                handle: profileHandle,
                                tagline: profileTagline,
                                description: profileDescription
                            )
                            editingProfile = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .textFieldStyle(.roundedBorder)
            .padding(28)
            .frame(width: 480)
        }
    }

    private func beginEditingProfile() {
        profileName = snapshot.model.displayName
        profileHandle = snapshot.model.handle
        profileTagline = snapshot.card?.tagline ?? ""
        profileDescription = snapshot.identity?.description ?? ""
        editingProfile = true
    }
}

private func copyText(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
}

private enum NativeRewindScreen: String {
    case year
    case month
    case day
}

private struct NativeRewindView: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot
    @State private var screen: NativeRewindScreen = .month
    @State private var selectedDayID: String?
    @State private var selectedEventIndex = 0
    @State private var monthSearch = ""
    @State private var daySearch = ""
    @State private var isDayRootSelected = false
    @FocusState private var monthSearchFocused: Bool

    private var days: [DaySnapshot] { snapshot.time?.days ?? [] }

    private var selectedDay: DaySnapshot? {
        if let selectedDayID, let match = days.first(where: { $0.id == selectedDayID }) {
            return match
        }
        return days.first
    }

    private var referenceDate: Date {
        days.compactMap { nativeDayDate($0.id) }.max() ?? Date()
    }

    var body: some View {
        Group {
            switch screen {
            case .year:
                rewindYear
            case .month:
                rewindMonth
            case .day:
                if let selectedDay {
                    rewindDay(selectedDay)
                } else {
                    rewindMonth
                }
            }
        }
        .onAppear(perform: applyRequestedDay)
        .onChange(of: state.rewindDayRequest) { _ in applyRequestedDay() }
    }

    private func applyRequestedDay() {
        guard
            let requested = state.rewindDayRequest,
            days.contains(where: { $0.id == requested })
        else { return }
        selectedDayID = requested
        selectedEventIndex = 0
        daySearch = ""
        screen = .day
        state.rewindDayRequest = nil
    }

    private var rewindYear: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 12)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .lastTextBaseline, spacing: 18) {
                            Text("\(days.count) 天")
                                .font(.system(size: 46, weight: .bold))
                                .tracking(-1.3)
                            Text("每一天都回得去\n深浅 = 那天它看了多少")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Color.black.opacity(0.54))
                                .lineSpacing(5)
                            Spacer()
                            Text("你的记忆，不用你记")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.black.opacity(0.26))
                        }

                        NativeYearHeatmap(
                            days: days,
                            referenceDate: referenceDate,
                            select: openDay
                        )
                        .padding(.top, 30)

                        HStack(alignment: .center, spacing: 12) {
                            Text("只点亮当前 Personal Model 真正返回的可靠日期。")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Color.black.opacity(0.54))
                            Spacer()
                            Text("less")
                            ForEach([0.04, 0.22, 0.50, 0.92], id: \.self) { opacity in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.blue.opacity(opacity))
                                    .frame(width: 9, height: 9)
                            }
                            Text("more")
                        }
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(0.30))
                        .padding(.top, 20)
                    }
                    .padding(.horizontal, 34)
                    .padding(.top, 30)
                    .padding(.bottom, 26)
                    .frame(maxWidth: 880, alignment: .topLeading)
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.56), lineWidth: 0.7)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 30, y: 20)

                    Button("你的年报 · tap \(nativeMonthName(referenceDate).prefix(3)) to zoom back in") {
                        screen = .month
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color.black.opacity(0.28))
                    .padding(.top, 14)
                    Spacer(minLength: 64)
                }
                .padding(.horizontal, 40)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var rewindMonth: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 12)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Color.black.opacity(0.46))
                                .accessibilityHidden(true)
                            TextField("search memories…", text: $monthSearch)
                                .textFieldStyle(.plain)
                                .font(.system(size: 15))
                                .focused($monthSearchFocused)
                                .onSubmit(locateMonthSearch)
                                .accessibilityLabel("搜索 Rewind 记忆")
                            Button(action: locateMonthSearch) { EmptyView() }
                                .keyboardShortcut(.defaultAction)
                                .frame(width: 0, height: 0)
                                .opacity(0)
                                .accessibilityHidden(true)
                        }
                        .frame(height: 33)
                        .padding(.bottom, 14)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.black.opacity(0.07))
                                .frame(height: 1)
                        }

                        if monthSearchFocused {
                            NativeRewindFilters(
                                days: days,
                                select: openDay
                            )
                            .padding(.vertical, 12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Button("← \(nativeYearLabel(referenceDate))") { screen = .year }
                                .buttonStyle(.plain)
                                .font(.system(size: 10.5, design: .monospaced))
                                .tracking(0.8)
                                .foregroundStyle(Color.black.opacity(0.58))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .overlay(
                                    Capsule().stroke(Color.black.opacity(0.10), lineWidth: 1)
                                )
                            Text("时间 · \(nativeMonthName(referenceDate))")
                                .font(.system(size: 22, weight: .semibold))
                                .tracking(-0.45)
                            Spacer()
                            Button("日历与记忆星图") {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    state.isMemorySkyOpen = true
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.black.opacity(0.42))
                        }
                        .padding(.top, 16)
                        .padding(.bottom, 18)

                        HStack(alignment: .top, spacing: 24) {
                            NativeMonthCalendar(
                                referenceDate: referenceDate,
                                days: days,
                                futureItems: (snapshot.now?.items ?? []).filter {
                                    $0.isFutureLike && $0.hasReliableSuggestionSource
                                },
                                select: openDay
                            )
                            .frame(maxWidth: .infinity)

                            Rectangle()
                                .fill(Color.black.opacity(0.09))
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)

                            NativeRewindApps(
                                days: days,
                                themeCount: snapshot.personalModel?.faces?.count ?? 0,
                                select: openDay
                            )
                            .frame(width: 240)
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 24)
                    .padding(.bottom, 26)
                    .frame(maxWidth: 980, alignment: .topLeading)
                    .background(
                        .ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white.opacity(0.60), lineWidth: 0.7)
                    )
                    .shadow(color: .black.opacity(0.24), radius: 36, y: 24)
                    Spacer(minLength: 64)
                }
                .padding(.horizontal, 40)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func rewindDay(_ day: DaySnapshot) -> some View {
        GeometryReader { geometry in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("REWIND · MEMORY DOCUMENT")
                                .font(.system(size: 9, design: .monospaced))
                                .tracking(2.2)
                                .foregroundStyle(Color.black.opacity(0.42))
                            Text(day.title ?? day.id)
                                .font(.system(size: 42, weight: .medium, design: .serif))
                                .tracking(-1.2)
                                .padding(.top, 13)
                            if let portrait = day.portrait?.trimmedNonEmpty {
                                Text(portrait)
                                    .font(.system(size: 14.5))
                                    .foregroundStyle(Color.black.opacity(0.57))
                                    .lineSpacing(8)
                                    .padding(.top, 14)
                                    .frame(maxWidth: 760, alignment: .leading)
                            }

                            NativeDayModelUpdates(
                                state: state,
                                snapshot: snapshot,
                                day: day
                            )
                            .padding(.top, 31)

                            NativeRewindHighlights(
                                state: state,
                                day: day,
                                selectedEventIndex: $selectedEventIndex
                            )
                            .padding(.bottom, 34)

                            NativeRewindTelevision(
                                day: day,
                                modelID: snapshot.model.id,
                                selectedEventIndex: $selectedEventIndex
                            )

                            if let letter = day.letter?.trimmedNonEmpty {
                                let letterParts = nativeDayLetterParts(letter)
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack {
                                        Text("ROOT · 今天留下的一句")
                                            .font(.system(size: 9, design: .monospaced))
                                            .tracking(2)
                                            .foregroundStyle(Color.black.opacity(0.42))
                                        Spacer()
                                        Button("生成今日卡 ↗") {
                                            state.openShare(highlight: letterParts.root)
                                        }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(Color.black.opacity(0.58))
                                    }

                                    Button {
                                        isDayRootSelected.toggle()
                                    } label: {
                                        VStack(alignment: .leading, spacing: 9) {
                                            Text(letterParts.root)
                                                .font(.system(size: 21, design: .serif))
                                                .foregroundStyle(Color(red: 0.18, green: 0.17, blue: 0.15))
                                                .lineSpacing(9)
                                                .underline(
                                                    isDayRootSelected,
                                                    color: Color.black.opacity(0.65)
                                                )
                                            Text(letterParts.description)
                                                .font(.system(size: 13.5, design: .serif))
                                                .foregroundStyle(Color.black.opacity(0.48))
                                                .lineSpacing(8)
                                        }
                                        .frame(maxWidth: 800, alignment: .leading)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 15)

                                    if isDayRootSelected {
                                        Button("划线分享 ↗") {
                                            state.openShare(highlight: letterParts.root)
                                        }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(Color.black.opacity(0.58))
                                        .padding(.top, 12)
                                    }
                                }
                                .padding(.top, 30)
                                .overlay(alignment: .top) {
                                    Rectangle()
                                        .fill(Color.black.opacity(0.13))
                                        .frame(height: 1)
                                }
                                .padding(.top, 38)
                            }

                            Text(day.source?.trimmedNonEmpty ?? "Personal Model · \(snapshot.model.id)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Color.black.opacity(0.28))
                                .padding(.top, 30)
                        }
                        .padding(.horizontal, 38)
                        .padding(.top, 34)
                        .padding(.bottom, 42)
                        .frame(maxWidth: 1_036, alignment: .topLeading)
                        .frame(maxWidth: .infinity)
                    } header: {
                        NativeRewindDayBar(
                            day: day,
                            search: $daySearch,
                            availableWidth: min(1_220, geometry.size.width - 34),
                            back: { screen = .month },
                            submit: { locateEvent(in: day) }
                        )
                    }
                }
                .frame(width: min(1_220, max(760, geometry.size.width - 34)))
                .background(Color(nsColor: .textBackgroundColor).opacity(0.97))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.black.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 36, y: 22)
                .padding(.top, 14)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { state.isRewindDayOpen = true }
        .onDisappear { state.isRewindDayOpen = false }
    }

    private func locateEvent(in day: DaySnapshot) {
        let query = daySearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return }
        if let index = (day.events ?? []).firstIndex(where: { event in
            [event.time, event.title, event.detail, event.app]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(query) }
        }) {
            selectedEventIndex = index
        }
    }

    private func locateMonthSearch() {
        let query = monthSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return }
        if let day = days.first(where: { day in
            let dayText = [day.title, day.portrait, day.letter]
                .compactMap { $0 }
                .joined(separator: " ")
                .lowercased()
            if dayText.contains(query) { return true }
            return (day.events ?? []).contains { event in
                [event.title, event.detail, event.app]
                    .compactMap { $0 }
                    .joined(separator: " ")
                    .lowercased()
                    .contains(query)
            }
        }) {
            monthSearch = ""
            openDay(day)
        }
    }

    private func openDay(_ day: DaySnapshot) {
        selectedDayID = day.id
        selectedEventIndex = 0
        daySearch = ""
        isDayRootSelected = false
        monthSearchFocused = false
        screen = .day
    }
}

private struct NativeRewindDayBar: View {
    let day: DaySnapshot
    @Binding var search: String
    let availableWidth: CGFloat
    let back: () -> Void
    let submit: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 9) {
                Button(action: back) {
                    Text("‹")
                        .font(.system(size: 23, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.48))
                        .frame(width: 30, height: 30)
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("回到 Rewind 月份")

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.black.opacity(0.40))
                        .accessibilityHidden(true)
                    TextField("Search this day", text: $search)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .onSubmit(submit)
                    Text("↵")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.black.opacity(0.24))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 11)
                .frame(width: min(320, max(210, availableWidth * 0.36)), height: 34)
                .background(
                    Color(red: 0.965, green: 0.96, blue: 0.945),
                    in: RoundedRectangle(cornerRadius: 9)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Rewind")
                .font(.system(size: 14.5, weight: .semibold))
                .tracking(-0.2)

            Text(day.title ?? nativeCompactDayLabel(day.id))
                .font(.system(size: 11.5))
                .foregroundStyle(Color.black.opacity(0.48))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct NativeYearHeatmap: View {
    let days: [DaySnapshot]
    let referenceDate: Date
    let select: (DaySnapshot) -> Void

    private let calendar = Calendar(identifier: .gregorian)
    private let weekCount = 28
    private let gap: CGFloat = 5

    private var dayByID: [String: DaySnapshot] {
        Dictionary(uniqueKeysWithValues: days.map { ($0.id, $0) })
    }

    private var firstWeekStart: Date {
        let end = mondayStart(for: referenceDate)
        return calendar.date(byAdding: .weekOfYear, value: -(weekCount - 1), to: end) ?? end
    }

    var body: some View {
        GeometryReader { proxy in
            let cell = max(8, (proxy.size.width - CGFloat(weekCount - 1) * gap) / CGFloat(weekCount))
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: gap) {
                    ForEach(0..<weekCount, id: \.self) { week in
                        Text(monthLabel(for: week))
                            .font(.system(size: 9, design: .monospaced))
                            .tracking(0.6)
                            .foregroundStyle(Color.black.opacity(0.30))
                            .frame(width: cell, alignment: .leading)
                            .lineLimit(1)
                    }
                }

                HStack(alignment: .top, spacing: gap) {
                    ForEach(0..<weekCount, id: \.self) { week in
                        VStack(spacing: gap) {
                            ForEach(0..<7, id: \.self) { weekday in
                                heatCell(week: week, weekday: weekday, size: cell)
                            }
                        }
                    }
                }
            }
        }
        .frame(height: 215)
    }

    @ViewBuilder
    private func heatCell(week: Int, weekday: Int, size: CGFloat) -> some View {
        let date = calendar.date(
            byAdding: .day,
            value: week * 7 + weekday,
            to: firstWeekStart
        ) ?? firstWeekStart
        let day = dayByID[dayID(date)]
        let shape = RoundedRectangle(cornerRadius: 3)

        if let day {
            Button { select(day) } label: {
                shape
                    .fill(heatColor(day))
                    .frame(width: size, height: size)
                    .overlay(
                        shape.stroke(
                            calendar.isDateInToday(date)
                                ? Color.black.opacity(0.72)
                                : .clear,
                            lineWidth: 1
                        )
                    )
            }
            .buttonStyle(.plain)
            .help(day.title ?? day.id)
            .accessibilityLabel("\(day.id)，\(day.events?.count ?? 0) 条记录")
        } else {
            shape
                .fill(Color.black.opacity(0.025))
                .frame(width: size, height: size)
                .overlay(
                    shape.stroke(
                        calendar.isDateInToday(date)
                            ? Color.black.opacity(0.44)
                            : .clear,
                        lineWidth: 1
                    )
                )
                .accessibilityHidden(true)
        }
    }

    private func mondayStart(for date: Date) -> Date {
        let start = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: start)
        let offset = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -offset, to: start) ?? start
    }

    private func dayID(_ date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func monthLabel(for week: Int) -> String {
        guard let date = calendar.date(
            byAdding: .weekOfYear,
            value: week,
            to: firstWeekStart
        ) else { return "" }
        if week > 0,
           let previous = calendar.date(byAdding: .weekOfYear, value: week - 1, to: firstWeekStart),
           calendar.component(.month, from: previous) == calendar.component(.month, from: date) {
            return ""
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM"
        return formatter.string(from: date).uppercased()
    }

    private func heatColor(_ day: DaySnapshot) -> Color {
        let count = day.events?.count ?? 0
        return Color.blue.opacity(min(0.92, 0.16 + Double(count) * 0.12))
    }
}


private struct NativeFlowLayout: Layout {
    var spacing: CGFloat = 7

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let availableWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maximumWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let nextWidth = lineWidth == 0
                ? size.width
                : lineWidth + spacing + size.width
            if lineWidth > 0 && nextWidth > availableWidth {
                maximumWidth = max(maximumWidth, lineWidth)
                totalHeight += lineHeight + spacing
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth = nextWidth
                lineHeight = max(lineHeight, size.height)
            }
        }
        maximumWidth = max(maximumWidth, lineWidth)
        totalHeight += lineHeight
        return CGSize(
            width: availableWidth.isFinite ? availableWidth : maximumWidth,
            height: totalHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + spacing + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            } else if x > bounds.minX {
                x += spacing
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width
            lineHeight = max(lineHeight, size.height)
        }
    }
}

private struct NativeRewindFilters: View {
    let days: [DaySnapshot]
    let select: (DaySnapshot) -> Void

    private var recentDays: [DaySnapshot] {
        Array(days.sorted { $0.id > $1.id }.prefix(3))
    }

    private var recentApps: [(name: String, day: DaySnapshot)] {
        var seen = Set<String>()
        var output: [(String, DaySnapshot)] = []
        for day in days.sorted(by: { $0.id > $1.id }) {
            for event in day.events ?? [] {
                guard let app = event.app?.trimmedNonEmpty, seen.insert(app).inserted else {
                    continue
                }
                output.append((app, day))
                if output.count == 6 { return output }
            }
        }
        return output
    }

    var body: some View {
        NativeFlowLayout(spacing: 7) {
                ForEach(Array(recentDays.enumerated()), id: \.element.id) { index, day in
                    Button(index == 0 ? "最近一天" : nativeCompactDayLabel(day.id)) {
                        select(day)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.black.opacity(0.76))
                    .padding(.horizontal, 13)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.74), in: Capsule())
                    .overlay(Capsule().stroke(Color.black.opacity(0.08)))
                }

                if !recentDays.isEmpty && !recentApps.isEmpty {
                    Rectangle()
                        .fill(Color.black.opacity(0.09))
                        .frame(width: 1, height: 16)
                        .padding(.horizontal, 3)
                }

                ForEach(recentApps, id: \.name) { app in
                    Button {
                        select(app.day)
                    } label: {
                        HStack(spacing: 7) {
                            NativeActivityIcon(text: app.name)
                                .scaleEffect(0.76)
                                .frame(width: 22, height: 22)
                            Text(app.name).lineLimit(1)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(Color.black.opacity(0.76))
                        .padding(.leading, 5)
                        .padding(.trailing, 12)
                        .padding(.vertical, 4)
                        .background(.white.opacity(0.74), in: Capsule())
                        .overlay(Capsule().stroke(Color.black.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
        }
    }
}

private struct NativeMonthCalendar: View {
    let referenceDate: Date
    let days: [DaySnapshot]
    let futureItems: [NowItem]
    let select: (DaySnapshot) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let calendar = Calendar(identifier: .gregorian)

    private var dayByNumber: [Int: DaySnapshot] {
        Dictionary(uniqueKeysWithValues: days.compactMap { day in
            guard let date = nativeDayDate(day.id),
                  calendar.isDate(date, equalTo: referenceDate, toGranularity: .month)
            else { return nil }
            return (calendar.component(.day, from: date), day)
        })
    }

    private var futureByNumber: [Int: [NowItem]] {
        var output: [Int: [NowItem]] = [:]
        for item in futureItems {
            guard let dayID = item.dayId,
                  let date = nativeDayDate(dayID),
                  calendar.isDate(date, equalTo: referenceDate, toGranularity: .month)
            else { continue }
            output[calendar.component(.day, from: date), default: []].append(item)
        }
        return output
    }

    private var cells: [Int?] {
        guard let interval = calendar.dateInterval(of: .month, for: referenceDate) else { return [] }
        let count = calendar.range(of: .day, in: .month, for: referenceDate)?.count ?? 30
        let weekday = calendar.component(.weekday, from: interval.start)
        let mondayOffset = (weekday + 5) % 7
        var result = Array(repeating: Optional<Int>.none, count: mondayOffset)
        result.append(contentsOf: (1...count).map(Optional.some))
        while !result.count.isMultiple(of: 7) { result.append(nil) }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(0.10))
                .frame(height: 1)

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.system(size: 9, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(Color.black.opacity(0.28))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        .padding(.bottom, 6)
                }

                ForEach(Array(cells.enumerated()), id: \.offset) { _, number in
                    if let number {
                        calendarDay(number)
                    } else {
                        Color.clear.frame(height: 52).accessibilityHidden(true)
                    }
                }
            }

            HStack(spacing: 16) {
                HStack(spacing: 5) {
                    Circle().fill(Color(red: 0.17, green: 0.17, blue: 0.18))
                        .frame(width: 3, height: 3)
                    Text("留下过记忆")
                }
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2.5)
                        .stroke(Color.black.opacity(0.88), lineWidth: 1.2)
                        .frame(width: 8, height: 8)
                    Text("今天")
                }
                HStack(spacing: 5) {
                    VStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { _ in
                            Capsule().fill(Color.black.opacity(0.48))
                                .frame(width: 8, height: 1)
                        }
                    }
                    Text("明天的影子")
                }
                Spacer()
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Color.black.opacity(0.28))
            .padding(.top, 16)
        }
    }

    @ViewBuilder
    private func calendarDay(_ number: Int) -> some View {
        let day = dayByNumber[number]
        let future = futureByNumber[number] ?? []
        let today = isToday(number)

        if let day {
            Button { select(day) } label: {
                dayLabel(number, hasMemory: true, futureCount: future.count, isToday: today)
            }
            .buttonStyle(.plain)
            .help(day.portrait ?? day.title ?? day.id)
            .accessibilityLabel("\(number)，留下过记忆\(today ? "，今天" : "")")
        } else {
            dayLabel(number, hasMemory: false, futureCount: future.count, isToday: today)
                .help(future.first?.displayTitle ?? (today ? "今天" : "没有记录"))
                .accessibilityLabel(
                    future.isEmpty
                        ? "\(number)\(today ? "，今天" : "，没有记录")"
                        : "\(number)，有来源的延续建议"
                )
        }
    }

    private func dayLabel(
        _ number: Int,
        hasMemory: Bool,
        futureCount: Int,
        isToday: Bool
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 3) {
                Text("\(number)")
                    .font(.system(size: 12, weight: hasMemory || futureCount > 0 || isToday ? .semibold : .regular))
                    .foregroundStyle(
                        hasMemory
                            ? Color.white
                            : futureCount > 0
                                ? Color.black.opacity(0.66)
                                : isToday
                                    ? Color.black.opacity(0.88)
                                    : Color.black.opacity(0.28)
                    )
                    .frame(width: 26, height: 26)
                    .background(
                        hasMemory ? Color(red: 0.17, green: 0.17, blue: 0.18) : .clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                futureCount > 0 && !hasMemory
                                    ? Color.black.opacity(0.22)
                                    : isToday && !hasMemory
                                        ? Color.black.opacity(0.88)
                                        : .clear,
                                lineWidth: isToday && !hasMemory ? 1.5 : 1
                            )
                    )
                    .shadow(
                        color: hasMemory ? Color.black.opacity(0.28) : .clear,
                        radius: 7,
                        y: 4
                    )
                Circle()
                    .fill(isToday ? Color.black.opacity(0.9) : .clear)
                    .frame(width: 3, height: 3)
            }

            if futureCount > 0 {
                VStack(spacing: 2) {
                    ForEach(0..<min(3, futureCount), id: \.self) { _ in
                        Capsule().fill(Color.black.opacity(0.48))
                            .frame(width: 7, height: 1)
                    }
                }
                .padding(.top, 7)
                .padding(.trailing, 5)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .contentShape(RoundedRectangle(cornerRadius: 9))
    }

    private func isToday(_ number: Int) -> Bool {
        guard let month = calendar.dateInterval(of: .month, for: referenceDate),
              let date = calendar.date(byAdding: .day, value: number - 1, to: month.start)
        else { return false }
        return calendar.isDateInToday(date)
    }
}

private struct NativeRewindApps: View {
    let days: [DaySnapshot]
    let themeCount: Int
    let select: (DaySnapshot) -> Void

    private var rows: [(app: String, count: Int, day: DaySnapshot)] {
        var counts: [String: (Int, DaySnapshot)] = [:]
        for day in days {
            for event in day.events ?? [] {
                let app = event.app?.trimmedNonEmpty ?? "Personal Model"
                let previous = counts[app]?.0 ?? 0
                counts[app] = (previous + 1, day)
            }
        }
        return counts
            .map { ($0.key, $0.value.0, $0.value.1) }
            .sorted {
                if $0.count == $1.count { return $0.app < $1.app }
                return $0.count > $1.count
            }
    }

    private var note: String {
        guard themeCount > 0 else {
            return "等待 Personal Model 返回个人主题。"
        }
        let recentDayCount = min(7, Set(days.map(\.id)).count)
        return "\(themeCount) 个实时主题 · 来自最近 \(recentDayCount) 个有记录日期的 Personal Model 活动；数量只表示当前记录密度。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("最近围绕的事")
                .font(.system(size: 9.5, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(Color.black.opacity(0.42))
            Text("不是另一张图表。它只是让你看见，这个月的时间流向了哪里。")
                .font(.system(size: 12))
                .foregroundStyle(Color.black.opacity(0.40))
                .lineSpacing(5)
                .padding(.top, 8)
                .padding(.bottom, 13)

            ForEach(Array(rows.prefix(6)), id: \.app) { row in
                Button { select(row.day) } label: {
                    HStack(spacing: 10) {
                        NativeActivityIcon(text: row.app)
                        Text(row.app)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(Color.black.opacity(0.82))
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(row.count) 段")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Color.black.opacity(0.42))
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
                    }
                }
                .buttonStyle(.plain)
            }

            Text(note)
                .font(.system(size: 13, design: .serif))
                .foregroundStyle(Color.black.opacity(0.58))
                .lineSpacing(7)
                .padding(.top, 14)
                .overlay(alignment: .top) {
                    Rectangle().fill(Color.black.opacity(0.10)).frame(height: 1)
                }
        }
    }
}


private struct NativeRewindHighlights: View {
    @ObservedObject var state: PersonalModelAppState
    let day: DaySnapshot
    @Binding var selectedEventIndex: Int

    private var highlights: [(index: Int, event: EventSnapshot)] {
        var seen = Set<String>()
        var output: [(Int, EventSnapshot)] = []
        for (index, event) in (day.events ?? []).enumerated() {
            let key = "\(event.title)|\(event.detail ?? "")"
                .lowercased()
                .replacingOccurrences(
                    of: #"personal card|who am i|persome|实时内容|当前任务|工作流|继续整理|继续处理|[\s·，。！？、:：;；\-—_()[\]（）]+"#,
                    with: "",
                    options: [.regularExpression, .caseInsensitive]
                )
            guard seen.insert(key).inserted else { continue }
            output.append((index, event))
        }
        return output
    }

    var body: some View {
        if !highlights.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("值得回去的瞬间")
                        .font(.system(size: 18, weight: .semibold))
                        .tracking(-0.35)
                    Text("每件事只出现一次 · 点一下回到画面")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.black.opacity(0.34))
                    Spacer()
                }
                .padding(.bottom, 8)

                ForEach(Array(highlights.enumerated()), id: \.element.event.id) { displayIndex, highlight in
                    HStack(alignment: .top, spacing: 13) {
                        Button {
                            selectedEventIndex = highlight.index
                        } label: {
                            HStack(alignment: .top, spacing: 13) {
                                Text(highlight.event.time ?? "—")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(Color.black.opacity(0.42))
                                    .frame(width: 44, alignment: .leading)
                                    .padding(.top, 2)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(highlight.event.title)
                                        .font(.system(size: 13.5, weight: .medium))
                                        .foregroundStyle(Color.black.opacity(0.84))
                                    Text(highlight.event.detail?.trimmedNonEmpty ?? "这条记录没有附加描述。")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Color.black.opacity(0.42))
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(String(format: "%02d", displayIndex + 1)) ↗")
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundStyle(Color.black.opacity(0.28))
                                    .padding(.top, 2)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if let reference = highlight.event.evidenceRef {
                            Button("✦ 证据") {
                                Task { await state.loadEvidence(reference) }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.black.opacity(0.58))
                            .padding(.top, 1)
                        }
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Color.black.opacity(0.09)).frame(height: 1)
                    }
                }
            }
        }
    }
}

private struct NativeDayModelUpdates: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot
    let day: DaySnapshot
    @State private var selectedUpdateID: String?

    private struct Update: Identifiable {
        let id: String
        let kind: String
        let title: String
        let text: String
        let evidenceReference: String?
    }

    private var updates: [Update] {
        let evidenceReference = (day.events ?? []).compactMap(\.evidenceRef).first
        return [
            Update(
                id: "face",
                kind: "FACE · 面",
                title: "今天的你",
                text: snapshot.identity?.dailyLine?.trimmedNonEmpty
                    ?? day.portrait?.trimmedNonEmpty
                    ?? "",
                evidenceReference: evidenceReference
            ),
            Update(
                id: "volume",
                kind: "VOLUME · 体",
                title: "今天长出来的关系",
                text: day.portrait?.trimmedNonEmpty ?? "",
                evidenceReference: evidenceReference
            ),
            Update(
                id: "root",
                kind: "ROOT · 根",
                title: "根上新增的一句话",
                text: day.letter?.trimmedNonEmpty.map {
                    nativeDayLetterParts($0).root
                } ?? "",
                evidenceReference: evidenceReference
            ),
        ].filter { !$0.text.isEmpty }
    }

    var body: some View {
        if !updates.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("今天写进 Personal Model")
                        .font(.system(size: 18, weight: .semibold))
                        .tracking(-0.35)
                    Spacer()
                    Text(selectedUpdateID == nil ? "点一句划线" : "已划线 · 点右侧生成分享卡")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.black.opacity(0.34))
                }
                .padding(.top, 25)
                .padding(.bottom, 8)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.black.opacity(0.13))
                        .frame(height: 1)
                }

                ForEach(updates) { update in
                    HStack(alignment: .top, spacing: 18) {
                        Text(update.kind)
                            .font(.system(size: 9, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(Color.black.opacity(0.42))
                            .frame(width: 88, alignment: .leading)
                            .padding(.top, 3)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(update.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.black.opacity(0.78))
                            Text(update.text)
                                .font(.system(size: 15.5, design: .serif))
                                .foregroundStyle(Color.black.opacity(0.66))
                                .lineSpacing(7)
                                .underline(
                                    selectedUpdateID == update.id,
                                    color: Color.black.opacity(0.62)
                                )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .trailing, spacing: 8) {
                            if let reference = update.evidenceReference {
                                Button("溯源 ↗") {
                                    Task { await state.loadEvidence(reference) }
                                }
                                .buttonStyle(.plain)
                            }
                            if selectedUpdateID == update.id {
                                Button("划线分享 ↗") {
                                    state.openShare(highlight: update.text)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.black.opacity(0.58))
                    }
                    .padding(.vertical, 16)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedUpdateID = selectedUpdateID == update.id ? nil : update.id
                    }
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color.black.opacity(0.09))
                            .frame(height: 1)
                    }
                }
            }
            .padding(.bottom, 36)
        }
    }
}

private struct NativeRewindTelevision: View {
    let day: DaySnapshot
    let modelID: String
    @Binding var selectedEventIndex: Int

    private var events: [EventSnapshot] { day.events ?? [] }

    private var currentIndex: Int {
        guard !events.isEmpty else { return 0 }
        return min(max(0, selectedEventIndex), events.count - 1)
    }

    private var selectedEvent: EventSnapshot? {
        guard !events.isEmpty else { return nil }
        return events[currentIndex]
    }

    private var appRows: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for event in events {
            counts[event.app?.trimmedNonEmpty ?? "Personal Model", default: 0] += 1
        }
        return counts
            .map { ($0.key, $0.value) }
            .sorted {
                if $0.count == $1.count { return $0.name < $1.name }
                return $0.count > $1.count
            }
    }

    private var chapterLabel: String {
        "0 / 0"
    }

    private var momentTitle: String {
        day.title?.trimmedNonEmpty ?? day.id
    }

    private var momentDetail: String {
        selectedEvent?.detail?.trimmedNonEmpty
            ?? day.portrait?.trimmedNonEmpty
            ?? "这一天没有可展示的画面描述。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.16, green: 0.16, blue: 0.17),
                                    Color(red: 0.055, green: 0.055, blue: 0.065),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    VStack(spacing: 11) {
                        Text("Persome")
                            .font(.system(size: 9, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(.white.opacity(0.38))
                        Text("当天没有可用的画面")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white.opacity(0.94))
                            .multilineTextAlignment(.center)
                        Text(momentDetail)
                            .font(.system(size: 13))
                            .lineSpacing(6)
                            .foregroundStyle(.white.opacity(0.54))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 560)
                    }
                    .padding(40)

                    VStack {
                        HStack {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.white.opacity(0.84))
                                    .frame(width: 6, height: 6)
                                Text("Persome")
                                    .font(.system(size: 11.5, weight: .medium))
                                Text("—")
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                            Spacer()
                        }
                        Spacer()
                        HStack(spacing: 12) {
                            Text("当天没有可用的画面")
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Spacer()
                            Text(chapterLabel)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.48))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(.black.opacity(0.56), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                        )
                    }
                    .padding(12)
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(minHeight: 300)
                .padding(10)

                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Circle().fill(Color.white.opacity(0.72)).frame(width: 5, height: 5)
                        Text("WHO AM I · REWIND")
                    }
                    Text("CH \(chapterLabel)")
                        .foregroundStyle(.white.opacity(0.26))
                    Spacer()
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(3), spacing: 3), count: 6),
                        spacing: 3
                    ) {
                        ForEach(0..<12, id: \.self) { _ in
                            Circle().fill(.black.opacity(0.55)).frame(width: 3, height: 3)
                        }
                    }
                    NativeTelevisionKnob(rotation: 0)
                    NativeTelevisionKnob(rotation: 52)
                }
                .font(.system(size: 7.5, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(.white.opacity(0.50))
                .padding(.horizontal, 14)
                .padding(.bottom, 9)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0.22, green: 0.22, blue: 0.23),
                        Color(red: 0.06, green: 0.06, blue: 0.07),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 21)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 21)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.7)
            )
            .shadow(color: .black.opacity(0.32), radius: 22, y: 15)

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(momentTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .tracking(-0.3)
                        Text("—")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Color.black.opacity(0.34))
                    }
                    Text(momentDetail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.black.opacity(0.44))
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 7) {
                    Button(action: {}) {
                        Text("‹")
                            .font(.system(size: 20))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(Color.black.opacity(0.14)))
                    }
                    .disabled(true)
                    Button(action: {}) {
                        Text("›")
                            .font(.system(size: 20))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(Color.black.opacity(0.14)))
                    }
                    .disabled(true)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.black.opacity(0.58))
            }
            .padding(.top, 17)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(red: 0.94, green: 0.935, blue: 0.91))
                    .frame(height: 14)
                Rectangle()
                    .fill(Color.black.opacity(0.82))
                    .frame(width: 1, height: 14)
            }
            .padding(.top, 16)

            HStack {
                Text("—")
                Spacer()
                Text("—")
                Spacer()
                Text("—")
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(Color.black.opacity(0.26))
            .padding(.top, 7)

            NativeFlowLayout(spacing: 15) {
                ForEach(Array(appRows.prefix(7)), id: \.name) { app in
                    HStack(spacing: 6) {
                        NativeActivityIcon(text: app.name)
                            .scaleEffect(0.62)
                            .frame(width: 18, height: 18)
                        Text(app.name).lineLimit(1)
                        Text("\(app.count) \(app.count == 1 ? "memory" : "memories")")
                            .fontWeight(.medium)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Color.black.opacity(0.52))
                    .fixedSize(horizontal: true, vertical: false)
                }
                Text(day.source?.trimmedNonEmpty ?? "Personal Model · \(modelID)")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.black.opacity(0.28))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.top, 14)
        }
    }
}

private struct NativeTelevisionKnob: View {
    let rotation: Double

    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(red: 0.56, green: 0.55, blue: 0.52),
                        Color(red: 0.28, green: 0.28, blue: 0.27),
                        Color(red: 0.13, green: 0.13, blue: 0.13),
                    ],
                    center: UnitPoint(x: 0.38, y: 0.32),
                    startRadius: 1,
                    endRadius: 11
                )
            )
            .frame(width: 16, height: 16)
            .overlay(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.50))
                    .frame(width: 1, height: 5)
                    .padding(.top, 2)
            }
            .rotationEffect(.degrees(rotation))
            .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
            .accessibilityHidden(true)
    }
}

private struct NativeDayLetterParts {
    let root: String
    let description: String
}

private func nativeDayLetterParts(_ value: String) -> NativeDayLetterParts {
    let lines = value
        .components(separatedBy: .newlines)
        .compactMap(\.trimmedNonEmpty)
    let hasSalutation = lines.first.map {
        $0.hasPrefix("给") && ($0.hasSuffix("：") || $0.hasSuffix(":"))
    } ?? false
    let body = hasSalutation ? Array(lines.dropFirst()) : lines
    return NativeDayLetterParts(
        root: body.first ?? value,
        description: body.dropFirst().first
            ?? "它不是对你的最终定义，只是今天愿意留在 Root 上的一句话。"
    )
}


private func nativeDayDate(_ id: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: id)
}

private func nativeYearLabel(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "yyyy"
    return formatter.string(from: date)
}

private func nativeMonthName(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MMMM"
    return formatter.string(from: date).uppercased()
}

private func nativeCompactDayLabel(_ id: String) -> String {
    guard let date = nativeDayDate(id) else { return id }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日"
    return formatter.string(from: date)
}

private func nativeMonthLabel(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "yyyy 年 M 月"
    return formatter.string(from: date)
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
                Text("Swipe your card")
                    .font(.system(size: 34, weight: .medium, design: .serif))
                Text("把你的 Personal Card 刷给 Agent。刷过以后，它们戴上这张卡；完成的工作会收成一页结果。每个连接都绑定当前模型与当前授权。")
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
                NativeConnectorSwipe(state: state, snapshot: snapshot, connectors: connectors)
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
    let snapshot: PersonalModelSnapshot
    let connectors: [ConnectorSnapshot]
    @State private var dragOffset: CGFloat = 0
    @State private var isSwiping = false

    private var done: Bool {
        !connectors.isEmpty && connectors.allSatisfy {
            $0.status == "connected" || $0.status == "missing"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 17)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.94, green: 0.935, blue: 0.92), Color(red: 0.89, green: 0.88, blue: 0.85)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.black.opacity(0.08)))
                    VStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 17)
                            .fill(
                                LinearGradient(
                                    colors: [Color(red: 0.24, green: 0.24, blue: 0.26), Color(red: 0.08, green: 0.08, blue: 0.09)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 76, height: 136)
                            .overlay(alignment: .top) {
                                Capsule().fill(.black.opacity(0.75)).frame(width: 48, height: 4).padding(.top, 20)
                            }
                            .overlay(alignment: .topTrailing) {
                                Circle()
                                    .fill(isSwiping ? Color.yellow : done ? .green : .gray)
                                    .frame(width: 7, height: 7)
                                    .shadow(color: isSwiping ? .yellow : .clear, radius: 6)
                                    .padding(.top, 35)
                                    .padding(.trailing, 13)
                            }
                            .overlay(alignment: .bottom) {
                                Text("SWIPE\nREADER")
                                    .font(.system(size: 6, design: .monospaced))
                                    .tracking(1.2)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.white.opacity(0.42))
                                    .padding(.bottom, 18)
                            }
                    }
                    .position(x: proxy.size.width * 0.47, y: proxy.size.height * 0.50)

                    NativeMiniPass(snapshot: snapshot)
                        .frame(width: 128, height: 82)
                        .rotationEffect(.degrees(isSwiping ? 0 : -3))
                        .offset(x: isSwiping ? proxy.size.width * 0.36 : dragOffset)
                        .opacity(isSwiping ? 0.1 : 1)
                        .position(x: proxy.size.width * 0.20, y: proxy.size.height * 0.52)
                        .animation(.easeInOut(duration: 0.68), value: isSwiping)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    guard !done else { return }
                                    dragOffset = min(max(0, value.translation.width), proxy.size.width * 0.45)
                                }
                                .onEnded { value in
                                    if value.translation.width > proxy.size.width * 0.26 { beginSwipe() }
                                    withAnimation(.spring(response: 0.35)) { dragOffset = 0 }
                                }
                        )

                    HStack(spacing: -18) {
                        ForEach(Array(connectors.prefix(3).enumerated()), id: \.element.id) { index, connector in
                            NativeAgentBadge(connector: connector, snapshot: snapshot)
                                .rotationEffect(.degrees(Double(index - 1) * 3.2))
                                .zIndex(Double(3 - index))
                        }
                    }
                    .position(x: proxy.size.width * 0.80, y: proxy.size.height * 0.53)
                    Text("YOUR CARD")
                        .font(.system(size: 6, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                        .position(x: 52, y: proxy.size.height - 12)
                    Text("AGENTS WEARING IT")
                        .font(.system(size: 6, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                        .position(x: proxy.size.width - 78, y: proxy.size.height - 12)
                }
            }
            .frame(height: 190)
            Button(done ? "可用 Agents 已处理" : isSwiping ? "正在刷入当前 Personal Model…" : "Swipe your Personal Card") {
                beginSwipe()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(done || connectors.isEmpty || isSwiping || !state.connectingConnector.isEmpty)
            Text(done ? "这张卡只绑定当前用户与当前授权" : "滑动卡片，或按下按钮；未安装的 Agent 不会被伪装成已连接。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
    }

    private func beginSwipe() {
        guard !done, !isSwiping, !connectors.isEmpty else { return }
        isSwiping = true
        Task {
            await state.connectAll()
            try? await Task.sleep(nanoseconds: 720_000_000)
            await MainActor.run { isSwiping = false }
        }
    }
}

private struct NativeMiniPass: View {
    let snapshot: PersonalModelSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("№ \(snapshot.model.memberNumber ?? "001")")
                Spacer()
                Text("PERSONAL CARD")
            }
            .font(.system(size: 5.5, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(.secondary)
            HStack(spacing: 7) {
                NativeGlyph(glyph: snapshot.card?.glyph ?? [])
                    .scaleEffect(0.28, anchor: .topLeading)
                    .frame(width: 23, height: 23)
                Text(snapshot.model.handle)
                    .font(.caption.weight(.semibold))
            }
            Spacer()
            HStack {
                Text("WHO AM I")
                Spacer()
                Text("ONE OF ONE")
            }
            .font(.system(size: 5, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.11)))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
    }
}

private struct NativeAgentBadge: View {
    let connector: ConnectorSnapshot
    let snapshot: PersonalModelSnapshot

    var body: some View {
        VStack(spacing: 4) {
            Capsule()
                .fill(connector.status == "connected" ? Color.blue.opacity(0.7) : Color.gray.opacity(0.65))
                .frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.09))
                        .frame(width: 18, height: 18)
                        .overlay(Text(String(connector.name.prefix(1))).font(.system(size: 8, weight: .bold)))
                    Text(connector.name).font(.system(size: 8, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    Circle()
                        .fill(connector.status == "connected" ? .green : .gray)
                        .frame(width: 5, height: 5)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("PERSONAL CARD")
                        .font(.system(size: 4.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                    Text(snapshot.model.handle)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white)
                    HStack {
                        Spacer()
                        Text("№ \(snapshot.model.memberNumber ?? "001")")
                            .font(.system(size: 4.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                }
                .padding(6)
                .background(Color.black.opacity(connector.status == "connected" ? 0.88 : 0.28), in: RoundedRectangle(cornerRadius: 5))
                Text(connector.status == "connected" ? "WEARING YOUR CARD" : "WAITING FOR CARD")
                    .font(.system(size: 4.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(7)
            .frame(width: 92, height: 116)
            .background(Color.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.black.opacity(0.1)))
            .shadow(color: .black.opacity(0.16), radius: 9, y: 6)
        }
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
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Text("Personal Model")
                    Text("/").foregroundStyle(.tertiary)
                    Text("Pages created")
                    Spacer()
                    Label("实时更新", systemImage: "circle.fill")
                        .foregroundStyle(.green)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text("它们写下的页面")
                    .font(.system(size: 28, weight: .medium, design: .serif))
                    .padding(.top, 16)
                Text("外面只留下结果。打开一页，才看见 Agent 怎样读你、理解你。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.top, 5)
                Divider().padding(.top, 18)
                if reports.isEmpty {
                    NativeInlineState(
                        symbol: "doc.badge.clock",
                        title: "报告尚未产生",
                        detail: connectedReportDetail
                    )
                    .padding(.vertical, 12)
                }
                ForEach(reports) { report in
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                expandedReport = expandedReport == report.id ? nil : report.id
                            }
                        } label: {
                            HStack(spacing: 13) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.black.opacity(0.045))
                                    .frame(width: 34, height: 40)
                                    .overlay(Image(systemName: "doc.text").foregroundStyle(.secondary))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(report.title).font(.headline)
                                    Text(report.summary?.trimmedNonEmpty ?? "这页没有提供可展示的摘要。")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                    HStack(spacing: 8) {
                                        Text(report.updatedAt ?? "as of now")
                                        if let readCount = report.readCount { Text("\(readCount) reads") }
                                        Text("\(report.evidenceCount ?? report.evidenceRefs?.count ?? 0) evidence")
                                    }
                                    .font(.system(size: 7.5, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                Text(report.connectorId?.uppercased() ?? "AGENT")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Image(systemName: expandedReport == report.id ? "chevron.up.circle.fill" : "chevron.down.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if expandedReport == report.id {
                            VStack(alignment: .leading, spacing: 0) {
                                HStack {
                                    Text(report.connectorId ?? "Agent")
                                    Text("/")
                                    Text(report.title).lineLimit(1)
                                    Spacer()
                                    Text("LIVE PAGE")
                                }
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                                Divider().padding(.top, 12)
                                Text(report.title)
                                    .font(.system(size: 23, weight: .medium, design: .serif))
                                    .padding(.top, 20)
                                if let summary = report.summary?.trimmedNonEmpty {
                                    Text(summary)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .lineSpacing(6)
                                        .padding(.top, 9)
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("CURRENT UNDERSTANDING")
                                            .font(.caption2.monospaced())
                                            .tracking(1.3)
                                            .foregroundStyle(.secondary)
                                        Text(summary).font(.callout).lineSpacing(6)
                                    }
                                    .padding(14)
                                    .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                                    .padding(.top, 16)
                                }
                                if !(report.sections ?? []).isEmpty {
                                    Text("这页用到的依据")
                                        .font(.callout.weight(.semibold))
                                        .padding(.top, 22)
                                    ForEach(report.sections ?? []) { section in
                                        HStack(alignment: .top, spacing: 9) {
                                            Text("•").foregroundStyle(.secondary)
                                            VStack(alignment: .leading, spacing: 5) {
                                                Text(section.title).font(.callout.weight(.semibold))
                                                Text(section.body)
                                                    .font(.callout)
                                                    .foregroundStyle(.secondary)
                                                    .lineSpacing(5)
                                                    .textSelection(.enabled)
                                                if let kind = section.kind {
                                                    Text(kind.uppercased())
                                                        .font(.caption2.monospaced())
                                                        .foregroundStyle(.tertiary)
                                                }
                                            }
                                        }
                                        .padding(.vertical, 10)
                                        Divider()
                                    }
                                }
                                Text("证据索引")
                                    .font(.callout.weight(.semibold))
                                    .padding(.top, 20)
                                Text("正文保持安静；需要时，再回到它真正读过的位置。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 3)
                                ForEach(Array((report.evidenceRefs ?? []).enumerated()), id: \.element) { index, reference in
                                    HStack {
                                        Text(String(format: "%02d", index + 1))
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.tertiary)
                                        Text(reference)
                                            .font(.caption.monospaced())
                                            .lineLimit(1)
                                        Spacer()
                                        Button("✦ 证据") { Task { await state.loadEvidence(reference) } }
                                            .buttonStyle(.borderless)
                                    }
                                    .padding(.vertical, 9)
                                    Divider()
                                }
                                HStack {
                                    Text("由真实读取自动整理")
                                    Spacer()
                                    Text("LOCAL · TRACEABLE")
                                }
                                .font(.caption2.monospaced())
                                .foregroundStyle(.tertiary)
                                .padding(.top, 12)
                            }
                            .padding(20)
                            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.08)))
                            .padding(.leading, 45)
                            .padding(.bottom, 18)
                            NativeTruthBadge(metadata: report.truthMetadata)
                                .padding(.leading, 45)
                                .padding(.bottom, 14)
                        }
                    }
                    Divider()
                }
                HStack {
                    Text("点击页面查看细节")
                    Spacer()
                    Text("RESULTS OUTSIDE · EVIDENCE INSIDE")
                }
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .padding(.top, 14)
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
    @State private var tagline = ""
    @State private var description = ""
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
                    TextField("一句话：你正在做什么", text: $tagline)
                        .accessibilityLabel("Card tagline")
                    TextField("简单介绍你自己（可选）", text: $description)
                        .accessibilityLabel("身份介绍")
                    Button("创建我的 Personal Card") {
                        Task {
                            await state.saveProfile(
                                displayName: displayName,
                                handle: handle,
                                tagline: tagline,
                                description: description
                            )
                        }
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

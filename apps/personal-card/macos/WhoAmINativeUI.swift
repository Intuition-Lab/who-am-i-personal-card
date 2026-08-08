import AppKit
import Foundation
import SwiftUI

let whoAmIVisualQAOpaque = ProcessInfo.processInfo.environment["WHOAMI_VISUAL_QA_OPAQUE"] == "1"

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
            if state.selectedSection != .card && !state.isShareOpen && !state.isMemorySkyOpen {
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
            .degrees(Double(drag.width / 45)),
            axis: (x: -drag.height / 80, y: 1, z: 0),
            perspective: 0.45
        )
        .offset(x: drag.width * 0.08, y: drag.height * 0.04)
        .animation(.spring(response: 0.46, dampingFraction: 0.82), value: flipped)
        .animation(.interactiveSpring(), value: drag)
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
        .accessibilityLabel("\(snapshot.model.displayName) Personal Model Card")
        .accessibilityHint("按空格、点击或横向滑动翻转 Card")
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
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 24)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .onTapGesture { flipped = true }
        .simultaneousGesture(cardGesture)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { flipped = true }
        .accessibilityLabel("翻转 \(snapshot.model.displayName) 的 Card")
        .accessibilityHint("显示模型依据、更正与复制操作")
    }

    private var back: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(cardStars.filter { !$0.isBright }) { star in
                    Circle()
                        .fill(material.detail.opacity(star.opacity))
                        .frame(width: star.size, height: star.size)
                        .position(
                            x: proxy.size.width * star.x / 100,
                            y: proxy.size.height * star.y / 100
                        )
                        .accessibilityHidden(true)
                }
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

private struct NativeSkyStar: Identifiable {
    let id: String
    let title: String
    let detail: String
    let reference: String?
    let source: String
    let x: CGFloat
    let y: CGFloat
    let strength: CGFloat
}

private struct NativeMemorySky: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot
    @State private var mode: NativeSkyMode = .constellation
    @State private var selectedStar: NativeSkyStar?
    @State private var threeD = false
    @State private var skyTilt = CGSize.zero
    @State private var skyCorrection = ""

    private var stars: [NativeSkyStar] {
        var output: [NativeSkyStar] = []
        for face in snapshot.personalModel?.faces ?? [] {
            output.append(
                NativeSkyStar(
                    id: "face:\(face.id)",
                    title: "Personal Model 推断",
                    detail: face.text,
                    reference: face.evidenceRefs?.first,
                    source: face.source ?? "Personal Model",
                    x: 0.12 + stableUnit(face.id, salt: 17) * 0.76,
                    y: 0.15 + stableUnit(face.id, salt: 43) * 0.64,
                    strength: 4 + CGFloat(min(8, max(0, face.observations ?? 1))) * 0.55
                )
            )
        }
        for day in snapshot.time?.days ?? [] {
            for event in day.events ?? [] where event.evidenceRef != nil {
                output.append(
                    NativeSkyStar(
                        id: "event:\(day.id):\(event.id)",
                        title: event.title,
                        detail: [event.time, event.app, event.detail]
                            .compactMap { $0?.trimmedNonEmpty }
                            .joined(separator: " · "),
                        reference: event.evidenceRef,
                        source: event.source ?? event.app ?? "Rewind",
                        x: 0.10 + stableUnit("\(day.id):\(event.id)", salt: 71) * 0.80,
                        y: 0.13 + stableUnit("\(day.id):\(event.id)", salt: 97) * 0.70,
                        strength: 3.2
                    )
                )
            }
        }
        return output
    }

    private var visibleStars: [NativeSkyStar] {
        switch mode {
        case .constellation: return stars
        case .dust: return stars
        case .time: return Array(stars.reversed())
        }
    }

    private var rootStar: NativeSkyStar {
        NativeSkyStar(
            id: "root",
            title: "ROOT · 我是谁",
            detail: snapshot.personalModel?.root?.trimmedNonEmpty ?? "Personal Model 正在形成对你的长期理解。",
            reference: nil,
            source: "Personal Model · 当前快照",
            x: 0.5,
            y: 0.46,
            strength: 9
        )
    }

    private func position(for star: NativeSkyStar, index: Int, in size: CGSize) -> CGPoint {
        guard mode == .time else {
            return CGPoint(x: star.x * size.width, y: star.y * size.height)
        }
        let count = max(1, visibleStars.count)
        let progress = CGFloat(index + 1) / CGFloat(count)
        let angle = stableUnit(star.id, salt: 211) * .pi * 2
        let radius = min(size.width, size.height) * (0.08 + 0.37 * sqrt(progress))
        return CGPoint(
            x: size.width * 0.5 + cos(angle) * radius,
            y: size.height * 0.46 + sin(angle) * radius * 0.78
        )
    }

    private var legend: String {
        switch mode {
        case .constellation:
            return "星 = 记忆段 · 线 = 同一件事 · 星座 = 主题"
        case .dust:
            return "只看密度 — 哪里亮，日子就长在哪里"
        case .time:
            return "由内向外 = 从最近到更早 · 新记忆亮，旧记忆暗"
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RadialGradient(
                    colors: [Color(red: 0.09, green: 0.10, blue: 0.16), Color(red: 0.025, green: 0.025, blue: 0.04)],
                    center: .center,
                    startRadius: 10,
                    endRadius: max(proxy.size.width, proxy.size.height) * 0.78
                )
                .ignoresSafeArea()
                ForEach(0..<6, id: \.self) { index in
                    Circle()
                        .fill(Color.indigo.opacity(0.035))
                        .frame(width: 190 + CGFloat(index * 34), height: 110 + CGFloat(index * 26))
                        .blur(radius: 34)
                        .position(
                            x: stableUnit("mist-\(index)", salt: 11) * proxy.size.width,
                            y: stableUnit("mist-\(index)", salt: 29) * proxy.size.height
                        )
                        .accessibilityHidden(true)
                }
                ZStack {
                    Canvas { context, size in
                        guard mode == .constellation else { return }
                        let center = CGPoint(x: size.width * 0.5, y: size.height * 0.46)
                        for (index, star) in visibleStars.prefix(32).enumerated() {
                            var path = Path()
                            path.move(to: center)
                            path.addLine(to: position(for: star, index: index, in: size))
                            context.stroke(path, with: .color(.white.opacity(0.055)), lineWidth: 0.7)
                        }
                    }
                    ForEach(Array(visibleStars.enumerated()), id: \.element.id) { index, star in
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { selectedStar = star }
                        } label: {
                            Circle()
                                .fill(star.reference == nil ? Color.white.opacity(0.54) : Color.white)
                                .frame(width: star.strength, height: star.strength)
                                .shadow(
                                    color: star.reference == nil ? .clear : Color.blue.opacity(0.72),
                                    radius: star.strength * 1.3
                                )
                                .contentShape(Circle().inset(by: -8))
                        }
                        .buttonStyle(.plain)
                        .position(position(for: star, index: index, in: proxy.size))
                        .accessibilityLabel("\(star.title)：\(star.detail)")
                    }
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { selectedStar = rootStar }
                    } label: {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [.white, .blue.opacity(0.82), .clear],
                                    center: .center,
                                    startRadius: 1,
                                    endRadius: 15
                                )
                            )
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(.white.opacity(0.18)))
                            .shadow(color: .blue.opacity(0.52), radius: 15)
                    }
                    .buttonStyle(.plain)
                    .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.46)
                    .accessibilityLabel("ROOT · 我是谁")
                }
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
                        .onChanged { value in if threeD { skyTilt = value.translation } }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.4)) { skyTilt = .zero }
                        }
                )
                VStack {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("MEMORY SKY")
                                .font(.caption2.monospaced())
                                .tracking(2.4)
                            Text("\(snapshot.personalModel?.memoryCount ?? 0) memories · \(visibleStars.count) visible stars")
                                .font(.caption2)
                        }
                        .foregroundStyle(.white.opacity(0.48))
                        Spacer()
                        Picker("Memory Sky mode", selection: $mode) {
                            ForEach(NativeSkyMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 210)
                        Button(threeD ? "2D" : "3D ⤢") {
                            withAnimation(.spring(response: 0.35)) {
                                threeD.toggle()
                                skyTilt = .zero
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { state.isMemorySkyOpen = false }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.52))
                        }
                        .buttonStyle(.plain)
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("关闭 Memory Sky")
                    }
                    Spacer()
                    if let selectedStar {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(selectedStar.title)
                                    .font(.caption2.monospaced())
                                    .tracking(1.7)
                                    .foregroundStyle(.white.opacity(0.45))
                                Spacer()
                                Button {
                                    withAnimation(.easeOut(duration: 0.15)) { self.selectedStar = nil }
                                } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain)
                            }
                            Text(selectedStar.detail)
                                .font(.system(size: 15, design: .serif))
                                .lineSpacing(5)
                                .foregroundStyle(.white.opacity(0.9))
                            HStack {
                                Text(selectedStar.source)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.white.opacity(0.42))
                                Spacer()
                                if let reference = selectedStar.reference {
                                    Button("出处") { Task { await state.loadEvidence(reference) } }
                                } else {
                                    Text("尚无可核验 Evidence")
                                        .font(.caption2)
                                        .foregroundStyle(.orange.opacity(0.85))
                                }
                                Button("改写") { skyCorrection = selectedStar.detail }
                                Button("行动") {
                                    state.isMemorySkyOpen = false
                                    state.selectedSection = .connectors
                                }
                                Button("分享 ↗") { state.openShare(highlight: selectedStar.detail) }
                            }
                            .buttonStyle(.borderless)
                            if !skyCorrection.isEmpty {
                                HStack(spacing: 8) {
                                    TextField("不对的话，改写它", text: $skyCorrection)
                                        .textFieldStyle(.plain)
                                        .foregroundStyle(.white)
                                        .onSubmit { Task { await state.correct(skyCorrection) } }
                                    Button(state.isCorrecting ? "写入中…" : "写入") {
                                        Task { await state.correct(skyCorrection) }
                                    }
                                    .disabled(state.isCorrecting)
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
                            }
                        }
                        .padding(17)
                        .frame(maxWidth: 500)
                        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12)))
                    } else {
                        VStack(spacing: 5) {
                            Text(legend)
                            Text("亮星可点 · Evidence 只来自当前 Personal Model")
                        }
                        .font(.caption2.monospaced())
                        .foregroundStyle(.white.opacity(0.34))
                    }
                }
                .padding(22)
            }
        }
        .focusable()
        .onMoveCommand { direction in
            let stars = visibleStars
            guard !stars.isEmpty else { return }
            let currentIndex = selectedStar.flatMap { selected in
                stars.firstIndex(where: { $0.id == selected.id })
            } ?? -1
            switch direction {
            case .left, .up:
                selectedStar = stars[(currentIndex - 1 + stars.count) % stars.count]
            case .right, .down:
                selectedStar = stars[(currentIndex + 1) % stars.count]
            default:
                break
            }
        }
        .accessibilityElement(children: .contain)
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
    let openEvidence: (String) -> Void

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
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
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
    @State private var daySearch = ""
    @State private var dayCorrection = ""

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

    private var rewindYear: some View {
        NativePaper(maxWidth: 900) {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .lastTextBaseline) {
                    Text("\(days.count) 天")
                        .font(.system(size: 46, weight: .bold))
                    Text("每一天都回得去\n深浅 = 那天留下的可靠记录")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("你的记忆，不用你记")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                NativeYearHeatmap(days: days) { day in
                    selectedDayID = day.id
                    screen = .day
                }
                HStack {
                    Text("只点亮当前 Personal Model 真正返回的日期。")
                    Spacer()
                    Button("回到这个月") { screen = .month }
                        .buttonStyle(.borderless)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var rewindMonth: some View {
        NativePaper(maxWidth: 1020) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("search memories…", text: $state.searchQuery)
                        .textFieldStyle(.plain)
                        .onSubmit {
                            state.selectedSection = .card
                            Task { await state.search() }
                        }
                        .accessibilityLabel("搜索 Rewind 记忆")
                }
                .padding(.horizontal, 13)
                .frame(height: 42)
                .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                HStack(alignment: .center, spacing: 13) {
                    Button("← \(nativeYearLabel(referenceDate))") { screen = .year }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Text("时间 · \(nativeMonthLabel(referenceDate))")
                        .font(.system(size: 24, weight: .bold))
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) { state.isMemorySkyOpen = true }
                    } label: {
                        Label("记忆星图", systemImage: "sparkles")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                HStack(alignment: .top, spacing: 28) {
                    NativeMonthCalendar(referenceDate: referenceDate, days: days) { day in
                        selectedDayID = day.id
                        selectedEventIndex = 0
                        daySearch = ""
                        screen = .day
                    }
                    .frame(maxWidth: .infinity)
                    Divider()
                    NativeRewindApps(days: days) { day in
                        selectedDayID = day.id
                        selectedEventIndex = 0
                        screen = .day
                    }
                    .frame(width: 250)
                }
                Text("不是另一张图表。日历只标出确实存在记录的日期；未来日期不会生成虚构安排。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rewindDay(_ day: DaySnapshot) -> some View {
        NativePaper(maxWidth: 1120) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Button {
                        screen = .month
                    } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderless)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Search this day", text: $daySearch)
                            .textFieldStyle(.plain)
                            .onSubmit { locateEvent(in: day) }
                    }
                    .padding(.horizontal, 11)
                    .frame(width: 270, height: 34)
                    .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                    Spacer()
                    Text("Rewind · memory document")
                        .font(.caption2.monospaced())
                        .tracking(1.4)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(day.id)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 20)
                Divider()
                VStack(alignment: .leading, spacing: 0) {
                    Text("REWIND · MEMORY DOCUMENT")
                        .font(.caption2.monospaced())
                        .tracking(2.2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 28)
                    Text(day.title ?? day.id)
                        .font(.system(size: 40, weight: .medium, design: .serif))
                        .padding(.top, 12)
                    if let portrait = day.portrait?.trimmedNonEmpty {
                        Text(portrait)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .lineSpacing(7)
                            .padding(.top, 13)
                        NativeTruthBadge(
                            metadata: NativeTruthMetadata(
                                kind: .generated,
                                source: day.source ?? "Personal Model",
                                timeRange: day.timeRange ?? day.id,
                                confidence: nil
                            )
                        )
                        .padding(.top, 9)
                    }
                    NativeDayModelUpdates(state: state, day: day)
                        .padding(.top, 28)
                    NativeRewindTelevision(
                        state: state,
                        day: day,
                        selectedEventIndex: $selectedEventIndex
                    )
                    .padding(.top, 32)
                    if let letter = day.letter?.trimmedNonEmpty {
                        Divider().padding(.top, 34)
                        HStack {
                            Text("ROOT · 今天留下的一句")
                                .font(.caption2.monospaced())
                                .tracking(2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("生成今日卡") {
                                withAnimation(.spring(response: 0.3)) { state.openShare(highlight: letter) }
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.top, 24)
                        Text(letter)
                            .font(.system(size: 21, design: .serif))
                            .lineSpacing(9)
                            .padding(.top, 13)
                        NativeTruthBadge(
                            metadata: NativeTruthMetadata(
                                kind: .generated,
                                source: day.source ?? "Personal Model",
                                timeRange: day.timeRange ?? day.id,
                                confidence: nil
                            )
                        )
                        .padding(.top, 9)
                    }
                    HStack(spacing: 8) {
                        TextField("这一天的理解不准确？写下你的更正…", text: $dayCorrection)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { Task { await state.correct(dayCorrection) } }
                        Button(state.isCorrecting ? "写入中…" : "更正") {
                            Task { await state.correct(dayCorrection) }
                        }
                        .disabled(dayCorrection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isCorrecting)
                    }
                    .padding(.top, 28)
                    Text("frames are local · the story stays with your Personal Model")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .padding(.top, 24)
                }
            }
        }
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
}

private struct NativeYearHeatmap: View {
    let days: [DaySnapshot]
    let select: (DaySnapshot) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 14)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 5) {
            ForEach(0..<98, id: \.self) { index in
                heatmapCell(at: index)
            }
        }
    }

    @ViewBuilder
    private func heatmapCell(at index: Int) -> some View {
        if index < days.count {
            let day = days[index]
            Button { select(day) } label: {
                RoundedRectangle(cornerRadius: 3)
                    .fill(heatColor(day))
                    .aspectRatio(1, contentMode: .fit)
            }
            .buttonStyle(.plain)
            .help(day.title ?? day.id)
            .accessibilityLabel("\(day.id)，\(day.events?.count ?? 0) 条记录")
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.black.opacity(0.025))
                .aspectRatio(1, contentMode: .fit)
                .accessibilityLabel("没有记录")
        }
    }

    private func heatColor(_ day: DaySnapshot) -> Color {
        let count = day.events?.count ?? 0
        return Color.blue.opacity(min(0.9, 0.22 + Double(count) * 0.16))
    }
}

private struct NativeMonthCalendar: View {
    let referenceDate: Date
    let days: [DaySnapshot]
    let select: (DaySnapshot) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
    private let calendar = Calendar(identifier: .gregorian)

    private var dayByNumber: [Int: DaySnapshot] {
        Dictionary(uniqueKeysWithValues: days.compactMap { day in
            guard let date = nativeDayDate(day.id),
                  calendar.isDate(date, equalTo: referenceDate, toGranularity: .month)
            else { return nil }
            return (calendar.component(.day, from: date), day)
        })
    }

    private var cells: [Int?] {
        guard let interval = calendar.dateInterval(of: .month, for: referenceDate) else { return [] }
        let count = calendar.range(of: .day, in: .month, for: referenceDate)?.count ?? 30
        let weekday = calendar.component(.weekday, from: interval.start)
        let mondayOffset = (weekday + 5) % 7
        return Array(repeating: nil, count: mondayOffset) + (1...count).map(Optional.some)
    }

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { label in
                    Text(label)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 6)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, number in
                    if let number {
                        let day = dayByNumber[number]
                        Button {
                            if let day { select(day) }
                        } label: {
                            VStack(spacing: 6) {
                                Text("\(number)")
                                    .font(.caption.monospacedDigit())
                                Circle()
                                    .fill(day == nil ? Color.clear : Color.primary)
                                    .frame(width: 4, height: 4)
                            }
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(
                                day == nil ? Color.clear : Color.black.opacity(0.035),
                                in: RoundedRectangle(cornerRadius: 9)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(day == nil)
                        .help(day?.portrait ?? "没有记录")
                    } else {
                        Color.clear.frame(minHeight: 54)
                    }
                }
            }
            HStack(spacing: 16) {
                Label("留下过记忆", systemImage: "circle.fill")
                Label("点日期进入当天", systemImage: "arrow.turn.down.right")
                Spacer()
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

private struct NativeRewindApps: View {
    let days: [DaySnapshot]
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
        return counts.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.count > $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("最近围绕的事")
                .font(.caption2.monospaced())
                .tracking(1.4)
            Text("这里按真实事件来源聚合，不根据缺失记录猜测使用时长。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .padding(.vertical, 10)
            if rows.isEmpty {
                NativeInlineState(
                    symbol: "clock.arrow.circlepath",
                    title: "还没有可回绕的记录",
                    detail: "可靠活动出现后，会按来源显示在这里。"
                )
            }
            ForEach(rows, id: \.app) { row in
                Button { select(row.day) } label: {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color.black.opacity(0.08))
                            .frame(width: 29, height: 29)
                            .overlay(Text(String(row.app.prefix(1))).font(.caption.weight(.bold)))
                        Text(row.app).font(.callout.weight(.semibold)).lineLimit(1)
                        Spacer()
                        Text("\(row.count) 段")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }
}

private struct NativeDayModelUpdates: View {
    @ObservedObject var state: PersonalModelAppState
    let day: DaySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("今天写进 Personal Model")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("每一条都保留类型与来源")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(day.events ?? []) { event in
                HStack(alignment: .top, spacing: 18) {
                    Text("RECORD")
                        .font(.caption2.monospaced())
                        .tracking(1)
                        .foregroundStyle(.secondary)
                        .frame(width: 72, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(event.title).font(.callout.weight(.semibold))
                        Text(event.detail?.trimmedNonEmpty ?? "这条记录没有附加描述。")
                            .font(.system(size: 15, design: .serif))
                            .foregroundStyle(.secondary)
                            .lineSpacing(6)
                        NativeTruthBadge(metadata: event.truthMetadata(day: day))
                    }
                    Spacer()
                    if let reference = event.evidenceRef {
                        Button("溯源") { Task { await state.loadEvidence(reference) } }
                            .buttonStyle(.borderless)
                    }
                }
                .padding(.vertical, 15)
                Divider()
            }
        }
    }
}

private struct NativeRewindTelevision: View {
    @ObservedObject var state: PersonalModelAppState
    let day: DaySnapshot
    @Binding var selectedEventIndex: Int

    private var events: [EventSnapshot] { day.events ?? [] }
    private var selectedEvent: EventSnapshot? {
        guard !events.isEmpty else { return nil }
        return events[min(max(0, selectedEventIndex), events.count - 1)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 21)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.22, green: 0.22, blue: 0.23), Color(red: 0.06, green: 0.06, blue: 0.07)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                VStack(spacing: 0) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 13)
                            .fill(Color(red: 0.075, green: 0.075, blue: 0.085))
                        if let selectedEvent {
                            VStack(spacing: 11) {
                                Text((selectedEvent.app ?? "Personal Model").uppercased())
                                    .font(.caption2.monospaced())
                                    .tracking(2)
                                    .foregroundStyle(.white.opacity(0.36))
                                Text(selectedEvent.title)
                                    .font(.system(size: 24, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .multilineTextAlignment(.center)
                                Text(selectedEvent.detail?.trimmedNonEmpty ?? "这条记录没有可显示的画面描述。")
                                    .font(.callout)
                                    .foregroundStyle(.white.opacity(0.52))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: 560)
                            }
                            .padding(40)
                            VStack {
                                HStack {
                                    Label(selectedEvent.app ?? "Personal Model", systemImage: "record.circle")
                                    Spacer()
                                    Text(selectedEvent.time ?? "—")
                                }
                                .font(.caption.monospaced())
                                .foregroundStyle(.white.opacity(0.62))
                                .padding(14)
                                Spacer()
                            }
                        } else {
                            Text("这一天没有可回放的可靠片段")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .padding(10)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    HStack(spacing: 10) {
                        Label("WHO AM I · REWIND", systemImage: "circle.fill")
                        Text("CH \(events.isEmpty ? "—" : "\(selectedEventIndex + 1)/\(events.count)")")
                            .foregroundStyle(.white.opacity(0.3))
                        Spacer()
                        ForEach(0..<12, id: \.self) { _ in
                            Circle().fill(.black.opacity(0.55)).frame(width: 3, height: 3)
                        }
                        Circle().fill(.gray).frame(width: 16, height: 16)
                        Circle().fill(.gray).frame(width: 16, height: 16)
                    }
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 9)
                }
            }
            if let selectedEvent {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedEvent.title).font(.headline)
                        Text(selectedEvent.detail?.trimmedNonEmpty ?? "没有附加描述")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { selectedEventIndex = max(0, selectedEventIndex - 1) } label: {
                        Image(systemName: "chevron.left.circle")
                    }
                    .disabled(selectedEventIndex == 0)
                    Button { selectedEventIndex = min(events.count - 1, selectedEventIndex + 1) } label: {
                        Image(systemName: "chevron.right.circle")
                    }
                    .disabled(selectedEventIndex >= events.count - 1)
                }
                .buttonStyle(.borderless)
                HStack(spacing: 3) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        Button { selectedEventIndex = index } label: {
                            Capsule()
                                .fill(index == selectedEventIndex ? Color.primary : Color.primary.opacity(0.16))
                                .frame(maxWidth: .infinity, minHeight: 8, maxHeight: 8)
                        }
                        .buttonStyle(.plain)
                        .help("\(event.time ?? "—") · \(event.title)")
                    }
                }
                HStack {
                    Text(events.first?.time ?? "—")
                    Spacer()
                    Text(selectedEvent.time ?? "—")
                    Spacer()
                    Text(events.last?.time ?? "—")
                }
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                if let reference = selectedEvent.evidenceRef {
                    Button {
                        Task { await state.loadEvidence(reference) }
                    } label: {
                        Label("打开这个片段的 Evidence", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
    }
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

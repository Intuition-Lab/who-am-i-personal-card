import AppKit
import CoreImage
import Foundation
import SwiftUI

let whoAmIVisualQAOpaque = ProcessInfo.processInfo.environment["WHOAMI_VISUAL_QA_OPAQUE"] == "1"
let whoAmIVisualQAActive =
    ProcessInfo.processInfo.environment["WHOAMI_VISUAL_QA_ACTIVE"] == "1"
    || whoAmIVisualQAOpaque
let whoAmIVisualQABackground =
    whoAmIVisualQAActive
    && ProcessInfo.processInfo.environment["WHOAMI_VISUAL_QA_BACKGROUND"] == "1"
let whoAmIVisualQASection = ProcessInfo.processInfo.environment["WHOAMI_VISUAL_QA_SECTION"]
let whoAmIVisualQAPresentation =
    ProcessInfo.processInfo.environment["WHOAMI_VISUAL_QA_PRESENTATION"]
let whoAmIVisualQAServerURL =
    ProcessInfo.processInfo.environment["WHOAMI_VISUAL_QA_SERVER_URL"]
let whoAmIVisualQASnapshotPath =
    ProcessInfo.processInfo.environment["WHOAMI_VISUAL_QA_SNAPSHOT_PATH"]
let whoAmIVisualQAModelID =
    ProcessInfo.processInfo.environment["WHOAMI_VISUAL_QA_MODEL_ID"]

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

struct ContentMetadataSnapshot: Decodable {
    let provenance: String?
    let sourceRefs: [String]?
    let confidence: Double?
    let timeRange: ContentMetadataTimeRange?
    let generatedAt: String?
    let method: String?
}

struct ContentMetadataTimeRange: Decodable {
    let start: String
    let end: String

    var label: String {
        let startLabel = compactDateLabel(start) ?? start
        let endLabel = compactDateLabel(end) ?? end
        return startLabel == endLabel ? startLabel : "\(startLabel)—\(endLabel)"
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
    let hasUsableModel: Bool?
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
    let app: String?
    let source: String?
    let timeRange: String?
    let confidence: Double?
    let contentType: String?
    let evidenceRef: String?
    let evidenceRefs: [String]?
    let metadata: ContentMetadataSnapshot?

    var allEvidenceRefs: [String] {
        var references: [String] = []
        for reference in (evidenceRefs ?? []) + (metadata?.sourceRefs ?? [])
        where !references.contains(reference) {
            references.append(reference)
        }
        if let evidenceRef, !references.contains(evidenceRef) { references.append(evidenceRef) }
        return references
    }

    var isFutureLike: Bool {
        let combined = "\(kind) \(title) \(when ?? "")".lowercased()
        return kind.lowercased() == "future" || combined.contains("明天") || combined.contains("tomorrow")
    }

    var hasReliableSuggestionSource: Bool {
        !allEvidenceRefs.isEmpty
            || (
                metadata?.method?.trimmedNonEmpty != nil
                    && metadata?.timeRange != nil
            )
            || (source?.trimmedNonEmpty != nil && timeRange?.trimmedNonEmpty != nil)
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
    let method: String?
    let degraded: Bool?
    let degradationReason: String?
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

private struct RewindFramesResponse: Decodable {
    let modelId: String
    let dayId: String
    let source: String
    let frames: [RewindFrameSnapshot]
}

struct RewindFrameSnapshot: Decodable, Identifiable {
    let reference: String
    let time: String
    let app: String
    let title: String
    let duration: Double
    let color: String
    let timestamp: String?

    var id: String { reference }
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

struct NativeShareFact: Equatable {
    let kind: String
    let text: String
    let meta: String
    let byline: String
    let isDaily: Bool
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
        let declaredKind = isFutureLike
            ? contentType
            : contentType ?? metadata?.provenance
        return NativeTruthMetadata(
            kind: NativeTruthKind.resolve(declaredKind, fallback: fallback),
            source: source
                ?? metadata?.method
                ?? (allEvidenceRefs.isEmpty ? "Personal Model" : "近期活动记录"),
            timeRange: timeRange
                ?? metadata?.timeRange?.label
                ?? (isFutureLike ? "基于近期活动" : dayId),
            confidence: confidence ?? metadata?.confidence
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
    @Published var shareFact: NativeShareFact?
    @Published var isMemorySkyOpen = false
    @Published var memorySkyEvidenceRequest: String?
    @Published var isRewindDayOpen = false
    @Published var rewindDayRequest: String?
    @Published var shareHighlight: String?
    @Published private(set) var snapshot: PersonalModelSnapshot?
    @Published private(set) var setupState = "loading"
    @Published private(set) var setupErrorMessage: String?
    @Published private(set) var setupStatusMessage: String?
    @Published private(set) var setupHasProfile = false
    @Published private(set) var setupProfileName = ""
    @Published private(set) var setupProfileHandle = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published var searchQuery = ""
    @Published private(set) var searchResults: [SearchResult] = []
    @Published private(set) var searchPhase: NativeRequestPhase = .idle
    @Published private(set) var searchErrorMessage: String?
    @Published private(set) var searchDegradedMessage: String?
    @Published var question = ""
    @Published private(set) var answer = ""
    @Published private(set) var askResponse: AskResponse?
    @Published private(set) var askPhase: NativeRequestPhase = .idle
    @Published private(set) var askErrorMessage: String?
    @Published private(set) var askIsReflection = false
    @Published private(set) var connectors: [ConnectorSnapshot] = []
    @Published private(set) var connectorErrorMessage: String?
    @Published private(set) var reports: [ReportSnapshot] = []
    @Published private(set) var selectedEvidence: EvidenceSnapshot?
    @Published private(set) var selectedEvidenceReference = ""
    @Published private(set) var evidencePhase: NativeRequestPhase = .idle
    @Published private(set) var evidenceErrorMessage: String?
    @Published private(set) var rewindFramesByDay: [String: [RewindFrameSnapshot]] = [:]
    @Published private(set) var rewindFrameSourcesByDay: [String: String] = [:]
    @Published private(set) var rewindFrameImages: [String: NSImage] = [:]
    @Published private(set) var connectingConnector = ""
    @Published private(set) var correctionPhase: NativeRequestPhase = .idle
    @Published private(set) var correctionMessage: String?
    @Published var isAskOpen = false
    @Published var searchFocusRequest = 0

    private let baseURL: URL
    private let session: URLSession
    private var personalModelStatus: PersonalModelStatus?
    private var loadingRewindDays = Set<String>()
    private var loadingRewindFrameReferences = Set<String>()
    private var askPromptIndex = 0

    init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
        if whoAmIVisualQAActive,
           let presentation = whoAmIVisualQAPresentation,
           presentation.hasPrefix("setup:") {
            let requested = String(presentation.dropFirst("setup:".count))
            if requested == "profile-saved" {
                setupState = "onboarding_required"
                setupHasProfile = true
                setupProfileName = "你的名字"
                setupProfileHandle = "@your-handle"
            } else {
                setupState = requested.replacingOccurrences(of: "-", with: "_")
            }
        }
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
        let hasSnapshotContent = (snapshot?.personalModel?.memoryCount ?? 0) > 0
            || !(snapshot?.personalModel?.faces ?? []).isEmpty
            || snapshot?.personalModel?.root?.trimmedNonEmpty != nil
            || !(snapshot?.time?.days ?? []).isEmpty
        if personalModelStatus?.hasUsableModel == true || hasSnapshotContent {
            return false
        }
        let buildStatus = personalModelStatus?.buildStatus?.lowercased() ?? ""
        let building = ["not_built", "building", "forming", "empty"].contains(buildStatus)
        return building || personalModelStatus?.hasUsableModel == false
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
        closeMemorySky()
        isShareOpen = false
        if isAskOpen { closeAsk() }
        selectedSection = .rewind
    }

    func openMemorySky() {
        memorySkyEvidenceRequest = nil
        isShareOpen = false
        if isAskOpen { closeAsk() }
        isMemorySkyOpen = true
    }

    func openEvidenceSky(_ reference: String) {
        memorySkyEvidenceRequest = reference.trimmedNonEmpty
        isShareOpen = false
        if isAskOpen { closeAsk() }
        isMemorySkyOpen = true
    }

    func closeMemorySky() {
        isMemorySkyOpen = false
        memorySkyEvidenceRequest = nil
    }

    func load() async {
        if whoAmIVisualQAActive,
           whoAmIVisualQAPresentation?.hasPrefix("setup:") == true {
            return
        }
        isLoading = true
        errorMessage = nil
        setupErrorMessage = nil
        defer { isLoading = false }
        do {
            let setup: SetupResponse = try await request(path: "api/setup/status")
            setupState = setup.state
            personalModelStatus = setup.personalModel
            setupHasProfile = setup.profile != nil
            setupProfileName = setup.profile?.displayName ?? ""
            setupProfileHandle = setup.profile?.handle ?? ""
            guard setup.ready else { return }
            let bootstrap: BootstrapResponse
            if whoAmIVisualQAActive,
               let requestedModelID = whoAmIVisualQAModelID?.trimmedNonEmpty {
                bootstrap = try await request(
                    path: "api/session/model",
                    method: "POST",
                    json: [
                        "modelId": requestedModelID,
                        "access": requestedModelID == "cecilia" ? "owner" : "authorized",
                    ]
                )
            } else {
                bootstrap = try await request(path: "api/model/bootstrap")
            }
            if snapshot?.model.id != bootstrap.snapshot.model.id {
                rewindFramesByDay = [:]
                rewindFrameSourcesByDay = [:]
                rewindFrameImages = [:]
                loadingRewindDays = []
                loadingRewindFrameReferences = []
            }
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
        isLoading = true
        setupErrorMessage = nil
        setupStatusMessage = nil
        defer { isLoading = false }
        do {
            let response: SetupResponse = try await request(
                path: "api/setup/profile",
                method: "POST",
                json: [
                    "displayName": displayName,
                    "handle": handle,
                    "tagline": tagline,
                    "description": description,
                ]
            )
            setupHasProfile = response.profile != nil
            setupProfileName = response.profile?.displayName ?? displayName
            setupProfileHandle = response.profile?.handle ?? handle
            setupStatusMessage = response.ready
                ? "你的 Personal Model 已连接"
                : "卡片身份已保存；继续完成 Personal Model 授权。"
            await load()
        } catch {
            if snapshot == nil {
                setupErrorMessage = error.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func launchPersonalModelSetup() async {
        isLoading = true
        setupErrorMessage = nil
        setupStatusMessage = nil
        defer { isLoading = false }
        do {
            let _: EmptyResponse = try await request(
                path: "api/setup/personal-model",
                method: "POST",
                json: [:]
            )
            setupStatusMessage = "安装与权限向导已在 Terminal 打开；完成后回到这里重新检测。"
        } catch {
            if snapshot == nil {
                setupErrorMessage = error.localizedDescription
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func rewindFrames(for dayId: String) -> [RewindFrameSnapshot] {
        rewindFramesByDay[dayId] ?? []
    }

    func rewindFrameSource(for dayId: String) -> String? {
        rewindFrameSourcesByDay[dayId]
    }

    func loadRewindFrames(dayId: String) async {
        guard rewindFramesByDay[dayId] == nil, !loadingRewindDays.contains(dayId) else {
            return
        }
        loadingRewindDays.insert(dayId)
        defer { loadingRewindDays.remove(dayId) }
        let encodedDay = dayId.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? dayId
        do {
            let response: RewindFramesResponse = try await request(
                path: "api/model/rewind/frames?day=\(encodedDay)"
            )
            guard response.modelId == snapshot?.model.id, response.dayId == dayId else {
                return
            }
            rewindFramesByDay[dayId] = response.frames
            rewindFrameSourcesByDay[dayId] = response.source
        } catch {
            // Rewind remains usable without Screen Recording or Coast frames.
            rewindFramesByDay[dayId] = []
            rewindFrameSourcesByDay[dayId] = "Coast · 当天没有可用画面"
        }
    }

    func loadRewindFrameImage(reference: String) async {
        guard rewindFrameImages[reference] == nil,
              !loadingRewindFrameReferences.contains(reference)
        else { return }
        loadingRewindFrameReferences.insert(reference)
        defer { loadingRewindFrameReferences.remove(reference) }
        guard let endpointURL = URL(
            string: "api/model/rewind/frame",
            relativeTo: baseURL
        ), var components = URLComponents(
            url: endpointURL.absoluteURL,
            resolvingAgainstBaseURL: false
        ) else { return }
        components.queryItems = [URLQueryItem(name: "reference", value: reference)]
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadRevalidatingCacheData
        request.timeoutInterval = 20
        request.setValue("image/png", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let image = NSImage(data: data)
            else { return }
            rewindFrameImages[reference] = image
        } catch {
            // The original V5 UI falls back to the frame description on image failure.
        }
    }

    func search() async {
        let query = searchQuery.trimmedNonEmpty ?? ""
        guard !query.isEmpty else {
            searchResults = []
            searchPhase = .idle
            searchErrorMessage = nil
            searchDegradedMessage = nil
            return
        }
        searchResults = []
        searchPhase = .loading
        searchErrorMessage = nil
        searchDegradedMessage = nil
        do {
            let response: SearchResponse = try await request(
                path: "api/model/search",
                method: "POST",
                json: ["query": query],
                timeoutInterval: 180
            )
            searchResults = response.results ?? []
            if response.degraded == true {
                searchDegradedMessage = response.degradationReason
                    ?? "实时语义搜索暂时不可用，当前显示关键词匹配结果。"
            }
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
            searchDegradedMessage = nil
        }
    }

    func submitSpotlight() async {
        let query = searchQuery.trimmedNonEmpty ?? ""
        guard !query.isEmpty else { return }
        searchQuery = ""

        let confidingPattern = "(?:我最近|我觉得|我发现|我好像|我有点|我一直|我其实|我想|我不想|我害怕|我担心|我很累|我好累|我很开心|我很难受|我很迷茫|我在纠结|说不上来|不知道为什么)"
        let questionPattern = "[？?]$|^(?:我)?(?:上周|昨天|今天|之前|什么时候|为什么|怎么|如何|哪里|哪次|有没有|是否|能不能|是什么)"
        let isConfiding = query.range(
            of: confidingPattern,
            options: .regularExpression
        ) != nil
        let isQuestion = query.range(
            of: questionPattern,
            options: .regularExpression
        ) != nil

        if !isConfiding || isQuestion {
            let normalizedQuery = query.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: .current
            )
            let matchingDay = snapshot?.time?.days?.first { day in
                let eventText = (day.events ?? []).map {
                    [$0.title, $0.detail, $0.app]
                        .compactMap { $0?.trimmedNonEmpty }
                        .joined(separator: " ")
                }
                let haystack = (
                    [day.title, day.portrait, day.letter]
                        .compactMap { $0?.trimmedNonEmpty }
                    + eventText
                )
                    .joined(separator: " ")
                    .folding(
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: .current
                    )
                return haystack.contains(normalizedQuery)
            }
            if let matchingDay {
                openRewind(dayID: matchingDay.id)
                return
            }
        }

        question = query
        askIsReflection = isConfiding && !isQuestion
        isAskOpen = true
        await ask()
        question = ""
    }

    func submitAsk() async {
        askIsReflection = false
        if question.trimmedNonEmpty == nil {
            let prompts = snapshot?.now?.items ?? []
            if !prompts.isEmpty {
                let item = prompts[askPromptIndex % prompts.count]
                answer = [item.displayTitle, item.why?.trimmedNonEmpty]
                    .compactMap { $0 }
                    .joined(separator: "——")
                askPromptIndex = (askPromptIndex + 1) % prompts.count
            } else {
                answer = "你的 Personal Model 正在等待新的个人依据。"
            }
            askResponse = nil
            askPhase = .success
            askErrorMessage = nil
            return
        }
        await ask()
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
                json: ["question": value],
                timeoutInterval: 180
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
        shareFact = nil
        closeMemorySky()
        isAskOpen = false
        searchFocusRequest += 1
    }

    func openAsk() {
        selectedSection = .card
        isShareOpen = false
        shareFact = nil
        closeMemorySky()
        askIsReflection = false
        isAskOpen = true
    }

    func closeAsk() {
        isAskOpen = false
        question = ""
        answer = ""
        askResponse = nil
        askPhase = .idle
        askErrorMessage = nil
        askIsReflection = false
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
        if shareFact != nil {
            closeFactShare()
            return true
        }
        if hasEvidencePresentation {
            closeEvidence()
            return true
        }
        if isShareOpen {
            isShareOpen = false
            return true
        }
        if isMemorySkyOpen {
            closeMemorySky()
            return true
        }
        if isAskOpen {
            closeAsk()
            return true
        }
        if selectedSection != .card {
            selectedSection = .card
            return true
        }
        return false
    }

    func openShare(highlight: String? = nil) {
        shareFact = nil
        shareHighlight = highlight?.trimmedNonEmpty
        closeMemorySky()
        if isAskOpen { closeAsk() }
        isShareOpen = true
    }

    func openFactShare(
        kind: String,
        text: String,
        meta: String,
        byline: String = "personal model said this",
        isDaily: Bool = false
    ) {
        isShareOpen = false
        shareFact = NativeShareFact(
            kind: kind,
            text: text,
            meta: meta,
            byline: byline,
            isDaily: isDaily
        )
    }

    func closeFactShare() {
        shareFact = nil
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
        json: [String: String]? = nil,
        timeoutInterval: TimeInterval = 30
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw NativeAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = timeoutInterval
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
    @State private var showsOpeningDossier: Bool

    init(state: PersonalModelAppState) {
        _state = StateObject(wrappedValue: state)
        _showsOpeningDossier = State(
            initialValue: state.selectedSection == .card
                && (
                    !whoAmIVisualQAActive
                        || whoAmIVisualQAPresentation == "opening"
                )
        )
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
            .blur(radius: state.isAskOpen ? 12 : 0)
            .zIndex(state.selectedSection == .connectors ? 30 : 0)
            .allowsHitTesting(
                !state.isMemorySkyOpen
                    && !state.isShareOpen
                    && !state.isAskOpen
                    && state.shareFact == nil
                    && !state.hasEvidencePresentation
            )
            .accessibilityHidden(
                state.isMemorySkyOpen
                    || state.isShareOpen
                    || state.isAskOpen
                    || state.shareFact != nil
                    || state.hasEvidencePresentation
            )
            if state.selectedSection != .card
                && state.selectedSection != .connectors
                && state.selectedSection != .identity
                && !state.isShareOpen
                && state.shareFact == nil
                && !state.isMemorySkyOpen {
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
            if let snapshot = state.snapshot, let fact = state.shareFact {
                NativeShareFactOverlay(state: state, snapshot: snapshot, fact: fact)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            }
            if state.hasEvidencePresentation {
                NativeEvidencePresentation(state: state)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            if let snapshot = state.snapshot, state.isAskOpen {
                NativeAskOverlay(state: state, snapshot: snapshot)
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
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
            if let snapshot = state.snapshot, showsOpeningDossier {
                NativeOpeningDossier(snapshot: snapshot) {
                    showsOpeningDossier = false
                }
                .transition(.opacity)
                .zIndex(200)
            }
        }
        .frame(minWidth: 900, minHeight: 640)
        .ignoresSafeArea()
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

private struct NativeAppTopBar: View {
    @ObservedObject var state: PersonalModelAppState
    @Binding var isMenuOpen: Bool
    @State private var isRecordingPaused = false

    private var statusLabel: String {
        if state.snapshot != nil {
            if state.authorizationLimited { return "Persome · 未授权" }
            if state.isModelForming { return "You · 正在形成模型" }
            return "Persome · 已连接"
        }
        switch state.setupState {
        case "profile_required": return "Personal Model · 等待创建"
        case "not_installed": return "Personal Model · 等待安装"
        case "onboarding_required": return "Personal Model · 等待权限"
        case "backend_unavailable": return "Persome · 未连接"
        default: return "Persome · 连接中"
        }
    }

    private var statusColor: Color {
        if state.authorizationLimited { return .orange }
        if state.snapshot != nil && !state.isModelForming {
            return Color(red: 0.31, green: 0.82, blue: 0.44)
        }
        if state.setupState == "backend_unavailable" { return .gray }
        return Color(red: 0.17, green: 0.45, blue: 0.95)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if isMenuOpen {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture { isMenuOpen = false }
            }

            HStack(spacing: 16) {
                Button {
                    state.closeMemorySky()
                    state.isShareOpen = false
                    if state.isAskOpen { state.closeAsk() }
                    state.selectedSection = .card
                    isMenuOpen = false
                } label: {
                    Text("✳")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("回到 Who Am I Card")

                Text("Who Am I")
                    .font(.system(size: 11.5, weight: .semibold))

                Spacer()

                Button {
                    Task { await state.load() }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(statusLabel)
                            .font(.system(size: 10.5))
                    }
                    .foregroundStyle(Color(red: 0.29, green: 0.29, blue: 0.31))
                }
                .buttonStyle(.plain)
                .help("刷新 Personal Model")

                Button {
                    isMenuOpen.toggle()
                } label: {
                    NativeMenuGlyph()
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open card menu")

                Text("as of now")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(red: 0.16, green: 0.16, blue: 0.18).opacity(0.80))
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .frame(height: 26)
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(0.18))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.black.opacity(0.10))
                    .frame(height: 0.5)
            }

            if isMenuOpen {
                NativeAppTopMenu(
                    state: state,
                    isRecordingPaused: $isRecordingPaused,
                    close: { isMenuOpen = false }
                )
                .padding(.top, 30)
                .padding(.trailing, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.14), value: isMenuOpen)
    }
}

private struct NativeMenuGlyph: View {
    var body: some View {
        Canvas { context, _ in
            var path = Path()
            path.move(to: CGPoint(x: 1.5, y: 4))
            path.addLine(to: CGPoint(x: 8.8, y: 4))
            path.move(to: CGPoint(x: 1.5, y: 7))
            path.addLine(to: CGPoint(x: 12.5, y: 7))
            path.move(to: CGPoint(x: 1.5, y: 10))
            path.addLine(to: CGPoint(x: 6.5, y: 10))
            context.stroke(
                path,
                with: .color(Color(red: 0.16, green: 0.16, blue: 0.18)),
                style: StrokeStyle(lineWidth: 1.2, lineCap: .round)
            )
        }
    }
}

private struct NativeAppTopMenu: View {
    @ObservedObject var state: PersonalModelAppState
    @Binding var isRecordingPaused: Bool
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            NativeTopMenuItem(symbol: "⌕", title: "搜索记忆", shortcut: "⌘K") {
                close()
                state.openSearch()
            }
            NativeTopMenuItem(symbol: "?", title: "问这张卡") {
                close()
                state.openAsk()
            }
            NativeTopMenuDivider()
            NativeTopMenuItem(symbol: "◷", title: "回到某一天") {
                close()
                state.openRewind(dayID: nil)
            }
            NativeTopMenuItem(symbol: "⌁", title: "继续工作") {
                close()
                state.closeMemorySky()
                if state.isAskOpen { state.closeAsk() }
                state.selectedSection = .connectors
            }
            NativeTopMenuItem(symbol: "↗", title: "分享这张卡") {
                close()
                state.openShare()
            }
            NativeTopMenuDivider()
            NativeTopMenuItem(
                symbol: "",
                title: isRecordingPaused ? "记录已暂停 · 恢复" : "正在记录 · 暂停 1 小时",
                dotColor: isRecordingPaused ? .gray : Color(red: 0.31, green: 0.82, blue: 0.44)
            ) {
                isRecordingPaused.toggle()
                close()
            }
        }
        .padding(5)
        .frame(width: 236)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color(red: 0.17, green: 0.17, blue: 0.19).opacity(0.86)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.55), radius: 25, y: 18)
        .foregroundStyle(Color(red: 0.96, green: 0.96, blue: 0.95))
    }
}

private struct NativeTopMenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
    }
}

private struct NativeTopMenuItem: View {
    let symbol: String
    let title: String
    var shortcut: String? = nil
    var dotColor: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                if let dotColor {
                    Circle().fill(dotColor).frame(width: 7, height: 7)
                        .frame(width: 13)
                } else {
                    Text(symbol)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.white.opacity(0.80))
                        .frame(width: 13)
                }
                Text(title)
                    .font(.system(size: 13))
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 29)
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

private struct WhoAmIBackground: View {
    @ViewBuilder
    var body: some View {
        if whoAmIVisualQAOpaque {
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let angle = 200.0 * Double.pi / 180.0
                let directionX = CGFloat(sin(angle))
                let directionY = CGFloat(-cos(angle))
                let gradientLength = abs(width * directionX) + abs(height * directionY)
                let halfLength = gradientLength / 2
                let startPoint = UnitPoint(
                    x: (width / 2 - directionX * halfLength) / width,
                    y: (height / 2 - directionY * halfLength) / height
                )
                let endPoint = UnitPoint(
                    x: (width / 2 + directionX * halfLength) / width,
                    y: (height / 2 + directionY * halfLength) / height
                )
                let shadowColor = Color(red: 60 / 255, green: 70 / 255, blue: 95 / 255)
                ZStack {
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: nativeHexColor("#8E9BB5"), location: 0),
                            .init(color: nativeHexColor("#A9A79E"), location: 0.38),
                            .init(color: nativeHexColor("#C9BEB0"), location: 0.68),
                            .init(color: nativeHexColor("#E4DDD2"), location: 1),
                        ]),
                        startPoint: startPoint,
                        endPoint: endPoint
                    )
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: .white.opacity(0.34), location: 0),
                            .init(color: .white.opacity(0), location: 0.55),
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 1
                    )
                    .frame(width: 2, height: 2)
                    .scaleEffect(x: width * 1.20, y: height * 0.80)
                    .position(x: width * 0.78, y: height * 0.08)
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: shadowColor.opacity(0.22), location: 0),
                            .init(color: shadowColor.opacity(0), location: 0.60),
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 1
                    )
                    .frame(width: 2, height: 2)
                    .scaleEffect(x: width * 0.90, y: height * 0.70)
                    .position(x: width * 0.12, y: height * 0.92)
                }
                .frame(width: width, height: height)
                .clipped()
            }
            .ignoresSafeArea()
        } else {
            Color.clear.ignoresSafeArea()
        }
    }
}

/// Renders the final (non-inset) CSS `box-shadow` term without changing the
/// layout of the view it sits behind. CSS blur radii are diameters, while the
/// Core Graphics blur filter uses a radius, so callers pass half of the CSS
/// blur value. Keeping the spread in the source geometry is important here:
/// SwiftUI's regular `.shadow` cannot express the large negative spread used
/// by the reference Card and Spotlight surfaces.
private struct NativeCSSBoxShadow: View {
    let boxSize: CGSize
    let cornerRadius: CGFloat
    let color: Color
    let blurRadius: CGFloat
    let spread: CGFloat
    let offset: CGSize

    private var canvasSize: CGSize {
        let horizontalRoom = blurRadius * 3 + abs(spread) + abs(offset.width)
        let verticalRoom = blurRadius * 3 + abs(spread) + abs(offset.height)
        return CGSize(
            width: boxSize.width + horizontalRoom * 2,
            height: boxSize.height + verticalRoom * 2
        )
    }

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            context.addFilter(.blur(radius: blurRadius, options: [.dithersResult]))
            let width = max(0, boxSize.width + spread * 2)
            let height = max(0, boxSize.height + spread * 2)
            let rect = CGRect(
                x: (size.width - width) / 2 + offset.width,
                y: (size.height - height) / 2 + offset.height,
                width: width,
                height: height
            )
            let radius = max(0, cornerRadius + spread)
            context.fill(
                Path(roundedRect: rect, cornerRadius: radius),
                with: .color(color)
            )
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// AppKit exposes a live background-filtering primitive. This keeps the
/// desktop/background visible through the Spotlight surface while matching the
/// reference blur and saturation instead of substituting another material.
private struct NativeBackdropFilter: NSViewRepresentable {
    let cornerRadius: CGFloat
    let blurRadius: CGFloat
    let saturation: CGFloat
    let backgroundColor: NSColor

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layerUsesCoreImageFilters = true
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSView) {
        guard let layer = view.layer else { return }
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        layer.masksToBounds = true
        layer.backgroundColor = backgroundColor.cgColor

        let blur = CIFilter(name: "CIGaussianBlur")
        blur?.setValue(blurRadius, forKey: kCIInputRadiusKey)
        let color = CIFilter(name: "CIColorControls")
        color?.setValue(saturation, forKey: kCIInputSaturationKey)
        layer.backgroundFilters = [blur, color].compactMap { $0 }
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
                    .frame(width: 20, height: 13)
                Text("回到卡").font(.system(size: 12.5, weight: .medium))
                Text("esc")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }
            .foregroundStyle(Color(red: 0.96, green: 0.96, blue: 0.95))
            .padding(.leading, 12)
            .padding(.trailing, 18)
            .padding(.vertical, 8)
            .background(Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.90), in: Capsule())
            .shadow(color: .black.opacity(0.50), radius: 17, y: 14)
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
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 41)
                .padding(.bottom, 31)
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
                top: nativeHexColor("#1E1E22"),
                bottom: nativeHexColor("#111113"),
                name: nativeHexColor("#0C0C0E"),
                corner: nativeHexColor("#6E6E73"),
                detail: nativeHexColor("#C8C8CC"),
                glyphOn: nativeHexColor("#F5F5F4"),
                glyphOff: nativeHexColor("#26262A"),
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

/// The original V5 opens as a closed Personal Model dossier before revealing
/// the Card workspace. Keep this as a real native transition instead of
/// skipping straight to the post-open dashboard.
private struct NativeOpeningDossier: View {
    let snapshot: PersonalModelSnapshot
    let dismiss: () -> Void

    @State private var isOpening = false

    private var material: NativeCardMaterial {
        NativeCardMaterial.resolve(snapshot.card?.material)
    }

    private var glyph: [Bool] {
        let source = snapshot.card?.glyph ?? []
        return source.count == 25 ? source : Array(repeating: true, count: 25)
    }

    var body: some View {
        ZStack {
            nativeHexColor("#F1EFE9")

            Text("WHO AM I")
                .font(.system(size: 11, design: .monospaced))
                .tracking(5.5)
                .foregroundStyle(nativeHexColor("#A9A69E"))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 58)

            VStack(spacing: 0) {
                dossier
                Text("tap to open")
                    .font(.system(size: 13))
                    .tracking(0.52)
                    .foregroundStyle(nativeHexColor("#8D8A83"))
                    .padding(.top, 48)
                    .opacity(isOpening ? 0 : 1)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                        value: isOpening
                    )
            }
        }
        .opacity(isOpening ? 0 : 1)
        .animation(.easeOut(duration: 0.8).delay(0.35), value: isOpening)
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Open (snapshot.model.displayName) Personal Card")
        .accessibilityHint("Opens the Personal Card workspace")
        .accessibilityAction { open() }
    }

    private var dossier: some View {
        ZStack {
            innerCard
                .padding(14)
                .offset(y: isOpening ? -24 : 0)
                .scaleEffect(isOpening ? 1.04 : 1)
                .animation(
                    .spring(response: 1.0, dampingFraction: 0.78).delay(0.5),
                    value: isOpening
                )

            cover
                .rotation3DEffect(
                    .degrees(isOpening ? -164 : 0),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .leading,
                    perspective: 0.42
                )
                .opacity(isOpening ? 0 : 1)
                .animation(
                    .timingCurve(0.5, 0.05, 0.2, 1, duration: 1.3),
                    value: isOpening
                )
        }
        .frame(width: 290, height: 388)
    }

    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [material.top, material.bottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.30),
                            .init(
                                color: .white.opacity(material.isLight ? 0.24 : 0.05),
                                location: 0.42
                            ),
                            .init(color: .clear, location: 0.56),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    material.isLight
                        ? Color.black.opacity(0.06)
                        : Color.white.opacity(0.08),
                    lineWidth: 1
                )

            VStack(alignment: .leading) {
                Text("✳")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(material.detail)
                Spacer()
                HStack(alignment: .bottom) {
                    Text("№ \(snapshot.model.memberNumber ?? "001")")
                    Spacer()
                    Text(
                        verbatim: "SINCE \(String(snapshot.model.sinceYear ?? 2026))"
                    )
                }
                .font(.system(size: 9, design: .monospaced))
                .tracking(1.98)
                .foregroundStyle(material.detail.opacity(0.72))
            }
            .padding(26)
        }
        .shadow(color: .black.opacity(0.24), radius: 24, y: 22)
    }

    private var innerCard: some View {
        VStack(spacing: 10) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(7), spacing: 2), count: 5),
                spacing: 2
            ) {
                ForEach(Array(glyph.enumerated()), id: \.offset) { _, isOn in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isOn ? nativeHexColor("#F5F5F4") : nativeHexColor("#2C2C2E"))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(7)
            .frame(width: 59, height: 59)
            .background(nativeHexColor("#161618"), in: RoundedRectangle(cornerRadius: 12))

            Text(snapshot.model.displayName)
                .font(.system(size: 19, weight: .semibold))
                .tracking(-0.19)
                .foregroundStyle(nativeHexColor("#1D1D1F"))

            Text(snapshot.card?.tagline ?? "Personal Model")
                .font(.system(size: 12.5))
                .foregroundStyle(nativeHexColor("#6E6E73"))
                .multilineTextAlignment(.center)

            Text(
                "member № \(snapshot.model.memberNumber ?? "001") · since \(snapshot.model.sinceYear ?? 2026)"
            )
            .font(.system(size: 10, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(nativeHexColor("#AEAEB2"))
        }
        .padding(26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(nativeHexColor("#FEFEFD"), in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(nativeHexColor("#ECECEA"), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 25, y: 20)
    }

    private func open() {
        guard !isOpening else { return }
        isOpening = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_150_000_000)
            dismiss()
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

private struct NativeGuideRing: View {
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60)) { timeline in
            let elapsed = max(0, timeline.date.timeIntervalSince(startedAt))
                .truncatingRemainder(dividingBy: 2.2)
            let linear = min(1, elapsed / 1.54)
            let eased = 1 - pow(1 - linear, 3)
            Circle()
                .stroke(nativeHexColor("#8FA6FF"), lineWidth: 1.2)
                .frame(width: 34, height: 34)
                .shadow(
                    color: nativeHexColor("#8FA6FF").opacity(0.40),
                    radius: 8
                )
                .scaleEffect(0.55 + 0.95 * CGFloat(eased))
                .opacity(elapsed < 1.54 ? 0.9 * (1 - eased) : 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct NativeHeroCard: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot
    @State private var flipped =
        whoAmIVisualQAActive
        && whoAmIVisualQAPresentation?.hasPrefix("card-back") == true
    @State private var drag = CGSize.zero
    @State private var hoverLocation: CGPoint?
    @State private var correction = ""
    @State private var selectedFaceID: String?
    @State private var rootSelected =
        whoAmIVisualQAActive && whoAmIVisualQAPresentation == "card-back-root"
    @State private var guideDone =
        whoAmIVisualQAActive
        && ["card-back-root", "card-back-face"].contains(whoAmIVisualQAPresentation ?? "")

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

    private var cardMemoryCountLabel: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(
            from: NSNumber(value: snapshot.personalModel?.memoryCount ?? 0)
        ) ?? String(snapshot.personalModel?.memoryCount ?? 0)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [material.top, material.bottom],
                        startPoint: materialKey == "graphite"
                            ? UnitPoint(x: 0.2899458868, y: -0.2144335241)
                            : .topLeading,
                        endPoint: materialKey == "graphite"
                            ? UnitPoint(x: 0.7100541132, y: 1.2144335241)
                            : .bottomTrailing
                    )
                )
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            materialKey == "ceramic"
                                ? Color.white.opacity(0.88)
                                : nativeHexColor("#5B79FF")
                                    .opacity(materialKey == "graphite" ? 0.14 : 0.08),
                            .clear,
                        ],
                        center: UnitPoint(x: 0.18, y: -0.10),
                        startRadius: 0,
                        endRadius: materialKey == "graphite" ? 199 : 275
                    )
                )
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(
                                color: .clear,
                                location: materialKey == "graphite" ? 0.34 : 0.32
                            ),
                            .init(
                                color: .white.opacity(material.isLight ? 0.24 : 0.045),
                                location: 0.42
                            ),
                            .init(
                                color: .clear,
                                location: materialKey == "graphite" ? 0.50 : 0.54
                            ),
                        ],
                        startPoint: materialKey == "graphite"
                            ? UnitPoint(x: -0.0314479180, y: 0.1069602807)
                            : .topLeading,
                        endPoint: materialKey == "graphite"
                            ? UnitPoint(x: 1.0314479180, y: 0.8930397193)
                            : .bottomTrailing
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
                .frame(width: 430, height: 430 / 1.586)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .opacity(flipped ? 1 : 0)
                .rotation3DEffect(.degrees(flipped ? 0 : -180), axis: (x: 0, y: 1, z: 0))
                .allowsHitTesting(flipped)
                .accessibilityHidden(!flipped)
        }
        .frame(width: 430, height: 430 / 1.586)
        .background {
            NativeCSSBoxShadow(
                boxSize: CGSize(width: 430, height: 430 / 1.586),
                cornerRadius: 20,
                color: materialKey == "klein"
                    ? Color(red: 0.12, green: 0.20, blue: 0.72).opacity(0.55)
                    : Color.black.opacity(material.isLight ? 0.37 : 0.65),
                blurRadius: 60,
                spread: -24,
                offset: CGSize(width: 0, height: 38)
            )
        }
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
        .task {
            if whoAmIVisualQAPresentation == "card-back-face" {
                selectedFaceID = snapshot.personalModel?.faces?.first?.id
            }
        }
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
                .tracking(1.92)
                .foregroundStyle(material.corner)
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("IDENTITY")
                            .foregroundStyle(material.corner)
                        Text("PERSONAL MODEL")
                            .fontWeight(.medium)
                            .foregroundStyle(material.detail)
                    }
                    .offset(y: 0.5)
                    Spacer()
                    let locatorLines = cardLocator.components(separatedBy: "\n")
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(locatorLines.first ?? "ONE OF ONE")
                            .foregroundStyle(material.corner)
                        Text(locatorLines.dropFirst().first ?? "")
                            .fontWeight(.medium)
                            .foregroundStyle(material.detail)
                    }
                        .offset(y: 0.5)
                        .multilineTextAlignment(.trailing)
                }
                .font(.system(size: 8.5, design: .monospaced))
                .tracking(1.36)
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
                    .shadow(color: .white.opacity(0.22), radius: 0.5, y: 1)
                    .shadow(color: .black.opacity(0.85), radius: 1, y: -1)
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
        .padding(.top, 24)
        .padding(.bottom, 28)
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
        let cardWidth: CGFloat = 430
        let cardHeight: CGFloat = 430 / 1.586
        return ZStack {
                Canvas { context, size in
                    for star in cardStars where !star.isBright {
                        let point = CGPoint(
                            x: size.width * star.x / 100 + star.size / 2,
                            y: size.height * star.y / 100 + star.size / 2
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
                    let starTint = star.isBlue
                        ? nativeHexColor("#8FA6FF")
                        : nativeHexColor("#F5F5F4")
                    Button {
                        guard let face else { return }
                        withAnimation(.easeOut(duration: 0.18)) {
                            selectedFaceID = selectedFaceID == face.id ? nil : face.id
                            rootSelected = false
                            guideDone = true
                        }
                    } label: {
                        Circle()
                            .fill(
                                RadialGradient(
                                    stops: [
                                        .init(color: starTint, location: 0),
                                        .init(color: starTint, location: 0.20),
                                        .init(color: starTint.opacity(0.42), location: 0.3111),
                                        .init(color: starTint.opacity(0.10), location: 0.6667),
                                        .init(color: .clear, location: 1),
                                    ],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 9
                                )
                            )
                            .frame(width: 20, height: 20)
                            .overlay {
                                if selectedFaceID == face?.id {
                                    Circle().stroke(starTint.opacity(0.55), lineWidth: 1)
                                }
                            }
                            .shadow(
                                color: selectedFaceID == face?.id
                                    ? starTint.opacity(0.35)
                                    : .clear,
                                radius: 7
                            )
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .position(
                        x: cardWidth * star.x / 100 + 3,
                        y: cardHeight * star.y / 100 + 3
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
                        guideDone = true
                    }
                } label: {
                    Circle()
                        .fill(
                            RadialGradient(
                                stops: [
                                    .init(color: nativeHexColor("#8FA6FF"), location: 0),
                                    .init(color: nativeHexColor("#8FA6FF"), location: 0.25),
                                    .init(color: nativeHexColor("#8FA6FF").opacity(0.35), location: 0.40),
                                    .init(color: nativeHexColor("#8FA6FF").opacity(0.12), location: 0.70),
                                    .init(color: .clear, location: 1),
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 10
                            )
                        )
                        .frame(width: 22, height: 22)
                        .shadow(
                            color: rootSelected
                                ? nativeHexColor("#8FA6FF").opacity(0.35)
                                : .clear,
                            radius: 7
                        )
                }
                .buttonStyle(.plain)
                .position(x: cardWidth * 0.5, y: cardHeight * 0.44)
                .accessibilityLabel("ROOT · 我是谁")
                if !guideDone {
                    NativeGuideRing()
                        .position(x: cardWidth * 0.5, y: cardHeight * 0.44)
                }

                VStack {
                    HStack {
                        Button("✦ 展开星空") {
                            withAnimation(.spring(response: 0.32)) { state.openMemorySky() }
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
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("ROOT · 我是谁")
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .tracking(2.7)
                                    .foregroundStyle(material.corner)
                                Spacer()
                                Text("← → 巡星")
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .tracking(0.5)
                                    .foregroundStyle(material.corner)
                                Button("×") { rootSelected = false }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 13))
                            }
                            .padding(.bottom, 8)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(material.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.10))
                                    .frame(height: 1)
                            }
                            Text(snapshot.personalModel?.root?.trimmedNonEmpty ?? "Personal Model 正在形成对你的长期理解。")
                                .font(.custom("Iowan Old Style", size: 13.5))
                                .lineSpacing(9.5)
                                .foregroundStyle(material.isLight ? Color.black.opacity(0.88) : Color.white.opacity(0.92))
                                .frame(minHeight: 25.65, alignment: .topLeading)
                                .padding(.top, 11)
                                .lineLimit(3)
                            HStack(spacing: 10) {
                                Text("Persome · 当前快照 · root_live · Persome · 由全部 \(cardMemoryCountLabel) 条记忆推出")
                                    .lineLimit(1)
                                Spacer()
                                Button("出处") {
                                    rootSelected = false
                                    flipped = false
                                    state.openRewind(dayID: snapshot.time?.days?.first?.id)
                                }
                                Button("改写") {
                                    correction = snapshot.personalModel?.root?.trimmedNonEmpty ?? ""
                                }
                                Button("行动") { state.selectedSection = .connectors }
                                Button("分享 ↗") {
                                    let root = snapshot.personalModel?.root?.trimmedNonEmpty
                                        ?? "Personal Model 正在形成对你的长期理解。"
                                    state.openFactShare(
                                        kind: "ROOT",
                                        text: root,
                                        meta: "root_live · 由全部 \(cardMemoryCountLabel) 条记忆推出"
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(material.corner)
                            .padding(.top, 12)
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
                                .padding(.top, 9)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(width: 394)
                        .background(
                            material.isLight
                                ? Color.white.opacity(0.94)
                                : Color(red: 10 / 255, green: 10 / 255, blue: 12 / 255).opacity(0.94),
                            in: RoundedRectangle(cornerRadius: 11)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(material.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.11))
                        )
                        .offset(y: 4)
                    }
                    if let selectedFace = (snapshot.personalModel?.faces ?? []).first(where: { $0.id == selectedFaceID }) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                Text("PERSONAL MODEL · INFERENCE")
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .tracking(2.7)
                                .foregroundStyle(material.corner)
                                Spacer()
                                Text("← → 巡星")
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .tracking(0.5)
                                    .foregroundStyle(material.corner)
                                Button("×") { selectedFaceID = nil }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 13))
                            }
                            .padding(.bottom, 8)
                            .overlay(alignment: .bottom) {
                                Rectangle()
                                    .fill(material.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.10))
                                    .frame(height: 1)
                            }
                            Text(selectedFace.text)
                                .font(.custom("Iowan Old Style", size: 13.5))
                                .lineSpacing(9.5)
                                .foregroundStyle(material.isLight ? Color.black.opacity(0.88) : Color.white.opacity(0.92))
                                .frame(minHeight: 25.65, alignment: .topLeading)
                                .padding(.top, 11)
                                .lineLimit(3)
                            let metadata = selectedFace.truthMetadata(updatedAt: snapshot.personalModel?.updatedAt)
                            HStack(spacing: 10) {
                                Text(metadata.kind.label)
                                if !metadata.detail.isEmpty { Text(metadata.detail).lineLimit(1) }
                                Spacer()
                                Button("出处") {
                                    selectedFaceID = nil
                                    flipped = false
                                    state.openRewind(dayID: snapshot.time?.days?.first?.id)
                                }
                                Button("改写") { correction = selectedFace.text }
                                Button("行动") { state.selectedSection = .connectors }
                                Button("分享 ↗") {
                                    state.openFactShare(
                                        kind: "FACE",
                                        text: selectedFace.text,
                                        meta: [
                                            selectedFace.evidenceRefs?.first,
                                            "来自 Personal Model 证据链",
                                        ].compactMap { $0 }.joined(separator: " · ")
                                    )
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(material.corner)
                            .padding(.top, 12)
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
                                .padding(.top, 9)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(width: 394)
                        .background(
                            material.isLight
                                ? Color.white.opacity(0.94)
                                : Color(red: 10 / 255, green: 10 / 255, blue: 12 / 255).opacity(0.94),
                            in: RoundedRectangle(cornerRadius: 11)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(material.isLight ? Color.black.opacity(0.08) : Color.white.opacity(0.11))
                        )
                        .offset(y: 4)
                    }
                    if !rootSelected && selectedFaceID == nil {
                        HStack(alignment: .bottom) {
                            Text("№ \(snapshot.model.memberNumber ?? "001")")
                                .font(.system(size: 19, weight: .medium))
                                .tracking(1.7)
                                .foregroundStyle(
                                    material.isLight
                                        ? nativeHexColor("#57544E")
                                        : nativeHexColor("#F5F5F4")
                                )
                            Spacer()
                            Text(cardMemoryCountLabel)
                                .font(.system(size: 8.5, design: .monospaced))
                                .tracking(1.7)
                                .foregroundStyle(material.corner)
                        }
                    }
                }
                .padding(.horizontal, 30)
                .padding(.top, 26)
                .padding(.bottom, 22)
        }
        .frame(width: cardWidth, height: cardHeight)
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
    @State private var spotlightPlaceholder = "search your life — 或直接问"
    @FocusState private var searchFocused: Bool

    private var visibleNowItems: [NowItem] {
        (snapshot.now?.items ?? []).filter { item in
            !item.isFutureLike || item.hasReliableSuggestionSource
        }
    }

    private var nowDateLabel: String {
        let value = snapshot.card?.monthYear?.trimmedNonEmpty
            ?? snapshot.personalModel?.updatedAt.flatMap(compactDateLabel)
            ?? "AS OF NOW"
        return value.replacingOccurrences(of: " / ", with: " ")
    }

    private var placeholderPool: [String] {
        visibleNowItems.map(\.displayTitle) + ["想说什么，也可以直接说。"]
    }

    private var placeholderAnimationID: String {
        placeholderPool.joined(separator: "\u{1F}")
    }

    private var futureActionLabel: String {
        guard let future = visibleNowItems.first(where: \.isFutureLike) else {
            return "看看接下来 ›"
        }
        let timing = "\(future.when ?? "") \(future.dayId ?? "")".lowercased()
        return timing.contains("明天") || timing.contains("tomorrow")
            ? "看看明天 ›"
            : "看看接下来 ›"
    }

    private var displayedSpotlightPlaceholder: String {
        if whoAmIVisualQAActive {
            return placeholderPool.first ?? spotlightPlaceholder
        }
        return spotlightPlaceholder
    }

    private var panelRule: some View {
        Rectangle()
            .fill(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.10))
            .frame(height: 1)
            .padding(.horizontal, 18)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 18, weight: .regular))
                    .frame(width: 20, height: 20)
                TextField(
                    "",
                    text: $state.searchQuery,
                    prompt: Text(displayedSpotlightPlaceholder)
                        .foregroundColor(nativeHexColor("#9A968F"))
                )
                    .textFieldStyle(.plain)
                    .font(.system(size: 18, weight: .regular))
                    .focused($searchFocused)
                    .onSubmit { Task { await state.submitSpotlight() } }
                    .tracking(-0.36)
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
                        state.openMemorySky()
                    }
                } label: {
                    Text("✦ 巡星")
                        .padding(.leading, 13)
                        .padding(.trailing, 9)
                        .padding(.vertical, 5)
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(Color.black.opacity(0.10))
                                .frame(width: 1)
                        }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityLabel("展开 Memory Sky")
                Button {
                    state.selectedSection = .connectors
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
            .overlay(alignment: .bottom) { panelRule }

            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text("Now")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(nativeHexColor("#5E5B55"))
                Text("过去 · 现在 · 未来")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(nativeHexColor("#9A968F"))
                Spacer()
                Text(nowDateLabel.uppercased())
                    .font(.system(size: 8.5, design: .monospaced))
                    .tracking(0.85)
                    .foregroundStyle(nativeHexColor("#A8A39A"))
            }
            .padding(.horizontal, 20)
            .offset(y: 2)
            .frame(height: 38)

            if [.success, .insufficient].contains(state.searchPhase),
               let message = state.searchDegradedMessage {
                NativeInlineState(
                    symbol: "exclamationmark.magnifyingglass",
                    title: "当前为关键词降级搜索",
                    detail: message,
                    tint: .orange
                )
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
                        .overlay(alignment: .top) { panelRule }
                }
            case .success:
                ForEach(state.searchResults, id: \.stableID) { result in
                    NativeSearchResultRow(state: state, result: result)
                        .overlay(alignment: .top) { panelRule }
                }
            }

            HStack(spacing: 15) {
                Text("不是待办，只是时间留下的线索")
                    .foregroundStyle(nativeHexColor("#AAA7A0"))
                Spacer()
                Button("时间") { state.selectedSection = .rewind }
                    .buttonStyle(.plain)
                    .foregroundStyle(nativeHexColor("#6E6E73"))
                if visibleNowItems.contains(where: \.isFutureLike) {
                    Button(futureActionLabel) { state.selectedSection = .rewind }
                        .buttonStyle(.plain)
                        .foregroundStyle(nativeHexColor("#6E6E73"))
                }
            }
            .font(.system(size: 10.5, weight: .regular))
            .padding(.horizontal, 21)
            .offset(y: -1)
            .frame(height: 40)
        }
        .background {
            ZStack {
                NativeBackdropFilter(
                    cornerRadius: 19,
                    blurRadius: 42,
                    saturation: 1.25,
                    backgroundColor: NSColor(
                        calibratedRed: 247 / 255,
                        green: 246 / 255,
                        blue: 241 / 255,
                        alpha: 0.91
                    )
                )
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.027), location: 0),
                                .init(color: .clear, location: 0.34),
                                .init(color: .clear, location: 0.72),
                                .init(color: .clear, location: 1),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.94), .clear],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.12)
                    ),
                    lineWidth: 1
                )
        }
        .background {
            NativeCSSBoxShadow(
                boxSize: CGSize(width: 620, height: 325),
                cornerRadius: 19,
                color: .black.opacity(0.38),
                blurRadius: 46,
                spread: -30,
                offset: CGSize(width: 0, height: 30)
            )
        }
        .onChange(of: state.searchFocusRequest) { _ in
            searchFocused = true
        }
        .task(id: placeholderAnimationID) {
            await animateSpotlightPlaceholder()
        }
    }

    @MainActor
    private func animateSpotlightPlaceholder() async {
        let pool = placeholderPool.filter { !$0.isEmpty }
        guard !pool.isEmpty else {
            spotlightPlaceholder = "搜索你记得的事…"
            return
        }
        if whoAmIVisualQAActive {
            spotlightPlaceholder = pool[0]
            return
        }
        var index = 0
        while !Task.isCancelled {
            let phrase = Array(pool[index % pool.count])
            spotlightPlaceholder = ""
            for length in 1...phrase.count {
                guard !Task.isCancelled else { return }
                spotlightPlaceholder = String(phrase.prefix(length))
                try? await Task.sleep(nanoseconds: 95_000_000)
            }
            for _ in 0..<24 {
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: 95_000_000)
            }
            var remaining = phrase
            while !remaining.isEmpty {
                guard !Task.isCancelled else { return }
                remaining.removeLast(min(2, remaining.count))
                spotlightPlaceholder = remaining.isEmpty
                    ? "search your life — 或直接问"
                    : String(remaining)
                try? await Task.sleep(nanoseconds: 95_000_000)
            }
            index = (index + 1) % pool.count
        }
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

    private var copyLabel: String {
        if snapshot.card?.isConfirmedPublished == true,
           let publicURL = snapshot.card?.publicUrl?.trimmedNonEmpty {
            return copied ? "已复制" : "复制 \(publicURL)"
        }
        return copied ? "已复制" : "复制卡片"
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RadialGradient(
                    colors: [nativeHexColor("#17171A"), nativeHexColor("#0B0B0D")],
                    center: .top,
                    startRadius: 0,
                    endRadius: max(proxy.size.width * 0.60, proxy.size.height)
                )
                .ignoresSafeArea()
                NativeShareDust(size: proxy.size)
                VStack(spacing: 22) {
                    NativeSharePoster(snapshot: snapshot, highlight: state.shareHighlight)
                        .frame(width: 320, height: 470.588235)
                    HStack(spacing: 9) {
                        ForEach(
                            [("𝕏", "X"), ("in", "LinkedIn"), ("♥", "Tinder"), ("Ig", "Instagram"), ("♫", "Spotify")],
                            id: \.1
                        ) { target in
                            ShareLink(item: shareText) {
                                Text(target.0)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(nativeHexColor("#D5D5D8"))
                                    .frame(width: 38, height: 38)
                                    .contentShape(Circle())
                                    .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .help(target.1)
                            .accessibilityLabel("分享到 \(target.1)")
                        }
                    }
                    HStack(spacing: 10) {
                        Button {
                            state.copyCard()
                            copied = true
                        } label: {
                            NativeSharePill(label: copyLabel)
                        }
                        .buttonStyle(.plain)
                        Button {
                            state.isShareOpen = false
                            state.selectedSection = .identity
                        } label: {
                            NativeSharePill(label: "My Page · Identity ↗", emphasized: true)
                        }
                        .buttonStyle(.plain)
                        Button {
                            saved = saveSharePoster(snapshot: snapshot, highlight: state.shareHighlight)
                        } label: {
                            NativeSharePill(label: saved ? "已保存" : "存为图片")
                        }
                        .buttonStyle(.plain)
                    }
                }
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        state.isShareOpen = false
                        state.shareHighlight = nil
                    }
                } label: {
                    Text("×")
                        .font(.system(size: 19, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.40))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("关闭分享卡")
                .position(x: proxy.size.width - 28, y: 20)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct NativeShareDust: View {
    let size: CGSize
    @State private var pulsing = false

    var body: some View {
        ForEach(0..<46, id: \.self) { index in
            let diameter: CGFloat = index.isMultiple(of: 3) ? 2 : 1.3
            let baseOpacity: Double = index.isMultiple(of: 4) ? 0.50 : 0.22
            Circle()
                .fill(Color.white.opacity(baseOpacity))
                .frame(width: diameter, height: diameter)
                .opacity(index.isMultiple(of: 5) ? (pulsing ? 1 : 0.45) : 1)
                .position(
                    x: (CGFloat((index * 137) % 97) + 1.5) / 100 * size.width,
                    y: (CGFloat((index * 89) % 93) + 3) / 100 * size.height
                )
                .animation(
                    index.isMultiple(of: 5)
                        ? .easeInOut(duration: Double(3 + index % 4))
                            .repeatForever(autoreverses: true)
                            .delay(Double(index % 6) / 2)
                        : nil,
                    value: pulsing
                )
                .accessibilityHidden(true)
        }
        .onAppear { pulsing = true }
    }
}

private struct NativeSharePill: View {
    let label: String
    var emphasized = false

    var body: some View {
        Text(label)
            .font(.system(size: 12.5))
            .foregroundStyle(emphasized ? nativeHexColor("#1D1D1F") : Color.white.opacity(0.72))
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(emphasized ? nativeHexColor("#F5F5F4") : Color.clear, in: Capsule())
            .overlay {
                if !emphasized {
                    Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1)
                }
            }
            .contentShape(Capsule())
    }
}

private struct NativeSharePoster: View {
    let snapshot: PersonalModelSnapshot
    let highlight: String?

    private var material: NativeCardMaterial {
        NativeCardMaterial.resolve(snapshot.card?.material)
    }

    private var doing: String {
        snapshot.personalModel?.root?.trimmedNonEmpty
            ?? snapshot.identity?.description?.trimmedNonEmpty
            ?? "Personal Model 正在形成"
    }

    private var thinking: String {
        snapshot.identity?.dailyLine?.trimmedNonEmpty
            ?? snapshot.card?.tagline?.trimmedNonEmpty
            ?? "还没有足够依据形成可展示的判断"
    }

    private var identityLine: String {
        snapshot.identity?.dailyLine?.trimmedNonEmpty
            ?? snapshot.identity?.description?.trimmedNonEmpty
            ?? snapshot.card?.tagline?.trimmedNonEmpty
            ?? "Personal Model"
    }

    private var normalizedGlyph: [Bool] {
        let glyph = snapshot.card?.glyph ?? []
        return Array((glyph + Array(repeating: false, count: 25)).prefix(25))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("№ \(snapshot.model.memberNumber ?? "001")")
                Spacer()
                Text("ONE OF ONE")
            }
            .font(.system(size: 8, design: .monospaced))
            .tracking(1.92)
            .foregroundStyle(material.corner)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(0..<5, id: \.self) { row in
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { column in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(normalizedGlyph[row * 5 + column] ? material.glyphOn : material.glyphOff)
                                .frame(width: 4, height: 4)
                        }
                    }
                }
            }
            .frame(width: 28, height: 28, alignment: .topLeading)
            .padding(.top, 28)
            Spacer()
            VStack(alignment: .leading, spacing: 0) {
                Text(highlight?.trimmedNonEmpty ?? identityLine)
                    .font(.system(size: 23, weight: .regular, design: .serif))
                    .lineSpacing(9)
                    .foregroundStyle(material.isLight ? nativeHexColor("#57544E") : nativeHexColor("#F5F5F4"))
                    .lineLimit(4)
                Text("\(snapshot.model.handle) · personal model")
                    .font(.system(size: 10.5))
                    .foregroundStyle(material.corner)
                    .padding(.top, 12)
            }
            Spacer()
            Text(snapshot.model.handle)
                .font(.system(size: 21, weight: .medium))
                .tracking(1.785)
                .foregroundStyle(material.name)
            Text("IDENTITY · PERSONAL MODEL")
                .font(.system(size: 8.5, design: .monospaced))
                .tracking(1.87)
                .foregroundStyle(material.corner)
                .padding(.top, 7)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                GridRow(alignment: .top) {
                    Text("在做").foregroundStyle(material.corner)
                    Text(doing).lineLimit(2)
                }
                GridRow(alignment: .top) {
                    Text("在想").foregroundStyle(material.corner)
                    Text(thinking).lineLimit(2)
                }
            }
            .font(.system(size: 11.5))
            .lineSpacing(6)
            .foregroundStyle(material.isLight ? nativeHexColor("#57544E") : nativeHexColor("#F5F5F4"))
            .padding(.top, 15)
            Divider()
                .overlay(material.isLight ? Color.black.opacity(0.12) : Color.white.opacity(0.14))
                .padding(.top, 17)
            HStack {
                Text(snapshot.card?.isConfirmedPublished == true ? "PUBLIC CUT · SAME MODEL" : "PRIVATE CARD · SAME MODEL")
                Spacer()
                Text(snapshot.card?.monthYear ?? "AS OF NOW")
            }
            .font(.system(size: 7.5, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(material.corner)
            .padding(.top, 12)
        }
        .padding(.top, 26)
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
        .background {
            NativeShareMaterialBackground(material: snapshot.card?.material)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    material.isLight ? Color.black.opacity(0.07) : Color.white.opacity(0.13),
                    lineWidth: 0.7
                )
        )
        .shadow(color: .black.opacity(0.75), radius: 50, y: 30)
    }
}

private struct NativeShareMaterialBackground: View {
    let material: String?

    var body: some View {
        ZStack {
            switch material?.lowercased() {
            case "ceramic":
                LinearGradient(
                    colors: [nativeHexColor("#F7F6F2"), nativeHexColor("#E9E7E1")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [.white, .white.opacity(0)],
                    center: UnitPoint(x: 0.22, y: -0.22),
                    startRadius: 0,
                    endRadius: 260
                )
            case "klein":
                LinearGradient(
                    colors: [nativeHexColor("#3350F0"), nativeHexColor("#2338C8"), nativeHexColor("#1B2CA8")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color.white.opacity(0.20), .clear],
                    center: UnitPoint(x: 0.20, y: -0.20),
                    startRadius: 0,
                    endRadius: 250
                )
            case "graphite":
                LinearGradient(
                    colors: [nativeHexColor("#1E1E22"), nativeHexColor("#111113")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [nativeHexColor("#5B79FF").opacity(0.14), .clear],
                    center: UnitPoint(x: 0.18, y: -0.10),
                    startRadius: 0,
                    endRadius: 250
                )
            default:
                LinearGradient(
                    colors: [nativeHexColor("#48484E"), nativeHexColor("#2E2E33"), nativeHexColor("#232327")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    colors: [Color.white.opacity(0.12), .clear],
                    center: UnitPoint(x: 0.22, y: -0.24),
                    startRadius: 0,
                    endRadius: 260
                )
            }
            LinearGradient(
                colors: [.clear, Color.white.opacity(0.045), .clear],
                startPoint: UnitPoint(x: 0.18, y: 0),
                endPoint: UnitPoint(x: 0.82, y: 1)
            )
        }
    }
}

@MainActor
private func saveSharePoster(snapshot: PersonalModelSnapshot, highlight: String?) -> Bool {
    let renderer = ImageRenderer(
        content: NativeSharePoster(snapshot: snapshot, highlight: highlight)
            .frame(width: 320, height: 470.588235)
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

private struct NativeShareFactOverlay: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot
    let fact: NativeShareFact
    @State private var saved = false

    var body: some View {
        ZStack {
            NativeShareBackdropBlur()
                .ignoresSafeArea()
            Color(red: 15 / 255, green: 15 / 255, blue: 17 / 255)
                .opacity(0.58)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { state.closeFactShare() }

            VStack(spacing: 16) {
                NativeShareFactCard(snapshot: snapshot, fact: fact)

                HStack(spacing: 10) {
                    Button(saved ? "已存 · 去发吧" : "保存图片") {
                        saved = saveShareFactImage(snapshot: snapshot, fact: fact)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Color(red: 0.114, green: 0.114, blue: 0.122))
                    .padding(.horizontal, 20)
                    .frame(height: 38)
                    .background(Color.white, in: Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 7, y: 4)

                    Button("关闭") { state.closeFactShare() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .padding(.horizontal, 18)
                        .frame(height: 38)
                        .overlay(Capsule().stroke(Color.white.opacity(0.28), lineWidth: 1))
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

private struct NativeShareBackdropBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .withinWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.alphaValue = 0.45
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.state = .active
    }
}

private struct NativeShareFactCard: View {
    let snapshot: PersonalModelSnapshot
    let fact: NativeShareFact

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(fact.kind.uppercased()) — IT KNOWS ME")
                .font(.system(size: 8.5, design: .monospaced))
                .tracking(2.72)
                .foregroundStyle(Color(red: 0.66, green: 0.64, blue: 0.60))
                .padding(.bottom, 20)

            Text(fact.text)
                .font(.custom("Iowan Old Style", size: 17))
                .lineSpacing(10.8)
                .foregroundStyle(Color(red: 0.18, green: 0.17, blue: 0.15))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 5.4)

            if fact.isDaily {
                Rectangle()
                    .fill(Color(red: 0.18, green: 0.17, blue: 0.15))
                    .frame(width: 54, height: 1)
                    .padding(.top, 13)
            }

            Text(fact.meta)
                .font(.system(size: 9, design: .monospaced))
                .lineSpacing(1.9)
                .foregroundStyle(Color(red: 0.66, green: 0.64, blue: 0.60))
                .padding(.top, 16)
                .padding(.vertical, 0.95)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 11) {
                NativeShareMiniGlyph(glyph: snapshot.card?.glyph ?? [])
                    .frame(width: 23.5, height: 23.5)

                VStack(alignment: .leading, spacing: 0) {
                    Text("\(snapshot.model.handle) · № \(snapshot.model.memberNumber ?? "001")")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color(red: 0.18, green: 0.17, blue: 0.15))
                        .lineLimit(1)
                        .frame(height: 18.6, alignment: .center)
                    Text(fact.byline)
                        .font(.system(size: 8.5, design: .monospaced))
                        .tracking(0.51)
                        .foregroundStyle(Color(red: 0.66, green: 0.64, blue: 0.60))
                        .lineLimit(1)
                        .frame(height: 24.8, alignment: .center)
                }
                .layoutPriority(1)

                Spacer(minLength: 0)

                Text("QR")
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(Color(red: 0.72, green: 0.70, blue: 0.66))
                    .frame(width: 38, height: 38)
                    .background(
                        Color(red: 0.18, green: 0.17, blue: 0.15),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }
            .padding(.top, 17)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color(red: 0.91, green: 0.89, blue: 0.85))
                    .frame(height: 1)
            }
            .padding(.top, 24)
        }
        .padding(.top, 30)
        .padding(.horizontal, 28)
        .padding(.bottom, 22)
        .frame(width: 320, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.988, green: 0.980, blue: 0.961),
                    Color(red: 0.953, green: 0.937, blue: 0.902),
                ],
                startPoint: UnitPoint(x: 0.62, y: 0),
                endPoint: UnitPoint(x: 0.38, y: 1)
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.95), lineWidth: 1)
                .mask(
                    LinearGradient(
                        colors: [.white, .clear],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
        }
        .shadow(color: .black.opacity(0.52), radius: 41, y: 26)
    }
}

private struct NativeShareMiniGlyph: View {
    let glyph: [Bool]

    var body: some View {
        Canvas { context, _ in
            for index in 0..<25 {
                let column = CGFloat(index % 5)
                let row = CGFloat(index / 5)
                let rect = CGRect(
                    x: column * 5,
                    y: row * 5,
                    width: 3.5,
                    height: 3.5
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1),
                    with: .color(
                        glyph.indices.contains(index) && glyph[index]
                            ? Color(red: 0.18, green: 0.17, blue: 0.15)
                            : Color.black.opacity(0.07)
                    )
                )
            }
        }
        .accessibilityHidden(true)
    }
}

private struct NativeShareFactExport: View {
    let snapshot: PersonalModelSnapshot
    let fact: NativeShareFact

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(fact.kind.uppercased())
                .font(.system(size: 22, design: .monospaced))
                .foregroundStyle(Color(red: 0.60, green: 0.59, blue: 0.56))

            Text(fact.text)
                .font(.custom("Songti SC", size: 52))
                .lineSpacing(25)
                .foregroundStyle(Color(red: 0.18, green: 0.17, blue: 0.15))
                .lineLimit(9)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 78)

            Rectangle()
                .fill(Color(red: 0.18, green: 0.17, blue: 0.15))
                .frame(width: 164, height: 2)
                .padding(.top, 12)

            Text(fact.meta)
                .font(.system(size: 22, design: .monospaced))
                .lineSpacing(12)
                .foregroundStyle(Color(red: 0.60, green: 0.59, blue: 0.56))
                .lineLimit(2)
                .padding(.top, 44)

            Spacer(minLength: 20)

            Rectangle()
                .fill(Color(red: 0.87, green: 0.85, blue: 0.80))
                .frame(height: 2)

            Text("\(snapshot.model.handle) · № \(snapshot.model.memberNumber ?? "001")")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color(red: 0.18, green: 0.17, blue: 0.15))
                .padding(.top, 33)
            Text(fact.byline)
                .font(.system(size: 20, design: .monospaced))
                .foregroundStyle(Color(red: 0.60, green: 0.59, blue: 0.56))
                .padding(.top, 8)
        }
        .padding(.horizontal, 86)
        .padding(.top, 80)
        .padding(.bottom, 68)
        .frame(width: 960, height: 1200, alignment: .topLeading)
        .background(Color(red: 0.973, green: 0.957, blue: 0.922))
        .overlay {
            Rectangle()
                .stroke(Color(red: 0.89, green: 0.87, blue: 0.82), lineWidth: 2)
                .padding(28)
        }
    }
}

@MainActor
private func saveShareFactImage(
    snapshot: PersonalModelSnapshot,
    fact: NativeShareFact
) -> Bool {
    let renderer = ImageRenderer(
        content: NativeShareFactExport(snapshot: snapshot, fact: fact)
    )
    renderer.scale = 1
    guard
        let image = renderer.nsImage,
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let data = bitmap.representation(using: .png, properties: [:]),
        let downloads = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask
        ).first
    else { return false }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    let stem = "WhoAmI-\(formatter.string(from: Date()))"
    var destination = downloads.appendingPathComponent("\(stem).png")
    var suffix = 2
    while FileManager.default.fileExists(atPath: destination.path) {
        destination = downloads.appendingPathComponent("\(stem)-\(suffix).png")
        suffix += 1
    }
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
    let dayID: String?
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
    let dayID: String?
    let shareKind: String
    let shareText: String
    let shareMeta: String
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
    @State private var mode: NativeSkyMode = {
        switch whoAmIVisualQAPresentation {
        case "memory-sky-dust": return .dust
        case "memory-sky-time": return .time
        default: return .constellation
        }
    }()
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
        Color(red: 108 / 255, green: 115 / 255, blue: 149 / 255),
        Color(red: 101 / 255, green: 127 / 255, blue: 114 / 255),
        Color(red: 141 / 255, green: 106 / 255, blue: 90 / 255),
        Color(red: 82 / 255, green: 84 / 255, blue: 91 / 255),
        Color(red: 0.44, green: 0.39, blue: 0.53),
        Color(red: 0.43, green: 0.50, blue: 0.58),
    ]

    private var themes: [NativeConstellationTheme] {
        Array((snapshot.personalModel?.faces ?? []).prefix(6).enumerated()).map {
            index, face in
            NativeConstellationTheme(
                id: index,
                face: face,
                dayID: (snapshot.time?.days ?? []).indices.contains(index)
                    ? snapshot.time?.days?[index].id
                    : nil,
                x: positions[index].0,
                y: positions[index].1,
                size: max(4, 16 - index * 2),
                color: themeColors[index]
            )
        }
    }

    private struct EvidenceFocus {
        let reference: String
        let kind: String
        let title: String
        let detail: String
        let source: String
        let dayID: String

        var text: String {
            [title, detail.trimmedNonEmpty]
                .compactMap { $0 }
                .joined(separator: "。 ")
        }
    }

    private var evidencePool: [EvidenceFocus] {
        (snapshot.time?.days ?? []).flatMap { day in
            (day.events ?? []).compactMap { event in
                guard let reference = event.evidenceRef?.trimmedNonEmpty else { return nil }
                return EvidenceFocus(
                    reference: reference,
                    kind: "REWIND · EVIDENCE",
                    title: event.title,
                    detail: event.detail?.trimmedNonEmpty ?? "",
                    source: "真实事件 · 可回溯",
                    dayID: day.id
                )
            }
        }
    }

    private var reportFaceReferences: [String] {
        var seen = Set<String>()
        let prefix = "\(snapshot.model.id):face:"
        return (snapshot.reports ?? [])
            .flatMap { $0.evidenceRefs ?? [] }
            .filter { $0.hasPrefix(prefix) && seen.insert($0).inserted }
    }

    private func primaryFaceReference(
        for theme: NativeConstellationTheme
    ) -> String? {
        let ordinal = String(format: "%02d", theme.id + 1)
        return reportFaceReferences.first(where: { $0.hasSuffix(":\(ordinal)") })
            ?? (reportFaceReferences.indices.contains(theme.id)
                ? reportFaceReferences[theme.id]
                : nil)
            ?? theme.face.evidenceRefs?.first?.trimmedNonEmpty
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
                let faceReference = primaryFaceReference(for: theme)
                let preservesFaceEvidence = index == 0 && faceReference != nil
                let evidence = bright && !preservesFaceEvidence && !evidencePool.isEmpty
                    ? evidencePool[(theme.id * 7 + index) % evidencePool.count]
                    : nil
                output.append(
                    NativeConstellationStar(
                        id: "theme:\(theme.id):\(index)",
                        themeIndex: theme.id,
                        title: evidence?.kind ?? "Personal Model 推断",
                        detail: evidence?.text ?? theme.face.text,
                        source: evidence?.source ?? theme.face.source ?? "Personal Model",
                        reference: evidence?.reference
                            ?? (bright ? faceReference : nil),
                        dayID: evidence?.dayID
                            ?? (bright ? snapshot.time?.days?.first?.id : nil),
                        shareKind: evidence == nil ? "FACE" : "EVIDENCE",
                        shareText: evidence?.title ?? theme.face.text,
                        shareMeta: evidence.map {
                            "\($0.reference) · 来自 Personal Model 证据链"
                        } ?? [
                            faceReference,
                            "来自 Personal Model 证据链",
                        ].compactMap { $0 }.joined(separator: " · "),
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
                    dayID: nil,
                    shareKind: "",
                    shareText: "",
                    shareMeta: "",
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
            source: "Persome · 当前快照",
            reference: nil,
            dayID: snapshot.time?.days?.first?.id,
            shareKind: "ROOT",
            shareText: snapshot.personalModel?.root?.trimmedNonEmpty
                ?? "Personal Model 正在形成对你的长期理解。",
            shareMeta: "root_live · Persome · 由全部 \(memoryCountLabel) 条记忆推出",
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
            return "只看密度 — 颜色是主题,哪里亮,日子就长在哪里"
        case .time:
            return "由内向外 = 从这周到半年前 · 新记忆亮,旧记忆暗"
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
        ZStack {
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
        }
        .ignoresSafeArea()
        .focusable()
        .onMoveCommand(perform: moveSelection)
        .task(id: state.memorySkyEvidenceRequest) {
            focusRequestedEvidence()
        }
        .task {
            if whoAmIVisualQAPresentation == "memory-sky-root" {
                selectedStar = rootStar
                skyCorrection = ""
            }
        }
        .onExitCommand {
            withAnimation(.easeOut(duration: 0.2)) { state.closeMemorySky() }
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
                            stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white, location: 3 / 14),
                                .init(color: nativeHexColor("#C8D2FF").opacity(0.50), location: 5 / 14),
                                .init(color: nativeHexColor("#C8D2FF").opacity(0.14), location: 9 / 14),
                                .init(color: .clear, location: 1),
                            ],
                            center: .center,
                            startRadius: 0,
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
                        if let dayID = theme.dayID {
                            state.closeMemorySky()
                            state.openRewind(dayID: dayID)
                        } else {
                            selectedStar = skyStars.first {
                                $0.themeIndex == theme.id && $0.isBright
                            }
                            skyCorrection = ""
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text(theme.face.text)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(theme.color)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .shadow(color: .black.opacity(0.9), radius: 5, y: 1)
                            Text("\(theme.face.observations ?? 0) observations")
                                .font(.system(size: 8.5, design: .monospaced))
                                .tracking(0.7)
                                .foregroundStyle(.white.opacity(0.45))
                        }
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
                                .init(color: tint.opacity(1 - Double(star.age / 70)), location: 0),
                                .init(color: tint.opacity(1 - Double(star.age / 70)), location: star.isBig ? 0.26 : 0.19),
                                .init(color: tint.opacity(0.42), location: star.isBig ? 0.38 : 0.29),
                                .init(color: tint.opacity(0.10), location: 0.65),
                                .init(color: .clear, location: 1),
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 10
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
                .offset(
                    x: star.isAmbient ? 0.65 : 1,
                    y: star.isAmbient ? 0.65 : 1
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
                Text("亮星可点 · ← → 巡星 · 点星座名回到那几天")
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
                .font(.custom("Iowan Old Style", size: 13.5))
                .fontWeight(.regular)
                .lineSpacing(9.5)
                .foregroundStyle(.white.opacity(0.96))
                .frame(minHeight: 25.65, alignment: .topLeading)
                .padding(.top, 11)

            HStack(alignment: .firstTextBaseline, spacing: 11) {
                Text(
                    [
                        star.source,
                        star.id == "root" ? star.shareMeta : star.reference,
                    ]
                        .compactMap { $0?.trimmedNonEmpty }
                        .joined(separator: " · ")
                )
                .lineLimit(1)
                Spacer()
                if let dayID = star.dayID {
                    Button("出处") {
                        state.closeMemorySky()
                        state.openRewind(dayID: dayID)
                    }
                } else if let reference = star.reference {
                    Button("出处") { Task { await state.loadEvidence(reference) } }
                } else {
                    Text("尚无 Evidence")
                        .foregroundStyle(.orange.opacity(0.82))
                }
                Button("改写") { skyCorrection = star.detail }
                Button("行动") {
                    state.closeMemorySky()
                    state.selectedSection = .connectors
                }
                Button("分享 ↗") { openFactShare(star) }
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
        .background(
            Color(red: 14 / 255, green: 14 / 255, blue: 18 / 255).opacity(0.92),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.60), radius: 30, y: 16)
    }

    private var returnToCard: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { state.closeMemorySky() }
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

    private func focusRequestedEvidence() {
        guard let reference = state.memorySkyEvidenceRequest?.trimmedNonEmpty else { return }
        let candidates = skyStars.filter(\.isBright)
        guard !candidates.isEmpty else { return }
        if let matching = candidates.first(where: { $0.reference == reference }) {
            selectedStar = matching
        } else {
            selectedStar = candidates[nativeEvidenceSeed(reference) % candidates.count]
        }
        skyCorrection = ""
        if whoAmIVisualQAPresentation?.hasPrefix("share-fact-evidence:") == true,
           let selectedStar {
            openFactShare(selectedStar)
        }
    }

    private func openFactShare(_ star: NativeConstellationStar) {
        guard !star.shareText.isEmpty else { return }
        state.openFactShare(
            kind: star.shareKind,
            text: star.shareText,
            meta: star.shareMeta
        )
    }
}

private func nativeEvidenceSeed(_ reference: String) -> Int {
    var hash: UInt32 = 0
    for scalar in reference.unicodeScalars {
        hash = hash &* 31 &+ scalar.value
    }
    return Int(hash)
}

private func stableUnit(_ value: String, salt: UInt64) -> CGFloat {
    var hash: UInt64 = 14_695_981_039_346_656_037 ^ salt
    for byte in value.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1_099_511_628_211
    }
    return CGFloat(hash % 10_000) / 10_000
}

private struct NativeAskOverlay: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot
    @FocusState private var questionFocused: Bool
    @FocusState private var correctionFocused: Bool
    @State private var correction = ""

    private var placeholder: String {
        snapshot.now?.items?.first?.displayTitle
            ?? "想说什么，也可以直接说。"
    }

    private var answerMeta: String {
        if state.askIsReflection {
            return "倾诉 · 只返回观察，不替你做决定"
        }
        if state.askPhase == .insufficient {
            return "Personal Model · 暂时没有足够个人依据"
        }
        if state.askResponse == nil, !state.answer.isEmpty {
            return "Persome · 最近活动 · ⏎ 下一条"
        }
        return state.askResponse?.source?.trimmedNonEmpty
            ?? "Persome · 本机 Personal Model"
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 20 / 255, green: 20 / 255, blue: 22 / 255)
                    .opacity(0.24)
                .contentShape(Rectangle())
                .onTapGesture { state.closeAsk() }

                VStack(spacing: 0) {
                    HStack {
                        Text("问这张卡")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Button("×") { state.closeAsk() }
                            .buttonStyle(.plain)
                            .font(.system(size: 20, weight: .light))
                            .accessibilityLabel("关闭 Ask")
                    }
                    .foregroundStyle(nativeHexColor("#F5F5F4"))
                    .padding(.horizontal, 4)
                    .padding(.bottom, 9)

                    HStack(spacing: 12) {
                        Text("?")
                            .font(.custom("Iowan Old Style", size: 17))
                            .foregroundStyle(nativeHexColor("#6E6E73"))
                        TextField(placeholder, text: $state.question)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .foregroundStyle(nativeHexColor("#1D1D1F"))
                            .focused($questionFocused)
                            .onSubmit { Task { await state.submitAsk() } }
                            .accessibilityLabel("向 Personal Model 提问")
                        if state.askPhase == .loading {
                            ProgressView()
                                .controlSize(.small)
                                .tint(nativeHexColor("#6E6E73"))
                                .accessibilityLabel("Personal Model 正在回答")
                        }
                    }
                    .padding(.horizontal, 17)
                    .padding(.vertical, 14)
                    .background {
                        NativeBackdropFilter(
                            cornerRadius: 16,
                            blurRadius: 24,
                            saturation: 1.6,
                            backgroundColor: NSColor(
                                calibratedWhite: 1,
                                alpha: 0.55
                            )
                        )
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.40), lineWidth: 1)
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.90), lineWidth: 1)
                            .mask(alignment: .top) {
                                Rectangle().frame(height: 2)
                            }
                    }
                    .shadow(color: .black.opacity(0.18), radius: 18, y: 12)

                    answerCard
                }
                .frame(width: min(620, geometry.size.width - 36))
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
        .ignoresSafeArea()
        .task {
            try? await Task.sleep(nanoseconds: 80_000_000)
            questionFocused = true
            if let presentation = whoAmIVisualQAPresentation,
               presentation.hasPrefix("reflect:") {
                state.searchQuery = String(presentation.dropFirst("reflect:".count))
                await state.submitSpotlight()
            } else if let presentation = whoAmIVisualQAPresentation,
                      presentation.hasPrefix("ask:") {
                state.question = String(presentation.dropFirst("ask:".count))
                await state.submitAsk()
            }
        }
        .onExitCommand { state.closeAsk() }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var answerCard: some View {
        if state.askPhase != .idle || state.askResponse != nil {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    switch state.askPhase {
                    case .loading:
                        Text("正在从你的 Personal Model 里找答案…")
                    case .failure:
                        Text(state.askErrorMessage ?? "这次没有回答成功。恢复本机 Personal Model 连接后再试一次。")
                    case .success, .insufficient:
                        Text(state.askResponse?.answer ?? state.answer)
                    case .idle, .empty:
                        Text(state.answer)
                    }
                }
                .font(.custom("Iowan Old Style", size: 15))
                .fontWeight(.regular)
                .lineSpacing(12.75)
                .foregroundStyle(nativeHexColor("#1D1D1F"))
                .frame(maxWidth: .infinity, minHeight: 27.75, alignment: .topLeading)
                .textSelection(.enabled)

                HStack(spacing: 8) {
                    Text(answerMeta)
                        .lineLimit(1)
                    Button("不对，改写 →") {
                        correction = state.askResponse?.answer ?? state.answer
                        correctionFocused = true
                    }
                    .buttonStyle(.plain)
                    .disabled(state.askPhase == .loading)
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(nativeHexColor("#AEAEB2"))
                .padding(.top, 7)

                if !correction.isEmpty {
                    TextField("改写它 ⏎ — correct_memory", text: $correction)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(nativeHexColor("#1D1D1F"))
                        .padding(.horizontal, 11)
                        .frame(height: 31)
                        .background(.white, in: RoundedRectangle(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(nativeHexColor("#E7E4DE"), lineWidth: 1)
                        }
                        .focused($correctionFocused)
                        .onSubmit {
                            Task {
                                await state.correct(correction)
                                correction = ""
                            }
                        }
                        .padding(.top, 10)
                }
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 15)
            .background(
                Color.white.opacity(0.88),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(nativeHexColor("#1D1D1F"))
                    .frame(width: 2)
                    .clipShape(RoundedRectangle(cornerRadius: 1))
            }
            .shadow(color: .black.opacity(0.32), radius: 16, y: 12)
            .padding(.top, 10)
        }
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
            NativeActivityIcon(text: "Personal Model")
                .frame(width: 34, alignment: .leading)
                .offset(y: 1)
            HStack(spacing: 6) {
                if kindLabel == "未来" {
                    Circle()
                        .stroke(nativeHexColor("#6E6E73"), lineWidth: 1)
                        .frame(width: 11, height: 11)
                        .frame(width: 15, height: 15)
                } else if kindLabel == "现在" {
                    Rectangle()
                        .fill(nativeHexColor("#6E6E73"))
                        .frame(width: 12, height: 1)
                        .frame(width: 15, height: 15)
                        .offset(y: 1.25)
                } else {
                    Text(kindMarker)
                        .font(.custom("Iowan Old Style", size: 15))
                        .foregroundStyle(nativeHexColor("#6E6E73"))
                        .frame(width: 15, height: 15)
                        .offset(y: 0.75)
                }
                Text(kindLabel)
                    .font(.system(size: 10.5))
                    .foregroundStyle(nativeHexColor("#8A8780"))
            }
                .frame(width: 48, alignment: .leading)
                .offset(y: 1)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.displayTitle)
                    .font(
                        Font(
                            NSFont.systemFont(
                                ofSize: 13.5,
                                weight: NSFont.Weight(0.30)
                            )
                        )
                    )
                    .tracking(-0.16)
                    .lineLimit(1)
                if let why = item.why?.trimmedNonEmpty {
                    Text(why)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(nativeHexColor("#8A8780"))
                        .lineLimit(1)
                }
            }
            .offset(y: 0.5)
            Spacer()
            if !item.isFutureLike, let when = item.when?.trimmedNonEmpty {
                Text(when)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(nativeHexColor("#AAA7A0"))
                    .offset(y: 1)
            } else if item.hasReliableSuggestionSource,
                      let when = item.when?.trimmedNonEmpty {
                Text(when)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(nativeHexColor("#AAA7A0"))
                    .offset(y: 1)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 63)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(red: 60 / 255, green: 60 / 255, blue: 67 / 255).opacity(0.10))
                .frame(height: 1)
                .padding(.horizontal, 18)
        }
        .opacity(item.isFutureLike ? 0.76 : 1)
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
                ZStack {
                    RoundedRectangle(cornerRadius: 6.35, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [nativeHexColor("#FAFAF8"), nativeHexColor("#DAD8D2")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 25.375, height: 25.375)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6.23, style: .continuous)
                                .stroke(Color.black.opacity(0.08), lineWidth: 0.25)
                                .frame(width: 25.14, height: 25.14)
                        }
                    Circle()
                        .fill(nativeHexColor("#2C2C2E"))
                        .frame(width: 10, height: 10)
                        .overlay {
                            Circle()
                                .fill(nativeHexColor("#F5F5F2"))
                                .frame(width: 3.2, height: 3.2)
                        }
                }
            }
        }
        .frame(width: 29, height: 29)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Color.black.opacity(0.10), lineWidth: 0.5)
        )
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

    private var latestDay: DaySnapshot? {
        snapshot.time?.days?.first
    }

    private var dailyTitle: String {
        latestDay?.portrait?.trimmedNonEmpty ?? "今天的你"
    }

    private var dailyLine: String {
        latestDay?.portrait?.trimmedNonEmpty
            ?? snapshot.identity?.dailyLine?.trimmedNonEmpty
            ?? "今天还没有足够的证据写下一句话。"
    }

    private var weeklyLines: [String] {
        snapshot.identity?.weeklyLetter ?? []
    }

    private var weekLabel: String {
        guard let dayID = latestDay?.id.trimmedNonEmpty else { return "THIS WEEK" }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: dayID) else { return "THIS WEEK" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return "THIS WEEK"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        let start = formatter.string(from: interval.start).uppercased()
        let endDate = calendar.date(byAdding: .day, value: -1, to: interval.end) ?? interval.end
        let end = formatter.string(from: endDate).uppercased()
        return "\(start) — \(end)"
    }

    private var dayShareKind: String {
        guard let dayID = latestDay?.id.trimmedNonEmpty else { return "TODAY · IDENTITY" }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: dayID) else { return "TODAY · IDENTITY" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return "TODAY · \(formatter.string(from: date).uppercased())"
    }

    private var modelOnlineLabel: String {
        if state.authorizationLimited { return "model unavailable" }
        if state.setupState == "ready" { return "model online" }
        return state.snapshot == nil ? "model unavailable" : "offline snapshot"
    }

    var body: some View {
        GeometryReader { proxy in
            let panelWidth = min(1120, max(0, proxy.size.width - 36))
            let contentWidth = min(820, max(0, panelWidth - 76))
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                nativeHexColor("#121214").opacity(0.72)
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) {
                            Text("\(snapshot.model.displayName)'s space")
                                .fontWeight(.medium)
                                .foregroundStyle(nativeHexColor("#8A8780"))
                            Text("/")
                            Text("Identity")
                                .foregroundStyle(nativeHexColor("#57544E"))
                            Spacer()
                            Text("updated by Personal Model · as of now")
                            Button {
                                state.selectedSection = .card
                            } label: {
                                Text("×")
                                    .font(.system(size: 18))
                                    .foregroundStyle(nativeHexColor("#AAA7A0"))
                                    .frame(width: 18, height: 18)
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.cancelAction)
                            .accessibilityLabel("关闭 Identity")
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(nativeHexColor("#A3A3A8"))

                        VStack(alignment: .leading, spacing: 0) {
                            Text("IDENTITY")
                                .font(.system(size: 9, design: .monospaced))
                                .tracking(3.06)
                                .foregroundStyle(nativeHexColor("#9A968F"))
                            Text(snapshot.model.displayName)
                                .font(.system(size: 50, weight: .semibold))
                                .tracking(-2.25)
                                .foregroundStyle(nativeHexColor("#1D1D1F"))
                                .padding(.top, 22)
                            Text(
                                snapshot.identity?.description?.trimmedNonEmpty
                                    ?? "Personal Model 还没有形成可展示的身份描述。"
                            )
                            .font(.system(size: 21))
                            .lineSpacing(14)
                            .foregroundStyle(nativeHexColor("#77736C"))
                            .padding(.top, 24)

                            HStack(spacing: 20) {
                                NativeGlyph(glyph: snapshot.card?.glyph ?? [])
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(snapshot.model.displayName)
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundStyle(nativeHexColor("#1D1D1F"))
                                    Text(snapshot.card?.tagline ?? "Personal Model")
                                        .font(.system(size: 14))
                                        .foregroundStyle(nativeHexColor("#8A8780"))
                                        .padding(.top, 4)
                                }
                                Spacer(minLength: 0)
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(nativeHexColor("#34C759"))
                                        .frame(width: 7, height: 7)
                                    Text(modelOnlineLabel)
                                }
                                .font(.system(size: 12))
                                .foregroundStyle(nativeHexColor("#77736C"))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .overlay(Capsule().stroke(nativeHexColor("#E7E4DE"), lineWidth: 1))
                            }
                            .padding(.horizontal, 27)
                            .padding(.vertical, 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 19, style: .continuous)
                                    .stroke(nativeHexColor("#E7E4DE"), lineWidth: 1)
                            )
                            .shadow(color: .black.opacity(0.08), radius: 15, y: 8)
                            .padding(.top, 48)

                            NativeIdentityColumnsLayout(spacing: 58) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("TODAY · 一句")
                                        .font(.system(size: 9, design: .monospaced))
                                        .tracking(2)
                                        .foregroundStyle(nativeHexColor("#9A968F"))
                                    Text(dailyTitle)
                                        .font(.custom("Iowan Old Style", size: 25).weight(.medium))
                                        .tracking(-0.625)
                                        .foregroundStyle(nativeHexColor("#1D1D1F"))
                                        .padding(.top, 12)
                                    Button {
                                        selectedLine = selectedLine == dailyLine ? nil : dailyLine
                                    } label: {
                                        Text(dailyLine)
                                            .font(.custom("Iowan Old Style", size: 17))
                                            .lineSpacing(13)
                                            .foregroundStyle(nativeHexColor("#3B3833"))
                                            .underline(selectedLine == dailyLine, color: nativeHexColor("#3B3833"))
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 14)
                                    if selectedLine == dailyLine {
                                        Button("划线分享 ↗") {
                                            state.openFactShare(
                                                kind: dayShareKind,
                                                text: dailyLine,
                                                meta: "\(dailyTitle) · My Page",
                                                byline: "a note from today",
                                                isDaily: true
                                            )
                                        }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(nativeHexColor("#77736C"))
                                        .padding(.top, 10)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 0) {
                                    HStack(alignment: .firstTextBaseline) {
                                        Text("LETTER · THIS WEEK")
                                            .font(.system(size: 9, design: .monospaced))
                                            .tracking(2)
                                            .foregroundStyle(nativeHexColor("#9A968F"))
                                        Spacer()
                                        Text(weekLabel)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(nativeHexColor("#B8B5AE"))
                                    }
                                    if weeklyLines.isEmpty {
                                        Text("本周尚未产生可靠的回顾。")
                                            .font(.custom("Iowan Old Style", size: 15))
                                            .lineSpacing(11)
                                            .foregroundStyle(nativeHexColor("#77736C"))
                                            .padding(.vertical, 12)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .overlay(alignment: .top) {
                                                Rectangle().fill(nativeHexColor("#EEECE7")).frame(height: 1)
                                            }
                                    } else {
                                        ForEach(Array(weeklyLines.enumerated()), id: \.offset) { index, line in
                                            VStack(alignment: .leading, spacing: 0) {
                                                Button {
                                                    selectedLine = selectedLine == line ? nil : line
                                                } label: {
                                                    VStack(alignment: .leading, spacing: 0) {
                                                        if index == 0 {
                                                            Text("ROOT · 本周写下的一句话")
                                                                .font(.system(size: 8.5, design: .monospaced))
                                                                .tracking(1.19)
                                                                .foregroundStyle(nativeHexColor("#9A968F"))
                                                                .padding(.bottom, 6)
                                                        }
                                                        Text(line)
                                                            .font(.custom("Iowan Old Style", size: 15))
                                                            .lineSpacing(11)
                                                            .foregroundStyle(nativeHexColor("#4A4741"))
                                                            .underline(selectedLine == line, color: nativeHexColor("#4A4741"))
                                                            .multilineTextAlignment(.leading)
                                                            .frame(maxWidth: .infinity, alignment: .leading)
                                                    }
                                                    .contentShape(Rectangle())
                                                }
                                                .buttonStyle(.plain)
                                                if selectedLine == line {
                                                    Button("划线分享 ↗") {
                                                        state.openFactShare(
                                                            kind: index == 0 ? "ROOT · THIS WEEK" : "LETTER · THIS WEEK",
                                                            text: line,
                                                            meta: "\(snapshot.model.displayName) · My Page · this week",
                                                            byline: index == 0
                                                                ? "one sentence from my root"
                                                                : "underlined from my weekly letter"
                                                        )
                                                    }
                                                    .buttonStyle(.plain)
                                                    .font(.system(size: 10.5))
                                                    .foregroundStyle(nativeHexColor("#77736C"))
                                                    .padding(.top, 8)
                                                }
                                            }
                                            .padding(.vertical, 12)
                                            .overlay(alignment: .top) {
                                                Rectangle().fill(nativeHexColor("#EEECE7")).frame(height: 1)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.top, 34)
                            .overlay(alignment: .top) {
                                Rectangle().fill(nativeHexColor("#DEDCD6")).frame(height: 1)
                            }
                            .padding(.top, 55)

                            HStack {
                                Text("SAME MODEL · PRIVATE INSIDE / PUBLIC OUTSIDE")
                                    .font(.system(size: 9, design: .monospaced))
                                    .tracking(1.08)
                                    .foregroundStyle(nativeHexColor("#B8B5AE"))
                                Spacer()
                                Button("← 回到分享卡") { state.openShare() }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 11))
                                    .foregroundStyle(nativeHexColor("#77736C"))
                            }
                            .padding(.top, 18)
                            .overlay(alignment: .top) {
                                Rectangle().fill(nativeHexColor("#DEDCD6")).frame(height: 1)
                            }
                            .padding(.top, 42)
                        }
                        .frame(width: contentWidth, alignment: .leading)
                        .padding(.top, 58)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 24)
                    .padding(.horizontal, 38)
                    .padding(.bottom, 64)
                    .frame(width: panelWidth, alignment: .topLeading)
                    .frame(minHeight: max(0, proxy.size.height - 62), alignment: .topLeading)
                    .background(nativeHexColor("#FFFFFF"), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: .black.opacity(0.65), radius: 60, y: 44)
                    .contextMenu {
                        Button("编辑身份") { beginEditingProfile() }
                    }
                    .padding(.top, 18)
                    .padding(.bottom, 44)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
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

private struct NativeIdentityColumnsLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard subviews.count >= 2 else {
            return subviews.first?.sizeThatFits(proposal) ?? .zero
        }
        let width = proposal.width ?? 820
        let available = max(0, width - spacing)
        let leftWidth = available * 0.35
        let rightWidth = available * 0.65
        let left = subviews[0].sizeThatFits(ProposedViewSize(width: leftWidth, height: proposal.height))
        let right = subviews[1].sizeThatFits(ProposedViewSize(width: rightWidth, height: proposal.height))
        return CGSize(width: width, height: max(left.height, right.height))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard subviews.count >= 2 else { return }
        let available = max(0, bounds.width - spacing)
        let leftWidth = available * 0.35
        let rightWidth = available * 0.65
        subviews[0].place(
            at: CGPoint(x: bounds.minX, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: leftWidth, height: nil)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + leftWidth + spacing, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: rightWidth, height: nil)
        )
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
    @State private var selectedFutureDayID: String?
    @State private var selectedEventIndex = 0
    @State private var selectedFrameIndex = -1
    @State private var monthSearch = ""
    @State private var daySearch = ""
    @State private var daySearchAnswer: String?
    @State private var daySearchAnswerTime = "—"
    @State private var isDayRootSelected = false
    @State private var monthYearHovered = false
    @FocusState private var monthSearchFocused: Bool

    private var days: [DaySnapshot] { snapshot.time?.days ?? [] }

    private var reliableFutureItems: [NowItem] {
        (snapshot.now?.items ?? []).filter {
            $0.isFutureLike && $0.hasReliableSuggestionSource && $0.dayId != nil
        }
    }

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
                if let selectedFutureDayID {
                    rewindFutureDay(
                        selectedFutureDayID,
                        items: reliableFutureItems.filter { $0.dayId == selectedFutureDayID }
                    )
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        )
                    )
                } else if let selectedDay {
                    rewindDay(selectedDay)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                } else {
                    rewindMonth
                }
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: screen)
        .onAppear(perform: applyRequestedDay)
        .onChange(of: state.rewindDayRequest) { _ in applyRequestedDay() }
    }

    private func applyRequestedDay() {
        guard
            let requested = state.rewindDayRequest,
            days.contains(where: { $0.id == requested })
        else { return }
        selectedDayID = requested
        selectedFutureDayID = nil
        selectedEventIndex = 0
        selectedFrameIndex = -1
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
                            zoomToMonth: { screen = .month }
                        )
                        .padding(.top, 30)

                        HStack(alignment: .center, spacing: 12) {
                            Text("\(days.count) 个有证据的日期来自当前 Personal Model；空白日期不做推断。")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Color.black.opacity(0.54))
                            Spacer()
                            Text("less")
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(red: 0.945, green: 0.941, blue: 0.925))
                                .frame(width: 9, height: 9)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(red: 0.169, green: 0.278, blue: 0.878).opacity(0.22))
                                .frame(width: 9, height: 9)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(red: 0.169, green: 0.278, blue: 0.878).opacity(0.50))
                                .frame(width: 9, height: 9)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(red: 0.169, green: 0.278, blue: 0.878))
                                .frame(width: 9, height: 9)
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
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(.ultraThinMaterial)
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Color.white.opacity(0.45))
                        }
                    }
                    .overlay {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.90), lineWidth: 1)
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.40), lineWidth: 0.5)
                        }
                    }
                    .shadow(color: .black.opacity(0.20), radius: 30, y: 18)

                    Text(
                        "你的年报 · tap \(nativeMonthName(referenceDate).prefix(3).uppercased()) to zoom back in"
                    )
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
            let panelWidth = max(320, min(980, geometry.size.width - 80))
            let panelHeight = max(430, min(526, geometry.size.height - 112))
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Color.black.opacity(0.46))
                                .accessibilityHidden(true)
                            TextField(
                                "",
                                text: $monthSearch,
                                prompt: Text("search memories…")
                                    .foregroundColor(Color(red: 0.54, green: 0.53, blue: 0.50))
                            )
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
                        .frame(height: 18)
                        .padding(.bottom, 14)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.black.opacity(0.07))
                                .frame(height: 1)
                        }
                        .padding(.bottom, 16)

                        if monthSearchFocused {
                            NativeRewindFilters(
                                days: days,
                                select: openDay
                            )
                            .padding(.bottom, 18)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Button("← \(nativeYearLabel(referenceDate))") { screen = .year }
                                .buttonStyle(.plain)
                                .font(.system(size: 10.5, design: .monospaced))
                                .tracking(0.8)
                                .foregroundStyle(
                                    monthYearHovered
                                        ? Color(red: 0.11, green: 0.11, blue: 0.12)
                                        : Color(red: 0.43, green: 0.43, blue: 0.45)
                                )
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(
                                    monthYearHovered
                                        ? Color(red: 0.933, green: 0.925, blue: 0.906)
                                        : Color.clear,
                                    in: Capsule()
                                )
                                .overlay(
                                    Capsule().stroke(
                                        Color(red: 0.906, green: 0.894, blue: 0.871),
                                        lineWidth: 1
                                    )
                                )
                                .onHover { monthYearHovered = $0 }
                            Text("时间 · \(nativeMonthName(referenceDate))")
                                .font(.system(size: 22, weight: .semibold))
                                .tracking(-0.45)
                            Spacer()
                            Text("日历与记忆星图")
                            .font(.system(size: 11))
                            .foregroundStyle(Color(red: 0.60, green: 0.59, blue: 0.56))
                        }
                        .padding(.bottom, 18)

                        NativeRewindMonthGrid(
                            referenceDate: referenceDate,
                            days: days,
                            futureItems: reliableFutureItems,
                            themeCount: snapshot.personalModel?.faces?.count ?? 0,
                            select: openDay,
                            selectFuture: openFutureDay
                        )
                    }
                    .frame(width: panelWidth - 60, alignment: .topLeading)
                    .padding(.horizontal, 30)
                    .padding(.top, 24)
                    .padding(.bottom, 26)
                    .frame(
                        width: panelWidth,
                        height: panelHeight,
                        alignment: .topLeading
                    )
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(.ultraThinMaterial)
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white.opacity(0.78))
                        }
                    }
                    .overlay(
                        ZStack {
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.92), lineWidth: 1)
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.black.opacity(0.09), lineWidth: 0.5)
                        }
                    )
                    .shadow(color: .black.opacity(0.24), radius: 36, y: 28)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 26)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func rewindDay(_ day: DaySnapshot) -> some View {
        GeometryReader { geometry in
            let cardWidth = max(320, min(1_220, geometry.size.width - 34))
            let documentWidth = min(960, max(0, cardWidth - 76))
            let usesVisualQAFallback = whoAmIVisualQAActive
                && whoAmIVisualQAPresentation?.hasPrefix("rewind-tv-fallback:") == true
            let visibleFrames = usesVisualQAFallback
                ? []
                : state.rewindFrames(for: day.id)
            let screenHeight = max(
                300,
                min(documentWidth * 9 / 16, max(300, geometry.size.height - 290))
            )
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        NativeRewindDayBar(
                            day: day,
                            search: $daySearch,
                            availableWidth: min(1_220, geometry.size.width - 34),
                            back: { screen = .month },
                            submit: {
                                guard locateEvent(in: day) else { return }
                                withAnimation(.easeOut(duration: 0.24)) {
                                    proxy.scrollTo("rewind-day-television", anchor: .top)
                                }
                            }
                        )

                        VStack(alignment: .leading, spacing: 0) {
                            Text("REWIND · MEMORY DOCUMENT")
                                .font(.system(size: 8.5, design: .monospaced))
                                .tracking(1.7)
                                .foregroundStyle(Color(red: 0.60, green: 0.59, blue: 0.56))
                            Text(day.title ?? day.id)
                                .font(.custom("Iowan Old Style", size: 42))
                                .tracking(-1.47)
                                .padding(.top, 13)
                            if let portrait = day.portrait?.trimmedNonEmpty {
                                Text(portrait)
                                    .font(.system(size: 14.5))
                                    .foregroundStyle(Color(red: 0.43, green: 0.43, blue: 0.45))
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
                                frames: visibleFrames,
                                selectedFrameIndex: selectedFrameIndex,
                                select: { index, event in
                                    selectedEventIndex = index
                                    selectedFrameIndex = nativeNearestFrameIndex(
                                        to: event,
                                        in: state.rewindFrames(for: day.id)
                                    ) ?? -1
                                    daySearchAnswer = nil
                                    daySearchAnswerTime = "—"
                                }
                            )
                            .padding(.bottom, 34)

                            NativeRewindTelevision(
                                state: state,
                                day: day,
                                modelID: snapshot.model.id,
                                frames: visibleFrames,
                                frameSource: state.rewindFrameSource(for: day.id),
                                selectedFrameIndex: $selectedFrameIndex,
                                searchAnswer: daySearchAnswer,
                                searchAnswerTime: daySearchAnswerTime,
                                screenHeight: screenHeight,
                                clearSearchAnswer: {
                                    daySearchAnswer = nil
                                    daySearchAnswerTime = "—"
                                }
                            )
                            .id("rewind-day-television")

                            if let letter = day.letter?.trimmedNonEmpty {
                                let letterParts = nativeDayLetterParts(letter)
                                VStack(alignment: .leading, spacing: 0) {
                                    HStack {
                                        Text("ROOT · 今天留下的一句")
                                            .font(.system(size: 8.5, design: .monospaced))
                                            .tracking(1.7)
                                            .foregroundStyle(Color(red: 0.60, green: 0.59, blue: 0.56))
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
                                                .font(.custom("Iowan Old Style", size: 21))
                                                .foregroundStyle(Color(red: 0.18, green: 0.17, blue: 0.15))
                                                .lineSpacing(9)
                                                .underline(
                                                    isDayRootSelected,
                                                    color: Color.black.opacity(0.65)
                                                )
                                            Text(letterParts.description)
                                                .font(.custom("Iowan Old Style", size: 13.5))
                                                .foregroundStyle(Color(red: 0.54, green: 0.53, blue: 0.50))
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
                                .id("rewind-day-root")
                            }

                            Text(day.source?.trimmedNonEmpty ?? "Personal Model · \(snapshot.model.id)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Color.black.opacity(0.28))
                                .padding(.top, 30)
                        }
                        .frame(width: documentWidth, alignment: .topLeading)
                        .padding(.top, 34)
                        .padding(.bottom, 42)
                        .frame(maxWidth: .infinity)
                    }
                    .frame(width: cardWidth)
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
                .task(id: whoAmIVisualQAPresentation) {
                    guard whoAmIVisualQAActive,
                          let presentation = whoAmIVisualQAPresentation
                    else { return }
                    let target: String
                    if presentation.hasPrefix("rewind-tv:")
                        || presentation.hasPrefix("rewind-tv-fallback:") {
                        target = "rewind-day-television"
                    } else if presentation.hasPrefix("rewind-root:") {
                        target = "rewind-day-root"
                    } else {
                        return
                    }
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
        .task(id: "\(snapshot.model.id):\(day.id):rewind-frames") {
            await state.loadRewindFrames(dayId: day.id)
        }
        .onAppear { state.isRewindDayOpen = true }
        .onDisappear { state.isRewindDayOpen = false }
    }

    private func rewindFutureDay(_ dayID: String, items: [NowItem]) -> some View {
        GeometryReader { geometry in
            let cardWidth = min(1_220, max(760, geometry.size.width - 34))
            let documentWidth = min(960, max(0, cardWidth - 76))
            ScrollView {
                VStack(spacing: 0) {
                    NativeRewindFutureDayBar(
                        dayID: dayID,
                        back: {
                            selectedFutureDayID = nil
                            screen = .month
                        }
                    )
                    NativeRewindFutureDocument(
                        dayID: dayID,
                        items: items,
                        modelID: snapshot.model.id
                    )
                    .frame(width: documentWidth, alignment: .topLeading)
                    .padding(.top, 34)
                    .padding(.bottom, 42)
                    .frame(maxWidth: .infinity)
                }
                .frame(width: cardWidth)
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
                .opacity(0.68)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear { state.isRewindDayOpen = true }
        .onDisappear { state.isRewindDayOpen = false }
    }

    @discardableResult
    private func locateEvent(in day: DaySnapshot) -> Bool {
        let rawQuery = daySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = rawQuery.lowercased()
        guard !query.isEmpty else { return false }
        let frames = state.rewindFrames(for: day.id)
        if let frameIndex = frames.firstIndex(where: { frame in
            [frame.time, frame.app, frame.title]
                .map { $0.lowercased() }
                .contains { $0.contains(query) }
        }) {
            let frame = frames[frameIndex]
            selectedEventIndex = -1
            selectedFrameIndex = frameIndex
            daySearchAnswer = "\(frame.time) · \(frame.app) · \(frame.title)"
            daySearchAnswerTime = frame.time
            daySearch = ""
            return true
        }
        let events = day.events ?? []
        let directIndex = events.firstIndex(where: { event in
            [event.time, event.title, event.detail, event.app]
                .compactMap { $0?.lowercased() }
                .contains { $0.contains(query) }
        })
        let fallbackIndex: Int? = {
            guard !events.isEmpty else { return nil }
            if query.range(of: #"下午|afternoon"#, options: .regularExpression) != nil {
                return min(1, events.count - 1)
            }
            if query.range(of: #"晚|night|evening"#, options: .regularExpression) != nil {
                return min(2, events.count - 1)
            }
            if query.range(of: #"早|上午|morning"#, options: .regularExpression) != nil {
                return 0
            }
            return nil
        }()
        if let index = directIndex ?? fallbackIndex {
            selectedEventIndex = index
            let event = events[index]
            selectedFrameIndex = nativeNearestFrameIndex(
                to: event,
                in: frames
            ) ?? -1
            let at = event.time?.trimmedNonEmpty ?? "—"
            let detail = event.detail?.trimmedNonEmpty ?? "这条记录没有附加描述。"
            daySearchAnswer = "\(at) 你在做「\(event.title)」——\(detail)"
            daySearchAnswerTime = at
        } else {
            daySearchAnswer = "这一天没有和「\(rawQuery)」对上的段。"
            daySearchAnswerTime = "—"
        }
        daySearch = ""
        return true
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
        selectedFutureDayID = nil
        selectedEventIndex = 0
        selectedFrameIndex = -1
        daySearch = ""
        daySearchAnswer = nil
        daySearchAnswerTime = "—"
        isDayRootSelected = false
        monthSearchFocused = false
        screen = .day
    }

    private func openFutureDay(_ dayID: String) {
        guard reliableFutureItems.contains(where: { $0.dayId == dayID }) else { return }
        selectedDayID = nil
        selectedFutureDayID = dayID
        selectedEventIndex = 0
        selectedFrameIndex = -1
        daySearch = ""
        daySearchAnswer = nil
        daySearchAnswerTime = "—"
        isDayRootSelected = false
        monthSearchFocused = false
        screen = .day
    }
}

private struct NativeRewindMonthGrid: View {
    let referenceDate: Date
    let days: [DaySnapshot]
    let futureItems: [NowItem]
    let themeCount: Int
    let select: (DaySnapshot) -> Void
    let selectFuture: (String) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 28) {
            NativeMonthCalendar(
                referenceDate: referenceDate,
                days: days,
                futureItems: futureItems,
                select: select,
                selectFuture: selectFuture
            )
            .frame(maxWidth: .infinity)

            NativeRewindApps(
                days: days,
                themeCount: themeCount,
                select: select
            )
            .padding(.leading, 24)
            .frame(width: 218, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color(red: 0.89, green: 0.88, blue: 0.85))
                    .frame(width: 1)
            }
        }
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
                    Button(action: submit) {
                        Text("↵")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.black.opacity(0.24))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("搜索这一天")
                }
                .padding(.horizontal, 11)
                .frame(width: min(320, max(210, (availableWidth + 34) * 0.36)), height: 34)
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
        .background(Color.white.opacity(0.88))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct NativeRewindFutureDayBar: View {
    let dayID: String
    let back: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Button(action: back) {
                Text("‹")
                    .font(.system(size: 23, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.48))
                    .frame(width: 30, height: 30)
                    .contentShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("回到 Rewind 月份")
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Tomorrow")
                .font(.system(size: 14.5, weight: .semibold))
                .tracking(-0.2)

            Text(nativeFullDayLabel(dayID))
                .font(.system(size: 11.5))
                .foregroundStyle(Color.black.opacity(0.48))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
        .background(Color.white.opacity(0.88))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct NativeRewindFutureDocument: View {
    let dayID: String
    let items: [NowItem]
    let modelID: String

    private var narrative: String {
        if items.count == 1 {
            return "Personal Model 从近期有来源的活动里，看见一条可能延续到明天的影子。"
        }
        return "Personal Model 从近期有来源的活动里，看见 \(items.count) 条可能延续到明天的影子。"
    }

    private var foot: String {
        let sources = Array(Set(items.compactMap { $0.truthMetadata.source?.trimmedNonEmpty })).sorted()
        let sourceText = sources.isEmpty ? "Personal Model" : sources.joined(separator: " · ")
        return "PERSONAL MODEL · \(modelID) · \(sourceText)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("TOMORROW · A QUIET PROJECTION")
                .font(.system(size: 8.5, design: .monospaced))
                .tracking(1.7)
                .foregroundStyle(Color(red: 0.60, green: 0.59, blue: 0.56))

            Text(nativeFullDayLabel(dayID))
                .font(.custom("Iowan Old Style", size: 42))
                .tracking(-1.47)
                .padding(.top, 6)

            Text(narrative)
                .font(.system(size: 15))
                .foregroundStyle(Color(red: 0.43, green: 0.43, blue: 0.45))
                .lineSpacing(12)
                .padding(.top, 15)
                .frame(maxWidth: 640, alignment: .leading)

            VStack(spacing: 0) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 14) {
                        NativeActivityIcon(
                            text: item.app?.trimmedNonEmpty
                                ?? item.truthMetadata.source?.trimmedNonEmpty
                                ?? "Personal Model"
                        )
                        .scaleEffect(30 / 36)
                        .frame(width: 34, height: 30, alignment: .leading)

                        Text(item.when?.trimmedNonEmpty ?? "—")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color(red: 0.60, green: 0.59, blue: 0.56))
                            .padding(.top, 3)
                            .frame(width: 58, alignment: .leading)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.displayTitle)
                                .font(.system(size: 16, weight: .medium))
                                .tracking(-0.24)
                                .foregroundStyle(Color.black.opacity(0.88))
                            Text(item.why?.trimmedNonEmpty ?? "这条延续建议没有附加说明。")
                                .font(.system(size: 13))
                                .foregroundStyle(Color(red: 0.54, green: 0.53, blue: 0.50))
                                .lineSpacing(8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Text(nativeFutureConfidenceLabel(item))
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.black.opacity(0.34))
                            .padding(.top, 2)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.vertical, 19)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(Color(red: 0.87, green: 0.86, blue: 0.84))
                            .frame(height: 1)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 38)

            Text("它们不是安排。明天到来时，现实会把这些影子重新写一遍。")
                .font(.custom("Iowan Old Style", size: 14).italic())
                .foregroundStyle(Color(red: 0.60, green: 0.59, blue: 0.56))
                .lineSpacing(8)
                .padding(.top, 18)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(red: 0.87, green: 0.86, blue: 0.84))
                        .frame(height: 1)
                }
                .padding(.top, 16)

            Text(foot)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Color.black.opacity(0.28))
                .padding(.top, 32)
        }
        .padding(.top, 22)
        .padding(.bottom, 34)
        .frame(maxWidth: 760, alignment: .leading)
        .frame(maxWidth: .infinity)
    }
}

private struct NativeYearHeatmap: View {
    let days: [DaySnapshot]
    let referenceDate: Date
    let zoomToMonth: () -> Void

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

    private var monthLabels: [(id: String, text: String)] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM"
        return (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: offset, to: referenceDate)
            else { return nil }
            let components = calendar.dateComponents([.year, .month], from: date)
            return (
                "\(components.year ?? 0)-\(components.month ?? 0)",
                formatter.string(from: date).uppercased()
            )
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let cell = max(8, (proxy.size.width - CGFloat(weekCount - 1) * gap) / CGFloat(weekCount))
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    ForEach(Array(monthLabels.enumerated()), id: \.element.id) { index, month in
                        let canZoom = index >= max(0, monthLabels.count - 2)
                        if canZoom {
                            Button(action: zoomToMonth) {
                                monthLabel(month.text, index: index)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("回到 \(month.text)")
                        } else {
                            monthLabel(month.text, index: index)
                        }
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
        .frame(height: 217)
    }

    private func monthLabel(_ text: String, index: Int) -> some View {
        Text(text)
            .font(
                .system(
                    size: 9.5,
                    weight: index == monthLabels.count - 1 ? .bold : .regular,
                    design: .monospaced
                )
            )
            .tracking(1.14)
            .foregroundStyle(
                index == monthLabels.count - 1
                    ? Color.black.opacity(0.88)
                    : Color.black.opacity(0.28)
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, index == 0 ? 2 : 0)
            .padding(.bottom, 2)
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
            Button(action: zoomToMonth) {
                shape
                    .fill(heatColor(day))
                    .frame(width: size, height: size)
            }
            .buttonStyle(.plain)
            .help("\(day.events?.count ?? 0) memories · \(day.title ?? day.id)")
            .accessibilityLabel("\(day.id)，\(day.events?.count ?? 0) 条记录")
        } else {
            shape
                .fill(Color(red: 0.957, green: 0.953, blue: 0.941))
                .frame(width: size, height: size)
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

    private func heatColor(_ day: DaySnapshot) -> Color {
        let count = day.events?.count ?? 0
        if count >= 4 { return Color(red: 0.169, green: 0.278, blue: 0.878) }
        if count >= 2 { return Color(red: 0.169, green: 0.278, blue: 0.878).opacity(0.45) }
        return Color(red: 0.169, green: 0.278, blue: 0.878).opacity(0.16)
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
            if subview[NativeFlowTrailingKey.self] {
                if lineWidth > 0 && lineWidth + spacing + size.width > availableWidth {
                    maximumWidth = max(maximumWidth, lineWidth)
                    totalHeight += lineHeight + spacing
                    lineHeight = size.height
                } else {
                    lineHeight = max(lineHeight, size.height)
                }
                lineWidth = availableWidth
                continue
            }
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
            if subview[NativeFlowTrailingKey.self] {
                if x > bounds.minX && x + spacing + size.width > bounds.maxX {
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                subview.place(
                    at: CGPoint(x: bounds.maxX - size.width, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(size)
                )
                x = bounds.maxX
                lineHeight = max(lineHeight, size.height)
                continue
            }
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

private struct NativeFlowTrailingKey: LayoutValueKey {
    static let defaultValue = false
}

private struct NativeRewindFilters: View {
    let days: [DaySnapshot]
    let select: (DaySnapshot) -> Void
    @State private var hoveredFilterID: String?

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
                let filterID = "day:\(day.id)"
                Button(index == 0 ? "最近一天" : nativeCompactDayLabel(day.id)) {
                    select(day)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Color(red: 0.23, green: 0.22, blue: 0.20))
                .padding(.horizontal, 13)
                .padding(.vertical, 5)
                .background(
                    Color.white.opacity(hoveredFilterID == filterID ? 1 : 0.75),
                    in: Capsule()
                )
                .overlay(Capsule().stroke(Color.black.opacity(0.07)))
                .onHover { hovering in
                    hoveredFilterID = hovering ? filterID : nil
                }
            }

            if !recentDays.isEmpty && !recentApps.isEmpty {
                Rectangle()
                    .fill(Color.black.opacity(0.09))
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, 3)
            }

            ForEach(recentApps, id: \.name) { app in
                let filterID = "app:\(app.name)"
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
                    .foregroundStyle(Color(red: 0.23, green: 0.22, blue: 0.20))
                    .padding(.leading, 5)
                    .padding(.trailing, 12)
                    .padding(.vertical, 4)
                    .background(
                        Color.white.opacity(hoveredFilterID == filterID ? 1 : 0.75),
                        in: Capsule()
                    )
                    .overlay(Capsule().stroke(Color.black.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    hoveredFilterID = hovering ? filterID : nil
                }
            }
        }
    }
}

private struct NativeMonthCalendar: View {
    let referenceDate: Date
    let days: [DaySnapshot]
    let futureItems: [NowItem]
    let select: (DaySnapshot) -> Void
    let selectFuture: (String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let calendar = Calendar(identifier: .gregorian)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveredDayNumber: Int?
    @State private var todayPulse = false

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
        let canPreview = day != nil || !future.isEmpty
        let previewTitle = !future.isEmpty
            ? "明天的影子 · \(future.count) 个片段"
            : day?.events?.last?.title.trimmedNonEmpty
                ?? day?.title
                ?? ""

        Group {
            if let day {
                Button { select(day) } label: {
                    dayLabel(number, hasMemory: true, futureCount: future.count, isToday: today)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(number)，留下过记忆\(today ? "，今天" : "")")
            } else if !future.isEmpty, let dayID = dayID(number) {
                Button { selectFuture(dayID) } label: {
                    dayLabel(number, hasMemory: false, futureCount: future.count, isToday: today)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(number)，有来源的延续建议")
            } else {
                dayLabel(number, hasMemory: false, futureCount: future.count, isToday: today)
                    .accessibilityLabel(
                        future.isEmpty
                            ? "\(number)\(today ? "，今天" : "，没有记录")"
                            : "\(number)，有来源的延续建议"
                    )
            }
        }
        .overlay(alignment: .top) {
            if canPreview && hoveredDayNumber == number {
                NativeMonthDayPeek(title: previewTitle)
                    .offset(y: -112)
                    .transition(.opacity)
            }
        }
        .background(
            hoveredDayNumber == number && canPreview
                ? Color(red: 0.933, green: 0.925, blue: 0.906)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 9)
        )
        .zIndex(hoveredDayNumber == number ? 20 : 0)
        .onHover { hovering in
            hoveredDayNumber = hovering ? number : nil
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
                                ? Color(red: 0.37, green: 0.37, blue: 0.35)
                                : isToday
                                    ? Color(red: 0.11, green: 0.11, blue: 0.12)
                                    : Color(red: 0.72, green: 0.71, blue: 0.68)
                    )
                    .frame(width: 26, height: 26)
                    .background(
                        hasMemory
                            ? Color(red: 0.173, green: 0.173, blue: 0.180)
                            : futureCount > 0
                                ? Color.white.opacity(0.34)
                                : .clear,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                futureCount > 0 && !hasMemory
                                    ? Color(red: 0.78, green: 0.77, blue: 0.74)
                                    : isToday && !hasMemory
                                        ? Color(red: 0.11, green: 0.11, blue: 0.12)
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
                    .fill(
                        isToday
                            ? Color(red: 0.11, green: 0.11, blue: 0.12)
                            : .clear
                    )
                    .frame(width: 3, height: 3)
                    .opacity(
                        isToday && !reduceMotion
                            ? (todayPulse ? 1 : 0.45)
                            : 1
                    )
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: todayPulse
                    )
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
        .onAppear {
            if !reduceMotion { todayPulse = true }
        }
    }

    private func isToday(_ number: Int) -> Bool {
        guard let month = calendar.dateInterval(of: .month, for: referenceDate),
              let date = calendar.date(byAdding: .day, value: number - 1, to: month.start)
        else { return false }
        return calendar.isDateInToday(date)
    }

    private func dayID(_ number: Int) -> String? {
        guard let month = calendar.dateInterval(of: .month, for: referenceDate),
              let date = calendar.date(byAdding: .day, value: number - 1, to: month.start)
        else { return nil }
        return nativeDayID(date)
    }
}

private struct NativeMonthDayPeek: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.94, blue: 0.93),
                        Color(red: 0.89, green: 0.88, blue: 0.86),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .frame(width: 75, height: 48)
                    .offset(x: -18, y: -6)
                    .shadow(color: .black.opacity(0.10), radius: 4, y: 2)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(red: 0.98, green: 0.98, blue: 0.97))
                    .frame(width: 44, height: 36)
                    .offset(x: 35, y: 12)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            }
            .frame(height: 86)
            .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color(red: 0.96, green: 0.96, blue: 0.95))
                .lineLimit(1)
                .padding(.horizontal, 3)
                .padding(.top, 5)
                .padding(.bottom, 2)
        }
        .padding(6)
        .frame(width: 150)
        .background(
            Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.94),
            in: RoundedRectangle(cornerRadius: 9)
        )
        .shadow(color: .black.opacity(0.40), radius: 17, y: 14)
        .allowsHitTesting(false)
    }
}

private struct NativeRewindApps: View {
    let days: [DaySnapshot]
    let themeCount: Int
    let select: (DaySnapshot) -> Void
    @State private var hoveredApp: String?

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
                .font(.system(size: 8.5, design: .monospaced))
                .tracking(1.7)
                .foregroundStyle(Color(red: 0.60, green: 0.59, blue: 0.56))
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
                            .scaleEffect(28 / 29)
                            .frame(width: 28, height: 28)
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
                .opacity(hoveredApp == row.app ? 0.66 : 1)
                .onHover { hovering in
                    hoveredApp = hovering ? row.app : nil
                }
            }

            Text(note)
                .font(.custom("Iowan Old Style", size: 13))
                .foregroundStyle(Color(red: 0.43, green: 0.43, blue: 0.45))
                .lineSpacing(7)
                .padding(.top, 14)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(red: 0.89, green: 0.88, blue: 0.85))
                        .frame(height: 1)
                }
                .padding(.top, 10)
        }
    }
}


private struct NativeRewindHighlights: View {
    @ObservedObject var state: PersonalModelAppState
    let day: DaySnapshot
    let frames: [RewindFrameSnapshot]
    let selectedFrameIndex: Int
    let select: (Int, EventSnapshot) -> Void
    @State private var hoveredEventID: String?

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
        return Array(output.suffix(3))
    }

    private var currentFrameIndex: Int {
        guard !frames.isEmpty else { return -1 }
        if selectedFrameIndex < 0 { return frames.count - 1 }
        return min(selectedFrameIndex, frames.count - 1)
    }

    private func isSelected(_ event: EventSnapshot) -> Bool {
        nativeNearestFrameIndex(to: event, in: frames) == currentFrameIndex
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

                ForEach(Array(highlights.enumerated()), id: \.element.event.id) { _, highlight in
                    let selected = isSelected(highlight.event)
                    HStack(alignment: .top, spacing: 13) {
                        Button {
                            select(highlight.index, highlight.event)
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
                                        .foregroundStyle(
                                            selected
                                                ? nativeHexColor("#1D1D1F")
                                                : nativeHexColor("#57544E")
                                        )
                                    Text(highlight.event.detail?.trimmedNonEmpty ?? "这条记录没有附加描述。")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(nativeHexColor("#8A8780"))
                                        .lineLimit(1)
                                        .frame(height: 20, alignment: .topLeading)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text("\(String(format: "%02d", highlight.index + 1)) ↗")
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .foregroundStyle(Color.black.opacity(0.28))
                                    .padding(.top, 2)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if let reference = highlight.event.evidenceRef {
                            Button("✦ 证据") {
                                state.openEvidenceSky(reference)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10.5))
                            .foregroundStyle(nativeHexColor("#77736C"))
                            .padding(.top, 1)
                        }
                    }
                    .padding(.vertical, 12)
                    .background(
                        hoveredEventID == highlight.event.id
                            ? Color(red: 0.969, green: 0.965, blue: 0.953)
                            : Color.clear
                    )
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        hoveredEventID = hovering ? highlight.event.id : nil
                    }
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
    @State private var hoveredUpdateID: String?

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
                                .font(.custom("Iowan Old Style", size: 15.5))
                                .foregroundStyle(Color(red: 0.34, green: 0.33, blue: 0.31))
                                .lineSpacing(10)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(minHeight: 29, alignment: .topLeading)
                                .underline(
                                    selectedUpdateID == update.id,
                                    color: Color.black.opacity(0.62)
                                )
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .trailing, spacing: 8) {
                            if let reference = update.evidenceReference {
                                Button("溯源 ↗") {
                                    state.openEvidenceSky(reference)
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
                    .background(
                        hoveredUpdateID == update.id
                            ? Color(red: 0.969, green: 0.965, blue: 0.953)
                            : Color.clear
                    )
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        hoveredUpdateID = hovering ? update.id : nil
                    }
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
    @ObservedObject var state: PersonalModelAppState
    let day: DaySnapshot
    let modelID: String
    let frames: [RewindFrameSnapshot]
    let frameSource: String?
    @Binding var selectedFrameIndex: Int
    let searchAnswer: String?
    let searchAnswerTime: String
    let screenHeight: CGFloat
    let clearSearchAnswer: () -> Void

    private var events: [EventSnapshot] { day.events ?? [] }

    private var currentIndex: Int {
        guard !frames.isEmpty else { return -1 }
        if selectedFrameIndex < 0 { return frames.count - 1 }
        return min(selectedFrameIndex, frames.count - 1)
    }

    private var selectedFrame: RewindFrameSnapshot? {
        guard currentIndex >= 0 else { return nil }
        return frames[currentIndex]
    }

    private var selectedEvent: EventSnapshot? {
        guard let selectedFrame else { return nil }
        let frameMinute = nativeMinuteValue(selectedFrame.time)
        guard let match = events.enumerated().min(by: {
            abs(nativeMinuteValue($0.element.time) - frameMinute)
                < abs(nativeMinuteValue($1.element.time) - frameMinute)
        }), abs(nativeMinuteValue(match.element.time) - frameMinute) <= 30
        else { return nil }
        return match.element
    }

    private var appRows: [(name: String, count: Int)] {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for frame in frames {
            let name = frame.app.trimmedNonEmpty ?? "Unknown"
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        return order.compactMap { name in counts[name].map { (name, $0) } }
    }

    private var chapterLabel: String {
        currentIndex >= 0 ? "\(currentIndex + 1) / \(frames.count)" : "0 / 0"
    }

    private var momentTitle: String {
        selectedFrame?.title.trimmedNonEmpty
            ?? day.title?.trimmedNonEmpty
            ?? day.id
    }

    private var momentDetail: String {
        selectedEvent?.detail?.trimmedNonEmpty
            ?? selectedFrame.map { "\($0.app) · Coast 捕获的真实画面" }
            ?? events.first?.detail?.trimmedNonEmpty
            ?? day.portrait?.trimmedNonEmpty
            ?? "这一天没有可展示的画面描述。"
    }

    private var frameApp: String { selectedFrame?.app ?? "Persome" }
    private var frameTime: String { selectedFrame?.time ?? "—" }
    private var screenTitle: String { selectedFrame?.title ?? "当天没有可用的画面" }

    private var totalDuration: Double {
        frames.reduce(0) { $0 + max(2, $1.duration) }
    }

    private var playhead: CGFloat {
        guard currentIndex >= 0, totalDuration > 0 else { return 0 }
        let before = frames.prefix(currentIndex).reduce(0) { $0 + max(2, $1.duration) }
        let current = max(2, frames[currentIndex].duration)
        return CGFloat((before + current / 2) / totalDuration)
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

                    if let selectedFrame,
                       let image = state.rewindFrameImages[selectedFrame.reference] {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(red: 0.067, green: 0.067, blue: 0.075))
                    } else {
                        VStack(spacing: 15) {
                            Text(frameApp)
                                .font(.system(size: 9, design: .monospaced))
                                .tracking(2)
                                .foregroundStyle(.white.opacity(0.38))
                            Text(screenTitle)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.white.opacity(0.94))
                                .multilineTextAlignment(.center)
                            Text(momentDetail)
                                .font(.system(size: 13))
                                .lineSpacing(10)
                                .foregroundStyle(.white.opacity(0.54))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 560)
                        }
                        .padding(34)
                        .offset(y: 7)
                    }

                    VStack {
                        HStack {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color.white.opacity(0.84))
                                    .frame(width: 6, height: 6)
                                Text(frameApp)
                                    .font(.system(size: 11.5, weight: .medium))
                                Text(frameTime)
                                    .font(.system(size: 9.5, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(nativeHexColor("#161618").opacity(0.68))
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 9)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                            )
                            Spacer()
                        }
                        Spacer()
                        HStack(spacing: 12) {
                            Text(screenTitle)
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
                        .background {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(nativeHexColor("#161618").opacity(0.68))
                            }
                        }
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                    }
                    .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
                }
                .frame(maxWidth: .infinity)
                .frame(height: screenHeight)
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .task(id: selectedFrame?.reference) {
                    if let reference = selectedFrame?.reference {
                        await state.loadRewindFrameImage(reference: reference)
                    }
                }

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
                    NativeTelevisionKnob(rotation: 28)
                    NativeTelevisionKnob(rotation: 80)
                }
                .font(.system(size: 7.5, design: .monospaced))
                .tracking(0.9)
                .foregroundStyle(.white.opacity(0.50))
                .padding(.horizontal, 14)
                .frame(height: 23)
                .padding(.top, 6)
                .padding(.bottom, 7)
            }
            .background(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: nativeHexColor("#353536"), location: 0),
                        .init(color: nativeHexColor("#1D1D1F"), location: 0.58),
                        .init(color: nativeHexColor("#141416"), location: 1),
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 21)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 21)
                    .stroke(Color.black.opacity(0.70), lineWidth: 1)
                RoundedRectangle(cornerRadius: 21)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.35), radius: 24, y: 24)

            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(momentTitle)
                            .font(.system(size: 17, weight: .semibold))
                            .tracking(-0.3)
                        Text(frameTime)
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundStyle(Color.black.opacity(0.34))
                    }
                    Text(momentDetail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.black.opacity(0.44))
                        .lineLimit(1)
                        .frame(height: 22, alignment: .topLeading)
                }
                Spacer()
                HStack(spacing: 7) {
                    Button {
                        guard currentIndex > 0 else { return }
                        selectedFrameIndex = currentIndex - 1
                        clearSearchAnswer()
                    } label: {
                        Text("‹")
                            .font(.system(size: 20))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(Color.black.opacity(0.14)))
                    }
                    .opacity(currentIndex > 0 ? 1 : 0.35)
                    Button {
                        guard currentIndex >= 0, currentIndex < frames.count - 1 else { return }
                        selectedFrameIndex = currentIndex + 1
                        clearSearchAnswer()
                    } label: {
                        Text("›")
                            .font(.system(size: 20))
                            .frame(width: 30, height: 30)
                            .overlay(Circle().stroke(Color.black.opacity(0.14)))
                    }
                    .opacity(currentIndex >= 0 && currentIndex < frames.count - 1 ? 1 : 0.35)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.black.opacity(0.58))
            }
            .padding(.top, 17)

            GeometryReader { geometry in
                let gaps = CGFloat(max(0, frames.count - 1)) * 2
                let segmentWidth = max(0, geometry.size.width - 6 - gaps)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(red: 0.94, green: 0.935, blue: 0.91))
                    if !frames.isEmpty, totalDuration > 0 {
                        HStack(spacing: 2) {
                            ForEach(Array(frames.enumerated()), id: \.element.id) { index, frame in
                                Button {
                                    selectedFrameIndex = index
                                    clearSearchAnswer()
                                } label: {
                                    Capsule()
                                        .fill(nativeHexColor(frame.color))
                                        .opacity(index == currentIndex ? 1 : 0.78)
                                        .overlay {
                                            if index == currentIndex {
                                                Capsule()
                                                    .stroke(Color.white.opacity(0.95), lineWidth: 2)
                                                    .overlay(
                                                        Capsule().stroke(
                                                            Color.black.opacity(0.18),
                                                            lineWidth: 1
                                                        )
                                                    )
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .frame(
                                    width: max(
                                        3,
                                        segmentWidth * CGFloat(max(2, frame.duration) / totalDuration)
                                    )
                                )
                            }
                        }
                        .padding(3)
                    }
                    Rectangle()
                        .fill(Color.black.opacity(0.82))
                        .frame(width: 1)
                        .offset(x: geometry.size.width * playhead - 1)
                    if frames.count > 1 {
                        Slider(
                            value: Binding(
                                get: { Double(max(0, currentIndex)) },
                                set: {
                                    selectedFrameIndex = Int($0.rounded())
                                    clearSearchAnswer()
                                }
                            ),
                            in: 0...Double(frames.count - 1),
                            step: 1
                        )
                        .opacity(0.01)
                    }
                }
            }
            .frame(height: 14)
            .padding(.top, 16)

            HStack {
                Text(frames.first?.time ?? "—")
                Spacer()
                Text(frameTime)
                Spacer()
                Text(frames.last?.time ?? "—")
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
                        Text("\(app.count) frames")
                            .fontWeight(.medium)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(
                        selectedFrame?.app == app.name
                            ? Color(red: 0.11, green: 0.11, blue: 0.12)
                            : Color(red: 0.54, green: 0.53, blue: 0.50)
                    )
                    .fixedSize(horizontal: true, vertical: false)
                }
                Text(
                    frameSource?.trimmedNonEmpty
                        ?? day.source?.trimmedNonEmpty
                        ?? "Personal Model · \(modelID)"
                )
                    .font(.system(size: 10))
                    .foregroundStyle(Color.black.opacity(0.28))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutValue(key: NativeFlowTrailingKey.self, value: true)
            }
            .padding(.top, 14)

            if let searchAnswer {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(searchAnswer)
                    Text("已定位到 \(searchAnswerTime)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.black.opacity(0.48))
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Color.black.opacity(0.82))
                .lineSpacing(6)
                .padding(.vertical, 8)
                .padding(.leading, 13)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color.black.opacity(0.88))
                        .frame(width: 2)
                }
                .padding(.top, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
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

private func nativeHexColor(_ value: String) -> Color {
    let hex = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    guard hex.count == 6, let number = UInt64(hex, radix: 16) else {
        return Color(red: 0.43, green: 0.43, blue: 0.45)
    }
    return Color(
        red: Double((number >> 16) & 0xFF) / 255,
        green: Double((number >> 8) & 0xFF) / 255,
        blue: Double(number & 0xFF) / 255
    )
}

private func nativeMinuteValue(_ value: String?) -> Int {
    let parts = (value ?? "").split(separator: ":")
    guard parts.count == 2,
          let hour = Int(parts[0]),
          let minute = Int(parts[1]),
          (0...23).contains(hour),
          (0...59).contains(minute)
    else { return 0 }
    return hour * 60 + minute
}

private func nativeNearestFrameIndex(
    to event: EventSnapshot,
    in frames: [RewindFrameSnapshot]
) -> Int? {
    guard !frames.isEmpty else { return nil }
    let eventText = "\(event.app ?? "") \(event.title) \(event.detail ?? "")".lowercased()
    let subjects = [
        ["微信", "wechat"],
        ["chatgpt", "codex"],
        ["chrome", "浏览器"],
        ["feishu", "飞书", "lark"],
        ["claude"],
        ["figma"],
        ["notion"],
        ["notes", "备忘录"],
        ["terminal", "开发"],
    ]
    let subject = subjects.first { words in words.contains { eventText.contains($0) } }
    let matching = frames.enumerated().filter { _, frame in
        guard let subject else { return true }
        let frameText = "\(frame.app) \(frame.title)".lowercased()
        return subject.contains { frameText.contains($0) }
    }
    let pool = matching.isEmpty ? Array(frames.enumerated()) : matching
    let eventMinute = nativeMinuteValue(event.time)
    return pool.min {
        abs(nativeMinuteValue($0.element.time) - eventMinute)
            < abs(nativeMinuteValue($1.element.time) - eventMinute)
    }?.offset
}


private func nativeDayDate(_ id: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: id)
}

private func nativeDayID(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date)
}

private func nativeFullDayLabel(_ id: String) -> String {
    guard let date = nativeDayDate(id) else { return id }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "EEEE, MMMM d"
    return formatter.string(from: date)
}

private func nativeFutureConfidenceLabel(_ item: NowItem) -> String {
    if let confidence = item.confidence ?? item.metadata?.confidence, confidence.isFinite {
        return "\(Int((min(1, max(0, confidence)) * 100).rounded()))%"
    }
    return "有来源"
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
    @State private var connectorPickerOpen: Bool
    @State private var expandedReportID: String?

    init(state: PersonalModelAppState, snapshot: PersonalModelSnapshot) {
        self._state = ObservedObject(wrappedValue: state)
        self.snapshot = snapshot
        self._connectorPickerOpen = State(
            initialValue: whoAmIVisualQAActive
                && whoAmIVisualQAPresentation == "connector-picker"
        )
        self._expandedReportID = State(
            initialValue: whoAmIVisualQAActive
                    && whoAmIVisualQAPresentation == "connector-report-expanded"
                ? state.substantiveReports.first?.id
                : nil
        )
    }

    private var connectors: [ConnectorSnapshot] {
        state.connectors.isEmpty ? (snapshot.connectors ?? []) : state.connectors
    }

    private var connectorSlots: [ConnectorSnapshot] {
        let definitions = [
            (id: "claude-code", name: "Claude", product: "Claude Code"),
            (id: "codex", name: "GPT", product: "Codex"),
        ]
        return definitions.map { definition in
            connectors.first(where: {
                $0.id == definition.id
                    || $0.name.lowercased().contains(definition.name.lowercased())
            }) ?? ConnectorSnapshot(
                id: definition.id,
                name: definition.name,
                product: definition.product,
                status: "missing",
                sessionId: nil,
                installed: false
            )
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let modalWidth = min(720, max(320, geometry.size.width - 32))
            let modalHeight = min(790, max(360, geometry.size.height - 48))
            ZStack {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.42)
                    Color.black.opacity(0.22)
                }
                    .ignoresSafeArea()
                    .onTapGesture { close() }

                ScrollViewReader { scrollProxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .top, spacing: 16) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("PERSONAL MODEL · MODEL PASS")
                                    .font(.system(size: 8.5, design: .monospaced))
                                    .tracking(1.7)
                                    .foregroundStyle(Color(red: 0.60, green: 0.59, blue: 0.56))
                                Text("Swipe your card")
                                    .font(.custom("Iowan Old Style", size: 31))
                                    .tracking(-0.93)
                                    .foregroundStyle(
                                        Color(red: 0.114, green: 0.114, blue: 0.122)
                                            .opacity(0.90)
                                    )
                                    .padding(.top, 8)
                                Text("把你的 Personal Card 刷给 Agent。刷过以后，它们戴上这张卡；完成的工作会收成一页结果。")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(
                                        Color(red: 0.47, green: 0.45, blue: 0.42)
                                            .opacity(0.82)
                                    )
                                    .lineSpacing(7)
                                    .frame(minHeight: 22, alignment: .top)
                                    .padding(.top, 10)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button(action: close) {
                                Text("×")
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundStyle(Color(red: 0.47, green: 0.45, blue: 0.42))
                                    .frame(width: 28, height: 28)
                                    .background(
                                        Color(red: 0.925, green: 0.918, blue: 0.898),
                                        in: Circle()
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("关闭 Connector")
                        }

                        NativeConnectorSwipe(
                            state: state,
                            snapshot: snapshot,
                            connectors: connectors,
                            badgeConnectors: connectorSlots
                        )
                        .padding(.top, 18)

                        if let message = state.connectorErrorMessage {
                            Text(message)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color(red: 0.60, green: 0.36, blue: 0.30))
                                .lineSpacing(6)
                                .padding(.horizontal, 11)
                                .padding(.vertical, 9)
                                .background(
                                    Color(red: 0.96, green: 0.925, blue: 0.905),
                                    in: RoundedRectangle(cornerRadius: 9)
                                )
                                .padding(.top, 12)
                        }

                        HStack(spacing: 8) {
                            ForEach(connectorSlots) { connector in
                                NativeConnectorTile(connector: connector)
                                    .frame(maxWidth: .infinity)
                            }
                            Button {
                                withAnimation(.easeOut(duration: 0.16)) {
                                    connectorPickerOpen.toggle()
                                }
                            } label: {
                                HStack(spacing: 7) {
                                    Text("＋")
                                        .font(.system(size: 15, weight: .regular))
                                        .frame(width: 20, height: 20)
                                        .background(
                                            Color(red: 0.91, green: 0.90, blue: 0.88),
                                            in: Circle()
                                        )
                                    Text("其他 Agent").font(.system(size: 10.5))
                                }
                                .foregroundStyle(Color(red: 0.47, green: 0.45, blue: 0.42))
                                .frame(maxWidth: .infinity, minHeight: 53)
                                .background(Color.white.opacity(0.28))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 11)
                                        .stroke(
                                            Color(red: 0.82, green: 0.81, blue: 0.78),
                                            style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .overlay(alignment: .topTrailing) {
                            if connectorPickerOpen {
                                NativeConnectorPicker()
                                    .frame(width: 246)
                                    .offset(y: 61)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                                    .zIndex(4)
                            }
                        }
                        .zIndex(connectorPickerOpen ? 4 : 0)
                        .padding(.top, 17)

                            NativeConnectorPagesSection(
                                state: state,
                                reports: state.substantiveReports,
                                expandedReportID: $expandedReportID
                            )
                            .padding(.top, 24)
                            .id("connector-pages")
                        }
                        .padding(.top, 25)
                        .padding(.horizontal, 30)
                        .padding(.bottom, 30)
                    }
                    .scrollIndicators(.hidden)
                    .frame(width: modalWidth, height: modalHeight)
                    .task {
                        guard whoAmIVisualQAActive,
                              whoAmIVisualQAPresentation == "connector-report-expanded"
                        else { return }
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        if let expandedReportID {
                            scrollProxy.scrollTo(
                                "connector-report-\(expandedReportID)",
                                anchor: .top
                            )
                        }
                    }
                }
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(.ultraThickMaterial)
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(red: 0.976, green: 0.976, blue: 0.968).opacity(0.90))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    ZStack {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.white, lineWidth: 1)
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.black.opacity(0.11), lineWidth: 0.5)
                    }
                }
                .shadow(color: .black.opacity(0.45), radius: 50, y: 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func close() {
        connectorPickerOpen = false
        state.selectedSection = .card
    }
}

private struct NativeConnectorTile: View {
    let connector: ConnectorSnapshot

    private var displayedName: String {
        connector.id == "codex" ? "GPT" : connector.name
    }

    private var status: String {
        switch connector.status?.lowercased() {
        case "connected": return "戴着你的卡"
        case "connecting": return "正在连接"
        case "available": return "等待刷卡"
        default: return "未发现应用"
        }
    }

    private var dot: Color {
        connector.status == "connected"
            ? Color(red: 0.20, green: 0.78, blue: 0.35)
            : Color(red: 0.67, green: 0.65, blue: 0.61)
    }

    var body: some View {
        HStack(spacing: 8) {
            NativeActivityIcon(text: connector.id)
                .scaleEffect(0.72)
                .frame(width: 27, height: 27)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle().fill(dot).frame(width: 5, height: 5)
                    Text(displayedName)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                }
                Text(status)
                    .font(.system(size: 8))
                    .foregroundStyle(Color(red: 0.63, green: 0.61, blue: 0.59))
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 53, alignment: .leading)
        .background(Color.white.opacity(0.48), in: RoundedRectangle(cornerRadius: 11))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color(red: 0.89, green: 0.88, blue: 0.85), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityHint(
            connector.status == "missing"
                ? "本机未安装，当前无法连接"
                : status
        )
    }
}

private struct NativeConnectorPicker: View {
    private let options = [
        (glyph: "◩", name: "Cursor", sub: "MCP connector"),
        (glyph: "✦", name: "Gemini", sub: "MCP connector"),
        (glyph: "＋", name: "Other Agent", sub: "Bring your own MCP client"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text("让更多 Agent 戴上这张卡")
                    .font(.system(size: 12, weight: .semibold))
                Text("任何支持 MCP 的 Agent 都可以成为 connector。")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color(red: 0.60, green: 0.59, blue: 0.56))
                    .lineSpacing(5)
                    .padding(.top, 3)
            }
            .padding(.horizontal, 7)
            .padding(.top, 5)
            .padding(.bottom, 9)
            ForEach(options, id: \.name) { option in
                HStack(spacing: 8) {
                    Text(option.glyph)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.36, green: 0.35, blue: 0.33))
                        .frame(width: 24, height: 24)
                        .background(
                            Color(red: 0.925, green: 0.918, blue: 0.898),
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(option.name).font(.system(size: 11, weight: .semibold))
                        Text(option.sub)
                            .font(.system(size: 7.5))
                            .foregroundStyle(Color(red: 0.67, green: 0.65, blue: 0.62))
                    }
                    Spacer()
                    Text("MCP")
                        .font(.system(size: 6, design: .monospaced))
                        .foregroundStyle(Color(red: 0.67, green: 0.65, blue: 0.62))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 8)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color(red: 0.925, green: 0.918, blue: 0.90))
                        .frame(height: 1)
                }
            }
        }
        .padding(9)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 13).fill(.ultraThickMaterial)
                RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.86))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 13)
                .stroke(Color(red: 0.87, green: 0.86, blue: 0.83), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 25, y: 16)
    }
}

private struct NativeConnectorSwipe: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot
    let connectors: [ConnectorSnapshot]
    let badgeConnectors: [ConnectorSnapshot]
    @State private var dragOffset: CGFloat = 0
    @State private var isSwiping = false

    private var availableConnectors: [ConnectorSnapshot] {
        connectors.filter {
            $0.status != "missing" && $0.installed != false
        }
    }

    private var done: Bool {
        !availableConnectors.isEmpty
            && availableConnectors.allSatisfy { $0.status == "connected" }
    }

    private var swipeLabel: String {
        if isSwiping { return "正在刷卡…" }
        if done {
            let names = availableConnectors.map { $0.id == "codex" ? "GPT" : $0.name }
            return "\(names.joined(separator: " 与 ")) 已戴上你的卡"
        }
        return "Swipe your Personal Card"
    }

    private var swipeHint: String {
        if isSwiping { return "正在把 \(snapshot.model.handle) 交给新的协作者" }
        if done { return "它们现在带着同一份你继续工作" }
        if availableConnectors.isEmpty { return "本机暂未发现可以刷卡的 Agent" }
        return "刷一下，让 Agent 戴上你的工牌"
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ZStack {
                    RoundedRectangle(cornerRadius: 17)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(
                                        red: 240.0 / 255.0,
                                        green: 239.0 / 255.0,
                                        blue: 235.0 / 255.0
                                    ),
                                    Color(
                                        red: 232.0 / 255.0,
                                        green: 230.0 / 255.0,
                                        blue: 224.0 / 255.0
                                    ),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay {
                            ZStack {
                                RoundedRectangle(cornerRadius: 17)
                                    .stroke(Color.black.opacity(0.10), lineWidth: 0.5)
                                RoundedRectangle(cornerRadius: 17)
                                    .stroke(Color.white.opacity(0.90), lineWidth: 0.5)
                            }
                        }

                    VStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 17)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(stops: [
                                        .init(
                                            color: Color(
                                                red: 59.0 / 255.0,
                                                green: 59.0 / 255.0,
                                                blue: 62.0 / 255.0
                                            ),
                                            location: 0
                                        ),
                                        .init(
                                            color: Color(
                                                red: 32.0 / 255.0,
                                                green: 32.0 / 255.0,
                                                blue: 35.0 / 255.0
                                            ),
                                            location: 0.64
                                        ),
                                        .init(
                                            color: Color(
                                                red: 23.0 / 255.0,
                                                green: 23.0 / 255.0,
                                                blue: 25.0 / 255.0
                                            ),
                                            location: 1
                                        ),
                                    ]),
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
                    .position(x: proxy.size.width * 0.47, y: 95)

                    NativeMiniPass(snapshot: snapshot)
                        .frame(width: 184, height: 108)
                        .rotationEffect(.degrees(isSwiping ? 0 : -3))
                        .offset(x: isSwiping ? proxy.size.width * 0.72 : dragOffset)
                        .opacity(isSwiping ? 0 : 1)
                        .position(x: proxy.size.width * 0.05 + 92, y: 95)
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

                    ForEach(Array(badgeConnectors.prefix(2).enumerated()), id: \.element.id) { index, connector in
                        NativeAgentBadge(connector: connector, snapshot: snapshot)
                            .frame(width: 92, height: 178)
                            .position(
                                x: proxy.size.width - (index == 0 ? 163 : 59),
                                y: 94
                            )
                            .zIndex(Double(3 - index))
                    }
                    Text("YOUR CARD")
                        .font(.system(size: 6, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                        .position(x: 48, y: 179)
                    Text("AGENTS WEARING IT")
                        .font(.system(size: 6, design: .monospaced))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                        .position(x: proxy.size.width - 76, y: 179)
                }
                .contentShape(RoundedRectangle(cornerRadius: 17))
                .onTapGesture { beginSwipe() }
            }
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 17))

            Button(swipeLabel) {
                beginSwipe()
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color(red: 0.96, green: 0.96, blue: 0.95))
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                Color(red: 0.11, green: 0.11, blue: 0.12),
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
            }
            .padding(.top, 10)

            Text(swipeHint)
                .font(.system(size: 10.5))
                .foregroundStyle(Color(red: 0.60, green: 0.59, blue: 0.56))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 8)
        }
        .accessibilityElement(children: .contain)
    }

    private func beginSwipe() {
        guard
            !done,
            !isSwiping,
            !availableConnectors.isEmpty,
            state.connectingConnector.isEmpty
        else { return }
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
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("№ \(snapshot.model.memberNumber ?? "001")")
                Spacer()
                Text("PERSONAL CARD")
            }
            .font(.system(size: 6, design: .monospaced))
            .tracking(1.08)
            .foregroundStyle(Color.white.opacity(0.52))

            HStack(spacing: 10) {
                NativeCompactGlyph(glyph: snapshot.card?.glyph ?? [])
                    .frame(width: 21, height: 21)
                Text(snapshot.model.handle)
                    .font(.system(size: 14, weight: .medium))
                    .tracking(0.28)
            }
            .padding(.top, 17)
            Spacer()
            HStack {
                Text("WHO AM I")
                Spacer()
                Text("ONE OF ONE")
            }
            .font(.system(size: 5.8, design: .monospaced))
            .tracking(0.58)
            .foregroundStyle(Color.white.opacity(0.48))
        }
        .foregroundStyle(Color(red: 0.96, green: 0.96, blue: 0.95))
        .padding(.horizontal, 15)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.21, green: 0.21, blue: 0.22),
                    Color(red: 0.095, green: 0.095, blue: 0.106),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.black.opacity(0.80), lineWidth: 0.5)
            }
        }
        .shadow(color: .black.opacity(0.80), radius: 15, y: 10)
    }
}

private struct NativeCompactGlyph: View {
    let glyph: [Bool]

    private var normalized: [Bool] {
        glyph.count == 25 ? glyph : Array(repeating: true, count: 25)
    }

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(3), spacing: 1.4), count: 5),
            spacing: 1.4
        ) {
            ForEach(Array(normalized.enumerated()), id: \.offset) { _, isOn in
                RoundedRectangle(cornerRadius: 0.6)
                    .fill(isOn ? Color.white : Color.white.opacity(0.18))
                    .frame(width: 3, height: 3)
            }
        }
    }
}

private struct NativeAgentBadge: View {
    let connector: ConnectorSnapshot
    let snapshot: PersonalModelSnapshot

    private var worn: Bool { connector.status == "connected" }
    private var connecting: Bool { connector.status == "connecting" }
    private var displayedName: String { connector.id == "codex" ? "GPT" : connector.name }
    private var badgeNumber: String { connector.id == "claude-code" ? "01" : "02" }
    private var statusText: String {
        connecting ? "CONNECTING" : worn ? "WEARING YOUR CARD" : "WAITING"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Capsule()
                .fill(worn ? Color(red: 0.28, green: 0.275, blue: 0.26) : Color(red: 0.79, green: 0.78, blue: 0.75))
                .frame(width: 4, height: 69)
                .rotationEffect(.degrees(-15), anchor: .bottom)
                .position(x: 25, y: 15.5)
            Capsule()
                .fill(worn ? Color(red: 0.28, green: 0.275, blue: 0.26) : Color(red: 0.79, green: 0.78, blue: 0.75))
                .frame(width: 4, height: 69)
                .rotationEffect(.degrees(15), anchor: .bottom)
                .position(x: 67, y: 15.5)
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.49, green: 0.48, blue: 0.47), Color(red: 0.30, green: 0.30, blue: 0.29)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 16, height: 12)
                .position(x: 46, y: 48)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    NativeActivityIcon(text: connector.id)
                        .scaleEffect(0.60)
                        .frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(displayedName)
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                        Text("\((connector.product ?? connector.name).uppercased()) · \(badgeNumber)")
                            .font(.system(size: 5.5, design: .monospaced))
                            .foregroundStyle(Color(red: 0.60, green: 0.58, blue: 0.55))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Circle()
                        .fill(
                            connecting
                                ? Color(red: 0.82, green: 0.66, blue: 0.29)
                                : worn
                                    ? Color(red: 0.20, green: 0.78, blue: 0.35)
                                    : Color(red: 0.72, green: 0.70, blue: 0.67)
                        )
                        .frame(width: 5, height: 5)
                }

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.20, green: 0.20, blue: 0.22), Color(red: 0.095, green: 0.095, blue: 0.106)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    VStack(alignment: .leading, spacing: 0) {
                    Text("PERSONAL CARD")
                            .font(.system(size: 4.8, design: .monospaced))
                            .tracking(0.67)
                        .foregroundStyle(.white.opacity(0.45))
                    Text(snapshot.model.handle)
                            .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white)
                            .padding(.top, 9)
                    HStack {
                        Spacer()
                        Text("№ \(snapshot.model.memberNumber ?? "001")")
                                .font(.system(size: 4.5, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                        .padding(.top, 4)
                    }
                    .padding(8)
                }
                .frame(height: 51)
                .opacity(worn ? 1 : 0.14)
                .padding(.top, 8)

                Text(statusText)
                    .font(.system(size: 4.8, design: .monospaced))
                    .tracking(0.38)
                    .foregroundStyle(Color(red: 0.67, green: 0.65, blue: 0.62))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 6)
            }
            .padding(9)
            .frame(width: 92, height: 116)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.98, green: 0.98, blue: 0.97), Color(red: 0.93, green: 0.92, blue: 0.90)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.13), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.45), radius: 12, y: 8)
            .position(x: 46, y: 110)
        }
        .accessibilityElement(children: .combine)
    }
}

private func nativeConnectorDisplayName(_ value: String?) -> String {
    guard let value = value?.trimmedNonEmpty else { return "Agent" }
    let normalized = value.lowercased()
    if normalized == "codex" || normalized.contains("gpt") {
        return "GPT"
    }
    if normalized.contains("claude") {
        return "Claude"
    }
    return value
}

private func nativeReportTime(_ value: String?) -> String {
    guard let value = value?.trimmedNonEmpty else { return "as of now" }

    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let regular = ISO8601DateFormatter()
    regular.formatOptions = [.withInternetDateTime]
    guard let date = fractional.date(from: value) ?? regular.date(from: value) else {
        return value
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.timeZone = .current
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: date)
}

private struct NativeReportDocumentIcon: View {
    let connectorID: String

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                .fill(Color(red: 0.949, green: 0.945, blue: 0.929))
                .overlay(
                    RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                        .stroke(Color.black.opacity(0.10), lineWidth: 0.5)
                )

            NativeActivityIcon(text: connectorID)
                .scaleEffect(19.0 / 29.0)
                .frame(width: 19, height: 19)
                .offset(x: 6, y: 7)

            Path { path in
                path.move(to: CGPoint(x: 0, y: 8))
                path.addLine(to: CGPoint(x: 8, y: 8))
                path.addLine(to: CGPoint(x: 8, y: 0))
                path.closeSubpath()
            }
            .fill(Color(red: 0.863, green: 0.851, blue: 0.824))
            .frame(width: 8, height: 8)
            .offset(x: 24, y: 0)
        }
        .frame(width: 31, height: 36)
        .accessibilityHidden(true)
    }
}

private struct NativeConnectorPagesSection: View {
    @ObservedObject var state: PersonalModelAppState
    let reports: [ReportSnapshot]
    @Binding var expandedReportID: String?

    private var liveDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日EEEE"
        return formatter.string(from: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Text("Personal Model").foregroundStyle(Color(red: 0.65, green: 0.64, blue: 0.61))
                Text("/").foregroundStyle(Color(red: 0.75, green: 0.73, blue: 0.70))
                Text("Pages created")
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(red: 0.20, green: 0.78, blue: 0.35))
                        .frame(width: 6, height: 6)
                        .shadow(color: Color.green.opacity(0.12), radius: 3)
                    Text("实时更新").font(.system(size: 9.5))
                }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Color(red: 0.56, green: 0.54, blue: 0.51))
            .frame(height: 13)

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("它们写下的页面")
                        .font(.custom("Iowan Old Style", size: 25))
                        .tracking(-0.625)
                        .foregroundStyle(Color(red: 0.114, green: 0.114, blue: 0.122))
                    Text("外面只留下结果。打开一页，才看见它怎样读你、理解你。")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(red: 0.60, green: 0.58, blue: 0.55))
                        .lineSpacing(6)
                        .frame(minHeight: 18, alignment: .top)
                        .padding(.top, 5)
                }
                Spacer()
                Button("刷新") { Task { await state.load() } }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(red: 0.47, green: 0.45, blue: 0.42))
                    .padding(.bottom, 2)
            }
            .padding(.top, 14)
            .padding(.bottom, 17)
            .frame(height: 89.59375)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(red: 0.91, green: 0.90, blue: 0.88))
                    .frame(height: 1)
            }

            Text(liveDate)
                .font(.system(size: 8, design: .monospaced))
                .tracking(1.04)
                .foregroundStyle(Color(red: 0.67, green: 0.65, blue: 0.62))
                .frame(maxWidth: .infinity, minHeight: 29, alignment: .bottomLeading)

            if reports.isEmpty {
                Text("Agent 第一次戴上你的卡并完成工作后，会在这里留下一页。")
                    .font(.custom("Iowan Old Style", size: 14))
                    .foregroundStyle(Color(red: 0.56, green: 0.54, blue: 0.51))
                    .lineSpacing(7)
                    .frame(minHeight: 23.8, alignment: .topLeading)
                    .padding(.top, 26)
                    .padding(.bottom, 30)
            } else {
                ForEach(reports) { report in
                    VStack(alignment: .leading, spacing: 0) {
                        Button {
                            withAnimation(.easeOut(duration: 0.20)) {
                                expandedReportID = expandedReportID == report.id ? nil : report.id
                            }
                        } label: {
                            HStack(spacing: 11) {
                                NativeReportDocumentIcon(
                                    connectorID: report.connectorId ?? "Agent"
                                )
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(report.title)
                                        .font(.system(size: 13.5, weight: .semibold))
                                        .foregroundStyle(Color(red: 0.16, green: 0.16, blue: 0.17))
                                        .frame(minHeight: 20.25, alignment: .topLeading)
                                    Text(report.summary?.trimmedNonEmpty ?? "这页没有提供可展示的摘要。")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(Color(red: 0.53, green: 0.51, blue: 0.49))
                                        .lineSpacing(5.8)
                                        .lineLimit(2)
                                        .frame(minHeight: 16.275, alignment: .topLeading)
                                        .padding(.top, 3)
                                    Text(reportMeta(report))
                                        .font(.system(size: 7, design: .monospaced))
                                        .foregroundStyle(Color(red: 0.69, green: 0.67, blue: 0.65))
                                        .frame(minHeight: 8.4, alignment: .topLeading)
                                        .padding(.top, 5)
                                }
                                Spacer()
                                HStack(spacing: 9) {
                                    Text(nativeConnectorDisplayName(report.connectorId))
                                        .font(.system(size: 10))
                                    Text(expandedReportID == report.id ? "⌃" : "⌄")
                                        .font(.system(size: 11))
                                        .frame(width: 24, height: 24)
                                        .background(
                                            Color(red: 0.94, green: 0.935, blue: 0.92),
                                            in: Circle()
                                        )
                                }
                                .foregroundStyle(Color(red: 0.60, green: 0.58, blue: 0.55))
                            }
                            .frame(height: 54.5234375)
                            .padding(.vertical, 17)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if expandedReportID == report.id {
                            NativeConnectorExpandedReport(state: state, report: report)
                                .padding(.leading, 45)
                                .padding(.bottom, 20)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .id("connector-report-\(report.id)")
                    .padding(.bottom, 1)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color(red: 0.925, green: 0.918, blue: 0.90))
                            .frame(height: 1)
                    }
                }
            }

            HStack {
                Text("点击页面查看细节")
                Spacer()
                Text("RESULTS OUTSIDE · EVIDENCE INSIDE")
            }
            .font(.system(size: 7, design: .monospaced))
            .tracking(0.56)
            .foregroundStyle(Color(red: 0.70, green: 0.68, blue: 0.65))
            .padding(.top, 12)
            .padding(.bottom, 6)
            .frame(height: 28)
        }
        .padding(.top, 22)
        .padding(.horizontal, 23)
        .padding(.bottom, 9)
        .background(Color.white.opacity(0.64), in: RoundedRectangle(cornerRadius: 15))
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(Color(red: 0.89, green: 0.88, blue: 0.86), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.10), radius: 2, y: 2)
    }

    private func reportMeta(_ report: ReportSnapshot) -> String {
        let reads = report.readCount ?? 0
        let evidence = report.evidenceCount ?? report.evidenceRefs?.count ?? 0
        return "\(reads) 次读取 · \(evidence) 条依据 · \(nativeReportTime(report.updatedAt)) 更新"
    }
}

private struct NativeConnectorExpandedReport: View {
    @ObservedObject var state: PersonalModelAppState
    let report: ReportSnapshot

    private struct Point: Identifiable {
        let id: String
        let text: String
        let meta: String
    }

    private var lead: String {
        report.sections?.first(where: { $0.kind?.lowercased() == "lead" })?
            .body.trimmedNonEmpty
            ?? report.summary?.trimmedNonEmpty
            ?? "这页没有提供可展示的正文。"
    }

    private var understanding: String? {
        report.sections?.first(where: { $0.kind?.lowercased() == "understanding" })?
            .body.trimmedNonEmpty
    }

    private var points: [Point] {
        var output = (report.evidenceRefs ?? []).map { reference in
            Point(
                id: "evidence:\(reference)",
                text: reference,
                meta: "Evidence · \(report.modelId ?? "Personal Model")"
            )
        }
        for section in report.sections ?? [] {
            let kind = section.kind?.lowercased() ?? ""
            guard kind == "evidence" || kind == "note" else { continue }
            output.append(
                Point(
                    id: "section:\(section.id)",
                    text: section.body,
                    meta: section.title
                )
            )
        }
        return output
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(nativeConnectorDisplayName(report.connectorId))
                Text("/")
                Text(report.title).lineLimit(1)
                Spacer()
                Text("LIVE PAGE")
            }
            .font(.system(size: 9.5))
            .foregroundStyle(Color(red: 0.63, green: 0.61, blue: 0.58))
            .frame(height: 14)
            .padding(.bottom, 13)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(red: 0.93, green: 0.925, blue: 0.905))
                    .frame(height: 1)
            }

            Text(report.title)
                .font(.custom("Iowan Old Style", size: 21))
                .tracking(-0.42)
                .foregroundStyle(Color(red: 0.18, green: 0.18, blue: 0.19))
                .frame(height: 29.5, alignment: .topLeading)
                .padding(.top, 23)
            Text(lead)
                .font(.system(size: 12.5))
                .foregroundStyle(Color(red: 0.35, green: 0.33, blue: 0.31))
                .lineSpacing(8)
                .frame(height: 23.125, alignment: .top)
                .padding(.top, 10)

            if let understanding {
                VStack(alignment: .leading, spacing: 6) {
                    Text("CURRENT UNDERSTANDING")
                        .font(.system(size: 6.5, design: .monospaced))
                        .tracking(0.91)
                        .foregroundStyle(Color(red: 0.60, green: 0.59, blue: 0.56))
                    Text(understanding)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(red: 0.33, green: 0.32, blue: 0.31))
                        .lineSpacing(7)
                        .frame(minHeight: 21.36, alignment: .top)
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .frame(height: 64.921875, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(red: 0.95, green: 0.945, blue: 0.925),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .padding(.top, 20)
            }

            if !points.isEmpty {
                Text("这页用到的依据")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(height: 16.5, alignment: .topLeading)
                    .padding(.top, 24)
                ForEach(points) { point in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(red: 0.65, green: 0.64, blue: 0.61))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(point.text)
                                .font(.system(size: 11.5))
                                .foregroundStyle(Color(red: 0.35, green: 0.34, blue: 0.31))
                                .lineSpacing(7)
                                .frame(minHeight: 19.55, alignment: .top)
                            Text(point.meta)
                                .font(.system(size: 6.8, design: .monospaced))
                                .foregroundStyle(Color(red: 0.69, green: 0.67, blue: 0.65))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .frame(height: 51.546875, alignment: .leading)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color(red: 0.94, green: 0.93, blue: 0.91))
                            .frame(height: 1)
                    }
                }
            }

            Text("证据索引")
                .font(.system(size: 12, weight: .semibold))
                .frame(height: 16.5, alignment: .topLeading)
                .padding(.top, 24)
            Text("正文保持安静；需要时，再回到它真正读过的位置。")
                .font(.system(size: 9.5))
                .foregroundStyle(Color(red: 0.63, green: 0.61, blue: 0.58))
                .frame(minHeight: 15.2, alignment: .top)
                .padding(.top, 4)
            ForEach(report.evidenceRefs ?? [], id: \.self) { reference in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("证据").font(.system(size: 11, weight: .medium))
                        Text("1 条依据 · \(report.timeRange?.trimmedNonEmpty ?? "")")
                            .font(.system(size: 6.8, design: .monospaced))
                            .foregroundStyle(Color(red: 0.69, green: 0.67, blue: 0.65))
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("回到当天") {
                        state.openRewind(dayID: report.updatedAt.map { String($0.prefix(10)) })
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 8.5))
                    .foregroundStyle(Color(red: 0.50, green: 0.48, blue: 0.45))
                    .accessibilityLabel("回到当天 · \(reference)")
                    Button("✦ 证据") { state.openEvidenceSky(reference) }
                        .buttonStyle(.plain)
                        .font(.system(size: 8.5))
                        .foregroundStyle(Color(red: 0.50, green: 0.48, blue: 0.45))
                        .accessibilityLabel("打开 Evidence · \(reference)")
                }
                .frame(minHeight: 27)
                .padding(.vertical, 10)
                .frame(height: 48.5)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color(red: 0.94, green: 0.93, blue: 0.91))
                        .frame(height: 1)
                }
            }

            HStack {
                Text("由真实读取自动整理")
                Spacer()
                Text("LOCAL · TRACEABLE")
            }
            .font(.system(size: 6.5, design: .monospaced))
            .tracking(0.52)
            .foregroundStyle(Color(red: 0.71, green: 0.69, blue: 0.67))
            .padding(.top, 10)
            .padding(.bottom, 5)
            .frame(height: 24)
        }
        .padding(.horizontal, 23)
        .padding(.top, 21)
        .padding(.bottom, 11)
        .background(
            Color(red: 0.996, green: 0.996, blue: 0.992),
            in: RoundedRectangle(cornerRadius: 11)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color(red: 0.90, green: 0.89, blue: 0.86), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 2, y: 2)
    }
}

private struct NativeReportsView: View {
    @ObservedObject var state: PersonalModelAppState
    let snapshot: PersonalModelSnapshot
    @State private var expandedReport: String?

    init(state: PersonalModelAppState, snapshot: PersonalModelSnapshot) {
        self._state = ObservedObject(wrappedValue: state)
        self.snapshot = snapshot
        self._expandedReport = State(
            initialValue: whoAmIVisualQAActive
                    && whoAmIVisualQAPresentation == "report-expanded"
                ? state.substantiveReports.first?.id
                : nil
        )
    }

    private var reports: [ReportSnapshot] {
        state.substantiveReports
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    NativeConnectorPagesSection(
                        state: state,
                        reports: reports,
                        expandedReportID: $expandedReport
                    )
                    .frame(
                        width: min(660, max(320, geometry.size.width - 64)),
                        alignment: .topLeading
                    )
                    .padding(.top, 42)
                    .padding(.bottom, 64)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                .task {
                    guard whoAmIVisualQAActive,
                          whoAmIVisualQAPresentation == "report-expanded"
                    else { return }
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    if let expandedReport {
                        scrollProxy.scrollTo(
                            "connector-report-\(expandedReport)",
                            anchor: .top
                        )
                    }
                }
            }
        }
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
        GeometryReader { proxy in
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                nativeHexColor("#F1EFE9").opacity(0.96)
                    .ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("YOUR PERSONAL MODEL · THIS MAC")
                            .font(.system(size: 8.5, design: .monospaced))
                            .tracking(2.125)
                            .foregroundStyle(nativeHexColor("#9A968F"))
                        Text("先让这张卡成为你的。")
                            .font(.system(size: 38, weight: .regular, design: .serif))
                            .foregroundStyle(nativeHexColor("#1D1D1F"))
                            .padding(.top, 12)
                        Text("姓名和卡片资料保存在产品目录；记忆、Rewind 与 Evidence 只从这台 Mac 上属于你的 Personal Model 读取。")
                            .font(.system(size: 13.5))
                            .lineSpacing(8)
                            .foregroundStyle(nativeHexColor("#77736C"))
                            .padding(.top, 12)

                        HStack(spacing: 9) {
                            Circle()
                                .fill(nativeHexColor("#D19A36"))
                                .frame(width: 7, height: 7)
                            Text(setupStateLabel)
                                .font(.system(size: 12.5))
                                .foregroundStyle(nativeHexColor("#5F5C56"))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(nativeHexColor("#F4F2EE"), in: RoundedRectangle(cornerRadius: 10))
                        .padding(.top, 24)

                        if !state.isLoading && !state.setupHasProfile {
                            VStack(spacing: 11) {
                                setupField("你的名字", text: $displayName)
                                    .focused($displayNameFocused)
                                    .accessibilityLabel("你的名字")
                                HStack(spacing: 11) {
                                    setupField("@handle", text: $handle)
                                        .accessibilityLabel("Card handle")
                                    setupField("一句话：你正在做什么", text: $tagline)
                                        .accessibilityLabel("Card tagline")
                                }
                                setupField("简单介绍你自己（可选）", text: $description)
                                    .accessibilityLabel("身份介绍")
                            }
                            .padding(.top, 20)
                            .onAppear { displayNameFocused = true }

                            Button {
                                Task {
                                    await state.saveProfile(
                                        displayName: displayName,
                                        handle: handle,
                                        tagline: tagline,
                                        description: description
                                    )
                                }
                            } label: {
                                Text("创建我的 Personal Card")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                                    .background(nativeHexColor("#1D1D1F"), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .keyboardShortcut(.defaultAction)
                            .padding(.top, 12)
                        }

                        if state.setupHasProfile {
                            HStack(spacing: 12) {
                                Text("✳")
                                    .font(.system(size: 15))
                                    .foregroundStyle(nativeHexColor("#F5F5F4"))
                                    .frame(width: 38, height: 38)
                                    .background(nativeHexColor("#1D1D20"), in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(state.setupProfileName)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundStyle(nativeHexColor("#1D1D1F"))
                                    Text(state.setupProfileHandle)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(nativeHexColor("#8E8A83"))
                                        .padding(.top, 3)
                                }
                                Spacer()
                                Text("卡片身份已保存")
                                    .font(.system(size: 11))
                                    .foregroundStyle(nativeHexColor("#237A45"))
                            }
                            .padding(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(nativeHexColor("#E7E4DE"), lineWidth: 1)
                            )
                            .padding(.top, 20)
                        }

                        if !state.isLoading && state.setupState != "ready" {
                            Button {
                                Task { await state.launchPersonalModelSetup() }
                            } label: {
                                Text("安装 / 完成本机授权")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                                    .background(nativeHexColor("#2B47E0"), in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 12)
                            Text("Terminal 会安装经过锁定和校验的 Personal Model。Accessibility、Screen Recording 和模型算力需要由你亲自授权。")
                                .font(.system(size: 11))
                                .lineSpacing(5)
                                .foregroundStyle(nativeHexColor("#9A968F"))
                                .padding(.top, 8)
                        }

                        if let error = state.setupErrorMessage?.trimmedNonEmpty {
                            Text(error)
                                .font(.system(size: 12))
                                .lineSpacing(7)
                                .foregroundStyle(nativeHexColor("#C1493F"))
                                .textSelection(.enabled)
                                .padding(.top, 12)
                        }
                        if let message = state.setupStatusMessage?.trimmedNonEmpty {
                            Text(message)
                                .font(.system(size: 12))
                                .lineSpacing(7)
                                .foregroundStyle(nativeHexColor("#237A45"))
                                .padding(.top, 12)
                        }
                        Button("完成后重新检测") {
                            Task { await state.load() }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(nativeHexColor("#6E6A63"))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)
                    }
                    .padding(.vertical, 34)
                    .padding(.horizontal, 36)
                    .frame(width: min(520, proxy.size.width * 0.94), alignment: .leading)
                    .background(nativeHexColor("#FEFEFD"), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color.black.opacity(0.07), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.28), radius: 50, y: 40)
                    .padding(.vertical, 28)
                    .frame(minHeight: proxy.size.height)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        .accessibilityValue(setupAccessibilityState)
        .accessibilityElement(children: .contain)
    }

    private var setupStateLabel: String {
        switch state.setupState {
        case "not_installed": return "Personal Model 尚未安装"
        case "onboarding_required": return "等待完成 macOS 权限与初始化"
        case "backend_unavailable", "runtime_unavailable": return "本机 Personal Model 暂时不可用"
        case "profile_required": return "先创建你的 Personal Card"
        case "model_forming": return "Personal Model 正在形成"
        case "unauthorized": return "Personal Model 尚未授权"
        default: return "正在检测这台 Mac"
        }
    }

    private var setupAccessibilityState: String {
        switch state.setupState {
        case "profile_required": return "第一次使用"
        case "backend_unavailable": return "本机服务未启动"
        default: return setupStateLabel
        }
    }

    private func setupField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(nativeHexColor("#1D1D1F"))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 39)
            .background(.white, in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(nativeHexColor("#DDD9D2"), lineWidth: 1)
            )
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

import AppKit
import Foundation
import SwiftUI

private let releaseAPI = URL(
    string: "https://api.github.com/repos/Intuition-Lab/who-am-i-personal-card/releases?per_page=10"
)!
private let releaseBase = "https://github.com/Intuition-Lab/who-am-i-personal-card/releases"

enum NativeLifecycleError: LocalizedError {
    case unsafePackage(String)
    case commandFailed(String)
    case cancelled
    case invalidRelease
    case noApprovedRelease
    case checksumMismatch
    case unsafeUninstall(String)

    var errorDescription: String? {
        switch self {
        case .unsafePackage(let detail):
            return "安装包校验失败。\(detail)"
        case .commandFailed(let detail):
            return detail
        case .cancelled:
            return "操作已取消；安装器已开始安全回滚。"
        case .invalidRelease:
            return "GitHub 返回的版本没有通过 immutable Release 与五资产校验。"
        case .noApprovedRelease:
            return "暂时没有通过发布门禁的 GitHub Release。"
        case .checksumMismatch:
            return "下载文件的 SHA-256 与 Release 校验文件不一致，文件不会被打开。"
        case .unsafeUninstall(let detail):
            return "为保护 Personal Model，卸载已停止。\(detail)"
        }
    }
}

private struct ProcessResult {
    let status: Int32
    let output: String
}

private final class LockedOutput: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ newData: Data) {
        lock.lock()
        data.append(newData)
        if data.count > 128 * 1024 {
            data.removeFirst(data.count - 128 * 1024)
        }
        lock.unlock()
    }

    func string() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private struct ReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: String
    let size: Int
    let state: String

    enum CodingKeys: String, CodingKey {
        case name, size, state
        case browserDownloadURL = "browser_download_url"
    }
}

private struct GitHubRelease: Decodable, Identifiable {
    let tagName: String
    let htmlURL: String
    let draft: Bool
    let immutable: Bool
    let assets: [ReleaseAsset]

    var id: String { tagName }
    var version: String { String(tagName.dropFirst()) }

    enum CodingKeys: String, CodingKey {
        case draft, immutable, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
    }
}

private struct ProductVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: String?

    init?(_ raw: String) {
        let value = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
        let pieces = value.split(separator: "-", maxSplits: 1).map(String.init)
        let numbers = pieces[0].split(separator: ".").compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
        prerelease = pieces.count == 2 ? pieces[1] : nil
    }

    static func < (lhs: ProductVersion, rhs: ProductVersion) -> Bool {
        let left = [lhs.major, lhs.minor, lhs.patch]
        let right = [rhs.major, rhs.minor, rhs.patch]
        if left != right { return left.lexicographicallyPrecedes(right) }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (.some, nil): return true
        case (nil, .some): return false
        case let (.some(a), .some(b)):
            return a.localizedStandardCompare(b) == .orderedAscending
        }
    }
}

@MainActor
final class NativeLifecycleController: ObservableObject {
    enum Stage: Equatable {
        case idle
        case verifying
        case preparing
        case installingRuntime
        case installingApp
        case validating
        case complete
        case failed
        case cancelled
        case checkingUpdate
        case downloadingUpdate
        case updateReady
        case diagnosing
        case uninstalling
    }

    @Published var stage: Stage = .idle
    @Published var title = "准备安装 Who Am I"
    @Published var detail = "将校验安装包，然后在本机初始化或连接你的 Personal Model。"
    @Published var progress: Double = 0
    @Published var errorMessage: String?
    @Published var diagnosticSummary = "尚未检查"
    @Published var updateSummary = "尚未检查"
    @Published var approvedRelease: String?
    @Published var verifiedUpdateURL: URL?
    @Published var requiresInteractiveStep = false
    @Published var isBusy = false

    private var runningProcess: Process?
    private var cancelRequested = false
    private var bootstrapProductRoot: URL?
    private var expectedVersion = ""
    private var bootstrapCompletion: ((URL) -> Void)?
    private var release: GitHubRelease?

    var stageLabel: String {
        switch stage {
        case .idle: return "准备"
        case .verifying: return "校验安装包"
        case .preparing: return "准备本机环境"
        case .installingRuntime: return "安装 Personal Model"
        case .installingApp: return "安装 Who Am I"
        case .validating: return "验证安装结果"
        case .complete: return "完成"
        case .failed: return "需要处理"
        case .cancelled: return "已取消"
        case .checkingUpdate: return "检查更新"
        case .downloadingUpdate: return "下载并校验"
        case .updateReady: return "更新已就绪"
        case .diagnosing: return "检查安装状态"
        case .uninstalling: return "正在卸载"
        }
    }

    func configureBootstrap(
        productRoot: URL,
        expectedVersion: String,
        completion: @escaping (URL) -> Void
    ) {
        bootstrapProductRoot = productRoot
        self.expectedVersion = expectedVersion
        bootstrapCompletion = completion
    }

    func startBootstrap() {
        guard !isBusy else { return }
        Task { await installBootstrap() }
    }

    func cancel() {
        guard isBusy else { return }
        cancelRequested = true
        runningProcess?.terminate()
        detail = "正在停止并回滚未完成的更改…"
    }

    private func installBootstrap() async {
        guard let productRoot = bootstrapProductRoot else {
            fail(NativeLifecycleError.unsafePackage("找不到 App 内的产品目录。"))
            return
        }
        isBusy = true
        cancelRequested = false
        errorMessage = nil
        requiresInteractiveStep = false
        stage = .verifying
        title = "正在验证安装包"
        detail = "确认 App、后端和固定版本 Runtime 未被改动。"
        progress = 0.08

        do {
            try await verifyBundledProduct(productRoot)
            try Task.checkCancellation()
            stage = .preparing
            title = "正在准备这台 Mac"
            detail = "检查系统环境并准备本机依赖，通常需要 2–7 分钟。"
            progress = 0.18

            let installer = productRoot.appendingPathComponent("install.sh")
            try requireRegularFile(installer, executable: false)
            let result = try await runProcess(
                executable: URL(fileURLWithPath: "/bin/bash"),
                arguments: [installer.path, "--non-interactive"],
                currentDirectory: productRoot,
                environment: ["WHOAMI_NATIVE_INSTALL": "1"],
                observe: { [weak self] line in self?.observeInstall(line) }
            )
            if cancelRequested { throw NativeLifecycleError.cancelled }
            guard result.status == 0 else {
                if result.output.contains(
                    "Updating an existing Runtime requires an interactive logged-in terminal"
                ) {
                    requiresInteractiveStep = true
                    throw NativeLifecycleError.commandFailed(
                        "该版本需要重新确认 Personal Model 权限与健康状态。只有这一步会打开终端。"
                    )
                }
                throw NativeLifecycleError.commandFailed(
                    safeFailure(from: result.output, fallback: "安装器未能完成，原有版本已保留。")
                )
            }

            stage = .validating
            title = "正在验证安装结果"
            detail = "确认 App 和本机后端完整可用。"
            progress = 0.92
            let installedApp = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Who Am I.app")
            let versionFile = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".persome/product-app/\(expectedVersion)/product-version")
            try requireDirectory(installedApp)
            let installedVersion = try String(contentsOf: versionFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard installedVersion == expectedVersion else {
                throw NativeLifecycleError.commandFailed("安装版本验证失败，原有版本已恢复。")
            }

            stage = .complete
            title = "Who Am I 已安装"
            detail = "接下来会打开你的 App。若 Personal Model 尚未授权，App 会单独引导该步骤。"
            progress = 1
            isBusy = false
            bootstrapCompletion?(installedApp)
        } catch {
            if cancelRequested {
                stage = .cancelled
                title = "安装已取消"
                detail = "未完成的更改已回滚；可以随时重新开始。"
                errorMessage = nil
            } else {
                fail(error)
            }
            isBusy = false
        }
    }

    func openRequiredInteractiveStep() {
        guard requiresInteractiveStep, let productRoot = bootstrapProductRoot else { return }
        let command = productRoot.appendingPathComponent("Install Who Am I.command")
        do {
            try requireRegularFile(command, executable: true)
            guard NSWorkspace.shared.open(command) else {
                throw NativeLifecycleError.commandFailed("无法打开 Runtime 权限确认。")
            }
        } catch {
            fail(error)
        }
    }

    private func verifyBundledProduct(_ productRoot: URL) async throws {
        try requireDirectory(productRoot)
        let manifest = productRoot.appendingPathComponent("SELF-CONTAINED-SHA256SUMS")
        try requireRegularFile(manifest, executable: false)
        let result = try await runProcess(
            executable: URL(fileURLWithPath: "/usr/bin/shasum"),
            arguments: ["-a", "256", "--check", manifest.lastPathComponent],
            currentDirectory: productRoot
        )
        guard result.status == 0 else {
            throw NativeLifecycleError.unsafePackage("完整性清单不匹配，请重新下载 DMG。")
        }
    }

    private func observeInstall(_ line: String) {
        if line.localizedCaseInsensitiveContains("installing reviewed runtime") {
            stage = .installingRuntime
            title = "正在安装 Personal Model"
            detail = "使用安装包内固定、已审核的 Runtime；不会访问第二个源码仓库。"
            progress = 0.42
        } else if line.contains("Installing Personal Card dependencies")
                    || line.contains("Refreshing installed Personal Card") {
            stage = .installingApp
            title = "正在安装 Who Am I"
            detail = "正在准备原生 App 和本机后端。"
            progress = 0.70
        } else if line.contains("Existing Personal Model detected") {
            stage = .installingApp
            title = "已连接现有 Personal Model"
            detail = "现有模型数据、权限和配置保持不变。"
            progress = 0.72
        } else if line.contains("Who Am I is installed in") {
            stage = .validating
            title = "正在完成安装"
            detail = "运行最终完整性检查。"
            progress = 0.88
        }
    }

    func runDiagnosis(persomeRoot: URL) {
        guard !isBusy else { return }
        Task {
            isBusy = true
            stage = .diagnosing
            errorMessage = nil
            diagnosticSummary = "正在检查…"
            defer { isBusy = false }
            do {
                let script = persomeRoot.appendingPathComponent(
                    "product-management/scripts/diagnose.sh"
                )
                try requireRegularFile(script, executable: true)
                let result = try await runProcess(
                    executable: URL(fileURLWithPath: "/bin/bash"),
                    arguments: [script.path, "--json"]
                )
                guard result.status == 0 || result.status == 3 else {
                    throw NativeLifecycleError.commandFailed("安装诊断无法完成。")
                }
                let data = Data(result.output.utf8)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                let overall = json?["overall_status"] as? String ?? "unknown"
                let runtime = json?["runtime_installation"] as? String ?? "unknown"
                let receipt = json?["receipt_status"] as? String ?? "unknown"
                diagnosticSummary = overall == "healthy"
                    ? "安装正常 · Runtime \(runtime) · 收据 \(receipt)"
                    : "需要处理 · Runtime \(runtime) · 收据 \(receipt)"
                stage = .idle
            } catch {
                diagnosticSummary = "检查失败"
                fail(error)
            }
        }
    }

    func checkForUpdates(currentVersion: String) {
        guard !isBusy else { return }
        Task {
            isBusy = true
            stage = .checkingUpdate
            errorMessage = nil
            updateSummary = "正在读取 immutable GitHub Releases…"
            verifiedUpdateURL = nil
            defer { isBusy = false }
            do {
                var request = URLRequest(url: releaseAPI)
                request.timeoutInterval = 20
                request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("Who-Am-I-macOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    throw NativeLifecycleError.commandFailed("暂时无法读取 GitHub Release。")
                }
                let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
                guard let approved = releases.first(where: isApprovedRelease) else {
                    throw NativeLifecycleError.noApprovedRelease
                }
                guard let current = ProductVersion(currentVersion),
                      let latest = ProductVersion(approved.version) else {
                    throw NativeLifecycleError.invalidRelease
                }
                if current < latest {
                    release = approved
                    approvedRelease = approved.tagName
                    updateSummary = "发现 \(approved.tagName) · 已通过 immutable 五资产门禁"
                } else if current == latest {
                    release = approved
                    approvedRelease = approved.tagName
                    updateSummary = "当前已是最新审核版本 \(approved.tagName)"
                } else {
                    release = nil
                    approvedRelease = nil
                    updateSummary = "审核版本 \(approved.tagName) 不高于当前版本，不会降级"
                }
                stage = .idle
            } catch {
                release = nil
                approvedRelease = nil
                updateSummary = "没有可用的审核版本"
                fail(error)
            }
        }
    }

    func downloadApprovedInstaller() {
        guard !isBusy, let release else { return }
        Task {
            isBusy = true
            stage = .downloadingUpdate
            errorMessage = nil
            updateSummary = "正在下载并校验 \(release.tagName)…"
            defer { isBusy = false }
            do {
                let packageName = "who-am-i-\(release.version)-self-contained-macos"
                guard let dmgAsset = release.assets.first(where: { $0.name == "\(packageName).dmg" }),
                      let sumAsset = release.assets.first(where: { $0.name == "SHA256SUMS" }),
                      let dmgURL = URL(string: dmgAsset.browserDownloadURL),
                      let sumURL = URL(string: sumAsset.browserDownloadURL) else {
                    throw NativeLifecycleError.invalidRelease
                }
                let cacheRoot = try updateCacheDirectory(tag: release.tagName)
                let checksumURL = cacheRoot.appendingPathComponent("SHA256SUMS")
                let dmgDestination = cacheRoot.appendingPathComponent(dmgAsset.name)
                try await download(sumURL, to: checksumURL)
                try await download(dmgURL, to: dmgDestination)
                let checksumValues = try checksumURL.resourceValues(forKeys: [.fileSizeKey])
                let values = try dmgDestination.resourceValues(forKeys: [.fileSizeKey])
                guard checksumValues.fileSize == sumAsset.size,
                      values.fileSize == dmgAsset.size else {
                    throw NativeLifecycleError.checksumMismatch
                }
                try verifyChecksum(
                    checksumFile: checksumURL,
                    asset: dmgDestination,
                    expectedName: dmgAsset.name
                )
                let verify = try await runProcess(
                    executable: URL(fileURLWithPath: "/usr/bin/hdiutil"),
                    arguments: ["verify", dmgDestination.path]
                )
                guard verify.status == 0 else { throw NativeLifecycleError.checksumMismatch }
                verifiedUpdateURL = dmgDestination
                updateSummary = "\(release.tagName) 已下载并通过 SHA-256 与 DMG 校验"
                stage = .updateReady
            } catch {
                verifiedUpdateURL = nil
                fail(error)
            }
        }
    }

    func openVerifiedInstaller() {
        guard let verifiedUpdateURL else { return }
        NSWorkspace.shared.open(verifiedUpdateURL)
    }

    func uninstallProduct(persomeRoot: URL, includeManagedRuntime: Bool) {
        guard !isBusy else { return }
        Task {
            isBusy = true
            stage = .uninstalling
            errorMessage = nil
            defer { isBusy = false }
            do {
                let action = includeManagedRuntime ? "remove-runtime-preserve" : "remove-product"
                let result = try await runLifecycleHelper(action: action, persomeRoot: persomeRoot)
                guard result.status == 0 else {
                    throw NativeLifecycleError.unsafeUninstall(
                        safeFailure(from: result.output, fallback: "卸载身份验证失败。")
                    )
                }
                NSApp.terminate(nil)
            } catch {
                fail(error)
            }
        }
    }

    func preparePermanentDelete(persomeRoot: URL) {
        guard !isBusy else { return }
        Task {
            isBusy = true
            stage = .uninstalling
            errorMessage = nil
            defer { isBusy = false }
            do {
                let result = try await runLifecycleHelper(
                    action: "prepare-permanent-delete",
                    persomeRoot: persomeRoot
                )
                guard result.status == 0 else {
                    throw NativeLifecycleError.unsafeUninstall(
                        safeFailure(from: result.output, fallback: "无法验证产品管理权。")
                    )
                }
                let path = result.output.split(separator: "\n").last.map(String.init) ?? ""
                let commandURL = URL(fileURLWithPath: path)
                try requireRegularFile(commandURL, executable: true)
                guard NSWorkspace.shared.open(commandURL) else {
                    throw NativeLifecycleError.commandFailed("无法打开系统删除确认。")
                }
                NSApp.terminate(nil)
            } catch {
                fail(error)
            }
        }
    }

    private func runLifecycleHelper(action: String, persomeRoot: URL) async throws -> ProcessResult {
        guard let resources = Bundle.main.resourceURL else {
            throw NativeLifecycleError.unsafeUninstall("App 缺少生命周期工具。")
        }
        let helper = resources.appendingPathComponent("native-lifecycle-helper.sh")
        try requireRegularFile(helper, executable: false)
        let appPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/Who Am I.app").path
        return try await runProcess(
            executable: URL(fileURLWithPath: "/bin/bash"),
            arguments: [helper.path, action, persomeRoot.path, appPath]
        )
    }

    private func isApprovedRelease(_ candidate: GitHubRelease) -> Bool {
        guard !candidate.draft, candidate.immutable,
              candidate.tagName.range(
                of: #"^v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$"#,
                options: .regularExpression
              ) != nil else { return false }
        let packageName = "who-am-i-\(candidate.version)-self-contained-macos"
        let expected = Set([
            "\(packageName).dmg",
            "\(packageName).tar.gz",
            "RELEASE-METADATA.txt",
            "RELEASE-NOTES.md",
            "SHA256SUMS",
        ])
        let names = candidate.assets.map(\.name)
        guard candidate.assets.count == 5, Set(names) == expected, Set(names).count == 5 else {
            return false
        }
        let prefix = "\(releaseBase)/download/\(candidate.tagName)/"
        return candidate.assets.allSatisfy {
            $0.state == "uploaded" && $0.size > 0
                && $0.browserDownloadURL == "\(prefix)\($0.name)"
        }
    }

    private func updateCacheDirectory(tag: String) throws -> URL {
        guard tag.range(of: #"^v\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$"#,
                        options: .regularExpression) != nil else {
            throw NativeLifecycleError.invalidRelease
        }
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Who Am I/Updates", isDirectory: true)
        let destination = base.appendingPathComponent(tag, isDirectory: true)
        try FileManager.default.createDirectory(
            at: destination,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let values = try destination.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw NativeLifecycleError.unsafePackage("更新缓存目录不安全。")
        }
        return destination
    }

    private func download(_ source: URL, to destination: URL) async throws {
        guard source.scheme == "https", source.host == "github.com",
              source.absoluteString.hasPrefix("\(releaseBase)/download/") else {
            throw NativeLifecycleError.invalidRelease
        }
        var request = URLRequest(url: source)
        request.timeoutInterval = 180
        request.setValue("Who-Am-I-macOS", forHTTPHeaderField: "User-Agent")
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NativeLifecycleError.commandFailed("更新文件下载失败。")
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destination.path
        )
    }

    private func verifyChecksum(
        checksumFile: URL,
        asset: URL,
        expectedName: String
    ) throws {
        let contents = try String(contentsOf: checksumFile, encoding: .utf8)
        let lines = contents.split(separator: "\n").map(String.init)
        guard expectedName.hasSuffix(".dmg") else {
            throw NativeLifecycleError.checksumMismatch
        }
        let packageName = String(expectedName.dropLast(4))
        let expectedEntries = Set([
            "\(packageName).dmg",
            "\(packageName).tar.gz",
            "RELEASE-METADATA.txt",
            "RELEASE-NOTES.md",
        ])
        var manifest: [String: String] = [:]
        for line in lines {
            let pieces = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard pieces.count == 2 else { throw NativeLifecycleError.checksumMismatch }
            let digest = String(pieces[0])
            let name = String(pieces.last!).trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            guard expectedEntries.contains(name), manifest[name] == nil,
                  digest.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
                throw NativeLifecycleError.checksumMismatch
            }
            manifest[name] = digest
        }
        guard Set(manifest.keys) == expectedEntries,
              let expectedDigest = manifest[expectedName] else {
            throw NativeLifecycleError.checksumMismatch
        }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        task.arguments = ["-a", "256", asset.path]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        try task.run()
        task.waitUntilExit()
        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        guard task.terminationStatus == 0,
              output.split(separator: " ").first.map(String.init) == expectedDigest else {
            throw NativeLifecycleError.checksumMismatch
        }
    }

    private func requireRegularFile(_ url: URL, executable: Bool) throws {
        let values = try url.resourceValues(forKeys: [
            .isRegularFileKey, .isSymbolicLinkKey,
        ])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (!executable || FileManager.default.isExecutableFile(atPath: url.path)) else {
            throw NativeLifecycleError.unsafePackage("缺少 \(url.lastPathComponent)。")
        }
    }

    private func requireDirectory(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else {
            throw NativeLifecycleError.unsafePackage("目录 \(url.lastPathComponent) 不可用。")
        }
    }

    private func runProcess(
        executable: URL,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment additions: [String: String] = [:],
        observe: ((String) -> Void)? = nil
    ) async throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        additions.forEach { environment[$0.key] = $0.value }
        process.environment = environment
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        let buffer = LockedOutput()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            buffer.append(data)
            if let observe, let text = String(data: data, encoding: .utf8) {
                for line in text.split(separator: "\n") {
                    Task { @MainActor in observe(String(line)) }
                }
            }
        }

        runningProcess = process
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { [weak self] finished in
                pipe.fileHandleForReading.readabilityHandler = nil
                let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
                if !remaining.isEmpty { buffer.append(remaining) }
                let result = ProcessResult(
                    status: finished.terminationStatus,
                    output: buffer.string()
                )
                Task { @MainActor in
                    self?.runningProcess = nil
                    continuation.resume(returning: result)
                }
            }
            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                runningProcess = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private func safeFailure(from output: String, fallback: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let lines = output.split(separator: "\n")
            .map(String.init)
            .map { $0.replacingOccurrences(of: home, with: "~") }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let final = lines.suffix(3).last else { return fallback }
        let bounded = String(final.prefix(260))
        return bounded.isEmpty ? fallback : bounded
    }

    private func fail(_ error: Error) {
        stage = .failed
        errorMessage = (error as? LocalizedError)?.errorDescription
            ?? "操作没有完成，请稍后重试。"
    }
}

struct NativeInstallerView: View {
    @ObservedObject var controller: NativeLifecycleController

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: controller.stage == .complete
                  ? "checkmark.circle.fill" : "person.crop.circle.fill")
                .font(.system(size: 48))
                .symbolRenderingMode(.hierarchical)
            Text(controller.title)
                .font(.system(size: 28, weight: .semibold))
            Text(controller.detail)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
            ProgressView(value: controller.progress)
                .frame(maxWidth: 430)
            HStack {
                Text(controller.stageLabel)
                Spacer()
                Text("\(Int(controller.progress * 100))%")
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: 430)
            if let error = controller.errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)
            }
            HStack(spacing: 12) {
                if controller.isBusy {
                    Button("取消") { controller.cancel() }
                } else if controller.requiresInteractiveStep {
                    Button("打开 Runtime 更新确认") {
                        controller.openRequiredInteractiveStep()
                    }
                    .buttonStyle(.borderedProminent)
                } else if controller.stage == .failed || controller.stage == .cancelled {
                    Button("重新安装") { controller.startBootstrap() }
                        .buttonStyle(.borderedProminent)
                }
            }
            Text("Personal Model 和 Personal Card 数据只保存在当前 Mac 用户目录中。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(42)
        .frame(minWidth: 600, minHeight: 440)
    }
}

struct NativeMaintenanceView: View {
    @ObservedObject var controller: NativeLifecycleController
    let productVersion: String
    let persomeRoot: URL
    @State private var confirmRemoval: Int = 0
    @State private var permanentStep = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("安装与维护")
                    .font(.system(size: 30, weight: .bold))
                Text("Who Am I \(productVersion) · 所有操作只针对当前 macOS 用户。")
                    .foregroundStyle(.secondary)

                maintenanceCard("安装状态", systemImage: "stethoscope") {
                    Text(controller.diagnosticSummary)
                        .foregroundStyle(.secondary)
                    Button("检查安装状态") {
                        controller.runDiagnosis(persomeRoot: persomeRoot)
                    }
                    .disabled(controller.isBusy)
                }

                maintenanceCard("更新或重新安装", systemImage: "arrow.triangle.2.circlepath") {
                    Text(controller.updateSummary)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("检查审核版本") {
                            controller.checkForUpdates(currentVersion: productVersion)
                        }
                        .disabled(controller.isBusy)
                        if controller.approvedRelease != nil {
                            Button("下载并校验 DMG") {
                                controller.downloadApprovedInstaller()
                            }
                            .disabled(controller.isBusy)
                        }
                        if controller.verifiedUpdateURL != nil {
                            Button("打开已验证的 DMG") {
                                controller.openVerifiedInstaller()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    Text("只接受 immutable GitHub Release 的精确五资产。不会运行 floating branch 或未校验更新。")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                maintenanceCard("卸载", systemImage: "trash") {
                    Text("删除 App 与产品代码不会删除 Personal Model 数据。独立安装的 Personal Model 永远不会被本 App 接管或删除。")
                        .foregroundStyle(.secondary)
                    if confirmRemoval == 0 {
                        HStack {
                            Button("删除 App，保留 Personal Model") { confirmRemoval = 1 }
                            Button("同时移除托管 Runtime，保留数据") { confirmRemoval = 2 }
                        }
                    } else {
                        Text(confirmRemoval == 1
                             ? "确认删除 Who Am I.app 和产品代码？Card Profile 与 Personal Model 数据会保留。"
                             : "确认移除 App 和产品托管的 Runtime 可执行文件？Personal Model 数据会保留。")
                            .font(.system(size: 12, weight: .semibold))
                        HStack {
                            Button("取消") { confirmRemoval = 0 }
                            Button("确认卸载", role: .destructive) {
                                controller.uninstallProduct(
                                    persomeRoot: persomeRoot,
                                    includeManagedRuntime: confirmRemoval == 2
                                )
                            }
                            .disabled(controller.isBusy)
                        }
                    }

                    Divider()
                    if permanentStep == 0 {
                        Button("永久删除 Personal Model 数据…", role: .destructive) {
                            permanentStep = 1
                        }
                    } else if permanentStep == 1 {
                        Text("此操作不可恢复。只有带产品管理收据的 Runtime 才能继续；已有独立 Personal Model 会被拒绝。")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red)
                        HStack {
                            Button("取消") { permanentStep = 0 }
                            Button("我理解，继续", role: .destructive) { permanentStep = 2 }
                        }
                    } else {
                        Text("最后一步会打开系统终端。你必须亲自输入 DELETE，才会永久删除数据。")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.red)
                        HStack {
                            Button("取消") { permanentStep = 0 }
                            Button("打开最终系统确认", role: .destructive) {
                                controller.preparePermanentDelete(persomeRoot: persomeRoot)
                            }
                            .disabled(controller.isBusy)
                        }
                    }
                }

                if let error = controller.errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(32)
        }
        .frame(minWidth: 680, minHeight: 640)
    }

    @ViewBuilder
    private func maintenanceCard<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 17, weight: .semibold))
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))
    }
}

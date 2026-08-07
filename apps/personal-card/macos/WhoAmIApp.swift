import Cocoa
import Foundation
import WebKit

private let serverURL = URL(string: "http://127.0.0.1:8772/")!
private let statusURL = URL(string: "http://127.0.0.1:8772/api/app/health")!

private struct SetupStatus: Decodable {
    let productVersion: String?
    let devMode: Bool?
}

private enum ServerProbe {
    case expected
    case unavailable
    case unexpected(version: String?, development: Bool?)
}

private enum LauncherError: LocalizedError {
    case missingBundleSetting(String)
    case invalidProductRoot(String)
    case missingProductFile(String)
    case unexpectedServer(String?)
    case launchFailed(String)
    case serverExited(Int32)
    case startupTimedOut

    var errorDescription: String? {
        switch self {
        case .missingBundleSetting(let key):
            return "Who Am I 安装不完整：缺少 \(key)。"
        case .invalidProductRoot(let path):
            return "Who Am I 产品目录不可用：\(path)"
        case .missingProductFile(let path):
            return "Who Am I 安装不完整：找不到 \(path)。"
        case .unexpectedServer(let version):
            if let version, !version.isEmpty {
                return "本机端口 8772 正在运行另一个 Who Am I 版本（\(version)）。"
            }
            return "本机端口 8772 已被其他服务占用。"
        case .launchFailed(let detail):
            return "无法启动 Who Am I 本机服务。\(detail)"
        case .serverExited(let status):
            return "Who Am I 本机服务已退出（状态 \(status)）。"
        case .startupTimedOut:
            return "Who Am I 本机服务启动超时。"
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var serverProcess: Process?
    private var serverOutputPipe: Pipe?
    private var recentServerOutput = Data()
    private let serverOutputLock = NSLock()
    private var isTerminating = false
    private var didReportFailure = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        createMainMenu()
        createWindow()
        NSApp.activate(ignoringOtherApps: true)

        Task { [weak self] in
            await self?.prepareAndLoad()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        serverOutputPipe?.fileHandleForReading.readabilityHandler = nil
        if let process = serverProcess, process.isRunning {
            process.terminate()
        }
    }

    private func createMainMenu() {
        let mainMenu = NSMenu()

        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "Who Am I")
        applicationMenu.addItem(
            withTitle: "About Who Am I",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: "Quit Who Am I",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        let viewItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let reloadItem = NSMenuItem(
            title: "Reload",
            action: #selector(reloadCard(_:)),
            keyEquivalent: "r"
        )
        reloadItem.target = self
        viewMenu.addItem(reloadItem)
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(
            withTitle: "Minimize",
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(
            withTitle: "Zoom",
            action: #selector(NSWindow.performZoom(_:)),
            keyEquivalent: ""
        )
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func reloadCard(_ sender: Any?) {
        webView?.reload()
    }

    private func createWindow() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.isElementFullscreenEnabled = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.setValue(false, forKey: "drawsBackground")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Who Am I"
        window.minSize = NSSize(width: 760, height: 560)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.webView = webView
        self.window = window
    }

    private func bundleString(_ key: String) throws -> String {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw LauncherError.missingBundleSetting(key)
        }
        return value
    }

    private func fileURL(fromBundleKey key: String) throws -> URL {
        let value = try bundleString(key)
        let expanded = (value as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else {
            throw LauncherError.missingBundleSetting(key)
        }
        return URL(fileURLWithPath: expanded, isDirectory: true).standardizedFileURL
    }

    private func prepareAndLoad() async {
        do {
            let productRoot = try fileURL(fromBundleKey: "WhoAmIProductRoot")
            let persomeRoot = try fileURL(fromBundleKey: "WhoAmIPersomeRoot")
            let expectedVersion = try bundleString("WhoAmIProductVersion")

            var isDirectory: ObjCBool = false
            guard
                FileManager.default.fileExists(
                    atPath: productRoot.path,
                    isDirectory: &isDirectory
                ),
                isDirectory.boolValue
            else {
                throw LauncherError.invalidProductRoot(productRoot.path)
            }

            switch await probeServer(expectedVersion: expectedVersion) {
            case .expected:
                loadProduct()
                return
            case .unexpected(let version, _):
                throw LauncherError.unexpectedServer(version)
            case .unavailable:
                break
            }

            try startServer(
                productRoot: productRoot,
                persomeRoot: persomeRoot,
                expectedVersion: expectedVersion
            )
            try await waitForExpectedServer(expectedVersion: expectedVersion)
            loadProduct()
        } catch {
            report(error)
        }
    }

    private func probeServer(expectedVersion: String) async -> ServerProbe {
        var request = URLRequest(url: statusURL)
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 1.0
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard
                let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                return .unavailable
            }
            let status = try JSONDecoder().decode(SetupStatus.self, from: data)
            if status.productVersion == expectedVersion, status.devMode == false {
                return .expected
            }
            return .unexpected(
                version: status.productVersion,
                development: status.devMode
            )
        } catch {
            return .unavailable
        }
    }

    private func startServer(
        productRoot: URL,
        persomeRoot: URL,
        expectedVersion: String
    ) throws {
        let nodeURL = productRoot.appendingPathComponent(
            "runtime/node/bin/node",
            isDirectory: false
        )
        let serverScriptURL = productRoot.appendingPathComponent(
            "persome-card-server.mjs",
            isDirectory: false
        )
        guard FileManager.default.isExecutableFile(atPath: nodeURL.path) else {
            throw LauncherError.missingProductFile("runtime/node/bin/node")
        }
        guard FileManager.default.fileExists(atPath: serverScriptURL.path) else {
            throw LauncherError.missingProductFile("persome-card-server.mjs")
        }

        let process = Process()
        process.executableURL = nodeURL
        process.arguments = [serverScriptURL.path]
        process.currentDirectoryURL = productRoot

        var environment = ProcessInfo.processInfo.environment
        environment["NODE_ENV"] = "production"
        environment["WHOAMI_DEV_MODE"] = "0"
        environment["WHOAMI_CARD_PORT"] = "8772"
        environment["PERSOME_ROOT"] = persomeRoot.path
        environment["PERSOME_INSTALL_HOME"] = persomeRoot.path
        environment["PATH"] = [
            productRoot.appendingPathComponent("runtime/node/bin").path,
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ].joined(separator: ":")
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.appendServerOutput(data)
        }

        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.async {
                guard let self, !self.isTerminating, !self.didReportFailure else {
                    return
                }
                self.report(LauncherError.serverExited(process.terminationStatus))
            }
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            throw LauncherError.launchFailed(error.localizedDescription)
        }
        serverOutputPipe = outputPipe
        serverProcess = process
    }

    private func appendServerOutput(_ data: Data) {
        serverOutputLock.lock()
        defer { serverOutputLock.unlock() }
        recentServerOutput.append(data)
        if recentServerOutput.count > 16_384 {
            recentServerOutput.removeFirst(recentServerOutput.count - 16_384)
        }
    }

    private func waitForExpectedServer(expectedVersion: String) async throws {
        for _ in 0..<120 {
            if let process = serverProcess, !process.isRunning {
                throw LauncherError.serverExited(process.terminationStatus)
            }
            switch await probeServer(expectedVersion: expectedVersion) {
            case .expected:
                return
            case .unexpected(let version, _):
                throw LauncherError.unexpectedServer(version)
            case .unavailable:
                break
            }
            try await Task.sleep(nanoseconds: 125_000_000)
        }
        throw LauncherError.startupTimedOut
    }

    private func loadProduct() {
        DispatchQueue.main.async { [weak self] in
            self?.webView?.load(URLRequest(url: serverURL))
            self?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func report(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.didReportFailure else { return }
            self.didReportFailure = true

            if let process = self.serverProcess, process.isRunning {
                process.terminate()
            }
            self.serverOutputPipe?.fileHandleForReading.readabilityHandler = nil

            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Who Am I 无法打开"
            alert.informativeText = (error as? LocalizedError)?.errorDescription
                ?? "本机服务暂时不可用。"
            alert.addButton(withTitle: "退出")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    private func isLocalProductURL(_ url: URL) -> Bool {
        guard url.scheme == "http" else { return false }
        let host = url.host?.lowercased()
        return host == "127.0.0.1"
            && (url.port ?? 80) == 8772
    }

    private func openExternally(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }
        if url.scheme == "about" || isLocalProductURL(url) {
            decisionHandler(.allow)
            return
        }
        openExternally(url)
        decisionHandler(.cancel)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        guard let url = navigationAction.request.url else { return nil }
        if isLocalProductURL(url) {
            webView.load(URLRequest(url: url))
        } else {
            openExternally(url)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        download.delegate = self
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            guard self != nil else {
                completionHandler(nil)
                return
            }
            let panel = NSSavePanel()
            panel.nameFieldStringValue = suggestedFilename
            panel.canCreateDirectories = true
            let modalResponse = panel.runModal()
            completionHandler(modalResponse == .OK ? panel.url : nil)
        }
    }
}

let application = NSApplication.shared
private let delegate = AppDelegate()
application.delegate = delegate
application.run()

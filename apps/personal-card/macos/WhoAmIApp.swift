import Cocoa
import Foundation
import SwiftUI

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
    case missingInstaller(String)
    case installerLaunchFailed
    case installationTimedOut
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
        case .missingInstaller(let path):
            return "Who Am I 安装包不完整：找不到 \(path)。请重新下载 DMG。"
        case .installerLaunchFailed:
            return "无法启动首次安装。请重新打开 DMG 后再试。"
        case .installationTimedOut:
            return "首次安装尚未完成。请查看终端里的提示，完成后重新打开 Who Am I。"
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

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var maintenanceWindow: NSWindow?
    private var appState: PersonalModelAppState?
    private var lifecycleController: NativeLifecycleController?
    private var statusItem: NSStatusItem?
    private var statusMenuModelItem: NSMenuItem?
    private var statusMenu: NSMenu?
    private var escapeMonitor: Any?
    private var serverProcess: Process?
    private var serverOutputPipe: Pipe?
    private var recentServerOutput = Data()
    private let serverOutputLock = NSLock()
    private var isTerminating = false
    private var didReportFailure = false

    private var isBootstrapInstaller: Bool {
        Bundle.main.object(forInfoDictionaryKey: "WhoAmIBootstrapInstall") as? Bool
            ?? false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(isBootstrapInstaller ? .regular : .accessory)
        createMainMenu()
        createWindow(bootstrap: isBootstrapInstaller)
        if !isBootstrapInstaller {
            createStatusItem()
        }
        NSApp.activate(ignoringOtherApps: true)

        Task { [weak self] in
            await self?.prepareAndLoad()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showMainWindow(nil)
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        lifecycleController?.cancel()
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
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
        if !isBootstrapInstaller {
            let maintenanceItem = NSMenuItem(
                title: "安装与维护…",
                action: #selector(showMaintenance(_:)),
                keyEquivalent: ","
            )
            maintenanceItem.target = self
            applicationMenu.addItem(maintenanceItem)
        }
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
        guard let appState else { return }
        Task { await appState.load() }
    }

    private func createWindow(bootstrap: Bool) {
        let initialSize = bootstrap
            ? NSSize(width: 640, height: 420)
            : NSSize(width: 1180, height: 820)
        let window: NSWindow
        if bootstrap {
            window = NSWindow(
                contentRect: NSRect(origin: .zero, size: initialSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
        } else {
            let spotlightPanel = NSPanel(
                contentRect: NSRect(origin: .zero, size: NSSize(width: 900, height: 840)),
                styleMask: [.borderless, .resizable],
                backing: .buffered,
                defer: false
            )
            spotlightPanel.isFloatingPanel = true
            spotlightPanel.level = .floating
            spotlightPanel.hidesOnDeactivate = true
            spotlightPanel.collectionBehavior = [
                .canJoinAllSpaces,
                .fullScreenAuxiliary,
                .transient,
            ]
            spotlightPanel.isOpaque = false
            spotlightPanel.backgroundColor = .clear
            spotlightPanel.hasShadow = false
            spotlightPanel.isMovableByWindowBackground = true
            spotlightPanel.animationBehavior = .utilityWindow
            spotlightPanel.isExcludedFromWindowsMenu = true
            window = spotlightPanel
        }
        window.title = "Who Am I"
        window.minSize = bootstrap
            ? NSSize(width: 560, height: 360)
            : NSSize(width: 760, height: 560)
        window.isReleasedWhenClosed = false
        window.contentView = bootstrap ? makeBootstrapView() : makeLoadingView()
        if bootstrap {
            window.center()
        } else {
            positionSpotlightPanel(window)
        }
        window.makeKeyAndOrderFront(nil)

        self.window = window

        if !bootstrap {
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
                [weak self] event in
                if event.keyCode == 53 {
                    if self?.appState?.handleEscape() == true {
                        return nil
                    }
                    self?.window?.orderOut(nil)
                    return nil
                }
                return event
            }
        }
    }

    private func createStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return }
        let image = NSImage(
            systemSymbolName: "asterisk",
            accessibilityDescription: "Who Am I"
        )
        image?.isTemplate = true
        button.image = image
        button.toolTip = "Who Am I · Personal Model"
        button.target = self
        button.action = #selector(statusItemPressed(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let menu = NSMenu(title: "Who Am I")
        let openItem = NSMenuItem(
            title: "打开 Who Am I",
            action: #selector(showMainWindow(_:)),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())

        let searchItem = NSMenuItem(
            title: "搜索记忆",
            action: #selector(showSearchFromStatusItem(_:)),
            keyEquivalent: "k"
        )
        searchItem.keyEquivalentModifierMask = [.command]
        searchItem.target = self
        menu.addItem(searchItem)
        let askItem = NSMenuItem(
            title: "问这张卡",
            action: #selector(showAskFromStatusItem(_:)),
            keyEquivalent: ""
        )
        askItem.target = self
        menu.addItem(askItem)
        menu.addItem(.separator())

        let nativeSections: [(WhoAmISection, String)] = [
            (.rewind, "回到某一天"),
            (.connectors, "继续工作"),
            (.identity, "Identity"),
            (.reports, "Reports"),
            (.evidence, "Evidence"),
        ]
        for (section, title) in nativeSections {
            let sectionItem = NSMenuItem(
                title: title,
                action: #selector(showSectionFromStatusItem(_:)),
                keyEquivalent: ""
            )
            sectionItem.target = self
            sectionItem.tag = WhoAmISection.allCases.firstIndex(of: section) ?? 0
            menu.addItem(sectionItem)
        }
        let skyItem = NSMenuItem(
            title: "巡星 · Memory Sky",
            action: #selector(showMemorySkyFromStatusItem(_:)),
            keyEquivalent: ""
        )
        skyItem.target = self
        menu.addItem(skyItem)
        let shareItem = NSMenuItem(
            title: "分享这张卡",
            action: #selector(showShareFromStatusItem(_:)),
            keyEquivalent: ""
        )
        shareItem.target = self
        menu.addItem(shareItem)
        menu.addItem(.separator())
        let modelItem = NSMenuItem(title: "Personal Model · 正在连接", action: nil, keyEquivalent: "")
        modelItem.isEnabled = false
        menu.addItem(modelItem)
        menu.addItem(.separator())
        let maintenanceItem = NSMenuItem(
            title: "安装状态、更新与卸载…",
            action: #selector(showMaintenance(_:)),
            keyEquivalent: ""
        )
        maintenanceItem.target = self
        menu.addItem(maintenanceItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(
            title: "退出 Who Am I",
            action: #selector(quitApplication(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem = item
        statusMenu = menu
        statusMenuModelItem = modelItem
    }

    @objc private func statusItemPressed(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp, let statusItem, let statusMenu {
            statusItem.menu = statusMenu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        toggleSpotlight(nil)
    }

    @objc private func toggleSpotlight(_ sender: Any?) {
        guard let window else { return }
        if window.isVisible && window.isKeyWindow {
            window.orderOut(nil)
        } else {
            showMainWindow(nil)
        }
    }

    @objc private func showMainWindow(_ sender: Any?) {
        guard let window else { return }
        if !isBootstrapInstaller {
            positionSpotlightPanel(window)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func positionSpotlightPanel(_ window: NSWindow) {
        let statusButton = statusItem?.button
        let statusScreen = statusButton?.window?.screen
        let screen = statusScreen ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        let horizontalMargin: CGFloat = 12
        let verticalMargin: CGFloat = 10
        var originX = visibleFrame.maxX - window.frame.width - horizontalMargin

        if let statusButton, let statusWindow = statusButton.window {
            let buttonRect = statusButton.convert(statusButton.bounds, to: nil)
            let screenRect = statusWindow.convertToScreen(buttonRect)
            originX = screenRect.maxX - window.frame.width + 8
        }

        originX = min(
            max(originX, visibleFrame.minX + horizontalMargin),
            visibleFrame.maxX - window.frame.width - horizontalMargin
        )
        let originY = visibleFrame.maxY - window.frame.height - verticalMargin
        window.setFrameOrigin(NSPoint(x: originX, y: originY))
    }

    @objc private func showSectionFromStatusItem(_ sender: NSMenuItem) {
        guard WhoAmISection.allCases.indices.contains(sender.tag) else { return }
        appState?.selectedSection = WhoAmISection.allCases[sender.tag]
        showMainWindow(nil)
    }

    @objc private func showSearchFromStatusItem(_ sender: Any?) {
        appState?.openSearch()
        showMainWindow(nil)
    }

    @objc private func showAskFromStatusItem(_ sender: Any?) {
        appState?.openAsk()
        showMainWindow(nil)
    }

    @objc private func showMemorySkyFromStatusItem(_ sender: Any?) {
        appState?.isMemorySkyOpen = true
        showMainWindow(nil)
    }

    @objc private func showShareFromStatusItem(_ sender: Any?) {
        appState?.openShare()
        showMainWindow(nil)
    }

    @objc private func quitApplication(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    @objc private func showMaintenance(_ sender: Any?) {
        do {
            if let maintenanceWindow {
                maintenanceWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            let productVersion = try bundleString("WhoAmIProductVersion")
            let persomeRoot = try fileURL(fromBundleKey: "WhoAmIPersomeRoot")
            let controller = lifecycleController ?? NativeLifecycleController()
            lifecycleController = controller
            let host = NSHostingView(
                rootView: NativeMaintenanceView(
                    controller: controller,
                    productVersion: productVersion,
                    persomeRoot: persomeRoot
                )
            )
            let panel = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 700),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
            panel.title = "Who Am I · 安装与维护"
            panel.minSize = NSSize(width: 680, height: 620)
            panel.contentView = host
            panel.isReleasedWhenClosed = false
            panel.center()
            panel.makeKeyAndOrderFront(nil)
            maintenanceWindow = panel
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            report(error)
        }
    }

    private func makeLoadingView() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        let material = NSVisualEffectView()
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 18
        material.layer?.masksToBounds = true
        material.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(material)
        let title = NSTextField(labelWithString: "正在连接你的 Personal Model")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.alignment = .center
        let progress = NSProgressIndicator()
        progress.style = .spinning
        progress.controlSize = .regular
        progress.isIndeterminate = true
        progress.startAnimation(nil)
        let stack = NSStackView(views: [title, progress])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        material.addSubview(stack)
        NSLayoutConstraint.activate([
            material.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            material.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            material.widthAnchor.constraint(equalToConstant: 460),
            material.heightAnchor.constraint(equalToConstant: 116),
            stack.centerXAnchor.constraint(equalTo: material.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: material.centerYAnchor),
        ])
        return container
    }

    private func makeBootstrapView() -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let title = NSTextField(labelWithString: "正在设置 Who Am I")
        title.font = .systemFont(ofSize: 26, weight: .semibold)
        title.alignment = .center

        let detail = NSTextField(
            wrappingLabelWithString: "首次打开会先验证安装包，再在 App 内初始化或连接你的 Personal Model。"
        )
        detail.font = .systemFont(ofSize: 15)
        detail.textColor = .secondaryLabelColor
        detail.alignment = .center
        detail.maximumNumberOfLines = 4

        let progress = NSProgressIndicator()
        progress.style = .spinning
        progress.controlSize = .regular
        progress.isIndeterminate = true
        progress.startAnimation(nil)

        let privacy = NSTextField(
            wrappingLabelWithString: "Personal Model 和 Personal Card 数据只保存在当前 Mac 用户目录中。"
        )
        privacy.font = .systemFont(ofSize: 12)
        privacy.textColor = .tertiaryLabelColor
        privacy.alignment = .center

        let stack = NSStackView(views: [title, detail, progress, privacy])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 20
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 44, bottom: 24, right: 44)
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 36),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -36),
            detail.widthAnchor.constraint(lessThanOrEqualToConstant: 500),
            privacy.widthAnchor.constraint(lessThanOrEqualToConstant: 500),
        ])
        return container
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
            let expectedVersion = try bundleString("WhoAmIProductVersion")
            if isBootstrapInstaller {
                try beginNativeBootstrap(expectedVersion: expectedVersion)
                return
            }
            let productRoot = try fileURL(fromBundleKey: "WhoAmIProductRoot")
            let persomeRoot = try fileURL(fromBundleKey: "WhoAmIPersomeRoot")

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

    private func beginNativeBootstrap(expectedVersion: String) throws {
        guard let resourcesURL = Bundle.main.resourceURL else {
            throw LauncherError.missingInstaller("Contents/Resources/product")
        }
        let packageRoot = resourcesURL
            .appendingPathComponent("product", isDirectory: true)
            .standardizedFileURL
        let installerURL = packageRoot
            .appendingPathComponent("install.sh", isDirectory: false)
        let manifestURL = packageRoot
            .appendingPathComponent("SELF-CONTAINED-SHA256SUMS", isDirectory: false)
        guard
            FileManager.default.fileExists(atPath: installerURL.path),
            FileManager.default.fileExists(atPath: manifestURL.path)
        else {
            throw LauncherError.missingInstaller(installerURL.lastPathComponent)
        }
        let controller = NativeLifecycleController()
        lifecycleController = controller
        window?.contentView = NSHostingView(
            rootView: NativeInstallerView(controller: controller)
        )
        controller.configureBootstrap(
            productRoot: packageRoot,
            expectedVersion: expectedVersion,
            completion: { [weak self] installedApp in
                self?.openInstalledApplication(installedApp)
            }
        )
        controller.startBootstrap()
    }

    private func openInstalledApplication(_ appURL: URL) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isTerminating else { return }
            self.isTerminating = true
            NSWorkspace.shared.open(appURL)
            NSApp.terminate(nil)
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
            Task { @MainActor [weak self] in
                self?.appendServerOutput(data)
            }
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
            guard let self, let window = self.window else { return }
            let state = PersonalModelAppState(baseURL: serverURL)
            self.appState = state
            let host = NSHostingView(rootView: WhoAmIRootView(state: state))
            host.wantsLayer = true
            host.layer?.backgroundColor = NSColor.clear.cgColor
            window.contentView = host
            window.backgroundColor = .clear
            self.statusMenuModelItem?.title = "Personal Model · 已连接"
            self.showMainWindow(nil)
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
            self.statusMenuModelItem?.title = "Personal Model · 连接失败"

            let alert = NSAlert()
            alert.alertStyle = .critical
            alert.messageText = "Who Am I 无法打开"
            alert.informativeText = (error as? LocalizedError)?.errorDescription
                ?? "本机服务暂时不可用。"
            alert.addButton(withTitle: "重新连接")
            alert.addButton(withTitle: "退出")
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                self.didReportFailure = false
                self.window?.contentView = self.makeLoadingView()
                Task { [weak self] in await self?.prepareAndLoad() }
            } else {
                NSApp.terminate(nil)
            }
        }
    }

}

@main
private struct WhoAmIMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.run()
    }
}

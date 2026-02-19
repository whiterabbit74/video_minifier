import SwiftUI
import AppKit

@main
struct VideoMinifierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settingsService = SettingsService()
    @State private var windowController: NSWindowController?
    @State private var showIncompatibilityAlert = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settingsService)
                .onAppear {
                    appDelegate.settingsService = settingsService
                    checkArchitectureCompatibility()
                    setupWindow()
                    configureAppBehavior()
                }
                .onReceive(settingsService.$settings) { settings in
                    configureAppBehavior()
                }
                .alert(NSLocalizedString("Несовместимая архитектура", comment: ""), isPresented: $showIncompatibilityAlert) {
                    Button(NSLocalizedString("Выйти", comment: "")) {
                        NSApp.terminate(nil)
                    }
                } message: {
                    Text(NSLocalizedString("Это приложение оптимизировано для процессоров Apple Silicon (M1/M2/M3) и не может работать на Intel Mac. Пожалуйста, используйте Mac с процессором Apple Silicon.", comment: ""))
                }
        }
    }
    
    private func checkArchitectureCompatibility() {
        #if arch(arm64)
        // App is running natively on Apple Silicon - all good
        #else
        // App is running on Intel or through Rosetta
        showIncompatibilityAlert = true
        #endif
    }
    
    private func setupWindow() {
        // Get the main window
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                self.windowController = NSWindowController(window: window)
                
                // Set window properties
                window.title = NSLocalizedString("Видео-Сжимака", comment: "")
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .visible
                window.setFrameAutosaveName("MainWindow")
                window.toolbarStyle = .unified
                
                // Restore window frame if available
                if let savedFrame = settingsService.loadWindowFrame() {
                    window.setFrame(savedFrame, display: true)
                } else {
                    // Set default frame
                    let defaultFrame = SettingsService.defaultWindowFrame
                    window.setFrame(defaultFrame, display: true)
                }
                
                // Sidebar has fixed width, so keep a larger minimum width.
                window.minSize = NSSize(width: 980, height: 620)
                
                // Save window frame when it changes
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didMoveNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    settingsService.saveWindowFrame(window.frame)
                }
                
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    settingsService.saveWindowFrame(window.frame)
                }
                
            }
        }
    }
    
    private func configureAppBehavior() {
        let settings = settingsService.settings
        
        // Configure Dock visibility
        if settings.showInDock {
            NSApp.setActivationPolicy(.regular)
        } else if settings.showInMenuBar {
            NSApp.setActivationPolicy(.accessory)
        } else {
            // If neither Dock nor MenuBar is enabled, force Dock visibility
            // to prevent the app from becoming inaccessible
            NSApp.setActivationPolicy(.regular)
        }
        
        // Configure menu bar behavior
        if settings.showInMenuBar {
            setupMenuBarItem()
        } else {
            removeMenuBarItem()
        }
    }
    
    private func setupMenuBarItem() {
        guard let delegate = AppDelegate.shared else { return }
        // Create status bar item if it doesn't exist
        if delegate.statusItem == nil {
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.button?.title = "🎬"
            statusItem.button?.toolTip = NSLocalizedString("Видео-Сжимака", comment: "")
            
            let menu = NSMenu()
            let itemShow = NSMenuItem(title: NSLocalizedString("Показать окно", comment: ""), action: #selector(AppDelegate.showMainWindow), keyEquivalent: "")
            itemShow.target = delegate
            menu.addItem(itemShow)
            menu.addItem(NSMenuItem.separator())
            let itemSettings = NSMenuItem(title: NSLocalizedString("Настройки", comment: ""), action: #selector(AppDelegate.showSettings), keyEquivalent: ",")
            itemSettings.target = delegate
            menu.addItem(itemSettings)
            let itemLogs = NSMenuItem(title: NSLocalizedString("menu.logs", comment: "Menu item title for logs"), action: #selector(AppDelegate.showLogs), keyEquivalent: "l")
            itemLogs.target = delegate
            menu.addItem(itemLogs)
            let itemAbout = NSMenuItem(title: NSLocalizedString("О программе", comment: ""), action: #selector(AppDelegate.showAbout), keyEquivalent: "")
            itemAbout.target = delegate
            menu.addItem(itemAbout)
            menu.addItem(NSMenuItem.separator())
            let itemQuit = NSMenuItem(title: NSLocalizedString("Выйти", comment: ""), action: #selector(AppDelegate.quit), keyEquivalent: "q")
            itemQuit.target = delegate
            menu.addItem(itemQuit)
            
            statusItem.menu = menu
            delegate.statusItem = statusItem
        }
    }
    
    private func removeMenuBarItem() {
        if let statusItem = AppDelegate.shared?.statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            AppDelegate.shared?.statusItem = nil
        }
    }
}

// MARK: - AppDelegate for Menu Bar Support

class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    var statusItem: NSStatusItem?
    weak var settingsService: SettingsService?
    private var aboutWindow: NSWindow?
    private var logsWindow: NSWindow?
    private var pendingOpenURLs: [URL] = []
    
    override init() {
        super.init()
        AppDelegate.shared = self
    }
    
    @objc func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    func applyTheme(_ theme: String) {
        switch theme {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }
    
    @objc func showSettings() {
        showMainWindow()
        NotificationCenter.default.post(name: .showSettings, object: nil)
    }

    func showSettingsWindow() {
        // Keep API compatibility for existing callers, but route to in-app tab.
        showSettings()
    }
    
    @objc func showAbout() {
        if let aboutWindow = aboutWindow {
            aboutWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let hostingView = NSHostingView(rootView: AboutView())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 360),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered,
                              defer: false)
        window.center()
        window.title = NSLocalizedString("О программе", comment: "")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.zoomButton)?.isHidden = true
        
        self.aboutWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            self?.aboutWindow = nil
        }
    }

    @objc func showLogs() {
        showLogsWindow()
    }
    
    func showLogsWindow() {
        if let logsWindow = logsWindow {
            logsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let hostingView = NSHostingView(rootView: LogsView(loggingService: LoggingService.shared))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered,
                              defer: false)
        window.center()
        window.title = NSLocalizedString("menu.logs", comment: "Logs window title")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 900, height: 600)
        
        self.logsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            self?.logsWindow = nil
        }
    }
    
    @objc func quit() {
        NSApp.terminate(nil)
    }

    func application(_ application: NSApplication, openFile filename: String) -> Bool {
        handleOpenFiles([URL(fileURLWithPath: filename)])
        return true
    }

    func application(_ application: NSApplication, openFiles filenames: [String]) {
        handleOpenFiles(filenames.map { URL(fileURLWithPath: $0) })
        application.reply(toOpenOrPrint: .success)
    }
    
    func application(_ application: NSApplication, open urls: [URL]) {
        handleOpenFiles(urls)
    }

    func consumePendingOpenFiles() -> [URL] {
        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()
        return urls
    }

    private func handleOpenFiles(_ urls: [URL]) {
        pendingOpenURLs.append(contentsOf: urls)
        NotificationCenter.default.post(name: .openFiles, object: nil, userInfo: ["urls": urls])
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showSettings = Notification.Name("showSettings")
    static let openLogs = Notification.Name("openLogs")
    static let openFiles = Notification.Name("openFiles")
}

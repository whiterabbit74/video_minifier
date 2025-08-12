import SwiftUI
import AppKit

@main
struct VideoSzhimakaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settingsService = SettingsService()
    @State private var windowController: NSWindowController?
    @State private var showIncompatibilityAlert = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settingsService)
                .onAppear {
                    checkArchitectureCompatibility()
                    setupWindow()
                    configureAppBehavior()
                }
                .onReceive(settingsService.$settings) { settings in
                    configureAppBehavior()
                }
                .alert("Несовместимая архитектура", isPresented: $showIncompatibilityAlert) {
                    Button("Выйти") {
                        NSApp.terminate(nil)
                    }
                } message: {
                    Text("Это приложение оптимизировано для процессоров Apple Silicon (M1/M2/M3) и не может работать на Intel Mac. Пожалуйста, используйте Mac с процессором Apple Silicon.")
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
                window.title = "Видео-Сжимака"
                window.titlebarAppearsTransparent = false
                window.titleVisibility = .visible
                
                // Restore window frame if available
                if let savedFrame = settingsService.loadWindowFrame() {
                    window.setFrame(savedFrame, display: true)
                } else {
                    // Set default frame
                    let defaultFrame = SettingsService.defaultWindowFrame
                    window.setFrame(defaultFrame, display: true)
                }
                
                // Set minimum size
                window.minSize = NSSize(width: 700, height: 500)
                
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
        // Create status bar item if it doesn't exist
        if AppDelegate.shared.statusItem == nil {
            let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statusItem.button?.title = "🎬"
            statusItem.button?.toolTip = "Видео-Сжимака"
            
            let menu = NSMenu()
            let itemShow = NSMenuItem(title: "Показать окно", action: #selector(AppDelegate.showMainWindow), keyEquivalent: "")
            itemShow.target = AppDelegate.shared
            menu.addItem(itemShow)
            menu.addItem(NSMenuItem.separator())
            let itemSettings = NSMenuItem(title: "Настройки", action: #selector(AppDelegate.showSettings), keyEquivalent: ",")
            itemSettings.target = AppDelegate.shared
            menu.addItem(itemSettings)
            menu.addItem(NSMenuItem.separator())
            let itemQuit = NSMenuItem(title: "Выйти", action: #selector(AppDelegate.quit), keyEquivalent: "q")
            itemQuit.target = AppDelegate.shared
            menu.addItem(itemQuit)
            
            statusItem.menu = menu
            AppDelegate.shared.statusItem = statusItem
        }
    }
    
    private func removeMenuBarItem() {
        if let statusItem = AppDelegate.shared.statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            AppDelegate.shared.statusItem = nil
        }
    }
}

// MARK: - AppDelegate for Menu Bar Support

class AppDelegate: NSObject, NSApplicationDelegate {
    static let shared = AppDelegate()
    var statusItem: NSStatusItem?
    
    @objc func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
    
    @objc func showSettings() {
        showMainWindow()
        // Post notification to show settings
        NotificationCenter.default.post(name: .showSettings, object: nil)
    }
    
    @objc func quit() {
        NSApp.terminate(nil)
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let showSettings = Notification.Name("showSettings")
}
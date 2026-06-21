import SwiftUI

@main
struct MP4MergerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    @StateObject private var languageManager = LanguageManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(languageManager)
                .frame(minWidth: 500, idealWidth: 500, maxWidth: .infinity, minHeight: 500, idealHeight: 600, maxHeight: .infinity)
        }
        
        Settings {
            SettingsView()
                .environmentObject(languageManager)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

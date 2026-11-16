import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // SwiftPM launches a bare executable, so opt into normal Mac app activation.
        NSApp.setActivationPolicy(.regular)
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png") {
            NSApp.applicationIconImage = NSImage(contentsOf: url)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main struct SpineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene { WindowGroup { LibraryView() }.defaultSize(width: 1280, height: 850) }
}

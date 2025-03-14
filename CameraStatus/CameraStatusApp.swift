import SwiftUI

@main
struct CameraStatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusBarController: StatusBarController?
    var popover = NSPopover()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        let contentView = CameraStatusView()
        
        popover.contentSize = NSSize(width: 300, height: 300)
        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.behavior = .transient
        
        statusBarController = StatusBarController(popover: popover)
        
        // We'll no longer try to start scanning here
        // Let the BLEManager handle this at the appropriate time
    }
}

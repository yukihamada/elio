#if targetEnvironment(macCatalyst)
import UIKit

/// Triggers the standard macOS "About ElioChat" panel via AppKit bridge.
/// Call this from a menu item or button when running under Mac Catalyst.
enum MacAboutBridge {
    static func showAboutPanel() {
        // Mac Catalyst can call NSApp.orderFrontStandardAboutPanel via Obj-C runtime
        // Info.plist keys populate the panel: CFBundleShortVersionString, NSHumanReadableCopyright
        if let nsApp = NSClassFromString("NSApplication"),
           let shared = nsApp.value(forKeyPath: "sharedApplication") as? NSObject {
            shared.perform(NSSelectorFromString("orderFrontStandardAboutPanel:"), with: nil)
        }
    }
}
#endif

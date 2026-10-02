import AppKit
import ServiceManagement

/// "Open at login" through SMAppService – shows up in System Settings → General → Login Items.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Returns an error message on failure.
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            return "Không đổi được mục khởi động: \(error.localizedDescription)"
        }
        if enabled && needsApproval {
            SMAppService.openSystemSettingsLoginItems()
            return "macOS cần bạn bật Sweepy trong System Settings → General → Login Items."
        }
        return nil
    }

    /// True when macOS started the app as a login item rather than the user opening it.
    static var launchedAtLogin: Bool {
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventID == kAEOpenApplication,
           event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            return true
        }
        // Fallback: started within 3 minutes of the user session beginning.
        var boot = timeval()
        var size = MemoryLayout<timeval>.stride
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return false }
        return Date().timeIntervalSince1970 - Double(boot.tv_sec) < 180
    }
}

import UIKit
import Darwin

// ─────────────────────────────────────────────
//  SecurityManager
//
//  Runs at launch and checks for:
//    • Jailbroken device (file artefacts, sandbox
//      escape, URL schemes, injected dylibs)
//    • Attached debugger (sysctl P_TRACED, release
//      builds only — debug builds skip this so
//      Xcode works normally)
//
//  Results are used by ReceiptValidator to refuse
//  subscription trust on compromised devices, and
//  by any premium-gated view that needs to know
//  whether the environment is trustworthy.
//
//  Usage (in BeautyBriefApp.init):
//    SecurityManager.shared.runChecks()
// ─────────────────────────────────────────────

enum SecurityThreat: String, Hashable {
    case jailbreak
    case debugger
}

@MainActor
final class SecurityManager: ObservableObject {

    static let shared = SecurityManager()
    private init() {}

    // MARK: — Published state

    @Published private(set) var threats: Set<SecurityThreat> = []

    var isJailbroken: Bool { threats.contains(.jailbreak) }
    var isDebugged:   Bool { threats.contains(.debugger) }

    /// Subscription receipts should never be trusted locally on a
    /// compromised device — force server-side re-validation instead.
    var subscriptionEnvironmentTrusted: Bool { threats.isEmpty }

    // MARK: — Entry point

    func runChecks() {
        // Always check jailbreak (simulator-safe — always returns false in Simulator).
        if detectJailbreak() { threats.insert(.jailbreak) }

        // Debugger check runs in release builds only.
        // In DEBUG the check is compiled out so Xcode can attach normally.
        #if !DEBUG
        if detectDebugger() { threats.insert(.debugger) }
        #endif
    }

    // MARK: — Jailbreak detection

    private func detectJailbreak() -> Bool {

        // Simulators are never jailbroken.
        #if targetEnvironment(simulator)
        return false
        #endif

        // 1 ── Common jailbreak artefact paths
        let suspiciousPaths: [String] = [
            "/Applications/Cydia.app",
            "/Applications/FakeCarrier.app",
            "/Applications/Icy.app",
            "/Applications/IntelliScreen.app",
            "/Applications/SBSettings.app",
            "/bin/bash",
            "/etc/apt",
            "/Library/MobileSubstrate/DynamicLibraries/LiveClock.plist",
            "/Library/MobileSubstrate/DynamicLibraries/Veency.plist",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/private/var/lib/apt",
            "/private/var/lib/cydia",
            "/private/var/mobile/Library/SBSettings/Themes",
            "/private/var/stash",
            "/private/var/tmp/cydia.log",
            "/System/Library/LaunchDaemons/com.saurik.Cydia.Startup.plist",
            "/usr/bin/cycript",
            "/usr/bin/ssh",
            "/usr/bin/sshd",
            "/usr/libexec/sftp-server",
            "/usr/sbin/sshd",
        ]
        for path in suspiciousPaths {
            if FileManager.default.fileExists(atPath: path) { return true }
        }

        // 2 ── Attempt to write outside the app sandbox
        //      (only possible on jailbroken devices)
        let probeFile = "/private/bb_probe_\(arc4random()).tmp"
        do {
            try "probe".write(toFile: probeFile, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: probeFile)
            return true
        } catch {}

        // 3 ── Cydia / Sileo URL schemes
        let jailbreakSchemes = ["cydia://", "sileo://", "zbra://", "filza://"]
        for scheme in jailbreakSchemes {
            if let url = URL(string: scheme), UIApplication.shared.canOpenURL(url) {
                return true
            }
        }

        // 4 ── Injected dynamic libraries
        //      Frida, Substrate, Cycript, libhooker all leave recognisable
        //      strings in the image name list.
        let suspiciousLibs = ["substrate", "cycript", "cynject", "libhooker",
                               "frida", "substitute", "tweakinject"]
        for i in 0..<_dyld_image_count() {
            guard let rawName = _dyld_get_image_name(i) else { continue }
            let imageName = String(cString: rawName).lowercased()
            for lib in suspiciousLibs where imageName.contains(lib) {
                return true
            }
        }

        return false
    }

    // MARK: — Debugger detection (release only)

    private func detectDebugger() -> Bool {
        var info = kinfo_proc()
        var mib:  [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size  = MemoryLayout<kinfo_proc>.stride
        sysctl(&mib, 4, &info, &size, nil, 0)
        // P_TRACED (0x800) is set when a debugger is attached via ptrace.
        return (info.kp_proc.p_flag & 0x800) != 0
    }
}

import Foundation
import MetricKit

// ─────────────────────────────────────────────
//  CrashReporter
//
//  Uses Apple's MetricKit (iOS 14+, zero dependencies)
//  to catch crash diagnostics and performance issues.
//
//  HOW IT WORKS:
//    • MetricKit delivers diagnostic payloads on the
//      NEXT app launch after a crash, hang, or
//      disk-write exception occurs.
//    • Each payload is written to a dated log file
//      in the app's Documents directory.
//    • On first launch after a crash, an email draft
//      is also prepared so you can send it to yourself.
//
//  SETUP (already wired in BeautyBriefApp.swift):
//    CrashReporter.shared.start()
//
//  TO VIEW LOGS:
//    Open Files app → On My iPhone → BeautyBrief
//    → crash_reports/
//    Or check your email if you sent the draft.
// ─────────────────────────────────────────────

@MainActor
final class CrashReporter: NSObject, ObservableObject {

    static let shared = CrashReporter()
    private override init() {}

    // MARK: — Published state

    /// True if a crash was detected since last launch.
    @Published private(set) var crashDetectedOnLastLaunch = false

    // MARK: — Configuration

    private static let supportEmail = "beautybriefapp@gmail.com"

    // MARK: — Start

    /// Call once in BeautyBriefApp.init() — registers this class
    /// as a MetricKit subscriber so diagnostics are delivered automatically.
    func start() {
        MXMetricManager.shared.add(self)
    }

    // MARK: — Log directory

    private static var logDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir  = docs.appendingPathComponent("crash_reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static var dateStamp: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f.string(from: Date())
    }

    // MARK: — Write log

    private func writeLog(_ text: String, filename: String) {
        let url = Self.logDirectory.appendingPathComponent(filename)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: — Format diagnostic payload

    private func format(_ payload: MXDiagnosticPayload) -> String {
        var lines: [String] = [
            "═══════════════════════════════════",
            "BeautyBrief Diagnostic Report",
            "Generated: \(Self.dateStamp)",
            "Time range: \(payload.timeStampBegin) → \(payload.timeStampEnd)",
            "═══════════════════════════════════",
            ""
        ]

        // ── Crashes ──
        if let crashes = payload.crashDiagnostics, !crashes.isEmpty {
            lines.append("CRASHES (\(crashes.count))")
            lines.append(String(repeating: "─", count: 40))
            for (i, crash) in crashes.enumerated() {
                lines.append("Crash #\(i + 1)")
                lines.append("  Exception type:   \(crash.exceptionType ?? "unknown")")
                lines.append("  Exception code:   \(crash.exceptionCode ?? "unknown")")
                lines.append("  Signal:           \(crash.signal ?? "unknown")")
                lines.append("  Termination reason: \(crash.terminationReason ?? "unknown")")
                lines.append("  Virtual memory region info: \(crash.virtualMemoryRegionInfo ?? "none")")
                lines.append("")
                lines.append("  Stack trace:")
                crash.callStackTree.callStacks.forEach { stack in
                    stack.callStackRootFrames.forEach { frame in
                        lines.append("    \(formatFrame(frame))")
                    }
                }
                lines.append("")
            }
        }

        // ── Hangs ──
        if let hangs = payload.hangDiagnostics, !hangs.isEmpty {
            lines.append("HANGS (\(hangs.count))")
            lines.append(String(repeating: "─", count: 40))
            for (i, hang) in hangs.enumerated() {
                lines.append("Hang #\(i + 1)")
                lines.append("  Duration: \(hang.hangDuration)")
                lines.append("")
                lines.append("  Stack trace:")
                hang.callStackTree.callStacks.forEach { stack in
                    stack.callStackRootFrames.forEach { frame in
                        lines.append("    \(formatFrame(frame))")
                    }
                }
                lines.append("")
            }
        }

        // ── CPU exceptions ──
        if let cpuExceptions = payload.cpuExceptionDiagnostics, !cpuExceptions.isEmpty {
            lines.append("CPU EXCEPTIONS (\(cpuExceptions.count))")
            lines.append(String(repeating: "─", count: 40))
            for (i, exc) in cpuExceptions.enumerated() {
                lines.append("CPU Exception #\(i + 1)")
                lines.append("  Total CPU time:   \(exc.totalCPUTime)")
                lines.append("  Total sampled time: \(exc.totalSampledTime)")
                lines.append("")
            }
        }

        // ── Disk write exceptions ──
        if let diskExceptions = payload.diskWriteExceptionDiagnostics, !diskExceptions.isEmpty {
            lines.append("DISK WRITE EXCEPTIONS (\(diskExceptions.count))")
            lines.append(String(repeating: "─", count: 40))
            for (i, exc) in diskExceptions.enumerated() {
                lines.append("Disk Write Exception #\(i + 1)")
                lines.append("  Total writes caused: \(exc.totalWritesCaused)")
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func formatFrame(_ frame: MXCallStackFrame) -> String {
        var s = frame.binaryName ?? "unknown"
        if let offset = frame.offsetIntoBinaryTextSegment {
            s += " + \(offset)"
        }
        if let address = frame.address {
            s += " (0x\(String(address, radix: 16)))"
        }
        return s
    }

    // MARK: — Format metric payload (performance stats)

    private func formatMetrics(_ payload: MXMetricPayload) -> String {
        var lines: [String] = [
            "═══════════════════════════════════",
            "BeautyBrief Performance Report",
            "Generated: \(Self.dateStamp)",
            "Time range: \(payload.timeStampBegin) → \(payload.timeStampEnd)",
            "Latest app version: \(payload.latestApplicationVersion)",
            "═══════════════════════════════════",
            ""
        ]

        if let launch = payload.applicationLaunchMetrics {
            lines.append("LAUNCH TIMES")
            lines.append(String(repeating: "─", count: 40))
            lines.append("  Time to first draw:      \(launch.histogrammedTimeToFirstDraw)")
            lines.append("  Application resume time: \(launch.histogrammedApplicationResumeTime)")
            lines.append("")
        }

        if let hang = payload.applicationResponsivenessMetrics {
            lines.append("RESPONSIVENESS")
            lines.append(String(repeating: "─", count: 40))
            lines.append("  Hang rate: \(hang.histogrammedApplicationHangTime)")
            lines.append("")
        }

        if let memory = payload.memoryMetrics {
            lines.append("MEMORY")
            lines.append(String(repeating: "─", count: 40))
            lines.append("  Peak memory: \(memory.peakMemoryUsage)")
            lines.append("  Avg suspended memory: \(memory.averageSuspendedMemory)")
            lines.append("")
        }

        if let cpu = payload.cpuMetrics {
            lines.append("CPU")
            lines.append(String(repeating: "─", count: 40))
            lines.append("  Cumulative CPU time: \(cpu.cumulativeCPUTime)")
            lines.append("")
        }

        if let network = payload.networkTransferMetrics {
            lines.append("NETWORK")
            lines.append(String(repeating: "─", count: 40))
            lines.append("  Cellular upload:   \(network.cumulativeCellularUpload)")
            lines.append("  Cellular download: \(network.cumulativeCellularDownload)")
            lines.append("  WiFi upload:       \(network.cumulativeWifiUpload)")
            lines.append("  WiFi download:     \(network.cumulativeWifiDownload)")
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}

// MARK: — MXMetricManagerSubscriber

extension CrashReporter: MXMetricManagerSubscriber {

    /// Called ~24 hours after each metric period ends (once per day).
    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            let text     = formatMetrics(payload)
            let filename = "metrics_\(Self.dateStamp).txt"
            Task { @MainActor in
                writeLog(text, filename: filename)
            }
        }
    }

    /// Called on the NEXT launch after a crash, hang, CPU spike, or
    /// excessive disk write is detected.
    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        guard !payloads.isEmpty else { return }

        var hasCrash = false
        for payload in payloads {
            let text     = format(payload)
            let filename = "crash_\(Self.dateStamp).txt"

            Task { @MainActor in
                writeLog(text, filename: filename)
            }

            if let crashes = payload.crashDiagnostics, !crashes.isEmpty {
                hasCrash = true
            }
        }

        if hasCrash {
            Task { @MainActor in
                crashDetectedOnLastLaunch = true
            }
        }
    }
}

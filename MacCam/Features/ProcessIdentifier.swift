import AppKit
import Foundation

struct ProcessCandidate: Equatable {
    let pid: pid_t
    let app: AppIdentity
    let score: Int
    let confidence: Double
}

/// Heuristic identification of which process is using the camera.
/// macOS does not expose a public "who owns the camera" API.
final class ProcessIdentifier {
    /// Well-known camera / video calling apps (bundle ID → bonus score).
    static let knownCameraApps: [String: Int] = [
        "com.apple.FaceTime": 80,
        "com.apple.PhotoBooth": 80,
        "com.apple.Safari": 40,
        "com.apple.WebKit.GPU": 55,
        "com.apple.WebKit.WebContent": 45,
        "com.google.Chrome": 50,
        "com.google.Chrome.helper": 55,
        "com.microsoft.edgemac": 45,
        "company.thebrowser.Browser": 40,
        "us.zoom.xos": 90,
        "com.hnc.Discord": 70,
        "com.tinyspeck.slackmacgap": 70,
        "com.microsoft.teams": 70,
        "com.microsoft.teams2": 70,
        "com.skype.skype": 70,
        "com.apple.Camera": 80,
        "com.apple.camera": 80,
        "com.obsproject.obs-studio": 75,
        "com.loom.desktop": 65,
        "com.webex.meetingmanager": 65,
        "com.cisco.webexmeetingsapp": 65,
        "com.apple.QuickTimePlayerX": 60
    ]

    private let selfPID: pid_t

    init(selfPID: pid_t = getpid()) {
        self.selfPID = selfPID
    }

    func identifyLikelyCameraUser(
        runningApps: [NSRunningApplication] = NSWorkspace.shared.runningApplications,
        frontmost: NSRunningApplication? = NSWorkspace.shared.frontmostApplication
    ) -> ProcessCandidate? {
        let scored = scoreCandidates(runningApps: runningApps, frontmost: frontmost)
        return scored.first
    }

    func scoreCandidates(
        runningApps: [NSRunningApplication],
        frontmost: NSRunningApplication?
    ) -> [ProcessCandidate] {
        var results: [ProcessCandidate] = []

        for app in runningApps {
            let pid = app.processIdentifier
            guard pid > 0, pid != selfPID else { continue }
            guard app.activationPolicy != .prohibited else { continue }

            let bundleID = app.bundleIdentifier ?? ""
            let processName = app.localizedName ?? (app.executableURL?.lastPathComponent ?? "Unknown")
            let identity = AppIdentity(
                bundleID: bundleID,
                processName: processName,
                displayName: app.localizedName ?? processName
            )

            var score = 0
            if let frontmost, frontmost.processIdentifier == pid {
                score += 100
            }
            if app.isActive {
                score += 20
            }
            if let bonus = Self.knownCameraApps[bundleID] {
                score += bonus
            }
            // Prefer regular apps over accessories/agents.
            switch app.activationPolicy {
            case .regular:
                score += 15
            case .accessory:
                score += 5
            default:
                break
            }

            guard score > 0 else { continue }

            let confidence = min(1.0, Double(score) / 200.0)
            results.append(ProcessCandidate(pid: pid, app: identity, score: score, confidence: confidence))
        }

        return results.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.pid < rhs.pid
        }
    }

    /// Testable pure scoring without AppKit objects.
    static func score(
        bundleID: String,
        processName: String,
        isFrontmost: Bool,
        isActive: Bool,
        activationPolicy: NSApplication.ActivationPolicy,
        selfPID: pid_t,
        pid: pid_t
    ) -> Int {
        guard pid > 0, pid != selfPID else { return 0 }
        var score = 0
        if isFrontmost { score += 100 }
        if isActive { score += 20 }
        if let bonus = knownCameraApps[bundleID] { score += bonus }
        switch activationPolicy {
        case .regular: score += 15
        case .accessory: score += 5
        default: break
        }
        // Tiny bump for camera-ish names when bundle is unknown.
        if bundleID.isEmpty {
            let lower = processName.lowercased()
            if lower.contains("camera") || lower.contains("facetime") || lower.contains("zoom") {
                score += 25
            }
        }
        return score
    }
}

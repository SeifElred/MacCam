import Foundation

/// Read ISP / camera power without opening a CMIO session.
/// `ioreg` on AppleH13CamIn does not call ConnectClient, so it will not re-light the LED.
enum ISPPowerProbe {
    /// `CurrentPowerState` from AppleH13CamIn IOPowerManagement (0 = cold / LED should be dark).
    static func currentPowerState() -> Int? {
        guard let output = runIoreg() else { return nil }
        // Prefer the AppleH13CamIn block's IOPowerManagement dict.
        if let range = output.range(of: #""CurrentPowerState"\s*=\s*(\d+)"#, options: .regularExpression) {
            let token = output[range]
            if let num = token.split(separator: "=").last?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               let value = Int(num) {
                return value
            }
        }
        return nil
    }

    /// True when the sensor/ISP is powered (green LED hardwired on).
    static var isSensorWarm: Bool {
        (currentPowerState() ?? 0) > 0
    }

    static var isFrontCameraStreaming: Bool {
        guard let output = runIoreg() else { return false }
        return output.contains("\"FrontCameraStreaming\" = Yes")
    }

    private static func runIoreg() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-c", "AppleH13CamIn", "-r", "-l", "-w", "0"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

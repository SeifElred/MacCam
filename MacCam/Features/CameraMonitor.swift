import CoreMediaIO
import Foundation

/// Polls CoreMediaIO for camera hardware activity.
/// Reading `kCMIODevicePropertyDeviceIsRunningSomewhere` does not require Camera TCC permission.
///
/// Important (M-series / appleh13camerad): any CMIO device enumeration talks to the ISP
/// extension and calls `ISP_PowerOnCamera`, resetting a ~4s DeferredPowerOff timer.
/// Polling while Privacy Lock + OS ban are active therefore keeps the green LED on.
/// Suspend hardware polling whenever the camera ban is active.
final class CameraMonitor: ObservableObject {
    @Published private(set) var isCameraOn: Bool = false
    @Published private(set) var lastChecked: Date = .distantPast
    /// When true, skip CoreMediaIO entirely so MacCam does not keep the ISP warm.
    @Published private(set) var hardwarePollingSuspended: Bool = false

    private var timer: Timer?
    private var pollInterval: TimeInterval
    private let includeExternal: Bool

    init(pollInterval: TimeInterval = 0.10, includeExternal: Bool = true) {
        self.pollInterval = pollInterval
        self.includeExternal = includeExternal
    }

    func start() {
        stop()
        // Do not CMIO-refresh while suspended — that ConnectClient wakes the ISP/LED.
        guard !hardwarePollingSuspended else {
            lastChecked = Date()
            isCameraOn = false
            return
        }
        refresh()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func setPollInterval(_ interval: TimeInterval) {
        guard abs(interval - pollInterval) > 0.001 else { return }
        pollInterval = interval
        if timer != nil || (!hardwarePollingSuspended && lastChecked != .distantPast) {
            start()
        }
    }

    /// Suspend/resume CMIO polling. While suspended, reports sensor off (ban handles privacy).
    func setHardwarePollingSuspended(_ suspended: Bool) {
        guard suspended != hardwarePollingSuspended else { return }
        hardwarePollingSuspended = suspended
        if suspended {
            timer?.invalidate()
            timer = nil
            if isCameraOn { isCameraOn = false }
            lastChecked = Date()
        } else {
            start()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        if hardwarePollingSuspended {
            lastChecked = Date()
            if isCameraOn { isCameraOn = false }
            return
        }
        let active = Self.isAnyCameraRunning(includeExternal: includeExternal)
        lastChecked = Date()
        if active != isCameraOn {
            isCameraOn = active
        }
    }

    /// Pure helper used by tests and production.
    static func isAnyCameraRunning(includeExternal: Bool = true) -> Bool {
        for deviceID in allDeviceIDs() {
            // Prefer built-in FaceTime camera for “running somewhere” (ISP activity).
            if isBuiltIn(deviceID) {
                if isRunningSomewhere(deviceID) { return true }
                continue
            }
            if !includeExternal { continue }
            if isLikelyVirtualOnly(deviceID) { continue }
            if isRunningSomewhere(deviceID) { return true }
        }
        return false
    }

    // MARK: - CoreMediaIO

    static func allDeviceIDs() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &dataSize) == 0,
              dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        let status = CMIOObjectGetPropertyData(
            CMIOObjectID(kCMIOObjectSystemObject),
            &address,
            0,
            nil,
            dataSize,
            &dataUsed,
            &devices
        )
        return status == 0 ? devices : []
    }

    static func isRunningSomewhere(_ deviceID: CMIOObjectID) -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )

        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == 0 else {
            return false
        }

        var isRunning: UInt32 = 0
        var dataUsed: UInt32 = 0
        let status = CMIOObjectGetPropertyData(deviceID, &address, 0, nil, dataSize, &dataUsed, &isRunning)
        return status == 0 && isRunning != 0
    }

    static func isBuiltIn(_ deviceID: CMIOObjectID) -> Bool {
        let transport = transportType(deviceID)
        return transport == kIOAudioDeviceTransportTypeBuiltIn
            || transport == kCMIODeviceTransportTypeBuiltIn
    }

    /// Virtual camera plugins often expose latency and have no physical transport.
    static func isLikelyVirtualOnly(_ deviceID: CMIOObjectID) -> Bool {
        var latencyAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyLatency),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard)
        )
        var dataSize: UInt32 = 0
        let hasLatency = CMIOObjectGetPropertyDataSize(deviceID, &latencyAddress, 0, nil, &dataSize) == 0
        guard hasLatency else { return false }

        let transport = transportType(deviceID)
        let physicalTransports: Set<UInt32> = [
            kIOAudioDeviceTransportTypeBuiltIn,
            kCMIODeviceTransportTypeBuiltIn,
            kIOAudioDeviceTransportTypeUSB,
            kIOAudioDeviceTransportTypePCI,
            kIOAudioDeviceTransportTypeBluetooth,
            kIOAudioDeviceTransportTypeFireWire
        ]
        return !physicalTransports.contains(transport)
    }

    static func transportType(_ deviceID: CMIOObjectID) -> UInt32 {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyTransportType),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var transport: UInt32 = 0
        let dataSize = UInt32(MemoryLayout<UInt32>.size)
        var dataUsed: UInt32 = 0
        let status = CMIOObjectGetPropertyData(deviceID, &address, 0, nil, dataSize, &dataUsed, &transport)
        return status == 0 ? transport : 0
    }
}

private let kCMIODeviceTransportTypeBuiltIn: UInt32 = 0x626C746E // 'bltn'
private let kIOAudioDeviceTransportTypeBuiltIn: UInt32 = 0x626C746E
private let kIOAudioDeviceTransportTypeUSB: UInt32 = 0x75736220 // 'usb '
private let kIOAudioDeviceTransportTypePCI: UInt32 = 0x70636920 // 'pci '
private let kIOAudioDeviceTransportTypeBluetooth: UInt32 = 0x626C7565 // 'blue'
private let kIOAudioDeviceTransportTypeFireWire: UInt32 = 0x66697265 // 'fire'

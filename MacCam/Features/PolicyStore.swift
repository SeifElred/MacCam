import Foundation

struct AppIdentity: Codable, Hashable, Identifiable {
    var id: String { bundleID.isEmpty ? processName : bundleID }
    let bundleID: String
    let processName: String
    let displayName: String

    init(bundleID: String, processName: String, displayName: String? = nil) {
        self.bundleID = bundleID
        self.processName = processName
        self.displayName = displayName ?? (processName.isEmpty ? bundleID : processName)
    }
}

enum PolicyDecision: Equatable {
    case allowlisted
    case blocklisted
    case unknown
}

final class PolicyStore: ObservableObject {
    @Published private(set) var allowlist: [AppIdentity] = []
    @Published private(set) var blocklist: [AppIdentity] = []

    private let defaults: UserDefaults
    private let allowKey = "macCam.allowlist"
    private let blockKey = "macCam.blocklist"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    func decision(for app: AppIdentity) -> PolicyDecision {
        if matches(app, in: allowlist) { return .allowlisted }
        if matches(app, in: blocklist) { return .blocklisted }
        return .unknown
    }

    func addToAllowlist(_ app: AppIdentity) {
        removeFromBlocklist(app)
        if !matches(app, in: allowlist) {
            allowlist.append(app)
            save()
        }
    }

    func addToBlocklist(_ app: AppIdentity) {
        removeFromAllowlist(app)
        if !matches(app, in: blocklist) {
            blocklist.append(app)
            save()
        }
    }

    func removeFromAllowlist(_ app: AppIdentity) {
        allowlist.removeAll { same($0, app) }
        save()
    }

    func removeFromBlocklist(_ app: AppIdentity) {
        blocklist.removeAll { same($0, app) }
        save()
    }

    func clearAllowlist() {
        allowlist = []
        save()
    }

    func clearBlocklist() {
        blocklist = []
        save()
    }

    // MARK: - Persistence

    private func load() {
        allowlist = decode(key: allowKey)
        blocklist = decode(key: blockKey)
    }

    private func save() {
        encode(allowlist, key: allowKey)
        encode(blocklist, key: blockKey)
    }

    private func decode(key: String) -> [AppIdentity] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([AppIdentity].self, from: data)) ?? []
    }

    private func encode(_ list: [AppIdentity], key: String) {
        if let data = try? JSONEncoder().encode(list) {
            defaults.set(data, forKey: key)
        }
    }

    private func matches(_ app: AppIdentity, in list: [AppIdentity]) -> Bool {
        list.contains { same($0, app) }
    }

    private func same(_ a: AppIdentity, _ b: AppIdentity) -> Bool {
        if !a.bundleID.isEmpty, !b.bundleID.isEmpty {
            return a.bundleID.caseInsensitiveCompare(b.bundleID) == .orderedSame
        }
        return a.processName.caseInsensitiveCompare(b.processName) == .orderedSame
    }
}

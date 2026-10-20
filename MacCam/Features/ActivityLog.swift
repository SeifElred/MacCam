import Foundation

enum ActivityAction: String, Codable {
    case allowed
    case blocked
    case prompted
    case autoBlocked
    case unlockedUse
}

struct ActivityEvent: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let app: AppIdentity
    let action: ActivityAction
    let detail: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        app: AppIdentity,
        action: ActivityAction,
        detail: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.app = app
        self.action = action
        self.detail = detail
    }
}

final class ActivityLog: ObservableObject {
    @Published private(set) var events: [ActivityEvent] = []

    private let maxEvents = 200
    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.maccam.activitylog")

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = support.appendingPathComponent("MacCam", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("activity.json")
        }
        load()
    }

    func record(_ event: ActivityEvent) {
        DispatchQueue.main.async {
            self.events.insert(event, at: 0)
            if self.events.count > self.maxEvents {
                self.events = Array(self.events.prefix(self.maxEvents))
            }
            self.persist()
        }
    }

    func recent(_ count: Int = 8) -> [ActivityEvent] {
        Array(events.prefix(count))
    }

    func clear() {
        events = []
        persist()
    }

    private func load() {
        queue.sync {
            guard let data = try? Data(contentsOf: fileURL),
                  let decoded = try? JSONDecoder().decode([ActivityEvent].self, from: data) else {
                return
            }
            DispatchQueue.main.async {
                self.events = decoded
            }
        }
    }

    private func persist() {
        let snapshot = events
        let url = fileURL
        queue.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}

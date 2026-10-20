import Darwin
import Foundation

struct EnumeratedProcess: Equatable {
    let pid: pid_t
    let name: String
}

enum ProcessEnumerator {
    /// All processes visible to this user (best-effort via libproc).
    static func allProcesses() -> [EnumeratedProcess] {
        let bytesNeeded = proc_listpids(PROC_ALL_PIDS, 0, nil, 0)
        guard bytesNeeded > 0 else { return [] }

        let count = Int(bytesNeeded) / MemoryLayout<pid_t>.size
        var pids = [pid_t](repeating: 0, count: count)
        let filled = proc_listpids(PROC_ALL_PIDS, 0, &pids, Int32(bytesNeeded))
        guard filled > 0 else { return [] }

        let actualCount = Int(filled) / MemoryLayout<pid_t>.size
        var results: [EnumeratedProcess] = []
        results.reserveCapacity(actualCount)

        for i in 0..<actualCount {
            let pid = pids[i]
            guard pid > 0, pid != getpid() else { continue }
            guard let name = processName(pid: pid), !name.isEmpty else { continue }
            results.append(EnumeratedProcess(pid: pid, name: name))
        }
        return results
    }

    static func processName(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 256)
        let len = proc_name(pid, &buffer, UInt32(buffer.count))
        guard len > 0 else { return nil }
        return String(cString: buffer)
    }
}

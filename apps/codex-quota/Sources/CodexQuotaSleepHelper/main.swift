import CodexQuotaCore
import Darwin
import Foundation

private enum Configuration {
    static let label = "local.openclaw.codexquota.sleephelper"
    static let root = "/Library/Application Support/CodexQuotaSleep"
    static let helper = root + "/CodexQuotaSleepHelper"
    static let daemon = "/Library/LaunchDaemons/" + label + ".plist"
    static let journal = root + "/active-lease"
    static let interval: TimeInterval = 2
}

private struct Journal {
    let uid: UInt32
    let restoreSleepDisabled: Bool

    init(uid: UInt32, restoreSleepDisabled: Bool) {
        self.uid = uid
        self.restoreSleepDisabled = restoreSleepDisabled
    }

    init?(_ data: Data) {
        guard
            data.count <= 32,
            let text = String(data: data, encoding: .utf8),
            let match = text.wholeMatch(of: /^(\d+)\n([01])\n$/),
            let uid = UInt32(match.1),
            let restore = Int(match.2)
        else { return nil }
        self.uid = uid
        restoreSleepDisabled = restore == 1
    }

    var data: Data {
        Data("\(uid)\n\(restoreSleepDisabled ? 1 : 0)\n".utf8)
    }
}

@main
struct CodexQuotaSleepHelper {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments == ["--run"] {
            guard geteuid() == 0 else { exit(EXIT_FAILURE) }
            let service = SleepLeaseService()
            service.evaluate()
            Timer.scheduledTimer(withTimeInterval: Configuration.interval, repeats: true) { _ in
                service.evaluate()
            }
            RunLoop.current.run()
        } else if arguments.count == 2, arguments[0] == "--install", let uidText = arguments.last {
            guard geteuid() == 0, let uid = UInt32(uidText), uid > 0 else { exit(EXIT_FAILURE) }
            do {
                try Installer.install(for: uid)
            } catch {
                fputs("CodexQuotaSleepHelper install failed: \(error)\n", stderr)
                exit(EXIT_FAILURE)
            }
        } else {
            fputs("Usage: CodexQuotaSleepHelper --install <uid> | --run\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}

private enum Installer {
    static func install(for uid: UInt32) throws {
        try makeDirectory(Configuration.root, owner: 0, mode: 0o755)
        let userDirectory = userDirectory(for: uid)
        try makeDirectory(userDirectory, owner: uid, mode: 0o700)

        let source = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        guard FileManager.default.isExecutableFile(atPath: source.path) else {
            throw HelperError.invalidSource
        }
        let destination = URL(fileURLWithPath: Configuration.helper)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
        try setOwnerAndMode(Configuration.helper, owner: 0, mode: 0o755)

        let plist: [String: Any] = [
            "Label": Configuration.label,
            "ProgramArguments": [Configuration.helper, "--run"],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Background"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: URL(fileURLWithPath: Configuration.daemon), options: .atomic)
        try setOwnerAndMode(Configuration.daemon, owner: 0, mode: 0o644)
        _ = try runFixed("/bin/launchctl", ["bootout", "system/\(Configuration.label)"], allowFailure: true)
        try runFixed("/bin/launchctl", ["bootstrap", "system", Configuration.daemon])
    }
}

private final class SleepLeaseService: @unchecked Sendable {
    private var isApplying = false

    func evaluate() {
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }

        do {
            guard try validRootDirectory() else { return }
            let journal = try readJournal()
            let leases = try liveLeases()
            switch TaskSleepLeasePolicy.decision(
                validLeases: leases,
                hasJournal: journal != nil
            ) {
            case .noChange:
                break
            case let .setSleepDisabled(active) where !leases.isEmpty:
                guard let lease = leases.max(by: { $0.scannedAt < $1.scannedAt }) else { return }
                if journal == nil {
                    try writeJournal(Journal(uid: lease.uid, restoreSleepDisabled: lease.restoreSleepDisabled))
                }
                // This is a system-wide setting. A newer monitoring lease from
                // another logged-in user must not turn sleep back on while any
                // valid lease still represents an active Codex task.
                let actual = try setSleepDisabled(active)
                for currentLease in leases {
                    try writeStatus(for: currentLease, active: active, sleepDisabled: actual, success: true)
                }
            case .setSleepDisabled(false):
                guard let journal else { return }
                _ = try setSleepDisabled(journal.restoreSleepDisabled)
                try FileManager.default.removeItem(atPath: Configuration.journal)
            case .setSleepDisabled(true):
                throw HelperError.commandFailed
            }
        } catch {
            fputs("CodexQuotaSleepHelper recovery error: \(error)\n", stderr)
        }
    }

    private func liveLeases() throws -> [TaskSleepLease] {
        let entries = try FileManager.default.contentsOfDirectory(atPath: Configuration.root)
        let now = Int64(Date().timeIntervalSince1970)
        var candidates: [TaskSleepLease] = []
        for entry in entries {
            guard
                let uidText = entry.wholeMatch(of: /^uid-(\d+)$/)?.1,
                let uid = UInt32(uidText),
                let lease = try readLease(for: uid),
                lease.uid == uid
            else { continue }
            candidates.append(lease)
        }
        return TaskSleepLeasePolicy.validatedLeases(candidates, now: now) {
            processIsAlive($0.ownerPID, ownedBy: $0.uid)
        }
    }

    private func readLease(for uid: UInt32) throws -> TaskSleepLease? {
        let directory = userDirectory(for: uid)
        guard try isSafeDirectory(directory, owner: uid, mode: 0o700) else { return nil }
        let path = directory + "/lease"
        guard let data = try secureRegularFile(path, owner: uid, maximumSize: 160) else { return nil }
        return TaskSleepLease.decode(data)
    }

    private func readJournal() throws -> Journal? {
        guard let data = try secureRegularFile(Configuration.journal, owner: 0, maximumSize: 32) else {
            return nil
        }
        return Journal(data)
    }

    private func writeJournal(_ journal: Journal) throws {
        let destination = URL(fileURLWithPath: Configuration.journal)
        try journal.data.write(to: destination, options: .atomic)
        try setOwnerAndMode(destination.path, owner: 0, mode: 0o600)
    }

    private func writeStatus(for lease: TaskSleepLease, active: Bool, sleepDisabled: Bool, success: Bool) throws {
        let path = Configuration.root + "/status-\(lease.uid)"
        let data = Data("1\n\(lease.ownerPID)\n\(lease.scannedAt)\n\(active ? 1 : 0)\n\(sleepDisabled ? 1 : 0)\n\(success ? 1 : 0)\n".utf8)
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        try setOwnerAndMode(path, owner: 0, mode: 0o644)
    }

    @discardableResult
    private func setSleepDisabled(_ value: Bool) throws -> Bool {
        let current = try currentSleepDisabled()
        if current != value {
            try runFixed("/usr/bin/pmset", ["-a", "disablesleep", value ? "1" : "0"])
        }
        let actual = try currentSleepDisabled()
        guard actual == value else { throw HelperError.commandFailed }
        return actual
    }

    private func currentSleepDisabled() throws -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "live"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw HelperError.commandFailed }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        if let match = text.wholeMatch(of: /(?s).*SleepDisabled\s+(\d+).*/), let value = Int(match.1) {
            return value != 0
        }
        // `SleepDisabled` is a hidden global override. pmset omits it from
        // `-g live` when no override is stored; absence therefore means the
        // normal/default state, equivalent to `disablesleep 0`.
        return false
    }
}

private enum HelperError: Error {
    case invalidSource
    case unsafePath
    case commandFailed
}

private func userDirectory(for uid: UInt32) -> String {
    Configuration.root + "/uid-\(uid)"
}

private func makeDirectory(_ path: String, owner: UInt32, mode: mode_t) throws {
    var info = stat()
    if lstat(path, &info) == 0 {
        guard (info.st_mode & S_IFMT) == S_IFDIR else { throw HelperError.unsafePath }
    } else {
        guard mkdir(path, mode) == 0 else { throw HelperError.unsafePath }
    }
    try setOwnerAndMode(path, owner: owner, mode: mode)
    guard try isSafeDirectory(path, owner: owner, mode: mode) else { throw HelperError.unsafePath }
}

private func setOwnerAndMode(_ path: String, owner: UInt32, mode: mode_t) throws {
    guard chown(path, owner, 0) == 0, chmod(path, mode) == 0 else { throw HelperError.unsafePath }
}

private func validRootDirectory() throws -> Bool {
    try isSafeDirectory(Configuration.root, owner: 0, mode: 0o755)
}

private func isSafeDirectory(_ path: String, owner: UInt32, mode: mode_t) throws -> Bool {
    var info = stat()
    guard lstat(path, &info) == 0 else { return false }
    return (info.st_mode & S_IFMT) == S_IFDIR
        && info.st_uid == owner
        && (info.st_mode & 0o777) == mode
}

private func secureRegularFile(
    _ path: String,
    owner: UInt32,
    maximumSize: Int
) throws -> Data? {
    let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    guard descriptor >= 0 else { return nil }
    defer { close(descriptor) }
    var info = stat()
    guard
        fstat(descriptor, &info) == 0,
        (info.st_mode & S_IFMT) == S_IFREG,
        info.st_uid == owner,
        (info.st_mode & 0o077) == 0,
        info.st_size >= 0,
        info.st_size <= maximumSize
    else { return nil }
    let count = Int(info.st_size)
    var bytes = [UInt8](repeating: 0, count: count)
    let readCount = bytes.withUnsafeMutableBytes { buffer in
        read(descriptor, buffer.baseAddress, count)
    }
    guard readCount == count else { return nil }
    return Data(bytes)
}

private func processIsAlive(_ pid: Int32, ownedBy uid: UInt32) -> Bool {
    guard kill(pid, 0) == 0 else { return false }
    var info = proc_bsdinfo()
    return proc_pidinfo(
        pid,
        PROC_PIDTBSDINFO,
        0,
        &info,
        Int32(MemoryLayout<proc_bsdinfo>.size)
    ) == MemoryLayout<proc_bsdinfo>.size && info.pbi_uid == uid
}

@discardableResult
private func runFixed(_ executable: String, _ arguments: [String], allowFailure: Bool = false) throws -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard allowFailure || process.terminationStatus == 0 else { throw HelperError.commandFailed }
    return process.terminationStatus
}

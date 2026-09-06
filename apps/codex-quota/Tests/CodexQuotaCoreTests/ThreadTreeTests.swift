import CodexQuotaCore
import Foundation

enum ThreadTreeTests {
    static let all: [TaskStatusParserTestCase] = [
        .init(name: "desktop thread tree keeps parent child relationship before group limit", run: relationshipAndLimit),
        .init(name: "desktop thread tree shows missing parent as its own group", run: missingParent),
        .init(name: "desktop thread tree groups missing-parent siblings together", run: missingParentSiblings),
        .init(name: "desktop thread tree breaks parent cycles", run: cycle),
        .init(name: "desktop thread tree hides cleared unknown rows but keeps running ancestors", run: hiddenUnknownWithRunningAncestor),
        .init(name: "desktop thread tree keeps ended parent of a running child clear-safe", run: runningChildKeepsParent),
        .init(name: "desktop thread group expansion defaults collapsed and persists", run: expansionPersistence),
        .init(name: "clear completed removes all eligible history beyond display limit", run: clearAllCompletedHistory),
        .init(name: "clear completed preserves unknown children and their parents", run: unknownChildKeepsParent)
    ]

    private static let now = Date(timeIntervalSince1970: 2_000_000_000)

    private static func thread(_ id: String, parent: String? = nil, offset: TimeInterval = 0, status: CodexDesktopThreadStatus = .ended) -> CodexDesktopThreadSnapshot {
        .init(id: id, parentThreadID: parent, title: id, source: .user, startedAt: now.addingTimeInterval(offset), lastActiveAt: now.addingTimeInterval(offset), status: status)
    }

    private static func relationshipAndLimit() -> Bool {
        let root = thread("root", offset: -100)
        let child = thread("child", parent: "root", status: .running)
        let others = (0..<9).map { thread("other-\($0)", offset: -Double($0 + 1)) }
        let groups = CodexDesktopThreadTree.groups(candidates: [root, child] + others, now: now)
        let rootGroup = groups.first { $0.root?.id == "root" }
        return groups.count == CodexDesktopSessionScanner.displayLimit
            && rootGroup?.root?.children.map(\.id) == ["child"]
    }

    private static func missingParent() -> Bool {
        let groups = CodexDesktopThreadTree.groups(candidates: [thread("child", parent: "missing", status: .running)], now: now)
        return groups.count == 1 && groups[0].missingParentID == "missing" && groups[0].orphanNodes.map(\.id) == ["child"]
    }

    private static func missingParentSiblings() -> Bool {
        let groups = CodexDesktopThreadTree.groups(candidates: [thread("a", parent: "missing"), thread("b", parent: "missing")], now: now)
        return groups.count == 1 && groups[0].id == "missing" && groups[0].orphanNodes.map(\.id) == ["a", "b"]
    }

    private static func cycle() -> Bool {
        let groups = CodexDesktopThreadTree.groups(candidates: [thread("a", parent: "b"), thread("b", parent: "a")], now: now)
        return groups.count == 1 && groups[0].root?.id == "a" && groups[0].root?.children.map(\.id) == ["b"]
    }

    private static func hiddenUnknownWithRunningAncestor() -> Bool {
        let parent = thread("parent", status: .running)
        let unknown = thread("unknown", parent: "parent", status: .unknown)
        let groups = CodexDesktopThreadTree.groups(candidates: [parent, unknown], now: now, hiddenIDs: ["unknown"])
        return groups.count == 1 && groups[0].root?.id == "parent" && groups[0].root?.children.isEmpty == true
    }

    private static func runningChildKeepsParent() -> Bool {
        let parent = thread("parent", status: .ended)
        let running = thread("running", parent: "parent", status: .running)
        let endedSibling = thread("ended", parent: "parent", status: .ended)
        let groups = CodexDesktopThreadTree.groups(candidates: [parent, running, endedSibling], now: now)
        return groups.first?.clearableThreadIDs == ["ended"]
    }

    private static func clearAllCompletedHistory() -> Bool {
        let completed = (0..<24).map { thread("completed-\($0)", offset: -Double($0)) }
        let pending = [thread("running", status: .running), thread("unknown", status: .unknown)]
        let all = completed + pending
        let ids = CodexDesktopThreadTree.clearableThreadIDs(in: all)
        let after = CodexDesktopThreadTree.groups(candidates: all, hiddenIDs: Set(ids))
        return Set(ids) == Set(completed.map(\.id))
            && Set(after.map(\.id)) == ["running", "unknown"]
            && CodexDesktopThreadTree.clearableThreadIDs(in: all, hiddenIDs: Set(ids)).isEmpty
    }

    private static func unknownChildKeepsParent() -> Bool {
        let all = [thread("parent"), thread("unknown", parent: "parent", status: .unknown), thread("done", parent: "parent")]
        return CodexDesktopThreadTree.clearableThreadIDs(in: all) == ["done"]
    }

    private static func expansionPersistence() -> Bool {
        let suite = "CodexQuota.ThreadTreeTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return false }
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TaskStatusStore(defaults: defaults)
        guard store.expandedDesktopThreadGroupIDs.isEmpty else { return false }
        store.expandedDesktopThreadGroupIDs = ["a", "b"]
        return TaskStatusStore(defaults: defaults).expandedDesktopThreadGroupIDs == ["a", "b"]
    }
}

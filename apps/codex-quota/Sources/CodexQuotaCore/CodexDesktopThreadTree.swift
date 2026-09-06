import Foundation

public struct CodexDesktopThreadNode: Equatable, Sendable, Identifiable {
    public let thread: CodexDesktopThreadSnapshot
    public let children: [CodexDesktopThreadNode]

    public var id: String { thread.id }

    public init(thread: CodexDesktopThreadSnapshot, children: [CodexDesktopThreadNode] = []) {
        self.thread = thread
        self.children = children
    }

    public var descendantCount: Int {
        children.reduce(0) { $0 + 1 + $1.descendantCount }
    }

    public var runningDescendantCount: Int {
        (thread.isRunning ? 1 : 0) + children.reduce(0) { $0 + $1.runningDescendantCount }
    }

    public var latestActiveAt: Date {
        children.reduce(thread.lastActiveAt) { max($0, $1.latestActiveAt) }
    }
}

public struct CodexDesktopThreadGroup: Equatable, Sendable, Identifiable {
    public let root: CodexDesktopThreadNode?
    public let orphanNodes: [CodexDesktopThreadNode]
    public let missingParentID: String?

    public var id: String { missingParentID ?? root!.id }
    public var isMissingParent: Bool { missingParentID != nil }
    public var descendantCount: Int { root?.descendantCount ?? orphanNodes.reduce(0) { $0 + 1 + $1.descendantCount } }
    public var runningCount: Int { root?.runningDescendantCount ?? orphanNodes.reduce(0) { $0 + $1.runningDescendantCount } }
    public var latestActiveAt: Date { (root.map(\.latestActiveAt) ?? orphanNodes.map(\.latestActiveAt).max())! }
    /// 仅隐藏明确结束的节点；有运行或未知状态后代的祖先保留。
    public var clearableThreadIDs: [String] {
        (root.map { [$0] } ?? orphanNodes).flatMap(\.clearableThreadIDs)
    }

    public init(root: CodexDesktopThreadNode) {
        self.root = root
        orphanNodes = []
        missingParentID = nil
    }

    public init(missingParentID: String, orphanNodes: [CodexDesktopThreadNode]) {
        root = nil
        self.orphanNodes = orphanNodes
        self.missingParentID = missingParentID
    }
}

private extension CodexDesktopThreadNode {
    var hasUnfinishedNode: Bool {
        thread.status != .ended || children.contains(where: \.hasUnfinishedNode)
    }

    var clearableThreadIDs: [String] {
        if thread.status != .ended || children.contains(where: \.hasUnfinishedNode) {
            return children.flatMap(\.clearableThreadIDs)
        }
        return [thread.id] + children.flatMap(\.clearableThreadIDs)
    }
}

public enum CodexDesktopThreadTree {
    public static func clearableThreadIDs(
        in candidates: [CodexDesktopThreadSnapshot],
        hiddenIDs: Set<String> = []
    ) -> [String] {
        groups(candidates: candidates, hiddenIDs: hiddenIDs, limit: candidates.count)
            .flatMap(\.clearableThreadIDs)
    }

    public static func groups(
        candidates: [CodexDesktopThreadSnapshot],
        now: Date = Date(),
        timeZone: TimeZone = .current,
        hiddenIDs: Set<String> = [],
        limit: Int = CodexDesktopSessionScanner.displayLimit
    ) -> [CodexDesktopThreadGroup] {
        let all = CodexDesktopSessionScanner.deduplicatedSnapshots(candidates)
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        let visibleIDs = Set(all.compactMap { snapshot -> String? in
            // unknown remains a distinct state; clearing only hides it from this list.
            if snapshot.status != .running && hiddenIDs.contains(snapshot.id) { return nil }
            return snapshot.id
        })
        var retained = visibleIDs
        for id in visibleIDs {
            var current = byID[id]?.parentThreadID
            var seen: Set<String> = [id]
            while let parentID = current, !seen.contains(parentID) {
                seen.insert(parentID)
                guard let parent = byID[parentID] else { break }
                retained.insert(parentID)
                current = parent.parentThreadID
            }
        }

        let retainedByID = byID.filter { retained.contains($0.key) }
        var parentByID = retainedByID.reduce(into: [String: String?]()) { result, item in
            result[item.key] = item.value.parentThreadID
        }
        breakCycles(&parentByID, knownIDs: Set(retainedByID.keys))
        var childrenByParent = [String: [String]]()
        var rootIDs: [String] = []
        var missingParentByRoot = [String: String]()
        for id in retainedByID.keys {
            if let parentID = parentByID[id] ?? nil, retainedByID[parentID] != nil {
                childrenByParent[parentID, default: []].append(id)
            } else {
                rootIDs.append(id)
                if let parentID = parentByID[id] ?? nil, byID[parentID] == nil {
                    missingParentByRoot[id] = parentID
                }
            }
        }
        func node(_ id: String) -> CodexDesktopThreadNode {
            let children = (childrenByParent[id] ?? []).sorted(by: sortIDs(byID)).map(node)
            return CodexDesktopThreadNode(thread: retainedByID[id]!, children: children)
        }
        let normalGroups = rootIDs.compactMap { id -> CodexDesktopThreadGroup? in
            guard missingParentByRoot[id] == nil else { return nil }
            return CodexDesktopThreadGroup(root: node(id))
        }
        let missingGroups = Dictionary(grouping: rootIDs.filter { missingParentByRoot[$0] != nil }) {
            missingParentByRoot[$0]!
        }.map { parentID, ids in
            CodexDesktopThreadGroup(missingParentID: parentID, orphanNodes: ids.sorted(by: sortIDs(byID)).map(node))
        }
        return (normalGroups + missingGroups)
        .sorted {
            if ($0.runningCount > 0) != ($1.runningCount > 0) { return $0.runningCount > 0 }
            if $0.latestActiveAt != $1.latestActiveAt { return $0.latestActiveAt > $1.latestActiveAt }
            return $0.id < $1.id
        }
        .prefix(max(0, limit))
        .map { $0 }
    }

    private static func sortIDs(
        _ byID: [String: CodexDesktopThreadSnapshot]
    ) -> (String, String) -> Bool {
        { left, right in
            let a = byID[left]!, b = byID[right]!
            if a.isRunning != b.isRunning { return a.isRunning }
            if a.lastActiveAt != b.lastActiveAt { return a.lastActiveAt > b.lastActiveAt }
            return left < right
        }
    }

    private static func breakCycles(
        _ parents: inout [String: String?],
        knownIDs: Set<String>
    ) {
        for start in parents.keys.sorted() {
            var path: [String] = []
            var index = [String: Int]()
            var current: String? = start
            while let id = current, knownIDs.contains(id) {
                if let cycleStart = index[id] {
                    let root = path[cycleStart...].min()!
                    parents[root] = nil
                    break
                }
                index[id] = path.count
                path.append(id)
                current = parents[id] ?? nil
            }
        }
    }
}

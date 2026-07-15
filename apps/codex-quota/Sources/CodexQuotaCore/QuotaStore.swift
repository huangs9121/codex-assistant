import Foundation

public struct QuotaStore: Sendable {
    private static let maximumFileCount = 50
    private static let initialBytesPerFile = 64 * 1024
    private static let maximumBytesPerFile = 4 * 1024 * 1024

    public init() {}

    public func latestSnapshot(in root: URL) -> QuotaSnapshot? {
        candidateFiles(in: root)
            .prefix(Self.maximumFileCount)
            .compactMap(latestSnapshotInFile(_:))
            .max { $0.observedAt < $1.observedAt }
    }

    private func candidateFiles(in root: URL) -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys)
        ) else {
            return []
        }

        var files: [(url: URL, modificationDate: Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard
                let values = try? url.resourceValues(forKeys: keys),
                values.isRegularFile == true
            else {
                continue
            }
            files.append((url, values.contentModificationDate ?? .distantPast))
        }

        return files
            .sorted {
                if $0.modificationDate != $1.modificationDate {
                    return $0.modificationDate > $1.modificationDate
                }
                return $0.url.standardizedFileURL.path
                    < $1.url.standardizedFileURL.path
            }
            .map(\.url)
    }

    private func latestSnapshotInFile(_ file: URL) -> QuotaSnapshot? {
        guard let handle = try? FileHandle(forReadingFrom: file) else {
            return nil
        }
        defer { try? handle.close() }

        do {
            let size = try handle.seekToEnd()
            guard size > 0 else {
                return nil
            }

            let limit = min(Int(size), Self.maximumBytesPerFile)
            var byteCount = min(Self.initialBytesPerFile, limit)
            while true {
                if
                    let contents = try tailContents(
                        from: handle,
                        fileSize: size,
                        byteCount: byteCount
                    ),
                    let snapshot = latestSnapshot(in: contents)
                {
                    return snapshot
                }

                guard byteCount < limit else {
                    return nil
                }
                byteCount = min(byteCount * 2, limit)
            }
        } catch {
            return nil
        }
    }

    private func latestSnapshot(in contents: String) -> QuotaSnapshot? {
        contents
            .split(whereSeparator: \Character.isNewline)
            .reversed()
            .lazy
            .compactMap { QuotaParser.snapshot(from: String($0)) }
            .first
    }

    private func tailContents(
        from handle: FileHandle,
        fileSize: UInt64,
        byteCount: Int
    ) throws -> String? {
        let offset = fileSize - UInt64(byteCount)
        var startsAtLineBoundary = offset == 0
        if offset > 0 {
            try handle.seek(toOffset: offset - 1)
            guard let previousByte = try handle.read(upToCount: 1), previousByte.count == 1 else {
                return nil
            }
            startsAtLineBoundary = previousByte[previousByte.startIndex] == 0x0A
        }

        try handle.seek(toOffset: offset)
        guard var data = try handle.read(upToCount: byteCount), data.count == byteCount else {
            return nil
        }

        if !startsAtLineBoundary {
            guard let firstNewline = data.firstIndex(of: 0x0A) else {
                return nil
            }
            data.removeSubrange(data.startIndex...firstNewline)
        }

        return String(data: data, encoding: .utf8)
    }
}

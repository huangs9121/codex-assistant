public enum QuotaRenderer {
    public static func title(remainingPercent: Int?) -> String {
        guard let remainingPercent else {
            return "Codex [░░░░░░░░░░] --%"
        }

        let percent = min(max(remainingPercent, 0), 100)
        let filledCount = min(max((percent + 5) / 10, 0), 10)
        let emptyCount = 10 - filledCount
        let bar = String(repeating: "█", count: filledCount)
            + String(repeating: "░", count: emptyCount)
        return "Codex [\(bar)] \(percent)%"
    }
}

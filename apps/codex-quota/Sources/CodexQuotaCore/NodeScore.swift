import Foundation

public struct NodeMetric: Codable, Sendable, Equatable {
    public var score: Double?
    public var detail: String
    public init(_ score: Double? = nil, _ detail: String = "未测") {
        self.score = score.map { min(10, max(0, $0)) }
        self.detail = detail
    }
}

public struct NodeScore: Codable, Identifiable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var date: Date = Date()
    public var metrics: [NodeMetric]
    public var source: String
    public var evidence: String
    public var version: Int
    public var downloadMB: Double?
    public var historicalTotal: Double?
    public var cancelled: Bool = false
    public static let labels = ["Codex / OpenAI", "CC / Anthropic", "ChatGPT 网页", "下载吞吐", "开发依赖下载", "YouTube 流畅度", "风控友好度"]
    // Keep the retired webpage slot for lossless decoding of existing records.
    public static let activeMetricIndices = [0, 1, 3, 4, 5, 6]
    public static let weights = [45.0, 10, 0, 15, 10, 5, 5]
    private var measuredWeight: Double { zip(metrics, Self.weights).reduce(0) { $0 + ($1.0.score == nil ? 0 : $1.1) } }
    public var coverage: Double { measuredWeight / Self.weights.reduce(0,+) }
    public var total: Double? {
        if version == 0 { return historicalTotal }
        guard metrics.count == 7, metrics[0].score != nil, coverage > 0, !cancelled else { return nil }
        return zip(metrics, Self.weights).reduce(0) { $0 + ($1.0.score ?? 0) * $1.1 } / measuredWeight
    }
    public init(name: String, metrics: [NodeMetric] = Array(repeating: NodeMetric(), count: 7), source: String = "本机实测", evidence: String = "", version: Int = 1) {
        self.name = name; self.metrics = metrics; self.source = source; self.evidence = evidence; self.version = version
    }
    public static func connectionScore(success: Int, count: Int, seconds: Double) -> Double {
        guard count > 0, seconds.isFinite else { return 0 }
        return Double(success) / Double(count) * max(1, min(10, 10 - max(0, seconds - 1) * 2))
    }
}

import CodexQuotaCore
import Foundation

@MainActor
final class CodexResetMonitorController {
    enum Result {
        case snapshot(CodexResetCache)
        case failure
    }

    private let session: URLSession
    private var retryAfter: Date?

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.urlCredentialStorage = nil
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: configuration)
        }
    }

    func check(cache: CodexResetCache?, completion: @escaping @MainActor (Result) -> Void) {
        guard retryAfter.map({ $0 <= Date() }) ?? true else {
            completion(.failure)
            return
        }
        var request = URLRequest(url: CodexResetFeed.apiURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexQuota", forHTTPHeaderField: "User-Agent")
        request.setValue(cache?.etag, forHTTPHeaderField: "If-None-Match")

        Task { [weak self] in
            guard let self else { return }
            do {
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else {
                    completion(.failure)
                    return
                }
                if response.statusCode == 429 || response.statusCode == 503 {
                    let delay = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                    retryAfter = Date().addingTimeInterval(max(delay ?? CodexResetFeed.pollInterval, CodexResetFeed.pollInterval))
                    completion(.failure)
                    return
                }
                if response.statusCode == 304, var cache, cache.etag != nil {
                    cache.receivedAt = Date()
                    retryAfter = nil
                    // A 304 must never advance the provider's checkedAt.
                    completion(.snapshot(cache))
                    return
                }
                guard response.statusCode == 200, !data.isEmpty, data.count <= 1_000_000 else {
                    completion(.failure)
                    return
                }
                let feed = try CodexResetFeed.decode(data)
                retryAfter = nil
                completion(.snapshot(CodexResetCache(
                    feed: feed,
                    etag: response.value(forHTTPHeaderField: "ETag"),
                    previous: cache
                )))
            } catch {
                completion(.failure)
            }
        }
    }

    func invalidate() { session.invalidateAndCancel() }
}

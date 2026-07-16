import CodexQuotaCore
import Foundation

@MainActor
final class TiboResetMonitorController {
    enum Result {
        case signal(TiboResetSignal?)
        case failure
    }

    private static let forecastURL = URL(
        string: "https://www.willcodexquotareset.com/api/forecast"
    )!
    private let session: URLSession

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 20
            self.session = URLSession(configuration: configuration)
        }
    }

    func check(completion: @escaping @MainActor (Result) -> Void) {
        var request = URLRequest(url: Self.forecastURL)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let (data, response) = try await session.data(for: request)
                guard
                    let response = response as? HTTPURLResponse,
                    response.statusCode == 200,
                    !data.isEmpty,
                    data.count <= 1_000_000
                else {
                    completion(.failure)
                    return
                }
                completion(.signal(try TiboResetSignal.latest(from: data)))
            } catch {
                completion(.failure)
            }
        }
    }

    func invalidate() {
        session.invalidateAndCancel()
    }
}

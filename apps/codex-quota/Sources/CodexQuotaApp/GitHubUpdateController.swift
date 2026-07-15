import CodexQuotaCore
import CodexQuotaUI
import Foundation

@MainActor
final class GitHubUpdateController {
    enum Result {
        case update(GitHubRelease)
        case current
        case failure(String)
    }

    private var preferences: DisplayPreferences
    private let session: URLSession

    init(defaults: UserDefaults = .standard, session: URLSession? = nil) {
        preferences = DisplayPreferences(defaults: defaults)
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            self.session = URLSession(configuration: configuration)
        }
    }

    func check(
        currentVersion: SemanticVersion,
        manual: Bool,
        completion: @escaping @MainActor (Result) -> Void
    ) {
        let now = Date()
        if !manual && !UpdatePolicy.shouldAutomaticallyCheck(
            lastSuccess: preferences.lastUpdateCheckSuccess,
            lastFailure: preferences.lastUpdateCheckFailure,
            now: now
        ) {
            return
        }
        guard let request = GitHubRelease.latestRequest() else {
            recordFailure(at: now)
            completion(.failure("无法创建更新检查请求"))
            return
        }

        Task { [weak self] in
            guard let self else {
                return
            }
            do {
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    recordFailure(at: Date())
                    completion(.failure("更新服务器响应无效"))
                    return
                }
                guard httpResponse.statusCode == 200 else {
                    recordFailure(at: Date())
                    completion(.failure("更新检查失败（HTTP \(httpResponse.statusCode)）"))
                    return
                }

                let release: GitHubRelease
                do {
                    release = try JSONDecoder().decode(GitHubRelease.self, from: data)
                } catch {
                    recordFailure(at: Date())
                    completion(.failure("更新信息格式无效"))
                    return
                }

                recordSuccess(at: Date())
                if let version = release.eligibleVersion, version > currentVersion {
                    completion(.update(release))
                } else {
                    completion(.current)
                }
            } catch {
                recordFailure(at: Date())
                completion(.failure("检查更新失败：\(error.localizedDescription)"))
            }
        }
    }

    func invalidate() {
        session.invalidateAndCancel()
    }

    private func recordSuccess(at date: Date) {
        preferences.lastUpdateCheckSuccess = date
        preferences.lastUpdateCheckFailure = nil
    }

    private func recordFailure(at date: Date) {
        preferences.lastUpdateCheckFailure = date
    }
}

import CodexQuotaCore
import CryptoKit
import Foundation
import LocalAuthentication
import Security

@MainActor
final class ClaudeUsageController {
    enum Source: Sendable { case oauth, oauthCache, desktopCache }
    enum Failure: Error, Sendable {
        case credentialsMissing
        case keychainPermission
        case keychainAuthentication
        case keychainWritePermission
        case credentialChanged
        case reauthenticationRequired
        case missingUsageScope
        case unauthorized
        case rateLimited
        case network
        case invalidResponse
        case httpStatus(Int)

        var isCredentialChange: Bool {
            if case .credentialChanged = self { return true }
            return false
        }
    }
    enum Result: Sendable {
        case snapshot(QuotaSnapshot, source: Source, stale: Bool, liveFailure: Failure?)
        case unavailable(Failure)
    }

    private static let staleAfter: TimeInterval = 30 * 60
    private var checking = false
    private var lastOAuth: (snapshot: QuotaSnapshot, fingerprint: Data)?
    private var cachedCredential: ClaudeOAuthUsageClient.Credential?
    private var backgroundKeychainFailure: Failure?
    private var automaticRetry: (after: Date, failure: Failure, fingerprint: Data?)?

    /// Background refreshes should pass false. Pass true only for an explicit user refresh,
    /// when a macOS Keychain authorization prompt can be shown and handled by the user.
    func check(
        allowKeychainPrompt: Bool = false,
        completion: @escaping @MainActor (Result) -> Void
    ) {
        guard !checking else { completion(.unavailable(.network)); return }
        checking = true
        if allowKeychainPrompt { backgroundKeychainFailure = nil }
        let retry = allowKeychainPrompt ? nil : automaticRetry
        let cachedCredential = allowKeychainPrompt ? nil : self.cachedCredential
        let keychainFailure = allowKeychainPrompt ? nil : backgroundKeychainFailure
        Task { @MainActor in
            let live: ClaudeOAuthUsageClient.Outcome
            let usedCooldown: Bool
            if let keychainFailure {
                usedCooldown = true
                live = .init(result: .failure(keychainFailure), fingerprint: nil,
                             previousFingerprint: nil)
            } else if let retry, retry.after > Date() {
                // A cooldown must not read the protected item on every timer tick.
                usedCooldown = true
                live = .init(result: .failure(retry.failure),
                             fingerprint: cachedCredential?.fingerprint ?? retry.fingerprint,
                             previousFingerprint: nil)
            } else {
                usedCooldown = false
                live = await Task.detached(priority: .utility) {
                    await ClaudeOAuthUsageClient.fetch(
                        allowKeychainPrompt: allowKeychainPrompt,
                        cachedCredential: cachedCredential
                    )
                }.value
            }
            if allowKeychainPrompt,
               let old = self.cachedCredential,
               let new = live.fingerprint,
               new != old.fingerprint {
                // A user refresh is the supported way to rebind to another account.
                lastOAuth = nil
            }
            let result: Result
            switch live.result {
            case .success(let snapshot):
                automaticRetry = nil
                self.cachedCredential = live.credential
                if let fingerprint = live.fingerprint {
                    lastOAuth = (snapshot, fingerprint)
                }
                result = .snapshot(snapshot, source: .oauth, stale: false, liveFailure: nil)
            case .failure(let failure):
                if case .keychainPermission = failure {
                    backgroundKeychainFailure = failure
                    self.cachedCredential = nil
                } else if case .keychainAuthentication = failure {
                    backgroundKeychainFailure = failure
                    self.cachedCredential = nil
                } else if case .keychainWritePermission = failure {
                    backgroundKeychainFailure = failure
                    self.cachedCredential = nil
                } else if failure.isCredentialChange {
                    self.cachedCredential = nil
                    lastOAuth = nil
                } else if let credential = live.credential {
                    self.cachedCredential = credential
                } else if !usedCooldown {
                    self.cachedCredential = nil
                }
                if !usedCooldown {
                    switch failure {
                    case .rateLimited:
                        automaticRetry = (Date().addingTimeInterval(15 * 60), failure, live.fingerprint)
                    case .reauthenticationRequired, .missingUsageScope, .unauthorized:
                        automaticRetry = (Date().addingTimeInterval(30 * 60), failure, live.fingerprint)
                    case .keychainPermission, .keychainAuthentication, .keychainWritePermission,
                         .credentialsMissing, .invalidResponse, .httpStatus:
                        automaticRetry = (Date().addingTimeInterval(5 * 60), failure, live.fingerprint)
                    case .network:
                        automaticRetry = (Date().addingTimeInterval(60), failure, live.fingerprint)
                    default:
                        automaticRetry = nil
                    }
                }
                if failure.isCredentialChange {
                    result = .unavailable(failure)
                } else if let previous = lastOAuth,
                   let fingerprint = live.fingerprint,
                   (fingerprint == previous.fingerprint
                       || live.previousFingerprint == previous.fingerprint),
                   Self.cacheIsCurrent(previous.snapshot, at: Date()) {
                    // A refresh can rotate the token while keeping the same account.
                    lastOAuth = (previous.snapshot, fingerprint)
                    result = .snapshot(
                        previous.snapshot,
                        source: .oauthCache,
                        stale: true,
                        liveFailure: failure
                    )
                } else {
                    let cached = await Task.detached(priority: .utility) {
                        ClaudeDesktopUsageStore.latestSnapshot()
                    }.value
                    if let cached {
                        let age = Date().timeIntervalSince(cached.observedAt)
                        result = .snapshot(
                            cached,
                            source: .desktopCache,
                            stale: age < 0 || age > Self.staleAfter,
                            liveFailure: failure
                        )
                    } else {
                        result = .unavailable(failure)
                    }
                }
            }
            checking = false
            completion(result)
        }
    }

    private static func cacheIsCurrent(_ snapshot: QuotaSnapshot, at now: Date) -> Bool {
        let resetDates = [snapshot.resetsAt, snapshot.secondaryWindow?.resetsAt]
            .compactMap { $0 }
        if resetDates.contains(where: { $0 <= now }) { return false }
        if resetDates.isEmpty {
            let age = now.timeIntervalSince(snapshot.observedAt)
            return age >= 0 && age <= staleAfter
        }
        return true
    }
}

private enum ClaudeDesktopUsageStore {
    static func latestSnapshot() -> QuotaSnapshot? {
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/plan-usage-history.json")
        guard
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
            values.isRegularFile == true,
            let size = values.fileSize,
            size > 0 && size <= 2 * 1_024 * 1_024,
            let data = try? Data(contentsOf: file)
        else { return nil }
        return ClaudeUsageParser.desktopHistorySnapshot(from: data)
    }
}

/// The Claude Code item uses the traditional file-based macOS Keychain. For
/// that implementation, LAContext and kSecUseAuthenticationUIFail alone do not
/// reliably suppress ACL prompts. Keep this process-wide switch scoped to one
/// synchronous SecItem call and restore its previous value before returning.
private enum ClaudeKeychainInteraction {
    private static let lock = NSLock()

    static func run<T>(
        stage: String,
        allowPrompt: Bool,
        _ operation: () -> T
    ) -> Swift.Result<T, ClaudeUsageController.Failure> {
        lock.lock()
        defer { lock.unlock() }
        if allowPrompt { return .success(operation()) }

        var wasAllowed = DarwinBoolean(false)
        let getStatus = SecKeychainGetUserInteractionAllowed(&wasAllowed)
        guard getStatus == errSecSuccess else {
            NSLog("ClaudeKeychain %@ Get status=%d", stage, getStatus)
            return .failure(.keychainPermission)
        }
        let setStatus = SecKeychainSetUserInteractionAllowed(false)
        guard setStatus == errSecSuccess else {
            NSLog("ClaudeKeychain %@ Set status=%d", stage, setStatus)
            return .failure(.keychainPermission)
        }
        let value = operation()
        let restoreStatus = SecKeychainSetUserInteractionAllowed(wasAllowed.boolValue)
        guard restoreStatus == errSecSuccess else {
            NSLog("ClaudeKeychain %@ Restore status=%d", stage, restoreStatus)
            return .failure(.keychainPermission)
        }
        return .success(value)
    }
}

private enum ClaudeOAuthUsageClient {
    private static let keychainService = "Claude Code-credentials"
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let refreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    // Claude Code's public OAuth client identifier, as used by CodexBar.
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    struct Credential: Sendable {
        let originalData: Data
        let account: String
        let modifiedAt: Date
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
        let scopes: [String]?
        let subscriptionType: String?
        let rateLimitTier: String?

        var fingerprint: Data {
            let ownerToken = refreshToken.flatMap { $0.isEmpty ? nil : $0 } ?? accessToken
            return Data(SHA256.hash(data: Data(ownerToken.utf8)))
        }
    }

    struct Outcome: Sendable {
        let result: Swift.Result<QuotaSnapshot, ClaudeUsageController.Failure>
        let fingerprint: Data?
        let previousFingerprint: Data?
        let credential: Credential?

        init(
            result: Swift.Result<QuotaSnapshot, ClaudeUsageController.Failure>,
            fingerprint: Data?,
            previousFingerprint: Data?,
            credential: Credential? = nil
        ) {
            self.result = result
            self.fingerprint = fingerprint
            self.previousFingerprint = previousFingerprint
            self.credential = credential
        }
    }

    private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            completionHandler(nil)
        }
    }

    private static func credentialStillCurrent(
        _ credential: Credential
    ) -> Swift.Result<Bool, ClaudeUsageController.Failure> {
        switch credentialMetadata() {
        case .success(let metadata):
            return .success(metadata.account == credential.account
                && metadata.modifiedAt == credential.modifiedAt)
        case .failure(let failure): return .failure(failure)
        }
    }

    private static func credentialMetadata()
    -> Swift.Result<(account: String, modifiedAt: Date), ClaudeUsageController.Failure> {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnAttributes as String: true,
            kSecUseAuthenticationContext as String: context,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
        let operation = ClaudeKeychainInteraction.run(stage: "attributes", allowPrompt: false) {
            var item: CFTypeRef?
            return (SecItemCopyMatching(query as CFDictionary, &item), item)
        }
        guard case .success(let (status, item)) = operation else {
            return .failure(.keychainPermission)
        }
        if status != errSecSuccess {
            NSLog("ClaudeKeychain attributes SecItemCopyMatching status=%d", status)
        }
        if status == errSecAuthFailed { return .failure(.keychainAuthentication) }
        guard status == errSecSuccess,
              let attributes = item as? [String: Any],
              let account = attributes[kSecAttrAccount as String] as? String,
              let modifiedAt = attributes[kSecAttrModificationDate as String] as? Date else {
            return .failure(status == errSecItemNotFound
                ? .credentialChanged : .keychainPermission)
        }
        return .success((account, modifiedAt))
    }

    static func fetch(
        allowKeychainPrompt: Bool,
        cachedCredential: Credential?
    ) async -> Outcome {
        var credential: Credential
        if let cachedCredential, !allowKeychainPrompt {
            switch credentialStillCurrent(cachedCredential) {
            case .success(true): credential = cachedCredential
            case .success(false):
                return Outcome(result: .failure(.credentialChanged), fingerprint: nil,
                               previousFingerprint: nil)
            case .failure(let failure):
                return Outcome(result: .failure(failure), fingerprint: nil,
                               previousFingerprint: nil)
            }
        } else {
            switch readCredential(allowKeychainPrompt: allowKeychainPrompt) {
            case .success(let value): credential = value
            case .failure(let failure):
                return Outcome(result: .failure(failure), fingerprint: nil,
                               previousFingerprint: nil)
            }
        }
        let originalFingerprint = credential.fingerprint
        if let scopes = credential.scopes, !scopes.isEmpty,
           !scopes.contains("user:profile") {
            return Outcome(
                result: .failure(.missingUsageScope),
                fingerprint: originalFingerprint,
                previousFingerprint: nil,
                credential: credential
            )
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        let session = URLSession(
            configuration: configuration,
            delegate: NoRedirectDelegate(),
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }
        var refreshed = false
        if credential.expiresAt.map({ $0 <= Date().addingTimeInterval(60) }) == true {
            switch await refresh(credential, session: session) {
            case .success(let value): credential = value; refreshed = true
            case .failure(let failure):
                // The write preflight may change modificationDate. Do not bind
                // an old token to a later item by comparing the account alone.
                return Outcome(
                    result: .failure(failure),
                    fingerprint: failure.isCredentialChange ? nil : originalFingerprint,
                    previousFingerprint: nil,
                    credential: nil
                )
            }
        }
        let first = await usage(credential: credential, session: session)
        if case .failure(.unauthorized) = first, !refreshed {
            switch await refresh(credential, session: session) {
            case .success(let value):
                let result = await usage(credential: value, session: session)
                return Outcome(
                    result: result,
                    fingerprint: value.fingerprint,
                    previousFingerprint: originalFingerprint,
                    credential: value
                )
            case .failure(let failure):
                return Outcome(
                    result: .failure(failure),
                    fingerprint: failure.isCredentialChange ? nil : originalFingerprint,
                    previousFingerprint: nil,
                    credential: nil
                )
            }
        }
        return Outcome(
            result: first,
            fingerprint: credential.fingerprint,
            previousFingerprint: refreshed ? originalFingerprint : nil,
            credential: credential
        )
    }

    private static func usage(
        credential: Credential,
        session: URLSession
    ) async -> Swift.Result<QuotaSnapshot, ClaudeUsageController.Failure> {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CodexQuota/ClaudeUsage", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.url?.scheme == "https",
                  http.url?.host == "api.anthropic.com" else {
                return .failure(.invalidResponse)
            }
            switch http.statusCode {
            case 200:
                guard let snapshot = ClaudeUsageParser.oauthSnapshot(
                    from: data,
                    subscriptionType: credential.subscriptionType,
                    rateLimitTier: credential.rateLimitTier
                ) else {
                    return .failure(.invalidResponse)
                }
                return .success(snapshot)
            case 401, 403: return .failure(.unauthorized)
            case 429: return .failure(.rateLimited)
            default: return .failure(.httpStatus(http.statusCode))
            }
        } catch {
            // Never log a request or server body: both can include sensitive credentials.
            return .failure(.network)
        }
    }

    private static func refresh(
        _ original: Credential,
        session: URLSession
    ) async -> Swift.Result<Credential, ClaudeUsageController.Failure> {
        guard let refreshToken = original.refreshToken, !refreshToken.isEmpty else {
            return .failure(.reauthenticationRequired)
        }
        // Check write permission before asking Anthropic to rotate the refresh token.
        // Even an explicit refresh allows only the initial credential read to
        // request authorization. A missing write ACL must fail before rotation.
        switch writeCredential(original.originalData, replacing: original) {
        case .success: break
        case .failure(let failure): return .failure(failure)
        }

        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = formBody([
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", clientID)
        ])
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  http.url?.scheme == "https",
                  http.url?.host == "platform.claude.com" else {
                return .failure(.invalidResponse)
            }
            switch http.statusCode {
            case 200: break
            case 400:
                let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                let errorCode = payload?["error"] as? String
                return .failure(errorCode == "invalid_grant"
                    ? .reauthenticationRequired : .invalidResponse)
            case 401, 403: return .failure(.reauthenticationRequired)
            case 429: return .failure(.rateLimited)
            default: return .failure(.httpStatus(http.statusCode))
            }
            guard
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let accessToken = object["access_token"] as? String,
                !accessToken.isEmpty,
                let seconds = object["expires_in"] as? NSNumber,
                CFGetTypeID(seconds) != CFBooleanGetTypeID(),
                (1...604_800).contains(seconds.doubleValue)
            else { return .failure(.invalidResponse) }
            let nextRefresh = (object["refresh_token"] as? String)
                .flatMap { $0.isEmpty ? nil : $0 } ?? refreshToken
            let expiry = Date().addingTimeInterval(seconds.doubleValue)
            guard let updated = ClaudeUsageParser.refreshedCredentialData(
                from: original.originalData,
                accessToken: accessToken,
                refreshToken: nextRefresh,
                expiresAt: expiry
            ) else {
                return .failure(.invalidResponse)
            }
            switch writeCredential(updated, replacing: original) {
            case .success:
                let metadataResult = credentialMetadata()
                if case .failure(.keychainAuthentication) = metadataResult {
                    return .failure(.keychainAuthentication)
                }
                guard case .success(let metadata) = metadataResult,
                      metadata.account == original.account else {
                    return .failure(.keychainPermission)
                }
                return .success(Credential(
                    originalData: updated,
                    account: original.account,
                    modifiedAt: metadata.modifiedAt,
                    accessToken: accessToken,
                    refreshToken: nextRefresh,
                    expiresAt: expiry,
                    scopes: original.scopes,
                    subscriptionType: original.subscriptionType,
                    rateLimitTier: original.rateLimitTier
                ))
            case .failure(let failure): return .failure(failure)
            }
        } catch {
            return .failure(.network)
        }
    }

    private static func readCredential(
        allowKeychainPrompt: Bool
    ) -> Swift.Result<Credential, ClaudeUsageController.Failure> {
        let context = LAContext()
        context.interactionNotAllowed = !allowKeychainPrompt
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecUseAuthenticationContext as String: context
        ]
        if !allowKeychainPrompt {
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }
        let operation = ClaudeKeychainInteraction.run(
            stage: "read", allowPrompt: allowKeychainPrompt
        ) {
            var item: CFTypeRef?
            return (SecItemCopyMatching(query as CFDictionary, &item), item)
        }
        guard case .success(let (status, item)) = operation else {
            return .failure(.keychainPermission)
        }
        if status != errSecSuccess {
            NSLog("ClaudeKeychain read SecItemCopyMatching status=%d", status)
        }
        switch status {
        case errSecSuccess: break
        case errSecItemNotFound: return .failure(.credentialsMissing)
        case errSecAuthFailed: return .failure(.keychainAuthentication)
        case errSecInteractionNotAllowed, errSecUserCanceled:
            return .failure(.keychainPermission)
        default: return .failure(.keychainPermission)
        }
        guard
            let attributes = item as? [String: Any],
            let data = attributes[kSecValueData as String] as? Data,
            let account = attributes[kSecAttrAccount as String] as? String,
            let modifiedAt = attributes[kSecAttrModificationDate as String] as? Date,
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String,
            !token.isEmpty
        else { return .failure(.credentialsMissing) }
        let expiry = oauth["expiresAt"] as? NSNumber
        let date = expiry.flatMap {
            CFGetTypeID($0) == CFBooleanGetTypeID() || !$0.doubleValue.isFinite
                ? nil : Date(timeIntervalSince1970: $0.doubleValue / 1_000)
        }
        return .success(Credential(
            originalData: data,
            account: account,
            modifiedAt: modifiedAt,
            accessToken: token,
            refreshToken: oauth["refreshToken"] as? String,
            expiresAt: date,
            scopes: oauth["scopes"] as? [String],
            subscriptionType: oauth["subscriptionType"] as? String,
            rateLimitTier: oauth["rateLimitTier"] as? String
        ))
    }

    private static func writeCredential(
        _ data: Data,
        replacing original: Credential
    ) -> Swift.Result<Void, ClaudeUsageController.Failure> {
        switch readCredential(allowKeychainPrompt: false) {
        case .success(let current) where current.account == original.account
            && current.originalData == original.originalData: break
        case .success: return .failure(.credentialChanged)
        case .failure(.credentialsMissing): return .failure(.credentialChanged)
        case .failure(.keychainAuthentication): return .failure(.keychainAuthentication)
        case .failure(let failure):
            return .failure(failure.isCredentialChange
                ? .credentialChanged : .keychainWritePermission)
        }
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: original.account,
            kSecUseAuthenticationContext as String: context,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail
        ]
        let operation = ClaudeKeychainInteraction.run(stage: "write", allowPrompt: false) {
            SecItemUpdate(query as CFDictionary, [
                kSecValueData as String: data
            ] as CFDictionary)
        }
        guard case .success(let status) = operation else {
            return .failure(.keychainWritePermission)
        }
        if status != errSecSuccess {
            NSLog("ClaudeKeychain write SecItemUpdate status=%d", status)
        }
        return status == errSecSuccess ? .success(()) : .failure(.keychainWritePermission)
    }

    private static func formBody(_ items: [(String, String)]) -> Data {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return Data(items.map { name, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(name)=\(encoded)"
        }.joined(separator: "&").utf8)
    }
}

import CodexQuotaCore
import Foundation

@MainActor
final class CodexRateLimitController {
    enum Result {
        case snapshot(QuotaSnapshot)
        case failure(Failure)
    }

    enum Failure: Equatable {
        case cliMissing
        case launchFailed
        case exited
        case timedOut
        case busy
        case serverError(String)
        case unreadable

        /// Shown in the quota line's help so a failed read explains itself.
        var message: String {
            switch self {
            case .cliMissing: "未找到 Codex 命令行（ChatGPT 或 Codex 应用内）"
            case .launchFailed: "无法启动 Codex 命令行"
            case .exited: "Codex 命令行意外退出"
            case .timedOut: "Codex 在 8 秒内没有返回额度"
            case .busy: "上一次读取尚未结束"
            case let .serverError(message): "Codex 返回错误：\(message)"
            case .unreadable: "返回的额度数据无法识别"
            }
        }
    }

    private static let initializeRequestID = 1
    private static let responseTimeout: TimeInterval = 8

    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputHandle: FileHandle?
    private var errorHandle: FileHandle?
    private var outputBuffer = Data()
    private var initialized = false
    private var nextRequestID = 2
    private var waitingForInitialization: (@MainActor (Result) -> Void)?
    private var initializationTimeout: DispatchWorkItem?
    private var pendingRequest: (
        id: Int,
        completion: @MainActor (Result) -> Void,
        timeout: DispatchWorkItem
    )?
    private var invalidated = false

    func check(completion: @escaping @MainActor (Result) -> Void) {
        guard !invalidated else {
            completion(.failure(.launchFailed))
            return
        }
        guard waitingForInitialization == nil, pendingRequest == nil else {
            completion(.failure(.busy))
            return
        }

        if initialized, process?.isRunning == true {
            requestRateLimits(completion: completion)
            return
        }

        waitingForInitialization = completion
        if let failure = startServer() {
            finishInitialization(with: .failure(failure))
            return
        }
        let timeout = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard self?.waitingForInitialization != nil else {
                    return
                }
                self?.finishInitialization(with: .failure(.timedOut))
                self?.stopServer()
            }
        }
        initializationTimeout = timeout
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.responseTimeout,
            execute: timeout
        )
        send([
            "id": Self.initializeRequestID,
            "method": "initialize",
            "params": [
                "clientInfo": [
                    "name": "codex-quota",
                    "version": appVersion
                ],
                "capabilities": ["experimentalApi": true]
            ]
        ])
    }

    func invalidate() {
        invalidated = true
        waitingForInitialization = nil
        initializationTimeout?.cancel()
        initializationTimeout = nil
        pendingRequest?.timeout.cancel()
        pendingRequest = nil
        stopServer()
    }

    private var appVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "unknown"
    }

    private func startServer() -> Failure? {
        stopServer()
        guard let executable = codexExecutable() else {
            return .cliMissing
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let outputHandle = outputPipe.fileHandleForReading
        outputHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { @MainActor [weak self] in
                self?.consume(data)
            }
        }
        let errorHandle = errorPipe.fileHandleForReading
        errorHandle.readabilityHandler = { handle in
            _ = handle.availableData
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.serverTerminated()
            }
        }

        do {
            try process.run()
        } catch {
            outputHandle.readabilityHandler = nil
            errorHandle.readabilityHandler = nil
            return .launchFailed
        }

        self.process = process
        inputHandle = inputPipe.fileHandleForWriting
        self.outputHandle = outputHandle
        self.errorHandle = errorHandle
        outputBuffer.removeAll(keepingCapacity: true)
        initialized = false
        return nil
    }

    private func requestRateLimits(
        completion: @escaping @MainActor (Result) -> Void
    ) {
        let requestID = nextRequestID
        nextRequestID += 1
        let timeout = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.requestTimedOut(id: requestID)
            }
        }
        pendingRequest = (requestID, completion, timeout)
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.responseTimeout,
            execute: timeout
        )
        send([
            "id": requestID,
            "method": "account/rateLimits/read"
        ])
    }

    private func send(_ object: [String: Any]) {
        guard
            JSONSerialization.isValidJSONObject(object),
            var data = try? JSONSerialization.data(withJSONObject: object)
        else {
            failAllRequests(with: .launchFailed)
            return
        }
        data.append(0x0A)
        do {
            try inputHandle?.write(contentsOf: data)
        } catch {
            failAllRequests(with: .exited)
            stopServer()
        }
    }

    private func consume(_ data: Data) {
        guard !data.isEmpty else {
            return
        }
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = Data(outputBuffer[..<newline])
            outputBuffer.removeSubrange(...newline)
            consumeLine(line)
        }
    }

    private func consumeLine(_ data: Data) {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let responseID = root["id"] as? NSNumber,
            CFGetTypeID(responseID) != CFBooleanGetTypeID()
        else {
            return
        }

        if responseID.intValue == Self.initializeRequestID {
            initializationTimeout?.cancel()
            initializationTimeout = nil
            guard root["result"] != nil else {
                finishInitialization(with: .failure(Self.failure(in: root)))
                stopServer()
                return
            }
            initialized = true
            guard let completion = waitingForInitialization else {
                return
            }
            waitingForInitialization = nil
            requestRateLimits(completion: completion)
            return
        }

        guard
            let request = pendingRequest,
            responseID.intValue == request.id
        else {
            return
        }
        request.timeout.cancel()
        pendingRequest = nil
        if let snapshot = AccountRateLimitsParser.snapshot(from: data) {
            request.completion(.snapshot(snapshot))
        } else {
            // Start from a fresh server next time in case this one has gone bad.
            stopServer()
            request.completion(.failure(Self.failure(in: root)))
        }
    }

    private static func failure(in root: [String: Any]) -> Failure {
        guard let error = root["error"] as? [String: Any] else {
            return .unreadable
        }
        let message = (error["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return .serverError(message.isEmpty ? "未知错误" : String(message.prefix(160)))
    }

    private func requestTimedOut(id: Int) {
        guard let request = pendingRequest, request.id == id else {
            return
        }
        pendingRequest = nil
        request.completion(.failure(.timedOut))
        stopServer()
    }

    private func finishInitialization(with result: Result) {
        initializationTimeout?.cancel()
        initializationTimeout = nil
        guard let completion = waitingForInitialization else {
            return
        }
        waitingForInitialization = nil
        completion(result)
    }

    private func failAllRequests(with failure: Failure) {
        finishInitialization(with: .failure(failure))
        guard let request = pendingRequest else {
            return
        }
        request.timeout.cancel()
        pendingRequest = nil
        request.completion(.failure(failure))
    }

    private func serverTerminated() {
        guard process != nil else {
            return
        }
        failAllRequests(with: .exited)
        stopServer(terminate: false)
    }

    private func stopServer(terminate: Bool = true) {
        let process = process
        self.process = nil
        initialized = false
        outputHandle?.readabilityHandler = nil
        errorHandle?.readabilityHandler = nil
        outputHandle = nil
        errorHandle = nil
        try? inputHandle?.close()
        inputHandle = nil
        outputBuffer.removeAll(keepingCapacity: true)
        initializationTimeout?.cancel()
        initializationTimeout = nil
        process?.terminationHandler = nil
        if terminate, process?.isRunning == true {
            process?.terminate()
        }
    }

    private func codexExecutable() -> URL? {
        var candidates: [URL] = []
        if let override = ProcessInfo.processInfo.environment["CODEX_QUOTA_CODEX_PATH"] {
            candidates.append(URL(fileURLWithPath: override))
        }
        candidates += [
            // ChatGPT 26.924 moved the CLI into a nested app; its bin/codex wrapper only execs this.
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"),
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex"),
            URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources/codex"),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/codex"),
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex")
        ]
        return candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }
    }
}

import CodexQuotaCore
import Foundation

@MainActor
final class CodexRateLimitController {
    enum Result {
        case snapshot(QuotaSnapshot)
        case failure
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
            completion(.failure)
            return
        }
        guard waitingForInitialization == nil, pendingRequest == nil else {
            completion(.failure)
            return
        }

        if initialized, process?.isRunning == true {
            requestRateLimits(completion: completion)
            return
        }

        waitingForInitialization = completion
        guard startServer() else {
            finishInitialization(with: .failure)
            return
        }
        let timeout = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard self?.waitingForInitialization != nil else {
                    return
                }
                self?.finishInitialization(with: .failure)
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

    private func startServer() -> Bool {
        stopServer()
        guard let executable = codexExecutable() else {
            return false
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
            return false
        }

        self.process = process
        inputHandle = inputPipe.fileHandleForWriting
        self.outputHandle = outputHandle
        self.errorHandle = errorHandle
        outputBuffer.removeAll(keepingCapacity: true)
        initialized = false
        return true
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
            failAllRequests()
            return
        }
        data.append(0x0A)
        do {
            try inputHandle?.write(contentsOf: data)
        } catch {
            failAllRequests()
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
                finishInitialization(with: .failure)
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
            request.completion(.failure)
        }
    }

    private func requestTimedOut(id: Int) {
        guard let request = pendingRequest, request.id == id else {
            return
        }
        pendingRequest = nil
        request.completion(.failure)
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

    private func failAllRequests() {
        finishInitialization(with: .failure)
        guard let request = pendingRequest else {
            return
        }
        request.timeout.cancel()
        pendingRequest = nil
        request.completion(.failure)
    }

    private func serverTerminated() {
        guard process != nil else {
            return
        }
        failAllRequests()
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

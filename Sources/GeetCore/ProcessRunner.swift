import Foundation
import Darwin

public enum ResolvePriority: Int, Sendable { case background = 0, foreground = 1 }

/// One process lane for version probes, imports, stream resolves, and look-ahead.
/// Foreground demand terminates speculative work, and waits for its exit before starting.
public actor ProcessRunner {
    struct Job {
        let id: UUID
        let executable: URL
        let arguments: [String]
        let priority: ResolvePriority
        let continuation: CheckedContinuation<Data, Error>
    }
    private var waiting: [Job] = []
    private var active: (job: Job, operation: ProcessOperation)?
    public private(set) var starts = 0
    public init() {}

    public func run(_ executable: URL, arguments: [String], priority: ResolvePriority = .foreground) async throws -> Data {
        let id = UUID()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                waiting.append(Job(id: id, executable: executable, arguments: arguments, priority: priority, continuation: continuation))
                waiting.sort { $0.priority.rawValue > $1.priority.rawValue }
                if priority == .foreground, active?.job.priority == .background { active?.operation.cancel() }
                startNext()
            }
        }, onCancel: { Task { await self.cancel(id) } })
    }

    public func cancelBackground() {
        let cancelled = waiting.filter { $0.priority == .background }
        waiting.removeAll { $0.priority == .background }
        cancelled.forEach { $0.continuation.resume(throwing: CancellationError()) }
        if active?.job.priority == .background { active?.operation.cancel() }
    }

    private func cancel(_ id: UUID) {
        if let index = waiting.firstIndex(where: { $0.id == id }) {
            waiting.remove(at: index).continuation.resume(throwing: CancellationError())
        } else if active?.job.id == id { active?.operation.cancel() }
    }

    private func startNext() {
        guard active == nil, !waiting.isEmpty else { return }
        let job = waiting.removeFirst(), operation = ProcessOperation()
        active = (job, operation); starts += 1
        Task.detached(priority: job.priority == .foreground ? .userInitiated : .utility) {
            let result: Result<Data, Error>
            do { result = .success(try await operation.execute(job.executable, arguments: job.arguments, priority: job.priority)) }
            catch { result = .failure(error) }
            await self.finish(job.id, result: result)
        }
    }

    private func finish(_ id: UUID, result: Result<Data, Error>) {
        guard let current = active, current.job.id == id else { return }
        active = nil
        current.job.continuation.resume(with: result)
        startNext()
    }
}

private final class ProcessOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timedOut = false

    func cancel(timeout: Bool = false) {
        lock.lock(); cancelled = true; timedOut = timedOut || timeout
        let running = process; lock.unlock()
        if let running, running.isRunning {
            running.terminate()
            // Only exists for an active process; never an idle polling loop.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                if running.isRunning { Darwin.kill(running.processIdentifier, SIGKILL) }
            }
        }
    }

    func execute(_ executable: URL, arguments: [String], priority: ResolvePriority) async throws -> Data {
        let process = Process(), output = Pipe(), error = Pipe()
        process.executableURL = executable; process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.qualityOfService = priority == .background ? .utility : .userInitiated
        process.standardOutput = output; process.standardError = error
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(executable.deletingLastPathComponent().path):/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = environment
        let exit = ProcessExit()
        process.terminationHandler = { _ in Task { await exit.finish() } }
        try launch(process)
        let deadline = Task { try? await Task.sleep(for: .seconds(60)); if !Task.isCancelled { self.cancel(timeout: true) } }
        defer { deadline.cancel() }
        let stdout = Task.detached(priority: .utility) { try self.read(output.fileHandleForReading, maximum: 16 * 1024 * 1024) }
        let stderr = Task.detached(priority: .utility) { try self.read(error.fileHandleForReading, maximum: 256 * 1024) }
        // Install before launch so even a helper that exits immediately is observed.
        // This avoids a blocking Foundation run loop on a cooperative executor.
        await exit.wait()
        process.terminationHandler = nil
        let bytes = try await stdout.value, errors = try await stderr.value
        let state = cancellationState()
        if state.1 { throw GeetError.message("YouTube took too long to respond. Try again in a moment.") }
        if state.0 { throw CancellationError() }
        guard process.terminationStatus == 0 else {
            let lines = String(decoding: errors, as: UTF8.self).split(separator: "\n")
            let message = lines.last(where: { $0.contains("ERROR:") }).map(String.init) ?? "This link couldn’t be opened. Check that it’s public or unlisted."
            throw GeetError.message(String(message.prefix(350)))
        }
        return bytes
    }

    private func launch(_ newProcess: Process) throws {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled else { throw CancellationError() }
        process = newProcess; try newProcess.run()
    }
    private func cancellationState() -> (Bool, Bool) { lock.lock(); defer { lock.unlock() }; return (cancelled, timedOut) }
    private func read(_ handle: FileHandle, maximum: Int) throws -> Data {
        defer { try? handle.close() }
        var data = Data()
        while let part = try handle.read(upToCount: 65_536), !part.isEmpty {
            guard data.count + part.count <= maximum else { cancel(); throw GeetError.message("That playlist is too large to import safely.") }
            data.append(part)
        }
        return data
    }
}

private actor ProcessExit {
    private var finished = false
    private var waiter: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            if finished { continuation.resume() } else { waiter = continuation }
        }
    }
    func finish() { finished = true; waiter?.resume(); waiter = nil }
}

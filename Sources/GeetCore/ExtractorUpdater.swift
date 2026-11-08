import CryptoKit
import Foundation

/// Only official stable macOS executables are accepted. The digest is supplied
/// by GitHub's HTTPS release API, independently of the downloaded asset.
public actor ExtractorUpdater {
    typealias Transport = @Sendable (URL, Int) async throws -> Data
    typealias Validate = @Sendable (URL, String) async throws -> Void
    static let endpoint = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!
    static let maximumAssetBytes = 96 * 1024 * 1024
    struct Install: Codable, Equatable {
        var directory: String
        var version: String
        var sha256: String
        var executableSHA256: String
    }
    private struct State: Codable {
        var current: Install?
        var previous: Install?
        var currentWorked = false
        var rejected: [String] = []
        var attempted: Date?
        var succeeded = false
        var failure: ExtractorSetupFailure?
    }
    private struct Release: Decodable {
        struct Asset: Decodable {
            var name: String
            var size: Int
            var digest: String?
            var browser_download_url: String
        }
        var tag_name: String
        var draft: Bool
        var prerelease: Bool
        var assets: [Asset]
    }
    enum UpdateError: Error, Equatable { case invalidRelease, invalidDownload, checksumMismatch, versionMismatch }
    private let root: URL
    private let transport: Transport
    private let validate: Validate
    private var state: State
    private var task: Task<Bool, Error>?
    private var cleaned = false
    private var verified: [InstallKey: Date] = [:]
    private struct InstallKey: Hashable { var directory: String; var size: Int; var digest: String }

    public init(root: URL) {
        self.init(root: root, transport: { try await Self.download($0, maximumBytes: $1) }, validate: { executable, version in
            let output = try await ProcessRunner().run(executable, arguments: ["--ignore-config", "--no-update", "--version"])
            guard String(decoding: output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == version else {
                throw UpdateError.versionMismatch
            }
        })
    }

    init(root: URL, transport: @escaping Transport, validate: @escaping Validate) {
        self.root = root.appendingPathComponent("ExtractorUpdates", isDirectory: true)
        self.transport = transport; self.validate = validate
        state = Paths.read(State.self, from: self.root.appendingPathComponent("state.json")) ?? State()
        // Construction does not start downloads or helpers.
    }

    public func executable() -> URL? {
        if let current = state.current, let url = verifiedExecutable(current) { return url }
        // Corruption or a missing active file must not make the previous copy unusable.
        if let previous = state.previous, let url = verifiedExecutable(previous) { return url }
        return nil
    }
    public func setupFailure() -> ExtractorSetupFailure? { state.failure }

    /// Calls share a single download, including a first playback arriving during launch.
    @discardableResult public func refresh(force: Bool = false, now: Date = Date()) async throws -> Bool {
        if let task { return try await task.value }
        cleanUnusedInstalls()
        if !force, (state.failure != nil || executable() != nil), let attempted = state.attempted,
           (0..<(state.succeeded ? 86_400.0 : 3_600.0)).contains(now.timeIntervalSince(attempted)) {
            if let failure = state.failure { throw failure }
            return false
        }
        state.attempted = now; state.succeeded = false; state.failure = nil
        do { try persist() }
        catch {
            let failure = ExtractorSetupFailure.classify(error)
            state.failure = failure
            throw failure
        }
        let task = Task {
            do { return try await self.installLatest() }
            catch { throw ExtractorSetupFailure.classify(error) }
        }
        self.task = task
        defer { self.task = nil }
        do {
            let changed = try await task.value
            state.succeeded = true; state.failure = nil; try persist()
            return changed
        } catch {
            let failure = ExtractorSetupFailure.classify(error)
            state.failure = failure; state.succeeded = false
            try? persist()
            throw failure
        }
    }

    /// Only retire an update after its predecessor successfully handles the same
    /// request. A private video or network outage must not blacklist a release.
    public func fallback(after failing: URL) -> URL? {
        guard let current = state.current, url(for: current) == failing,
              let previous = state.previous else { return nil }
        return verifiedExecutable(previous)
    }

    public func acceptFallback(after failing: URL) throws {
        guard let current = state.current, url(for: current) == failing,
              let previous = state.previous, verifiedExecutable(previous) != nil else { return }
        var next = state
        next.rejected = Array((next.rejected + [current.version]).suffix(16))
        next.current = previous; next.previous = nil
        next.currentWorked = true
        try Paths.write(next, to: root.appendingPathComponent("state.json"))
        state = next
    }

    public func recordSuccess(_ executable: URL) throws {
        guard !state.currentWorked, let current = state.current, url(for: current) == executable else { return }
        var next = state
        next.currentWorked = true
        try Paths.write(next, to: root.appendingPathComponent("state.json"))
        state = next
    }

    private func installLatest() async throws -> Bool {
        let metadata = try await transport(Self.endpoint, 1024 * 1024)
        guard metadata.count <= 1024 * 1024 else { throw UpdateError.invalidRelease }
        let release = try JSONDecoder().decode(Release.self, from: metadata)
        let version = release.tag_name
        guard !release.draft, !release.prerelease, Self.validVersion(version) else { throw UpdateError.invalidRelease }
        if state.rejected.contains(version) { return false }
        if let current = state.current, verifiedExecutable(current) != nil,
           version.compare(current.version, options: .numeric) != .orderedDescending { return false }
        let assets = release.assets.filter { $0.name == "yt-dlp_macos.zip" }
        let expectedURL = "https://github.com/yt-dlp/yt-dlp/releases/download/\(version)/yt-dlp_macos.zip"
        guard assets.count == 1, let asset = assets.first,
              (1...Self.maximumAssetBytes).contains(asset.size), asset.browser_download_url == expectedURL,
              let published = asset.digest, published.hasPrefix("sha256:"),
              Self.validDigest(String(published.dropFirst(7))) else { throw UpdateError.invalidRelease }
        let digest = String(published.dropFirst(7))
        let bytes = try await transport(URL(string: expectedURL)!, Self.maximumAssetBytes)
        try Task.checkCancellation()
        guard bytes.count == asset.size else { throw UpdateError.invalidDownload }
        guard Self.digest(bytes) == digest else { throw UpdateError.checksumMismatch }
        try ExtractorArchive.validate(bytes)

        // Each install has an immutable path. The atomic state write is the only
        // activation step, so interruption never replaces a working executable.
        var install = Install(directory: UUID().uuidString, version: version, sha256: digest, executableSHA256: "")
        let directory = root.appendingPathComponent(install.directory, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: directory) } }
        let executable = url(for: install)
        let archive = directory.appendingPathComponent("download.zip")
        try bytes.write(to: archive, options: .atomic)
        _ = try await ProcessRunner().run(URL(fileURLWithPath: "/usr/bin/ditto"),
                                         arguments: ["-x", "-k", archive.path, directory.appendingPathComponent("runtime").path])
        try FileManager.default.removeItem(at: archive)
        guard FileManager.default.fileExists(atPath: executable.deletingLastPathComponent().appendingPathComponent("_internal").path) else {
            throw UpdateError.invalidDownload
        }
        install.executableSHA256 = Self.digest(try Data(contentsOf: executable))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        // No downloaded code is executed before its published hash is verified.
        try await validate(executable, version)
        try Task.checkCancellation()
        var next = state
        let validCurrent = state.current.flatMap { verifiedExecutable($0) != nil ? $0 : nil }
        let validPrevious = state.previous.flatMap { verifiedExecutable($0) != nil ? $0 : nil }
        next.previous = state.currentWorked ? (validCurrent ?? validPrevious) : (validPrevious ?? validCurrent)
        next.current = install
        next.currentWorked = false
        try Paths.write(next, to: root.appendingPathComponent("state.json"))
        state = next; committed = true
        return true
    }

    private func verifiedExecutable(_ install: Install) -> URL? {
        guard UUID(uuidString: install.directory) != nil, Self.validVersion(install.version),
              Self.validDigest(install.sha256), Self.validDigest(install.executableSHA256) else { return nil }
        let executable = url(for: install)
        guard let values = try? executable.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey]),
              values.isRegularFile == true, values.isSymbolicLink == false,
              let size = values.fileSize, (1...Self.maximumAssetBytes).contains(size),
              let modified = values.contentModificationDate,
              FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        let key = InstallKey(directory: install.directory, size: size, digest: install.executableSHA256)
        if verified[key] != modified {
            guard let bytes = try? Data(contentsOf: executable, options: .mappedIfSafe), Self.digest(bytes) == install.executableSHA256 else { return nil }
            verified[key] = modified
        }
        return executable
    }
    private func url(for install: Install) -> URL { root.appendingPathComponent(install.directory).appendingPathComponent("runtime/yt-dlp_macos") }
    private func persist() throws { try Paths.write(state, to: root.appendingPathComponent("state.json")) }
    private func cleanUnusedInstalls() {
        guard !cleaned else { return }
        cleaned = true
        let keep = Set([state.current?.directory, state.previous?.directory].compactMap { $0 })
        // Defer deleting retired versions until the next updater session, so a
        // process already queued against an old path can still start safely.
        for directory in (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            if UUID(uuidString: directory.lastPathComponent) != nil, !keep.contains(directory.lastPathComponent) {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }
    private static func validVersion(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        return value.count <= 40 && (3...4).contains(parts.count) && parts.allSatisfy { !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }
    }
    private static func validDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }

    static func download(_ url: URL, maximumBytes: Int) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("geet-extractor-updater", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = 180
        let session = URLSession(configuration: configuration, delegate: ExtractorRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse,
              let finalURL = response.url, ExtractorRedirects.trusted(finalURL) else { throw UpdateError.invalidDownload }
        guard response.statusCode == 200 else { throw ExtractorSetupFailure.unavailable }
        guard response.expectedContentLength <= maximumBytes else { throw UpdateError.invalidDownload }
        var data = Data()
        for try await byte in bytes {
            guard data.count < maximumBytes else { throw UpdateError.invalidDownload }
            data.append(byte)
        }
        return data
    }
}

private final class ExtractorRedirects: NSObject, URLSessionTaskDelegate {
    static func trusted(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443) &&
            ["api.github.com", "github.com", "release-assets.githubusercontent.com", "objects.githubusercontent.com"].contains(url.host ?? "")
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(Self.trusted) == true ? request : nil)
    }
}

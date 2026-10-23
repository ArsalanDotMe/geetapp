import AppKit
import SwiftUI
import ImageIO
import CryptoKit

@MainActor
final class ArtworkStore {
    private struct Entry { var image: NSImage; var cost: Int; var touched: UInt64 }
    private var images: [URL: Entry] = [:]
    private var tick: UInt64 = 0
    private var requests: [URL: Task<Data, Error>] = [:]
    private let directory = GeetCore.Paths.support.appendingPathComponent("Artwork", isDirectory: true)
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpMaximumConnectionsPerHost = 2; config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config, delegate: ArtworkResponseGuard(), delegateQueue: nil)
    }()
    func image(_ url: URL) async -> NSImage? {
        tick &+= 1
        if var image = images[url] { image.touched = tick; images[url] = image; return image.image }
        let name = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = directory.appendingPathComponent(name)
        do {
            let data: Data
            if let saved = try? Data(contentsOf: file), saved.count <= 4 * 1024 * 1024 { data = saved }
            else {
                let task: Task<Data, Error>
                if let pending = requests[url] { task = pending }
                else {
                    task = Task { [session] in
                        let (data, response) = try await session.data(from: url)
                        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 4 * 1024 * 1024 else { throw URLError(.badServerResponse) }
                        return data
                    }
                    requests[url] = task
                }
                defer { requests.removeValue(forKey: url) }
                data = try await task.value
                try Task.checkCancellation()
                GeetCore.Paths.ensure(directory); try? data.write(to: file, options: .atomic)
                trimDisk()
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                     kCGImageSourceThumbnailMaxPixelSize: 800, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
            let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            images[url] = Entry(image: image, cost: cg.bytesPerRow * cg.height, touched: tick)
            while images.count > 24 || images.values.reduce(0, { $0 + $1.cost }) > 24 * 1024 * 1024 {
                guard let key = images.min(by: { $0.value.touched < $1.value.touched })?.key else { break }; images.removeValue(forKey: key)
            }
            return image
        } catch { return nil }
    }
    func cancelAll() { requests.values.forEach { $0.cancel() }; requests.removeAll() }
    private func trimDisk() {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else { return }
        let sorted = files.compactMap { url -> (URL, Int, Date)? in
            guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var size = sorted.reduce(0) { $0 + $1.1 }, count = sorted.count
        for (file, bytes, _) in sorted where size > 64 * 1024 * 1024 || count > 128 {
            try? FileManager.default.removeItem(at: file); size -= bytes; count -= 1
        }
    }
}

private final class ArtworkResponseGuard: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        completionHandler((response as? HTTPURLResponse)?.statusCode == 200 && response.expectedContentLength > 0 && response.expectedContentLength <= 4 * 1024 * 1024 ? .allow : .cancel)
    }
}

import GeetCore

struct CoverArt: View {
    let url: URL?
    let store: ArtworkStore
    var seed = ""
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFill() }
            else { Image(nsImage: LocalArtwork.image(seed)).resizable().scaledToFill() }
        }
        .task(id: url) {
            image = nil
            if let url { let loaded = await store.image(url); if !Task.isCancelled { image = loaded } }
        }
        .onDisappear { image = nil }
        // Scaled artwork can extend beyond its visible, clipped card bounds.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@MainActor private enum LocalArtwork {
    static let images: [String: NSImage] = ["late-night", "soft-focus", "rainy-sunday", "piano"].reduce(into: [:]) { result, name in
        if let url = Bundle.module.url(forResource: name, withExtension: "png"),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 900] as CFDictionary) {
            result[name] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
    }
    static func image(_ seed: String) -> NSImage {
        let name = seed == "soft" ? "soft-focus" : seed == "rain" ? "rainy-sunday" : seed == "piano" ? "piano" : "late-night"
        return images[name] ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)!
    }
}

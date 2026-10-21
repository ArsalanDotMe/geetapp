import AVFoundation
import GeetCore

/// Only retained while AVPlayer has an active cached asset. All callbacks and
/// request bookkeeping live on the main queue; disk/network work lives in MediaCache.
@MainActor
final class MediaResourceLoader: NSObject, @preconcurrency AVAssetResourceLoaderDelegate {
    let cache: MediaCache
    let key: String
    let stream: ResolvedStream?
    private var work: [ObjectIdentifier: Task<Void, Never>] = [:]
    init(cache: MediaCache, key: String, stream: ResolvedStream?) { self.cache = cache; self.key = key; self.stream = stream }
    func asset() -> AVURLAsset {
        let asset = AVURLAsset(url: URL(string: "geet-audio://cache/\(key).m4a")!)
        asset.resourceLoader.setDelegate(self, queue: .main)
        return asset
    }
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource request: AVAssetResourceLoadingRequest) -> Bool {
        let id = ObjectIdentifier(request)
        work[id] = Task { [weak self] in
            guard let self else { return }
            defer { work.removeValue(forKey: id) }
            do {
                let offset = request.dataRequest?.currentOffset ?? 0
                let initialIndex = Int(offset / MediaCache.chunkSize)
                let (_, length) = try await cache.chunk(key: key, index: initialIndex, stream: stream)
                try Task.checkCancellation()
                if let info = request.contentInformationRequest {
                    info.contentType = "public.mpeg-4-audio"; info.contentLength = length; info.isByteRangeAccessSupported = true
                }
                if let wanted = request.dataRequest {
                    var cursor = max(wanted.currentOffset, wanted.requestedOffset)
                    let end = wanted.requestsAllDataToEndOfResource ? length : min(length, wanted.requestedOffset + Int64(wanted.requestedLength))
                    while cursor < end {
                        try Task.checkCancellation()
                        let index = Int(cursor / MediaCache.chunkSize)
                        let (chunk, _) = try await cache.chunk(key: key, index: index, stream: stream)
                        try Task.checkCancellation()
                        let start = Int(cursor % MediaCache.chunkSize), count = min(chunk.count - start, Int(end - cursor))
                        guard count > 0 else { throw GeetError.message("The saved audio segment is incomplete.") }
                        wanted.respond(with: chunk.subdata(in: start..<(start + count)))
                        cursor += Int64(count)
                    }
                }
                request.finishLoading()
            } catch {
                if !Task.isCancelled { request.finishLoading(with: error) }
            }
        }
        return true
    }
    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel request: AVAssetResourceLoadingRequest) {
        work.removeValue(forKey: ObjectIdentifier(request))?.cancel()
    }
    func cancel() { work.values.forEach { $0.cancel() }; work.removeAll() }
}

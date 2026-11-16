import AVFoundation
import Foundation
import ImageIO
import Vision

enum SimilarMedia {
    struct Match: Identifiable, Sendable {
        let first: DiskItem
        let second: DiskItem
        let firstPreview: Data?
        let secondPreview: Data?
        var id: String { first.id }
    }

    struct Report: Sendable {
        var matches: [Match] = []
        var compared = 0
        var skipped = 0
        var partial = false
    }

    private struct Fingerprint {
        let item: DiskItem
        let frames: [VNFeaturePrintObservation]
        let preview: Data?
        let duration: Double?
    }

    private static let photos: Set<String> = ["jpg", "jpeg", "heic", "png", "tif", "tiff", "webp", "avif"]
    private static let videos: Set<String> = ["mov", "mp4", "m4v"]

    static func scan(_ root: URL, token: ScanCancellation) async -> Report {
        var report = Report()
        let root = root.resolvingSymlinksInPath().standardizedFileURL
        var unreadable = false
        let ignored = IgnoredLocations.paths
        guard !excluded(root), !IgnoredLocations.contains(root, in: ignored), let iterator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .isPackageKey],
            options: [.skipsHiddenFiles], errorHandler: { _, _ in unreadable = true; return true }
        ) else { report.partial = true; return report }

        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(60)
        var unmatched: [Fingerprint] = []
        var visited = 0
        while let url = iterator.nextObject() as? URL {
            if token.cancelled || Task.isCancelled || clock.now >= deadline || visited >= 20_000 || report.compared + report.skipped >= 300 {
                report.partial = true
                break
            }
            visited += 1
            guard let flags = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .isPackageKey]) else {
                report.partial = true
                continue
            }
            if flags.isSymbolicLink == true || flags.isPackage == true || excluded(url) || IgnoredLocations.contains(url, in: ignored) {
                iterator.skipDescendants()
                continue
            }
            let ext = url.pathExtension.lowercased()
            guard flags.isRegularFile == true, photos.contains(ext) || videos.contains(ext) else { continue }
            guard let item = InventoryService.measure(url, token: token), item.identity != nil, !item.incomplete, !item.directory, !item.symlink,
                  let signature = await fingerprint(item, video: videos.contains(ext), token: token),
                  FileIdentity.read(url) == item.identity else {
                report.skipped += 1
                continue
            }
            report.compared += 1
            if let index = unmatched.firstIndex(where: { resembles($0, signature) }) {
                let other = unmatched.remove(at: index)
                report.matches.append(Match(first: other.item, second: item, firstPreview: other.preview, secondPreview: signature.preview))
            } else {
                unmatched.append(signature)
            }
        }
        if unreadable || token.cancelled || Task.isCancelled { report.partial = true }
        return report
    }

    static func excluded(_ url: URL) -> Bool {
        url.pathComponents.contains { component in
            let ext = (component as NSString).pathExtension.lowercased()
            return ["photoslibrary", "photolibrary", "aplibrary", "photosasset", "migratedphotolibrary"].contains(ext)
        } || CleanupSafety.isSensitive(url.path)
    }

    private static func fingerprint(_ item: DiskItem, video: Bool, token: ScanCancellation) async -> Fingerprint? {
        if !video {
            guard let source = CGImageSourceCreateWithURL(item.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 384,
                    kCGImageSourceCreateThumbnailWithTransform: true
                  ] as CFDictionary), let print = feature(image) else { return nil }
            return Fingerprint(item: item, frames: [print], preview: thumbnail(image), duration: nil)
        }

        let asset = AVURLAsset(url: item.url)
        guard let length = try? await asset.load(.duration), length.seconds.isFinite, length.seconds > 0 else { return nil }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 384, height: 384)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = generator.requestedTimeToleranceBefore
        var frames: [VNFeaturePrintObservation] = []
        var preview: Data?
        for portion in [0.2, 0.5, 0.8] {
            guard !token.cancelled, !Task.isCancelled,
                  let sample = try? await generator.image(at: CMTime(seconds: length.seconds * portion, preferredTimescale: 600)),
                  let print = feature(sample.image) else { return nil }
            frames.append(print)
            if portion == 0.5 { preview = thumbnail(sample.image) }
        }
        return Fingerprint(item: item, frames: frames, preview: preview, duration: length.seconds)
    }

    private static func feature(_ image: CGImage) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        do { try VNImageRequestHandler(cgImage: image).perform([request]) }
        catch { return nil }
        return request.results?.first
    }

    private static func thumbnail(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let output = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(output, image, [kCGImageDestinationLossyCompressionQuality: 0.76] as CFDictionary)
        return CGImageDestinationFinalize(output) ? data as Data : nil
    }

    private static func resembles(_ lhs: Fingerprint, _ rhs: Fingerprint) -> Bool {
        guard lhs.frames.count == rhs.frames.count,
              lhs.item.identity != rhs.item.identity else { return false }
        if let a = lhs.duration, let b = rhs.duration, abs(a - b) > max(0.4, min(a, b) * 0.04) { return false }
        return zip(lhs.frames, rhs.frames).allSatisfy { a, b in
            var distance: Float = 0
            do { try a.computeDistance(&distance, to: b); return distance <= 0.20 }
            catch { return false }
        }
    }
}

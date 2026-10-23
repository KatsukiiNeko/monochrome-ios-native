// ArtworkTintStore.swift: sample and cache one average artwork color per track.
#if canImport(SwiftUI) && canImport(ImageIO) && canImport(CoreGraphics)
import CoreGraphics
import Foundation
import ImageIO
import MonochromeCore

actor ArtworkTintStore {
    private var cache: [String: ArtworkTintColor] = [:]
    private var inFlight: [String: Task<ArtworkTintColor, Never>] = [:]

    func tint(for track: Track, localURL: URL?) async -> ArtworkTintColor {
        if let cached = cache[track.id] { return cached }
        if let running = inFlight[track.id] { return await running.value }

        let url = localURL ?? track.artworkURL
        let task = Task.detached(priority: .utility) {
            await Self.sample(url: url)
        }
        inFlight[track.id] = task
        let tint = await task.value
        cache[track.id] = tint
        inFlight[track.id] = nil
        return tint
    }

    private nonisolated static func sample(url: URL?) async -> ArtworkTintColor {
        guard let url else { return .neutral }
        if url.isFileURL {
            return sample(data: nil, url: url)
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else {
            return .neutral
        }
        return sample(data: data, url: nil)
    }

    private nonisolated static func sample(data: Data?, url: URL?) -> ArtworkTintColor {
        let source: CGImageSource?
        if let data {
            source = CGImageSourceCreateWithData(data as CFData, nil)
        } else if let url {
            source = CGImageSourceCreateWithURL(url as CFURL, nil)
        } else {
            source = nil
        }
        guard let source, let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return .neutral
        }
        return averageColor(of: image)
    }

    /// Draws the image into one pixel; the result is the average artwork color.
    private nonisolated static func averageColor(of image: CGImage) -> ArtworkTintColor {
        var pixel = [UInt8](repeating: 0, count: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let drew = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drew else { return .neutral }
        return ArtworkTint.derive(
            from: ArtworkTintColor(
                red: Double(pixel[0]) / 255,
                green: Double(pixel[1]) / 255,
                blue: Double(pixel[2]) / 255
            )
        )
    }
}
#endif

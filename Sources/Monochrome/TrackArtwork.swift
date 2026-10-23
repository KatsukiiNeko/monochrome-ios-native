// TrackArtwork.swift: square artwork for any track — remote catalog image, local file, or placeholder.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct TrackArtwork: View {
    let track: Track?
    var localURL: URL?
    var cornerRadius: CGFloat = Theme.artworkRadius

    var body: some View {
        Group {
            if let remote = track?.artworkURL {
                AsyncImage(url: remote) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        ArtworkPlaceholder()
                    }
                }
            } else {
                LocalArtwork(fileURL: localURL)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

private struct ArtworkPlaceholder: View {
    var body: some View {
        Rectangle()
            .fill(Theme.elevated)
            .overlay {
                Image(systemName: "music.note")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
    }
}

private struct LocalArtwork: View {
    let fileURL: URL?

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ArtworkPlaceholder()
            }
        }
        .task(id: fileURL) {
            image = nil
            guard let fileURL else { return }
            image = UIImage(contentsOfFile: fileURL.path)
        }
    }
}
#endif

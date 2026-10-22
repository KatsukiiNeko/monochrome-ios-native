// ArtworkView.swift: embedded artwork, falling back to a waveform placeholder.
#if canImport(SwiftUI)
import SwiftUI

struct ArtworkView: View {
    let fileURL: URL?

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 72, weight: .thin))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 280)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityHidden(true)
        .task(id: fileURL) {
            image = nil
            guard let fileURL else { return }
            image = UIImage(contentsOfFile: fileURL.path)
        }
    }
}
#endif

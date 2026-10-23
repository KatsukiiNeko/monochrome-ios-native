// Scrubber.swift: thin seek track that thickens while dragging.
#if canImport(SwiftUI)
import MonochromeCore
import SwiftUI

struct Scrubber: View {
    let position: Double
    let duration: Double
    var onSeek: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDragging = false
    @State private var dragPosition: Double?

    private var displayedPosition: Double {
        dragPosition ?? position
    }

    private var fraction: Double {
        guard duration > 0 else { return 0 }
        return min(max(displayedPosition / duration, 0), 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let height: CGFloat = isDragging ? 6 : 2
                let thumb: CGFloat = isDragging ? 16 : 12
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.separator)
                        .frame(height: height)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: width * fraction, height: height)
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: thumb, height: thumb)
                        .offset(x: max(0, min(width - thumb, width * fraction - thumb / 2)))
                        .opacity(isDragging ? 1 : 0)
                }
                .animation(reduceMotion ? nil : Theme.quick, value: isDragging)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard duration > 0 else { return }
                            isDragging = true
                            let x = min(max(value.location.x, 0), width)
                            dragPosition = (x / width) * duration
                        }
                        .onEnded { _ in
                            if let dragPosition {
                                onSeek(dragPosition)
                            }
                            isDragging = false
                            dragPosition = nil
                        }
                )
            }
            .frame(height: 24)

            HStack {
                Text(formatDuration(displayedPosition))
                Spacer()
                Text("-\(formatDuration(max(0, duration - displayedPosition)))")
            }
            .font(Theme.time)
            .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Playback position")
        .accessibilityValue(
            "\(formatDuration(displayedPosition)) of \(formatDuration(duration))"
        )
        .accessibilityHint("Swipe up or down to seek")
        .accessibilityAdjustableAction { direction in
            guard duration > 0 else { return }
            let step = max(duration / 20, 5)
            switch direction {
            case .increment:
                onSeek(min(duration, position + step))
            case .decrement:
                onSeek(max(0, position - step))
            @unknown default:
                break
            }
        }
    }
}
#endif

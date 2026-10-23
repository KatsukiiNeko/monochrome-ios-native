// AirPlayRoutePicker.swift: system AirPlay route button for Now Playing.
#if canImport(SwiftUI) && canImport(AVKit)
import AVKit
import SwiftUI

struct AirPlayRoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .label
        view.activeTintColor = .label
        view.prioritizesVideoDevices = false
        view.accessibilityLabel = "AirPlay"
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
#endif

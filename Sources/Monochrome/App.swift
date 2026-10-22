// App.swift: SwiftUI entry point for the iOS app shell.
#if canImport(SwiftUI)
import SwiftUI

@main
struct MonochromeApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Monochrome")
                .font(.title)
        }
    }
}
#endif

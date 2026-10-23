// ArtworkTint.swift: turn an artwork's average color into a dark, readable surface color.
import Foundation

/// Normalized RGB, each channel in 0...1.
public struct ArtworkTintColor: Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Fallback used when artwork is missing or cannot be sampled.
    public static let neutral = ArtworkTintColor(red: 0.12, green: 0.12, blue: 0.12)
}

public enum ArtworkTint {
    /// Brightness is clamped to this range so white text stays readable.
    public static let minimumBrightness = 0.12
    public static let maximumBrightness = 0.35

    /// Preserves hue, keeps grays gray, and clamps the result to a dark surface.
    public static func derive(from color: ArtworkTintColor) -> ArtworkTintColor {
        let red = clamp(color.red)
        let green = clamp(color.green)
        let blue = clamp(color.blue)

        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let brightness = maximum
        let saturation = maximum == 0 ? 0 : (maximum - minimum) / maximum
        let targetBrightness = min(
            max(brightness * 0.45, minimumBrightness),
            maximumBrightness
        )

        // Near-neutral artwork stays neutral; a tinted surface would look wrong.
        guard saturation >= 0.02 else {
            return ArtworkTintColor(
                red: targetBrightness,
                green: targetBrightness,
                blue: targetBrightness
            )
        }

        let hue = hue(red: red, green: green, blue: blue, maximum: maximum, minimum: minimum)
        let targetSaturation = min(1, saturation * 1.12 + 0.02)
        return rgb(
            hue: hue,
            saturation: targetSaturation,
            brightness: targetBrightness
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func hue(
        red: Double,
        green: Double,
        blue: Double,
        maximum: Double,
        minimum: Double
    ) -> Double {
        let delta = maximum - minimum
        guard delta > 0 else { return 0 }
        let raw: Double
        if maximum == red {
            raw = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == green {
            raw = (blue - red) / delta + 2
        } else {
            raw = (red - green) / delta + 4
        }
        let degrees = raw * 60
        return degrees < 0 ? degrees + 360 : degrees
    }

    private static func rgb(hue: Double, saturation: Double, brightness: Double) -> ArtworkTintColor {
        let chroma = brightness * saturation
        let sector = (hue / 60).truncatingRemainder(dividingBy: 6)
        let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let (red, green, blue): (Double, Double, Double)
        switch sector {
        case 0..<1: (red, green, blue) = (chroma, x, 0)
        case 1..<2: (red, green, blue) = (x, chroma, 0)
        case 2..<3: (red, green, blue) = (0, chroma, x)
        case 3..<4: (red, green, blue) = (0, x, chroma)
        case 4..<5: (red, green, blue) = (x, 0, chroma)
        default: (red, green, blue) = (chroma, 0, x)
        }
        let match = brightness - chroma
        return ArtworkTintColor(red: red + match, green: green + match, blue: blue + match)
    }
}

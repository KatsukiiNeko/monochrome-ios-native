// LayoutSpec.swift: screen numbers shared by the views and their host tests.
import Foundation

/// One place for the measurements a layout test can assert. Views read these
/// through `Theme`, so a value changes in one place.
public enum LayoutSpec {
    /// Minimum height of the mini-player card, and the band it reserves from
    /// the scroll content through the bottom safe-area inset.
    public static let miniPlayerHeight: CGFloat = 64
    /// Vertical touch target of the player scrubber; the visible track stays thin.
    public static let scrubberHitTarget: CGFloat = 44
    /// Square artwork in the full player on a regular screen.
    public static let playerArtworkMaxWidth: CGFloat = 360
    /// Square artwork when the player is short or narrow.
    public static let playerCompactArtworkMaxWidth: CGFloat = 264
    /// A player shorter than this switches to the compact composition.
    public static let playerCompactHeight: CGFloat = 700
    /// A player narrower than this switches to the compact composition.
    public static let playerCompactWidth: CGFloat = 360
    /// Extra scrollable space below the last row, so it can rise above the
    /// mini-player. About one and a half track rows.
    public static let scrollBottomPadding: CGFloat = 80
    /// Skeleton rows wait this long before appearing, so a fast answer never flashes.
    public static let searchSkeletonGraceMs = 150
    /// Once shown, skeleton rows stay at least this long.
    public static let searchSkeletonMinVisibleMs = 300
}

/// Which full-player composition fits a screen.
public enum PlayerVariant: Sendable, Equatable {
    case regular
    case compact
}

public enum PlayerLayout {
    public static func variant(forWidth width: CGFloat, height: CGFloat) -> PlayerVariant {
        if width < LayoutSpec.playerCompactWidth { return .compact }
        if height < LayoutSpec.playerCompactHeight { return .compact }
        return .regular
    }

    public static func artworkMaxWidth(for variant: PlayerVariant) -> CGFloat {
        switch variant {
        case .regular: LayoutSpec.playerArtworkMaxWidth
        case .compact: LayoutSpec.playerCompactArtworkMaxWidth
        }
    }

    public static func artworkMaxWidth(forWidth width: CGFloat, height: CGFloat) -> CGFloat {
        artworkMaxWidth(for: variant(forWidth: width, height: height))
    }
}

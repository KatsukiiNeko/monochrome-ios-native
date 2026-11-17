// TestSupport.swift: small helpers shared by test files.
import Foundation

/// Seeded linear generator so shuffle order is exactly reproducible.
func seededGenerator(seed: UInt64) -> (Int) -> Int {
    var state = seed
    return { bound in
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) % UInt64(max(bound, 1)))
    }
}

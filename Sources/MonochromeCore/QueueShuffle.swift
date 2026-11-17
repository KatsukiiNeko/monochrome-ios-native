// QueueShuffle.swift: Fisher-Yates shuffle that keeps one track pinned in place.
import Foundation

public enum QueueShuffle {
    /// Returns a copy of `items` where every entry except the one at `pinIndex`
    /// is shuffled by Fisher-Yates using the injected generator. The generator
    /// receives the exclusive upper bound and returns a value in `0..<bound`.
    public static func shuffled<T>(_ items: [T], pinIndex: Int?, generator: (Int) -> Int) -> [T] {
        guard items.count > 1 else { return items }
        guard let pinIndex, items.indices.contains(pinIndex) else {
            return fisherYates(items, generator: generator)
        }
        var pool = Array(items.indices).filter { $0 != pinIndex }
        guard pool.count > 1 else { return items }
        for index in stride(from: pool.count - 1, to: 0, by: -1) {
            pool.swapAt(index, generator(index + 1))
        }
        var shuffled = items
        var poolIndex = 0
        for slot in items.indices where slot != pinIndex {
            shuffled[slot] = items[pool[poolIndex]]
            poolIndex += 1
        }
        return shuffled
    }

    private static func fisherYates<T>(_ items: [T], generator: (Int) -> Int) -> [T] {
        var shuffled = items
        for index in stride(from: shuffled.count - 1, to: 0, by: -1) {
            shuffled.swapAt(index, generator(index + 1))
        }
        return shuffled
    }
}

//
//  IndexedCollection.swift
//  moro
//
//  A zero-copy `(offset, element)` view of an array, for ForEach rows that need their index.
//

import Foundation

/// `ForEach(Array(items.enumerated()), …)` copies every element into a new array of tuples
/// on each body pass; for a timeline of hundreds of posts that is a full copy every time the
/// view model publishes. This wraps the same array (copy-on-write, no copy) and builds each
/// pair only when SwiftUI asks for it. Elements match `enumerated()`: `(offset:, element:)`.
nonisolated struct IndexedCollection<Base: RandomAccessCollection>: RandomAccessCollection
where Base.Index == Int {
    let base: Base

    var startIndex: Int { base.startIndex }
    var endIndex: Int { base.endIndex }

    subscript(position: Int) -> (offset: Int, element: Base.Element) {
        (position - base.startIndex, base[position])
    }
}

extension RandomAccessCollection where Index == Int {
    /// Same pairs as `enumerated()`, as a random-access collection ForEach can use directly.
    nonisolated func indexed() -> IndexedCollection<Self> {
        IndexedCollection(base: self)
    }
}

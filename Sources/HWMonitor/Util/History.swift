import Foundation

/// Fixed-length ring of samples, oldest first. Pre-filled with zeros so charts
/// keep a stable x-range and scroll in from the right.
struct History: Equatable {
    private(set) var values: [Double]
    let capacity: Int

    init(capacity: Int) {
        self.capacity = capacity
        self.values = Array(repeating: 0, count: capacity)
    }

    mutating func push(_ v: Double) {
        values.append(v)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }

    var last: Double { values.last ?? 0 }
    var max: Double { values.max() ?? 0 }
    func suffix(_ n: Int) -> [Double] { Array(values.suffix(n)) }
}

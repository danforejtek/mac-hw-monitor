import SwiftUI
import Combine

/// Tiny observable box used instead of `@State` (the Command Line Tools toolchain cannot
/// expand the `@State` macro from the macOS 26 SDK, while `@StateObject` works fine).
final class UIState<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}

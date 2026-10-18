import Combine
import SwiftUI

/// Drop-in stand-in for SwiftUI's `@State`.
///
/// In the macOS 27 SDK `@State` is a macro whose implementation (SwiftUIMacros)
/// ships only with full Xcode, so the Command Line Tools toolchain can't compile it.
/// This wrapper stores the value in a `@StateObject` box instead, which needs no macro.
@propertyWrapper
struct ViewState<Value>: DynamicProperty {
    @StateObject private var box: Box

    init(wrappedValue: Value) {
        _box = StateObject(wrappedValue: Box(wrappedValue))
    }

    init() where Value: ExpressibleByNilLiteral {
        self.init(wrappedValue: nil)
    }

    var wrappedValue: Value {
        get { box.value }
        nonmutating set { box.value = newValue }
    }

    var projectedValue: Binding<Value> {
        let box = box
        return Binding(get: { box.value }, set: { box.value = $0 })
    }

    final class Box: ObservableObject {
        @Published var value: Value
        init(_ value: Value) { self.value = value }
    }
}

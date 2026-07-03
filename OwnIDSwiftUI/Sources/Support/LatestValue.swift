import SwiftUI

internal final class LatestValueBox<Value> {
    internal var value: Value

    internal init(_ value: Value) {
        self.value = value
    }
}

@propertyWrapper
internal struct LatestValue<Value>: DynamicProperty {
    @State private var box: LatestValueBox<Value>
    private let latestValue: Value

    internal init(wrappedValue: Value) {
        self.latestValue = wrappedValue
        self._box = State(initialValue: LatestValueBox(wrappedValue))
    }

    internal var wrappedValue: Value {
        latestValue
    }

    internal var projectedValue: LatestValueBox<Value> {
        box
    }

    internal mutating func update() {
        box.value = latestValue
    }
}

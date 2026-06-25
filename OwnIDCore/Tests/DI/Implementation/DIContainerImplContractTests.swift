import Foundation
import Testing

@_spi(OwnIDInternal) @testable import OwnIDCore

struct DIContainerImplContractTests {

    @Test func `Registration replacement and factory lifetime follow current scope binding`() throws {
        let container = DIContainerImpl(scopeName: "test")
        let counter = LockedCounter()

        container.register(TestService.self, instance: TestService(value: "first"))
        container.register(TestService.self, instance: TestService(value: "second"))

        #expect(try container.getOrThrow(type: TestService.self) == TestService(value: "second"))

        container.registerFactory(TestService.self, dependencies: []) { _ in
            TestService(value: "factory-\(counter.increment())")
        }

        #expect(try container.getOrThrow(type: TestService.self) == TestService(value: "factory-1"))
        #expect(try container.getOrThrow(type: TestService.self) == TestService(value: "factory-2"))
    }

    @Test func `Child scopes inherit parent bindings and override only their subtree`() throws {
        let root = DIContainerImpl(scopeName: "root")
        let child = root.createScope(scopeName: "child")
        let sibling = root.createScope(scopeName: "sibling")

        root.register(TestService.self, instance: TestService(value: "root"))

        #expect(try child.getOrThrow(type: TestService.self) == TestService(value: "root"))
        #expect(try sibling.getOrThrow(type: TestService.self) == TestService(value: "root"))

        child.register(TestService.self, instance: TestService(value: "child"))

        #expect(try root.getOrThrow(type: TestService.self) == TestService(value: "root"))
        #expect(try child.getOrThrow(type: TestService.self) == TestService(value: "child"))
        #expect(try sibling.getOrThrow(type: TestService.self) == TestService(value: "root"))

        child.remove(TestService.self)

        #expect(try child.getOrThrow(type: TestService.self) == TestService(value: "root"))
    }

    @Test func `Parent factory resolves nested dependencies from original requester`() throws {
        let root = DIContainerImpl(scopeName: "root")
        let child = root.createScope(scopeName: "child")

        root.register(TestService.self, instance: TestService(value: "root"))
        root.registerFactory(ComposedService.self, dependencies: [TestService.self]) { resolver in
            ComposedService(service: try resolver.getOrThrow(type: TestService.self))
        }
        child.register(TestService.self, instance: TestService(value: "child"))

        #expect(try root.getOrThrow(type: ComposedService.self) == ComposedService(service: TestService(value: "root")))
        #expect(try child.getOrThrow(type: ComposedService.self) == ComposedService(service: TestService(value: "child")))
    }

    @Test func `Missing dependency error values come from requesting scope and type`() throws {
        let root = DIContainerImpl(scopeName: "root")
        let child = root.createScope(scopeName: "child")

        let error = try #require(throws: (any Error).self) {
            try child.getOrThrow(type: MissingService.self)
        }
        let missing = try #require(error as? MissingDependencyError)

        #expect(missing.dependencyName == String(describing: MissingService.self))
        #expect(missing.scopeName == "child")
        expectDiagnostic(missing.entryPoint, contains: String(describing: MissingService.self))
        #expect(child.getOrNil(type: MissingService.self) == nil)
    }

    @Test func `Factory failures are wrapped as dependency resolution errors and suppressed by get or nil`() throws {
        let container = DIContainerImpl(scopeName: "factory-scope")

        container.registerFactory(FailingService.self, dependencies: []) { _ throws -> FailingService in
            throw FactoryFailure.expected
        }

        let error = try #require(throws: (any Error).self) {
            try container.getOrThrow(type: FailingService.self)
        }
        let resolution = try #require(error as? DependencyResolutionError)

        #expect(resolution.dependencyName == String(describing: FailingService.self))
        #expect(resolution.scopeName == "factory-scope")
        expectDiagnostic(resolution.entryPoint, contains: String(describing: FailingService.self))
        #expect(resolution.cause is FactoryFailure)
        #expect(container.getOrNil(type: FailingService.self) == nil)
    }

    @Test func `Declared dependencies drive can resolve and unsatisfied traces`() {
        let container = DIContainerImpl(scopeName: "dependency-scope")

        container.registerFactory(ComposedService.self, dependencies: [MissingService.self]) { _ in
            ComposedService(service: TestService(value: "unused"))
        }

        #expect(!(container.canResolve(ComposedService.self)))
        #expect(
            container.getUnsatisfiedDependencies(for: ComposedService.self)?.contains {
                $0.contains("dependency-scope") && $0.contains("ComposedService") && $0.contains("MissingService")
            } == true
        )

        container.register(MissingService.self, instance: MissingService())

        #expect(container.canResolve(ComposedService.self))
        #expect(container.getUnsatisfiedDependencies(for: ComposedService.self) == nil)
    }

    @Test func `Declared dependency cycles are reported without running factories`() {
        let container = DIContainerImpl(scopeName: "cycle-scope")

        container.registerFactory(CycleA.self, dependencies: [CycleB.self]) { _ in CycleA() }
        container.registerFactory(CycleB.self, dependencies: [CycleA.self]) { _ in CycleB() }

        #expect(!(container.canResolve(CycleA.self)))
        #expect(
            container.getUnsatisfiedDependencies(for: CycleA.self)?.contains {
                $0.contains("cycle-scope") && $0.contains("CycleA") && $0.contains("CycleB")
            } == true
        )
    }

    @Test func `All instances returns visible matching bindings and skips failing factories`() {
        let parent = DIContainerImpl(scopeName: "parent")
        let child = parent.createScope(scopeName: "child")
        let parentPlugin = ParentPlugin(value: "parent")
        let childPlugin = ChildPlugin(value: "child")

        parent.register(ParentPlugin.self, instance: parentPlugin)
        parent.registerFactory(BrokenPlugin.self, dependencies: [MissingService.self]) { resolver in
            BrokenPlugin(missing: try resolver.getOrThrow(type: MissingService.self))
        }
        child.register(ChildPlugin.self, instance: childPlugin)

        let plugins =
            child
            .getAllInstancesOf { type in type is any TestPlugin.Type }
            .compactMap { $0 as? any TestPlugin }
            .map(\.value)

        #expect(plugins == ["child", "parent"])
    }

}

private struct TestService: Sendable, Equatable {
    let value: String
}

private struct ComposedService: Sendable, Equatable {
    let service: TestService
}

private struct MissingService: Sendable {}

private struct FailingService: Sendable {}

private struct CycleA: Sendable {}

private struct CycleB: Sendable {}

private protocol TestPlugin: Sendable {
    var value: String { get }
}

private struct ParentPlugin: TestPlugin {
    let value: String
}

private struct ChildPlugin: TestPlugin {
    let value: String
}

private struct BrokenPlugin: TestPlugin {
    let missing: MissingService
    let value = "broken"
}

private enum FactoryFailure: Error {
    case expected
}

private func expectDiagnostic(
    _ diagnostic: String?,
    contains expectedFragment: String,
    sourceLocation: SourceLocation = SourceLocation(fileID: #fileID, filePath: #filePath, line: #line, column: #column)
) {
    #expect(
        diagnostic?.contains(expectedFragment) == true,
        "Expected diagnostic to mention \(expectedFragment), got \(diagnostic ?? "nil")",
        sourceLocation: sourceLocation
    )
}

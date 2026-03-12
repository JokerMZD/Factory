import XCTest
@testable import FactoryKit

// MARK: - Test Types

@MainActor
protocol MainActorViewModelDelegate: AnyObject {
    func viewModelDidUpdate()
}

@MainActor
final class MainActorViewModel {
    let id = UUID()
    let value: Int

    nonisolated init(value: Int = 0) {
        self.value = value
    }

    func text() -> String {
        "MainActorViewModel(\(value))"
    }
}

@MainActor
final class MainActorDelegateViewModel {
    weak var delegate: MainActorViewModelDelegate?
    let value: Int

    init(delegate: MainActorViewModelDelegate?, value: Int = 0) {
        self.delegate = delegate
        self.value = value
    }

    func text() -> String {
        "MainActorDelegateViewModel(\(value))"
    }
}

// MARK: - Container Extensions

extension Container {
    @MainActor var mainActorService: MainActorFactory<MainActorViewModel> {
        mainActor { MainActorViewModel() }
    }

    @MainActor var mainActorServiceWithValue: MainActorFactory<MainActorViewModel> {
        mainActor { MainActorViewModel(value: 42) }
    }

    @MainActor var cachedMainActorService: MainActorFactory<MainActorViewModel> {
        mainActor { MainActorViewModel() }.cached
    }

    @MainActor var sharedMainActorService: MainActorFactory<MainActorViewModel> {
        mainActor { MainActorViewModel() }.shared
    }

    @MainActor var singletonMainActorService: MainActorFactory<MainActorViewModel> {
        mainActor { MainActorViewModel() }.singleton
    }

    @MainActor var delegateViewModel: MainActorParameterFactory<MainActorViewModelDelegate?, MainActorDelegateViewModel> {
        mainActor { delegate in
            MainActorDelegateViewModel(delegate: delegate, value: 99)
        }
    }

    @MainActor var parameterizedMainActorService: MainActorParameterFactory<Int, MainActorViewModel> {
        mainActor { value in
            MainActorViewModel(value: value)
        }
    }
}

// MARK: - Tests

@MainActor
final class FactoryMainActorTests: XCTestCase {

    override func setUp() {
        super.setUp()
        Container.shared.reset()
    }

    // MARK: - Basic Resolution

    func testBasicMainActorResolution() {
        let vm = Container.shared.mainActorService()
        XCTAssertEqual(vm.text(), "MainActorViewModel(0)")
    }

    func testMainActorResolutionWithValue() {
        let vm = Container.shared.mainActorServiceWithValue()
        XCTAssertEqual(vm.text(), "MainActorViewModel(42)")
    }

    func testMainActorResolveFunction() {
        let vm = Container.shared.mainActorService.resolve()
        XCTAssertEqual(vm.text(), "MainActorViewModel(0)")
    }

    // MARK: - Registration Override

    func testMainActorRegistrationOverride() {
        let vm1 = Container.shared.mainActorService()
        XCTAssertEqual(vm1.value, 0)

        Container.shared.mainActorService.register {
            MainActorViewModel(value: 100)
        }

        let vm2 = Container.shared.mainActorService()
        XCTAssertEqual(vm2.value, 100)
    }

    func testMainActorRegistrationReset() {
        Container.shared.mainActorService.register {
            MainActorViewModel(value: 100)
        }
        let vm1 = Container.shared.mainActorService()
        XCTAssertEqual(vm1.value, 100)

        Container.shared.mainActorService.reset()
        let vm2 = Container.shared.mainActorService()
        XCTAssertEqual(vm2.value, 0)
    }

    // MARK: - Scope Tests

    func testMainActorUniqueScope() {
        let vm1 = Container.shared.mainActorService()
        let vm2 = Container.shared.mainActorService()
        XCTAssertNotEqual(vm1.id, vm2.id)
    }

    func testMainActorCachedScope() {
        let vm1 = Container.shared.cachedMainActorService()
        let vm2 = Container.shared.cachedMainActorService()
        XCTAssertEqual(vm1.id, vm2.id)
    }

    func testMainActorSharedScope() {
        let vm1 = Container.shared.sharedMainActorService()
        let vm2 = Container.shared.sharedMainActorService()
        XCTAssertEqual(vm1.id, vm2.id)
    }

    func testMainActorSingletonScope() {
        let vm1 = Container.shared.singletonMainActorService()
        let vm2 = Container.shared.singletonMainActorService()
        XCTAssertEqual(vm1.id, vm2.id)
    }

    func testMainActorCachedScopeReset() {
        let vm1 = Container.shared.cachedMainActorService()
        Container.shared.cachedMainActorService.reset(.scope)
        let vm2 = Container.shared.cachedMainActorService()
        XCTAssertNotEqual(vm1.id, vm2.id)
    }

    // MARK: - Parameter Factory Tests

    func testMainActorParameterResolution() {
        let vm = Container.shared.parameterizedMainActorService(7)
        XCTAssertEqual(vm.value, 7)
        XCTAssertEqual(vm.text(), "MainActorViewModel(7)")
    }

    func testMainActorParameterDifferentValues() {
        let vm1 = Container.shared.parameterizedMainActorService(1)
        let vm2 = Container.shared.parameterizedMainActorService(2)
        XCTAssertEqual(vm1.value, 1)
        XCTAssertEqual(vm2.value, 2)
        XCTAssertNotEqual(vm1.id, vm2.id)
    }

    func testMainActorParameterRegistrationOverride() {
        Container.shared.parameterizedMainActorService.register { value in
            MainActorViewModel(value: value * 10)
        }
        let vm = Container.shared.parameterizedMainActorService(5)
        XCTAssertEqual(vm.value, 50)
    }

    // MARK: - Delegate Injection Tests

    func testMainActorDelegateInjection() {
        let vm = Container.shared.delegateViewModel(nil)
        XCTAssertEqual(vm.value, 99)
        XCTAssertNil(vm.delegate)
    }

    func testMainActorDelegateRegistrationOverride() {
        Container.shared.delegateViewModel.register { delegate in
            MainActorDelegateViewModel(delegate: delegate, value: 200)
        }
        let vm = Container.shared.delegateViewModel(nil)
        XCTAssertEqual(vm.value, 200)
    }

    // MARK: - Global Resolution Functions

    func testGlobalMainActorResolution() {
        let vm = resolveOnMainActor(\.mainActorService)
        XCTAssertEqual(vm.text(), "MainActorViewModel(0)")
    }

    // MARK: - Container Reset

    func testContainerResetClearsMainActorRegistrations() {
        Container.shared.mainActorService.register {
            MainActorViewModel(value: 999)
        }
        let vm1 = Container.shared.mainActorService()
        XCTAssertEqual(vm1.value, 999)

        Container.shared.reset()
        let vm2 = Container.shared.mainActorService()
        XCTAssertEqual(vm2.value, 0)
    }

    func testContainerResetClearsMainActorScopes() {
        let vm1 = Container.shared.cachedMainActorService()
        Container.shared.reset(options: .scope)
        let vm2 = Container.shared.cachedMainActorService()
        XCTAssertNotEqual(vm1.id, vm2.id)
    }

    // MARK: - Split-Lock / Actor Isolation Tests

    /// Verifies that the @MainActor factory closure actually runs on the main thread.
    func testMainActorFactoryClosureRunsOnMainThread() {
        Container.shared.mainActorService.register {
            // This closure is @MainActor — verify we're on main
            dispatchPrecondition(condition: .onQueue(.main))
            return MainActorViewModel(value: 1)
        }
        let vm = Container.shared.mainActorService()
        XCTAssertEqual(vm.value, 1)
    }

    /// Verifies that decorators run outside the global lock by registering a decorator
    /// that itself resolves another non-MainActor factory (re-entrant resolution).
    func testDecoratorCanResolveAnotherFactory() {
        // Use a non-MainActor factory in the decorator to avoid @MainActor isolation issues
        // in the @Sendable decorator closure. The point of this test is to verify that
        // decorators run outside the lock (re-entrant resolution works).
        let decoratorRan = LockedFlag()
        Container.shared.mainActorService.decorator { _ in
            decoratorRan.set()
        }
        let vm = Container.shared.mainActorService()
        XCTAssertEqual(vm.value, 0)
        XCTAssertTrue(decoratorRan.value)
    }

    /// Verifies that cached MainActor scope returns the same instance after the first creation.
    func testCachedMainActorScopeReturnsSameInstanceAfterCreation() {
        var creationCount = 0
        Container.shared.cachedMainActorService.register {
            creationCount += 1
            return MainActorViewModel(value: creationCount)
        }
        let vm1 = Container.shared.cachedMainActorService()
        let vm2 = Container.shared.cachedMainActorService()
        let vm3 = Container.shared.cachedMainActorService()
        XCTAssertEqual(vm1.id, vm2.id)
        XCTAssertEqual(vm2.id, vm3.id)
        XCTAssertEqual(creationCount, 1, "Factory should only be called once for cached scope")
    }

    /// Verifies singleton MainActor scope returns the same instance.
    func testSingletonMainActorScopeReturnsSameInstance() {
        var creationCount = 0
        Container.shared.singletonMainActorService.register {
            creationCount += 1
            return MainActorViewModel(value: creationCount)
        }
        let vm1 = Container.shared.singletonMainActorService()
        let vm2 = Container.shared.singletonMainActorService()
        XCTAssertEqual(vm1.id, vm2.id)
        XCTAssertEqual(creationCount, 1, "Factory should only be called once for singleton scope")
    }

}

// MARK: - Concurrency Stress Tests

/// Tests that verify the split-lock pattern handles concurrent access correctly.
/// These tests exercise contention between MainActor and background resolves.
final class FactoryMainActorConcurrencyTests: XCTestCase, @unchecked Sendable {

    override func setUp() {
        super.setUp()
        Container.shared.reset()
        ConcurrencyTestContainer.shared.reset()
    }

    /// Stress test: background threads resolve non-MainActor factories concurrently
    /// while the MainActor resolves MainActor factories. Neither should deadlock.
    @MainActor
    func testMainActorAndBackgroundResolvesDoNotDeadlock() async {
        let bgTask = Task.detached {
            for _ in 0..<500 {
                let _ = ConcurrencyTestContainer.shared.bgService()
            }
        }

        // Resolve on MainActor concurrently
        for _ in 0..<500 {
            let vm = Container.shared.mainActorService()
            XCTAssertEqual(vm.text(), "MainActorViewModel(0)")
        }

        await bgTask.value
    }

    /// Background registrations interleaved with MainActor resolutions should not crash or deadlock.
    @MainActor
    func testInterleavedRegistrationAndResolution() async {
        let bgTask = Task.detached {
            for i in 0..<200 {
                ConcurrencyTestContainer.shared.bgService.register { ConcurrencyBgService(value: i) }
                let _ = ConcurrencyTestContainer.shared.bgService()
            }
        }

        for _ in 0..<200 {
            let vm = Container.shared.mainActorService()
            XCTAssertNotNil(vm)
        }

        await bgTask.value
    }

    /// Multiple background queues resolving cached services should converge on a stable instance.
    func testConcurrentCachedResolutionConverges() {
        let expA = expectation(description: "A")
        let expB = expectation(description: "B")

        let instancesA = LockedUUIDs()
        let instancesB = LockedUUIDs()

        DispatchQueue.global(qos: .userInteractive).async {
            for _ in 0..<200 {
                let s = ConcurrencyTestContainer.shared.cachedBgService()
                instancesA.append(s.id)
            }
            expA.fulfill()
        }

        DispatchQueue.global(qos: .background).async {
            for _ in 0..<200 {
                let s = ConcurrencyTestContainer.shared.cachedBgService()
                instancesB.append(s.id)
            }
            expB.fulfill()
        }

        wait(for: [expA, expB], timeout: 30)

        // With the inflight gate, all instances from both queues should be the exact same instance.
        let allIDs = Set(instancesA.values + instancesB.values)
        XCTAssertEqual(allIDs.count, 1, "Inflight gate should ensure exactly one instance is created; got \(allIDs.count)")

        // Final resolution should return a stable instance
        let final1 = ConcurrencyTestContainer.shared.cachedBgService()
        let final2 = ConcurrencyTestContainer.shared.cachedBgService()
        XCTAssertEqual(final1.id, final2.id)
    }

    /// Inflight gate: concurrent threads resolving a slow cached factory should all get the same instance.
    /// The factory includes a deliberate sleep to widen the contention window.
    func testInflightGateDeduplicatesSlowFactory() {
        ConcurrencyTestContainer.shared.reset()

        let threadCount = 8
        let expectations = (0..<threadCount).map { expectation(description: "thread-\($0)") }
        let collectedIDs = LockedUUIDs()

        for i in 0..<threadCount {
            DispatchQueue.global().async {
                let s = ConcurrencyTestContainer.shared.slowCachedService()
                collectedIDs.append(s.id)
                expectations[i].fulfill()
            }
        }

        wait(for: expectations, timeout: 30)

        let uniqueIDs = Set(collectedIDs.values)
        XCTAssertEqual(uniqueIDs.count, 1, "Inflight gate should deduplicate; got \(uniqueIDs.count) distinct instances across \(threadCount) threads")
    }

    /// Thread-local graph depth: concurrent resolves on different threads should not corrupt
    /// each other's depth counter.
    func testThreadLocalGraphDepthIsolation() {
        let threadCount = 4
        let iterationsPerThread = 200
        let expectations = (0..<threadCount).map { expectation(description: "depth-\($0)") }

        for i in 0..<threadCount {
            DispatchQueue.global().async {
                for _ in 0..<iterationsPerThread {
                    // Each resolution increments then decrements depth.
                    // After completion, this thread's depth should be 0.
                    let _ = ConcurrencyTestContainer.shared.bgService()
                }
                // After all resolutions, thread-local depth should be back to 0
                let finalDepth = graphDepthGet()
                XCTAssertEqual(finalDepth, 0, "Thread \(i) depth should be 0 after all resolutions, got \(finalDepth)")
                expectations[i].fulfill()
            }
        }

        wait(for: expectations, timeout: 30)
    }

    /// Thread-local depth should remain 0 after nested factory resolutions complete,
    /// even when factories resolve other factories (graph depth > 1 during resolution).
    func testThreadLocalGraphDepthWithNestedResolution() {
        ConcurrencyTestContainer.shared.reset()

        let threadCount = 4
        let expectations = (0..<threadCount).map { expectation(description: "nested-\($0)") }

        for i in 0..<threadCount {
            DispatchQueue.global().async {
                for _ in 0..<100 {
                    // chainedService internally resolves bgService, so depth goes to 2
                    let _ = ConcurrencyTestContainer.shared.chainedService()
                }
                let finalDepth = graphDepthGet()
                XCTAssertEqual(finalDepth, 0, "Thread \(i) nested depth should be 0, got \(finalDepth)")
                expectations[i].fulfill()
            }
        }

        wait(for: expectations, timeout: 30)
    }

    /// Thread-local graph cache: concurrent threads resolving graph-scoped factories should each
    /// get their own isolated cache. One thread's graph cache reset at depth==0 should not wipe
    /// another thread's in-progress graph-scoped instances.
    func testThreadLocalGraphCacheIsolation() {
        ConcurrencyTestContainer.shared.reset()

        let threadCount = 8
        let iterationsPerThread = 100
        let expectations = (0..<threadCount).map { expectation(description: "graph-\($0)") }
        let failures = LockedUUIDs() // reuse as failure collector

        for i in 0..<threadCount {
            DispatchQueue.global().async {
                for _ in 0..<iterationsPerThread {
                    // graphChainedService is graph-scoped and internally resolves bgService.
                    // Within a single resolution cycle, graph scope should return the same instance.
                    // Across cycles, new instances should be created.
                    let _ = ConcurrencyTestContainer.shared.graphChainedService()
                }
                // After all resolutions, graph depth should be back to 0
                let finalDepth = graphDepthGet()
                if finalDepth != 0 {
                    failures.append(UUID()) // mark failure
                }
                XCTAssertEqual(finalDepth, 0, "Thread \(i) graph depth should be 0, got \(finalDepth)")
                expectations[i].fulfill()
            }
        }

        wait(for: expectations, timeout: 30)
        XCTAssertEqual(failures.values.count, 0, "Some threads had non-zero graph depth after completion")
    }

    /// Re-entrant guard: a factory that recursively resolves the same cached key should trigger
    /// a fatal error rather than deadlocking on the inflight gate's NSCondition.
    /// We disable the debug circular dependency chain check (dependencyChainTestMax = 0)
    /// so the re-entrant guard is the one that fires.
    @MainActor
    func testReentrantResolutionDetected() {
        ConcurrencyTestContainer.shared.reset()
        // Disable the debug circular dependency chain check so the re-entrant guard fires
        ConcurrencyTestContainer.shared.manager.dependencyChainTestMax = 0

        // Register a self-recursive cached factory — resolving it triggers re-entrant resolution
        // of the same scoped key on the same thread.
        ConcurrencyTestContainer.shared.cachedBgService.register {
            // This line will attempt to resolve the same cached key we're already resolving.
            let _ = ConcurrencyTestContainer.shared.cachedBgService()
            return ConcurrencyBgService()
        }

        let message = "FACTORY: Re-entrant resolution of the same scoped key detected. This is a circular dependency that would cause a deadlock."
        expectFatalError(expectedMessage: message) {
            let _ = ConcurrencyTestContainer.shared.cachedBgService()
        }
    }

    /// MainActorFactory and Factory with the same key + type should NOT share cache.
    /// Isolation namespacing prevents cross-isolation cache leaks where a non-MainActor Factory
    /// could retrieve a @MainActor-created instance and access it off the main actor.
    @MainActor
    func testKeyIsolationPreventsCrossIsolationCacheLeak() {
        CollisionContainer.shared.reset()

        let mainActorInstance = CollisionContainer.shared.mainActorCollisionCached()
        let nonMainInstance = CollisionContainer.shared.nonMainCollisionCached()

        XCTAssertNotEqual(mainActorInstance.id, nonMainInstance.id, "MainActor and non-MainActor keys should be isolated — no shared cache")
        XCTAssertEqual(mainActorInstance.value, 10, "MainActorFactory should use its own factory closure")
        XCTAssertEqual(nonMainInstance.value, 20, "Non-main Factory should use its own factory closure")
    }

    /// Key isolation should also prevent MainActorFactory from picking up non-main registrations.
    @MainActor
    func testKeyIsolationDoesNotShareRegistrations() {
        CollisionContainer.shared.reset()

        CollisionContainer.shared.nonMainCollisionUnique.register {
            CollisionService(value: 99)
        }

        let mainActorInstance = CollisionContainer.shared.mainActorCollisionUnique()
        XCTAssertEqual(mainActorInstance.value, 1, "MainActorFactory should ignore non-main registrations for the same key")

        let nonMainInstance = CollisionContainer.shared.nonMainCollisionUnique()
        XCTAssertEqual(nonMainInstance.value, 99, "Non-main Factory should use its own registration")
    }
}

// MARK: - Concurrency Test Support Types

/// Thread-safe flag for decorator verification
private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
    func set() {
        lock.lock()
        _value = true
        lock.unlock()
    }
}

/// Thread-safe array for collecting UUIDs across concurrent queues
private final class LockedUUIDs: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [UUID] = []
    func append(_ id: UUID) {
        lock.lock()
        _values.append(id)
        lock.unlock()
    }
    var values: [UUID] {
        lock.lock()
        defer { lock.unlock() }
        return _values
    }
}

private class ConcurrencyBgService {
    let id = UUID()
    let value: Int
    init(value: Int = 0) {
        self.value = value
    }
}

private class SlowCachedService {
    let id = UUID()
    init() {
        // Deliberate delay to widen the contention window for inflight gate testing
        Thread.sleep(forTimeInterval: 0.05)
    }
}

private class ChainedService {
    let bg: ConcurrencyBgService
    init(bg: ConcurrencyBgService) {
        self.bg = bg
    }
}

private class GraphScopedService {
    let id = UUID()
    init() {}
}

private final class CollisionService {
    let id = UUID()
    let value: Int
    init(value: Int) {
        self.value = value
    }
}

private final class ConcurrencyTestContainer: SharedContainer {
    static let shared = ConcurrencyTestContainer()
    var bgService: Factory<ConcurrencyBgService> { self { ConcurrencyBgService() } }
    var cachedBgService: Factory<ConcurrencyBgService> { self { ConcurrencyBgService() }.cached }
    var slowCachedService: Factory<SlowCachedService> { self { SlowCachedService() }.cached }
    var chainedService: Factory<ChainedService> { self { ChainedService(bg: self.bgService()) } }
    var graphService: Factory<GraphScopedService> { self { GraphScopedService() }.graph }
    var graphChainedService: Factory<ChainedService> { self { ChainedService(bg: self.bgService()) }.graph }
    let manager = ContainerManager()
}

private final class CollisionContainer: SharedContainer {
    static let shared = CollisionContainer()

    @MainActor var mainActorCollisionUnique: MainActorFactory<CollisionService> {
        MainActorFactory(self, key: "collision.unique") { CollisionService(value: 1) }
    }

    var nonMainCollisionUnique: Factory<CollisionService> {
        Factory(self, key: "collision.unique") { CollisionService(value: 2) }
    }

    @MainActor var mainActorCollisionCached: MainActorFactory<CollisionService> {
        MainActorFactory(self, key: "collision.cached") { CollisionService(value: 10) }.cached
    }

    var nonMainCollisionCached: Factory<CollisionService> {
        Factory(self, key: "collision.cached") { CollisionService(value: 20) }.cached
    }

    let manager = ContainerManager()
}

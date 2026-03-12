//
// MainActorFactory.swift
//
// GitHub Repo and Documentation: https://github.com/hmlongco/Factory
//
// Copyright © 2022-2025 Michael Long. All rights reserved.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.
//

import Foundation

// MARK: - MainActor Factory Type Aliases

/// Factory closure type that is guaranteed to run on the MainActor.
/// Note: the closure is `@Sendable`, so captured values must be Sendable under Swift 6 strict concurrency.
public typealias MainActorVoidFactoryType<T> = @MainActor @Sendable () -> T

/// Parameter factory closure type that is guaranteed to run on the MainActor.
/// Note: the closure is `@Sendable`, so captured values must be Sendable under Swift 6 strict concurrency.
public typealias MainActorParameterFactoryType<P, T> = @MainActor @Sendable (P) -> T

// MARK: - MainActorFactory

/// A Factory whose resolution is guaranteed to occur on the MainActor.
///
/// Use `MainActorFactory` when the dependency being created is `@MainActor`-isolated (e.g., view models
/// that touch `@Published` properties or UIKit components). The compiler enforces that resolution only
/// happens from a `@MainActor` context — no `MainActor.assumeIsolated` needed.
///
/// ## Defining a MainActorFactory
/// ```swift
/// extension Container {
///     @MainActor var dashboardViewModel: MainActorFactory<DashboardViewModel> {
///         MainActorFactory(self) { DashboardViewModel() }
///     }
/// }
/// ```
///
/// ## Resolving
/// ```swift
/// @MainActor
/// func showDashboard() {
///     let vm = Container.shared.dashboardViewModel()
///     // ...
/// }
/// ```
///
/// Attempting to resolve from a non-isolated context produces a compile-time error.
///
/// ## Scopes and Modifiers
/// `MainActorFactory` supports all the same modifiers as `Factory` — `.cached`, `.shared`, `.singleton`,
/// `.scope()`, `.decorator()`, `.context()`, `.once()`, and `.reset()`.
@MainActor
public struct MainActorFactory<T>: MainActorFactoryModifying {

    /// Public initializer creates a MainActorFactory capable of managing @MainActor dependencies.
    ///
    /// - Parameters:
    ///   - container: The bound container that manages registrations and scope caching for this Factory.
    ///   - key: Hidden value used to differentiate different instances of the same type in the same container.
    ///   - factory: A @MainActor factory closure that produces an object of the desired type when required.
    public init(_ container: ManagedContainer, key: StaticString = #function, _ factory: @escaping MainActorVoidFactoryType<T>) {
        self.registration = MainActorFactoryRegistration<Void, T>(key: key, container: container, factory: factory)
    }

    /// Evaluates the factory on the MainActor and returns an object or service of the desired type.
    ///
    /// ```swift
    /// let vm = Container.shared.dashboardViewModel()
    /// ```
    /// - Returns: An object or service of the desired type.
    public func callAsFunction() -> T {
        registration.resolve(with: ())
    }

    /// Unsugared resolution function.
    public func resolve() -> T {
        registration.resolve(with: ())
    }

    /// Registers a new @MainActor factory closure capable of producing an object or service of the desired type.
    ///
    /// ```swift
    /// container.dashboardViewModel.register {
    ///     MockDashboardViewModel()
    /// }
    /// ```
    @discardableResult
    public func register(factory: @escaping MainActorVoidFactoryType<T>) -> Self {
        registration.register(factory)
        return self
    }

    /// Internal registration that manages this Factory's resolution, scoping, and caching.
    public var registration: MainActorFactoryRegistration<Void, T>

}

extension MainActorFactory: @unchecked Sendable where T: Sendable {}

// MARK: - MainActorParameterFactory

/// A Factory whose resolution is guaranteed to occur on the MainActor, and which accepts a parameter at resolution time.
///
/// Use `MainActorParameterFactory` when you need to pass a delegate, configuration, or other parameter
/// to a `@MainActor`-isolated dependency at the point of resolution.
///
/// ## Defining a MainActorParameterFactory
/// ```swift
/// extension Container {
///     @MainActor var detailViewModel: MainActorParameterFactory<DetailViewModelDelegate, DetailViewModel> {
///         MainActorParameterFactory(self) { delegate in
///             DetailViewModel(delegate: delegate)
///         }
///     }
/// }
/// ```
///
/// ## Resolving
/// ```swift
/// @MainActor
/// func showDetail() {
///     let vm = Container.shared.detailViewModel(self) // self is the delegate
///     // ...
/// }
/// ```
@MainActor
public struct MainActorParameterFactory<P, T>: MainActorFactoryModifying {

    /// Public initializer creates a MainActorParameterFactory capable of taking parameters at runtime.
    ///
    /// - Parameters:
    ///   - container: The bound container that manages registrations and scope caching for this Factory.
    ///   - key: Hidden value used to differentiate different instances of the same type in the same container.
    ///   - factory: A @MainActor factory closure that takes a parameter and produces an object of the desired type.
    public init(_ container: ManagedContainer, key: StaticString = #function, _ factory: @escaping MainActorParameterFactoryType<P, T>) {
        self.registration = MainActorFactoryRegistration<P, T>(key: key, container: container, factory: factory)
    }

    /// Resolves the factory with the given parameter on the MainActor.
    ///
    /// ```swift
    /// let vm = container.detailViewModel(self)
    /// ```
    public func callAsFunction(_ parameters: P) -> T {
        registration.resolve(with: parameters)
    }

    /// Unsugared resolution function.
    public func resolve(_ parameters: P) -> T {
        registration.resolve(with: parameters)
    }

    /// Registers a new @MainActor factory closure capable of taking parameters at runtime.
    ///
    /// ```swift
    /// container.detailViewModel.register { delegate in
    ///     MockDetailViewModel(delegate: delegate)
    /// }
    /// ```
    @discardableResult
    public func register(factory: @escaping MainActorParameterFactoryType<P, T>) -> Self {
        registration.register(factory)
        return self
    }

    /// Internal registration that manages this Factory's resolution, scoping, and caching.
    public var registration: MainActorFactoryRegistration<P, T>

}

extension MainActorParameterFactory: @unchecked Sendable where T: Sendable {}

// MARK: - MainActorFactoryRegistration

/// Registration type for MainActorFactory and MainActorParameterFactory.
///
/// This mirrors `FactoryRegistration` but stores `@MainActor`-isolated closures and resolves on the MainActor.
/// It reuses the same `ContainerManager` infrastructure (registrations, scopes, caches) as the standard
/// `FactoryRegistration`, ensuring full compatibility with existing container behavior.
@MainActor
public struct MainActorFactoryRegistration<P, T>: @unchecked Sendable {

    /// Key used to manage registrations and cached values.
    internal let key: FactoryKey
    /// A strong reference to the container supporting this Factory.
    internal let container: ManagedContainer
    /// Typed MainActor-isolated factory closure.
    internal let factory: MainActorParameterFactoryType<P, T>

    #if DEBUG
    /// Internal debug
    internal let debug: FactoryDebugInformation
    #endif

    /// Mutable once flag
    internal var once: Bool = false

    /// Initializer for registration.
    internal init(key: StaticString, container: ManagedContainer, factory: @escaping MainActorParameterFactoryType<P, T>) {
        self.key = FactoryKey(type: T.self, key: key, isolation: .mainActor)
        self.container = container
        self.factory = factory
        #if DEBUG
        self.debug = .init(type: self.key.typeName, key: key)
        #endif
    }

    /// Support function for one-time only option updates
    internal func unsafeCanUpdateOptions() -> Bool {
        let options = container.manager.options[key]
        return options == nil || options?.once == once
    }

    /// Resolves a MainActorFactory, returning an instance of the desired type. All roads lead here.
    ///
    /// This method mirrors `FactoryRegistration.resolve(with:)` but executes on the MainActor.
    /// It uses the same container manager infrastructure (registrations, options, scope caches),
    /// but keys are namespaced by isolation domain to prevent cross-isolation cache leaks.
    ///
    /// Uses a split-lock pattern identical to `FactoryRegistration.resolve(with:)`:
    ///   - **Phase 1 (locked):** Read metadata, select factory, check scope cache (fast-path return on hit).
    ///     If a scoped cache-miss occurs, check for an inflight resolution by another thread. If one exists,
    ///     wait for it to complete and re-check the cache. Otherwise, claim the key and proceed.
    ///   - **Phase 2 (unlocked):** Execute the user's `@MainActor` factory closure.
    ///   - **Phase 3 (locked):** Store result in scope cache, signal inflight waiters, update graph depth.
    ///   - **Phase 4 (unlocked):** Run decorators.
    ///
    /// Factory closures maintain full `@MainActor` typing throughout. The split-lock pattern calls
    /// `scope.cachedValue(...)` and `scope.store(...)` directly (not `Scope.resolve`), so the
    /// `@MainActor` closure is invoked during Phase 2 within this `@MainActor`-isolated method
    /// — no erasure or bridging is needed.
    ///
    /// The inflight gate ensures that concurrent cache-miss resolvers for the same scoped key produce
    /// exactly one instance (the first to complete), preventing duplicate creations under contention.
    ///
    /// - Parameter parameters: The parameter to pass to the factory closure (Void for MainActorFactory).
    /// - Returns: Instance of the desired type.
    internal func resolve(with parameters: P) -> T {

        // ──────────────────────────────────────────────
        // Phase 1: Locked — read metadata + cache check
        // ──────────────────────────────────────────────
        #if DEBUG
        let lockWaitStart = CFAbsoluteTimeGetCurrent()
        #endif

        globalRecursiveLock.lock()

        #if DEBUG
        let lockAcquireTime = CFAbsoluteTimeGetCurrent() - lockWaitStart
        // Warn when MainActor blocks on the global lock for more than 16ms (one frame at 60fps).
        // This indicates background factory resolution is holding the lock and causing UI hitches.
        if lockAcquireTime > 0.016 {
            globalLogger("FACTORY WARNING: MainActor blocked \(String(format: "%.1f", lockAcquireTime * 1000))ms waiting for globalRecursiveLock during resolution of \(debug.key). Consider reducing lock contention from background factory resolutions.")
        }
        #endif

        container.unsafeCheckAutoRegistration()

        let manager = container.manager
        let options = manager.options[key]

        // Factory closure keeps its @MainActor isolation — no nonisolated(unsafe) needed.
        // The Scope.resolve @MainActor overload handles the isolation bridge.
        var current: @MainActor (P) -> T

        #if DEBUG
        var traceResolutions = threadTraceResolutionsGet()
        let traceLevel: Int = traceResolutions.count
        var traceNew: String?
        var traceNewType: String?
        #endif

        if let found = options?.factoryForCurrentContext() as? MainActorTypedFactory<P, T> {
            #if DEBUG
            traceNewType = "O"
            #endif
            current = found.factory
        } else if let found = manager.registrations[key] as? MainActorTypedFactory<P, T> {
            #if DEBUG
            traceNewType = "R"
            #endif
            current = found.factory
        } else {
            #if DEBUG
            traceNewType = "F"
            #endif
            current = factory
        }

        #if DEBUG
        if manager.dependencyChainTestMax > 0 {
            circularDependencyChainCheck(max: manager.dependencyChainTestMax)
        }
        #endif

        let scope = options?.scope ?? manager.defaultScope
        let parameterizedKey = (scope != nil && options?.scopeOnParameters == true) ? key.parameterized(parameters) : key
        let ttl = options?.ttl
        let cache = manager.cache
        var ownsInflightEntry = false

        // Fast path: scope cache hit — run decorators but skip factory execution
        if let scope = scope {
            if let cached: T = scope.cachedValue(using: cache, key: parameterizedKey, ttl: ttl) {
                #if DEBUG
                // Trace: record cache hit
                if manager.trace {
                    traceResolutions.append("")
                    let depth = graphDepthInc()
                    let indent = String(repeating: "    ", count: depth - 1)
                    let address = Int(bitPattern: ObjectIdentifier(cached as AnyObject))
                    traceResolutions[traceLevel] = "\(depth - 1): \(indent)\(container).\(debug.key) = C:\(address) \(type(of: cached as Any))"
                    graphDepthDec()
                    if graphDepthGet() == 0 {
                        traceResolutions.forEach { globalLogger($0) }
                        traceResolutions = []
                    }
                    threadTraceResolutionsSet(traceResolutions)
                }
                var depChain = threadDependencyChainGet()
                if !depChain.isEmpty {
                    depChain.removeLast()
                    threadDependencyChainSet(depChain)
                }
                #endif
                // Capture decorator references while still under lock
                let factoryDecorator = (options?.decorator as? TypedDecoratorBox<T>)?.decorator
                let containerDecorator = manager.decorator
                globalRecursiveLock.unlock()
                // Run decorators even on cache hits (matches original behavior)
                if let decorator = factoryDecorator {
                    decorator(cached)
                }
                if let decorator = containerDecorator {
                    decorator(cached)
                }
                return cached
            }

            // Re-entrant guard: if this thread is already resolving this key, it's a circular
            // dependency that would deadlock on the inflight gate. Fail fast.
            if !resolvingKeysInsert(parameterizedKey) {
                // Don't remove the key — the original in-progress resolution owns it.
                globalRecursiveLock.unlock()
                let message = "FACTORY: Re-entrant resolution of the same scoped key detected. This is a circular dependency that would cause a deadlock."
                #if DEBUG
                resetAndTriggerFatalError(message, #file, #line)
                #else
                fatalError(message)
                #endif
            }

            // Inflight gate: another thread is already creating an instance for this key.
            // Wait for it to finish, then re-check the cache.
            if let inflight = manager.inflight[parameterizedKey] {
                inflight.waiters += 1
                globalRecursiveLock.unlock()

                inflight.condition.lock()
                while !inflight.completed {
                    inflight.condition.wait()
                }
                inflight.condition.unlock()

                // Re-acquire lock to check the now-populated cache
                globalRecursiveLock.lock()
                resolvingKeysRemove(parameterizedKey)
                if let cached: T = scope.cachedValue(using: cache, key: parameterizedKey, ttl: ttl) {
                    #if DEBUG
                    var depChainW = threadDependencyChainGet()
                    if !depChainW.isEmpty {
                        depChainW.removeLast()
                        threadDependencyChainSet(depChainW)
                    }
                    #endif
                    // Capture decorator references while still under lock
                    let factoryDecoratorW = (options?.decorator as? TypedDecoratorBox<T>)?.decorator
                    let containerDecoratorW = manager.decorator
                    globalRecursiveLock.unlock()
                    // Run decorators even on cache hits (matches original behavior)
                    if let decorator = factoryDecoratorW {
                        decorator(cached)
                    }
                    if let decorator = containerDecoratorW {
                        decorator(cached)
                    }
                    return cached
                }
                // Cache was evicted between signal and re-lock — fall through to create a new instance.
                // Re-insert into resolving set since we're about to create.
                resolvingKeysInsert(parameterizedKey)
            }

            // Claim this key: we are the thread that will execute the factory.
            if manager.inflight[parameterizedKey] == nil {
                let inflightEntry = InflightResolution()
                manager.inflight[parameterizedKey] = inflightEntry
                ownsInflightEntry = true
            }
        }

        #if DEBUG
        if manager.trace {
            let wrapped = current
            current = {
                traceNew = traceNewType
                return wrapped($0)
            }
            traceResolutions.append("")
            threadTraceResolutionsSet(traceResolutions)
        }
        #endif

        graphDepthInc()

        // Capture decorator references while still under lock
        let factoryDecorator = (options?.decorator as? TypedDecoratorBox<T>)?.decorator
        let containerDecorator = manager.decorator

        globalRecursiveLock.unlock()

        // ──────────────────────────────────────────────
        // Phase 2: Unlocked — execute @MainActor factory
        // ──────────────────────────────────────────────
        let instance: T = current(parameters)

        // ──────────────────────────────────────────────
        // Phase 3: Locked — store in cache + bookkeeping
        // ──────────────────────────────────────────────
        globalRecursiveLock.lock()

        if let scope = scope {
            scope.store(instance, using: cache, key: parameterizedKey)
        }

        // Signal inflight waiters and remove entry (only if we own it)
        if ownsInflightEntry, let inflight = manager.inflight.removeValue(forKey: parameterizedKey) {
            inflight.condition.lock()
            inflight.completed = true
            inflight.condition.broadcast()
            inflight.condition.unlock()
        }

        // Remove from thread-local resolving set now that the instance is cached
        resolvingKeysRemove(parameterizedKey)

        let currentDepth = graphDepthDec()

        if currentDepth == 0 {
            threadGraphCacheReset()
            #if DEBUG
            threadDependencyChainMessagesSet([])
            #endif
        }

        #if DEBUG
        var depChain = threadDependencyChainGet()
        if !depChain.isEmpty {
            depChain.removeLast()
            threadDependencyChainSet(depChain)
        }

        if manager.trace {
            var traceRes = threadTraceResolutionsGet()
            let indent = String(repeating: "    ", count: currentDepth)
            let address = Int(bitPattern: ObjectIdentifier(instance as AnyObject))
            let resolution = "\(traceNew ?? "C"):\(address) \(type(of: instance as Any))"
            if traceRes.count > traceLevel {
                traceRes[traceLevel] = "\(currentDepth): \(indent)\(container).\(debug.key) = \(resolution)"
            }
            if currentDepth == 0 {
                traceRes.forEach { globalLogger($0) }
                traceRes = []
            }
            threadTraceResolutionsSet(traceRes)
        }
        #endif

        globalRecursiveLock.unlock()

        // ──────────────────────────────────────────────
        // Phase 4: Unlocked — run decorators
        // ──────────────────────────────────────────────
        if let decorator = factoryDecorator {
            decorator(instance)
        }
        if let decorator = containerDecorator {
            decorator(instance)
        }

        return instance
    }

    /// Registers a new @MainActor factory closure.
    internal func register(_ factory: @escaping @MainActor @Sendable (P) -> T) {
        defer { globalRecursiveLock.unlock() }
        globalRecursiveLock.lock()
        container.unsafeCheckAutoRegistration()
        if unsafeCanUpdateOptions() {
            let manager = container.manager
            manager.registrations[key] = MainActorTypedFactory(factory: factory)
            if manager.autoRegistering == false, let scope = manager.options[key]?.scope {
                let cache = (scope as? InternalScopeCaching)?.cache ?? manager.cache
                cache.removeValue(forKey: key)
            }
        }
    }

    /// Registers a new factory scope.
    internal func scope(_ scope: Scope?) {
        defer { globalRecursiveLock.unlock() }
        globalRecursiveLock.lock()
        container.unsafeCheckAutoRegistration()
        let manager = container.manager
        if var options = manager.options[key] {
            if once == options.once && scope !== options.scope {
                options.scope = scope
                manager.options[key] = options
                manager.cache.removeValue(forKey: key)
            }
        } else {
            manager.options[key] = FactoryOptions(scope: scope)
        }
    }

    /// Registers a new context.
    internal func context(_ context: FactoryContextType, key: FactoryKey, factory: @escaping @MainActor @Sendable (P) -> T) {
        options { options in
            switch context {
            case .arg(let arg):
                if options.argumentContexts == nil {
                    options.argumentContexts = [:]
                }
                options.argumentContexts?[arg] = MainActorTypedFactory(factory: factory)
            case .args(let args):
                if options.argumentContexts == nil {
                    options.argumentContexts = [:]
                }
                args.forEach { arg in
                    options.argumentContexts?[arg] = MainActorTypedFactory(factory: factory)
                }
            default:
                if options.contexts == nil {
                    options.contexts = [:]
                }
                options.contexts?["\(context)"] = MainActorTypedFactory(factory: factory)
            }
        }
    }

    /// Registers a new decorator.
    internal func decorator(_ decorator: @escaping (T) -> Void) {
        options { options in
            options.decorator = TypedDecoratorBox(decorator: decorator)
        }
    }

    /// Support function for options mutation.
    internal func options(mutate: (_ options: inout FactoryOptions) -> Void) {
        defer { globalRecursiveLock.unlock() }
        globalRecursiveLock.lock()
        container.unsafeCheckAutoRegistration()
        let manager = container.manager
        var options = manager.options[key, default: FactoryOptions()]
        if options.once == once {
            mutate(&options)
            manager.options[key] = options
        }
    }

    /// Resets the behavior for a specific Factory to its original state.
    internal func reset(options: FactoryResetOptions) {
        defer { globalRecursiveLock.unlock() }
        globalRecursiveLock.lock()
        let manager = container.manager
        switch options {
        case .all:
            let cache = (manager.options[key]?.scope as? InternalScopeCaching)?.cache ?? manager.cache
            cache.removeValue(forKey: key)
            manager.registrations.removeValue(forKey: key)
            manager.options.removeValue(forKey: key)
        case .context:
            self.options {
                $0.argumentContexts = nil
                $0.contexts = nil
            }
        case .none:
            break
        case .registration:
            manager.registrations.removeValue(forKey: key)
        case .scope:
            let cache = (manager.options[key]?.scope as? InternalScopeCaching)?.cache ?? manager.cache
            cache.removeValue(forKey: key)
        }
    }

    #if DEBUG
    internal func circularDependencyChainCheck(max: Int) {
        let typeComponents = debug.type.components(separatedBy: CharacterSet(charactersIn: "<>"))
        let typeName = typeComponents.count > 1 ? typeComponents[1] : typeComponents[0]
        var depChain = threadDependencyChainGet()
        let typeIndex = depChain.firstIndex(where: { $0 == typeName })
        depChain.append(typeName)
        if let index = typeIndex {
            let chain = depChain[index...]
            let message = "FACTORY: Circular dependency chain - \(chain.joined(separator: " > "))"
            var depMessages = threadDependencyChainMessagesGet()
            if depMessages.filter({ $0 == message }).count == max {
                resetAndTriggerFatalError(message, #file, #line)
            } else {
                threadDependencyChainSet([typeName])
                depMessages.append(message)
                threadDependencyChainMessagesSet(depMessages)
                return
            }
        }
        threadDependencyChainSet(depChain)
    }
    #endif

}

// MARK: - MainActorTypedFactory

/// Internal factory storage type for @MainActor-isolated closures.
/// This is the MainActor counterpart of `TypedFactory` — it conforms to `AnyFactory`
/// so it can be stored in the same `ContainerManager.registrations` dictionary.
internal struct MainActorTypedFactory<P, T>: AnyFactory {
    let factory: @MainActor @Sendable (P) -> T
}

// MARK: - MainActorFactoryModifying

/// Public protocol with functionality common to MainActorFactory types.
/// This is the @MainActor counterpart of `FactoryModifying`.
@MainActor
public protocol MainActorFactoryModifying {

    /// The parameter type of the Factory, if any. Will be `Void` on MainActorFactory.
    associatedtype P

    /// The return type of the Factory's dependency.
    associatedtype T

    /// Internal registration information.
    var registration: MainActorFactoryRegistration<P, T> { get set }

}

// MARK: - MainActorFactoryModifying Scope Functionality

extension MainActorFactoryModifying {

    /// Defines a dependency scope for this Factory. See ``Scope``.
    @discardableResult
    public func scope(_ scope: Scope) -> Self {
        registration.scope(scope)
        return self
    }

    /// Syntactic sugar defines this Factory's dependency scope to be cached.
    public var cached: Self {
        registration.scope(.cached)
        return self
    }

    /// Syntactic sugar defines this Factory's dependency scope to be graph.
    public var graph: Self {
        registration.scope(.graph)
        return self
    }

    /// Syntactic sugar defines this Factory's dependency scope to be shared.
    public var shared: Self {
        registration.scope(.shared)
        return self
    }

    /// Syntactic sugar defines this Factory's dependency scope to be singleton.
    public var singleton: Self {
        registration.scope(.singleton)
        return self
    }

    /// Syntactic sugar defines unique scope.
    public var unique: Self {
        registration.scope(.unique)
        return self
    }

    /// Adds time to live option for scopes.
    @discardableResult
    public func timeToLive(_ seconds: TimeInterval) -> Self {
        registration.options { options in
            options.ttl = seconds
        }
        return self
    }

}

// MARK: - MainActorFactoryModifying Decorator Functionality

extension MainActorFactoryModifying {

    /// Adds a factory specific decorator.
    @discardableResult
    public func decorator(_ decorator: @escaping @Sendable (_ instance: T) -> Void) -> Self {
        registration.decorator(decorator)
        return self
    }

}

// MARK: - MainActorFactoryModifying Context Functionality

extension MainActorFactoryModifying {

    /// Registers a factory closure to be used only when running in a specific context.
    @discardableResult
    public func context(_ contexts: FactoryContextType..., factory: @escaping MainActorParameterFactoryType<P, T>) -> Self {
        for context in contexts {
            switch context {
            case .arg, .args, .device, .simulator:
                registration.context(context, key: registration.key, factory: factory)
            default:
                #if DEBUG
                registration.context(context, key: registration.key, factory: factory)
                #endif
                break
            }
        }
        return self
    }

    /// Factory builder shortcut for context(.arg("test")) { .. }
    @discardableResult
    public func onArg(_ argument: String, factory: @escaping MainActorParameterFactoryType<P, T>) -> Self {
        context(.arg(argument), factory: factory)
    }

    /// Factory builder shortcut for context(.args(["test1","test2"])) { .. }
    @discardableResult
    public func onArgs(_ args: [String], factory: @escaping MainActorParameterFactoryType<P, T>) -> Self {
        context(.args(args), factory: factory)
    }

    /// Factory builder shortcut for context(.preview) { .. }
    @discardableResult
    public func onPreview(factory: @escaping MainActorParameterFactoryType<P, T>) -> Self {
        context(.preview, factory: factory)
    }

    /// Factory builder shortcut for context(.test) { .. }
    @discardableResult
    public func onTest(factory: @escaping MainActorParameterFactoryType<P, T>) -> Self {
        context(.test, factory: factory)
    }

    /// Factory builder shortcut for context(.debug) { .. }
    @discardableResult
    public func onDebug(factory: @escaping MainActorParameterFactoryType<P, T>) -> Self {
        context(.debug, factory: factory)
    }

    /// Factory builder shortcut for context(.simulator) { .. }
    @discardableResult
    public func onSimulator(factory: @escaping MainActorParameterFactoryType<P, T>) -> Self {
        context(.simulator, factory: factory)
    }

    /// Factory builder shortcut for context(.device) { .. }
    @discardableResult
    public func onDevice(factory: @escaping MainActorParameterFactoryType<P, T>) -> Self {
        context(.device, factory: factory)
    }

}

// MARK: - MainActorFactoryModifying Once Functionality

extension MainActorFactoryModifying {

    /// Adds ability to mutate Factory on first instantiation only.
    @discardableResult
    public func once() -> Self {
        registration.options { options in
            options.once = true
        }
        var mutable = self
        mutable.registration.once = true
        return mutable
    }

}

// MARK: - MainActorFactoryModifying Common Functionality

extension MainActorFactoryModifying {

    /// Resets the Factory's behavior to its original state.
    @discardableResult
    public func reset(_ options: FactoryResetOptions = .all) -> Self {
        registration.reset(options: options)
        return self
    }

}

// MARK: - MainActorParameterFactory Scope On Parameters

extension MainActorFactoryModifying where P: Hashable {

    /// Enables per-parameter scope caching for MainActorParameterFactory.
    public var scopeOnParameters: Self {
        registration.options { options in
            options.scopeOnParameters = true
        }
        return self
    }

}

// MARK: - ManagedContainer MainActor Sugar

extension ManagedContainer {

    /// Syntactic sugar allows container to create a properly bound MainActorFactory.
    ///
    /// ```swift
    /// extension Container {
    ///     @MainActor var viewModel: MainActorFactory<MyViewModel> {
    ///         mainActor { MyViewModel() }
    ///     }
    /// }
    /// ```
    @MainActor @inlinable @inline(__always) public func mainActor<T>(
        key: StaticString = #function,
        _ factory: @escaping MainActorVoidFactoryType<T>
    ) -> MainActorFactory<T> {
        MainActorFactory(self, key: key, factory)
    }

    /// Syntactic sugar allows container to create a properly bound MainActorParameterFactory.
    ///
    /// ```swift
    /// extension Container {
    ///     @MainActor var detailViewModel: MainActorParameterFactory<Delegate, DetailViewModel> {
    ///         mainActor { delegate in DetailViewModel(delegate: delegate) }
    ///     }
    /// }
    /// ```
    @MainActor @inlinable @inline(__always) public func mainActor<P, T>(
        key: StaticString = #function,
        _ factory: @escaping MainActorParameterFactoryType<P, T>
    ) -> MainActorParameterFactory<P, T> {
        MainActorParameterFactory(self, key: key, factory)
    }

}

// MARK: - Resolutions for MainActorFactory

/// Global function to resolve a keypath on Container.shared into the requested type on the MainActor.
///
/// ```swift
/// @MainActor
/// @State var model: ContentViewModel = resolveOnMainActor(\.contentViewModel)
/// ```
@MainActor
public func resolveOnMainActor<T>(_ keyPath: KeyPath<Container, MainActorFactory<T>>) -> T {
    Container.shared[keyPath: keyPath]()
}

/// Global function to resolve a keypath on the specified shared container into the requested type on the MainActor.
@MainActor
public func resolveOnMainActor<C: SharedContainer, T>(_ keyPath: KeyPath<C, MainActorFactory<T>>) -> T {
    C.shared[keyPath: keyPath]()
}

// MARK: - SwiftUI Support

#if canImport(SwiftUI)
import SwiftUI

extension MainActorFactory {
    /// Defines a convenience function that allows easy mocking in SwiftUI Previews.
    /// ```swift
    /// #Preview {
    ///     Container.shared.myViewModel.preview { MockViewModel() }
    ///     MainView()
    /// }
    /// ```
    @discardableResult
    public func preview(factory: @escaping MainActorVoidFactoryType<T>) -> EmptyView {
        registration.register(factory)
        return EmptyView()
    }
}

extension MainActorParameterFactory {
    /// Defines a convenience function that allows easy mocking in SwiftUI Previews.
    @discardableResult
    public func preview(factory: @escaping MainActorParameterFactoryType<P, T>) -> EmptyView {
        registration.register(factory)
        return EmptyView()
    }
}
#endif

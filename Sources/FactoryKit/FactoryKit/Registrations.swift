//
// Registrations.swift
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

/// Shared registration type for Factory and ParameterFactory. Used internally to manage the registration and resolution process.
public struct FactoryRegistration<P,T>: Sendable {

    /// Key used to manage registrations and cached values.
    internal let key: FactoryKey
    /// A strong reference to the container supporting this Factory.
    internal let container: ManagedContainer
    /// Typed factory with scope and factory.
    internal let factory: ParameterFactoryType<P, T>

    #if DEBUG
    /// Internal debug
    internal let debug: FactoryDebugInformation
    #endif

    /// Mutable once flag
    internal var once: Bool = false

    /// Initializer for registration sets passed values and default scope from container manager.
    internal init(key: StaticString, container: ManagedContainer, factory: @escaping ParameterFactoryType<P,T>) {
        self.key = FactoryKey(type: T.self, key: key)
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

    /// Resolves a Factory, returning an instance of the desired type. All roads lead here.
    ///
    /// Resolution uses a split-lock pattern to avoid holding the global lock while executing user factory
    /// closures and decorators:
    ///   - **Phase 1 (locked):** Read metadata, select factory, check scope cache (fast-path return on hit).
    ///     If a scoped cache-miss occurs, check for an inflight resolution by another thread. If one exists,
    ///     wait for it to complete and re-check the cache. Otherwise, claim the key and proceed.
    ///   - **Phase 2 (unlocked):** Execute the user's factory closure.
    ///   - **Phase 3 (locked):** Store result in scope cache, signal inflight waiters, update graph depth.
    ///   - **Phase 4 (unlocked):** Run decorators.
    ///
    /// The inflight gate ensures that concurrent cache-miss resolvers for the same scoped key produce
    /// exactly one instance (the first to complete), preventing duplicate creations under contention.
    ///
    /// - Parameter parameters: The parameter to pass to the factory closure (Void for Factory).
    /// - Returns: Instance of the desired type.
    internal func resolve(with parameters: P) -> T {

        // ──────────────────────────────────────────────
        // Phase 1: Locked — read metadata + cache check
        // ──────────────────────────────────────────────
        globalRecursiveLock.lock()

        container.unsafeCheckAutoRegistration()

        let manager = container.manager
        let options = manager.options[key]

        var current: (P) -> T

        #if DEBUG
        var traceResolutions = threadTraceResolutionsGet()
        let traceLevel: Int = traceResolutions.count
        var traceNew: String?
        var traceNewType: String?
        #endif

        if let found = options?.factoryForCurrentContext() as? TypedFactory<P,T> {
            #if DEBUG
            traceNewType = "O"
            #endif
            current = found.factory
        } else if let found = manager.registrations[key] as? TypedFactory<P,T> {
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
            // Don't remove the key — the original in-progress resolution owns it.
            if !resolvingKeysInsert(parameterizedKey) {
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
        // Phase 2: Unlocked — execute factory closure
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

    /// Registers a new factory closure capable of producing an object or service of the desired type. This factory overrides the original factory and
    /// the next time this factory is resolved Factory will evaluate the newly registered factory instead.
    /// - Parameters:
    ///   - id: ID of associated Factory.
    ///   - factory: Factory closure called to create a new instance of the service when needed.
    internal func register(_ factory: @escaping @Sendable (P) -> T) {
        defer { globalRecursiveLock.unlock()  }
        globalRecursiveLock.lock()
        container.unsafeCheckAutoRegistration()
        if unsafeCanUpdateOptions() {
            let manager = container.manager
            manager.registrations[key] = TypedFactory(factory: factory)
            if manager.autoRegistering == false, let scope = manager.options[key]?.scope {
                let cache = (scope as? InternalScopeCaching)?.cache ?? manager.cache
                cache.removeValue(forKey: key)
            }
        }
    }

    /// Registers a new factory scope.
    /// - Parameter: - scope: New scope
    internal func scope(_ scope: Scope?) {
        defer { globalRecursiveLock.unlock()  }
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
    internal func context(_ context: FactoryContextType, key: FactoryKey, factory: @escaping @Sendable (P) -> T) {
        options { options in
            switch context {
            case .arg(let arg):
                if options.argumentContexts == nil {
                    options.argumentContexts = [:]
                }
                options.argumentContexts?[arg] = TypedFactory(factory: factory)
            case .args(let args):
                if options.argumentContexts == nil {
                    options.argumentContexts = [:]
                }
                args.forEach { arg in
                    options.argumentContexts?[arg] = TypedFactory(factory: factory)
                }
            default:
                if options.contexts == nil {
                    options.contexts = [:]
                }
                options.contexts?["\(context)"] = TypedFactory(factory: factory)
            }
            // #146 container.manager.cache.removeValue(forKey: key)
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
        defer { globalRecursiveLock.unlock()  }
        globalRecursiveLock.lock()
        container.unsafeCheckAutoRegistration()
        let manager = container.manager
        var options = manager.options[key, default: FactoryOptions()]
        if options.once == once {
            mutate(&options)
            manager.options[key] = options
        }
    }

    /// Support function resets the behavior for a specific Factory to its original state, removing any associated registrations and clearing
    /// any cached instances from the specified scope.
    /// - Parameters:
    ///   - options: Reset option: .all, .registration, .scope, .none
    ///   - id: ID of item to remove from the appropriate cache.
    internal func reset(options: FactoryResetOptions) {
        defer { globalRecursiveLock.unlock()  }
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

// MARK: - Protocols and Types

/// Reset options for Factory's and Container's
public enum FactoryResetOptions {
    /// Resets registration and scope caches
    case all
    /// Performs no reset actions on this container
    case none
    /// Resets registrations on this container
    case registration
    /// Resets context-based registrations on this container
    case context
    /// Resets all scope caches on this container
    case scope
}

/// Type-safe wrapper for factory decorators.
///
/// Wrapping the decorator in a generic struct makes the `as?` downcast match on the struct's
/// generic parameter rather than on bare function-type metadata. This is more robust against
/// future Swift runtime changes to function type casting (e.g., stricter `@Sendable` / `@MainActor`
/// attribute matching) and eliminates silent cast failures.
internal struct TypedDecoratorBox<T> {
    let decorator: (T) -> Void
}

internal struct FactoryOptions {
    /// Managed scope for this factory instance
    var scope: Scope?
    /// Scope cache value also based on ParameterFactory parameter
    var scopeOnParameters: Bool = false
    /// Time to live option for scopes
    var ttl: TimeInterval?
    /// Contexts
    var argumentContexts: [String:AnyFactory]?
    /// Contexts
    var contexts: [String:AnyFactory]?
    /// Decorator will be passed fully constructed instance for further configuration.
    /// Stored as `TypedDecoratorBox<T>` erased to `Any?` for type-safe retrieval.
    var decorator: Any?
    /// Once flag for options
    var once: Bool = false
}

extension FactoryOptions {
    /// Internal function to return factory based on current context
    func factoryForCurrentContext() -> AnyFactory?  {
        if let contexts = argumentContexts, !contexts.isEmpty {
            for arg in FactoryContext.current.arguments {
                if let found = contexts[arg] {
                    return found
                }
            }
            for (_, arg) in FactoryContext.current.runtimeArguments {
                if let found = contexts[arg] {
                    return found
                }
            }
        }
        if let contexts = contexts, !contexts.isEmpty {
            #if DEBUG
            if FactoryContext.current.isPreview, let found = contexts["preview"] {
                return found
            }
            if FactoryContext.current.isTest, let found = contexts["test"] {
                return found
            }
            #endif
            if FactoryContext.current.isSimulator, let found = contexts["simulator"] {
                return found
            }
            if !FactoryContext.current.isSimulator, let found = contexts["device"] {
                return found
            }
            #if DEBUG
            if let found = contexts["debug"] {
                return found
            }
            #endif
        }
        return nil
    }

}

#if DEBUG
internal struct FactoryDebugInformation {
    let type: String
    let key: String
    internal init(type: String, key: StaticString) {
        self.type = type
        self.key = "\(key)<\(type)>"
    }
}
#endif

// Internal Factory type
internal protocol AnyFactory {}

internal struct TypedFactory<P,T>: AnyFactory {
    let factory: @Sendable (P) -> T
}

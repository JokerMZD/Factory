//
// Globals.swift
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

// MARK: - Thread-Local Keys

/// Keys used for thread-local storage via Thread.current.threadDictionary.
/// Each thread gets its own independent copy of resolution depth, dependency chain,
/// and trace arrays. This prevents cross-thread corruption now that the global lock
/// is released during factory execution (split-lock pattern).
private let kGraphResolutionDepth = "Factory.graphResolutionDepth"
private let kResolvingKeys = "Factory.resolvingKeys"
private let kGraphCache = "Factory.graphCache"
#if DEBUG
private let kDependencyChain = "Factory.dependencyChain"
private let kDependencyChainMessages = "Factory.dependencyChainMessages"
private let kTraceResolutions = "Factory.traceResolutions"
#endif

// MARK: - Thread-Local Graph Resolution Depth

/// Returns the current thread's graph resolution depth (0 if unset).
@usableFromInline
internal func graphDepthGet() -> Int {
    Thread.current.threadDictionary[kGraphResolutionDepth] as? Int ?? 0
}

/// Increments and returns the current thread's graph resolution depth.
@discardableResult
@usableFromInline
internal func graphDepthInc() -> Int {
    let new = graphDepthGet() + 1
    Thread.current.threadDictionary[kGraphResolutionDepth] = new
    return new
}

/// Decrements and returns the current thread's graph resolution depth.
@discardableResult
@usableFromInline
internal func graphDepthDec() -> Int {
    let new = max(graphDepthGet() - 1, 0)
    Thread.current.threadDictionary[kGraphResolutionDepth] = new
    return new
}

/// Resets the current thread's graph resolution depth to zero.
@usableFromInline
internal func graphDepthReset() {
    Thread.current.threadDictionary.removeObject(forKey: kGraphResolutionDepth)
}

// MARK: - Thread-Local Resolving Keys (Re-entrant Guard)

/// Returns the current thread's set of keys that are mid-resolution.
/// Used to detect re-entrant resolution of the same scoped key on the same thread,
/// which would deadlock on the inflight gate's NSCondition.
internal func resolvingKeysGet() -> Set<FactoryKey> {
    Thread.current.threadDictionary[kResolvingKeys] as? Set<FactoryKey> ?? []
}

/// Sets the current thread's resolving keys set.
internal func resolvingKeysSet(_ value: Set<FactoryKey>) {
    if value.isEmpty {
        Thread.current.threadDictionary.removeObject(forKey: kResolvingKeys)
    } else {
        Thread.current.threadDictionary[kResolvingKeys] = value
    }
}

/// Inserts a key into the current thread's resolving set. Returns `true` if the key was newly inserted,
/// `false` if it was already present (indicating re-entrant resolution).
@discardableResult
internal func resolvingKeysInsert(_ key: FactoryKey) -> Bool {
    var keys = resolvingKeysGet()
    let (inserted, _) = keys.insert(key)
    resolvingKeysSet(keys)
    return inserted
}

/// Removes a key from the current thread's resolving set.
internal func resolvingKeysRemove(_ key: FactoryKey) {
    var keys = resolvingKeysGet()
    keys.remove(key)
    resolvingKeysSet(keys)
}

// MARK: - Thread-Local Graph Cache

/// Returns or creates the current thread's graph scope cache.
/// Each thread gets its own independent graph cache so that concurrent resolution
/// cycles don't share or corrupt each other's graph-scoped instances.
internal func threadGraphCacheGet() -> Scope.Cache {
    if let cache = Thread.current.threadDictionary[kGraphCache] as? Scope.Cache {
        return cache
    }
    let cache = Scope.Cache()
    Thread.current.threadDictionary[kGraphCache] = cache
    return cache
}

/// Resets the current thread's graph cache. Called when graph depth reaches zero.
internal func threadGraphCacheReset() {
    if let cache = Thread.current.threadDictionary[kGraphCache] as? Scope.Cache {
        cache.reset()
    }
}

// MARK: - Thread-Local Debug State

#if DEBUG
/// Returns the current thread's dependency chain array.
internal func threadDependencyChainGet() -> [String] {
    Thread.current.threadDictionary[kDependencyChain] as? [String] ?? []
}

/// Sets the current thread's dependency chain array.
internal func threadDependencyChainSet(_ value: [String]) {
    Thread.current.threadDictionary[kDependencyChain] = value
}

/// Returns the current thread's dependency chain messages array.
internal func threadDependencyChainMessagesGet() -> [String] {
    Thread.current.threadDictionary[kDependencyChainMessages] as? [String] ?? []
}

/// Sets the current thread's dependency chain messages array.
internal func threadDependencyChainMessagesSet(_ value: [String]) {
    Thread.current.threadDictionary[kDependencyChainMessages] = value
}

/// Returns the current thread's trace resolutions array.
internal func threadTraceResolutionsGet() -> [String] {
    Thread.current.threadDictionary[kTraceResolutions] as? [String] ?? []
}

/// Sets the current thread's trace resolutions array.
internal func threadTraceResolutionsSet(_ value: [String]) {
    Thread.current.threadDictionary[kTraceResolutions] = value
}

/// Clears all thread-local resolution state for the current thread.
internal func threadResolutionStateReset() {
    let dict = Thread.current.threadDictionary
    dict.removeObject(forKey: kGraphResolutionDepth)
    dict.removeObject(forKey: kResolvingKeys)
    dict.removeObject(forKey: kGraphCache)
    dict.removeObject(forKey: kDependencyChain)
    dict.removeObject(forKey: kDependencyChainMessages)
    dict.removeObject(forKey: kTraceResolutions)
}
#endif

// MARK: - Internal Variables

/// Internal key used for Resolver mode
internal let globalResolverKey: StaticString = "*"

#if DEBUG
/// Global trace flag — this is intentionally global (not thread-local) because it's a configuration
/// setting toggled by the developer, not per-resolution state.
nonisolated(unsafe) internal var globalTraceFlag: Bool = false
/// Global logger — same rationale as globalTraceFlag.
nonisolated(unsafe) internal var globalLogger: (String) -> Void = { print($0) }

/// Triggers fatalError after resetting enough stuff so unit tests can continue
internal func resetAndTriggerFatalError(_ message: String, _ file: StaticString, _ line: UInt) -> Never {
    threadResolutionStateReset()
    globalRecursiveLock = RecursiveLock()
    triggerFatalError(message, file, line) // GOES BOOM
}

/// Allow unit test interception of any fatal errors that may occur running the circular dependency check
/// Variation of solution: https://stackoverflow.com/questions/32873212/unit-test-fatalerror-in-swift#
nonisolated(unsafe) internal var triggerFatalError = Swift.fatalError
#endif

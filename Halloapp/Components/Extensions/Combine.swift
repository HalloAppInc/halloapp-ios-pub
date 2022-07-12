//
//  Combine.swift
//  HalloApp
//
//  Created by Cay Zhang on 7/8/22.
//  Copyright © 2022 HalloApp, Inc. All rights reserved.
//

import Combine

extension Future {
    convenience init(priority: TaskPriority? = nil, operation: @escaping @Sendable () async -> Output) where Failure == Never {
        self.init { promise in
            Task(priority: priority) {
                let result = await operation()
                promise(.success(result))
            }
        }
    }
    
    convenience init(priority: TaskPriority? = nil, operation: @escaping @Sendable () async throws -> Output) where Failure == any Error {
        self.init { promise in
            Task(priority: priority) {
                do {
                    let result = try await operation()
                    promise(.success(result))
                } catch {
                    promise(.failure(error))
                }
            }
        }
    }
}

extension Publisher where Failure == Never {
    /// Assigns each element from a publisher to a property on an object, maintaining a weak reference of the object.
    ///
    /// - Parameters:
    ///   - keyPath: A key path that indicates the property to assign.
    ///   - object: The object that contains the property. The subscriber assigns the object’s property every time it receives a new value.
    /// - Returns: An ``AnyCancellable`` instance. Call ``cancel()`` on this instance when you no longer want
    ///            the publisher to automatically assign the property. Deinitializing this instance
    ///            will also cancel automatic assignment.
    func assign<Root: AnyObject>(to keyPath: ReferenceWritableKeyPath<Root, Output>, onWeak object: Root) -> AnyCancellable {
        sink { [weak object] value in
            object?[keyPath: keyPath] = value
        }
    }
}

extension Publisher {
    /// Transform a publisher to a new publisher that wraps ``Output`` and ``Failure`` in ``Result``, and has ``Never`` for ``Failure`` type.
    ///
    /// - Returns: ``some Publisher<Result<Output, Failure>, Never>``
    func mapToResult() -> Publishers.Catch<Publishers.Map<Self, Result<Output, Failure>>, Just<Result<Output, Failure>>> {
        map(Result.success)
            .catch { Just(.failure($0)) }
    }
}

extension Publisher {
    /// Groups the elements of the source publisher into tuples of 2 consecutive elements.
    ///
    /// The resulting publisher
    ///    - does not emit anything until the source publisher emits at least 2 elements;
    ///    - emits a tuple for every element after that;
    ///    - forwards the completion.
    ///
    /// - Returns: A publisher that holds tuple with 2 elements.
    func pairwise() -> Publishers.CompactMap<Publishers.Scan<Self, (Output?, Output?)>, (Output, Output)> {
        scan((nil, nil)) { (accumulated: (Output?, Output?), next: Output) -> (Output?, Output?) in
            (accumulated.1, next)
        }.compactMap { (a, b) in
            if let a = a, let b = b {
                return (a, b)
            } else {
                return nil
            }
        }
    }
}

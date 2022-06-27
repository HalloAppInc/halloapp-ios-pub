//
//  Hashcash.swift
//  Core
//
//  Created by Garrett on 12/21/21.
//  Copyright © 2021 Hallo App, Inc. All rights reserved.
//

import CocoaLumberjackSwift
import Foundation

enum HashcashError: Error {
    case invalidChallenge
    case timeExpired
}

public struct HashcashSolution: Equatable {
    var solution: String
    var timeTaken: TimeInterval
    var expiration: Date
}

/// Closure that attempts to fetch a new hashcash challenge and calls a completion block on the result
typealias HashcashChallengeRequester = (_ completion: @escaping (Result<String, Error>) -> Void) -> Void

/// Computes hashcash solution and manages state (initial/requesting/solving/solved)
class HashcashSolver {

    init(fetchNext: @escaping HashcashChallengeRequester) {
        self.fetchNext = fetchNext
    }

    enum State: Equatable {
        case initial
        case requesting
        case solving(String)
        case solved(HashcashSolution)
    }

    enum HashcashSolverError: Error {
        case busy
    }

    private let fetchNext: HashcashChallengeRequester
    private var state: State = .initial
    private var completion: ((Result<HashcashSolution, Error>) -> Void)?

    func solveNext(completion: ((Result<HashcashSolution, Error>) -> Void)? = nil) {
        if let completion = self.completion {
            completion(.failure(HashcashSolverError.busy))
            self.completion = nil
            return
        }
        switch state {
        case .initial:
            // Save completion (if given) and begin execution
            self.completion = completion
            execute()
        case .requesting, .solving:
            // Save completion (will be called when execution completes)
            self.completion = completion
        case .solved(let solution):
            // Call completion and reset state if completion given, otherwise hold onto solution and wait
            guard let completion = completion else {
                DDLogInfo("HashcashSolver/solveNext/solved/waiting [no-completion]")
                return
            }
            guard solution.expiration > Date() else {
                DDLogInfo("HashcashSolver/solveNext/refetching [expired-solution]")
                self.completion = completion
                state = .initial
                execute()
                return
            }
            completion(.success(solution))
            self.completion = nil
            state = .initial
        }
    }

    private func execute() {
        guard state == .initial else {
            DDLogInfo("HashcashSolver/solveNext/skipping [state: \(state)]")
            return
        }
        state = .requesting
        fetchNext() { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let challenge):
                DDLogInfo("HashcashSolver/fetch/success [\(challenge)]")
                self.state = .solving(challenge)
                Self.solve(challenge) { [weak self] result in
                    guard let self = self else { return }
                    switch result {
                    case .success(let solution):
                        DDLogInfo("HashcashSolver/solve/success [\(solution.solution)] [\(solution.timeTaken)s]")
                        if let completion = self.completion {
                            completion(.success(solution))
                            self.completion = nil
                            self.state = .initial
                        } else {
                            self.state = .solved(solution)
                        }
                    case .failure(let error):
                        DDLogError("HashcashSolver/solve/error [\(error)]")
                        self.state = .initial
                        self.completion?(.failure(error))
                        self.completion = nil
                    }
                }
            case .failure(let error):
                DDLogError("HashcashSolver/fetch/error [\(error)]")
                self.state = .initial
                self.completion?(.failure(error))
                self.completion = nil
            }
        }
    }

    static func solve(_ input: String, completion: @escaping (Result<HashcashSolution, HashcashError>) -> ()) {
        guard let challenge = HashcashChallenge(input) else {
            completion(.failure(.invalidChallenge))
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let startTime = CACurrentMediaTime()
            // NB: The difficulty D refers to the number of leading 0's in the hash.
            //     This should show up once in every 2^D hashes, so we'd expect > 256 valid solutions in D/8 + 2 bytes.
            let guessBytes = challenge.difficulty / 8 + 2
            var guess = Data(count: guessBytes)
            var timeTaken: TimeInterval = 0
            while timeTaken < challenge.expiresIn {
                let candidate = input + ":" + guess.base64EncodedString()
                let success = challenge.verify(candidate)
                timeTaken = CACurrentMediaTime() - startTime
                if success {
                    completion(.success(HashcashSolution(
                        solution: candidate,
                        timeTaken: timeTaken,
                        expiration: Date().addingTimeInterval(challenge.expiresIn))))
                    return
                } else {
                    guess = guess.next()
                }
            }
            completion(.failure(.timeExpired))
        }
    }
}

struct HashcashChallenge {
    init?(_ string: String) {
        let segments = string.split(separator: ":")
        guard segments.count >= 6 else {
            DDLogError("HashcashChallenge/init/error [segments-count] [\(segments.count)]")
            return nil
        }
        guard let tag = Tag(rawValue: String(segments[0])) else {
            DDLogError("HashcashChallenge/init/error [unsupported-tag] [\(segments[0])]")
            return nil
        }
        guard let difficulty = Int(segments[1]) else {
            DDLogError("HashcashChallenge/init/error [unsupported-difficulty] [\(segments[1])]")
            return nil
        }
        guard let expiresIn = Int(segments[2]) else {
            DDLogError("HashcashChallenge/init/error [unsupported-expiration] [\(segments[2])]")
            return nil
        }
        guard let algo = Algorithm(rawValue: String(segments[5])) else {
            DDLogError("HashcashChallenge/init/error [unsupported algo] [\(segments[5])]")
            return nil
        }
        self.tag = tag
        self.difficulty = difficulty
        self.expiresIn = TimeInterval(expiresIn)
        self.subject = String(segments[3])
        self.nonce = String(segments[4])
        self.algo = algo
    }

    func verify(_ candidate: String) -> Bool {
        let data: Data
        switch algo {
        case .SHA256:
            guard let sha256 = candidate.sha256() else {
                DDLogError("HashcashChallenge/verify/sha256/error [\(candidate)]")
                return false
            }
            data = sha256
        }

        var bitsRemaining = difficulty
        for byte in data.bytes {
            let prefixToCheck = byte >> max(0, 8 - bitsRemaining)
            if prefixToCheck != 0 {
                return false
            }

            bitsRemaining -= 8
            if bitsRemaining <= 0 {
                return true
            }
        }
        return false
    }

    var tag: Tag
    var difficulty: Int
    var expiresIn: TimeInterval
    var subject: String
    var nonce: String
    var algo: Algorithm

    enum Tag: String {
        case H
    }
    enum Algorithm: String {
        case SHA256 = "SHA-256"
    }
}

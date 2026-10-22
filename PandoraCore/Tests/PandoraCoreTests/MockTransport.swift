//
//  MockTransport.swift
//  PandoraCoreTests
//
//  Shared scripted HTTP transport: returns `responses` in call order,
//  recording every request. No network in any unit test.
//

import Foundation
@testable import PandoraCore

final class MockTransport: HTTPTransport, @unchecked Sendable {
    struct RecordedRequest {
        let url: URL
        let body: Data
        let contentType: String
    }

    private let lock = NSLock()
    private var recorded: [RecordedRequest] = []
    private let responses: [Result<Data, Error>]
    private var next = 0

    init(responses: [Result<Data, Error>]) {
        self.responses = responses
    }

    var requests: [RecordedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func post(url: URL, body: Data, contentType: String) async throws -> Data {
        lock.lock()
        recorded.append(RecordedRequest(url: url, body: body, contentType: contentType))
        let index = next
        next += 1
        lock.unlock()

        guard index < responses.count else {
            throw PandoraTransportError(reason: "mock exhausted at request \(index)")
        }
        return try responses[index].get()
    }
}

import XCTest
@testable import Jabber

/// Tests for `OpenRouterPostProcessor`. A transport closure captures the
/// outgoing `URLRequest` and returns canned `(Data, URLResponse)` tuples, so no
/// test ever hits the network or the Keychain (the provider takes the API key
/// as an init parameter).
final class OpenRouterPostProcessorTests: XCTestCase {
    private let testKey = "sk-test-greendale-abc"

    // MARK: - isAvailable

    func testIsAvailableFalseForEmptyKey() {
        XCTAssertFalse(OpenRouterPostProcessor(apiKey: "").isAvailable)
    }

    func testIsAvailableFalseForWhitespaceKey() {
        XCTAssertFalse(OpenRouterPostProcessor(apiKey: "   \n  ").isAvailable)
    }

    func testIsAvailableTrueForNonEmptyKey() {
        XCTAssertTrue(OpenRouterPostProcessor(apiKey: testKey).isAvailable)
    }

    func testDisplayNameIsOpenRouter() {
        XCTAssertEqual(OpenRouterPostProcessor(apiKey: testKey).displayName, "OpenRouter")
    }

    // MARK: - process: success

    func testProcessReturnsChoiceContentVerbatim() async throws {
        let captured = RequestCapture()
        let provider = OpenRouterPostProcessor(
            apiKey: testKey,
            transport: captured.transportReturning(
                body: #"{"choices":[{"message":{"content":"Hello."}}]}"#
            )
        )

        let result = try await provider.process(" um hello ")
        XCTAssertEqual(result, "Hello.")
        XCTAssertEqual(captured.requests.count, 1)
    }

    func testProcessEmptyStringContentIsReturnedNotThrown() async throws {
        // An empty/whitespace content is a valid cancellation outcome (e.g.
        // "scratch that"), not a failure. The coordinator normalizes it.
        let provider = OpenRouterPostProcessor(
            apiKey: testKey,
            transport: RequestCapture().transportReturning(
                body: #"{"choices":[{"message":{"content":""}}]}"#
            )
        )
        let result = try await provider.process("cancel that")
        XCTAssertEqual(result, "")
    }

    // MARK: - process: request shape

    func testProcessRequestShapeHeadersAndBody() async throws {
        let captured = RequestCapture()
        let provider = OpenRouterPostProcessor(
            apiKey: testKey,
            modelId: "~anthropic/claude-haiku-latest",
            transport: captured.transportReturning(
                body: #"{"choices":[{"message":{"content":"ok"}}]}"#
            )
        )

        _ = try await provider.process("señor chang")

        let request = try XCTUnwrap(captured.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url, OpenRouterPostProcessor.endpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(testKey)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Title"), "Jabber")
        XCTAssertEqual(request.value(forHTTPHeaderField: "HTTP-Referer"), "https://rselbach.github.io/jabber/")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "~anthropic/claude-haiku-latest")
        XCTAssertEqual(json["stream"] as? Bool, false)
        XCTAssertEqual(json["temperature"] as? Int, 0)

        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[0]["content"] as? String, AppleIntelligencePostProcessor.instructions)
        XCTAssertEqual(messages[1]["role"] as? String, "user")
        XCTAssertEqual(messages[1]["content"] as? String, "señor chang")
    }

    func testProcessUnknownModelSlugFallsBackToDefault() async throws {
        let captured = RequestCapture()
        let provider = OpenRouterPostProcessor(
            apiKey: testKey,
            modelId: "openai/gpt-4o",
            transport: captured.transportReturning(
                body: #"{"choices":[{"message":{"content":"ok"}}]}"#
            )
        )

        _ = try await provider.process("abed")
        let body = try XCTUnwrap(captured.requests.first?.httpBody)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, OpenRouterModelCatalog.defaultModelId)
    }

    // MARK: - process: errors

    func testProcessThrowsMissingApiKeyWhenKeyBlank() async {
        let provider = OpenRouterPostProcessor(
            apiKey: "  ",
            transport: RequestCapture().transportReturning(body: "{}")
        )
        do {
            _ = try await provider.process("hello")
            XCTFail("Expected missingApiKey")
        } catch let error as OpenRouterPostProcessingError {
            XCTAssertEqual(error, .missingApiKey)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProcessThrowsHTTPFailureOnNon2xx() async {
        // Flat string error (not OpenRouter's structured shape) → no message
        // extracted, status-only failure.
        let provider = OpenRouterPostProcessor(
            apiKey: testKey,
            transport: RequestCapture().transportReturning(body: #"{"error":"rate limited"}"#, status: 429)
        )
        do {
            _ = try await provider.process("hello")
            XCTFail("Expected httpFailure")
        } catch let error as OpenRouterPostProcessingError {
            XCTAssertEqual(error, .httpFailure(429, nil))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProcessHTTPFailureIncludesAPIErrorMessage() async {
        // OpenRouter returns a structured `{"error":{"message":...}}` body; the
        // message must be carried alongside the status code and surface in the
        // human-readable description so the user knows *why* it failed.
        let body = #"{"error":{"message":"No more credits, Troy."}}"#
        let provider = OpenRouterPostProcessor(
            apiKey: testKey,
            transport: RequestCapture().transportReturning(body: body, status: 402)
        )
        do {
            _ = try await provider.process("hello")
            XCTFail("Expected httpFailure")
        } catch let error as OpenRouterPostProcessingError {
            XCTAssertEqual(error, .httpFailure(402, "No more credits, Troy."))
            let desc = error.errorDescription ?? ""
            XCTAssertTrue(desc.contains("402"), "status code must remain in the description: \(desc)")
            XCTAssertTrue(desc.contains("No more credits, Troy."), "API message must be in the description: \(desc)")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProcessHTTPFailureTruncatesLongAPIErrorMessage() async {
        let longMessage = String(repeating: "a", count: 600)
        let body = #"{"error":{"message":"\#(longMessage)"}}"#
        let provider = OpenRouterPostProcessor(
            apiKey: testKey,
            transport: RequestCapture().transportReturning(body: body, status: 500)
        )
        do {
            _ = try await provider.process("hello")
            XCTFail("Expected httpFailure")
        } catch let error as OpenRouterPostProcessingError {
            let message = extractHttpFailureMessage(error)
            XCTAssertNotNil(message, "expected httpFailure with a message")
            XCTAssertEqual(message?.count, 200, "API message must be truncated to 200 characters")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProcessThrowsMalformedResponseOnGarbageJSON() async {
        let provider = OpenRouterPostProcessor(
            apiKey: testKey,
            transport: RequestCapture().transportReturning(body: "not json at all")
        )
        do {
            _ = try await provider.process("hello")
            XCTFail("Expected malformedResponse")
        } catch let error as OpenRouterPostProcessingError {
            XCTAssertEqual(error, .malformedResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProcessThrowsEmptyResponseWhenChoicesArrayEmpty() async {
        let provider = OpenRouterPostProcessor(
            apiKey: testKey,
            transport: RequestCapture().transportReturning(body: #"{"choices":[]}"#)
        )
        do {
            _ = try await provider.process("hello")
            XCTFail("Expected emptyResponse")
        } catch let error as OpenRouterPostProcessingError {
            XCTAssertEqual(error, .emptyResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProcessThrowsMalformedResponseWhenContentMissing() async {
        let provider = OpenRouterPostProcessor(
            apiKey: testKey,
            transport: RequestCapture().transportReturning(body: #"{"choices":[{"message":{}}]}"#)
        )
        do {
            _ = try await provider.process("hello")
            XCTFail("Expected malformedResponse")
        } catch let error as OpenRouterPostProcessingError {
            XCTAssertEqual(error, .malformedResponse)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProcessThrowsNetworkErrorWhenTransportThrows() async {
        struct GreendaleNetworkError: Error {}
        let provider = OpenRouterPostProcessor(
            apiKey: testKey,
            transport: RequestCapture().transportThrowing(GreendaleNetworkError())
        )
        do {
            _ = try await provider.process("hello")
            XCTFail("Expected networkError")
        } catch let error as OpenRouterPostProcessingError {
            if case .networkError = error {
                // expected
            } else {
                XCTFail("Expected networkError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testProcessMapsCancelledURLErrorToCancellationError() async {
        // URLSession.data(for:) reacts to task cancellation by throwing
        // URLError(.cancelled), not CancellationError. A cancelled dictation
        // must surface as cancellation, not as a user-visible network failure.
        let provider = OpenRouterPostProcessor(
            apiKey: testKey,
            transport: RequestCapture().transportThrowing(URLError(.cancelled))
        )
        do {
            _ = try await provider.process("hello")
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    // MARK: - error messages never leak the key

    func testErrorDescriptionsDoNotLeakApiKey() {
        let key = "sk-super-secret-greendale"
        let cases: [OpenRouterPostProcessingError] = [
            .missingApiKey,
            .httpFailure(500, nil),
            .httpFailure(402, "No more credits, Troy."),
            .malformedResponse,
            .emptyResponse,
            .networkError("connection reset")
        ]
        for error in cases {
            let desc = error.errorDescription ?? ""
            XCTAssertFalse(desc.contains(key), "Error message must not leak the API key: \(desc)")
        }
    }
}

// MARK: - Request capture helper

private func extractHttpFailureMessage(_ error: OpenRouterPostProcessingError) -> String? {
    if case let .httpFailure(_, message) = error {
        return message
    }
    return nil
}

private final class RequestCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [URLRequest] = []

    var requests: [URLRequest] {
        lock.withLock { _requests }
    }

    func transportReturning(body: String, status: Int = 200) -> @Sendable (URLRequest) async throws -> (Data, URLResponse) {
        let data = Data(body.utf8)
        let response = HTTPURLResponse(
            url: OpenRouterPostProcessor.endpoint,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return { [self] request in
            self.lock.withLock { self._requests.append(request) }
            return (data, response)
        }
    }

    func transportThrowing(_ error: Error) -> @Sendable (URLRequest) async throws -> (Data, URLResponse) {
        return { [self] request in
            self.lock.withLock { self._requests.append(request) }
            throw error
        }
    }
}

import XCTest
@testable import Jabber

final class TranscriptionServiceTests: XCTestCase {
    func testProviderCallGateSerializesConcurrentOperations() async throws {
        let gate = ProviderCallGate()
        let probe = ProviderCallProbe()
        let firstStarted = TestLatch()
        let releaseFirst = TestLatch()

        let firstTask = Task {
            try await gate.run {
                await probe.start("first")
                await firstStarted.open()
                await releaseFirst.wait()
                await probe.finish()
                return "one"
            }
        }

        await firstStarted.wait()

        let secondTask = Task {
            try await gate.run {
                await probe.start("second")
                await probe.finish()
                return "two"
            }
        }

        try await Task.sleep(for: .milliseconds(50))
        let activeCountWhileFirstHeld = await probe.maxActiveCount
        let orderWhileFirstHeld = await probe.startedOrder
        XCTAssertEqual(activeCountWhileFirstHeld, 1)
        XCTAssertEqual(orderWhileFirstHeld, ["first"])

        await releaseFirst.open()

        let firstResult = try await firstTask.value
        let secondResult = try await secondTask.value
        XCTAssertEqual(firstResult, "one")
        XCTAssertEqual(secondResult, "two")
        let finalActiveCount = await probe.maxActiveCount
        let finalOrder = await probe.startedOrder
        XCTAssertEqual(finalActiveCount, 1)
        XCTAssertEqual(finalOrder, ["first", "second"])
    }

    // MARK: - resolveLanguage

    func testResolveLanguageAcceptsAuto() {
        XCTAssertEqual(TranscriptionService.resolveLanguage("auto"), "auto")
    }

    func testResolveLanguageAcceptsValidCode() {
        XCTAssertEqual(TranscriptionService.resolveLanguage("en"), "en")
        XCTAssertEqual(TranscriptionService.resolveLanguage("zh"), "zh")
        XCTAssertEqual(TranscriptionService.resolveLanguage("fa"), "fa")
    }

    func testResolveLanguageFallsBackForInvalidCode() {
        XCTAssertEqual(TranscriptionService.resolveLanguage("xyz"), "auto")
        XCTAssertEqual(TranscriptionService.resolveLanguage(""), "auto")
        XCTAssertEqual(TranscriptionService.resolveLanguage("EN"), "auto")
    }

    func testResolveLanguageAcceptsAllValidLanguageCodes() {
        for code in Constants.validLanguageCodes {
            XCTAssertEqual(
                TranscriptionService.resolveLanguage(code),
                code,
                "resolveLanguage should accept valid code '\(code)'"
            )
        }
    }

    // MARK: - resolveLanguageForProvider

    func testResolveLanguageForProviderReturnsNilForAuto() {
        XCTAssertNil(TranscriptionService.resolveLanguageForProvider("auto"))
    }

    func testResolveLanguageForProviderReturnsCodeForSpecificLanguage() {
        XCTAssertEqual(TranscriptionService.resolveLanguageForProvider("en"), "en")
        XCTAssertEqual(TranscriptionService.resolveLanguageForProvider("ja"), "ja")
    }

    // MARK: - truncateVocabularyPrompt

    func testTruncateVocabularyPromptShortStringUnchanged() {
        XCTAssertEqual(TranscriptionService.truncateVocabularyPrompt("hello"), "hello")
    }

    func testTruncateVocabularyPromptEmptyStringUnchanged() {
        XCTAssertEqual(TranscriptionService.truncateVocabularyPrompt(""), "")
    }

    func testTruncateVocabularyPromptTruncatesAt500Characters() {
        let short = String(repeating: "a", count: 400)
        let exact = String(repeating: "b", count: 500)
        let long = String(repeating: "c", count: 600)

        XCTAssertEqual(TranscriptionService.truncateVocabularyPrompt(short).count, 400)
        XCTAssertEqual(TranscriptionService.truncateVocabularyPrompt(exact).count, 500)
        XCTAssertEqual(TranscriptionService.truncateVocabularyPrompt(long).count, 500)
    }
}

private actor TestLatch {
    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pendingContinuations = continuations
        continuations = []
        for continuation in pendingContinuations {
            continuation.resume()
        }
    }
}

private actor ProviderCallProbe {
    private var activeCount = 0
    private var _maxActiveCount = 0
    private var _startedOrder: [String] = []

    var maxActiveCount: Int {
        _maxActiveCount
    }

    var startedOrder: [String] {
        _startedOrder
    }

    func start(_ name: String) {
        activeCount += 1
        _maxActiveCount = max(_maxActiveCount, activeCount)
        _startedOrder.append(name)
    }

    func finish() {
        activeCount -= 1
    }
}

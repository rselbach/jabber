import os
import XCTest
@testable import Jabber

final class TranscriptionServiceTests: XCTestCase {
    func testConcurrentLoadModelCallersShareSingleProviderLoad() async throws {
        let downloadProbe = ModelDownloadProbe()
        let provider = FakeTranscriptionProvider(modelId: AppMode.qwen3ModelId)
        let loadStarted = TestLatch()
        let releaseLoad = TestLatch()
        provider.holdLoad(started: loadStarted, release: releaseLoad)
        let service = TranscriptionService(loadDependencies: TranscriptionService.LoadDependencies(
            waitForUIReady: {},
            selectedModelId: { AppMode.qwen3ModelId },
            setSelectedModelId: { _ in },
            ensureModelDownloaded: { modelId in
                try await downloadProbe.ensureDownloaded(modelId)
            },
            makeProvider: { _ in provider }
        ))

        let firstTask = Task {
            try await service.ensureModelLoaded()
        }
        await loadStarted.wait()

        let secondTask = Task {
            try await service.ensureModelLoaded()
        }

        try await Task.sleep(for: .milliseconds(50))
        let modelIdsWhileFirstHeld = await downloadProbe.modelIds
        XCTAssertEqual(modelIdsWhileFirstHeld, [AppMode.qwen3ModelId])
        XCTAssertEqual(provider.loadCallCount, 1)

        await releaseLoad.open()
        try await firstTask.value
        try await secondTask.value

        let finalModelIds = await downloadProbe.modelIds
        let currentModelId = await service.currentModelId()
        XCTAssertEqual(finalModelIds, [AppMode.qwen3ModelId])
        XCTAssertEqual(provider.loadCallCount, 1)
        XCTAssertEqual(provider.unloadCallCount, 0)
        XCTAssertEqual(currentModelId, AppMode.qwen3ModelId)
    }

    func testUnloadDuringLoadCancelsGenerationAndUnloadsNewProvider() async throws {
        let downloadProbe = ModelDownloadProbe()
        let provider = FakeTranscriptionProvider(modelId: AppMode.qwen3ModelId)
        let loadStarted = TestLatch()
        let releaseLoad = TestLatch()
        provider.holdLoad(started: loadStarted, release: releaseLoad)
        let service = TranscriptionService(loadDependencies: TranscriptionService.LoadDependencies(
            waitForUIReady: {},
            selectedModelId: { AppMode.qwen3ModelId },
            setSelectedModelId: { _ in },
            ensureModelDownloaded: { modelId in
                try await downloadProbe.ensureDownloaded(modelId)
            },
            makeProvider: { _ in provider }
        ))

        let loadTask = Task {
            try await service.ensureModelLoaded()
        }
        await loadStarted.wait()

        await service.unloadModel()
        await releaseLoad.open()

        do {
            try await loadTask.value
            XCTFail("load should be cancelled after a generation bump")
        } catch is CancellationError {}

        XCTAssertEqual(provider.loadCallCount, 1)
        XCTAssertEqual(provider.unloadCallCount, 1)
        let currentModelId = await service.currentModelId()
        XCTAssertNil(currentModelId)
    }

    func testReentrantSelectedModelAwaitDoesNotStartDuplicateLoad() async throws {
        let selectedProbe = SelectedModelProbe(modelId: AppMode.qwen3ModelId)
        let downloadProbe = ModelDownloadProbe()
        let provider = FakeTranscriptionProvider(modelId: AppMode.qwen3ModelId)
        let service = TranscriptionService(loadDependencies: TranscriptionService.LoadDependencies(
            waitForUIReady: {},
            selectedModelId: {
                await selectedProbe.selectedModelId()
            },
            setSelectedModelId: { _ in },
            ensureModelDownloaded: { modelId in
                try await downloadProbe.ensureDownloaded(modelId)
            },
            makeProvider: { _ in provider }
        ))

        let firstTask = Task {
            try await service.ensureModelLoaded()
        }
        await selectedProbe.waitForCallCount(1)

        let secondTask = Task {
            try await service.ensureModelLoaded()
        }
        await selectedProbe.waitForCallCount(2)
        await selectedProbe.releaseAll()

        try await firstTask.value
        try await secondTask.value

        let modelIds = await downloadProbe.modelIds
        XCTAssertEqual(modelIds, [AppMode.qwen3ModelId])
        XCTAssertEqual(provider.loadCallCount, 1)
        XCTAssertEqual(provider.unloadCallCount, 0)
    }

    func testModelSwitchUnloadSuspensionDoesNotStartDuplicateLoad() async throws {
        let downloadProbe = ModelDownloadProbe()
        let selected = MutableSelectedModel(AppMode.qwen3ModelId)
        let providerA = FakeTranscriptionProvider(modelId: AppMode.qwen3ModelId)
        let providerB = FakeTranscriptionProvider(modelId: AppMode.nemotronModelId)
        let transcribeStarted = TestLatch()
        let releaseTranscribe = TestLatch()
        providerA.holdTranscribe(started: transcribeStarted, release: releaseTranscribe)
        let service = TranscriptionService(loadDependencies: TranscriptionService.LoadDependencies(
            waitForUIReady: {},
            selectedModelId: { await selected.get() },
            setSelectedModelId: { _ in },
            ensureModelDownloaded: { modelId in
                try await downloadProbe.ensureDownloaded(modelId)
            },
            makeProvider: { modelId in
                modelId == providerA.modelId ? providerA : providerB
            }
        ))

        try await service.ensureModelLoaded()
        XCTAssertEqual(providerA.loadCallCount, 1)

        // Park the provider gate with an in-flight transcribe so the model
        // switch's unload of providerA suspends behind it.
        let transcribeTask = Task { try await service.transcribe(samples: []) }
        await transcribeStarted.wait()

        await selected.set(AppMode.nemotronModelId)

        let firstLoad = Task { try await service.ensureModelLoaded() }
        try await Task.sleep(for: .milliseconds(50))
        // While firstLoad is suspended in the unload, a second caller must
        // wait for it instead of claiming a duplicate concurrent load.
        let secondLoad = Task { try await service.ensureModelLoaded() }
        try await Task.sleep(for: .milliseconds(50))

        await releaseTranscribe.open()
        _ = try await transcribeTask.value
        try await firstLoad.value
        try await secondLoad.value

        XCTAssertEqual(providerA.unloadCallCount, 1)
        XCTAssertEqual(providerB.loadCallCount, 1)
        XCTAssertEqual(providerB.unloadCallCount, 0)
        let currentModelId = await service.currentModelId()
        XCTAssertEqual(currentModelId, AppMode.nemotronModelId)
    }

    func testUnknownModelFallsBackToRecommendedDefaultLanguageModel() async throws {
        let selectedModelId = "greendale-human-being"
        let fallbackModelId = LanguageModelCatalog.recommendedModelId(for: Constants.defaultLanguage)
        let downloadProbe = ModelDownloadProbe(missingModelIds: [selectedModelId])
        let selectedModelSetter = SelectedModelSetterProbe()
        let provider = FakeTranscriptionProvider(modelId: fallbackModelId)
        let service = TranscriptionService(loadDependencies: TranscriptionService.LoadDependencies(
            waitForUIReady: {},
            selectedModelId: { selectedModelId },
            setSelectedModelId: { modelId in
                await selectedModelSetter.set(modelId)
            },
            ensureModelDownloaded: { modelId in
                try await downloadProbe.ensureDownloaded(modelId)
            },
            makeProvider: { modelId in
                modelId == fallbackModelId ? provider : nil
            }
        ))

        try await service.ensureModelLoaded()

        let downloadedModelIds = await downloadProbe.modelIds
        let selectedModelIds = await selectedModelSetter.modelIds
        let currentModelId = await service.currentModelId()
        XCTAssertEqual(downloadedModelIds, [selectedModelId, fallbackModelId])
        XCTAssertEqual(selectedModelIds, [fallbackModelId])
        XCTAssertEqual(provider.loadCallCount, 1)
        XCTAssertEqual(currentModelId, fallbackModelId)
    }

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

private actor MutableSelectedModel {
    private var modelId: String

    init(_ modelId: String) {
        self.modelId = modelId
    }

    func set(_ modelId: String) {
        self.modelId = modelId
    }

    func get() -> String {
        modelId
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

private final class FakeTranscriptionProvider: TranscriptionProvider, @unchecked Sendable {
    private struct State {
        var loadStarted: TestLatch?
        var releaseLoad: TestLatch?
        var transcribeStarted: TestLatch?
        var releaseTranscribe: TestLatch?
        var isReady = false
        var loadCallCount = 0
        var unloadCallCount = 0
    }

    let modelId: String

    private let state = OSAllocatedUnfairLock(initialState: State())

    init(modelId: String) {
        self.modelId = modelId
    }

    var isReady: Bool {
        state.withLock { state in
            state.isReady
        }
    }

    var loadCallCount: Int {
        state.withLock { state in
            state.loadCallCount
        }
    }

    var unloadCallCount: Int {
        state.withLock { state in
            state.unloadCallCount
        }
    }

    func holdLoad(started: TestLatch, release: TestLatch) {
        state.withLock { state in
            state.loadStarted = started
            state.releaseLoad = release
        }
    }

    func holdTranscribe(started: TestLatch, release: TestLatch) {
        state.withLock { state in
            state.transcribeStarted = started
            state.releaseTranscribe = release
        }
    }

    func load(from _: URL, progressHandler _: (@Sendable (Double, String) -> Void)?) async throws {
        let holds = state.withLock { state in
            state.loadCallCount += 1
            return (started: state.loadStarted, release: state.releaseLoad)
        }

        await holds.started?.open()
        await holds.release?.wait()

        state.withLock { state in
            state.isReady = true
        }
    }

    func transcribe(samples _: [Float], language _: String?, vocabularyPrompt _: String?) async throws -> String {
        let holds = state.withLock { state in
            (started: state.transcribeStarted, release: state.releaseTranscribe)
        }
        await holds.started?.open()
        await holds.release?.wait()
        return "Troy and Abed in the morning"
    }

    func transcribeStreaming(samples _: [Float], language _: String?, vocabularyPrompt _: String?) async throws -> String {
        "Troy and Abed in the morning"
    }

    func resetStreamingTranscription() {}

    func unload() {
        state.withLock { state in
            state.unloadCallCount += 1
            state.isReady = false
        }
    }
}

private actor ModelDownloadProbe {
    private let missingModelIds: Set<String>
    private var _modelIds: [String] = []

    init(missingModelIds: Set<String> = []) {
        self.missingModelIds = missingModelIds
    }

    var modelIds: [String] {
        _modelIds
    }

    func ensureDownloaded(_ modelId: String) throws -> URL {
        _modelIds.append(modelId)
        if missingModelIds.contains(modelId) {
            throw ModelError.modelNotFound(modelId: modelId)
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("JabberTests.TranscriptionService.")
            .appendingPathComponent(modelId, isDirectory: true)
    }
}

private actor SelectedModelSetterProbe {
    private var _modelIds: [String] = []

    var modelIds: [String] {
        _modelIds
    }

    func set(_ modelId: String) {
        _modelIds.append(modelId)
    }
}

private actor SelectedModelProbe {
    private let modelId: String
    private var callCount = 0
    private var isReleased = false
    private var waitForCallCountContinuations: [(Int, CheckedContinuation<Void, Never>)] = []
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []

    init(modelId: String) {
        self.modelId = modelId
    }

    func selectedModelId() async -> String {
        callCount += 1
        resumeCallCountWaiters()
        if !isReleased {
            await withCheckedContinuation { continuation in
                releaseContinuations.append(continuation)
            }
        }
        return modelId
    }

    func waitForCallCount(_ want: Int) async {
        if callCount >= want { return }
        await withCheckedContinuation { continuation in
            waitForCallCountContinuations.append((want, continuation))
        }
    }

    func releaseAll() {
        guard !isReleased else { return }
        isReleased = true
        let continuations = releaseContinuations
        releaseContinuations = []
        for continuation in continuations {
            continuation.resume()
        }
    }

    private func resumeCallCountWaiters() {
        let readyContinuations = waitForCallCountContinuations.filter { want, _ in
            callCount >= want
        }
        waitForCallCountContinuations.removeAll { want, _ in
            callCount >= want
        }
        for (_, continuation) in readyContinuations {
            continuation.resume()
        }
    }
}

import Foundation

/// The status menu's Language submenu: the languages used most recently, so
/// switching between, say, English and Portuguese doesn't need Settings.
/// Pure so membership and model choice are testable without AppKit.
enum LanguageMenu {
    /// Most languages the submenu remembers.
    static let recentLimit = 5

    struct Item: Equatable {
        let code: String
        let title: String
        let isSelected: Bool
    }

    /// `current` first, then the stored codes in recency order, without
    /// duplicates or codes Jabber no longer offers, capped at `recentLimit`.
    static func recentLanguages(adding current: String, to stored: String) -> [String] {
        var recents = [current]
        for code in stored.split(separator: ",").map(String.init) where isOffered(code) && !recents.contains(code) {
            recents.append(code)
        }
        return Array(recents.prefix(recentLimit))
    }

    static func encode(_ codes: [String]) -> String {
        codes.joined(separator: ",")
    }

    /// One item per recent language, sorted by name so the submenu keeps its
    /// order as recency shifts.
    static func items(recentLanguages: [String], current: String) -> [Item] {
        recentLanguages
            .map { Item(code: $0, title: displayName(for: $0), isSelected: $0 == current) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The model to dictate `languageCode` with: the current one when it can
    /// transcribe the language, else the first downloaded model for it,
    /// recommended first. `nil` when no downloaded model can.
    static func modelId(
        for languageCode: String,
        currentModelId: String,
        downloadedModelIds: Set<String>
    ) -> String? {
        if downloadedModelIds.contains(currentModelId),
           LanguageModelCatalog.supportsLanguage(languageCode, modelId: currentModelId) {
            return currentModelId
        }
        return LanguageModelCatalog.routes(for: languageCode)
            .sorted { $0.isRecommended && !$1.isRecommended }
            .first { downloadedModelIds.contains($0.modelId) }?
            .modelId
    }

    static func displayName(for code: String) -> String {
        guard code != "auto" else { return "Automatic" }
        return Constants.sortedLanguages.first { $0.code == code }?.name ?? code
    }

    private static func isOffered(_ code: String) -> Bool {
        code == "auto" || Constants.validLanguageCodes.contains(code)
    }
}

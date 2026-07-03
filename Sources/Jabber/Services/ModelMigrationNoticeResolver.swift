import Foundation

/// A model migration notice that should be surfaced to the user, if any.
struct ModelMigrationNotice: Equatable, Sendable {
    let migration: ModelManager.Migration
    /// Persistent key identifying this specific from->to migration, used to
    /// avoid re-prompting for the same migration on every launch.
    let noticeKey: String
}

/// Pure decider for whether a model migration should produce a user-facing
/// notice. Kept free of UI and storage concerns so it can be unit tested.
enum ModelMigrationNoticeResolver {
    static func resolve(
        migration: ModelManager.Migration?,
        newModelDownloaded: Bool,
        newModelIsBuiltIn: Bool,
        lastShownKey: String
    ) -> ModelMigrationNotice? {
        guard let migration else { return nil }
        // Built-in (Apple Speech) needs no download; an already-downloaded
        // replacement needs no action. In both cases the user feels nothing,
        // so we don't bug them.
        guard !newModelIsBuiltIn else { return nil }
        guard !newModelDownloaded else { return nil }
        let key = "\(migration.from)->\(migration.to)"
        guard lastShownKey != key else { return nil }
        return ModelMigrationNotice(migration: migration, noticeKey: key)
    }
}

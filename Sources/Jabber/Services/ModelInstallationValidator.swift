import FluidAudio
import Foundation

struct ModelFolderValidation: Equatable {
    let folderExists: Bool
    let missingRequiredFiles: [String]
    let hasWeights: Bool
    let readErrorDescription: String?

    var isComplete: Bool {
        folderExists
            && readErrorDescription == nil
            && missingRequiredFiles.isEmpty
            && hasWeights
    }

    var failureDescription: String {
        guard !isComplete else { return "complete" }

        var problems: [String] = []
        if !folderExists {
            problems.append("folder does not exist")
        }
        if let readErrorDescription {
            problems.append("could not read folder: \(readErrorDescription)")
        }
        if !missingRequiredFiles.isEmpty {
            problems.append("missing files: \(missingRequiredFiles.joined(separator: ", "))")
        }
        if !hasWeights {
            problems.append("missing model weights")
        }
        return problems.joined(separator: "; ")
    }
}

enum ModelInstallationValidator {
    /// What a downloaded model folder must contain: the loose files and the
    /// compiled CoreML bundles. Drives both the download allowlist and the
    /// completeness check, so the two cannot drift apart.
    struct FolderLayout: Equatable {
        let files: [String]
        let directories: [String]

        var requiredAssets: [String] {
            files + directories
        }
    }

    static let parakeetLayout = FolderLayout(
        files: ["parakeet_vocab.json"],
        directories: [
            "Preprocessor.mlmodelc",
            "Encoder.mlmodelc",
            "Decoder.mlmodelc",
            "JointDecision.mlmodelc"
        ]
    )

    /// Ultra keeps v3's joint graph, which computes the top-K outputs the
    /// language hint filters on. The rest of the layout matches v2.
    static let parakeetMultilingualLayout = FolderLayout(
        files: ["parakeet_vocab.json"],
        directories: [
            "Preprocessor.mlmodelc",
            "Encoder.mlmodelc",
            "Decoder.mlmodelc",
            "JointDecisionv3.mlmodelc"
        ]
    )

    /// The Japanese model carries its own vocabulary file name and a decoder
    /// and joint pair named for the v2 graphs they derive from.
    static let parakeetJapaneseLayout = FolderLayout(
        files: ["vocab.json"],
        directories: [
            "Preprocessor.mlmodelc",
            "Encoder.mlmodelc",
            "Decoderv2.mlmodelc",
            "Jointerv2.mlmodelc"
        ]
    )

    static func parakeetLayout(for modelId: String) -> FolderLayout {
        switch modelId {
        case AppMode.parakeetMultilingualModelId:
            return parakeetMultilingualLayout
        case AppMode.parakeetJapaneseModelId:
            return parakeetJapaneseLayout
        default:
            return parakeetLayout
        }
    }

    /// Parakeet Unified computes its mel features in Swift, so it ships no
    /// preprocessor bundle, and its streaming latency tier is baked into the
    /// encoder export, so the layout names the one the provider loads.
    static let parakeetUnifiedLayout: FolderLayout = {
        let config = UnifiedASRProvider.config
        return FolderLayout(
            files: [config.family.vocab],
            directories: [
                config.family.streamingEncoderFile(precision: .int8, contextSuffix: config.contextSuffix),
                config.family.decoderFile,
                config.family.jointDecisionFile
            ]
        )
    }()

    /// What a model's folder must hold, or nil for a model that ships with
    /// macOS.
    static func layout(for definition: AppMode.ModelDefinition) -> FolderLayout? {
        switch definition.family {
        case .parakeetTDT:
            return parakeetLayout(for: definition.id)
        case .parakeetUnified:
            return parakeetUnifiedLayout
        case .appleSpeech:
            return nil
        }
    }

    /// File present at the root of every compiled CoreML `.mlmodelc` bundle.
    /// Used to confirm a bundle was fully written, not just created as an
    /// empty directory by an interrupted download.
    static let coreMLBundleMarkerFile = "coremldata.bin"

    static func validateParakeetModelFolder(
        at folder: URL,
        layout: FolderLayout = parakeetLayout
    ) -> ModelFolderValidation {
        let fm = FileManager.default
        let requiredAssets = layout.requiredAssets
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return ModelFolderValidation(
                folderExists: false,
                missingRequiredFiles: requiredAssets,
                hasWeights: false,
                readErrorDescription: nil
            )
        }

        let contents: [URL]
        do {
            contents = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        } catch {
            return ModelFolderValidation(
                folderExists: true,
                missingRequiredFiles: requiredAssets,
                hasWeights: false,
                readErrorDescription: error.localizedDescription
            )
        }

        let fileNames = Set(contents.map(\.lastPathComponent))
        let missingFiles = layout.files.filter { !fileNames.contains($0) }
        let missingDirs = layout.directories.filter { !fileNames.contains($0) }
        let hasWeights = layout.directories.allSatisfy { dirName in
            let marker = folder
                .appendingPathComponent(dirName)
                .appendingPathComponent(coreMLBundleMarkerFile)
            return fm.fileExists(atPath: marker.path)
        }

        return ModelFolderValidation(
            folderExists: true,
            missingRequiredFiles: missingFiles + missingDirs,
            hasWeights: hasWeights,
            readErrorDescription: nil
        )
    }

    static func validate(folder: URL, for definition: AppMode.ModelDefinition) -> ModelFolderValidation {
        guard let layout = layout(for: definition) else {
            return ModelFolderValidation(
                folderExists: true,
                missingRequiredFiles: [],
                hasWeights: true,
                readErrorDescription: nil
            )
        }
        return validateParakeetModelFolder(at: folder, layout: layout)
    }
}

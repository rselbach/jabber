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

    /// v3 ships its own joint graph, which computes the top-K outputs the
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

    static let requiredCoreMLTransducerFiles = [
        "config.json",
        "vocab.json"
    ]

    static let requiredCoreMLTransducerDirectories = [
        "encoder.mlmodelc",
        "decoder.mlmodelc",
        "joint.mlmodelc"
    ]

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

    static func validateCoreMLTransducerModelFolder(at folder: URL) -> ModelFolderValidation {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return ModelFolderValidation(
                folderExists: false,
                missingRequiredFiles: requiredCoreMLTransducerFiles + requiredCoreMLTransducerDirectories,
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
                missingRequiredFiles: requiredCoreMLTransducerFiles + requiredCoreMLTransducerDirectories,
                hasWeights: false,
                readErrorDescription: error.localizedDescription
            )
        }

        let fileNames = Set(contents.map(\.lastPathComponent))
        let missingFiles = requiredCoreMLTransducerFiles.filter { !fileNames.contains($0) }
        let missingDirs = requiredCoreMLTransducerDirectories.filter { !fileNames.contains($0) }
        let missing = missingFiles + missingDirs
        let hasWeights = requiredCoreMLTransducerDirectories.allSatisfy { dirName in
            let marker = folder
                .appendingPathComponent(dirName)
                .appendingPathComponent(coreMLBundleMarkerFile)
            return fm.fileExists(atPath: marker.path)
        }

        return ModelFolderValidation(
            folderExists: true,
            missingRequiredFiles: missing,
            hasWeights: hasWeights,
            readErrorDescription: nil
        )
    }

    static func validate(folder: URL, for definition: AppMode.ModelDefinition) -> ModelFolderValidation {
        switch definition.family {
        case .parakeetTDT:
            return validateParakeetModelFolder(at: folder, layout: parakeetLayout(for: definition.id))
        case .nemotronASR:
            return validateCoreMLTransducerModelFolder(at: folder)
        case .appleSpeech:
            return ModelFolderValidation(
                folderExists: true,
                missingRequiredFiles: [],
                hasWeights: true,
                readErrorDescription: nil
            )
        }
    }
}

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
    static let requiredParakeetFiles = [
        "parakeet_vocab.json"
    ]

    static let requiredParakeetDirectories = [
        "Preprocessor.mlmodelc",
        "Encoder.mlmodelc",
        "Decoder.mlmodelc",
        "JointDecision.mlmodelc"
    ]

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

    static func validateParakeetModelFolder(at folder: URL) -> ModelFolderValidation {
        let fm = FileManager.default
        let requiredAssets = requiredParakeetFiles + requiredParakeetDirectories
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
        let missingFiles = requiredParakeetFiles.filter { !fileNames.contains($0) }
        let missingDirs = requiredParakeetDirectories.filter { !fileNames.contains($0) }
        let hasWeights = requiredParakeetDirectories.allSatisfy { dirName in
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

    static func validate(folder: URL, for family: AppMode.ModelFamily) -> ModelFolderValidation {
        switch family {
        case .parakeetTDT:
            return validateParakeetModelFolder(at: folder)
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

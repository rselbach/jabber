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
    static let requiredQwen3ASRFiles = [
        "config.json",
        "vocab.json",
        "merges.txt",
        "tokenizer_config.json"
    ]

    static let requiredParakeetFiles = [
        "config.json",
        "vocab.json"
    ]

    static let requiredParakeetDirectories = [
        "encoder.mlmodelc",
        "decoder.mlmodelc",
        "joint.mlmodelc"
    ]

    static func validateQwen3ASRModelFolder(at folder: URL) -> ModelFolderValidation {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return ModelFolderValidation(
                folderExists: false,
                missingRequiredFiles: requiredQwen3ASRFiles,
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
                missingRequiredFiles: requiredQwen3ASRFiles,
                hasWeights: false,
                readErrorDescription: error.localizedDescription
            )
        }

        let fileNames = Set(contents.map(\.lastPathComponent))
        let missingRequiredFiles = requiredQwen3ASRFiles.filter { !fileNames.contains($0) }
        let hasWeights = contents.contains { $0.pathExtension == "safetensors" }

        return ModelFolderValidation(
            folderExists: true,
            missingRequiredFiles: missingRequiredFiles,
            hasWeights: hasWeights,
            readErrorDescription: nil
        )
    }

    static func validateParakeetModelFolder(at folder: URL) -> ModelFolderValidation {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return ModelFolderValidation(
                folderExists: false,
                missingRequiredFiles: requiredParakeetFiles + requiredParakeetDirectories,
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
                missingRequiredFiles: requiredParakeetFiles + requiredParakeetDirectories,
                hasWeights: false,
                readErrorDescription: error.localizedDescription
            )
        }

        let fileNames = Set(contents.map(\.lastPathComponent))
        let missingFiles = requiredParakeetFiles.filter { !fileNames.contains($0) }
        let missingDirs = requiredParakeetDirectories.filter { !fileNames.contains($0) }
        let missing = missingFiles + missingDirs
        let hasWeights = requiredParakeetDirectories.allSatisfy { fileNames.contains($0) }

        return ModelFolderValidation(
            folderExists: true,
            missingRequiredFiles: missing,
            hasWeights: hasWeights,
            readErrorDescription: nil
        )
    }

    static func validate(folder: URL, for family: AppMode.ModelFamily) -> ModelFolderValidation {
        switch family {
        case .qwen3ASR:
            return validateQwen3ASRModelFolder(at: folder)
        case .parakeetASR, .nemotronASR:
            return validateParakeetModelFolder(at: folder)
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

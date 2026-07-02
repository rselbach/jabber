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
        case .qwen3ASR:
            return validateQwen3ASRModelFolder(at: folder)
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

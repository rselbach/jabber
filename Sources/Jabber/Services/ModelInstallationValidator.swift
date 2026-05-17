import Foundation

struct ModelFolderValidation: Equatable {
    let folderExists: Bool
    let missingRequiredFiles: [String]
    let hasSafetensors: Bool
    let readErrorDescription: String?

    var isComplete: Bool {
        folderExists
            && readErrorDescription == nil
            && missingRequiredFiles.isEmpty
            && hasSafetensors
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
        if !hasSafetensors {
            problems.append("missing safetensors weights")
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

    static func validateQwen3ASRModelFolder(at folder: URL) -> ModelFolderValidation {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return ModelFolderValidation(
                folderExists: false,
                missingRequiredFiles: requiredQwen3ASRFiles,
                hasSafetensors: false,
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
                hasSafetensors: false,
                readErrorDescription: error.localizedDescription
            )
        }

        let fileNames = Set(contents.map(\.lastPathComponent))
        let missingRequiredFiles = requiredQwen3ASRFiles.filter { !fileNames.contains($0) }
        let hasSafetensors = contents.contains { $0.pathExtension == "safetensors" }

        return ModelFolderValidation(
            folderExists: true,
            missingRequiredFiles: missingRequiredFiles,
            hasSafetensors: hasSafetensors,
            readErrorDescription: nil
        )
    }
}

import Foundation
import os

/// Application-wide constants and notification names
enum Constants {
    /// Notification names used throughout the application
    enum Notifications {
        /// Posted when the selected Whisper model changes
        static let modelDidChange = Notification.Name("com.rselbach.jabber.modelDidChange")
    }

    /// Helper for locating Whisper model files
    enum ModelPaths {
        private static let repoName = "argmaxinc/whisperkit-coreml"
        private static let logger = Logger(subsystem: "com.rselbach.jabber", category: "ModelPaths")

        /// Returns the base directory where models are stored
        static func modelsBaseURL() -> URL? {
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                return nil
            }
            return docs
                .appendingPathComponent("huggingface")
                .appendingPathComponent("models")
                .appendingPathComponent(repoName)
        }

        /// Finds the local folder for a specific model ID
        /// - Parameter modelId: The model identifier (e.g., "base", "tiny", "large-v3")
        /// - Returns: URL to the model folder if found, nil otherwise
        static func localModelFolder(for modelId: String) -> URL? {
            guard let base = modelsBaseURL() else { return nil }

            let fm = FileManager.default
            guard fm.fileExists(atPath: base.path) else { return nil }

            let contents: [String]
            do {
                contents = try fm.contentsOfDirectory(atPath: base.path)
            } catch {
                logger.warning("Failed to read model directory at \(base.path): \(error.localizedDescription)")
                return nil
            }

            let suffixPattern = "-\(modelId)"

            for folder in contents {
                let matchesExactSuffix = folder.hasSuffix(suffixPattern)
                let matchesExactName = folder == modelId

                guard matchesExactSuffix || matchesExactName else {
                    continue
                }

                let folderURL = base.appendingPathComponent(folder)
                let configPath = folderURL.appendingPathComponent("config.json")

                guard fm.fileExists(atPath: configPath.path) else {
                    continue
                }

                return folderURL
            }

            return nil
        }
    }
}

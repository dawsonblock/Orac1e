import Foundation

@MainActor
public final class FailureArtifactWriter {
    private let baseURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
        try? FileManager.default.createDirectory(
            at: baseURL,
            withIntermediateDirectories: true
        )
    }

    public convenience init() {
        self.init(baseURL: ExperienceStore.traceRootDirectory().appendingPathComponent("artifacts", isDirectory: true))
    }

    public func writeTextArtifact(
        sessionID: String,
        stepID: Int,
        name: String,
        contents: String
    ) -> String? {
        let fileURL = artifactURL(sessionID: sessionID, stepID: stepID, name: name, ext: "txt")
        do {
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL.path
        } catch {
            Log.warn("Failed to write text artifact: \(error)")
            return nil
        }
    }

    public func writeObservationArtifact(
        sessionID: String,
        stepID: Int,
        name: String,
        observation: Observation
    ) -> String? {
        let fileURL = artifactURL(sessionID: sessionID, stepID: stepID, name: name, ext: "json")
        let encoder = OracleJSONCoding.makeEncoder(outputFormatting: [.prettyPrinted, .sortedKeys])

        do {
            let data = try encoder.encode(observation)
            try data.write(to: fileURL)
            return fileURL.path
        } catch {
            Log.warn("Failed to write observation artifact: \(error)")
            return nil
        }
    }

    public func writeScreenshotArtifact(
        sessionID: String,
        stepID: Int,
        appName: String?
    ) -> String? {
        let fileURL = artifactURL(sessionID: sessionID, stepID: stepID, name: "screenshot", ext: "png")
        let result = AXScanner.screenshot(appName: appName, fullResolution: false)

        guard result.success,
              let data = result.data,
              let base64 = data["image"] as? String,
              let png = Data(base64Encoded: base64)
        else {
            return nil
        }

        do {
            try png.write(to: fileURL)
            return fileURL.path
        } catch {
            Log.warn("Failed to write screenshot artifact: \(error)")
            return nil
        }
    }

    private func artifactURL(sessionID: String, stepID: Int, name: String, ext: String) -> URL {
        baseURL.appendingPathComponent("\(sessionID)-step\(stepID)-\(sanitize(name)).\(ext)")
    }

    private func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }.reduce(into: "") { result, character in
            result.append(character)
        }
    }
}

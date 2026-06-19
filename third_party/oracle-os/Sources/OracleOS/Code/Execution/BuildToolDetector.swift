import Foundation

public enum BuildTool: String, Codable, Sendable, CaseIterable {
    case swiftPackage = "swift-package"
    case npm
    case pytest
    case xcodebuild
    case unknown
}

public enum BuildToolDetector {
    public static func detect(at workspaceRoot: URL) -> BuildTool {
        let fm = FileManager.default
        if fm.fileExists(atPath: workspaceRoot.appendingPathComponent("Package.swift").path) {
            return .swiftPackage
        }
        if fm.fileExists(atPath: workspaceRoot.appendingPathComponent("package.json").path) {
            return .npm
        }
        if fm.fileExists(atPath: workspaceRoot.appendingPathComponent("pytest.ini").path)
            || fm.fileExists(atPath: workspaceRoot.appendingPathComponent("pyproject.toml").path)
        {
            return .pytest
        }
        if let files = try? fm.contentsOfDirectory(atPath: workspaceRoot.path),
           files.contains(where: { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") })
        {
            return .xcodebuild
        }
        return .unknown
    }

    public static func defaultBuildCommand(
        for buildTool: BuildTool,
        workspaceRoot: URL
    ) -> CommandSpec? {
        switch buildTool {
        case .swiftPackage:
            return CommandSpec(
                category: .build,
                executable: "/usr/bin/env",
                arguments: ["swift", "build"],
                workspaceRoot: workspaceRoot.path,
                summary: "swift build"
            )
        case .npm:
            return CommandSpec(
                category: .build,
                executable: "/usr/bin/env",
                arguments: ["npm", "run", "build"],
                workspaceRoot: workspaceRoot.path,
                summary: "npm run build"
            )
        case .xcodebuild:
            return CommandSpec(
                category: .build,
                executable: "/usr/bin/env",
                arguments: ["xcodebuild", "-quiet"],
                workspaceRoot: workspaceRoot.path,
                summary: "xcodebuild -quiet"
            )
        case .pytest, .unknown:
            return nil
        }
    }

    public static func defaultTestCommand(
        for buildTool: BuildTool,
        workspaceRoot: URL
    ) -> CommandSpec? {
        switch buildTool {
        case .swiftPackage:
            return CommandSpec(
                category: .test,
                executable: "/usr/bin/env",
                arguments: ["swift", "test"],
                workspaceRoot: workspaceRoot.path,
                summary: "swift test"
            )
        case .npm:
            return CommandSpec(
                category: .test,
                executable: "/usr/bin/env",
                arguments: ["npm", "test", "--", "--runInBand"],
                workspaceRoot: workspaceRoot.path,
                summary: "npm test"
            )
        case .pytest:
            return CommandSpec(
                category: .test,
                executable: "/usr/bin/env",
                arguments: ["pytest"],
                workspaceRoot: workspaceRoot.path,
                summary: "pytest"
            )
        case .xcodebuild:
            return CommandSpec(
                category: .test,
                executable: "/usr/bin/env",
                arguments: ["xcodebuild", "test", "-quiet"],
                workspaceRoot: workspaceRoot.path,
                summary: "xcodebuild test -quiet"
            )
        case .unknown:
            return nil
        }
    }
}

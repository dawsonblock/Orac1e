import Foundation

public enum GoalClassifier {
    public static func classify(
        description: String,
        workspaceRoot: URL? = nil
    ) -> AgentKind {
        let lowercased = description.lowercased()
        let codeSignals = [
            "fix",
            "build",
            "test",
            "compile",
            "refactor",
            "repository",
            "repo",
            "patch",
            "commit",
            "branch",
            "push",
            "lint",
            "format",
            "debug",
        ]
        let osSignals = [
            "open",
            "click",
            "focus",
            "browser",
            "finder",
            "slack",
            "mail",
            "download",
            "upload",
            "window",
            "tab",
            "app",
        ]

        let codeMatches = codeSignals.filter(lowercased.contains).count
        let osMatches = osSignals.filter(lowercased.contains).count

        if workspaceRoot != nil && codeMatches > 0 && osMatches > 0 {
            return .mixed
        }
        if codeMatches > 0 && osMatches > 0 {
            return .mixed
        }
        if codeMatches > 0 {
            return .code
        }
        return .os
    }
}

import Foundation

public enum ProtectedOperation: String, Codable, Sendable, CaseIterable {
    case send
    case purchase
    case delete
    case uploadShare = "upload-share"
    case credentialEntry = "credential-entry"
    case settingsChange = "settings-change"
    case terminalControl = "terminal-control"
    case clipboardExfiltration = "clipboard-exfiltration"
    case workspaceWrite = "workspace-write"
    case gitPush = "git-push"
    case destructiveVCS = "destructive-vcs"
    case externalNetworkFetch = "external-network-fetch"
}

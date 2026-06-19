import Foundation

public struct CodingCommandApprovalPolicy: Sendable {
    public let allowShell: Bool

    public init(allowShell: Bool) {
        self.allowShell = allowShell
    }

    public func allow(_ command: String) -> Bool {
        guard allowShell else {
            return false
        }
        let blocked = ["curl ", "wget ", "rm -rf", "sudo ", "docker run", "ssh "]
        return !blocked.contains(where: { command.contains($0) })
    }
}

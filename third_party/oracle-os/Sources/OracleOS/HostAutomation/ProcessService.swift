import AppKit
import Foundation

@MainActor
public final class ProcessService {
    public init() {}

    public func processIdentifier(forAppNamed name: String) -> Int32? {
        NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name })?.processIdentifier
    }

    public func runningProcessNames() -> [String] {
        NSWorkspace.shared.runningApplications.compactMap(\.localizedName).sorted()
    }
}

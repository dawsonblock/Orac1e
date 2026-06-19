import Foundation

@MainActor
public protocol ApplicationServicing {
    func runningApplications() -> [HostApplicationSnapshot]
    func frontmostApplication() -> HostApplicationSnapshot?
    @discardableResult
    func activateApplication(named name: String) -> Bool
}

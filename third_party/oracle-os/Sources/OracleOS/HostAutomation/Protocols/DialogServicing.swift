import Foundation

@MainActor
public protocol DialogServicing {
    func activeDialog(appName: String?) -> HostDialogSnapshot?
}

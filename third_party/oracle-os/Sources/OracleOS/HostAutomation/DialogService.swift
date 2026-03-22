import Foundation

@MainActor
public final class DialogService: DialogServicing {
    private static let dialogButtonLabels = Set(["ok", "cancel", "allow", "don’t allow", "dont allow", "open", "save", "delete"])

    public init() {}

    public func activeDialog(appName: String?) -> HostDialogSnapshot? {
        let observation = ObservationBuilder.capture(appName: appName, maxDepth: 8, maxElements: 80)
        let resolvedAppName = observation.app ?? appName ?? "Unknown"
        let buttonLabels = observation.elements
            .filter { $0.role == "AXButton" }
            .compactMap(\.label)
            .filter { Self.dialogButtonLabels.contains($0.lowercased()) }

        let modalTitle = observation.windowTitle?.lowercased()
        let looksModal = buttonLabels.count >= 2
            || modalTitle?.contains("dialog") == true
            || modalTitle?.contains("alert") == true

        guard looksModal else { return nil }

        return HostDialogSnapshot(
            id: [resolvedAppName, observation.windowTitle ?? "dialog"].joined(separator: "|"),
            title: observation.windowTitle,
            message: observation.elements.compactMap(\.label).first(where: { !$0.isEmpty }),
            buttonLabels: Array(Set(buttonLabels)).sorted()
        )
    }
}

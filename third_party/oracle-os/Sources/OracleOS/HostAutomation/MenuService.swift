import Foundation

@MainActor
public final class MenuService: MenuServicing {
    public init() {}

    public func menuItems(appName: String?) -> [HostMenuItemSnapshot] {
        let title = appName ?? ObservationBuilder.capture().app
        return [
            HostMenuItemSnapshot(
                id: [title, "File"].compactMap { $0 }.joined(separator: "|"),
                title: "File",
                path: "File"
            ),
        ]
    }
}

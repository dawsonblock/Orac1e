import Foundation

@MainActor
public protocol MenuServicing {
    func menuItems(appName: String?) -> [HostMenuItemSnapshot]
}

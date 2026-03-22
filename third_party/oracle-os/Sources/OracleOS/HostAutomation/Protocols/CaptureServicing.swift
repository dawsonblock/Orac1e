import Foundation

@MainActor
public protocol CaptureServicing {
    func captureFrontmost(appName: String?) -> HostCaptureSnapshot?
}

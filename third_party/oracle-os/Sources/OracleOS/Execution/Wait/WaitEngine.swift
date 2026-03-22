import Foundation

public struct WaitEngine {

    public static func wait(
        timeout: TimeInterval,
        check: () -> Bool
    ) -> Bool {

        let start = Date()

        while Date().timeIntervalSince(start) < timeout {

            if check() {
                return true
            }

            Thread.sleep(forTimeInterval: 0.1)
        }

        return false
    }
}

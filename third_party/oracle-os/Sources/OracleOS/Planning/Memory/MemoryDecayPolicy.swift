import Foundation

public enum MemoryDecayPolicy {
    public static func freshnessMultiplier(
        since date: Date,
        now: Date = Date(),
        freshWindow: TimeInterval = 60 * 60 * 24 * 30,
        staleWindow: TimeInterval = 60 * 60 * 24 * 90
    ) -> Double {
        let age = now.timeIntervalSince(date)
        if age <= freshWindow {
            return 1
        }
        if age >= staleWindow {
            return 0
        }

        let progress = (age - freshWindow) / max(staleWindow - freshWindow, 1)
        return max(0, 1 - progress)
    }
}

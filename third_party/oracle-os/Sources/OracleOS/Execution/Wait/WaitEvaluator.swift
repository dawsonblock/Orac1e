import Foundation

@MainActor
public enum WaitEvaluator {
    public static func isSatisfied(_ condition: WaitCondition, appName: String?) -> Bool {
        let observation = ObservationBuilder.capture(appName: appName)
        return isSatisfied(condition, observation: observation)
    }

    public static func isSatisfied(_ condition: WaitCondition, observation: Observation) -> Bool {
        switch condition {
        case .appFrontmost(let value):
            return observation.app?.localizedCaseInsensitiveContains(value) == true

        case .urlContains(let value):
            return observation.url?.localizedCaseInsensitiveContains(value) == true

        case .titleContains(let value):
            return observation.windowTitle?.localizedCaseInsensitiveContains(value) == true

        case .elementExists(let target):
            return observation.elements.contains { ActionVerifier.matchesElement($0, query: target) }

        case .elementGone(let target):
            return !observation.elements.contains { ActionVerifier.matchesElement($0, query: target) }

        case .urlChanged(let baseline):
            return observation.url != baseline && observation.url != nil

        case .titleChanged(let baseline):
            return observation.windowTitle != baseline && observation.windowTitle != nil

        case .focusEquals(let target):
            guard let focused = observation.focusedElement else { return false }
            return ActionVerifier.matchesElement(focused, query: target)

        case .valueEquals(let target, let value):
            return observation.elements.first(where: { ActionVerifier.matchesElement($0, query: target) })?.value == value

        case .elementFocused(let target):
            guard let focused = observation.focusedElement else { return false }
            return ActionVerifier.matchesElement(focused, query: target)

        case .screenStable:
            // Placeholder for actual stability check
            return true
        }
    }
}

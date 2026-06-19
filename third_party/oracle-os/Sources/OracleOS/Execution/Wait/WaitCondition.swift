public enum WaitCondition {

    case elementExists(String)
    case elementGone(String)
    case elementFocused(String)
    case appFrontmost(String)
    case urlContains(String)
    case titleContains(String)
    case urlChanged(String?)
    case titleChanged(String?)
    case screenStable
    case focusEquals(String)
    case valueEquals(String, String)

    public static func parse(condition: String, value: String?, baseline: String? = nil) -> WaitCondition? {
        switch condition {
        case "appFrontmost": return value.map { .appFrontmost($0) }
        case "urlContains": return value.map { .urlContains($0) }
        case "windowTitleContains": return value.map { .titleContains($0) }
        case "titleContains": return value.map { .titleContains($0) }
        case "elementExists": return value.map { .elementExists($0) }
        case "elementGone": return value.map { .elementGone($0) }
        case "urlChanged": return .urlChanged(baseline)
        case "titleChanged": return .titleChanged(baseline)
        case "focusEquals": return value.map { .focusEquals($0) }
        case "valueEquals": 
            guard let val = value else { return nil }
            let parts = val.components(separatedBy: "=")
            if parts.count == 2 {
                return .valueEquals(parts[0], parts[1])
            }
            return nil
        default: return nil
        }
    }
}

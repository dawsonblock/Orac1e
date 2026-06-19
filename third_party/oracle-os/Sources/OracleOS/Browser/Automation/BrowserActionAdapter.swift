import Foundation

public enum BrowserActionAdapter {
    public static func clickIntent(
        selection: BrowserTargetSelection,
        appName: String
    ) -> ActionIntent {
        let element = selection.match.element
        return ActionIntent.click(
            app: appName,
            query: element.label,
            role: element.role,
            domID: element.domID,
            postconditions: [
                .elementFocused(element.domID ?? element.id),
            ]
        )
    }

    public static func typeIntent(
        selection: BrowserTargetSelection,
        text: String,
        appName: String
    ) -> ActionIntent {
        let element = selection.match.element
        return ActionIntent.type(
            app: appName,
            into: element.label,
            domID: element.domID,
            text: text,
            postconditions: [.elementValueEquals(element.domID ?? element.id, text)]
        )
    }
}

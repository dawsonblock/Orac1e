import Foundation

public enum EventKinds {
    public static let commandStarted = "CommandStarted"
    public static let commandSucceeded = "CommandSucceeded"
    public static let commandFailed = "CommandFailed"
    public static let policyRejected = "PolicyRejected"

    public static let uiObservationCaptured = "UIObservationCaptured"
    public static let appFocused = "AppFocused"
    public static let windowFocused = "WindowFocused"
    public static let navigationObserved = "NavigationObserved"
    public static let elementClicked = "ElementClicked"
    public static let textEntered = "TextEntered"

    public static let repositoryObserved = "RepositoryObserved"
    public static let fileRead = "FileRead"
    public static let fileModified = "FileModified"
    public static let buildCompleted = "BuildCompleted"
    public static let testsCompleted = "TestsCompleted"

    public static let lessonPromoted = "LessonPromoted"
    public static let recipeRecorded = "RecipeRecorded"
    public static let traceSaved = "TraceSaved"
}

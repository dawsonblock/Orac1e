import Foundation

public enum DefaultReducers {
    public static func make() -> [any EventReducer] {
        [
            composite(),
        ]
    }

    public static func composite() -> CompositeStateReducer {
        CompositeStateReducer(
            reducers: [
                RuntimeStateReducer(),
                UIStateReducer(),
                ProjectStateReducer(),
                MemoryStateReducer(),
            ]
        )
    }
}

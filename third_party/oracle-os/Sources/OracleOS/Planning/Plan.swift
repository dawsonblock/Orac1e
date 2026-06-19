public struct Plan {

    public let goal: String
    public let steps: [String]

    public init(goal: String, steps: [String]) {
        self.goal = goal
        self.steps = steps
    }
}

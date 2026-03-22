public struct WorldState: Sendable {
    public internal(set) var observationHash: String
    public internal(set) var planningState: PlanningState
    public internal(set) var beliefStateID: String?

    public internal(set) var observation: Observation
    public internal(set) var repositorySnapshot: RepositorySnapshot?

    public internal(set) var lastAction: ActionIntent?

    public init(
        observation: Observation,
        lastAction: ActionIntent? = nil,
        beliefStateID: String? = nil,
        repositorySnapshot: RepositorySnapshot? = nil,
        stateAbstraction: StateAbstraction = StateAbstraction()
    ) {
        let observationHash = ObservationHash.hash(observation)
        self.observationHash = observationHash
        self.planningState = stateAbstraction.abstract(
            observation: observation,
            repositorySnapshot: repositorySnapshot,
            observationHash: observationHash
        )
        self.beliefStateID = beliefStateID
        self.observation = observation
        self.repositorySnapshot = repositorySnapshot
        self.lastAction = lastAction
    }

    public init(
        observationHash: String,
        planningState: PlanningState,
        beliefStateID: String? = nil,
        observation: Observation,
        repositorySnapshot: RepositorySnapshot? = nil,
        lastAction: ActionIntent? = nil
    ) {
        self.observationHash = observationHash
        self.planningState = planningState
        self.beliefStateID = beliefStateID
        self.observation = observation
        self.repositorySnapshot = repositorySnapshot
        self.lastAction = lastAction
    }
}

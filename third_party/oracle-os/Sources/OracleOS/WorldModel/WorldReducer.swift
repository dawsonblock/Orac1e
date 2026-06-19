public struct WorldReducer {

    public static func update(
        state: WorldState,
        newObservation: Observation,
        stateAbstraction: StateAbstraction = StateAbstraction()
    ) -> WorldState {

        var new = state
        new.observation = newObservation
        let observationHash = ObservationHash.hash(newObservation)
        new.observationHash = observationHash
        new.planningState = stateAbstraction.abstract(
            observation: newObservation,
            observationHash: observationHash
        )
        return new
    }
}

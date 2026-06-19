import Foundation

public enum TraceEnricher {
    public static func mergedNotes(
        existing: String?,
        planningStateID: PlanningStateID?,
        actionContractID: String?,
        postconditionClass: PostconditionClass?,
        executionMode: String?,
        recoverySource: String?
    ) -> String? {
        let fields = [
            existing,
            planningStateID.map { "planning_state=\($0.rawValue)" },
            actionContractID.map { "action_contract=\($0)" },
            postconditionClass.map { "postcondition_class=\($0.rawValue)" },
            executionMode.map { "execution_mode=\($0)" },
            recoverySource.map { "recovery_source=\($0)" },
        ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

        guard !fields.isEmpty else { return nil }
        return fields.joined(separator: " | ")
    }
}

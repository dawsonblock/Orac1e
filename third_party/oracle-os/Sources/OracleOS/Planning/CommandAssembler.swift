import Foundation
/// Assembles a final Command from a domain planner decision.
public struct CommandAssembler {
    public init() {}
    public func assemble(intent: Intent, domain: IntentDomain, context: PlanningContext) throws -> Command {
        let meta = CommandMetadata(intentID: intent.id, source: "command-assembler.\(domain.rawValue)")
        switch domain {
        case .ui:
            return Command(type: .ui, payload: .ui(UIAction(name: "focus")), metadata: meta)
        case .code:
            return Command(type: .code, payload: .code(CodeAction(name: "searchRepository", query: intent.objective)), metadata: meta)
        case .system:
            return Command(type: .ui, payload: .ui(UIAction(name: "launchApp", app: intent.objective)), metadata: meta)
        case .mixed:
            _ = context
            return Command(type: .code, payload: .code(CodeAction(name: "searchRepository", query: intent.objective)), metadata: meta)
        }
    }
}

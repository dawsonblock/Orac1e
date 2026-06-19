import Foundation

/// The canonical repair pipeline for autonomous code fixes.
///
/// Pipeline stages:
///
///     failure
///     ↓
///     localization (via ``ProgramKnowledgeGraph``)
///     ↓
///     candidate symbols / root causes
///     ↓
///     patch candidates
///     ↓
///     sandbox validation
///     ↓
///     build / test / regression check
///     ↓
///     rank best fix
///     ↓
///     apply
///
/// **Invariants:**
/// - Localization is mandatory before patch generation.
/// - Patch candidates are fed from symbol/root-cause candidates, not just file paths.
/// - Sandbox validation is mandatory before apply.
/// - Regression checks run on every accepted patch.
/// - Candidates are ranked with structural evidence, not just LLM preference.
public enum RepairPipeline {

    /// The ordered stages of a repair attempt.
    public enum Stage: String, Sendable, CaseIterable {
        case failure
        case localization
        case candidateSymbols
        case patchCandidates
        case sandboxValidation
        case regressionCheck
        case rankFix
        case apply
    }

    /// Validates that a repair attempt followed the required stage ordering.
    ///
    /// Returns the first missing stage, or `nil` if the sequence is valid.
    public static func validateOrder(_ completedStages: [Stage]) -> Stage? {
        let required = Stage.allCases
        for (index, stage) in required.enumerated() {
            if index < completedStages.count {
                guard completedStages[index] == stage else {
                    return stage
                }
            }
        }
        return nil
    }

    /// Returns `true` when localization has been completed before patch generation.
    public static func localizationPrecedesPatching(
        _ completedStages: [Stage]
    ) -> Bool {
        guard let locIdx = completedStages.firstIndex(of: .localization),
              let patchIdx = completedStages.firstIndex(of: .patchCandidates)
        else {
            return completedStages.contains(.localization)
                || !completedStages.contains(.patchCandidates)
        }
        return locIdx < patchIdx
    }

    /// Returns `true` when sandbox validation occurred before apply.
    public static func sandboxPrecedesApply(
        _ completedStages: [Stage]
    ) -> Bool {
        guard let sandboxIdx = completedStages.firstIndex(of: .sandboxValidation),
              let applyIdx = completedStages.firstIndex(of: .apply)
        else {
            return completedStages.contains(.sandboxValidation)
                || !completedStages.contains(.apply)
        }
        return sandboxIdx < applyIdx
    }
}

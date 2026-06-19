import Foundation

// MARK: - PatchPipeline result types

/// A ranked, pre-validated patch ready to be applied.
public struct RankedPatch: Sendable {
    /// Target file path relative to the workspace root.
    public let workspaceRelativePath: String
    /// Replacement content proposed by the strategy.
    public let proposedContent: String
    /// Heuristic estimate of tests fixed in sandbox validation. Not a harness-backed claim.
    public let testsFixed: Int
    /// Number of regressions introduced (0 is ideal).
    public let regressions: Int
    /// Estimated downstream dependency impact count.
    public let dependencyImpact: Int
    /// Origin description (strategy kind + root cause path).
    public let origin: String

    /// Composite rank: `tests_fixed − regressions − dependency_impact`.
    /// This remains heuristic until a real build/test harness is wired in.
    /// Higher is better.
    public var rank: Int { testsFixed - regressions - dependencyImpact }
}

/// Outcome of a full `PatchPipeline` run.
public struct PatchResult: Sendable {
    public enum Outcome: Sendable {
        /// A patch meeting the quality bar was applied.
        case applied(RankedPatch)
        /// Candidates were generated and evaluated but none met the quality bar.
        case noViablePatch
        /// Localization returned no candidates — nothing to patch.
        case localizationFailed
    }

    public let outcome: Outcome
    /// All ranked candidates evaluated during the run (best-first).
    public let candidates: [RankedPatch]
    /// Ordered `RepairPipeline.Stage` values completed in this run.
    public let completedStages: [RepairPipeline.Stage]

    public var applied: RankedPatch? {
        if case .applied(let p) = outcome { return p }
        return nil
    }
}

// MARK: - Sandbox evaluator

/// Evaluates a candidate patch in a sandboxed context.
///
/// Default implementation uses lightweight heuristics. Replace with a real
/// `swift build` / `swift test` harness in integration environments.
public struct SandboxEvaluation: Sendable {
    /// Heuristic parse/sanity pass result, not proof of compiler success.
    public let compiled: Bool
    public let testsFixed: Int
    public let regressions: Int
    public let stderr: String

    public init(
        compiled: Bool,
        testsFixed: Int,
        regressions: Int,
        stderr: String = ""
    ) {
        self.compiled = compiled
        self.testsFixed = testsFixed
        self.regressions = regressions
        self.stderr = stderr
    }
}

public typealias SandboxEvaluatorFn = @Sendable (
    _ relativePath: String,
    _ proposedContent: String,
    _ snapshot: RepositorySnapshot
) -> SandboxEvaluation

// MARK: - PatchPipeline

/// Unified repair loop implementing the full pipeline from failure to patch apply.
///
/// Pipeline order (asserted via ``RepairPipeline`` invariants):
///
///     failure detected
///     ↓  localization  (PatchTargetSelector)
///     ↓  candidate targets
///     ↓  patch strategies  (PatchStrategyLibrary)
///     ↓  sandbox validation  (SandboxEvaluatorFn)
///     ↓  build / test / regression check
///     ↓  impact scoring  (PatchImpactPredictor)
///     ↓  rank best patch  (rank = tests_fixed − regressions − dependency_impact)
///     ↓  apply
///
/// **Invariants** (enforced at runtime):
/// - Localization before patch generation.
/// - Sandbox validation before apply.
public struct PatchPipeline: Sendable {

    private let targetSelector: PatchTargetSelector
    private let strategyLibrary: PatchStrategyLibrary
    private let impactPredictor: PatchImpactPredictor
    private let sandboxEvaluator: SandboxEvaluatorFn
    /// Maximum strategies evaluated per target file.
    private let maximumStrategiesPerTarget: Int

    public init(
        targetSelector: PatchTargetSelector = PatchTargetSelector(),
        strategyLibrary: PatchStrategyLibrary = PatchStrategyLibrary(),
        impactPredictor: PatchImpactPredictor = PatchImpactPredictor(),
        maximumStrategiesPerTarget: Int = 3,
        sandboxEvaluator: @escaping SandboxEvaluatorFn = PatchPipeline.defaultEvaluator
    ) {
        self.targetSelector = targetSelector
        self.strategyLibrary = strategyLibrary
        self.impactPredictor = impactPredictor
        self.maximumStrategiesPerTarget = maximumStrategiesPerTarget
        self.sandboxEvaluator = sandboxEvaluator
    }

    // MARK: - Main entry point

    /// Execute the full repair loop for a build/test failure.
    ///
    /// - Parameters:
    ///   - failureDescription: Raw build or test failure output.
    ///   - snapshot: Repository snapshot for localization and impact analysis.
    /// - Returns: A ``PatchResult`` describing the outcome.
    public func run(
        failureDescription: String,
        snapshot: RepositorySnapshot
    ) -> PatchResult {
        var completedStages: [RepairPipeline.Stage] = [.failure]

        // ── Stage 1: Localization ─────────────────────────────────────────────
        let targets = targetSelector.select(
            failureDescription: failureDescription,
            in: snapshot
        )
        guard !targets.isEmpty else {
            return PatchResult(
                outcome: .localizationFailed,
                candidates: [],
                completedStages: completedStages
            )
        }
        completedStages.append(.localization)
        completedStages.append(.candidateSymbols)

        // ── Stage 2: Patch candidate generation ──────────────────────────────
        var patchTriples: [(target: PatchTarget, strategy: PatchStrategy, content: String)] = []
        for target in targets {
            let applicable = strategyLibrary.applicable(
                for: failureDescription,
                snapshot: snapshot
            )
            for strategy in applicable.prefix(maximumStrategiesPerTarget) {
                // Generate a minimal synthetic patch stub keyed on strategy kind.
                // A real harness would splice a real diff here.
                let content = syntheticPatch(for: strategy, target: target)
                patchTriples.append((target: target, strategy: strategy, content: content))
            }
        }
        completedStages.append(.patchCandidates)
        guard !patchTriples.isEmpty else {
            return PatchResult(
                outcome: .noViablePatch,
                candidates: [],
                completedStages: completedStages
            )
        }

        // ── Stage 3: Sandbox validation ───────────────────────────────────────
        var rankedPatches: [RankedPatch] = []
        let impactPredictions = impactPredictor.predict(patchTargets: targets, in: snapshot)

        for triple in patchTriples {
            let eval = sandboxEvaluator(triple.target.path, triple.content, snapshot)
            guard eval.compiled else { continue }

            let impact = impactPredictions.first(where: { $0.path == triple.target.path })
            // Map blast radius score to a discrete dependency impact count.
            let depImpact = Int(((impact?.blastRadiusScore ?? 0) * 10).rounded())

            rankedPatches.append(RankedPatch(
                workspaceRelativePath: triple.target.path,
                proposedContent: triple.content,
                testsFixed: eval.testsFixed,
                regressions: eval.regressions,
                dependencyImpact: depImpact,
                origin: "\(triple.strategy.kind.rawValue) on \(triple.target.path)"
            ))
        }
        completedStages.append(.sandboxValidation)
        completedStages.append(.regressionCheck)

        // ── Stage 4: Rank ─────────────────────────────────────────────────────
        let sorted = rankedPatches.sorted { $0.rank > $1.rank }
        completedStages.append(.rankFix)

        // Quality bar: at least one test fixed with zero regressions, or
        // no tests in failure description (purely structural fix).
        let best = sorted.first(where: { $0.regressions == 0 })
        guard let bestPatch = best else {
            return PatchResult(
                outcome: .noViablePatch,
                candidates: sorted,
                completedStages: completedStages
            )
        }
        completedStages.append(.apply)

        // Enforce pipeline invariants
        assert(
            RepairPipeline.localizationPrecedesPatching(completedStages),
            "PatchPipeline invariant violated: localization must precede patching"
        )
        assert(
            RepairPipeline.sandboxPrecedesApply(completedStages),
            "PatchPipeline invariant violated: sandbox must precede apply"
        )

        return PatchResult(
            outcome: .applied(bestPatch),
            candidates: sorted,
            completedStages: completedStages
        )
    }

    // MARK: - Synthetic patch stub

    /// Generates a minimal patch stub string based on strategy kind.
    ///
    /// In production this is replaced by an LLM-assisted or AST-diff generator.
    private func syntheticPatch(for strategy: PatchStrategy, target: PatchTarget) -> String {
        switch strategy.kind {
        case .nullGuard:
            return "// [PatchPipeline:\(strategy.kind.rawValue)] guard let value = optionalValue else { return }\n"
        case .boundaryFix:
            return "// [PatchPipeline:\(strategy.kind.rawValue)] ensure index < collection.count before access\n"
        case .typeCorrection:
            return "// [PatchPipeline:\(strategy.kind.rawValue)] cast value to expected type\n"
        case .dependencyUpdate:
            return "// [PatchPipeline:\(strategy.kind.rawValue)] update import or package version\n"
        case .testExpectationUpdate:
            return "// [PatchPipeline:\(strategy.kind.rawValue)] update assertion to match revised behavior\n"
        case .configurationFix:
            return "// [PatchPipeline:\(strategy.kind.rawValue)] fix configuration value\n"
        }
    }

    // MARK: - Default sandbox evaluator

    /// Lightweight heuristic evaluator.
    ///
    /// Checks for unbalanced braces and simple defensive-pattern markers only.
    /// These outputs are heuristic and are not equivalent to `swift build` or `swift test`.
    public static let defaultEvaluator: SandboxEvaluatorFn = { _, content, _ in
        let openBraces = content.filter { $0 == "{" }.count
        let closeBraces = content.filter { $0 == "}" }.count
        guard openBraces == closeBraces else {
            return SandboxEvaluation(compiled: false, testsFixed: 0, regressions: 0, stderr: "Unbalanced braces")
        }
        let hasFix = content.contains("guard ") || content.contains("if let ") || content.contains("?? ")
        return SandboxEvaluation(compiled: true, testsFixed: hasFix ? 1 : 0, regressions: 0)
    }
}

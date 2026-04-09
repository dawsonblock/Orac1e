import Foundation
import OracleControllerShared
import OracleOS

struct ControllerRuntimeResultMapper {
    let sessionID: String

    func mapActionResult(
        request: ActionRequest,
        result: ToolResult,
        resultingObservation: ObservationSnapshot?
    ) -> ActionRunResult {
        let runtimeBoundary = result.decodePayload(RuntimeBoundaryResult.self)
            ?? result.data.flatMap(RuntimeBoundaryResult.from(dict:))
        let actionResult = runtimeBoundary?.actionResult
            ?? result.data?["action_result"].flatMap { $0 as? [String: Any] }.flatMap(ActionResult.from(dict:))
        let traceResult = runtimeBoundary?.trace
            ?? result.data?["trace"].flatMap { $0 as? [String: Any] }.flatMap(TraceResult.from(dict:))
        let codeResult = runtimeBoundary?.codeExecution
            ?? result.data?["code_execution"].flatMap { $0 as? [String: Any] }.flatMap(CodeExecutionResult.from(dict:))

        return ActionRunResult(
            request: request,
            success: actionResult?.success ?? result.success,
            verified: actionResult?.verified ?? result.success,
            message: actionResult?.message ?? result.error ?? result.suggestion,
            failureClass: actionResult?.failureClass,
            method: actionResult?.method ?? runtimeBoundary?.method,
            elapsedMs: actionResult?.elapsedMs ?? 0,
            traceSessionID: traceResult?.sessionID,
            traceStepID: traceResult?.stepID,
            resultingObservation: resultingObservation,
            approvalRequestID: actionResult?.approvalRequestID,
            approvalStatus: actionResult?.approvalStatus,
            protectedOperation: actionResult?.protectedOperation,
            appProtectionProfile: actionResult?.appProtectionProfile,
            blockedByPolicy: actionResult?.blockedByPolicy ?? false,
            policyMode: actionResult?.policyDecision?.policyMode.rawValue,
            agentKind: traceResult?.agentKind,
            plannerFamily: traceResult?.plannerFamily,
            commandCategory: codeResult?.commandCategory ?? traceResult?.commandCategory,
            commandSummary: codeResult?.summary ?? traceResult?.commandSummary,
            workspaceRelativePath: codeResult?.workspaceRelativePath ?? traceResult?.workspaceRelativePath,
            buildResultSummary: codeResult?.buildResultSummary,
            testResultSummary: codeResult?.testResultSummary,
            patchID: codeResult?.patchID
        )
    }

    func mapRecipeRunResult(
        recipeName: String,
        totalStepsFallback: Int,
        result: ToolResult
    ) -> RecipeRunResultDocument {
        let runtimeBoundary = result.decodePayload(RuntimeBoundaryResult.self)
            ?? result.data.flatMap(RuntimeBoundaryResult.from(dict:))
        let recipeBoundary = runtimeBoundary?.recipeRun
            ?? result.decodePayload(RecipeRunBoundaryResult.self)
            ?? result.data.flatMap(RecipeRunBoundaryResult.from(dict:))
        let stepResults = (recipeBoundary?.stepResults ?? []).map { stepData in
            RecipeRunStepResult(
                id: stepData.step,
                action: stepData.action,
                success: stepData.success,
                durationMs: stepData.durationMs,
                error: stepData.error,
                note: stepData.note
            )
        }

        return RecipeRunResultDocument(
            recipeName: recipeName,
            success: result.success,
            stepsCompleted: recipeBoundary?.stepsCompleted ?? 0,
            totalSteps: recipeBoundary?.totalSteps ?? totalStepsFallback,
            error: result.error,
            traceSessionID: sessionID,
            stepResults: stepResults,
            paused: recipeBoundary?.pendingApproval == true,
            pendingApprovalRequestID: recipeBoundary?.approvalRequestID,
            resumeToken: recipeBoundary?.resumeToken
        )
    }
}
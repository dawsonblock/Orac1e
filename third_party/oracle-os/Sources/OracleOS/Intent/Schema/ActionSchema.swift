// ActionSchema.swift — Typed action schemas for the planner.
//
// The planner should never emit raw instructions like "move mouse to 840, 410".
// Instead it emits typed schemas such as `Click(Button("Send"))`.
// The executor resolves the actual coordinates.

import Foundation

// MARK: - Precondition / Postcondition

/// A condition the environment must satisfy before or after an action.
public enum SchemaCondition: Sendable, Codable, Hashable {
    /// The named element must be visible in the current UI state.
    case elementExists(kind: SemanticElementKind, label: String)
    /// The named application is the frontmost application.
    case appFrontmost(String)
    /// The window title contains the given substring.
    case windowTitleContains(String)
    /// The URL contains the given substring.
    case urlContains(String)
    /// A value field equals the expected string.
    case valueEquals(elementLabel: String, expected: String)
    /// Custom predicate described as free text (for extensibility).
    case custom(String)
}

// MARK: - Action schema

/// Typed, planner-level description of a single action.
///
/// Each schema declares explicit *preconditions* (what must hold before
/// the action runs) and *expected postconditions* (what should be true
/// after a successful execution). The ``VerifiedExecutor`` already
/// verifies postconditions; the schema makes them first-class for the
/// planner so it can reason about sequencing and recovery.
public struct ActionSchema: Sendable, Codable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let kind: ActionSchemaKind
    public let preconditions: [SchemaCondition]
    public let expectedPostconditions: [SchemaCondition]

    public init(
        id: String = UUID().uuidString,
        name: String,
        kind: ActionSchemaKind,
        preconditions: [SchemaCondition] = [],
        expectedPostconditions: [SchemaCondition] = []
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.preconditions = preconditions
        self.expectedPostconditions = expectedPostconditions
    }

    public func toDict() -> [String: Any] {
        [
            "id": id,
            "name": name,
            "kind": kind.rawValue,
            "preconditions": preconditions.map(conditionToDict),
            "expected_postconditions": expectedPostconditions.map(conditionToDict),
        ]
    }

    private func conditionToDict(_ condition: SchemaCondition) -> [String: Any] {
        switch condition {
        case .elementExists(let kind, let label):
            return ["type": "element_exists", "kind": kind.rawValue, "label": label]
        case .appFrontmost(let app):
            return ["type": "app_frontmost", "app": app]
        case .windowTitleContains(let value):
            return ["type": "window_title_contains", "value": value]
        case .urlContains(let value):
            return ["type": "url_contains", "value": value]
        case .valueEquals(let label, let expected):
            return ["type": "value_equals", "element_label": label, "expected": expected]
        case .custom(let description):
            return ["type": "custom", "description": description]
        }
    }
}

/// Broad classification of schema actions the planner can emit.
public enum ActionSchemaKind: String, Sendable, Codable, CaseIterable, Hashable {
    case click
    case type
    case focus
    case openApplication
    case closeWindow
    case navigate
    case scroll
    case runTests
    case buildProject
    case applyPatch
    case commitPatch
    case revertPatch
    case dismissModal
    case custom

    /// Whether this action kind operates on code/repository state.
    public var isCodeAction: Bool {
        switch self {
        case .runTests, .buildProject, .applyPatch, .commitPatch, .revertPatch:
            return true
        default:
            return false
        }
    }
}

// MARK: - Schema library

/// Provides canonical ``ActionSchema`` instances for common planner actions.
///
/// The library acts as the stable primitive set from which all agent
/// behaviour is composed. Planners pull schemas from the library
/// and the executor resolves them into concrete ``ActionIntent`` values.
public struct ActionSchemaLibrary: Sendable {
    public init() {}

    /// Return the canonical schema for clicking an element.
    public func click(element: SemanticElement) -> ActionSchema {
        ActionSchema(
            name: "click_\(element.label)",
            kind: .click,
            preconditions: [
                .elementExists(kind: element.kind, label: element.label),
            ],
            expectedPostconditions: []
        )
    }

    /// Return the canonical schema for typing text into an element.
    public func type(text: String, into element: SemanticElement) -> ActionSchema {
        ActionSchema(
            name: "type_into_\(element.label)",
            kind: .type,
            preconditions: [
                .elementExists(kind: .input, label: element.label),
            ],
            expectedPostconditions: [
                .valueEquals(elementLabel: element.label, expected: text),
            ]
        )
    }

    /// Return the canonical schema for opening an application.
    public func openApplication(name: String) -> ActionSchema {
        ActionSchema(
            name: "open_\(name)",
            kind: .openApplication,
            preconditions: [],
            expectedPostconditions: [
                .appFrontmost(name),
            ]
        )
    }

    /// Return the canonical schema for running tests.
    public func runTests() -> ActionSchema {
        ActionSchema(
            name: "run_tests",
            kind: .runTests,
            preconditions: [],
            expectedPostconditions: [
                .custom("test_execution_completed"),
            ]
        )
    }

    /// Return the canonical schema for building the project.
    public func buildProject() -> ActionSchema {
        ActionSchema(
            name: "build_project",
            kind: .buildProject,
            preconditions: [],
            expectedPostconditions: [
                .custom("build_completed"),
            ]
        )
    }

    /// Return the canonical schema for applying a patch.
    public func applyPatch() -> ActionSchema {
        ActionSchema(
            name: "apply_patch",
            kind: .applyPatch,
            preconditions: [],
            expectedPostconditions: [
                .custom("patch_applied"),
            ]
        )
    }

    /// Return the canonical schema for committing a patch.
    public func commitPatch() -> ActionSchema {
        ActionSchema(
            name: "commit_patch",
            kind: .commitPatch,
            preconditions: [
                .custom("patch_applied"),
            ],
            expectedPostconditions: [
                .custom("patch_committed"),
            ]
        )
    }

    /// Return the canonical schema for reverting a patch.
    public func revertPatch() -> ActionSchema {
        ActionSchema(
            name: "revert_patch",
            kind: .revertPatch,
            preconditions: [
                .custom("patch_applied"),
            ],
            expectedPostconditions: [
                .custom("workspace_clean"),
            ]
        )
    }

    /// Return the canonical schema for dismissing a modal.
    public func dismissModal() -> ActionSchema {
        ActionSchema(
            name: "dismiss_modal",
            kind: .dismissModal,
            preconditions: [
                .custom("modal_present"),
            ],
            expectedPostconditions: [
                .custom("modal_dismissed"),
            ]
        )
    }

    /// Check whether all preconditions of a schema are met in the given UI state.
    public func preconditionsMet(
        _ schema: ActionSchema,
        in state: CompressedUIState
    ) -> Bool {
        for condition in schema.preconditions {
            switch condition {
            case .elementExists(let kind, let label):
                let found = state.elements.contains {
                    $0.kind == kind && $0.label == label
                }
                if !found { return false }
            case .appFrontmost(let app):
                if state.app != app { return false }
            case .windowTitleContains(let value):
                guard let title = state.windowTitle, title.contains(value) else {
                    return false
                }
            case .urlContains(let value):
                guard let url = state.url, url.contains(value) else {
                    return false
                }
            case .valueEquals, .custom:
                // Cannot verify statically; assume met.
                break
            }
        }
        return true
    }
}

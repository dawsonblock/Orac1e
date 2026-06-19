import Foundation
import Testing
@testable import OracleOS

@Suite("Target Resolution")
struct TargetResolutionTests {

    @Test("ClickSkill fails when no candidates are available")
    func clickSkillFailsWhenNoCandidatesExist() {
        let observation = Observation(
            app: "Finder",
            windowTitle: "Finder",
            elements: [
                UnifiedElement(id: "status", source: .ax, role: "AXStaticText", label: "Ready", enabled: false, confidence: 0.95),
            ]
        )
        let skill = ClickSkill()

        do {
            _ = try skill.resolve(
                query: ElementQuery(text: "Rename", clickable: true, visibleOnly: true, app: "Finder"),
                state: WorldState(observation: observation),
                memoryStore: UnifiedMemoryStore()
            )
            Issue.record("Expected no candidate failure")
        } catch let error as SkillResolutionError {
            #expect(error == .noCandidate("Rename"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("TypeSkill returns a strong ranked editable candidate")
    func typeSkillReturnsStrongEditableCandidate() throws {
        let observation = Observation(
            app: "Google Chrome",
            windowTitle: "Compose",
            focusedElementID: "subject",
            elements: [
                UnifiedElement(
                    id: "subject",
                    source: .ax,
                    role: "AXTextField",
                    label: "Subject",
                    frame: CGRect(x: 100, y: 100, width: 300, height: 24),
                    focused: true,
                    confidence: 0.96
                ),
                UnifiedElement(
                    id: "body",
                    source: .ax,
                    role: "AXButton",
                    label: "Attach",
                    frame: CGRect(x: 100, y: 160, width: 400, height: 200),
                    enabled: false,
                    confidence: 0.94
                ),
            ]
        )
        let skill = TypeSkill()
        let resolution = try skill.resolve(
            query: ElementQuery(text: "Subject", editable: true, visibleOnly: true, app: "Google Chrome"),
            state: WorldState(observation: observation),
            memoryStore: UnifiedMemoryStore()
        )

        #expect(resolution.selectedCandidate?.element.id == "subject")
        #expect((resolution.selectedCandidate?.score ?? 0) >= OSTargetResolver.minimumScore)
        #expect(resolution.selectedCandidate?.reasons.isEmpty == false)
        #expect((resolution.selectedCandidate?.ambiguityScore ?? 1) <= OSTargetResolver.maximumAmbiguity)
    }

    @Test("FillFormSkill fails closed on ambiguous candidates")
    func fillFormSkillFailsOnAmbiguousCandidates() {
        let observation = Observation(
            app: "Google Chrome",
            windowTitle: "Settings",
            elements: [
                UnifiedElement(id: "email-primary", source: .ax, role: "AXTextField", label: "Email", confidence: 0.96),
                UnifiedElement(id: "email-secondary", source: .ax, role: "AXTextField", label: "Email", confidence: 0.95),
            ]
        )
        let skill = FillFormSkill()

        do {
            _ = try skill.resolve(
                query: ElementQuery(text: "Email", editable: true, visibleOnly: true, app: "Google Chrome"),
                state: WorldState(observation: observation),
                memoryStore: UnifiedMemoryStore()
            )
            Issue.record("Expected ambiguous candidate failure")
        } catch let error as SkillResolutionError {
            if case let .ambiguousTarget(label, ambiguity) = error {
                #expect(label == "Email")
                #expect(ambiguity > OSTargetResolver.maximumAmbiguity)
            } else {
                Issue.record("Unexpected resolution error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("ReadFileSkill returns resolved target metadata")
    func readFileSkillReturnsResolvedTargetMetadata() throws {
        let observation = Observation(
            app: "Finder",
            windowTitle: "Finder",
            focusedElementID: "report",
            elements: [
                UnifiedElement(
                    id: "report",
                    source: .ax,
                    role: "AXRow",
                    label: "Quarterly Report.pdf",
                    frame: CGRect(x: 80, y: 120, width: 260, height: 22),
                    focused: true,
                    confidence: 0.98
                ),
            ]
        )
        let skill = ReadFileSkill()
        let resolution = try skill.resolve(
            query: ElementQuery(text: "Quarterly Report.pdf", clickable: true, visibleOnly: true, app: "Finder"),
            state: WorldState(observation: observation),
            memoryStore: UnifiedMemoryStore()
        )

        #expect(resolution.selectedCandidate?.element.id == "report")
        #expect((resolution.selectedCandidate?.score ?? 0) >= OSTargetResolver.minimumScore)
        #expect((resolution.selectedCandidate?.ambiguityScore ?? 1) <= OSTargetResolver.maximumAmbiguity)
    }

    @Test("All audited target-bearing OS skills route through OSTargetResolver")
    func auditedTargetBearingSkillsUseSharedResolver() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let skillPaths = [
            "Sources/OracleOS/Skills/OS/ClickSkill.swift",
            "Sources/OracleOS/Skills/OS/TypeSkill.swift",
            "Sources/OracleOS/Skills/OS/FillFormSkill.swift",
            "Sources/OracleOS/Skills/OS/ReadFileSkill.swift",
        ]

        for relativePath in skillPaths {
            let source = try String(
                contentsOf: repoRoot.appendingPathComponent(relativePath),
                encoding: .utf8
            )
            #expect(source.contains("OSTargetResolver.resolve("))
        }
    }
}

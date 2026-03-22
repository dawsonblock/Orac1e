import Foundation
import CoreGraphics

public struct ObservationFusion {

    public static func fuse(
        ax: [UnifiedElement],
        cdp: [UnifiedElement],
        vision: [UnifiedElement]
    ) -> [UnifiedElement] {
        var fused: [UnifiedElement] = ax

        for candidate in cdp + vision {
            if let index = fused.firstIndex(where: { shouldMerge(primary: $0, candidate: candidate) }) {
                fused[index] = merge(primary: fused[index], candidate: candidate)
            } else {
                fused.append(candidate)
            }
        }

        return fused.sorted { lhs, rhs in
            if lhs.focused != rhs.focused {
                return lhs.focused && !rhs.focused
            }
            if lhs.confidence != rhs.confidence {
                return lhs.confidence > rhs.confidence
            }
            return lhs.id < rhs.id
        }
    }

    private static func shouldMerge(primary: UnifiedElement, candidate: UnifiedElement) -> Bool {
        if primary.id == candidate.id {
            return true
        }

        let normalizedPrimaryLabel = normalized(primary.label)
        let normalizedCandidateLabel = normalized(candidate.label)
        let sameRole = normalized(primary.role) == normalized(candidate.role)

        if !normalizedPrimaryLabel.isEmpty,
           normalizedPrimaryLabel == normalizedCandidateLabel,
           sameRole
        {
            return true
        }

        guard let primaryFrame = primary.frame, let candidateFrame = candidate.frame else {
            return false
        }

        let overlap = intersectionOverUnion(primaryFrame, candidateFrame)
        let labelsCompatible = normalizedPrimaryLabel.isEmpty
            || normalizedCandidateLabel.isEmpty
            || normalizedPrimaryLabel == normalizedCandidateLabel

        return overlap >= 0.65 && (sameRole || labelsCompatible)
    }

    private static func merge(primary: UnifiedElement, candidate: UnifiedElement) -> UnifiedElement {
        let keepPrimary = priority(of: primary.source) >= priority(of: candidate.source)
        let stronger = keepPrimary ? primary : candidate
        let weaker = keepPrimary ? candidate : primary
        let source: ElementSource = stronger.source == weaker.source ? stronger.source : .fused

        return UnifiedElement(
            id: stronger.id,
            source: source,
            role: stronger.role ?? weaker.role,
            label: stronger.label ?? weaker.label,
            value: stronger.value ?? weaker.value,
            frame: stronger.frame ?? weaker.frame,
            enabled: stronger.enabled || weaker.enabled,
            visible: stronger.visible || weaker.visible,
            focused: stronger.focused || weaker.focused,
            confidence: max(stronger.confidence, weaker.confidence)
        )
    }

    private static func priority(of source: ElementSource) -> Int {
        switch source {
        case .ax:
            return 3
        case .cdp:
            return 2
        case .vision:
            return 1
        case .fused:
            return 4
        }
    }

    private static func normalized(_ value: String?) -> String {
        guard let value else { return "" }
        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> Double {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }

        let intersectionArea = intersection.width * intersection.height
        let unionArea = (lhs.width * lhs.height) + (rhs.width * rhs.height) - intersectionArea
        guard unionArea > 0 else { return 0 }
        return Double(intersectionArea / unionArea)
    }
}

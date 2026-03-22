import Foundation

/// Policy for governing knowledge graph trust-tier promotions.
/// 
/// ENHANCEMENT: Added criticVerificationRequired and replayEvidenceRequired flags
/// to enforce ADR-012 requirements that were previously not implemented.
/// This addresses the risk identified in risk-register.md: "Stable graph promotion 
/// can still be poisoned by weak evidence if replay and trust-tier rules are bypassed."
public struct GraphPromotionPolicy: Sendable {
    public let minAttempts: Int
    public let minSuccessRate: Double
    public let minPostconditionConsistency: Double
    public let maxTargetAmbiguityRate: Double
    public let successRecencyDays: Int
    public let demotionRollingSuccessRate: Double
    public let pruneAttempts: Int
    public let pruneSuccessRate: Double
    public let pruneDays: Int
    public let freezeGlobalSuccessRate: Double
    
    // ENHANCEMENT: ADR-012 enforcement flags
    /// If true, edges must have passed critic verification before promotion.
    /// This implements: "Only knowledge that passes critic verification can be promoted"
    public let criticVerificationRequired: Bool
    
    /// If true, stable graph promotion requires replay evidence.
    /// This implements: "Stable graph promotion requires replay evidence"
    public let replayEvidenceRequired: Bool
    
    /// Minimum number of verified successes required for promotion to stable.
    /// Provides stronger guarantee than raw successRate.
    public let minVerifiedSuccesses: Int
    
    public init(
        minAttempts: Int = 5,
        minSuccessRate: Double = 0.8,
        minPostconditionConsistency: Double = 0.9,
        maxTargetAmbiguityRate: Double = 0.2,
        successRecencyDays: Int = 7,
        demotionRollingSuccessRate: Double = 0.5,
        pruneAttempts: Int = 10,
        pruneSuccessRate: Double = 0.3,
        pruneDays: Int = 14,
        freezeGlobalSuccessRate: Double = 0.5,
        // ENHANCEMENT: New parameters with secure defaults
        criticVerificationRequired: Bool = true,
        replayEvidenceRequired: Bool = true,
        minVerifiedSuccesses: Int = 3
    ) {
        self.minAttempts = minAttempts
        self.minSuccessRate = minSuccessRate
        self.minPostconditionConsistency = minPostconditionConsistency
        self.maxTargetAmbiguityRate = maxTargetAmbiguityRate
        self.successRecencyDays = successRecencyDays
        self.demotionRollingSuccessRate = demotionRollingSuccessRate
        self.pruneAttempts = pruneAttempts
        self.pruneSuccessRate = pruneSuccessRate
        self.pruneDays = pruneDays
        self.freezeGlobalSuccessRate = freezeGlobalSuccessRate
        self.criticVerificationRequired = criticVerificationRequired
        self.replayEvidenceRequired = replayEvidenceRequired
        self.minVerifiedSuccesses = minVerifiedSuccesses
    }

    public func promotionsFrozen(globalVerifiedSuccessRate: Double) -> Bool {
        globalVerifiedSuccessRate < freezeGlobalSuccessRate
    }

    /// Checks if an edge meets all requirements for promotion to stable tier.
    /// 
    /// ENHANCEMENT: Now enforces:
    /// 1. Critic verification requirement (ADR-012)
    /// 2. Replay evidence requirement (ADR-012)
    /// 3. Minimum verified successes threshold
    public func shouldPromote(edge: EdgeTransition, now: Date) -> Bool {
        guard edge.recoveryTagged == false else { 
            edge.recordPromotionAttempt(success: false, reason: "recoveryTagged is true")
            return false 
        }
        guard edge.knowledgeTier != .experiment else { 
            edge.recordPromotionAttempt(success: false, reason: "knowledgeTier is experiment")
            return false 
        }
        guard edge.knowledgeTier != .recovery else { 
            edge.recordPromotionAttempt(success: false, reason: "knowledgeTier is recovery")
            return false 
        }
        guard edge.attempts >= minAttempts else { 
            edge.recordPromotionAttempt(success: false, reason: "insufficient attempts \(edge.attempts)/\(minAttempts)")
            return false 
        }
        guard edge.successRate >= minSuccessRate else { 
            edge.recordPromotionAttempt(success: false, reason: "insufficient successRate \(edge.successRate)/\(minSuccessRate)")
            return false 
        }
        guard edge.postconditionConsistency >= minPostconditionConsistency else { 
            edge.recordPromotionAttempt(success: false, reason: "insufficient postconditionConsistency \(edge.postconditionConsistency)/\(minPostconditionConsistency)")
            return false 
        }
        guard edge.targetAmbiguityRate <= maxTargetAmbiguityRate else { 
            edge.recordPromotionAttempt(success: false, reason: "excessive targetAmbiguityRate \(edge.targetAmbiguityRate)/\(maxTargetAmbiguityRate)")
            return false 
        }
        guard let lastSuccessTimestamp = edge.lastSuccessTimestamp else { 
            edge.recordPromotionAttempt(success: false, reason: "no lastSuccessTimestamp")
            return false 
        }
        let age = now.timeIntervalSince1970 - lastSuccessTimestamp
        guard age <= TimeInterval(successRecencyDays * 86_400) else { 
            edge.recordPromotionAttempt(success: false, reason: "success too old \(age)/\(TimeInterval(successRecencyDays * 86_400))")
            return false 
        }
        
        // ENHANCEMENT: ADR-012 critic verification enforcement
        if criticVerificationRequired {
            guard edge.criticVerified == true else { 
                edge.recordPromotionAttempt(success: false, reason: "critic verification required but not passed")
                return false 
            }
        }
        
        // ENHANCEMENT: ADR-012 replay evidence enforcement
        if replayEvidenceRequired && edge.knowledgeTier != .candidate {
            guard edge.replayEvidenceCount >= minVerifiedSuccesses else {
                edge.recordPromotionAttempt(success: false, reason: "insufficient replay evidence \(edge.replayEvidenceCount)/\(minVerifiedSuccesses)")
                return false
            }
        }
        
        // ENHANCEMENT: Minimum verified successes for stable promotion
        guard edge.verifiedSuccesses >= minVerifiedSuccesses else {
            edge.recordPromotionAttempt(success: false, reason: "insufficient verified successes \(edge.verifiedSuccesses)/\(minVerifiedSuccesses)")
            return false
        }
        
        edge.recordPromotionAttempt(success: true)
        return true
    }

    public func shouldDemote(edge: EdgeTransition) -> Bool {
        edge.rollingSuccessRate < demotionRollingSuccessRate
    }

    public func shouldPrune(edge: EdgeTransition, now: Date) -> Bool {
        guard edge.attempts >= pruneAttempts else { return false }
        guard edge.successRate <= pruneSuccessRate else { return false }
        guard let lastSuccessTimestamp = edge.lastSuccessTimestamp else { return true }
        let age = now.timeIntervalSince1970 - lastSuccessTimestamp
        return age >= TimeInterval(pruneDays * 86_400)
    }
}

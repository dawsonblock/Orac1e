# Oracle OS Policy Layer Implementation Plan

## Executive Summary

This document outlines the implementation plan for the Oracle OS policy layer, addressing critical placeholder implementations in `ActionApproval.swift` and `CapabilityPolicy.swift`.

## Current State Assessment

### Files Analyzed
- `third_party/oracle-os/Sources/OracleOS/Policy/ActionApproval.swift`
- `third_party/oracle-os/Sources/OracleOS/Policy/CapabilityPolicy.swift`
- `configs/approval_policy.json`
- `configs/tool_policy.json`

### Issues Identified

| File | Current State | Required Implementation |
|------|---------------|------------------------|
| ActionApproval.swift | Empty struct with no logic | Approval evaluation engine |
| CapabilityPolicy.swift | Empty set with no logic | Capability filtering engine |

### Configuration Analysis

**approval_policy.json:**
```json
{
  "require_apply_approval": true,
  "allow_auto_approve_in_test_mode": true
}
```

**tool_policy.json:**
```json
{
  "default": {
    "allow_low": true,
    "allow_medium": true,
    "allow_high": false
  },
  "capability_overrides": {}
}
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Skill Execution Flow                     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  [Skill Request]                                            │
│       │                                                     │
│       ▼                                                     │
│  ┌─────────────────────┐                                    │
│  │ CapabilityPolicy    │ ── Filter by risk level            │
│  │ .canExecute(cap)    │   (low/medium/high)                │
│  └─────────────────────┘                                    │
│       │                                                     │
│       ▼                                                     │
│  ┌─────────────────────┐                                    │
│  │ ApprovalPolicy      │ ── Check if approval required      │
│  │ .requiresApproval() │   based on action type             │
│  └─────────────────────┘                                    │
│       │                                                     │
│       ▼                                                     │
│  ┌─────────────────────┐                                    │
│  │ ActionApproval     │ ── Return approval decision         │
│  │ .evaluate()       │   with conditions                   │
│  └─────────────────────┘                                    │
│       │                                                     │
│       ▼                                                     │
│  [Execute or Block Action]                                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Steps

### Step 1: Implement RiskLevel Enum
Create `RiskLevel.swift` defining low, medium, and high risk categories.

### Step 2: Extend CapabilityPolicy
- Add `riskLevel: RiskLevel` property
- Implement `.canExecute(capability: String) -> Bool`
- Wire in tool_policy.json configuration

### Step 3: Extend ActionApproval  
- Add `.requiresApproval(for: ActionIntent) -> Bool`
- Implement `.evaluate(intent: ActionIntent, policy: ApprovalPolicy) -> ActionApproval`
- Support test mode auto-approval

### Step 4: Add Policy Loading
Create `PolicyLoader.swift` to load JSON configs.

### Step 5: Integration
Add policy checks to skill execution in Skills framework.

## Files to Modify

1. `third_party/oracle-os/Sources/OracleOS/Policy/ActionApproval.swift`
2. `third_party/oracle-os/Sources/OracleOS/Policy/CapabilityPolicy.swift`
3. Create: `third_party/oracle-os/Sources/OracleOS/Policy/RiskLevel.swift`
4. Create: `third_party/oracle-os/Sources/OracleOS/Policy/PolicyLoader.swift`

## Testing Strategy

1. Unit tests for risk level classification
2. Unit tests for capability filtering
3. Unit tests for approval evaluation
4. Integration tests with mock policy configs
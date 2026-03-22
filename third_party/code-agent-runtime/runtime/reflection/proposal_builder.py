from __future__ import annotations

from dataclasses import dataclass

from runtime.common.ids import next_id
from runtime.reflection.failure_miner import FailurePattern


@dataclass(frozen=True)
class ReflectionProposalRecord:
    proposal_id: str
    proposal_type: str
    severity: str
    summary: str
    payload: dict


class ReflectionProposalBuilder:
    def build(self, task_id: str, attempt_id: str, patterns: list[FailurePattern]) -> list[ReflectionProposalRecord]:
        proposals: list[ReflectionProposalRecord] = []
        for pattern in patterns:
            if pattern.count < 2:
                continue
            if 'forbidden_paths' in pattern.code or 'workspace_escape' in pattern.code:
                proposals.append(ReflectionProposalRecord(
                    proposal_id=next_id('proposal'),
                    proposal_type='policy_constraint',
                    severity='high',
                    summary=f'Extend deny rules for repeated {pattern.code}',
                    payload={'rule_hint': pattern.code, 'examples': pattern.examples},
                ))
            elif 'pytest_failed' in pattern.code or 'full_tests_failed' in pattern.code:
                proposals.append(ReflectionProposalRecord(
                    proposal_id=next_id('proposal'),
                    proposal_type='new_test',
                    severity='medium',
                    summary=f'Capture failing scenario for {pattern.code}',
                    payload={'failure_code': pattern.code, 'examples': pattern.examples},
                ))
            else:
                proposals.append(ReflectionProposalRecord(
                    proposal_id=next_id('proposal'),
                    proposal_type='heuristic_update',
                    severity='medium',
                    summary=f'Retune planner or patch search for {pattern.code}',
                    payload={'failure_code': pattern.code, 'examples': pattern.examples},
                ))
        return proposals

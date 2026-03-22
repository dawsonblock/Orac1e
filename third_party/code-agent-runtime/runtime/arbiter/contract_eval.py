from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml

from runtime.common.result import Result


class ContractEvaluator:
    def __init__(self, contract_file: Path):
        payload = yaml.safe_load(Path(contract_file).read_text(encoding='utf-8'))
        self.contracts = payload['contracts']

    def evaluate(self, context: dict[str, Any]) -> Result:
        env = {
            'any': any,
            'all': all,
            'len': len,
            'min': min,
            'max': max,
            'sorted': sorted,
        }
        env.update(context)
        for clause in self.contracts.get('hard', []):
            when_expr = clause.get('when')
            if when_expr and not bool(eval(when_expr, {'__builtins__': {}}, env)):
                continue
            deny_expr = clause.get('deny')
            require_expr = clause.get('require')
            if deny_expr and bool(eval(deny_expr, {'__builtins__': {}}, env)):
                return Result(False, clause['id'], f"contract denied: {clause['id']}")
            if require_expr and not bool(eval(require_expr, {'__builtins__': {}}, env)):
                return Result(False, clause['id'], f"contract requirement failed: {clause['id']}")
        return Result(True, 'ok', 'contracts passed')

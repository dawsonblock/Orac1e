from __future__ import annotations

import os
import tempfile
from pathlib import Path

from integration.shared_py.models import ProposeRequest
from integration.shared_py.process_utils import run
from integration.worker_aider.prompt_builder import build_prompt
from integration.worker_aider.normalize_diff import normalize_diff


def _resolve_aider_bin() -> list[str]:
    value = os.environ.get('AIDER_BIN')
    if value:
        return value.split()
    return ['python', '-m', 'aider.main']


def run_aider(req: ProposeRequest) -> dict:
    repo_path = Path(req.repo_path)
    if not (repo_path / '.git').exists():
        raise FileNotFoundError(f'repo_path is not a git worktree: {repo_path}')

    with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False, encoding='utf-8') as handle:
        handle.write(build_prompt(req))
        prompt_file = handle.name

    try:
        argv = [
            *_resolve_aider_bin(),
            '--message-file', prompt_file,
            '--yes-always',
            '--no-auto-commits',
        ]
        model = os.environ.get('AIDER_MODEL')
        if model:
            argv.extend(['--model', model])
        for rel in req.context.files[: req.constraints.max_files]:
            argv.extend(['--file', rel])

        result = run(argv, cwd=repo_path, timeout=900)
        diff = run(['git', 'diff', '--no-ext-diff', '--binary', '--relative'], cwd=repo_path)
        diff_text, touched, warnings = normalize_diff(
            diff.stdout,
            req.constraints.allowed_paths,
            req.constraints.max_changed_lines,
        )
        if not result.ok and result.stderr:
            warnings.append(result.stderr.strip()[:800])
        return {
            'summary': req.task.splitlines()[0][:160],
            'diff': diff_text,
            'touched_files': touched,
            'commands_requested': [],
            'warnings': warnings,
            'artifacts': [
                {
                    'kind': 'aider_output',
                    'stdout': result.stdout[-4000:],
                    'stderr': result.stderr[-4000:],
                    'exit_code': result.exit_code,
                }
            ],
        }
    finally:
        try:
            os.unlink(prompt_file)
        except OSError:
            pass

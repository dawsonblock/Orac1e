from __future__ import annotations

from integration.shared_py.models import ProposeRequest


def build_prompt(req: ProposeRequest) -> str:
    lines = [
        'You are editing a git worktree owned by Oracle.',
        'Return a clean code change only inside the allowed paths.',
        'Do not commit, push, or modify files outside scope.',
        '',
        'TASK:',
        req.task,
        '',
        'ALLOWED PATHS:',
        ', '.join(req.constraints.allowed_paths) if req.constraints.allowed_paths else '(no explicit path budget)',
        '',
        'FOCUSED FILES:',
    ]
    lines.extend(f'- {path}' for path in req.context.files[: req.constraints.max_files])
    if req.context.snippets:
        lines.extend(['', 'RETRIEVED SNIPPETS:'])
        for item in req.context.snippets[:8]:
            lines.append(f'FILE: {item.path}')
            if item.start_line is not None and item.end_line is not None:
                lines.append(f'LINES: {item.start_line}-{item.end_line}')
            lines.append(item.snippet)
            lines.append('')
    return '\n'.join(lines).strip()

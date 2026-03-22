from __future__ import annotations


def _commands_from_notes(notes: list[str]) -> list[str]:
    commands: list[str] = []
    for note in notes:
        if note.startswith('selected_tests='):
            payload = note.split('=', 1)[1]
            for item in payload.split(','):
                item = item.strip()
                if item:
                    commands.append(item)
    return commands


def to_response(patch, report, trace, patch_message: str | None) -> dict:
    warnings: list[str] = []
    if patch_message:
        warnings.append(patch_message)
    notes = list(getattr(report, 'notes', []) or []) if report is not None else []
    warnings.extend(notes)
    return {
        'summary': patch.summary if patch is not None else 'No patch produced',
        'diff': patch.diff_text if patch is not None else '',
        'touched_files': patch.changed_files if patch is not None else [],
        'commands_requested': _commands_from_notes(notes),
        'warnings': warnings,
        'artifacts': [
            {
                'kind': 'search_trace',
                'attempted_files': getattr(trace, 'attempted_files', []),
                'rejected_files': getattr(trace, 'rejected_files', []),
                'reasons': getattr(trace, 'reasons', []),
                'strategies': getattr(trace, 'strategies', []),
            }
        ],
    }

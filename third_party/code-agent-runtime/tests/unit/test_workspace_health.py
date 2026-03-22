from pathlib import Path

from runtime.validation.workspace_health import WorkspaceHealth
from tests.helpers import init_python_repo


def test_workspace_health_detects_dirty_and_resets(tmp_path: Path):
    repo = tmp_path / 'repo'
    repo.mkdir()
    init_python_repo(repo)
    health = WorkspaceHealth()
    clean = health.ensure_clean(repo)
    assert clean.ok
    (repo / 'src' / 'calc.py').write_text('def inc(x):\n    return x + 99\n', encoding='utf-8')
    dirty = health.ensure_clean(repo)
    assert not dirty.ok
    assert 'src/calc.py' in dirty.data['changed_files']
    reset = health.hard_reset(repo)
    assert reset.ok
    restored = (repo / 'src' / 'calc.py').read_text(encoding='utf-8')
    assert 'return x + 2' in restored

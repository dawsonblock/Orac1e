import json
from pathlib import Path

from runtime.swebench.harness import SwebenchHarness
from runtime.swebench.manifest import load_manifest
from tests.helpers import init_python_repo


def test_swebench_harness_runs_local_manifest(tmp_path: Path):
    repo = tmp_path / 'repo'
    repo.mkdir()
    init_python_repo(repo)
    manifest = tmp_path / 'manifest.jsonl'
    manifest.write_text(json.dumps({
        'repo': 'acme/repo',
        'repo_path': str(repo),
        'issue_number': 7,
        'title': 'Fix inc',
        'body': 'File: src/calc.py\nReplace: return x + 2\nWith: return x + 1\nTests: tests/test_calc.py\n',
        'base_ref': 'main',
        'labels': ['agent:fix'],
    }) + '\n', encoding='utf-8')
    tasks = load_manifest(manifest)
    results = SwebenchHarness().run_manifest(tasks, tmp_path / 'out')
    assert len(results) == 1
    assert results[0].decision_mode == 'draft_pr'
    assert (tmp_path / 'out' / 'results.jsonl').exists()
    assert (tmp_path / 'out' / 'results.csv').exists()

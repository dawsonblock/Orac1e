import json

from runtime.validation.dependency_snapshot import DependencySnapshotter


def test_dependency_snapshot_collects_manifest_files(tmp_path):
    (tmp_path / 'pyproject.toml').write_text('[project]\nname="x"\n', encoding='utf-8')
    (tmp_path / 'requirements.txt').write_text('pytest\n', encoding='utf-8')
    snap = DependencySnapshotter().collect(tmp_path)
    assert 'pyproject.toml' in snap
    assert 'requirements.txt' in snap
    assert len(snap['pyproject.toml']['sha256']) == 64
    data = json.loads(DependencySnapshotter().to_json(tmp_path))
    assert 'requirements.txt' in data

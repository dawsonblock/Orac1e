from pathlib import Path

from runtime.validation.language_detection import RepoLanguageDetector


def test_detects_python_repo(tmp_path: Path):
    (tmp_path / 'pyproject.toml').write_text('[project]\nname = "x"\n', encoding='utf-8')
    result = RepoLanguageDetector().detect(tmp_path)
    assert result.primary == 'python'


def test_detects_js_repo(tmp_path: Path):
    (tmp_path / 'package.json').write_text('{"name":"x"}', encoding='utf-8')
    result = RepoLanguageDetector().detect(tmp_path)
    assert result.primary == 'js_ts'


def test_detects_rust_repo(tmp_path: Path):
    (tmp_path / 'Cargo.toml').write_text('[package]\nname = "x"\nversion = "0.1.0"\n', encoding='utf-8')
    result = RepoLanguageDetector().detect(tmp_path)
    assert result.primary == 'rust'

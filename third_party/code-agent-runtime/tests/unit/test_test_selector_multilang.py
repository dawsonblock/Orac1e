from pathlib import Path

from runtime.validation.test_selector import TestSelector


def test_selector_finds_js_tests(tmp_path: Path):
    (tmp_path / 'package.json').write_text('{"name":"x"}', encoding='utf-8')
    (tmp_path / 'src').mkdir()
    (tmp_path / 'tests').mkdir()
    (tmp_path / 'src' / 'math.ts').write_text('export const x = 1;\n', encoding='utf-8')
    (tmp_path / 'tests' / 'math.test.ts').write_text('test("x", () => {});\n', encoding='utf-8')
    selected = TestSelector().select(tmp_path, ['src/math.ts'], [])
    assert selected == ['tests/math.test.ts']


def test_selector_finds_rust_tests(tmp_path: Path):
    (tmp_path / 'Cargo.toml').write_text('[package]\nname = "x"\nversion = "0.1.0"\n', encoding='utf-8')
    (tmp_path / 'src').mkdir()
    (tmp_path / 'tests').mkdir()
    (tmp_path / 'src' / 'core.rs').write_text('pub fn x() {}\n', encoding='utf-8')
    (tmp_path / 'tests' / 'core.rs').write_text('#[test] fn ok() {}\n', encoding='utf-8')
    selected = TestSelector().select(tmp_path, ['src/core.rs'], [])
    assert selected == ['core']

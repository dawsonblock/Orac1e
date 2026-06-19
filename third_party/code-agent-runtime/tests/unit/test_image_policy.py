from pathlib import Path

from runtime.common.config import SandboxConfig
from runtime.sandbox.image_policy import SandboxImagePolicy


PROFILE_ROOT = Path(__file__).resolve().parents[2] / 'domains' / 'code' / 'language_profiles'


def test_image_policy_detects_python_repo(tmp_path: Path):
    (tmp_path / 'pyproject.toml').write_text('[project]\nname = "demo"\n', encoding='utf-8')
    (tmp_path / 'app.py').write_text('print("x")\n', encoding='utf-8')
    policy = SandboxImagePolicy(PROFILE_ROOT)
    decision = policy.choose(tmp_path, SandboxConfig(mode='docker', image='python:3.11-slim'))
    assert decision.language == 'python'
    assert decision.image == 'python:3.11-slim'


def test_image_policy_detects_js_repo(tmp_path: Path):
    (tmp_path / 'package.json').write_text('{"name":"demo"}\n', encoding='utf-8')
    (tmp_path / 'index.ts').write_text('export const x = 1\n', encoding='utf-8')
    policy = SandboxImagePolicy(PROFILE_ROOT)
    decision = policy.choose(tmp_path, SandboxConfig(mode='docker', image='python:3.11-slim'))
    assert decision.language == 'js_ts'
    assert decision.image.startswith('node:20')

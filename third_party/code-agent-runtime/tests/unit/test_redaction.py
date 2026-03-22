from runtime.reporting.redaction import redact_text
from runtime.validation.artifact_collector import ArtifactCollector


def test_redact_text_masks_tokens_and_keys(tmp_path):
    text = "token=ghp_abcdefghijklmnopqrstuvwxyz1234\npassword: hunter2\n"
    out = redact_text(text)
    assert 'ghp_' not in out
    assert 'hunter2' not in out
    assert '[REDACTED]' in out


def test_artifact_collector_redacts_written_files(tmp_path):
    collector = ArtifactCollector(tmp_path)
    path = collector.write_text('x.txt', 'api_key=secret123')
    assert 'secret123' not in path.read_text(encoding='utf-8')

from runtime.editing.patch_guard import PatchGuard
from runtime.events.schemas import PatchArtifact


def test_patch_guard_rejects_assert_removal_without_replacement():
    artifact = PatchArtifact(
        task_id='t',
        attempt_id='a',
        patch_id='p',
        diff_text='''--- tests/test_calc.py\n+++ tests/test_calc.py\n@@\n-    assert value == 1\n+    value == 1\n''',
        changed_files=['tests/test_calc.py'],
        added_tests=[],
        rationale='bad',
        summary='bad',
    )
    result = PatchGuard().evaluate(artifact)
    assert not result.ok
    assert result.code == 'assertions_removed'

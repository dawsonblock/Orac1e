from runtime.common.ids import stable_task_id, stable_attempt_id, workspace_id
from runtime.workspace.branch_namer import branch_name


def test_ids_and_branch_name_shapes():
    task_id = stable_task_id('org/repo', 12)
    attempt_id = stable_attempt_id(task_id, 2)
    ws = workspace_id(task_id, attempt_id)
    assert task_id == 'task_org-repo_000012'
    assert attempt_id.endswith('_02')
    assert ws.startswith('ws_')
    assert branch_name(12, 2) == 'agent/issue-12-attempt-02'

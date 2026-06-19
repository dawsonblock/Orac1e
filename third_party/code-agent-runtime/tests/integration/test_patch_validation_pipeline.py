import shutil
import subprocess
from pathlib import Path

from apps.patch_worker import PatchWorker
from apps.planner_worker import PlannerWorker
from apps.reporter_worker import ReporterWorker
from apps.validation_worker import ValidationWorker
from runtime.common.ids import stable_task_id
from runtime.events.schemas import IssueTask


def init_repo(path: Path):
    subprocess.run(["git", "init", "-b", "main"], cwd=path, check=True, capture_output=True, text=True)
    subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=path, check=True, capture_output=True, text=True)
    subprocess.run(["git", "config", "user.name", "Test User"], cwd=path, check=True, capture_output=True, text=True)
    (path / "src").mkdir()
    (path / "tests").mkdir()
    (path / "domains" / "code").mkdir(parents=True)
    (path / "src" / "calc.py").write_text("def inc(x):\n    return x + 2\n", encoding="utf-8")
    (path / "tests" / "test_calc.py").write_text(
        "from src.calc import inc\n\n\ndef test_inc():\n    assert inc(1) == 2\n",
        encoding="utf-8",
    )
    contract_src = Path(__file__).resolve().parents[2] / "domains" / "code" / "contracts.yaml"
    shutil.copy2(contract_src, path / "domains" / "code" / "contracts.yaml")
    subprocess.run(["git", "add", "."], cwd=path, check=True, capture_output=True, text=True)
    subprocess.run(["git", "commit", "-m", "init"], cwd=path, check=True, capture_output=True, text=True)


def test_pipeline_emits_draft_pr_artifact(tmp_path: Path):
    repo = tmp_path / "repo"
    repo.mkdir()
    init_repo(repo)
    task = IssueTask(
        task_id=stable_task_id("acme/repo", 1),
        repo="acme/repo",
        repo_url="https://example.invalid/acme/repo.git",
        issue_number=1,
        base_ref="main",
        title="Fix inc",
        body="File: src/calc.py\nReplace: return x + 2\nWith: return x + 1\nTests: tests/test_calc.py\n",
        labels=["agent:fix"],
    )
    planner = PlannerWorker()
    plan, parsed = planner.run(repo, task)
    patch, guard, trace = PatchWorker().run(repo, plan, parsed)
    assert patch is not None, guard.message
    report, _details = ValidationWorker().run(repo, plan, patch)
    reporter = ReporterWorker((repo / ".agent_outbox"), repo / "domains" / "code" / "contracts.yaml")
    decision, artifact_path = reporter.run(target_branch="agent/issue-1-attempt-01", task=task, plan=plan, patch=patch, report=report, attempt_index=1, attempted_files=trace.attempted_files)
    assert decision.mode == "draft_pr"
    assert artifact_path.exists()
    assert "draft_pr_bundle" in artifact_path.name

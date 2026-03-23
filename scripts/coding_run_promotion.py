from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import shutil
import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

ROOT = Path(__file__).resolve().parents[1]
RUNS_ROOT = ROOT / "workspace" / "runs"
RUNS_FILE = RUNS_ROOT / "runs.json"
EVENTS_FILE = RUNS_ROOT / "events.jsonl"
APPROVALS_FILE = RUNS_ROOT / "approvals.jsonl"
PROMOTIONS_FILE = RUNS_ROOT / "promotions.jsonl"
RUN_METADATA_DIR = RUNS_ROOT / "metadata"


class PromotionError(RuntimeError):
    pass


@dataclass
class PromotionResult:
    run_id: str
    canonical_repo: str
    promotion_commit: str
    status: str
    validation_ok: bool
    receipt_path: str

    def to_dict(self) -> dict[str, Any]:
        return {
            "run_id": self.run_id,
            "canonical_repo": self.canonical_repo,
            "promotion_commit": self.promotion_commit,
            "status": self.status,
            "validation_ok": self.validation_ok,
            "receipt_path": self.receipt_path,
        }


@dataclass
class RunPaths:
    metadata_path: Path
    approval_receipt_path: Path
    promotion_receipt_path: Path


def now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def _read_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def _write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)


def _read_jsonl(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    items: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        items.append(json.loads(line))
    return items


def _append_jsonl(path: Path, item: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(item, sort_keys=True) + "\n")


def _run(
    argv: list[str],
    cwd: Path | None = None,
    check: bool = True,
    timeout: int = 30,
) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(
        argv,
        cwd=str(cwd) if cwd else None,
        text=True,
        capture_output=True,
        timeout=timeout,
    )
    if check and proc.returncode != 0:
        raise PromotionError(proc.stderr.strip() or proc.stdout.strip() or f"command failed: {' '.join(argv)}")
    return proc


def _git(repo: Path, *args: str, check: bool = True, strip: bool = True) -> str:
    proc = _run(["git", "-C", str(repo), *args], check=check)
    return proc.stdout.strip() if strip else proc.stdout


def _load_run(run_id: str) -> dict[str, Any]:
    for item in _read_json(RUNS_FILE, []):
        if item.get("id") == run_id:
            return item
    raise PromotionError(f"run not found: {run_id}")


def _replace_run(updated: dict[str, Any]) -> None:
    runs = _read_json(RUNS_FILE, [])
    replaced = False
    for idx, item in enumerate(runs):
        if item.get("id") == updated.get("id"):
            runs[idx] = updated
            replaced = True
            break
    if not replaced:
        raise PromotionError(f"run {updated.get('id')!r} not found in runs file; cannot replace")
    _write_json(RUNS_FILE, runs)


def _paths_for(run_id: str) -> RunPaths:
    return RunPaths(
        metadata_path=RUN_METADATA_DIR / f"{run_id}.json",
        approval_receipt_path=RUNS_ROOT / "approvals" / f"{run_id}.json",
        promotion_receipt_path=RUNS_ROOT / "promotions" / f"{run_id}.json",
    )


def _load_metadata(run_id: str) -> dict[str, Any]:
    paths = _paths_for(run_id)
    if not paths.metadata_path.exists():
        raise PromotionError(f"run metadata missing: {paths.metadata_path}")
    return _read_json(paths.metadata_path, {})


def _record_event(run_id: str, event_type: str, payload: dict[str, Any] | None = None) -> None:
    ts = now_iso()
    _append_jsonl(
        EVENTS_FILE,
        {
            "id": f"{run_id}:{event_type}:{ts}",
            "runID": run_id,
            "type": event_type,
            "ts": ts,
            "payload": payload or {},
        },
    )


def _record_approval(run_id: str, decision: str, actor: str, note: str) -> dict[str, Any]:
    receipt = {
        "run_id": run_id,
        "decision": decision,
        "actor": actor,
        "note": note,
        "at": now_iso(),
    }
    _append_jsonl(APPROVALS_FILE, receipt)
    _write_json(_paths_for(run_id).approval_receipt_path, receipt)
    return receipt


def _record_promotion(run_id: str, receipt: dict[str, Any]) -> None:
    _append_jsonl(PROMOTIONS_FILE, receipt)
    _write_json(_paths_for(run_id).promotion_receipt_path, receipt)


def _repo_is_clean(repo: Path) -> bool:
    return _git(repo, "status", "--porcelain") == ""


def _validate_worktree_lineage(canonical_repo: Path, worktree_repo: Path) -> str:
    canonical_head = _git(canonical_repo, "rev-parse", "HEAD")
    worktree_head = _git(worktree_repo, "rev-parse", "HEAD")
    if canonical_head != worktree_head:
        raise PromotionError("worktree lineage mismatch: base commit no longer matches canonical HEAD; refusing promotion")
    return canonical_head


def _capture_environment(repo: Path) -> dict[str, str]:
    """Capture environment information for equivalence checking using SHA-256."""
    env = {}

    # Use python3 explicitly; add timeout to avoid hanging on slow systems.
    try:
        proc = subprocess.run(
            ["python3", "--version"],
            cwd=repo,
            text=True,
            capture_output=True,
            timeout=5,
        )
        if proc.returncode == 0:
            env["python_version"] = proc.stdout.strip() or proc.stderr.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass

    # Capture Node version if available
    try:
        proc = subprocess.run(
            ["node", "--version"],
            cwd=repo,
            text=True,
            capture_output=True,
            timeout=5,
        )
        if proc.returncode == 0:
            env["node_version"] = proc.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass
    
    # Capture key dependency hashes using SHA-256
    lock_files = [
        "requirements.txt",
        "requirements-dev.txt",
        "poetry.lock",
        "pyproject.toml",
        "package-lock.json",
        "pnpm-lock.yaml",
        "yarn.lock",
        "package.json",
        "Package.resolved",
        "Package.swift",
        ".oracle-validation.json"
    ]
    
    hasher = hashlib.sha256()
    for lock in sorted(lock_files):
        lock_path = repo / lock
        if lock_path.exists():
            hasher.update(f"{lock}:".encode())
            hasher.update(lock_path.read_bytes())
            hasher.update(b"\n")
    
    env["dependencies_hash"] = hasher.hexdigest()
    
    return env


def _environments_match(env1: dict[str, str], env2: dict[str, str]) -> bool:
    """Check if two environments are equivalent."""
    for key in ["python_version", "node_version", "dependencies_hash"]:
        if env1.get(key) != env2.get(key):
            return False
    return True


def _run_validation(repo: Path, commands: list[str]) -> dict[str, Any]:
    # Capture once; reused across all return paths to avoid redundant subprocess spawns.
    environment = _capture_environment(repo)
    if not commands:
        return {
            "ok": False,
            "steps": [],
            "environment": environment,
            "error_category": "validation_unconfigured",
            "summary": "Validation configuration missing - no validation commands configured",
        }
    steps: list[dict[str, Any]] = []
    for command in commands:
        proc = subprocess.run(
            ["/bin/bash", "-lc", command],
            cwd=repo,
            text=True,
            capture_output=True,
            timeout=300,
        )
        step = {
            "name": command,
            "ok": proc.returncode == 0,
            "stdout": proc.stdout,
            "stderr": proc.stderr,
            "exitCode": proc.returncode,
        }
        steps.append(step)
        if proc.returncode != 0:
            return {"ok": False, "steps": steps, "environment": environment}
    return {"ok": True, "steps": steps, "environment": environment}


def _write_validation_artifact(run_id: str, validation: dict[str, Any], kind: str) -> str:
    path = RUNS_ROOT / "validation" / f"{run_id}.{kind}.json"
    _write_json(path, validation)
    return str(path)


def _capture_patch(worktree_repo: Path, run_id: str) -> tuple[str, Path]:
    patch_text = _git(worktree_repo, "diff", "--binary", strip=False)
    if not patch_text.strip():
        raise PromotionError("no diff found in worktree; refusing empty promotion")

    patch_file = RUNS_ROOT / "artifacts" / f"{run_id}.patch"
    patch_file.parent.mkdir(parents=True, exist_ok=True)
    patch_file.write_text(patch_text, encoding="utf-8")
    return patch_text, patch_file


def _apply_patch_to_canonical(canonical_repo: Path, patch_file: Path) -> None:
    _run(["git", "-C", str(canonical_repo), "apply", "--index", "--whitespace=nowarn", str(patch_file)])


def _commit_promotion(canonical_repo: Path, run_id: str) -> str:
    commit_message = f"Promote approved coding run {run_id}"
    _run(["git", "-C", str(canonical_repo), "commit", "-m", commit_message])
    return _git(canonical_repo, "rev-parse", "HEAD")


def _rollback_canonical(canonical_repo: Path, should_rollback: bool) -> None:
    if should_rollback:
        _run(["git", "-C", str(canonical_repo), "reset", "--hard", "HEAD"], check=False)
        _run(["git", "-C", str(canonical_repo), "clean", "-fd"], check=False)


def _resolve_validation_profile(repo: Path, metadata: dict[str, Any]) -> tuple[str, int, list[dict[str, Any]], bool]:
    """
    Resolve validation profile with precedence:
    1. Explicit run override (preferredValidationProfile in metadata)
    2. Repo-local .oracle-validation.json
    3. Inferred profile from file detection
    4. Fallback default
    
    Returns: (profile_name, profile_version, stages, allow_no_validation)
    """
    # 1. Check for explicit override in run metadata
    if preferred := metadata.get("preferredValidationProfile"):
        profile_name = preferred
        profile_version = 1
        allow_no_validation = metadata.get("allowNoValidation", False)
        return profile_name, profile_version, [], allow_no_validation
    
    # 2. Check for repo-local override
    local_config = repo / ".oracle-validation.json"
    if local_config.exists():
        try:
            config = json.loads(local_config.read_text(encoding="utf-8"))
            return (
                config.get("profile", "default"),
                config.get("version", 1),
                config.get("stages", []),
                config.get("allowNoValidation", False)
            )
        except json.JSONDecodeError:
            pass  # Fall through to inference
    
    # 3-4. Inference handled by Swift side, return default
    return "default", 1, [], False


def promote_run(
    run_id: str,
    actor: str = "operator",
    note: str = "",
    cleanup_worktree: bool = True,
    allow_skip_canonical_validation: bool = False,
    allow_no_validation: bool = False,
) -> PromotionResult:
    run = _load_run(run_id)
    metadata = _load_metadata(run_id)
    canonical_repo = Path(metadata.get("canonicalRepoPath") or run.get("repoPath") or "").resolve()
    worktree_repo = Path(metadata.get("worktreePath") or ROOT / "workspace" / "worktrees" / run_id).resolve()

    # Resolve validation profile (repo-local .oracle-validation.json takes precedence over defaults)
    _profile_name, _profile_version, _profile_stages, _profile_allow_no = _resolve_validation_profile(
        canonical_repo, metadata
    )

    # Support both legacy flat commands and new stage-based validation.
    # Metadata values take precedence; resolved profile provides the fallback.
    validation_commands = list(metadata.get("validationCommands") or [])
    validation_stages = metadata.get("validationStages") or _profile_stages
    validation_profile_name = metadata.get("validationProfileName") or _profile_name
    validation_profile_version = metadata.get("validationProfileVersion") or _profile_version
    allow_no_validation = (
        allow_no_validation
        or bool(metadata.get("allowNoValidation"))
        or _profile_allow_no
        or os.environ.get("ORACLE_ALLOW_NO_VALIDATION") == "1"
    )

    # Normalized status vocabulary check - load immediately after run
    current_status = run.get("status")

    # Check if already applied BEFORE worktree existence check (idempotent path)
    if current_status == "applied":
        # Already applied - return existing promotion receipt (no worktree needed for idempotent path)
        paths = _paths_for(run_id)
        if paths.promotion_receipt_path.exists():
            existing_receipt = _read_json(paths.promotion_receipt_path, {})
            return PromotionResult(
                run_id=run_id,
                canonical_repo=existing_receipt.get("canonical_repo", str(canonical_repo)),
                promotion_commit=existing_receipt.get("promotion_commit", ""),
                status="applied",
                validation_ok=existing_receipt.get("validation_ok", False),
                receipt_path=str(paths.promotion_receipt_path),
            )
        raise PromotionError(f"run {run_id} is already applied but receipt is missing")

    # Only verify worktree exists for non-applied runs
    if not canonical_repo.exists():
        raise PromotionError(f"canonical repo missing: {canonical_repo}")
    if not worktree_repo.exists():
        raise PromotionError(f"worktree missing: {worktree_repo}")

    # Verify run is in correct state for promotion
    if current_status != "awaiting_approval":
        raise PromotionError(f"run {run_id} is not awaiting approval (current status: {current_status})")
    
    if not _repo_is_clean(canonical_repo):
        raise PromotionError("canonical repo is dirty; refusing promotion")

    # Check if validation is configured - fail-closed unless explicitly allowed
    has_validation = bool(validation_commands or validation_stages)
    if not has_validation and not allow_no_validation:
        raise PromotionError("no validation configured and allowNoValidation is not enabled")
    
    if not has_validation and allow_no_validation:
        # Skip validation entirely if explicitly allowed
        pre_validation = {
            "ok": True,
            "steps": [{"name": "validation_skipped", "ok": True, "stdout": "", "stderr": "", "exitCode": 0, "skipped": True}],
            "environment": _capture_environment(worktree_repo),
            "skipped": True,
            "skip_reason": "allow_no_validation",
        }
    else:
        # Flatten stages to commands for execution (backward compatible)
        commands_to_run = validation_commands
        if validation_stages:
            commands_to_run = []
            for stage in validation_stages:
                commands_to_run.extend(stage.get("commands", []))
        
        pre_validation = _run_validation(worktree_repo, commands_to_run)
        _write_validation_artifact(run_id, pre_validation, "worktree")
        if not pre_validation["ok"]:
            run["status"] = "failed"
            _replace_run(run)
            raise PromotionError("worktree validation failed before promotion")

    base_commit = _validate_worktree_lineage(canonical_repo, worktree_repo)

    pre_status_clean = _repo_is_clean(canonical_repo)
    patch_applied = False
    canonical_validation_ran: bool = False
    canonical_validation_skip_reason: str | None = None

    try:
        _, patch_file = _capture_patch(worktree_repo, run_id)

        worktree_env = pre_validation.get("environment", {})
        canonical_env = _capture_environment(canonical_repo)
        explicit_skip_requested = allow_skip_canonical_validation or os.environ.get("ORACLE_ALLOW_SKIP_CANONICAL_VALIDATION") == "1"
        environments_match = pre_validation["ok"] and _environments_match(worktree_env, canonical_env)
        no_validation_skipped = not has_validation and allow_no_validation
        should_skip_canonical = (explicit_skip_requested and environments_match) or no_validation_skipped
        canonical_validation_ran = not should_skip_canonical
        canonical_validation_skip_reason = None

        _apply_patch_to_canonical(canonical_repo, patch_file)
        patch_applied = True

        if should_skip_canonical:
            canonical_validation_skip_reason = (
                "allow_no_validation" if no_validation_skipped
                else "explicit_override_with_matching_environments"
            )
            logger.warning(
                f"Canonical validation skipped for run {run_id}: "
                f"{'allow_no_validation flag set' if no_validation_skipped else 'explicit override enabled and worktree environment matches canonical environment'}."
            )
            post_validation = {
                "ok": pre_validation["ok"],
                "steps": [{"name": "canonical_validation_skipped", "ok": True, "stdout": "", "stderr": "", "exitCode": 0}],
                "environment": canonical_env,
                "skipped": True,
                "skip_reason": canonical_validation_skip_reason,
            }
            _write_validation_artifact(run_id, post_validation, "canonical")
        else:
            post_validation = _run_validation(canonical_repo, validation_commands)
            _write_validation_artifact(run_id, post_validation, "canonical")
            if not post_validation["ok"]:
                raise PromotionError("canonical validation failed after patch apply")

        promotion_commit = _commit_promotion(canonical_repo, run_id)

        # Record approval here — after validation and commit succeed — so the
        # audit trail is never left with a stale 'approved' entry on failure.
        approval = _record_approval(run_id, "approved", actor, note)
        _record_event(run_id, "approval.recorded", approval)

        run["status"] = "applied"
        _replace_run(run)
        receipt = {
            "run_id": run_id,
            "actor": actor,
            "note": note,
            "at": now_iso(),
            "base_commit": base_commit,
            "promotion_commit": promotion_commit,
            "canonical_repo": str(canonical_repo),
            "worktree_repo": str(worktree_repo),
            "status": "applied",
            "validation_ok": True,
            "patch_file": str(patch_file),
            "canonical_validation_ran": canonical_validation_ran,
            "canonical_validation_skip_reason": canonical_validation_skip_reason,
            "validation_profile_name": validation_profile_name,
            "validation_profile_version": validation_profile_version,
            "validation_stages_count": len(validation_stages),
            "validation": {
                "mode": "skipped" if pre_validation.get("skipped") else "full",
                "ok": True,
                "step_count": len(pre_validation.get("steps", [])),
                "skipped": bool(pre_validation.get("skipped")),
                "skip_reason": pre_validation.get("skip_reason"),
                "error_category": pre_validation.get("error_category"),
            },
        }
        _record_promotion(run_id, receipt)
        _record_event(run_id, "promotion.completed", receipt)

        if cleanup_worktree:
            try:
                _run(["git", "-C", str(canonical_repo), "worktree", "remove", "--force", str(worktree_repo)], check=False)
            finally:
                shutil.rmtree(worktree_repo, ignore_errors=True)

        return PromotionResult(
            run_id=run_id,
            canonical_repo=str(canonical_repo),
            promotion_commit=promotion_commit,
            status="applied",
            validation_ok=True,
            receipt_path=str(_paths_for(run_id).promotion_receipt_path),
        )
    except Exception as exc:
        should_rollback = pre_status_clean and patch_applied
        _rollback_canonical(canonical_repo, should_rollback)
        run["status"] = "failed"
        _replace_run(run)
        _pre = locals().get("pre_validation") or {}
        receipt = {
            "run_id": run_id,
            "actor": actor,
            "note": note,
            "at": now_iso(),
            "base_commit": base_commit,
            "canonical_repo": str(canonical_repo),
            "worktree_repo": str(worktree_repo),
            "status": "failed",
            "validation_ok": False,
            "error": str(exc),
            "canonical_validation_ran": canonical_validation_ran,
            "canonical_validation_skip_reason": canonical_validation_skip_reason,
            "validation": {
                "mode": "skipped" if _pre.get("skipped") else "full",
                "ok": False,
                "step_count": len(_pre.get("steps", [])),
                "skipped": bool(_pre.get("skipped")),
                "skip_reason": _pre.get("skip_reason"),
                "error_category": _pre.get("error_category"),
            },
        }
        _record_promotion(run_id, receipt)
        _record_event(run_id, "promotion.failed", receipt)
        raise PromotionError(str(exc)) from exc


def reject_run(run_id: str, actor: str = "operator", note: str = "") -> dict[str, Any]:
    run = _load_run(run_id)

    current_status = run.get("status")
    if current_status == "rejected":
        approval = _record_approval(run_id, "rejected", actor, note)
        _record_event(run_id, "approval.rejected", approval)
        return approval

    if current_status == "applied":
        raise PromotionError(f"run {run_id} is already applied")

    if current_status != "awaiting_approval":
        raise PromotionError(f"run {run_id} is not awaiting approval (current status: {current_status})")

    approval = _record_approval(run_id, "rejected", actor, note)
    run["status"] = "rejected"
    _replace_run(run)
    _record_event(run_id, "approval.rejected", approval)
    return approval


def main() -> int:
    parser = argparse.ArgumentParser(description="Promote an approved coding run into the canonical repo")
    parser.add_argument("run_id")
    parser.add_argument("--actor", default="operator")
    parser.add_argument("--note", default="")
    parser.add_argument("--reject", action="store_true")
    parser.add_argument("--keep-worktree", action="store_true")
    parser.add_argument("--allow-skip-canonical-validation", action="store_true", help="Allow skipping canonical validation when environments match")
    parser.add_argument("--allow-no-validation", action="store_true", help="Allow promotion without validation (dangerous)")
    args = parser.parse_args()

    try:
        if args.reject:
            result = reject_run(args.run_id, actor=args.actor, note=args.note)
        else:
            result = promote_run(
                args.run_id,
                actor=args.actor,
                note=args.note,
                cleanup_worktree=not args.keep_worktree,
                allow_skip_canonical_validation=args.allow_skip_canonical_validation,
                allow_no_validation=args.allow_no_validation,
            ).to_dict()
    except PromotionError as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, sort_keys=True))
        return 1

    print(json.dumps({"ok": True, "result": result}, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

from __future__ import annotations

import hashlib
import hmac
import json
from typing import Any

from runtime.common.ids import stable_task_id
from runtime.events.schemas import IssueTask


class SignatureError(ValueError):
    pass


class GitHubEventNormalizer:
    def verify_signature(self, secret: str, body: bytes, signature_header: str) -> None:
        digest = "sha256=" + hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
        if not hmac.compare_digest(digest, signature_header):
            raise SignatureError("invalid signature")

    def normalize_issue_event(self, payload: dict[str, Any]) -> IssueTask:
        issue = payload["issue"]
        repo = payload["repository"]
        full_name = repo["full_name"]
        repo_url = repo.get("clone_url") or repo.get("html_url", "")
        issue_number = int(issue["number"])
        task_id = stable_task_id(full_name, issue_number)
        return IssueTask(
            task_id=task_id,
            repo=full_name,
            repo_url=repo_url,
            issue_number=issue_number,
            base_ref=payload.get("base_ref") or repo.get("default_branch", "main"),
            title=issue.get("title", ""),
            body=issue.get("body", "") or "",
            labels=[x["name"] for x in issue.get("labels", [])],
        )

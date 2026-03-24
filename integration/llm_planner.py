"""LLM planner for creating multi-file edit plans."""

import json
import logging
import os
from typing import Dict, Any, List, Optional


API_KEY = os.getenv("OPENAI_API_KEY")
logger = logging.getLogger(__name__)


def call_llm(prompt: str, model: str = "gpt-4o-mini") -> str:
    """Call OpenAI API with the given prompt."""
    try:
        import requests
    except ImportError:
        logger.warning("requests module not available")
        return ""

    if not API_KEY:
        logger.warning("OPENAI_API_KEY not set")
        return ""

    try:
        r = requests.post(
            "https://api.openai.com/v1/chat/completions",
            headers={
                "Authorization": f"Bearer {API_KEY}",
                "Content-Type": "application/json"
            },
            json={
                "model": model,
                "messages": [{"role": "user", "content": prompt}],
                "temperature": 0.1
            },
            timeout=60
        )
        r.raise_for_status()
        data = r.json()
        return data["choices"][0]["message"]["content"]
    except requests.exceptions.RequestException as e:
        logger.error("LLM API request failed: %s", e)
        return ""
    except (ValueError, KeyError, IndexError, TypeError) as e:
        # ValueError: r.json() failed; KeyError/IndexError/TypeError: unexpected response shape
        logger.error("Unexpected LLM API response format: %s", e)
        return ""


def create_plan(task: str, context: List[Dict[str, Any]]) -> Optional[Dict[str, Any]]:
    """
    Create an edit plan based on the task and repository context.

    Args:
        task: Description of the coding task
        context: List of file dicts with 'file' and 'content' keys

    Returns:
        Dict with 'edits' list, or None if planning failed
    """
    # Format context as readable text
    context_str = ""
    for item in context:
        context_str += f"\n--- File: {item['file']} ---\n{item['content']}\n"

    prompt = f"""You are a coding agent. Your task is to analyze the provided code and produce edits to fix the described issue.

Task:
{task}

Repository Context:
{context_str}

Return ONLY valid JSON in this exact format:
{{
  "edits": [
    {{
      "file": "path/to/file.py",
      "search": "exact code to find (must match exactly including whitespace)",
      "replace": "replacement code"
    }}
  ]
}}

Important:
- The "search" field must match the exact code in the file, including indentation
- If multiple files need changes, include multiple edit objects
- If you cannot produce a valid edit, return {{"edits": []}}
- Only return the JSON, no other text
"""

    try:
        response = call_llm(prompt)
        if not response:
            return None

        # Try to parse JSON response
        plan = json.loads(response)
        if "edits" in plan and isinstance(plan["edits"], list):
            return plan
        return None
    except (json.JSONDecodeError, KeyError, TypeError):
        return None

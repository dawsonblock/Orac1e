from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import PurePosixPath


@dataclass(frozen=True)
class ParsedIssue:
    title: str
    body: str
    explicit_files: list[str]
    ignored_files: list[str]
    stacktrace_files: list[str]
    search_terms: list[str]
    symbol_names: list[str]
    replace_text: str | None
    with_text: str | None
    regex_pattern: str | None
    insert_before: str | None
    insert_after: str | None
    append_text: str | None
    target_function: str | None
    replace_all: bool
    tests: list[str]
    add_test_file: str | None
    add_test_content: str | None
    max_files: int | None
    max_attempts: int | None


FILE_RE = re.compile(r"^\s*File:\s*(.+)$", re.MULTILINE)
TESTS_RE = re.compile(r"^\s*Tests?:\s*(.+)$", re.MULTILINE)
ADD_TEST_FILE_RE = re.compile(r"^\s*Add-Test-File:\s*(.+)$", re.MULTILINE)
STACKTRACE_FILE_RE = re.compile(r"(?:File \"([^\"]+)\"|([\w./-]+\.(?:py|js|jsx|ts|tsx|rs)))")
NUMBER_RE = re.compile(r"^\s*(Max-Files|Max-Attempts):\s*(\d+)\s*$", re.MULTILINE)
REPLACE_ALL_RE = re.compile(r"^\s*Replace-All:\s*(true|false)\s*$", re.MULTILINE)


FIELD_ALIASES = {
    'Ignore-Files': 'ignore_files',
    'Search': 'search_terms',
    'Symbol': 'symbol_names',
    'Insert-Before': 'insert_before',
    'Insert-After': 'insert_after',
    'Append-Text': 'append_text',
    'Function': 'target_function',
}


def _unique_keep_order(values: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for value in values:
        norm = value.strip()
        if not norm or norm in seen:
            continue
        seen.add(norm)
        out.append(norm)
    return out


def _normalize_path(value: str) -> str:
    value = value.strip().replace('\\', '/')
    try:
        return PurePosixPath(value).as_posix()
    except Exception:
        return value


def _parse_csv_field(body: str, label: str) -> list[str]:
    raw = _read_field(body, label)
    if not raw:
        return []
    if '\n' in raw:
        parts = [line.strip(' -\t') for line in raw.splitlines() if line.strip()]
    else:
        parts = [part.strip() for part in raw.split(',') if part.strip()]
    normalized: list[str] = []
    for part in parts:
        if label.endswith('Files') or label == 'Search' and ('/' in part or '.' in part):
            normalized.append(_normalize_path(part))
        else:
            normalized.append(part)
    return _unique_keep_order(normalized)


def _read_field(body: str, label: str) -> str | None:
    lines = body.splitlines()
    prefix = f'{label}:'
    for i, line in enumerate(lines):
        stripped = line.strip()
        if not stripped.startswith(prefix):
            continue
        rest = stripped[len(prefix):].lstrip()
        if rest.startswith('```'):
            fence = '```'
            collected: list[str] = []
            for inner in lines[i + 1:]:
                if inner.strip() == fence:
                    break
                collected.append(inner)
            return '\n'.join(collected).strip()
        if rest:
            continuation: list[str] = [rest]
            for inner in lines[i + 1:]:
                if not inner.strip():
                    break
                stripped_inner = inner.strip()
                if re.match(r'^[A-Za-z][A-Za-z0-9_-]*:\s*', stripped_inner):
                    break
                if inner.startswith((' ', '\t')):
                    continuation.append(inner.rstrip())
                    continue
                break
            return '\n'.join(continuation).strip() or None
        return None
    return None


def _extract_stacktrace_files(body: str) -> list[str]:
    candidates: list[str] = []
    for line in body.splitlines():
        if re.match(r'^\s*[A-Za-z][A-Za-z0-9_-]*:\s*', line):
            continue
        for match in STACKTRACE_FILE_RE.finditer(line):
            raw = next((group for group in match.groups() if group), '')
            if not raw:
                continue
            normalized = _normalize_path(raw)
            if normalized.startswith(('/', './', '../')):
                normalized = normalized.lstrip('./')
            if normalized.endswith(('.pyc', '.map')):
                continue
            if normalized.count('/') == 0 and '.' not in normalized:
                continue
            candidates.append(normalized)
    return _unique_keep_order(candidates)


def _read_bool_field(body: str, label: str) -> bool:
    for field, value in REPLACE_ALL_RE.findall(body):
        if field == label:
            return value.lower() == 'true'
    return False

def _extract_number(body: str, label: str) -> int | None:
    for field, value in NUMBER_RE.findall(body):
        if field == label:
            return int(value)
    return None


class IssueParser:
    def parse(self, title: str, body: str) -> ParsedIssue:
        explicit_files = [_normalize_path(m.group(1).strip()) for m in FILE_RE.finditer(body)]
        stacktrace_files = _extract_stacktrace_files(body)
        tests = _parse_csv_field(body, 'Tests') or _parse_csv_field(body, 'Test')
        add_test_file_raw = _read_field(body, 'Add-Test-File')
        add_test_file = _normalize_path(add_test_file_raw) if add_test_file_raw else None
        ignored_files = _parse_csv_field(body, 'Ignore-Files')
        search_terms = _parse_csv_field(body, 'Search')
        symbol_names = _parse_csv_field(body, 'Symbol')
        replace_text = _read_field(body, 'Replace')
        with_text = _read_field(body, 'With')
        regex_pattern = _read_field(body, 'Regex')
        insert_before = _read_field(body, 'Insert-Before')
        insert_after = _read_field(body, 'Insert-After')
        append_text = _read_field(body, 'Append-Text')
        target_function = _read_field(body, 'Function')
        combined_explicit = _unique_keep_order(explicit_files + stacktrace_files)
        return ParsedIssue(
            title=title.strip(),
            body=body.strip(),
            explicit_files=combined_explicit,
            ignored_files=ignored_files,
            stacktrace_files=stacktrace_files,
            search_terms=search_terms,
            symbol_names=symbol_names,
            replace_text=replace_text,
            with_text=with_text,
            regex_pattern=regex_pattern,
            insert_before=insert_before,
            insert_after=insert_after,
            append_text=append_text,
            target_function=target_function,
            replace_all=_read_bool_field(body, 'Replace-All'),
            tests=tests,
            add_test_file=add_test_file,
            add_test_content=_read_field(body, 'Add-Test-Content'),
            max_files=_extract_number(body, 'Max-Files'),
            max_attempts=_extract_number(body, 'Max-Attempts'),
        )

#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
TOOLS_ROOT = ROOT / 'integration' / 'tools'
OUTPUT = ROOT / 'third_party' / 'oracle-os' / 'web' / 'public' / 'tool-registry.json'


def health_check(base_url: str, health_path: str, timeout: float = 1.5):
    url = f"{base_url.rstrip('/')}{health_path}"
    req = Request(url, method='GET')
    try:
        with urlopen(req, timeout=timeout) as resp:
            return 200 <= getattr(resp, 'status', 200) < 300
    except (URLError, HTTPError, ValueError):
        return False


def main() -> None:
    manifests = []
    for tool_json in sorted(TOOLS_ROOT.glob('*/tool.json')):
        data = json.loads(tool_json.read_text())
        manifests.append(data)

    capabilities = sorted({cap for manifest in manifests for cap in manifest.get('capabilities', [])})
    tools = []
    for manifest in manifests:
        healthy = health_check(manifest['base_url'], manifest['health_path'])
        tools.append({
            'id': manifest['id'],
            'name': manifest['name'],
            'kind': manifest['kind'],
            'capabilities': manifest.get('capabilities', []),
            'base_url': manifest['base_url'],
            'invoke_path': manifest['invoke_path'],
            'health_path': manifest['health_path'],
            'risk_level': manifest['risk_level'],
            'healthy': healthy,
            'detail': f"{manifest['kind']} · risk={manifest['risk_level']} · caps={', '.join(manifest.get('capabilities', []))}",
        })

    payload = {
        'generated_at': datetime.now(timezone.utc).isoformat(),
        'root_path': str(TOOLS_ROOT),
        'tool_count': len(tools),
        'capabilities': capabilities,
        'tools': tools,
    }
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, indent=2))
    print(f'wrote {OUTPUT}')


if __name__ == '__main__':
    main()

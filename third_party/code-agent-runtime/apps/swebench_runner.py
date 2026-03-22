from __future__ import annotations

import argparse
from pathlib import Path

from runtime.swebench.harness import SwebenchHarness
from runtime.swebench.manifest import load_manifest


def main() -> int:
    parser = argparse.ArgumentParser(description='Run the local harness over a SWE-bench-style manifest')
    parser.add_argument('manifest', type=Path)
    parser.add_argument('--output-dir', type=Path, default=Path('swebench_out'))
    args = parser.parse_args()

    tasks = load_manifest(args.manifest)
    harness = SwebenchHarness()
    results = harness.run_manifest(tasks, args.output_dir)
    print(f'completed {len(results)} task(s)')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

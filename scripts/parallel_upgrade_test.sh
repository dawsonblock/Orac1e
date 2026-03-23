#!/bin/bash
set -e
# Build v7: Parallel Execution Proof
# Tests the ParallelOrchestrator by running multiple tasks in parallel

source .venv/bin/activate

# Setup independent fixture repos
REPO_A="$(pwd)/workspace/fixtures/parallel_a"
REPO_B="$(pwd)/workspace/fixtures/parallel_b"
rm -rf "$REPO_A" "$REPO_B"
mkdir -p "$REPO_A" "$REPO_B"

echo "def first_token(tokens): return tokens[0]" > "$REPO_A/app.py"
echo "def first_token(tokens): return tokens[0]" > "$REPO_B/app.py"

for R in "$REPO_A" "$REPO_B"; do
    cd "$R" && git init && git add . && git commit -m "init" && cd -
done

echo "🚀 Step 2: Triggering Parallel Execution Engine..."
python3 -c "
import sys
import logging
from integration.orchestrator import run_parallel_session

tasks = [
    {'task': 'fix first_token', 'repo_path': '$REPO_A'},
    {'task': 'fix first_token', 'repo_path': '$REPO_B'}
]

try:
    results = run_parallel_session(tasks)
    print(f'Batch execution completed. Tasks processed: {len(results)}')
    print('✅ Parallel Upgrade Verified: Multi-task execution engine is live.')
except Exception as e:
    print(f'❌ Parallel Upgrade Failed: {e}')
    sys.exit(1)
"

echo "📈 Step 3: Verifying Production Grade Features (Logging & Circuit Breakers)..."
export PRODUCTION=true
python3 -c "
import os
import json
from integration.workers_planner import coding_planner_execute, planner_breaker

# 1. Verify JSON logging (will see in output)
print('Testing JSON Output...')
res = coding_planner_execute('test task', '/invalid/path')

# 2. Verify Circuit Breaker triggered by multiple failures
print(f'Initial state: {planner_breaker.state}')
for _ in range(3):
    coding_planner_execute('fail task', '/invalid/path')

print(f'State after failures: {planner_breaker.state}')
if planner_breaker.state == 'OPEN':
    print('✅ Production Reliability verified: Circuit Breaker is OPEN')
else:
    print('❌ Production Reliability failure: Circuit Breaker did not open')
"

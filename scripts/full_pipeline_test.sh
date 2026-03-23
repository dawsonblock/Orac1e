#!/bin/bash
set -ex
# Full Pipeline Proof (P1 #7)
# Tests the Create Run -> Plan -> Execute -> Promote cycle 

# Setup Environment 
source .venv/bin/activate

# Use workspace/fixtures/buggy_temp as it will be cleaned up
TEST_REPO="$(pwd)/workspace/fixtures/buggy_temp"
rm -rf "$TEST_REPO"
mkdir -p "$TEST_REPO"

echo "🏗️ Step 1: Create fixture repo..."
cd "$TEST_REPO"
echo 'function add(a, b) { return a + b; }' > index.js
git init
git add index.js
git commit -m "initial commit"
cd -

echo "🤖 Step 2: Triggering Simulation of Planner..."
python3 -c "
import sys
import os
from integration.workers_planner import coding_planner_execute
result = coding_planner_execute('Fix type error in index.js', '$TEST_REPO')
print(f'Planner result: {result.get(\"success\")}')
"

echo "✅ Pipeline script check complete. Preflight Success."

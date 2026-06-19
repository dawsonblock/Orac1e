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

echo "🤖 Step 2: Triggering Planner..."
RESULT=$(python3 -c "
import sys
import os
import json
from integration.workers_planner import coding_planner_execute
result = coding_planner_execute('Fix type error in index.js', '$TEST_REPO')
print(json.dumps(result))
")

echo "📋 Step 3: Validating Results..."
SUCCESS=$(echo "$RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('success', False))")
if [ "$SUCCESS" != "True" ]; then
    echo "❌ Pipeline failed: Planner did not succeed"
    echo "$RESULT" | python3 -m json.tool
    exit 1
fi

# Validate diff is present and non-empty
DIFF=$(echo "$RESULT" | python3 -c "import sys, json; print(json.load(sys.stdin).get('diff', ''))")
if [ -z "$DIFF" ]; then
    echo "❌ Pipeline failed: No diff produced"
    exit 1
fi

# Validate changed files list
FILES=$(echo "$RESULT" | python3 -c "import sys, json; files = json.load(sys.stdin).get('changed_files', []); print(','.join(files) if files else '')")
if [ -z "$FILES" ]; then
    echo "❌ Pipeline failed: No changed files reported"
    exit 1
fi

# Validate validation report
VALIDATION=$(echo "$RESULT" | python3 -c "import sys, json; v = json.load(sys.stdin).get('validation', {}); print(v.get('success', False))")
if [ "$VALIDATION" != "True" ]; then
    echo "❌ Pipeline failed: Validation did not pass"
    exit 1
fi

echo "✅ Pipeline validated successfully!"
echo "  - Diff produced: ${#DIFF} chars"
echo "  - Files changed: $FILES"
echo "  - Validation: passed"

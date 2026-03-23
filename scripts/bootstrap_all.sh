#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}[bootstrap] Starting unified cold-start...${NC}"

# 1. Setup Venv
if [ ! -d ".venv" ]; then
    echo -e "${BLUE}[bootstrap] 1/6 Creating venv...${NC}"
    python3 -m venv .venv
else
    echo -e "${BLUE}[bootstrap] 1/6 Reusing existsing venv...${NC}"
fi

# 2. Upgrade Pip/Core toolchain
echo -e "${BLUE}[bootstrap] 2/6 Upgrading toolchain...${NC}"
.venv/bin/pip install --upgrade pip setuptools wheel hatchling editables > /dev/null

# 3. Install core dependencies (excluding problematic git ones first)
echo -e "${BLUE}[bootstrap] 3/6 Installing standard requirements...${NC}"
grep -vE "git\+https|egg=" requirements.txt > requirements_bootstrap.txt
.venv/bin/pip install -r requirements_bootstrap.txt > /dev/null

# 4. Install local editable modules
echo -e "${BLUE}[bootstrap] 4/6 Installing local modules...${NC}"
.venv/bin/pip install --no-deps -e third_party/cocoindex-code > /dev/null
.venv/bin/pip install --no-deps -e third_party/code-agent-runtime > /dev/null
.venv/bin/pip install --no-deps -e . > /dev/null

# 5. Verify Aider (Vendored)
echo -e "${BLUE}[bootstrap] 5/6 Verifying aider...${NC}"
export PYTHONPATH=$PWD/third_party/aider
if .venv/bin/python -m aider.main --help > /dev/null 2>&1; then
    echo -e "${GREEN}[bootstrap] Aider OK${NC}"
else
    echo -e "${RED}[bootstrap] Aider check failed. Installing missing deps...${NC}"
    .venv/bin/pip install json5 pexpect pydub sounddevice soundfile analytics-python monotonic > /dev/null
    if .venv/bin/python -m aider.main --help > /dev/null 2>&1; then
        echo -e "${GREEN}[bootstrap] Aider OK (fixed)${NC}"
    else
        echo -e "${RED}[bootstrap] Aider FAIL - manual intervention required${NC}"
        .venv/bin/python -m aider.main --help
        exit 1
    fi
fi

# 6. Final preflight
echo -e "${BLUE}[bootstrap] 6/6 Final preflight...${NC}"
if [ -f "configs/system.yaml" ]; then
    export PYTHONPATH=$PWD
    .venv/bin/python -m integration.preflight
    echo -e "${GREEN}[bootstrap] System OK${NC}"
else
    echo -e "${BLUE}[bootstrap] Skipping preflight (no system.yaml yet)${NC}"
fi

echo -e "${GREEN}[bootstrap] Bootstrapped successfully!${NC}"

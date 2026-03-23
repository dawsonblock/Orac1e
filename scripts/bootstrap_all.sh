#!/usr/bin/env bash
set -euo pipefail

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
    echo -e "${BLUE}[bootstrap] 1/6 Reusing existing venv...${NC}"
fi
source .venv/bin/activate

# 2. Upgrade Pip/Core toolchain
echo -e "${BLUE}[bootstrap] 2/6 Upgrading toolchain...${NC}"
pip install --upgrade pip setuptools wheel hatchling editables > /dev/null

# 3. Install core dependencies
echo -e "${BLUE}[bootstrap] 3/6 Installing standard requirements...${NC}"
pip install -r requirements.txt > /dev/null

# 4. Install local editable modules
echo -e "${BLUE}[bootstrap] 4/6 Installing local modules...${NC}"
pip install -e third_party/aider > /dev/null
pip install -e third_party/code-agent-runtime > /dev/null
pip install -e third_party/cocoindex-code > /dev/null

# 5. Verify imports
echo -e "${BLUE}[bootstrap] 5/6 Verifying imports...${NC}"
python - <<'PY'
import importlib

for module_name in ("integration", "aider", "cocoindex_code", "fastapi", "pydantic", "git"):
    importlib.import_module(module_name)

print("Import checks passed")
PY

# 6. Final preflight
echo -e "${BLUE}[bootstrap] 6/6 Final preflight...${NC}"
if [ -f "configs/system.yaml" ]; then
    python -m integration.preflight
    echo -e "${GREEN}[bootstrap] System OK${NC}"
else
    echo -e "${BLUE}[bootstrap] Skipping preflight (no system.yaml yet)${NC}"
fi

echo -e "${GREEN}[bootstrap] Bootstrapped successfully!${NC}"

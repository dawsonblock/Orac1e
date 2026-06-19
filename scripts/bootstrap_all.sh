#!/usr/bin/env bash
set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}[bootstrap] Starting unified cold-start...${NC}"

# ============================================================================
# Portable Python Interpreter Resolution
# ============================================================================

# Allow PYTHON_BIN override, default to python3
PYTHON_BIN="${PYTHON_BIN:-python3}"

# Check Python exists
if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
    echo -e "${RED}[bootstrap] Python not found: $PYTHON_BIN${NC}"
    echo "Set PYTHON_BIN to specify a different interpreter:"
    echo "  PYTHON_BIN=/path/to/python3.11 bash scripts/bootstrap_all.sh"
    exit 1
fi

echo -e "${BLUE}[bootstrap] Using Python: $PYTHON_BIN${NC}"

# Validate Python version is 3.11+
if ! "$PYTHON_BIN" - <<'EOF'
import sys
min_version = (3, 11)
if sys.version_info < min_version:
    print(f"Python {min_version[0]}.{min_version[1]}+ required, found {sys.version}")
    sys.exit(1)
EOF
 then
    echo -e "${RED}[bootstrap] Python 3.11+ required${NC}"
    "$PYTHON_BIN" --version
    exit 1
fi

PYTHON_VERSION=$("$PYTHON_BIN" --version 2>&1)
echo -e "${BLUE}[bootstrap] Python version OK: $PYTHON_VERSION${NC}"

# 1. Setup Venv
if [ ! -d ".venv" ]; then
    echo -e "${BLUE}[bootstrap] 1/6 Creating venv...${NC}"
    "$PYTHON_BIN" -m venv .venv
else
    echo -e "${BLUE}[bootstrap] 1/6 Reusing existing venv...${NC}"
fi
source .venv/bin/activate

# Use explicit venv Python for all subsequent operations
VENV_PYTHON=".venv/bin/python"
VENV_PIP=".venv/bin/pip"

# 2. Upgrade Pip/Core toolchain
echo -e "${BLUE}[bootstrap] 2/6 Upgrading toolchain...${NC}"
"$VENV_PIP" install --upgrade pip setuptools wheel hatchling editables > /dev/null

# 3. Install core dependencies
echo -e "${BLUE}[bootstrap] 3/6 Installing standard requirements...${NC}"
"$VENV_PIP" install -r requirements.txt > /dev/null

# 4. Install local editable modules
echo -e "${BLUE}[bootstrap] 4/6 Installing local modules...${NC}"
"$VENV_PIP" install -e third_party/aider > /dev/null
"$VENV_PIP" install -e third_party/cocoindex-code > /dev/null
"$VENV_PIP" install -e third_party/code-agent-runtime > /dev/null
"$VENV_PIP" install -e . > /dev/null

# 5. Verify imports
echo -e "${BLUE}[bootstrap] 5/6 Verifying imports...${NC}"
IMPORT_OK=true
for module_name in integration aider cocoindex fastapi pydantic git; do
    if ! "$VENV_PYTHON" -c "import $module_name" 2>/dev/null; then
        echo -e "${RED}[bootstrap] Import failed: $module_name${NC}"
        IMPORT_OK=false
    fi
done

# Verify aider specifically
if "$VENV_PYTHON" -m aider --version > /dev/null 2>&1 || "$VENV_PYTHON" -c "import aider" > /dev/null 2>&1; then
    echo -e "${GREEN}[bootstrap] Aider OK${NC}"
else
    echo -e "${RED}[bootstrap] Aider check failed. Installing missing deps...${NC}"
    "$VENV_PIP" install json5 pexpect pydub sounddevice soundfile analytics-python monotonic > /dev/null
    if "$VENV_PYTHON" -m aider --version > /dev/null 2>&1 || "$VENV_PYTHON" -c "import aider" > /dev/null 2>&1; then
        echo -e "${GREEN}[bootstrap] Aider OK (fixed)${NC}"
    else
        echo -e "${RED}[bootstrap] Aider FAIL - manual intervention required${NC}"
        IMPORT_OK=false
    fi
fi

# 6. Final verification - import checks
echo -e "${BLUE}[bootstrap] 6/6 Verifying runtime imports...${NC}"

IMPORT_OK=true
# Core modules that must be importable
for module in integration.lifecycle integration.preflight integration.orchestrator oracle_runtime.approval_store; do
    if ! "$VENV_PYTHON" -c "import $module" 2>/dev/null; then
        echo -e "${RED}[bootstrap] Import failed: $module${NC}"
        IMPORT_OK=false
    fi
done

# Optional modules (may have additional dependencies)
for module in redis rq; do
    if ! "$VENV_PYTHON" -c "import $module" 2>/dev/null; then
        echo -e "${BLUE}[bootstrap] Optional dependency not available: $module${NC}"
    fi
done

if [ "$IMPORT_OK" = false ]; then
    echo -e "${RED}[bootstrap] Some imports failed - check package installation${NC}"
    exit 1
fi

# 7. Preflight check
if [ -f "configs/system.yaml" ]; then
    echo -e "${BLUE}[bootstrap] 7/7 Running preflight...${NC}"
    "$VENV_PYTHON" -m integration.preflight
    echo -e "${GREEN}[bootstrap] System OK${NC}"
else
    echo -e "${BLUE}[bootstrap] 7/7 Skipping preflight (no system.yaml yet)${NC}"
fi

echo -e "${GREEN}[bootstrap] Bootstrapped successfully!${NC}"
echo ""
echo "To start the system:"
echo "  bash scripts/run_local.sh"

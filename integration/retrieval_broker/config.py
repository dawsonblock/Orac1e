from __future__ import annotations
import os

BROKER_HOST = os.environ.get("ORACLE_HOST", "127.0.0.1")
BROKER_PORT = int(os.environ.get("BROKER_PORT", "8787"))

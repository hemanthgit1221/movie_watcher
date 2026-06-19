"""Shared pytest configuration for FDFS Alert test harness."""

import sys
from pathlib import Path

# Allow `import regression` / `import shared` when invoking `pytest testing/...`
# without an editable install (CI still uses `pip install -e ./testing`).
_ROOT = Path(__file__).resolve().parent
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

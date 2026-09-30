"""Every embedded StyleLib copy must match the master DDingUI_StyleLib."""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / "DDingUI_StyleLib/tools"))
import sync_stylelib as sync


def check():
    assert sync.sync(check=True) == [], "run: python DDingUI_StyleLib/tools/sync_stylelib.py"
    # Private namespaces round-trip, so an edit made in a private copy folds back losslessly.
    core = (sync.MASTER / "Core.lua").read_bytes()
    for addon, spec in sync.PRIVATE.items():
        private = sync.to_private(Path("Core.lua"), core, spec)
        assert b'"' + sync.SHARED_MAJOR.encode() + b'"' not in private, addon
        assert b"\nDDingUI_StyleLib = lib" not in private.replace(b"\r\n", b"\n"), addon
        assert sync.from_private(Path("Core.lua"), private, spec) == core, addon
    print(f"PASS: {len(sync.targets())} StyleLib copies match the master, private namespaces round-trip")


if __name__ == "__main__":
    check()

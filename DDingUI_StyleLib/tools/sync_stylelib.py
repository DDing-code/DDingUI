"""Propagate the master DDingUI_StyleLib to every embedded copy.

The standalone addon folder ``DDingUI_StyleLib/`` is the single source.  Every
addon that embeds StyleLib under ``Libs/DDingUI_StyleLib/`` receives a copy:

* shared copies (CDM, Toolkit, Profile, APL) are byte-identical to the master;
* private copies (RaidHelper, FX) get their own LibStub major and global name
  so an embedded fallback never becomes the code owner of the shared library.
  FX ships only the files its TOC loads.

Usage::

    python DDingUI_StyleLib/tools/sync_stylelib.py            # copy master -> all
    python DDingUI_StyleLib/tools/sync_stylelib.py --check    # exit 1 on drift
    python DDingUI_StyleLib/tools/sync_stylelib.py --from DDingUI_CDM/Libs/DDingUI_StyleLib/Widgets.lua
        # an edit made inside an embedded copy is first folded back into the
        # master (private copies are un-transformed), then propagated.

DDingUI_UF is frozen (2026-08-26) and keeps its old copy; it is never touched.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MASTER = ROOT / "DDingUI_StyleLib"
SHARED_MAJOR = "DDingUI-StyleLib-1.0"
MASTER_ONLY = {"DDingUI_StyleLib.toc", "lib.xml", "tools"}
FROZEN = {"DDingUI_UF"}

SHARED = ["DDingUI_CDM", "DDingUI_Toolkit", "DDingUI_Profile", "DDIngUI_APL"]
PRIVATE = {
    "DDingUI_RaidHelper": {
        "major": "DDingUI-RaidHelper-StyleLib-1.0",
        "files": None,  # every master file
        "core": [
            ('local MAJOR, MINOR = "DDingUI-RaidHelper-StyleLib-1.0"',
             "-- Keep the bundled fallback private.  Registering an embedded copy under the\n"
             "-- shared DDingUI major lets whichever addon loads first become the code owner\n"
             "-- for every other DDingUI addon (and transfers its taint/source identity).\n"
             'local MAJOR, MINOR = "DDingUI-RaidHelper-StyleLib-1.0"'),
            ("-- 하위 호환: 글로벌 참조 유지\nDDingUI_StyleLib = lib",
             "-- RaidHelper resolves this private fallback through ns:GetStyleLib().  Never\n"
             "-- replace the public DDingUI_StyleLib global used by DDingUI/CDM/Toolkit.\n"
             "DDingUI_RaidHelperStyleLib = lib"),
        ],
    },
    "DDingUI_FX": {
        "major": "DDingUI-FX-StyleLib-1.0",
        "files": {"Core.lua", "Colors.lua", "Gradient.lua", "Motion.lua",
                  "Widgets.lua", "DesignTokens.lua"},
        "core": [
            ("-- 하위 호환: 글로벌 참조 유지\nDDingUI_StyleLib = lib",
             "-- 하위 호환: 글로벌 참조 유지\nlocal DDingUI_StyleLib = lib"),
        ],
    },
}


def master_files() -> list[Path]:
    """Relative paths of every master file that embedded copies carry."""
    out = []
    for path in sorted(MASTER.rglob("*")):
        rel = path.relative_to(MASTER)
        if path.is_file() and rel.parts[0] not in MASTER_ONLY and "__pycache__" not in rel.parts:
            out.append(rel)
    return out


def _replace_eol_aware(text: str, old: str, new: str) -> str:
    """Replace ``old`` with ``new`` whether the file uses LF or CRLF."""
    if old in text:
        return text.replace(old, new)
    crlf_old, crlf_new = old.replace("\n", "\r\n"), new.replace("\n", "\r\n")
    if crlf_old in text:
        return text.replace(crlf_old, crlf_new)
    raise ValueError(f"expected block not found: {old.splitlines()[0]!r}")


def to_private(rel: Path, data: bytes, spec: dict) -> bytes:
    if rel.suffix != ".lua":
        return data
    text = data.decode("utf-8").replace(f'"{SHARED_MAJOR}"', f'"{spec["major"]}"')
    if rel.name == "Core.lua":
        for old, new in spec["core"]:
            text = _replace_eol_aware(text, old, new)
    return text.encode("utf-8")


def from_private(rel: Path, data: bytes, spec: dict) -> bytes:
    if rel.suffix != ".lua":
        return data
    text = data.decode("utf-8")
    if rel.name == "Core.lua":
        for old, new in spec["core"]:
            text = _replace_eol_aware(text, new, old)
    return text.replace(f'"{spec["major"]}"', f'"{SHARED_MAJOR}"').encode("utf-8")


def targets() -> list[tuple[str, Path, dict | None]]:
    """(addon, embedded folder, private spec or None) for every live copy."""
    out = []
    for addon in SHARED:
        out.append((addon, ROOT / addon / "Libs" / "DDingUI_StyleLib", None))
    for addon, spec in PRIVATE.items():
        out.append((addon, ROOT / addon / "Libs" / "DDingUI_StyleLib", spec))
    # Any other addon that embeds StyleLib must be registered above.
    known = {a for a, _, _ in out} | FROZEN
    for folder in ROOT.glob("*/Libs/DDingUI_StyleLib"):
        if folder.parts[-3] not in known:
            raise SystemExit(f"unregistered StyleLib copy: {folder.relative_to(ROOT)} "
                             "(add it to SHARED/PRIVATE in sync_stylelib.py)")
    return out


def expected(rel: Path, spec: dict | None) -> bytes | None:
    if spec and spec["files"] is not None and rel.suffix == ".lua" and rel.name not in spec["files"]:
        return None
    data = (MASTER / rel).read_bytes()
    return to_private(rel, data, spec) if spec else data


def sync(check: bool) -> list[str]:
    drift = []
    rels = master_files()
    for addon, folder, spec in targets():
        for rel in rels:
            want = expected(rel, spec)
            if want is None:
                continue
            dest = folder / rel
            if dest.exists() and dest.read_bytes() == want:
                continue
            drift.append(f"{addon}: {rel.as_posix()}")
            if not check:
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(want)
        # Files that the master no longer has are stale in every copy.
        master_set = {r.as_posix() for r in rels}
        for path in folder.rglob("*"):
            rel = path.relative_to(folder)
            if path.is_file() and rel.as_posix() not in master_set and "__pycache__" not in rel.parts:
                # Never delete automatically; a stale file is reported so a person decides.
                drift.append(f"{addon}: {rel.as_posix()} (not in master; remove by hand)")
    return drift


def fold_back(edited: Path) -> str | None:
    """Copy an edit made inside an embedded copy back into the master."""
    edited = edited.resolve()
    try:
        rel_root = edited.relative_to(ROOT)
    except ValueError:
        return None
    parts = rel_root.parts
    if len(parts) < 4 or parts[1:3] != ("Libs", "DDingUI_StyleLib"):
        return None  # master itself (or not StyleLib): nothing to fold
    addon, rel = parts[0], Path(*parts[3:])
    if addon in FROZEN or not edited.is_file():
        return None
    data = edited.read_bytes()
    spec = PRIVATE.get(addon)
    if spec:
        data = from_private(rel, data, spec)
    master = MASTER / rel
    if master.exists() and master.read_bytes() == data:
        return None
    master.parent.mkdir(parents=True, exist_ok=True)
    master.write_bytes(data)
    return f"{addon}/Libs/DDingUI_StyleLib/{rel.as_posix()} -> DDingUI_StyleLib/{rel.as_posix()}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="report drift without writing")
    parser.add_argument("--from", dest="source", type=Path,
                        help="a file edited inside an embedded copy; fold it into the master first")
    args = parser.parse_args(argv)

    folded = None
    if args.source and not args.check:
        folded = fold_back(args.source)
        if folded:
            print(f"folded back: {folded}")
    drift = sync(args.check)
    if args.check:
        for line in drift:
            print(f"DRIFT {line}")
        print("OK: every StyleLib copy matches the master" if not drift
              else f"FAIL: {len(drift)} drifted file(s); run sync_stylelib.py")
        return 1 if drift else 0
    for line in drift:
        print(f"updated {line}")
    print(f"synced {len(drift)} file(s)" if drift else "already in sync")
    return 0


if __name__ == "__main__":
    sys.exit(main())

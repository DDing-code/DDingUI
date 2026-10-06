from __future__ import annotations

import re
import unittest
from pathlib import Path

from lupa import LuaRuntime

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from wcl_pipeline import DPS_COOLDOWNS_BY_SPEC  # noqa: E402


ADDON_ROOT = Path(__file__).resolve().parents[1]


class CooldownCatalogTests(unittest.TestCase):
    def test_dps_catalog_matches_wcl_candidate_ids(self) -> None:
        lua = LuaRuntime(unpack_returned_tuples=True)
        namespace = lua.table()
        lua.execute(
            (ADDON_ROOT / "Data" / "CooldownCatalog.lua").read_text(encoding="utf-8"),
            "DDingUI_RaidHelper", namespace,
        )
        catalog = namespace.CooldownCatalog
        for spec_id, candidates in DPS_COOLDOWNS_BY_SPEC.items():
            spec = catalog.GetSpec(catalog, spec_id)
            self.assertIsNotNone(spec)
            self.assertGreaterEqual(len(spec.spells), 5)
            self.assertEqual(
                {int(spell.spellID) for spell in spec.spells.values()},
                set(candidates),
                f"DPS catalog mismatch for spec {spec_id}",
            )
            for spell_id, candidate in candidates.items():
                entry = catalog.GetEntry(catalog, spec_id, spell_id)
                self.assertEqual(entry.category, candidate["category"])
                self.assertEqual(entry.defaultShown, candidate["default_shown"])

    def test_catalog_loads_before_models_and_contains_halo(self) -> None:
        toc = (ADDON_ROOT / "DDingUI_RaidHelper.toc").read_text(encoding="utf-8")
        catalog_position = toc.index(r"Data\CooldownCatalog.lua")
        registry_position = toc.index(r"Data\Registry.lua")
        self.assertLess(catalog_position, registry_position)

        catalog = (ADDON_ROOT / "Data" / "CooldownCatalog.lua").read_text(
            encoding="utf-8"
        )
        halo = re.search(
            r"spellID\s*=\s*120517.*?category\s*=\s*\"semi\".*?defaultShown\s*=\s*true",
            catalog,
        )
        self.assertIsNotNone(halo)


if __name__ == "__main__":
    unittest.main()

# Third-party sources

## SimulationCraft

- Project: https://github.com/simulationcraft/simc
- Snapshot: faf366dbb9e60c9bab904d5c91da8adaad10ab85 (midnight)
- Generated game data: 12.1.0.69933
- APL sources: ActionPriorityLists/default/*.simc (34 files; exact paths and normalized-text SHA256 in Packs/manifest.json)
- Specialization identities: engine/dbc/generated/sc_specialization_data.inc
- Spell names and IDs: engine/dbc/generated/sc_spell_data.inc
- License: GPL-3.0-or-later. Upstream COPYING is included as LICENSE.
- Copyright remains with the SimulationCraft authors and contributors.
- Pack assembly/generation: tools/sync_simc.py. Original rules are retained, not represented as validated live rotations.

This alpha runtime is distributed under GPL-3.0-or-later together with these data.
All Lua runtime source is included. There is no compiled binary.
This is an independent DDingUI project, not an official Hekili or SimulationCraft release.

## Embedded libraries

- DDingUI_StyleLib: unmodified copies of the DDingUI workspace's canonical Core, Colors, Gradient, Motion, Widgets and DesignTokens modules.
- LibStub 1.0: copyright/license notice retained in Libs/LibStub/LibStub.lua.
- CallbackHandler-1.0 (MINOR 7), LibDataBroker-1.1 (MINOR 4), LibDBIcon-1.0 (MINOR 55): unmodified copies from the DDingUI_Toolkit embeds, used only for the minimap button.
- Media/APL_Icon.tga: built from the workspace's Branding/DDingUI_Symbol_Orange.png by tools/build_brand_icon.py.
- No Hekili runtime source or external binary is bundled.

## API design references

- Blizzard UI source mirror, 12.1.0:
  https://github.com/Gethe/wow-ui-source/tree/09b9db7948abc9b9648dedaab51eb0cf3ee67b31
- SimC expression semantics:
  https://github.com/simulationcraft/simc/wiki/Action-List-Conditional-Expressions
- SimC action lists:
  https://github.com/simulationcraft/simc/wiki/ActionLists

Source inspection does not certify runtime API availability or combat compatibility.

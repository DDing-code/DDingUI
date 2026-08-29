import re
from pathlib import Path


ROOT = Path(__file__).parents[1]


def test_voidcore_helper_is_wired_with_bis_settings_and_safe_prompt_reads() -> None:
    module = (ROOT / "Modules/VoidcoreHelper/VoidcoreHelper.lua").read_text(encoding="utf-8-sig")
    database = (ROOT / "Core/Database.lua").read_text(encoding="utf-8-sig")
    config = (ROOT / "Config_Data.lua").read_text(encoding="utf-8-sig")
    workspace = (ROOT / "UI/Workspace.lua").read_text(encoding="utf-8-sig")
    toc = (ROOT / "DDingUI_Toolkit.toc").read_text(encoding="utf-8-sig")
    popup = (ROOT / "UI/NewModulePopup.lua").read_text(encoding="utf-8-sig")

    assert 'DDingToolKit:RegisterModule("VoidcoreHelper", VoidcoreHelper)' in module
    assert '[3418] = true' in module and '[3513] = true' in module
    assert 'if not IsSecret(entry) and type(entry) == "table" then' in module
    assert 'local currencyID = SafeNumber(entry.currencyID)' in module
    assert 'function VoidcoreHelper:TryAutoDecline(spellID, prompt)' in module
    assert 'DeclineSpellConfirmationPrompt(spellID)' in module
    assert 'configuredTargetCount > 0 and lootEntries and #lootEntries > 0' in module
    assert 'targetCount == 0' in module
    assert 'if self:TryAutoDecline(spellID, prompt) then return end' in module
    assert 'DDINGTOOLKIT_VOIDCORE_DECLINE_WARNING' not in module
    assert 'return tostring(instanceID), displayName' in module
    assert 'tostring(instanceID) .. ":" .. tostring(difficultyID)' not in module
    assert 'function VoidcoreHelper:OpenBISSettings()' in module
    assert 'local SOURCE_ORDER = {' in module
    assert 'C_EncounterJournal.GetLootInfoByIndex(index)' in module
    assert 'EJ_SetLootFilter(classID, specID)' in module
    loot_scan = module.split('local ok = journalInstanceID and pcall(function()', 1)[1].split('local count =', 1)[0]
    assert loot_scan.index('EJ_SelectInstance(journalInstanceID)') < loot_scan.index('EJ_SetLootFilter(classID, specID)')
    assert 'Enum.ItemArmorSubclass.Cosmetic' in module
    assert 'local function IsBISLootItem(itemID, specID)' in module
    assert 'Enum.ItemClass.Weapon' in module
    assert 'classID ~= weaponClass and classID ~= armorClass' in module
    assert 'equipLoc == "INVTYPE_NON_EQUIP_IGNORE"' in module
    assert 'pcall(C_Item.GetItemSpecInfo, itemID)' in module
    assert 'type(specs) == "table" and #specs > 0' in module
    assert 'SafeNumber(allowedSpecID) == specID' in module
    assert 'itemID and IsBISLootItem(itemID, specID)' in module
    assert 'slot ~= ""' not in module
    assert 'function VoidcoreHelper:ToggleTarget(specID, itemID, sourceItemID)' in module
    assert 'sources[tostring(itemID)] = sourceItemID' in module
    assert 'local function GetStoredSourceTargetState(self, specID, sourceItemID)' in module
    assert 'sourceMapComplete and not hasStoredTarget' in module
    assert 'frame.input = CreateFrame("EditBox"' not in module
    item_events = module.split('eventFrame:SetScript("OnEvent"', 1)[1]
    assert item_events.index('event == "GET_ITEM_INFO_RECEIVED"') < item_events.index('local self = activeModule')
    assert 'name or RETRIEVING_ITEM_INFO' in module
    assert 'frame:SetScript("OnUpdate"' in module
    assert 'if not FindVoidcorePrompt() then VoidcoreHelper:HideAdvisor() end' in module
    assert 'bisBySpec = {}' in database
    assert 'bisSourcesBySpec = {}' in database
    assert 'VoidcoreHelper = false' in database
    assert 'tree.panels["voidcorehelper"]' in config
    party = workspace.split('key = "party"', 1)[1].split('key = "alerts"', 1)[0]
    utility = workspace.split('key = "utility"', 1)[1].split('key = "classfeatures"', 1)[0]
    assert '"voidcorehelper"' not in party
    assert '"raidlootpass"' not in party
    assert '"raidlootpass"' in utility
    assert '"voidcorehelper"' in utility
    assert 'profile.VoidcoreHelper.bisBySpec' not in config
    assert 'Modules\\VoidcoreHelper\\VoidcoreHelper.lua' in toc
    assert 'id = "VoidcoreHelper-2.1.5"' in popup

    references = module + config + popup
    keys = set(re.findall(r'(?:L\[|T\()"(VCH_[A-Z0-9_]+|TAB_VOIDCOREHELPER|NEW_MODULE_POPUP_VCH_DESC)"', references))
    for locale_name in ("koKR", "enUS"):
        locale = (ROOT / f"Locales/{locale_name}.lua").read_text(encoding="utf-8-sig")
        assert all(f'L["{key}"]' in locale for key in keys)

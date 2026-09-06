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
    assert 'if configuredTargetCount == 0 then' in module
    assert 'if lootEntries and #lootEntries > 0' in module
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
    assert 'local function IsBISLootItem(itemID, specID, itemLink)' in module
    assert 'Enum.ItemClass.Weapon' in module
    assert 'classID ~= weaponClass and classID ~= armorClass' in module
    assert 'equipLoc == "INVTYPE_NON_EQUIP_IGNORE"' in module
    assert 'pcall(C_Item.IsItemDataCachedByID, itemID)' in module
    assert 'pcall(C_Item.DoesItemContainSpec, itemLink or itemID, playerClassID, specID)' in module
    assert 'pcall(C_Item.GetItemSpecInfo' not in module
    assert 'if type(isEligible) ~= "boolean" then' in module
    assert 'if not itemDataLoading and #items > 0 then self.lootCache[cacheKey] = items end' in module
    assert 'local function ExtractLootEntries(prompt, specID)' in module
    assert 'local lootEntries, lootDataLoading = ExtractLootEntries(prompt, specID)' in module
    assert 'targetDataLoading or lootDataLoading' in module
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


def test_loot_recovers_from_delayed_data_without_losing_filters_or_targets():
    from lupa.lua51 import LuaRuntime

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
        ns = { DDingToolKit = { RegisterModule = function() end } }
        function LibStub() return {} end
        eventFrame = { events = {} }
        function eventFrame:RegisterEvent(event) self.events[event] = true end
        function eventFrame:SetScript(_, callback) self.onEvent = callback end
        function CreateFrame() return eventFrame end
        function notify(event) eventFrame.onEvent(eventFrame, event) end
        timers = {}
        C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
        function flush()
            assert(#timers == 1, "item events must share one refresh")
            table.remove(timers, 1)()
            assert(#timers == 0, "scanning must not enqueue itself")
        end
        function localFunction(fn, wanted)
            for index = 1, 100 do
                local name, value = debug.getupvalue(fn, index)
                if name == wanted then return value end
                if not name then break end
            end
            error("missing local function: " .. wanted)
        end
        function UnitClass() return "Priest", "PRIEST", 5 end
        function InCombatLockdown() return inCombat == true end
        EncounterJournal = { instanceID = 90, IsShown = function() return false end }
        currentInstance, difficulty, filterClass, filterSpec, slotFilter = 90, 16, 2, 70, 11
        function EJ_GetDifficulty() return difficulty end
        function EJ_GetLootFilter() return filterClass, filterSpec end
        function EJ_SelectInstance(id)
            currentInstance, difficulty = id, 1
            notify("EJ_LOOT_DATA_RECIEVED")
        end
        function EJ_SetDifficulty(value) difficulty = value end
        function EJ_GetEncounterInfo(id) return "Ula'tek", nil, id, nil, nil, 1322 end
        function EJ_SelectEncounter(id) currentEncounter = id end
        function EJ_ResetLootFilter() filterClass, filterSpec = 0, 0 end
        function EJ_SetLootFilter(class, spec) filterClass, filterSpec = class, spec end
        loot, outdated, requests = {}, true, {}
        C_EncounterJournal = {
            GetSlotFilter = function() return slotFilter end,
            ResetSlotFilter = function() slotFilter = 0 end,
            SetSlotFilter = function(value) slotFilter = value end,
            GetLootInfoByIndex = function(index) return loot[index] end,
        }
        function EJ_IsLootListOutOfDate() return outdated end
        expectedSpec = 256
        function EJ_GetNumLoot()
            assert(currentInstance == 1322 and difficulty == (currentEncounter == 2895 and 16 or 23), "select instance before difficulty")
            assert(filterClass == 5 and filterSpec == expectedSpec, "keep the selected spec filter")
            assert(slotFilter == 0, "read all equipment slots")
            return #loot
        end
        metadataReady = false
        C_Item = {
            RequestLoadItemDataByID = function(id) requests[id] = true end,
            IsItemDataCachedByID = function() return true end,
            GetItemInfoInstant = function(id)
                if id == 2 and not metadataReady then return nil end
                if id == 268265 or id == 9 then
                    return id, "Armor", "Miscellaneous", id == 268265 and "INVTYPE_NECK" or "INVTYPE_FINGER", 100, 4, 0
                end
                return id, "Armor", "Cloth", "INVTYPE_HEAD", 100,
                    id == 3 and 9 or 4, id == 4 and 5 or 1
            end,
            GetItemSpecInfo = function(item)
                local id = type(item) == "string" and tonumber(item:match("^item:(%d+)")) or item
                if id == 268265 then return {} end
                if id == 9 then return nil end
                if id == 5 or item == 6 then return { 71 } end
                return { 256 }
            end,
            DoesItemContainSpec = function(item, classID, specID)
                assert(classID == 5 and specID == expectedSpec, "query the selected class/spec explicitly")
                local id = type(item) == "string" and tonumber(item:match("^item:(%d+)")) or item
                if id == 268265 or id == 9 then return true end
                return id ~= 5 and item ~= 6 and specID == 256
            end,
        }
        function item(id, name)
            return { itemID = id, name = name or "Item " .. id,
                link = "item:" .. id .. ":0:0", icon = 100, slot = "Head" }
        end
        function checkRestored()
            assert(currentInstance == 90 and difficulty == 16)
            assert(filterClass == 2 and filterSpec == 70 and slotFilter == 11)
        end
    ''')
    lua.execute(
        (ROOT / "Modules/VoidcoreHelper/VoidcoreHelper.lua").read_text(encoding="utf-8-sig"),
        "DDingUI_Toolkit", lua.globals().ns,
    )
    lua.execute(r'''
        local mod = ns.VoidcoreHelper
        mod.bisFrame = { IsShown = function() return true end }
        local rows, err, loading = mod:GetSourceLoot(279618, 256)
        assert(not err and #rows == 0 and loading)
        assert(not mod.lootCache["256:279618"], "initial empty response must not be cached")
        checkRestored()

        loot, outdated = { item(1), item(2), item(3), item(4), item(5), item(6), {} }, false
        rows, err, loading = mod:GetSourceLoot(279618, 256)
        assert(not err and #rows == 2 and rows[1].itemID == 1 and rows[2].itemID == 6)
        assert(loading and requests[2], "missing instant metadata must request data")
        assert(not mod.lootCache["256:279618"], "a partial response must not be cached")
        checkRestored()

        metadataReady, loot[7] = true, item(7)
        local refreshCount = 0
        function mod:RefreshBISFrame()
            refreshCount = refreshCount + 1
            rows, err, loading = self:GetSourceLoot(279618, 256)
        end
        assert(eventFrame.events.EJ_LOOT_DATA_RECIEVED, "listen for journal loot completion")
        notify("EJ_LOOT_DATA_RECIEVED")
        notify("ITEM_DATA_LOAD_RESULT")
        notify("GET_ITEM_INFO_RECEIVED")
        flush()
        assert(refreshCount == 1 and not err and not loading and #rows == 4)
        assert(mod.lootCache["256:279618"], "complete loot can be cached")

        loot[#loot + 1] = item(8)
        notify("EJ_LOOT_DATA_RECIEVED")
        flush()
        assert(#rows == 5, "new journal rows must invalidate the old cache")
        checkRestored()

        inCombat = true
        rows = mod:GetSourceLoot(279618, 256)
        assert(#rows == 5, "already loaded loot remains usable in combat")
        mod.lootCache = nil
        rows, err, loading = mod:GetSourceLoot(279618, 256)
        assert(rows == nil and err == nil and loading, "defer journal mutations during combat")
        inCombat = false
        notify("PLAYER_REGEN_ENABLED")
        flush()
        assert(#rows == 5 and not loading, "resume deferred loot when combat ends")

        local analyze = localFunction(mod.TryAutoDecline, "AnalyzePromptTargets")
        local extract = localFunction(analyze, "ExtractLootEntries")
        C_TooltipInfo = { GetItemByID = function()
            return { lines = {
                { leftText = "- Item 1" },
                { leftText = "- |Hitem:2:0|h[Item 2]|h" },
                { leftText = "- Item 5", itemID = 5 },
                { leftText = "- Item 6" },
            } }
        end }
        local prompt = { sourceItemID = 279618, itemContext = 16, keyLevel = 10 }
        rows, loading = extract(prompt, 256)
        assert(#rows == 3 and not loading, "name-only tooltip loot must resolve within the filtered source")
        assert(rows[1].itemID == 1 and rows[2].itemID == 2 and rows[3].itemID == 6)
        C_TooltipInfo.GetItemByID = function()
            return { lines = { { leftText = "- Unresolved target" } } }
        end
        rows, loading = extract(prompt, 256)
        assert(#rows == 0 and loading, "unknown loot must not be treated as confirmed absent BIS")

        -- Optional spec lists must not veto jewelry accepted by native loot eligibility.
        expectedSpec = 257
        loot = { item(268265, "Aqirbane Reliquary"), item(9, "Common Ring"), item(5), item(3), item(4) }
        local necklaceCached = false
        C_Item.IsItemDataCachedByID = function(id) return id ~= 268265 or necklaceCached end
        rows, err, loading = mod:GetSourceLoot(278284, 257)
        assert(not err and loading and requests[268265], "uncached jewelry must wait for item data")
        assert(not mod.lootCache["257:278284"], "do not cache incomplete raid loot")
        necklaceCached = true
        rows, err, loading = mod:GetSourceLoot(278284, 257)
        assert(not err and not loading and #rows == 2, "Ula'tek jewelry must be listed for Holy")
        assert(rows[1].itemID == 268265 and rows[2].itemID == 9, "keep the neck and ring, exclude wrong-spec/cosmetic/recipe items")
        checkRestored()
        C_TooltipInfo.GetItemByID = function()
            return { lines = { { leftText = "- Aqirbane Reliquary" }, { leftText = "- Common Ring" }, { leftText = "- Item 5", itemID = 5 } } }
        end
        rows, loading = extract({ sourceItemID = 278284, itemContext = 6 }, 257)
        assert(#rows == 2 and not loading, "bonus-roll analysis must use the same jewelry eligibility")
    ''')

from pathlib import Path

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).parent
OVERLAY = (ROOT / "DDingUI_CDM/Modules/GroupSystem/NativeTrinketOverlay.lua").read_text(encoding="utf-8")
SKINNING = (ROOT / "DDingUI_CDM/Modules/IconViewers/IconSkinning.lua").read_text(encoding="utf-8")


def test_native_pair_selection():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
        SECRET = {}
        function issecretvalue(v) return rawequal(v, SECRET) end
        function wipe(t) for k in pairs(t) do t[k] = nil end end
        combat = false
        function InCombatLockdown() return combat end
        local queue = {}
        C_Timer = {After = function(_, fn) queue[#queue + 1] = fn end}
        function flush()
            for i = 1, 50 do
                if #queue == 0 then return end
                local pending = queue; queue = {}
                for _, fn in ipairs(pending) do fn() end
            end
            error("state refresh loop")
        end
        function hooksecurefunc(obj, key, hook)
            local original = obj[key]
            obj[key] = function(self, ...)
                original(self, ...); hook(self, ...)
            end
        end
        local methods = {
            GetAlpha = function(self) return self.alpha end,
            SetAlpha = function(self, alpha) self.alpha = alpha end,
            IsShown = function(self) return self.shown end,
            IsForbidden = function() return false end,
            GetWidth = function() return 40 end,
            GetHeight = function() return 40 end,
            ClearAllPoints = function() end,
            SetPoint = function(self, _, target) self.anchor = target end,
            HookScript = function(self, event, fn) self.hooks[event] = fn end,
            SetScript = function(self, event, fn) self.hooks[event] = fn end,
            RegisterUnitEvent = function() end,
            RegisterEvent = function() end,
            UnregisterAllEvents = function() end,
            IsActive = function(self) return self.active end,
            OnActiveStateChanged = function() end,
        }
        function CreateFrame()
            return setmetatable({alpha = 1, shown = true, hooks = {}}, {__index = methods})
        end
        function proc(id, slot)
            local frame = CreateFrame()
            frame.cooldownID = id
            frame.cooldownInfo = {cooldownID = id, category = 2, equipSlot = slot}
            frame.Cooldown = CreateFrame()
            frame.Applications = CreateFrame()
            frame.active = false
            return frame
        end
        base = CreateFrame(); base.alpha = 0.8
        base._ddIsManaged = true; base._ddContainerRef = {}
        base.cooldown = CreateFrame()
        secondBase = CreateFrame()
        secondBase._ddIsManaged = true; secondBase._ddContainerRef = {}
        secondBase.cooldown = CreateFrame()
        idle, active = proc(101, 13), proc(102, 13)
        secondProc = proc(103, 14)
        apiInfo = {
            [101] = {cooldownID = 101, category = 8, equipSlot = 13, buffSlot = 1},
            [102] = {cooldownID = 102, category = 8, equipSlot = 13, buffSlot = 2},
            [103] = {cooldownID = 103, category = 8, equipSlot = 14, buffSlot = 1},
        }
        C_CooldownViewer = {GetCooldownViewerCooldownInfo = function(id) return apiInfo[id] end}
        function GetInventoryItemID(_, slot) return slot == 14 and 270164 or 249343 end
        dyn = {iconData = {
            bag = {type = "slot", slotID = 13, settings = {trackTrinketEffect = true}},
            second = {type = "slot", slotID = 14, settings = {}},
        }, groups = {trinkets = {icons = {"bag", "second"}}}}
        addon = {
            db = {profile = {dynamicIcons = dyn,
                groupSystem = {groups = {Trinkets = {enabled = true, sourceGroupKey = "trinkets"}}}}},
            CustomIcons = {GetDynamicDB = function() return dyn end,
                GetAllIconFrames = function() return {bag = base, second = secondBase} end},
            FrameController = {SetupFrameInContainer = function(_, frame, target)
                assert(not combat, "combat reanchor")
                frame._ddContainerRef = target
            end, ReleaseFrameFromContainer = function(_, frame)
                assert(not combat, "combat detach")
                frame._ddContainerRef = nil
            end},
        }
        registry = {GetFrames = function(_, viewer)
            return viewer == "BuffIconCooldownViewer"
                and {[101] = idle, [102] = active, [103] = secondProc} or {}
        end}
    ''')
    ns = lua.table(Addon=lua.globals().addon)
    lua.execute((ROOT / "DDingUI_CDM/Core/CDMCompat.lua").read_text(encoding="utf-8"), "DDingUI_CDM", ns)
    lua.execute(OVERLAY, "DDingUI_CDM", ns)
    lua.execute(r'''
        local overlay = addon.NativeTrinketOverlay
        assert(overlay:RefreshPairs(registry) == 2, "nil tracking setting excluded the second slot")
        overlay:ApplyAll(); flush()
        local pair = overlay:GetPairForSlot(13)
        assert(#pair.effects == 2 and idle.anchor == base and active.anchor == base)
        assert(not overlay:IsSlotEffectActive(13), "shown idle effects claimed the trinket")
        assert(base.cooldown.alpha == 1, "idle effects hid the item cooldown")
        assert(overlay:OwnsBaseFrame(secondBase, 14) and secondProc.anchor == secondBase)
        combat = true
        -- Only the second buff slot procs; the first can remain shown in CDM.
        active.active = true; active:OnActiveStateChanged(); flush()
        assert(pair.activeProcFrame == active, "idle first buff masked the active second buff")
        assert(idle.alpha == 0 and active.alpha == 0.8)
        assert(base.cooldown.alpha == 0)
        -- A protected aura handle must not override an explicit inactive state.
        idle.auraInstanceID = SECRET; idle:OnActiveStateChanged(); flush()
        assert(pair.activeProcFrame == active, "protected idle aura handle masked the proc")
        active.active = false; active:OnActiveStateChanged(); flush()
        assert(not overlay:IsSlotEffectActive(13) and base.cooldown.alpha == 1)
        assert(idle.alpha == 0 and active.alpha == 0)
        secondProc.active = true; secondProc:OnActiveStateChanged(); flush()
        assert(secondProc.alpha == 1 and secondBase.cooldown.alpha == 0)
        -- A plain equipped item uses the same default; explicit opt-out still wins.
        combat = false
        dyn.iconData.second = {type = "item", id = 270164}
        assert(overlay:RefreshPairs(registry) == 2, "equipped item was not resolved to slot 14")
        dyn.iconData.second.settings = {trackTrinketEffect = false}
        for i = 1, 3 do overlay:RefreshPairs(registry) end
        assert(not overlay:OwnsBaseFrame(secondBase, 14), "explicit tracking opt-out ignored")
        assert(secondBase.cooldown.alpha == 1)
        dyn.iconData.second = {type = "trinketProc", slotID = 14}
        assert(overlay:RefreshPairs(registry) == 2, "dedicated trinket tracking regressed")
        addon.db.profile.groupSystem.integrateNativeTrinketEffects = false
        assert(overlay:RefreshPairs(registry) == 0, "global integration opt-out ignored")
        flush()
    ''')
    lua.execute(r'''
        -- Native layout notifications reach protected GroupBuffFilter APIs, even
        -- when an addon starts the update outside combat. The overlay only reads.
        local overlay = addon.NativeTrinketOverlay
        addon.db.profile.groupSystem.integrateNativeTrinketEffects = true
        local function forbiddenWrite()
            error("overlay changed Blizzard CDM state (SetHiddenGroupBuffs taint path)")
        end
        local manager = {SaveLayouts = forbiddenWrite, NotifyListeners = forbiddenWrite}
        local provider = {
            GetLayoutManager = function() return manager end,
            GetCooldownInfoForID = function(_, id) return apiInfo[id] end,
            SetCooldownToCategory = forbiddenWrite,
        }
        CooldownViewerSettings = {
            IsShown = function() return false end,
            GetDataProvider = function() return provider end,
        }
        Enum = {CooldownViewerVisibleSetting = {Always = 1, Hidden = 3}}
        BuffIconCooldownViewer = setmetatable({}, {
            __index = {
                visibleSetting = 3,
                IsShown = function() return false end,
                IsForbidden = function() return false end,
                UpdateShownState = forbiddenWrite,
                UpdateSystemSettingVisibleSetting = forbiddenWrite,
            },
            __newindex = forbiddenWrite,
        })
        C_CooldownViewer.GetCooldownViewerCategorySet = function() return {101, 102, 103} end
        addon.CDMCompat:Invalidate()
        for _, inCombat in ipairs({false, true, false}) do
            combat = inCombat
            assert(overlay:RefreshPairs(registry) == 2)
            overlay:ApplyAll(); flush()
        end
        -- A specific item must not retain a stale slot after it is unequipped.
        dyn.iconData.second = {type = "item", id = 400002, slotID = 14}
        for i = 1, 3 do overlay:RefreshPairs(registry) end
        overlay:ApplyAll(); flush()
        assert(not overlay:OwnsBaseFrame(secondBase, 14))
    ''')


def main():
    identity_reader = OVERLAY.split("local function GetEquipmentIdentity", 1)[1].split(
        "local function FindIcon", 1
    )[0]
    assert identity_reader.index("GetCooldownInfo(cooldownID, true)") < identity_reader.index(
        "GetFrameCooldownInfo(frame)"
    )
    assert "categoryLookup[cooldownID]" not in identity_reader

    pair_state = OVERLAY.split("local function ApplyPairState", 1)[1].split(
        "local function RefreshAllStates", 1
    )[0]
    assert pair_state.index("_ddNativeTrinketActive") < pair_state.index("SetSwipeColor")
    assert "RestoreActiveIconVisual" not in pair_state
    assert "effect.visualActive = visualApplied and true or nil" in pair_state
    assert "effect.visualActive = nil" in pair_state
    assert 'FrameFlagIsTrue(icon, "_ddNativeTrinketActive")' in SKINNING


if __name__ == "__main__":
    main()
    test_native_pair_selection()
    print("native trinket overlay contract: ok")

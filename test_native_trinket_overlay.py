from pathlib import Path

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).parent
OVERLAY = (ROOT / "DDingUI_CDM/Modules/GroupSystem/NativeTrinketOverlay.lua").read_text(encoding="utf-8")
SKINNING = (ROOT / "DDingUI_CDM/Modules/IconViewers/IconSkinning.lua").read_text(encoding="utf-8")


def overlay_runtime():
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
            IsProtected = function(self) return self.protected == true end,
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
            GetEquipSlot = function(self) return self.cooldownInfo and self.cooldownInfo.equipSlot end,
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
                assert(not combat or (not frame:IsProtected() and not target:IsProtected()), "protected combat reanchor")
                frame._ddContainerRef = target
                frame._ddLayoutCooldownID = frame.cooldownID
            end, ReleaseFrameFromContainer = function(_, frame)
                assert(not combat or not frame:IsProtected(), "protected combat detach")
                frame._ddContainerRef = nil
                frame:SetAlpha(1)
            end},
        }
        buffFrames = {[101] = idle, [102] = active, [103] = secondProc}
        registry = {GetFrames = function(_, viewer)
            return viewer == "BuffIconCooldownViewer" and buffFrames or {}
        end}
    ''')
    ns = lua.table(Addon=lua.globals().addon)
    lua.execute((ROOT / "DDingUI_CDM/Core/CDMCompat.lua").read_text(encoding="utf-8"), "DDingUI_CDM", ns)
    lua.execute(OVERLAY, "DDingUI_CDM", ns)
    return lua


def test_native_pair_selection():
    lua = overlay_runtime()
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


def test_proc_frames_reassigned_in_combat():
    lua = overlay_runtime()
    lua.execute(r'''
        local overlay = addon.NativeTrinketOverlay
        overlay:RefreshPairs(registry); overlay:ApplyAll(); flush()
        combat = true
        -- Blizzard RefreshData can assign different IDs to the same pooled frames.
        active.cooldownID, secondProc.cooldownID = 103, 102
        active.cooldownInfo = {category = 2, equipSlot = 14}
        secondProc.cooldownInfo = {category = 2, equipSlot = 13}
        active.active = true; active:OnActiveStateChanged(); flush()
        assert(active.alpha == 0, "reused proc appeared over the previous trinket before reconcile")
        assert(base.cooldown.alpha == 1, "reused proc suppressed the wrong item cooldown")
        buffFrames[102], buffFrames[103] = secondProc, active
        overlay:RefreshPairs(registry); overlay:ApplyAll(); flush()
        assert(active.anchor == secondBase and secondProc.anchor == base, "combat pair kept old slots")
        assert(active.alpha == 1 and secondProc.alpha == 0)
        assert(not overlay:IsSlotEffectActive(13) and overlay:IsSlotEffectActive(14))
        secondProc.active = true; secondProc:OnActiveStateChanged(); flush()
        assert(secondProc.alpha == 0.8 and active.alpha == 1, "simultaneous procs fought for one slot")
    ''')


def test_second_proc_appearing_during_combat():
    lua = overlay_runtime()
    lua.execute(r'''
        local overlay = addon.NativeTrinketOverlay
        buffFrames[102] = nil
        overlay:RefreshPairs(registry); overlay:ApplyAll(); flush()
        combat = true
        active.active = true; buffFrames[102] = active
        overlay:RefreshPairs(registry); flush()
        assert(active.anchor == base and active.alpha == 0.8, "new combat proc was never anchored")
        assert(overlay:GetPairForSlot(13).activeProcFrame == active)
        assert(base.cooldown.alpha == 0 and secondBase.cooldown.alpha == 1)
    ''')


def test_missing_pair_cannot_reclaim_recycled_frame():
    lua = overlay_runtime()
    lua.execute(r'''
        local overlay = addon.NativeTrinketOverlay
        buffFrames[102] = nil
        overlay:RefreshPairs(registry); overlay:ApplyAll(); flush()
        combat = true
        -- A transient registry gap retains an unchanged frame.
        buffFrames[101] = nil
        overlay:RefreshPairs(registry); flush()
        assert(overlay:GetPairForSlot(13), "temporary scan miss discarded a valid pair")
        -- Once reused, that same frame can no longer be retained by slot 13.
        idle.cooldownID = 103; idle.active = true
        idle.cooldownInfo = {category = 2, equipSlot = 14}
        buffFrames[103] = idle
        overlay:RefreshPairs(registry); flush()
        assert(not overlay:GetPairForSlot(13), "missing pair retained a recycled frame")
        assert(idle.anchor == secondBase and idle.alpha == 1)
        assert(base.cooldown.alpha == 1 and secondBase.cooldown.alpha == 0)
    ''')


def test_protected_proc_waits_for_safe_layout():
    lua = overlay_runtime()
    lua.execute(r'''
        local overlay = addon.NativeTrinketOverlay
        buffFrames[102] = nil
        overlay:RefreshPairs(registry); overlay:ApplyAll(); flush()
        combat = true
        active.protected = true; active.active = true; buffFrames[102] = active
        overlay:RefreshPairs(registry); flush()
        assert(active.anchor == nil and active.alpha == 0)
        assert(base.cooldown.alpha == 1, "unplaced effect suppressed the base cooldown")
        combat = false; overlay:ApplyAll(); flush()
        assert(active.anchor == base and active.alpha == 0.8)
        -- A protected old frame must still be released after its pair is replaced.
        combat = true
        replacement = proc(102, 13); replacement.active = true
        buffFrames[102] = replacement
        overlay:RefreshPairs(registry); flush()
        assert(active._ddContainerRef == base and active.alpha == 0)
        assert(replacement.anchor == base and replacement.alpha == 0.8)
        combat = false; overlay:ApplyAll(); flush()
        assert(active._ddContainerRef == nil, "protected pending release was lost")
        assert(replacement.anchor == base and replacement.alpha == 0.8)
    ''')


def test_proc_only_base_can_be_shown_before_anchoring():
    lua = overlay_runtime()
    lua.execute(r'''
        local overlay = addon.NativeTrinketOverlay
        dyn.iconData.bag = {type = "trinketProc", slotID = 13, settings = {showItemCooldown = false}}
        base._ddIsManaged = nil; base._ddContainerRef = nil; base.shown = false
        local notified = false
        addon.DynamicIconBridge = {NotifyIconsChanged = function() notified = true end}
        active.active = true
        overlay:RefreshPairs(registry); flush()
        assert(overlay:IsSlotEffectActive(13) and notified, "hidden proc-only base could never enter layout")
        assert(active.alpha == 0 and base.cooldown.alpha == 1)
        base._ddIsManaged = true; base._ddContainerRef = {}; base.shown = true
        overlay:ApplyAll(); flush()
        assert(active.anchor == base and active.alpha == 0.8)
    ''')


def test_reused_proc_does_not_capture_regular_buff_group():
    for hidden_id in (False, True):
        lua = overlay_runtime()
        lua.globals().hiddenID = hidden_id
        lua.execute(r'''
            local overlay = addon.NativeTrinketOverlay
            overlay:RefreshPairs(registry); overlay:ApplyAll(); flush()
            combat = true
            local buffsGroup = {}
            -- The pool frame now holds a regular class buff. Its public metadata
            -- has no equipment slot even when its new ID is temporarily secret.
            apiInfo[201] = {category = 2, spellID = 556}
            active.cooldownID = hiddenID and SECRET or 201
            active.cooldownInfo = {category = 2, spellID = 556}
            active.active = true
            active._ddContainerRef = buffsGroup; active.anchor = buffsGroup
            active:SetAlpha(0.6); active:OnActiveStateChanged(); flush()
            assert(active.anchor == buffsGroup, "regular buff was pulled back to the trinket slot")
            assert(active.alpha == 0.6, "old trinket pair hid a regular buff in another group")
            assert(not overlay:IsOverlayFrame(active), "regular buff remained excluded from group classification")
            buffFrames[102] = nil; buffFrames[201] = active
            overlay:RefreshPairs(registry); flush()
            assert(active._ddContainerRef == buffsGroup and active.alpha == 0.6,
                "detaching the old pair released the buff's new group")
        ''')


def test_secret_equipment_metadata_keeps_valid_proc():
    lua = overlay_runtime()
    lua.execute(r'''
        local overlay = addon.NativeTrinketOverlay
        overlay:RefreshPairs(registry); overlay:ApplyAll(); flush()
        combat = true
        active.cooldownID = SECRET
        active.cooldownInfo = {category = 2, equipSlot = SECRET}
        active.active = true; active:OnActiveStateChanged(); flush()
        assert(active.anchor == base and active.alpha == 0.8)
        assert(overlay:IsOverlayFrame(active) and overlay:IsSlotEffectActive(13))
        -- A readable slot change also overrides an old cached ID.
        active.cooldownInfo.equipSlot = 14
        active:OnActiveStateChanged(); flush()
        assert(not overlay:IsOverlayFrame(active) and active.alpha == 0)
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
    test_proc_frames_reassigned_in_combat()
    test_second_proc_appearing_during_combat()
    test_missing_pair_cannot_reclaim_recycled_frame()
    test_protected_proc_waits_for_safe_layout()
    test_proc_only_base_can_be_shown_before_anchoring()
    test_reused_proc_does_not_capture_regular_buff_group()
    test_secret_equipment_metadata_keeps_valid_proc()
    print("native trinket overlay contract: ok")

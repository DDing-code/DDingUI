from pathlib import Path

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).parent


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
        secret = {}
        function issecretvalue(value) return rawequal(value, secret) end
        local compat = {}
        function compat:IsPublicValue(value) return not issecretvalue(value) end
        function compat:IsUsableID(value)
            return not issecretvalue(value) and type(value) == "number" and value > 0
        end
        function compat:ResolveFrameSpellID(frame) return frame.auraSpellID end
        function compat:GetLiveOverrideSpellID(spellID)
            return spellID == 366155 and (liveOverride or spellID) or spellID
        end
        addon = {
            CDMCompat = compat,
            IconViewers = { _iconData = {}, _cdData = {}, _texData = {} },
            GetFont = function() return nil end,
        }
        function upvalue(fn, wanted, seen)
            seen = seen or {}
            if seen[fn] then return end
            seen[fn] = true
            for i = 1, 100 do
                local name, value = debug.getupvalue(fn, i)
                if not name then break end
                if name == wanted then return value end
                if type(value) == "function" then
                    local found = upvalue(value, wanted, seen)
                    if found then return found end
                end
            end
        end
    ''')
    lua.execute(
        (ROOT / "DDingUI_CDM/Modules/IconViewers/IconSkinning.lua").read_text(encoding="utf-8"),
        "DDingUI_CDM",
        lua.table(Addon=lua.globals().addon),
    )
    lua.execute(r'''
        local apply = assert(upvalue(addon.IconViewers.SkinIcon, "ApplyHiddenActiveCooldown"))
        local gray = assert(upvalue(addon.IconViewers.SkinIcon, "SetHideActiveStateGray"))
        local texture = {
            SetDesaturated = function(self, value) self.desaturated = value end,
            SetDesaturation = function(self, value) self.desaturation = value end,
            SetVertexColor = function(self, r, g, b, a) self.color = { r, g, b, a } end,
        }
        local cooldown = {
            SetDrawSwipe = function() end,
            SetReverse = function() end,
            SetUseAuraDisplayTime = function() end,
            SetSwipeColor = function() end,
            SetHideCountdownNumbers = function() end,
            GetRegions = function() end,
            Clear = function(self) self.duration = nil end,
            SetCooldownFromDurationObject = function(self, value) self.duration = value end,
        }
        local frame = {
            Icon = texture, Cooldown = cooldown, auraSpellID = 1256579,
            GetBaseSpellID = function() return 366155 end,
            HasVisualDataSource_Charges = function(self) return self.wasSetFromCharges end,
        }
        local settings = { hideActiveState = true }
        local cdd = { parentIcon = frame, settings = settings }
        addon.IconViewers._cdData[cooldown] = cdd
        local spellInfo, spellDuration, chargeDuration, queriedID
        local baseDuration = { base = true }
        C_Spell = {
            GetSpellCooldown = function(spellID)
                queriedID = spellID
                if spellID == 1256581 then return spellInfo end
                return { isActive = true, isOnGCD = false }
            end,
            GetSpellCooldownDuration = function(spellID)
                return spellID == 1256581 and spellDuration or
                    (spellID == 366155 and baseDuration or nil)
            end,
            GetSpellChargeDuration = function(spellID)
                assert(spellID == 1256581, "charge duration must use the live override")
                return chargeDuration
            end,
        }

        liveOverride = 1256581
        spellInfo = { isActive = false, isOnGCD = false }
        cooldown.duration = { aura = true }
        texture:SetDesaturated(true)
        apply(frame, cooldown, cdd, settings, true)
        assert(texture.desaturated == false, "castable Merithra proc must not be gray")
        assert(queriedID == 1256581, "aura ID is not the castable spell ID")
        assert(cooldown.duration == nil, "ready override must clear the previous aura timer")
        assert(addon.IconViewers._iconData[frame].hideActiveStateGray == false,
            "ready override must retain ownership across native desaturation updates")

        spellInfo = { isActive = true, isOnGCD = false }
        spellDuration = { realCooldown = true }
        apply(frame, cooldown, cdd, settings, true)
        assert(texture.desaturated == true, "a real override cooldown must still be gray")
        assert(cooldown.duration == spellDuration)

        spellInfo.isOnGCD = true
        spellDuration = { gcd = true }
        apply(frame, cooldown, cdd, settings, true)
        assert(texture.desaturated == false, "GCD alone must not gray a castable proc")
        assert(cooldown.duration == spellDuration)

        spellInfo.isOnGCD = false
        frame.wasSetFromCharges = true
        chargeDuration = { recharge = true }
        apply(frame, cooldown, cdd, settings, true)
        assert(texture.desaturated == false, "a banked charge remains usable during recharge")
        assert(cooldown.duration == chargeDuration)

        frame.wasSetFromCharges = false
        apply(frame, cooldown, cdd, settings, true)
        assert(texture.desaturated == true, "exhausted charges retain real cooldown gray")
        assert(cooldown.duration == spellDuration)

        spellInfo = { isActive = secret, isOnGCD = secret }
        gray(frame, true)
        assert(texture.desaturated == true, "unknown state must not be treated as ready")

        liveOverride = nil
        apply(frame, cooldown, cdd, settings, true)
        assert(queriedID == 366155, "proc expiration must return to the base spell")
        assert(cooldown.duration == baseDuration)
        gray(frame, false)
        assert(addon.IconViewers._iconData[frame].hideActiveStateGray == nil)
        assert(texture.desaturated == false and texture.desaturation == 0)
    ''')
    print("hidden active cooldown: Lua 5.1 behavior checks passed")


if __name__ == "__main__":
    main()

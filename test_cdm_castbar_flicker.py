"""The CDM cast bar and its options preview copy must not re-apply unchanged textures/geometry.

Lua 5.1 checks against the real DDingUI_CDM/Modules/CastBars/CastBars.lua + PlayerCastBar.lua and
DDingUI_CDM_Option/DashboardPreview.lua with call-counting frame mocks:
  * UpdateCastBarLayout called again with the same settings (every cast start, anchor-width
    notifications, test cast) does not call SetStatusBarTexture / SetWidth / SetHeight /
    ClearAllPoints / SetPoint again and only notifies when the width really changed,
  * the anchor-width listener ignores the cast bar's own width notification,
  * a looping test cast restarts in place at its end (no hide, no relayout); a normal one ends,
  * re-copying the preview (every 0.25 s) never hides a cell and never re-sets an unchanged
    status-bar texture, texture, font or anchor.
"""
from pathlib import Path

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).parent

MOCKS = r'''
counts = {}
function Count(key) counts[key] = (counts[key] or 0) + 1 end
function N(key) return counts[key] or 0 end
function ResetCounts() for k in pairs(counts) do counts[k] = nil end end
clock = 100
function GetTime() return clock end
function GetBuildInfo() return "12.1.0", "1", "", 120100 end
function InCombatLockdown() return false end
function issecretvalue() return false end
function wipe(t) for k in pairs(t) do t[k] = nil end end
UIParent = nil
C_Timer = { After = function(_, fn) fn() end, NewTicker = function() return { Cancel = function() end } end }

local Base = {}
local function New(tag, parent)
    local o = { _tag = tag, _parent = parent, _shown = true, _scripts = {}, _level = 1, _alpha = 1 }
    return setmetatable(o, { __index = function(t, k)
        if Base[k] then return Base[k] end
        -- any other widget method (capitalised) is a no-op; data fields stay nil
        if type(k) == "string" and k:match("^[A-Z]") then return function() end end
    end })
end
NewObject = New
function Base:SetPoint(p, rel, rp, x, y)
    Count(self._tag .. ":SetPoint")
    self._np = (self._np or 0) + 1
    if self._np == 1 then self._p = { p, rel, rp, x, y } end
end
function Base:ClearAllPoints() Count(self._tag .. ":ClearAllPoints"); self._np = 0; self._p = nil end
function Base:SetAllPoints(rel) Count(self._tag .. ":SetAllPoints"); self._np = 2; self._p = { "TOPLEFT", rel, "TOPLEFT", 0, 0 } end
function Base:GetNumPoints() return self._np or 0 end
function Base:GetPoint() local p = self._p; if p then return p[1], p[2], p[3], p[4], p[5] end end
function Base:SetWidth(w) Count(self._tag .. ":SetWidth"); self._w = w end
function Base:SetHeight(h) Count(self._tag .. ":SetHeight"); self._h = h end
function Base:SetSize(w, h) Count(self._tag .. ":SetSize"); self._w, self._h = w, h end
function Base:GetWidth() return self._w or 0 end
function Base:GetHeight() return self._h or 0 end
function Base:GetRect() return self._x or 0, self._y or 0, self._w or 0, self._h or 0 end
function Base:Show() if not self._shown then Count(self._tag .. ":Show") end; self._shown = true end
function Base:Hide() Count(self._tag .. ":Hide"); self._shown = false end
function Base:SetShown(v) if v then self:Show() else self:Hide() end end
function Base:IsShown() return self._shown end
function Base:IsVisible() return self._shown end
function Base:GetParent() return self._parent end
function Base:SetParent(p) self._parent = p end
function Base:SetScript(k, v) self._scripts[k] = v end
function Base:GetScript(k) return self._scripts[k] end
function Base:GetFrameLevel() return self._level end
function Base:SetFrameLevel(l) Count(self._tag .. ":SetFrameLevel"); self._level = l end
function Base:GetEffectiveScale() return 1 end
function Base:GetEffectiveAlpha() return self._alpha end
function Base:SetAlpha(a) self._alpha = a end
function Base:GetObjectType() return self._type or "Frame" end
function Base:CreateTexture() local t = New(self._tag .. ".tex", self); t._type = "Texture"; return t end
function Base:CreateMaskTexture() return New(self._tag .. ".mask", self) end
function Base:CreateFontString() local t = New(self._tag .. ".text", self); t._type = "FontString"; return t end
function Base:SetTexture(tex) Count(self._tag .. ":SetTexture"); self._tex = tex end
function Base:SetColorTexture(r, g, b, a) self._colorTexture = { r, g, b, a } end
function Base:GetTexture() return self._tex end
function Base:SetAtlas(a) Count(self._tag .. ":SetAtlas"); self._atlas = a end
function Base:GetAtlas() return nil end
function Base:SetStatusBarTexture(tex)
    Count(self._tag .. ":SetStatusBarTexture")
    self._fill = self._fill or New(self._tag .. ".fill", self)
    self._fill._tex = tex
end
function Base:GetStatusBarTexture() return self._fill end
function Base:SetMinMaxValues(lo, hi) self._min, self._max = lo, hi end
function Base:GetMinMaxValues() return self._min or 0, self._max or 1 end
function Base:SetValue(v) self._value = v end
function Base:GetValue() return self._value or 0 end
function Base:GetInterpolatedValue() return self._value or 0 end
function Base:SetStatusBarColor(r, g, b, a) self._color = { r, g, b, a } end
function Base:GetStatusBarColor() local c = self._color or { 1, 1, 1, 1 }; return c[1], c[2], c[3], c[4] end
function Base:GetOrientation() return self._orientation or "HORIZONTAL" end
function Base:SetOrientation(o) Count(self._tag .. ":SetOrientation"); self._orientation = o end
function Base:SetFont(font, size, flags) Count(self._tag .. ":SetFont"); self._font = { font, size, flags }; return true end
function Base:GetFont() local f = self._font; if f then return f[1], f[2], f[3] end end
function Base:SetText(t) self._text = t end
function Base:GetText() return self._text end
function Base:GetTextColor() return 1, 1, 1, 1 end
function Base:GetTexCoord() return 0, 1, 0, 1 end
function Base:GetVertexColor() return 1, 1, 1, 1 end
function Base:GetDesaturation() return 0 end
function Base:GetNumMaskTextures() return 0 end
function Base:GetRegions() return unpack(self._regions or {}) end
function Base:GetChildren() return unpack(self._children or {}) end
function CreateFrame(kind, name, parent)
    local f = New(name or kind, parent)
    f._type = kind
    f._shown = true
    return f
end
UIParent = New("UIParent")
UIParent._w, UIParent._h = 1920, 1080
'''


def cast_runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCKS + r'''
        notified = {}
        widthListener = nil
        anchor = NewObject("anchor")
        addon = {
            db = { profile = { castBar = { enabled = true, width = 0, height = 18, showSpark = true } } },
        }
        function addon:Scale(v) return v end
        function addon:GetTexture(name) return name or "Interface\\bar\\flat" end
        function addon:GetFont() return "Fonts\\2002.TTF" end
        function addon:GetGlobalFont() return "Fonts\\2002.TTF" end
        function addon:ResolveAnchorFrame() return anchor end
        autoWidth = 240
        function addon:ResolveAutoWidth() return autoWidth end
        function addon:NotifyAnchorWidthChanged(key) notified[#notified + 1] = key end
        function addon:RegisterAnchorWidthListener(fn) widthListener = fn end
    ''')
    ns = lua.table(Addon=lua.globals().addon)
    for path in ("DDingUI_CDM/Modules/CastBars/CastBars.lua", "DDingUI_CDM/Modules/CastBars/PlayerCastBar.lua"):
        lua.execute((ROOT / path).read_text(encoding="utf-8"), "DDingUI_CDM", ns)
    return lua


def test_cast_bar_layout_only_applies_changes():
    lua = cast_runtime()
    lua.execute(r'''
        local CastBars = addon.CastBars
        local bar = CastBars:GetCastBar()
        CastBars:UpdateCastBarLayout()          -- first layout applies everything once
        assert(#notified == 1 and notified[1] == "castBar", "first width not announced")
        ResetCounts(); notified = {}
        for _ = 1, 5 do CastBars:UpdateCastBarLayout() end   -- e.g. five cast starts
        for _, key in ipairs({ "StatusBar:SetStatusBarTexture", "DDingUICastBar:SetWidth",
            "DDingUICastBar:SetHeight", "DDingUICastBar:ClearAllPoints", "DDingUICastBar:SetPoint",
            "StatusBar:ClearAllPoints", "StatusBar:SetPoint", "DDingUICastBar.tex:ClearAllPoints" }) do
            assert(N(key) == 0, key .. " re-applied with unchanged settings: " .. N(key))
        end
        assert(#notified == 0, "width notification without a width change")

        -- the cast bar's own width notification does not relayout it again
        widthListener({ castBar = true })
        assert(N("StatusBar:SetStatusBarTexture") == 0 and N("DDingUICastBar:SetWidth") == 0)

        -- a real anchor width change still resizes and notifies exactly once
        autoWidth = 260
        widthListener({ powerBar = true })
        assert(N("DDingUICastBar:SetWidth") == 1 and bar:GetWidth() == 260)
        assert(#notified == 1 and notified[1] == "castBar")
        assert(N("StatusBar:SetStatusBarTexture") == 0, "texture re-applied on a width change")

        -- a texture change is applied
        addon.db.profile.castBar.texture = "Interface\\bar\\other"
        CastBars:UpdateCastBarLayout()
        assert(N("StatusBar:SetStatusBarTexture") == 1)
        -- a moved bar (e.g. by the mover) is re-anchored
        bar:ClearAllPoints(); bar:SetPoint("TOP", UIParent, "TOP", 5, 5)
        ResetCounts()
        CastBars:UpdateCastBarLayout()
        assert(N("DDingUICastBar:SetPoint") == 1, "moved bar was not re-anchored")
    ''')


def test_looping_test_cast_restarts_in_place():
    lua = cast_runtime()
    lua.execute(r'''
        local CastBars = addon.CastBars
        local bar = CastBars:GetCastBar()
        CastBars:ShowTestCastBar(true)
        local onUpdate = bar:GetScript("OnUpdate")
        assert(onUpdate and bar:IsShown() and CastBars:IsTestCastActive())
        ResetCounts()
        clock = clock + 15.02                     -- one frame past the end
        onUpdate(bar, 0.016)
        assert(bar:IsShown() and N("DDingUICastBar:Hide") == 0, "looping test cast blinked at its end")
        assert(CastBars:IsTestCastActive() and bar.startTime == clock and bar.endTime == clock + 15)
        assert(N("StatusBar:SetStatusBarTexture") == 0 and N("DDingUICastBar:ClearAllPoints") == 0,
            "loop re-applied the layout")
        -- stopping ends it; a normal (button) test cast still ends after 15 s
        assert(CastBars:StopTestCastBar() and not bar:IsShown())
        CastBars:ShowTestCastBar()
        clock = clock + 15.02
        bar:GetScript("OnUpdate")(bar, 0.016)
        assert(not bar:IsShown(), "non-looping test cast did not end")
    ''')


def test_preview_recopy_never_blanks_or_resets():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCKS + r'''
        addon = { GUI = {} }
    ''')
    ns = lua.table(Addon=lua.globals().addon)
    lua.execute((ROOT / "DDingUI_CDM_Option/DashboardPreview.lua").read_text(encoding="utf-8"),
                "DDingUI_CDM_Option", ns)
    lua.execute(r'''
        local Preview = addon.GUI.DashboardPreview
        -- runtime cast bar: frame > status bar (fill, spark, time text) + background texture
        local bar = CreateFrame("Frame", "srcBar")
        bar._x, bar._y, bar._w, bar._h = 100, 100, 200, 20
        local status = CreateFrame("StatusBar", "srcStatus", bar)
        status._x, status._y, status._w, status._h = 100, 100, 200, 20
        status:SetStatusBarTexture("Interface\\bar\\flat")
        status:SetMinMaxValues(0, 15); status:SetValue(3)
        local spark = status:CreateTexture(); spark:SetTexture("spark")
        spark._x, spark._y, spark._w, spark._h = 140, 95, 15, 30
        local text = status:CreateFontString(); text:SetFont("Fonts\\2002.TTF", 10, "OUTLINE"); text:SetText("3.0")
        text._x, text._y, text._w, text._h = 260, 100, 30, 20
        local bg = bar:CreateTexture(); bg:SetTexture("bg")
        bg._x, bg._y, bg._w, bg._h = 100, 100, 200, 20
        bar._regions = { bg }
        bar._children = { status }
        status._regions = { status._fill, spark, text }
        status._fill._x, status._fill._y, status._fill._w, status._fill._h = 100, 100, 40, 20

        local host = CreateFrame("Frame", "host")
        local bounds = { left = 90, bottom = 90 }
        local painted = Preview.Paint(host, { bar }, bounds, 1)
        assert(painted == 4, "painted " .. tostring(painted))
        ResetCounts()
        for frame = 1, 8 do                        -- two seconds of 0.25 s full copies
            clock = clock + 0.25
            status:SetValue(3 + frame * 0.25); text:SetText(string.format("%.1f", 3 + frame * 0.25))
            assert(Preview.Paint(host, { bar }, bounds, 1) == 4)
        end
        for key, n in pairs(counts) do
            assert(not key:find(":Hide$"), "a copy cell was hidden during a re-copy: " .. key)
            assert(not key:find(":SetStatusBarTexture$"), "status bar texture re-set: " .. key .. " x" .. n)
            assert(not key:find(":SetTexture$") or key:find("^src"), "texture re-set: " .. key .. " x" .. n)
            assert(not key:find(":SetFont$") or key:find("^src"), "font re-set: " .. key)
            assert(not key:find(":ClearAllPoints$") or key:find("^src"), "anchor re-set: " .. key)
        end
        -- values still follow, and a moved spark / changed texture is applied
        local cell = host._previewPool.StatusBar[1]
        assert(cell._value == 5 and host._previewPool.FontString[1].visual._text == "5.0")
        spark._x = 150
        status:SetStatusBarTexture("Interface\\bar\\other")
        ResetCounts()
        Preview.Paint(host, { bar }, bounds, 1)
        assert(N("StatusBar:SetStatusBarTexture") == 1, "changed texture not applied to the copy")
        assert(N("Frame:ClearAllPoints") == 1, "moved spark not re-anchored exactly once")
    ''')


def test_preview_text_is_not_truncated():
    """Single-anchored texts the game shows in full (cast name, "11.5/15.0") must not get an
    ellipsis in the copy because scaled glyphs are a little wider than the copied box."""
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(MOCKS + "addon = { GUI = {} }")
    ns = lua.table(Addon=lua.globals().addon)
    lua.execute((ROOT / "DDingUI_CDM_Option/DashboardPreview.lua").read_text(encoding="utf-8"),
                "DDingUI_CDM_Option", ns)
    lua.execute(r'''
        local Preview = addon.GUI.DashboardPreview
        local bar = CreateFrame("Frame", "srcBar")
        bar._x, bar._y, bar._w, bar._h = 100, 100, 200, 20
        local time = bar:CreateFontString(); time:SetFont("font.ttf", 10, "OUTLINE"); time:SetText("11.5/15.0")
        time._x, time._y, time._w, time._h = 250, 100, 48, 20
        time.GetJustifyH = function() return "RIGHT" end
        time.IsTruncated = function() return false end
        bar._regions = { time }
        local host = CreateFrame("Frame", "host")
        assert(Preview.Paint(host, { bar }, { left = 90, bottom = 90 }, 1.3) == 1)
        local visual = host._previewPool.FontString[1].visual
        assert(visual:GetNumPoints() == 1 and visual._p[1] == "RIGHT",
            "full text copy is still boxed (ellipsis): points=" .. visual:GetNumPoints())
        -- a text the game itself truncates keeps the source box, so the copy truncates alike
        time.IsTruncated = function() return true end
        Preview.Paint(host, { bar }, { left = 90, bottom = 90 }, 1.3)
        assert(visual:GetNumPoints() == 2, "truncated text lost its box")
    ''')


def test_ellesmere_channel_tick_conditions():
    lua = cast_runtime()
    lua.execute(r'''
        local CastBars = addon.CastBars
        local cfg = addon.db.profile.castBar
        local bar = CastBars:GetCastBar()
        bar.status:SetSize(120, 20)
        bar.isChannel, bar.isEmpowered = true, false
        bar.startTime, bar.endTime = 100, 104
        known = {}
        function IsPlayerSpell(id) return known[id] or false end
        function issecretvalue(v) return v == "secret" end
        local function Draw(id, castID)
            bar.spellID, bar.castBarID = id, castID
            CastBars:UpdateChannelTicks(bar)
        end

        Draw(5143, 1) -- Arcane Missiles: first and last missiles are at bar edges
        assert(bar.numChannelTicks == 4 and bar.channelTicks[1]._p[4] == 90
            and bar.channelTicks[3]._p[4] == 30)
        known[236628] = true -- Amplification adds two missiles
        Draw(5143, 1) -- the same channel is re-reported after the modifier changes
        assert(bar.numChannelTicks == 6 and bar.channelTicks[5]._p[4] == 20)
        known[236628] = nil
        C_Item = { GetSetBonusesForSpecializationByItemID = function(_, item)
            if item == 101 or item == 102 then return { 1296581 } end
        end }
        function GetSpecialization() return 1 end
        function GetSpecializationInfo() return 62 end
        function GetInventoryItemID(_, slot) if slot <= 2 then return 100 + slot end end
        Draw(5143, 3) -- two equipped set pieces add one missile
        assert(bar.numChannelTicks == 5 and bar.channelTicks[4]._p[4] == 24)
        C_Item = nil
        bar.startTime, bar.endTime = 120, 124
        Draw(5143, 10)
        bar.startTime, bar.endTime = 123.3, 127.3
        Draw(5143, 11) -- chained missiles keep the outgoing cadence
        assert(bar.numChannelTicks == 5 and bar.channelTicks[1]._p[4] == 99)
        local carry = bar._tickCarry
        bar.endTime = 128
        Draw(5143, 11) -- duration update is still the same channel
        assert(math.abs(bar._tickCarry - carry) < 0.001)

        bar.startTime, bar.endTime = 100, 104
        Draw(356995, 4) -- Disintegrate: immediate damage, three intervals
        assert(bar.numChannelTicks == 3 and bar.channelTicks[2]._p[4] == 40)
        bar.startTime, bar.endTime = 103, 107 -- chained before the previous end
        Draw(356995, 5)
        assert(bar.numChannelTicks == 4 and bar.channelTicks[1]._p[4] == 90
            and bar.channelTicks[3]._p[4] == 30)
        known[1219723] = true -- Azure Celerity: four intervals on a fresh cast
        bar.startTime, bar.endTime = 110, 114
        Draw(356995, 6)
        assert(bar.numChannelTicks == 4 and bar.channelTicks[3]._p[4] == 30)

        known[459794] = true -- Quick Draw adds three Rapid Fire missiles
        Draw(257044, 7)
        assert(bar.numChannelTicks == 9)
        cfg.showChannelTickMarks, cfg.showChannelLastTick = false, true
        cfg.channelLastTickColor = { 0.2, 0.4, 0.6, 0.8 }
        Draw(257044, 7)
        assert(not bar.channelTicks[1]:IsShown() and bar.channelTicks[8]:IsShown())
        local lastColor = bar.channelTicks[8]._colorTexture
        assert(lastColor[1] == 0.2 and lastColor[2] == 0.4
            and lastColor[3] == 0.6 and lastColor[4] == 0.8)
        cfg.showChannelTickMarks, cfg.showChannelLastTick = true, false
        cfg.channelTickColor = { 0.1, 0.3, 0.5, 0.7 }
        Draw(257044, 7)
        lastColor = bar.channelTicks[8]._colorTexture
        assert(bar.channelTicks[8]:IsShown() and lastColor[1] == 0.1
            and lastColor[2] == 0.3 and lastColor[3] == 0.5 and lastColor[4] == 0.7)
        cfg.showChannelTicks = false
        Draw(257044, 7)
        assert(not bar.channelTicks[8]:IsShown())
        cfg.showChannelTicks = true
        Draw(999999, 8)
        assert(bar.numChannelTicks == 0)
        Draw("secret", 9)
        assert(bar.numChannelTicks == 0)
        bar.spellID, bar.endTime = 15407, "secret"
        CastBars:UpdateChannelTicks(bar)
        assert(bar.numChannelTicks == 0)

        bar.endTime, bar.spellID = 104, 5143
        cfg.showChannelTickMarks, cfg.showChannelLastTick = true, false
        CastBars:ShowTestCastBar()
        bar.isChannel, bar.castBarID = true, 12
        bar.startTime, bar.endTime = clock, clock + 4
        CastBars:UpdateChannelTicks(bar)
        for _, tick in pairs(bar.channelTicks) do
            tick.ClearAllPoints = function() error("ticks were re-anchored every frame") end
        end
        bar:GetScript("OnUpdate")(bar, 0.016)
    ''')


if __name__ == "__main__":
    test_cast_bar_layout_only_applies_changes()
    test_looping_test_cast_restarts_in_place()
    test_preview_recopy_never_blanks_or_resets()
    test_preview_text_is_not_truncated()
    test_ellesmere_channel_tick_conditions()
    print("CDM cast bar flicker: layout guards, looping test cast, preview re-copy OK")

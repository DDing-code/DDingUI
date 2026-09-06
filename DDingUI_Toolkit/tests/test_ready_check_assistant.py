from pathlib import Path


ROOT = Path(__file__).parents[1]


def panel_runtime(locale="koKR"):
    from lupa.lua51 import LuaRuntime

    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
        local methods = {}
        regions = {}
        local function region(kind, name, parent)
            local value = setmetatable({kind=kind, name=name, parent=parent, points={}, scripts={}, shown=true}, {__index=methods})
            regions[#regions+1] = value
            return value
        end
        function CreateFrame(kind, name, parent) return region(kind, name, parent) end
        function methods:CreateTexture(name) return region("Texture", name, self) end
        function methods:CreateFontString(name) return region("FontString", name, self) end
        function methods:SetScript(name, callback) self.scripts[name] = callback end
        function methods:SetPoint(point, relative, relativePoint, x, y)
            if type(relative) == "number" then
                x, y, relative, relativePoint = relative, relativePoint, self.parent, point
            end
            self.points[point] = {relative=relative or self.parent, anchor=relativePoint or point, x=x or 0, y=y or 0}
        end
        function methods:ClearAllPoints() self.points = {} end
        function methods:SetAllPoints() self:SetPoint("TOPLEFT"); self:SetPoint("BOTTOMRIGHT") end
        function methods:SetSize(w,h) self.width=w; self.height=h end
        function methods:SetWidth(w) self.width=w end
        function methods:SetHeight(h) self.height=h end
        function methods:GetWidth()
            local left = self.points.TOPLEFT or self.points.BOTTOMLEFT
            local right = self.points.TOPRIGHT or self.points.BOTTOMRIGHT
            if left and right and left.relative == right.relative then return left.relative:GetWidth()+right.x-left.x end
            return self.width or self:GetStringWidth()
        end
        function methods:GetStringWidth()
            local width = 0
            for char in (self.text or ""):gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                width = width + (#char > 1 and 1 or 0.55) * (self.fontSize or 12)
            end
            return width
        end
        function methods:SetText(text)
            assert(self.fontSize, "font must be set before text")
            assert(text ~= nil, "missing localization")
            self.text = tostring(text)
        end
        function methods:SetFont(font,size,flags) self.font=font; self.fontSize=size; self.fontFlags=flags end
        function methods:SetTextColor(...) self.textColor={...} end
        function methods:SetColorTexture(...) self.color={...} end
        function methods:SetVertexColor(...) self.vertexColor={...} end
        function methods:SetTexCoord(...) self.texCoord={...} end
        function methods:SetTexture(texture) self.texture=texture end
        function methods:SetBackdropColor(...) self.background={...} end
        function methods:SetBackdropBorderColor(...) self.border={...} end
        function methods:SetStatusBarColor(...) self.barColor={...} end
        function methods:SetValue(value) self.value=value end
        function methods:SetScale(scale) self.scale=scale end
        function methods:SetJustifyH(value) self.justify=value end
        function methods:SetHighlightTexture(texture) self.highlight=self:CreateTexture(); self.highlight:SetTexture(texture) end
        function methods:GetHighlightTexture() return self.highlight end
        function methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
        function methods:IsShown() return self.shown end
        function methods:Show() self.shown=true end
        function methods:Hide() self.shown=false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
        for _, name in ipairs({"RegisterEvent", "SetBackdrop", "SetFrameStrata", "SetClampedToScreen", "EnableMouse",
            "SetShadowOffset", "SetShadowColor", "SetJustifyV", "SetWordWrap", "RegisterForClicks",
            "SetStatusBarTexture", "SetMinMaxValues"}) do methods[name] = function() end end
        UIParent = CreateFrame("Frame")
        UIParent:SetSize(1920,1080)
        ReadyCheckFrame = CreateFrame("Frame", "ReadyCheckFrame", UIParent)
        ReadyCheckFrame:SetSize(300,100)
        clock = 10
        function GetTime() return clock end
        function InCombatLockdown() return inCombat or false end
        C_Timer = {After=function(_, callback) callback() end}
        DDingUI_StyleLib = {Font={path="font.ttf"}}
        ns = {DDingToolKit={RegisterModule=function() end}, L={}, db={profile={ReadyCheckAssistant={raidLoadouts="Raid"}}}}
        function LibStub() return {NewLocale=function() return ns.L end} end
    ''')
    lua.execute((ROOT / f"Locales/{locale}.lua").read_text(encoding="utf-8-sig"))
    lua.execute((ROOT / "UI/Themes.lua").read_text(encoding="utf-8-sig"),
                "DDingUI_Toolkit", lua.globals().ns)
    lua.execute((ROOT / "Modules/ReadyCheckAssistant/ReadyCheckAssistant.lua").read_text(encoding="utf-8-sig"),
                "DDingUI_Toolkit", lua.globals().ns)
    lua.execute('''
        module = ns.ReadyCheckAssistant
        function module:GetSpecializationInfo() return {id=262, name="Elemental"} end
        currentLoadout, loadoutKnown = "Dungeon", true
        function module:GetLoadoutInfo() return currentLoadout, loadoutKnown end
        function module:GetGroupContext() return "RAID" end
        durability = {lowest=18, average=64, threshold=25, lowSlots={{label="Chest", percent=18}, {label="Shoulder", percent=22}}}
        function module:GetDurabilityInfo() return durability end
        module:OnEnable()
        display = module.frame
    ''')
    return lua


def test_ready_check_layout_and_status_transitions():
    for locale in ("koKR", "enUS"):
        lua = panel_runtime(locale)
        lua.execute('''
            local L = ns.L
            for label in pairs(display.fontSizes) do assert(label.text ~= "", "missing panel label") end
            assert(display.width == 440 and display.height == 400)
            assert(module.snapshot.issueCount == 2)
            assert(display.statusText.text == string.format(L.RCA_SUMMARY_ISSUES_FORMAT, 2))
            assert(display.statusDetail.text:find(L.RCA_SUMMARY_MISMATCH, 1, true))
            assert(display.statusDetail.text:find(L.RCA_REPAIR_NEEDED, 1, true))
            assert(display.loadoutText.text == "Dungeon" and display.expectedText.text == "Raid")
            assert(display.openTalentsButton.primary)
            assert(display.durabilityText.text == "18" and display.durabilityBar.value == 18)
            local report = module:BuildReport(module.snapshot)
            assert(report:find(string.format(L.RCA_REPORT_REPAIR, 2), 1, true))
            assert(report:find(string.format(L.RCA_REPORT_LOADOUT, "Raid"), 1, true))
            local anchors = {}
            for _, key in ipairs({"specText", "loadoutText", "expectedText", "durabilityText", "statusText"}) do
                anchors[key] = display[key].points.TOPLEFT
            end
            currentLoadout = "Raid"
            durability = {lowest=86, average=94, threshold=25, lowSlots={}}
            module:Refresh()
            assert(module.snapshot.issueCount == 0 and module.snapshot.status == "READY")
            assert(display.statusText.text == L.RCA_STATUS_READY)
            assert(display.loadoutStatus.text == L.RCA_CHECK_MATCH and not display.openTalentsButton.primary)
            assert(display.detailText.text == L.RCA_NO_LOW_SLOTS)
            for key, anchor in pairs(anchors) do assert(display[key].points.TOPLEFT == anchor) end
            loadoutKnown = false
            module:Refresh()
            assert(module.snapshot.status == "UNKNOWN" and module.snapshot.issueCount == 1)
            assert(display.loadoutStatus.text == L.RCA_CHECK_UNKNOWN)
            ns.db.profile.ReadyCheckAssistant.raidLoadouts = ""
            module:Refresh()
            assert(display.loadoutStatus.text == L.RCA_CHECK_UNKNOWN)
            loadoutKnown = true
            module:Refresh()
            assert(display.loadoutStatus.text == L.RCA_NOT_CONFIGURED)
            assert(display.expectedText.text == L.RCA_NOT_CONFIGURED and not display.loadoutStatusIcon.shown)
            assert(display.statusDetail.text:find(L.RCA_SUMMARY_UNSET, 1, true))

            for _, width in ipairs({320, 440, 560}) do
                module.db.width = width
                for _, talents in ipairs({true, false}) do
                    for _, reportShown in ipairs({true, false}) do
                        module.db.showOpenTalentsButton, module.db.showReportButton = talents, reportShown
                        module:ApplySettings()
                        assert(display.width == width)
                        assert(display.height == ((talents or reportShown) and 400 or 346))
                        assert(display.openTalentsButton.shown == talents and display.reportButton.shown == reportShown)
                        local buttonWidth = (talents and reportShown) and (width - 40) / 2 or width - 32
                        assert(display.openTalentsButton.width == buttonWidth and display.reportButton.width == buttonWidth)
                        assert(display.openTalentsButton.label:GetStringWidth() + 21 <= buttonWidth)
                        assert(display.reportButton.label:GetStringWidth() + 21 <= buttonWidth)
                        assert(display.openTalentsButton.points.BOTTOMLEFT.x == 16)
                        assert(display.reportButton.points.BOTTOMRIGHT.x == -16)
                        assert(display.durabilityBar:GetWidth() == width - 32)
                        assert(display.durabilityThresholdMarker.points.CENTER.x == math.floor((width - 32) * 0.25 + 0.5))
                    end
                end
            end
            DDingUI_StyleLib.Font.path = "new-font.ttf"
            module:OnMediaChanged()
            for label, size in pairs(display.fontSizes) do
                assert(label.font == "new-font.ttf" and label.fontSize == size and label.fontFlags == "")
            end
            module:EnterEditPreview()
            assert(display.shown)
            display.closeButton.scripts.OnClick()
            assert(not display.shown and ReadyCheckFrame.shown)
            assert(next(ReadyCheckFrame.points) == nil and next(ReadyCheckFrame.scripts) == nil)
            module:HandleReadyCheck()
            assert(display.shown)
            ReadyCheckFrame:Hide()
            clock = clock + 1
            display.scripts.OnUpdate()
            assert(not display.shown)
            inCombat = true
            assert(not module:Show(false))
            module:OnDisable()
            assert(not module:Show(false))
        ''')


def test_ready_check_icon_atlas_has_seven_transparent_icons():
    from PIL import Image

    with Image.open(ROOT / "Media/ReadyCheckIcons.tga") as atlas:
        assert atlas.size == (512, 64) and atlas.mode == "RGBA"
        for index in range(7):
            alpha = atlas.getchannel("A").crop((index * 64, 0, (index + 1) * 64, 64))
            assert alpha.getextrema() == (0, 255)
            left, top, right, bottom = alpha.getbbox()
            assert left > 0 and top > 0 and right < 64 and bottom < 64
        assert not atlas.getchannel("A").crop((448, 0, 512, 64)).getbbox()


def test_ready_check_panel_has_an_independent_close_button() -> None:
    module = (Path(__file__).parents[1] / "Modules/ReadyCheckAssistant/ReadyCheckAssistant.lua").read_text(
        encoding="utf-8-sig"
    )

    assert 'frame.closeButton = CreateFrame("Button", nil, frame)' in module
    close_handler = module.split('frame.closeButton:SetScript("OnClick", function()', 1)[1].split("end)", 1)[0]
    assert "ReadyCheckAssistant:Hide()" in close_handler


def test_durability_gauge_has_notches_and_configured_threshold_marker() -> None:
    module = (Path(__file__).parents[1] / "Modules/ReadyCheckAssistant/ReadyCheckAssistant.lua").read_text(
        encoding="utf-8-sig"
    )

    assert "frame.durabilityTicks = {}" in module
    assert "frame.durabilityThresholdMarker" in module
    scale = module.split("local function PositionDurabilityScale", 1)[1].split(
        "function ReadyCheckAssistant:Refresh", 1
    )[0]
    assert "width * index / 10" in scale
    assert "durability and durability.threshold" in scale
    assert "PositionDurabilityScale(durability)" in module

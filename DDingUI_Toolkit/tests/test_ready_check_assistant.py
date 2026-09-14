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
        function module:GetConsumables()
            return {flask={value=true,remaining=2700}, food={value=true,remaining=1680},
                rune={value=true,remaining=3120}, weapon={value=true,remaining=3240}}
        end
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
            assert(display.width == 720 and display.height == 340)
            assert(module.snapshot.issueCount == 2)
            assert(display.statusText.text == string.format(L.RCA_SUMMARY_ISSUES_FORMAT, 2))
            assert(display.statusDetail.text:find(L.RCA_SUMMARY_MISMATCH, 1, true))
            assert(display.statusDetail.text:find(L.RCA_REPAIR_NEEDED, 1, true))
            assert(display.loadoutText.text == "Dungeon" and display.expectedText.text == L.RCA_EXPECTED .. ": Raid")
            assert(display.openTalentsButton.primary)
            assert(display.cells[5].value.text:find("18%",1,true))
            assert(#display.cells == 5 and not display.durabilityBar)
            local report = module:BuildReport(module.snapshot)
            assert(report:find(string.format(L.RCA_REPORT_REPAIR, 2), 1, true))
            assert(report:find(string.format(L.RCA_REPORT_LOADOUT, "Raid"), 1, true))
            local anchors = {}
            for _, key in ipairs({"specText", "loadoutText", "expectedText", "statusText"}) do
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
            assert(display.expectedText.text == L.RCA_EXPECTED .. ": " .. L.RCA_NOT_CONFIGURED and not display.loadoutStatusIcon.shown)
            assert(display.statusDetail.text:find(L.RCA_SUMMARY_UNSET, 1, true))

            for _, width in ipairs({560, 720, 900}) do
                module.db.width = width
                for _, talents in ipairs({true, false}) do
                    for _, reportShown in ipairs({true, false}) do
                        module.db.showOpenTalentsButton, module.db.showReportButton = talents, reportShown
                        module:ApplySettings()
                        assert(display.width == width)
                        assert(display.height == ((talents or reportShown) and 340 or 286))
                        assert(display.openTalentsButton.shown == talents and display.reportButton.shown == reportShown)
                        local buttonWidth = (talents and reportShown) and (width - 40) / 2 or width - 32
                        assert(display.openTalentsButton.width == buttonWidth and display.reportButton.width == buttonWidth)
                        assert(display.openTalentsButton.label:GetStringWidth() + 21 <= buttonWidth)
                        assert(display.reportButton.label:GetStringWidth() + 21 <= buttonWidth)
                        assert(display.openTalentsButton.points.BOTTOMLEFT.x == 16)
                        assert(display.reportButton.points.BOTTOMRIGHT.x == -16)
                        for index, cell in ipairs(display.cells) do
                            assert(cell.width == (width-32)/5)
                            assert(cell.points.TOPLEFT.x == 16+(index-1)*cell.width)
                            assert(cell.label:GetStringWidth() <= cell.width-8)
                            assert(cell.value:GetStringWidth() <= cell.width-8)
                            assert(cell.points.TOPLEFT.y == -178)
                        end
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


def test_ready_check_icon_atlas_has_twelve_transparent_icons():
    from PIL import Image

    with Image.open(ROOT / "Media/ReadyCheckIcons.tga") as atlas:
        assert atlas.size == (1024, 64) and atlas.mode == "RGBA"
        for index in range(12):
            alpha = atlas.getchannel("A").crop((index * 64, 0, (index + 1) * 64, 64))
            assert alpha.getextrema() == (0, 255)
            left, top, right, bottom = alpha.getbbox()
            assert left > 0 and top > 0 and right < 64 and bottom < 64
        assert not atlas.getchannel("A").crop((768, 0, 1024, 64)).getbbox()


def test_ready_check_panel_has_an_independent_close_button() -> None:
    module = (Path(__file__).parents[1] / "Modules/ReadyCheckAssistant/ReadyCheckAssistant.lua").read_text(
        encoding="utf-8-sig"
    )

    assert 'frame.closeButton = CreateFrame("Button", nil, frame)' in module
    close_handler = module.split('frame.closeButton:SetScript("OnClick", function()', 1)[1].split("end)", 1)[0]
    assert "ReadyCheckAssistant:Hide()" in close_handler


def test_personal_consumables_use_shared_scan_without_enabling_raid_module():
    lua = panel_runtime()
    # Restore the real collector, then load the shared scanner with no OnEnable.
    lua.execute((ROOT / "Modules/ReadyCheckAssistant/ReadyCheckAssistant.lua").read_text(encoding="utf-8-sig"),
                "DDingUI_Toolkit", lua.globals().ns)
    lua.execute("UISpecialFrames, SlashCmdList = {}, {}; function LibStub() return nil end")
    lua.execute((ROOT / "Modules/RaidPreparation/RaidPreparation.lua").read_text(encoding="utf-8-sig"),
                "DDingUI_Toolkit", lua.globals().ns)
    lua.execute('''
        local personal = ns.ReadyCheckAssistant
        local function clone(t) local n={} for k,v in pairs(t) do n[k]=v end return n end
        function CopyTable(t) return clone(t) end
        function UnitExists() return true end
        function UnitIsConnected() return true end
        local secret = {}
        function issecretvalue(v) return v == secret end
        local auras = {
            {spellId=1236763,icon=111,expirationTime=clock+2700},
            {spellId=308488,icon=222,expirationTime=clock+1680},
            {spellId=1234969,icon=333,expirationTime=clock+3120},
        }
        C_UnitAuras={GetAuraDataByIndex=function(_,i) return auras[i] end}
        C_Secrets={ShouldAurasBeSecret=function() return false end}
        function GetWeaponEnchantInfo() return true,3240000,0,1,false end
        local data=personal:GetConsumables()
        assert(data.flask.value==true and data.flask.remaining==2700 and data.flask.icon==111)
        assert(data.food.value==true and data.rune.value==true)
        assert(data.weapon.remaining==3240 and data.weapon.value==true)
        assert(not ns.RaidPreparation.frame and not ns.RaidPreparation.enabled)
        auras={}
        data=personal:GetConsumables()
        assert(data.flask.value==false and data.food.value==false and data.rune.value==false)
        auras={{spellId=secret,icon=secret,expirationTime=secret}}
        data=personal:GetConsumables()
        assert(data.flask.value==nil and data.food.value==nil and data.rune.value==nil)
        auras={secret}
        assert(personal:GetConsumables().flask.value==nil)
        C_UnitAuras.GetAuraDataByIndex=function() error("unavailable") end
        assert(personal:GetConsumables().flask.value==nil)
        C_Secrets.ShouldAurasBeSecret=function() return true end
        assert(personal:GetConsumables().flask.value==nil)
        C_Secrets.ShouldAurasBeSecret=function() return secret end
        assert(personal:GetConsumables().flask.value==nil)
        function GetWeaponEnchantInfo() return secret,secret,0,0,secret end
        assert(personal:GetConsumables().weapon.value==nil)
        C_Secrets.ShouldAurasBeSecret=function() return false end
        C_UnitAuras.GetAuraDataByIndex=function(_,i)
            if i==1 then return {spellId=1236763,expirationTime=clock-1} end
        end
        assert(personal:GetConsumables().flask.value=="LOW")
    ''')


def test_personal_consumable_status_and_reports():
    lua = panel_runtime()
    lua.execute('''
        currentLoadout="Raid"
        durability={lowest=96,average=98,threshold=25,lowSlots={}}
        local buffs={flask={value=false},food={value=true,remaining=1680},
            rune={},weapon={value=true,remaining=32}}
        function module:GetConsumables() return buffs end
        module:Refresh()
        assert(module.snapshot.issueCount==2)
        assert(display.cells[1].value.text==ns.L.RCA_MISSING)
        assert(display.cells[2].value.text==string.format(ns.L.RCA_MINUTES_LEFT,28))
        assert(display.cells[3].value.text==ns.L.RCA_CHECK_UNKNOWN)
        assert(display.cells[4].value.text==string.format(ns.L.RCA_SECONDS_LEFT,32))
        local atlas = display.cells[5].icon.texture
        for index=1,4 do
            local cell=display.cells[index]
            assert(cell.icon.texture==atlas)
            assert(cell.icon.texCoord[1]==(index+6)/16)
            for channel=1,3 do assert(cell.icon.vertexColor[channel]==cell.value.textColor[channel]) end
        end
        assert(display.specIcon.texture==atlas and display.specIcon.texCoord[1]==11/16)
        local report=module:BuildReport(module.snapshot)
        assert(report:find(ns.L.RAIDPREP_COLUMN_FLASK,1,true))
        assert(report:find(ns.L.RCA_CHECK_UNKNOWN,1,true))
        buffs.flask={value=true};buffs.rune={value=true}
        local flaskUV=display.cells[1].icon.texCoord[1]
        module:Refresh()
        assert(module.snapshot.issueCount==0 and module.snapshot.status=="READY")
        assert(display.cells[1].value.text==ns.L.RCA_ACTIVE)
        assert(display.cells[1].icon.texCoord[1]==flaskUV)
        assert(display.cells[1].icon.vertexColor[2]==display.cells[1].value.textColor[2])
    ''')

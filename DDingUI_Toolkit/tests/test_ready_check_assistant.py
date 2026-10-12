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
        function methods:GetEffectiveScale() return (self.scale or 1) * (self.parent and self.parent:GetEffectiveScale() or 1) end
        function methods:SetJustifyH(value) self.justify=value end
        function methods:SetHighlightTexture(texture) self.highlight=self:CreateTexture(); self.highlight:SetTexture(texture) end
        function methods:GetHighlightTexture() return self.highlight end
        function methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
        function methods:IsShown() return self.shown end
        function methods:Show() self.shown=true end
        function methods:Hide() self.shown=false; if self.scripts.OnHide then self.scripts.OnHide(self) end end
        for _, name in ipairs({"RegisterEvent", "SetBackdrop", "SetFrameStrata", "SetClampedToScreen",
            "SetShadowOffset", "SetShadowColor", "SetJustifyV", "SetWordWrap",
            "SetStatusBarTexture", "SetMinMaxValues"}) do methods[name] = function() end end
        function methods:EnableMouse(value) self.mouse=value end
        function methods:RegisterForClicks(...) self.clicks={...} end
        function methods:SetFrameLevel(level) self.level=level end
        function methods:GetFrameLevel() return self.level or 1 end
        function methods:SetAlpha(alpha) self.alpha=alpha end
        function methods:GetAlpha() return self.alpha or 1 end
        function methods:SetMask(mask) self.mask=mask end
        function methods:GetText() return self.text end
        function methods:GetParent() return self.parent end
        UIParent = CreateFrame("Frame")
        UIParent:SetSize(1920,1080)
        ReadyCheckFrame = CreateFrame("Frame", "ReadyCheckFrame", UIParent)
        ReadyCheckFrame:SetSize(323,100)
        clock = 10
        function GetTime() return clock end
        function InCombatLockdown() return inCombat or false end
        C_Timer = {After=function(_, callback) callback() end}
        DDingUI_StyleLib = {Font={path="font.ttf"}}
        ns = {DDingToolKit={RegisterModule=function() end}, L={}, db={profile={ReadyCheckAssistant={raidLoadouts="Raid"}}}}
        -- Core/Core.lua shared chat helpers
        ns.CHAT_PREFIX = "DDingUI Toolkit: "
        function ns.Print(msg, ...) print(ns.CHAT_PREFIX .. tostring(msg), ...) end
        function ns.PrintError(msg, ...) ns.Print(msg, ...) end
        function LibStub() return {NewLocale=function() return ns.L end} end
    ''')
    lua.execute((ROOT / f"Locales/{locale}.lua").read_text(encoding="utf-8-sig"))
    lua.execute((ROOT / "UI/Themes.lua").read_text(encoding="utf-8-sig"),
                "DDingUI_Toolkit", lua.globals().ns)
    lua.execute((ROOT / "UI/ReadyStatus.lua").read_text(encoding="utf-8-sig"),
                "DDingUI_Toolkit", lua.globals().ns)
    lua.execute((ROOT / "Modules/ReadyCheckAssistant/ReadyCheckAssistant.lua").read_text(encoding="utf-8-sig"),
                "DDingUI_Toolkit", lua.globals().ns)
    lua.execute('''
        module = ns.ReadyCheckAssistant
        function module:GetSpecializationInfo() return {id=262, name="Elemental", icon=136048} end
        currentLoadout, loadoutKnown = "Dungeon", true
        function module:GetLoadoutInfo() return currentLoadout, loadoutKnown end
        function module:GetGroupContext() return "RAID" end
        durability = {lowest=18, average=64, threshold=25, lowSlots={{label="Chest", percent=18}, {label="Shoulder", percent=22}}}
        function module:GetDurabilityInfo() return durability end
        function module:GetConsumables()
            return {flask={value=true,remaining=2700}, food={value=true,remaining=1680},
                rune={value=true,remaining=3120}, vantus={value=true}, weapon={value=true,remaining=3240}}
        end
        module:OnEnable()
        display = module.frame
    ''')
    return lua


PANEL_CHECKS = r'''
    function descendants(root)
        local out = {}
        for _, r in ipairs(regions) do
            local p = r.parent
            while p do if p == root then out[#out+1] = r; break end; p = p.parent end
        end
        return out
    end
    function states(display)
        local out = {}
        for i, row in ipairs(display.rows) do out[i] = row.state or "none" end
        return table.concat(out, ",")
    end
'''


def test_ready_check_compact_checklist_layout():
    for locale in ("koKR", "enUS"):
        lua = panel_runtime(locale)
        lua.execute(PANEL_CHECKS)
        lua.execute('''
            local L = ns.L
            local styles = ns.ReadyStatus
            -- Popup width, seven rows with a 14px optional group separator.
            assert(display.width == 323 and display.height == 260, display.width .. "x" .. display.height)
            assert(#display.rows == 7)
            for i, row in ipairs(display.rows) do
                assert(row.height == 26 and row.width == 299)
                assert(row.points.TOPLEFT.y == -(54 + (i - 1) * 26 + (i > 5 and 14 or 0)))
                assert(row.cell.width == styles.PERSONAL_ICON and row.cell.height == 24)
            end
            assert(display.openTalentsButton == nil and display.reportButton == nil)
            for _, r in ipairs(descendants(display)) do
                if r.kind == "FontString" then
                    assert(r.fontSize >= 12, "text below 12pt: " .. tostring(r.text))
                    assert(r.text ~= L.RCA_OPEN_TALENTS and r.text ~= L.RCA_REPORT_BUTTON, "button text left in panel")
                end
            end
            -- talents, flask, food, weapon, durability | augment, Vantus
            assert(display.rows[1].label.text == string.format(L.RCA_TALENT_ROW, "Raid"))
            assert(display.rows[2].label.text == L.RAIDPREP_COLUMN_FLASK)
            assert(display.rows[3].label.text == L.RAIDPREP_COLUMN_FOOD)
            assert(display.rows[4].label.text == L.RAIDPREP_COLUMN_WEAPON)
            assert(display.rows[5].label.text == L.RAIDPREP_COLUMN_DURABILITY)
            assert(display.rows[6].label.text == L.RCA_ROW_RUNE)
            assert(display.rows[7].label.text == L.RCA_ROW_VANTUS)
            -- loadout "Dungeon" vs expected "Raid", durability 18% below 25%
            assert(module.snapshot.issueCount == 2)
            assert(display.summaryPill.text.text == string.format(L.RCA_SUMMARY_ISSUES_FORMAT, 2))
            assert(display.summaryPill.state == "warn")
            assert(display.contextPill.text.text == L.RCA_CONTEXT_RAID)
            for _, context in ipairs({"RAID", "MPLUS", "PARTY"}) do
                display.summaryPill:SetPill(string.format(L.RCA_SUMMARY_ISSUES_FORMAT, 6), "warn")
                display.contextPill:SetPill(L["RCA_CONTEXT_" .. context])
                assert(display.summaryPill.width + 8 + display.contextPill.width <= 299, context)
            end
            for _, row in ipairs(display.rows) do
                assert(row.status:GetStringWidth() + 24 + 10 + 8 <= 299)
            end
            assert(display.rows[1].status.text == L.RCA_CHECK_MISMATCH)
            assert(display.rows[5].status.text == L.RCA_LOWEST .. " 18%")
            assert(states(display) == "bad,ok,ok,ok,bad,ok,ok", states(display))
            assert(display.rows[1].card.shown and display.rows[5].card.shown and not display.rows[2].card.shown)
            local bad = styles.Color("bad")
            assert(display.rows[1].status.textColor[1] == bad[1] and display.rows[1].cell.icon.mask)
            assert(display.rows[1].cell.icon.texture == 136048, "spec icon")
            -- Toolkit's own icons (full-bleed, no 8% crop) for flask and durability
            assert(display.rows[2].cell.icon.texture:find("ready_flask", 1, true))
            assert(display.rows[5].cell.icon.texture:find("ready_durability", 1, true))
            assert(display.rows[2].cell.icon.texCoord[1] == 0 and display.rows[2].cell.icon.texCoord[2] == 1)

            currentLoadout = "Raid"
            durability = {lowest=86, average=94, threshold=25, lowSlots={}}
            module:Refresh()
            assert(module.snapshot.issueCount == 0 and module.snapshot.status == "READY")
            assert(display.summaryPill.text.text == L.RCA_NO_ISSUES and display.summaryPill.state == "ok")
            assert(display.rows[1].status.text == L.RCA_STATUS_MATCH)
            assert(states(display) == "ok,ok,ok,ok,ok,ok,ok")
            for _, row in ipairs(display.rows) do assert(not row.card.shown) end
            loadoutKnown = false
            module:Refresh()
            assert(display.rows[1].status.text == L.RCA_CHECK_UNKNOWN and display.rows[1].state == "warn")
            loadoutKnown = true
            ns.db.profile.ReadyCheckAssistant.raidLoadouts = ""
            module:Refresh()
            assert(display.rows[1].status.text == L.RCA_NOT_CONFIGURED and display.rows[1].state == nil)
            assert(display.rows[1].label.text == string.format(L.RCA_TALENT_ROW, "Raid"), "unset: current loadout name")

            -- old width option no longer changes the panel
            module.db.width = 900
            module:ApplySettings()
            assert(display.width == 323 and display.height == 260)
            DDingUI_StyleLib.Font.path = "new-font.ttf"
            module:OnMediaChanged()
            for label, size in pairs(display.fontSizes) do
                assert(label.font == "new-font.ttf" and label.fontSize == size and size >= 12)
            end
        ''')


def test_talent_row_opens_talents_and_close_button_hides():
    lua = panel_runtime()
    lua.execute('''
        opened = {}
        PlayerSpellsUtil = {TogglePlayerSpellsFrame=function(tab) opened[#opened+1]=tab end}
        local row = display.talentRow
        assert(row == display.rows[1] and row.clicks)
        row.scripts.OnClick(row, "LeftButton")
        assert(#opened == 1 and opened[1] == 2)
        inCombat = true
        row.scripts.OnClick(row, "LeftButton")
        assert(#opened == 1, "talent window must not open in combat")
        inCombat = false
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


def test_panel_uses_series_title_bar_and_report_lives_in_options():
    module = (ROOT / "Modules/ReadyCheckAssistant/ReadyCheckAssistant.lua").read_text(encoding="utf-8-sig")
    config = (ROOT / "Config_Data.lua").read_text(encoding="utf-8-sig")
    assert 'SL.CreateTitleBar(frame, "MJToolkit", title' in module
    assert "bar.closeBtn:SetScript(\"OnClick\", Close)" in module
    assert "openTalentsButton" not in module and "CreatePanelButton" not in module
    rca = config.split('tree.panels["readycheckassistant"]', 1)[1].split("tree.panels[", 1)[0]
    for removed in ("showOpenTalentsButton", "showReportButton", "showLowSlots", "ReadyCheckAssistant.width"):
        assert removed not in rca, removed
    assert 'label = L["RCA_REPORT_BUTTON"]' in rca and "mod:SendReport(false)" in rca


def test_personal_consumable_status_and_reports():
    lua = panel_runtime()
    lua.execute(PANEL_CHECKS)
    lua.execute('''
        currentLoadout="Raid"
        durability={lowest=96,average=98,threshold=25,lowSlots={}}
        local buffs={flask={value=false},food={value=true,remaining=1680,icon=999},
            rune={},weapon={value=true,remaining=32}}
        function module:GetConsumables() return buffs end
        module:Refresh()
        assert(module.snapshot.issueCount==1)
        assert(display.rows[2].status.text==ns.L.RCA_MISSING and display.rows[2].state=="bad")
        assert(display.rows[3].status.text==string.format(ns.L.RCA_MINUTES_LEFT,28) and display.rows[3].state=="ok")
        assert(display.rows[3].cell.icon.texture==999, "live aura icon wins")
        assert(display.rows[6].status.text==ns.L.RCA_CHECK_UNKNOWN and display.rows[6].state==nil)
        assert(display.rows[4].status.text==string.format(ns.L.RCA_SECONDS_LEFT,32) and display.rows[4].state=="warn")
        assert(display.rows[2].card.shown and display.rows[4].card.shown and not display.rows[6].card.shown)
        local report=module:BuildReport(module.snapshot)
        assert(report:find(ns.L.RAIDPREP_COLUMN_FLASK,1,true))
        assert(not report:find(ns.L.RAIDPREP_COLUMN_RUNE,1,true))
        buffs.flask={value=true};buffs.rune={value=true}
        module:Refresh()
        assert(module.snapshot.issueCount==0 and module.snapshot.status=="READY")
        assert(display.rows[2].status.text==ns.L.RCA_ACTIVE and display.rows[2].state=="ok")
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


def test_optional_rows_do_not_count_and_follow_popup_width():
    for locale in ("koKR", "enUS"):
        lua = panel_runtime(locale)
        lua.execute('''
            currentLoadout="Raid"
            durability={lowest=96,average=98,threshold=25,lowSlots={}}
            local buffs={flask={value=true},food={value=true},weapon={value=true},rune={},vantus={}}
            function module:GetConsumables() return buffs end
            for _, value in ipairs({false, "LOW", true}) do
                buffs.rune={value=value,remaining=value=="LOW" and 32 or nil}
                buffs.vantus={value=value}
                module:Refresh()
                assert(module.snapshot.status=="READY" and module.snapshot.issueCount==0)
                assert(display.summaryPill.state=="ok")
                for i=6,7 do
                    local row=display.rows[i]
                    assert(row.state==(value==true and "ok" or nil) and not row.card.shown)
                    if value~=true then
                        assert(row.status.textColor[1]==ns.ReadyStatus.Token("text","dim")[1])
                        assert(not row.cell.wellTint.shown)
                    end
                end
                local report=module:BuildReport(module.snapshot)
                assert(not report:find(ns.L.RAIDPREP_COLUMN_RUNE,1,true))
                assert(not report:find(ns.L.RCA_ROW_VANTUS,1,true))
            end
            module.db.showOptional=false; module:ApplySettings()
            assert(display.height==194 and not display.optionalHeader.shown)
            assert(not display.rows[6].shown and not display.rows[7].shown)
            ReadyCheckFrame:SetWidth(400)
            ReadyCheckFrame:SetScale(.9); module.db.scale=1.25
            module.db.showOptional=true; module:ApplySettings()
            assert(math.abs(display.width*display:GetEffectiveScale()-ReadyCheckFrame:GetWidth()*ReadyCheckFrame:GetEffectiveScale())<.001)
            assert(display.rows[7].width==display.width-24 and display.rows[7].shown)
            module.db.scale=1; ReadyCheckFrame:SetScale(1)
            buffs.flask={value=false}; buffs.food={value=false}; buffs.weapon={value=false}
            for _,scale in ipairs({.6,1,1.4,1.8}) do
                module.db.scale=scale; module:ApplySettings()
                assert(math.abs(display.width*display:GetEffectiveScale()-400)<.001)
                if display.contextPill.shown then
                    assert(display.summaryPill.width+display.contextPill.width+8<=display.width-24)
                end
            end
            module.db.scale=1
            for _, width in ipairs({50,900}) do
                ReadyCheckFrame:SetWidth(width); module:ApplySettings(); assert(display.width==323)
            end
            local secret={}; function issecretvalue(value) return rawequal(value,secret) end
            local getWidth=ReadyCheckFrame.GetWidth
            ReadyCheckFrame.GetWidth=function() return secret end
            module:ApplySettings(); assert(display.width==323)
            ReadyCheckFrame.GetWidth=getWidth; ReadyCheckFrame:SetWidth(323)
            inCombat=true; module.db.showOptional=false; module:ApplySettings()
            assert(module.settingsPending and display.height==260)
            inCombat=false
            for _, region in ipairs(regions) do
                if region.scripts.OnEvent then region.scripts.OnEvent(region,"PLAYER_REGEN_ENABLED") end
            end
            assert(not module.settingsPending and display.height==194)
        ''')

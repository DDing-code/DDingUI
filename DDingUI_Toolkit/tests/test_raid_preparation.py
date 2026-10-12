from pathlib import Path

from test_ready_check_assistant import panel_runtime

ROOT = Path(__file__).parents[1]


def raid_runtime(locale="koKR"):
    lua = panel_runtime(locale)
    lua.execute('''
        local methods = getmetatable(UIParent).__index
        for _, name in ipairs({"SetMovable", "RegisterForDrag"}) do methods[name]=function() end end
        function methods:GetScript(name) return self.scripts[name] end
        function methods:GetName() return self.name end
        UISpecialFrames, SlashCmdList = {}, {}
        timers = {}
        C_Timer.After = function(delay, fn) timers[#timers+1]={delay=delay,fn=fn} end
        function LibStub() return nil end
        RAID_CLASS_COLORS={PRIEST={r=1,g=1,b=1},MAGE={r=0.25,g=0.78,b=0.92}}
        GameTooltip = {shown=false, lines={}}
        function GameTooltip:SetOwner(owner) self.owner=owner; self.lines={} end
        function GameTooltip:GetOwner() return self.owner end
        function GameTooltip:AddLine(text,r,g,b,wrap)
            assert(wrap==nil or type(wrap)=="boolean")
            self.lines[#self.lines+1]={text=text,r=r,g=g,b=b}
        end
        function GameTooltip:Show() self.shown=true end
        function GameTooltip:Hide() self.shown=false end
        function GameTooltip:IsShown() return self.shown end
        printed = {}
        ns.Print = function(msg) printed[#printed+1]=msg end
        ns.PrintError = function(msg) printed[#printed+1]="ERR "..msg end
    ''')
    lua.execute((ROOT / "Modules/RaidPreparation/RaidPreparation.lua").read_text(encoding="utf-8-sig"),
                "DDingUI_Toolkit", lua.globals().ns)
    lua.execute('''
        module = ns.RaidPreparation
        function module:RegisterLibDurability() end
        function module:UnregisterLibDurability() end
        function module:UpdateDynamicRoster() end
        function module:ApplyRaidBuffStatus() end
        function module:AnnounceReadyCheckStatus() end
        function module:CollectRoster() return self.roster end
        function module:CanOpenAutomatically() return true end
        module:OnEnable()
        module.roster = {}
        for i=1,20 do
            module.roster[i]={name="Player"..i.."-Realm",classToken="PRIEST",subgroup=1,
                ready=true,food=true,flask=true,rune=true,vantus=true,raidBuff=true,weapon=true,durability=100}
        end
        module:ShowWindow(false,true)
        display = module.frame
        function descendants(root)
            local out = {}
            for _, r in ipairs(regions) do
                local p = r.parent
                while p do if p == root then out[#out+1] = r; break end; p = p.parent end
            end
            return out
        end
        function badges()
            local out = {}
            for i, cell in ipairs(display.icons) do
                out[i] = cell.badge.shown and (cell.badgeCount .. cell.badgeState) or (cell.state or "-")
            end
            return table.concat(out, ",")
        end
    ''')
    return lua


def test_strip_layout_and_auto_close_lifecycle():
    for locale in ("koKR", "enUS"):
        lua = raid_runtime(locale)
        lua.execute('''
            local L, styles = ns.L, ns.ReadyStatus
            assert(display.width==412 and display.height==92)
            assert(display.rows==nil and display.scrollTrack==nil and display.declinedNames==nil)
            assert(#display.icons==7 and #display.gauge.segments==10)
            for i, cell in ipairs(display.icons) do
                assert(cell.width==32 and cell.height==32 and cell.badge.width>=16 and cell.badge.height==16)
                assert(cell.points.TOPLEFT.x==12+(i-1)*40+(i>5 and 9 or 0) and cell.points.TOPLEFT.y==-46)
                assert(cell.icon.texture==module.Items[i].icon)
            end
            for _, r in ipairs(descendants(display)) do
                if r.kind=="FontString" then assert(r.fontSize>=12, "text below 12pt: "..tostring(r.text)) end
            end
            assert(display.count.fontSize==22 and display.closeButton.width==18 and display.closeButton.label.text=="X")
            assert(display.reportButton.label.text==L.RAIDPREP_REPORT_SHORT and display.refreshButton.label.text==L.RAIDPREP_REFRESH_SHORT)
            -- headline and replies fit beside each other above the gauge; the buttons fit the row
            for _, key in ipairs({"RAIDPREP_COMPLETE", "RAIDPREP_INCOMPLETE", "RAIDPREP_NO_GROUP"}) do
                display.headline:SetText(L[key]); display.replies:SetText(string.format(L.RAIDPREP_REPLIES, 40))
                assert(display.headline:GetStringWidth()+6+display.replies:GetStringWidth()<=display.gauge.width, key)
            end
            assert(display.gauge.points.TOPLEFT.x+display.gauge.width+8+display.reportButton.width+4
                +display.refreshButton.width+4+18+8<=412)
            display.hint:SetText(L.RAIDPREP_ICON_HINT)
            for line in display.hint.text:gmatch("[^\\n]+") do
                local probe=display:CreateFontString(); probe:SetFont("f",12); probe:SetText(line)
                assert(probe:GetStringWidth()<=display.hint.width, line)
            end
            module:Refresh()
            -- all ready: green number, ok borders, no badges, full gauge
            assert(module.fullyReady and display.closeElapsed==0)
            assert(display.count.text=="20" and display.total.text=="/20")
            assert(display.count.textColor[2]==styles.Color("ok")[2])
            assert(display.headline.text==L.RAIDPREP_COMPLETE)
            assert(badges()=="ok,ok,ok,ok,ok,ok,ok", badges())
            for _, segment in ipairs(display.gauge.segments) do assert(segment.color[2]==styles.Color("ok")[2]) end
            display.scripts.OnUpdate(display,1.6)
            assert(display.shown and display.alpha<1 and display.alpha>0)
            -- one player without food: warn number, red badge 1 on food
            module.roster[1].food=false
            module:Refresh()
            assert(not module.fullyReady and display.closeElapsed==nil and display.alpha==1)
            assert(display.headline.text==L.RAIDPREP_INCOMPLETE)
            assert(display.count.textColor[1]==styles.Color("warn")[1])
            assert(badges()=="1bad,ok,ok,ok,ok,ok,ok", badges())
            -- readiness gauge: 16 of 20 ready -> 8 of 10 segments
            for i=1,4 do module.roster[i].ready=nil end
            module.roster[5].ready=false
            module:Refresh()
            local filled=0
            for _, segment in ipairs(display.gauge.segments) do
                if segment.color[2]==styles.Color("ok")[2] then filled=filled+1 end
            end
            assert(filled==7 and display.count.text=="15", filled)
            assert(display.replies.text==string.format(L.RAIDPREP_REPLIES,16))
            for i=1,5 do module.roster[i].ready=true end
            module.roster[1].food=true
            module:Refresh()
            assert(module.fullyReady)
            display.scripts.OnUpdate(display,1.8)
            assert(not display.shown and display.alpha==1)
            module:ShowWindow(false)
            display.scripts.OnUpdate(display,10)
            assert(display.shown and display.closeElapsed==nil)
            module.db.closeAfterReadyCheck=true
            module:HandleReadyFinished()
            timers[#timers].fn()
            assert(display.shown)
            module:HandleReadyCheck("Player1")
            assert(module.ready.player1==true and display.autoOpened)
            local driver
            for _,r in ipairs(regions) do if r.scripts.OnEvent and r~=ReadyCheckFrame then driver=r end end
            driver.scripts.OnEvent(driver,"PLAYER_REGEN_DISABLED")
            assert(not display.shown)
            inCombat=true
            module:ShowWindow(false,true)
            assert(not display.shown)
            inCombat=false
            module.roster={}
            module:ShowWindow(false,true)
            assert(not module.fullyReady and display.closeElapsed==nil and display.count.text=="0")
            assert(display.headline.text==L.RAIDPREP_NO_GROUP)
            display.closeButton.scripts.OnClick()
            assert(not display.shown)
            module:ShowWindow(false)
            module:OnDisable()
            assert(not display.shown)
        ''')


def test_badges_and_tooltips_list_missing_players():
    for locale in ("koKR", "enUS"):
        lua = raid_runtime(locale)
        lua.execute('''
            local L, styles = ns.L, ns.ReadyStatus
            module.roster[2].flask=false
            module.roster[3].flask="LOW"
            module.roster[3].classToken="MAGE"
            module.roster[4].rune=nil
            module.roster[5].durability=12
            module.roster[6].weapon=false
            module.roster[7].weapon=false
            module:Refresh()
            -- food ok, flask 2 (one missing -> red), rune unknown only (no border), raid buff ok,
            -- weapon 2 red, durability 1 warn (yellow)
            assert(badges()=="ok,2bad,ok,2bad,1warn,-,ok", badges())
            local flask=display.icons[2]
            assert(flask.badge.fill.color[1]==styles.Color("bad")[1])
            assert(display.icons[5].badge.fill.color[1]==styles.Color("warn")[1])
            flask.scripts.OnEnter(flask)
            assert(GameTooltip.shown and GameTooltip.owner==flask)
            assert(GameTooltip.lines[1].text==L.RAIDPREP_COLUMN_FLASK)
            assert(GameTooltip.lines[2].text=="Player2" and GameTooltip.lines[2].g==1)
            assert(GameTooltip.lines[3].text=="Player3  "..L.RAIDPREP_LOW and GameTooltip.lines[3].g==0.78)
            assert(#GameTooltip.lines==3)
            local rune=display.icons[6]
            rune.scripts.OnEnter(rune)
            assert(GameTooltip.lines[2].text==L.RAIDPREP_UNKNOWN_GROUP..": Player4")
            local durability=display.icons[5]
            durability.scripts.OnEnter(durability)
            assert(GameTooltip.lines[2].text=="Player5  12%")
            -- hovered tooltip follows updates
            module.roster[5].durability=100
            module:Refresh()
            assert(GameTooltip.shown and GameTooltip.lines[2].text==L.RAIDPREP_ALL_OK)
            assert(badges()=="ok,2bad,ok,2bad,ok,-,ok", badges())
            -- disabled check: dimmed icon, no badge
            module.db.checkWeaponEnchant=false
            module:Refresh()
            assert(display.icons[4].alpha==0.35 and not display.icons[4].badge.shown and display.icons[4].state==nil)
            display.icons[4].scripts.OnEnter(display.icons[4])
            assert(GameTooltip.lines[2].text==L.RAIDPREP_ITEM_OFF)
            -- ready-check replies on the number
            module.roster[8].ready=false
            module.roster[9].ready=nil
            module:Refresh()
            display.countArea.scripts.OnEnter(display.countArea)
            local texts={}
            for _, line in ipairs(GameTooltip.lines) do texts[#texts+1]=line.text end
            texts=table.concat(texts,"|")
            assert(texts:find(L.RAIDPREP_NOT_READY.."|Player8",1,true) and texts:find(L.RAIDPREP_WAITING.."|Player9",1,true), texts)
            display:Hide()
            display.icons[2].scripts.OnEnter(display.icons[2])
            display:Hide()
            assert(not GameTooltip.shown, "closing the strip must close its item tooltip")
        ''')


def test_report_button_follows_permission_and_reports_to_chat():
    lua = raid_runtime()
    lua.execute('''
        local L = ns.L
        function IsInRaid() return true end
        function UnitIsGroupLeader() return false end
        function UnitIsGroupAssistant() return false end
        module:Refresh()
        assert(display.reportButton.disabled)
        function UnitIsGroupLeader() return true end
        module:Refresh()
        assert(not display.reportButton.disabled)
        module.testMode=true
        display.reportButton.scripts.OnClick(display.reportButton)
        assert(printed[#printed]=="ERR "..L.RAIDPREP_STATUS_TEST)
        module:Refresh()
        assert(display.hint.text==L.RAIDPREP_STATUS_TEST)
        module.testMode=false
        module:Refresh()
        assert(display.hint.text==L.RAIDPREP_ICON_HINT)
    ''')


def test_no_hardcoded_colours_or_glyph_icons():
    for rel in ("Modules/RaidPreparation/RaidPreparation.lua", "Modules/ReadyCheckAssistant/ReadyCheckAssistant.lua"):
        source = (ROOT / rel).read_text(encoding="utf-8")
        assert "SetColorTexture(0." not in source and "SetTextColor(0." not in source and "SetTextColor(1," not in source, rel
        for glyph in ("↻", "✕", "✖", "✓"):
            assert glyph not in source, (rel, glyph)


def test_optional_badges_reports_and_ready_completion():
    for locale in ("koKR", "enUS"):
        lua = raid_runtime(locale)
        lua.execute('''
            local L, RS=ns.L,ns.ReadyStatus
            module.db.reportUnknown=true
            module.roster[1].rune=false; module.roster[2].vantus="LOW"
            module.roster[3].rune=nil; module.roster[3].vantus=nil
            module:Refresh()
            assert(module.fullyReady and display.headline.text==L.RAIDPREP_COMPLETE)
            assert(display.closeElapsed==0)
            assert(module:IsRecordComplete(module.roster[1],true))
            assert(display.icons[6].state=="opt" and display.icons[7].state=="opt")
            assert(display.icons[6].badgeCount==1 and display.icons[7].badgeCount==1)
            assert(display.icons[7].badge.fill.color[1]==RS.Token("text","dim")[1])
            assert(display.icons[7].badge.text.textColor[1]==RS.Token("bg","main")[1])
            assert(display.icons[7].icon.vertexColor[1]==RS.Token("text","normal")[1])
            assert(not display.icons[7].wellTint.shown)
            display.icons[7].scripts.OnEnter(display.icons[7])
            assert(GameTooltip.lines[1].text==L.RCA_ROW_VANTUS.." · "..L.RAIDPREP_OPTIONAL_LABEL)
            assert(GameTooltip.lines[#GameTooltip.lines].text==L.RAIDPREP_OPTIONAL_NOTE)
            local groups=module:BuildReportGroups()
            assert(#groups.rune==0 and #groups.vantus==0 and #groups.unknown==0)
            function IsInGroup() return true end
            sent={}; function SendChatMessage(msg) sent[#sent+1]=msg end
            local function report(auto)
                timers={}; sent={}; assert(module:SendReport(auto))
                for _,timer in ipairs(timers) do timer.fn() end
                return table.concat(sent,"|")
            end
            assert(report(true)==L.RAIDPREP_REPORT_ALL_READY)
            module.db.reportOptional=true
            for _,auto in ipairs({false,true}) do
                local text=report(auto)
                assert(text:find(L.RAIDPREP_REPORT_RUNE.."Player1",1,true))
                assert(text:find(L.RAIDPREP_REPORT_VANTUS.."Player2",1,true))
                assert(text:find(L.RAIDPREP_REPORT_UNKNOWN.."Player3",1,true))
            end
            module.db.checkVantus=false; module:Refresh()
            assert(display.icons[7].alpha==.35 and not display.icons[7].badge.shown)
            assert(#module:BuildReportGroups().vantus==0)
            display.scripts.OnUpdate(display,1.8); assert(not display.shown)
            module.db.checkVantus=true
            module:BuildTestRoster(); module.testMode=true; module:Refresh()
            assert(module.itemSummary[6].state=="opt" and module.itemSummary[7].state=="opt")
        ''')


def test_vantus_scanner_preserves_returns_and_refreshes_records():
    lua = raid_runtime()
    lua.execute('''
        function UnitExists() return true end
        function UnitIsConnected() return true end
        function UnitIsUnit() return false end
        local secret={}; function issecretvalue(v) return rawequal(v,secret) end
        C_Secrets={ShouldAurasBeSecret=function() return false end}
        local auras={}
        C_UnitAuras={GetAuraDataByIndex=function(_,i) return auras[i] end}
        module.db.minimumBuffMinutes=10
        module.db.customVantusSpellIDs="999001, 999002"
        module:BuildSpellSets()
        for id in pairs(module.vantusIDs) do
            auras={{spellId=id,name=secret,icon=456,expirationTime=clock+3600}}
            local food,flask,rune,_,_,_,found,icons,vantus,remaining=module:ScanUnitAuras("raid1")
            assert(food==false and flask==false and rune==false and type(found)=="table")
            assert(vantus==true and remaining==3600 and icons.vantus==456)
        end
        for _, name in ipairs({"반투스 룬: 새 보스","Vantus Rune: New Boss"}) do
            auras={{spellId=999999,name=name,expirationTime=clock+32}}
            local values={module:ScanUnitAuras("raid1")}
            assert(values[9]=="LOW" and values[10]==32)
        end
        auras={{spellId=999999,name=secret,expirationTime=secret}}
        local food,_,_,_,_,_,found,_,vantus=module:ScanUnitAuras("raid1")
        assert(food==false and type(found)=="table" and vantus==nil)
        auras={{spellId=1276687,icon=777,expirationTime=clock+3600}}
        local record=module:BuildRecord("raid1","Player1-Realm",1,1,"MAGE","DAMAGER",0)
        assert(record.vantus and record.vantusRemaining==3600)
        module.roster={record}; auras={}; module:RefreshUnitAura("raid1")
        assert(record.vantus==false and record.vantusRemaining==nil)
        auras={{spellId=secret,name=secret,expirationTime=secret}}
        module:RefreshUnitAura("raid1"); assert(record.vantus==nil)
        C_Secrets.ShouldAurasBeSecret=function() return true end
        assert(select(9,module:ScanUnitAuras("raid1"))==nil)
        C_Secrets.ShouldAurasBeSecret=function() return false end
        C_UnitAuras.GetAuraDataByIndex=function() error("restricted") end
        assert(select(9,module:ScanUnitAuras("raid1"))==nil)
    ''')
    lua.execute((ROOT / "Modules/ReadyCheckAssistant/ReadyCheckAssistant.lua").read_text(encoding="utf-8-sig"),
                "DDingUI_Toolkit", lua.globals().ns)
    lua.execute('''
        C_UnitAuras.GetAuraDataByIndex=function(_,i)
            if i==1 then return {spellId=999888,name="New custom buff",expirationTime=clock+3600} end
        end
        local personal=ns.ReadyCheckAssistant
        assert(personal:GetConsumables().vantus.value==false)
        module.db.customVantusSpellIDs="999888"
        module:ApplySettings()
        assert(personal:GetConsumables().vantus.value==true, "shared custom IDs must refresh the cached personal scanner")
    ''')

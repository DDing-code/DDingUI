"""설정 정리 후 실제 Lua의 켜짐·조건부 옵션·위치 저장을 검사한다."""
import re

from test_calm_alert_visual import ROOT, calm_runtime
from test_edit_mode import enter, toolkit_runtime
from test_mail_alert import mail_runtime


def load(lua, rel):
    lua.execute((ROOT / rel).read_text(encoding="utf-8-sig"), "DDingUI_Toolkit", lua.globals().ns)


def config_runtime():
    lua = calm_runtime()
    lua.execute("ns.modules={}; C_AddOns={GetAddOnMetadata=function() return '2.2.1' end}")
    load(lua, "Config_Data.lua")
    lua.execute("tree=ns:InitConfigTree(); fields={}; for _,panel in pairs(tree.panels) do "
                "for _,s in ipairs(panel.settings or {}) do if s.key then fields[s.key]=s end end end")
    return lua


def test_config_removes_guides_duplicates_positions_and_dead_controls():
    lua = config_runtime()
    lua.execute('''
        assert(not tree.panels.mythicplus and not ns.ConfigModuleMap.mythicplus)
        for _,panel in pairs(tree.panels) do
            assert(not panel.desc)
            for _,s in ipairs(panel.settings or {}) do
                assert(s.type ~= "text" and not s.desc)
                if s.key then
                    assert(not s.key:match("%.position%.[xy]$") and not s.key:match("Position%.[xy]$"))
                    assert(not s.key:match("%.pos[XY]$") and not s.key:match("[Ll]ocked$"))
                    assert(not s.key:match("%.alertPosition$"))
                end
            end
        end
        for _,module in ipairs({"CastingAlert", "CharacterPositionMarker", "DeathReleaseGuard", "RaidLootPass"}) do
            assert(fields["profile.modules."..module])
            assert(not fields["profile."..module..".enabled"])
        end
        assert(fields["profile.SoundManager.enabled"], "Keep the actual global sound switch")
        assert(fields["profile.VoidcoreHelper.entryPrompt"], "Keep separate entry consent")
        assert(not fields["profile.SkyridingTracker.barTexture"])
        assert(not fields["profile.SkyridingTracker.borderSize"])
        assert(not fields["profile.StasisTracker.fontSize"])
        local labels,count={},0
        for key,s in pairs(fields) do
            if key:match("^profile%.RaidDefensiveTracker%.sounds%..+%.soundFile$") then
                assert(s.label and not labels[s.label], "Each sound must identify its spell")
                labels[s.label]=true; count=count+1
            end
        end
        assert(count==15)
        for _,key in ipairs({"CastingAlert.scanDelay", "CastingAlert.combatOnly", "CastingAlert.ignoreMinor",
            "CharacterPositionMarker.rangeUpdateRate", "RangeDisplay.font", "RangeDisplay.fontOutline",
            "StasisTracker.orderFontSize", "PartyFullAlert.pollInterval", "LFGAlert.frameStrata",
            "PartyFullAlert.frameStrata", "CalendarInviteAlert.frameStrata", "DurabilityCheck.frameStrata"}) do
            assert(fields["profile."..key] and ns:GetDBValue("profile."..key) ~= nil, key)
        end
    ''')


def test_visibility_and_immediate_notepad_refresh():
    lua = config_runtime()
    lua.execute('''
        local p=ns.db.profile
        p.CharacterPositionMarker.shape="CROSS"
        assert(not fields["profile.CharacterPositionMarker.centerGap"].visible())
        p.CharacterPositionMarker.shape="RETICLE"
        assert(fields["profile.CharacterPositionMarker.centerGap"].visible())
        p.CharacterPositionMarker.shape="DIAMOND"
        assert(not fields["profile.CharacterPositionMarker.thickness"].visible())
        p.CharacterPositionMarker.visualMode="SIMPLE"
        assert(not fields["profile.CharacterPositionMarker.effectColor"].visible())
        p.CharacterPositionMarker.visualMode="SYSTEM"
        assert(fields["profile.CharacterPositionMarker.effectColor"].visible())
        p.CombatStateAlert.visualMode="SIMPLE"
        assert(not fields["profile.CombatStateAlert.startLineColor"].visible())
        p.CombatStateAlert.visualMode="FANCY"
        assert(fields["profile.CombatStateAlert.startLineColor"].visible())
        assert(fields["profile.CastingAlert.onlyTargetingMe"].refreshPanel)
        updates=0; ns.modules.Notepad={UpdateSettings=function() updates=updates+1 end}
        fields["profile.Notepad.showPVEButton"].onChange(false)
        assert(updates==1)
    ''')


def test_actual_section_builder_drops_separator_only_tabs():
    lua = config_runtime()
    source = (ROOT / "Config_UI.lua").read_text(encoding="utf-8-sig")
    visibility = source.split("local function IsSettingVisible(setting)", 1)[1].split("\nend", 1)[0]
    builder = source.split("local function BuildPanelSections(", 1)[1].split("local function CreateSectionTab", 1)[0]
    lua.execute('''function LT(_,fallback) return fallback end
        function IsRedundantPreviewButton() return false end
        local function IsSettingVisible(setting)''' + visibility + "\nend\n"
        "local function BuildPanelSections(" + builder + "\nBuildSections=BuildPanelSections")
    lua.execute('''
        for key,panel in pairs(tree.panels) do
            for _,section in ipairs(BuildSections(panel,true,key)) do
                assert(#section.settings>0)
                assert(section.settings[1].type ~= "separator")
                assert(section.settings[#section.settings].type ~= "separator")
            end
        end
        local sections=BuildSections({settings={{type="header"},{type="separator"}}},true,"test")
        assert(#sections==0)
    ''')


def test_shared_control_search_opens_profile_and_retains_legacy_fallback():
    lua = config_runtime()
    source = (ROOT / "Config_UI.lua").read_text(encoding="utf-8-sig")
    index = source.split("local SEARCHABLE_TYPES =", 1)[1].split("local function ClearSearchWidgets", 1)[0]
    lua.execute("settingsPanel={workspace=true}\nlocal SEARCHABLE_TYPES=" + index + "\nSearchIndex=BuildSearchIndex")
    lua.execute('''
        local found=0
        for _,entry in ipairs(SearchIndex()) do
            if entry.name==ns.L.SHOW_MINIMAP_BUTTON or entry.name==ns.L.SHOW_WELCOME_MESSAGE then
                assert(entry.panelKey=="profile"); found=found+1
            end
        end
        assert(found==2)
        settingsPanel=nil
        for _,entry in ipairs(SearchIndex()) do
            if entry.name==ns.L.SHOW_MINIMAP_BUTTON then assert(entry.panelKey=="general") end
        end
    ''')


def test_mail_legacy_position_and_saved_position_for_both_designs():
    lua = mail_runtime()
    lua.execute('''
        local m=ns.MailAlert
        m:OnInitialize()
        for _,style in ipairs({"FACTION","SEAL"}) do
            m.db.alertStyle=style; m.db.alertPosition="BOTTOM"; m.db.position=nil
            m:ShowAlert(true)
            assert(m.alertFrame.point=="BOTTOM" and m.alertFrame.y==200)
            assert(m.db.position==nil, "Preview must not create a saved position")
            m.db.position={point="CENTER",relativePoint="CENTER",x=123,y=-234}
            m:ApplySettings()
            assert(m.alertFrame.point=="CENTER" and m.alertFrame.x==123 and m.alertFrame.y==-234)
        end
    ''')


def test_lfg_and_mail_edit_mode_save_undo_and_reset():
    lua = toolkit_runtime()
    lua.execute('''
        for _,name in ipairs({"LFGAlert","MailAlert"}) do
            ns.db.profile[name]={alertPosition="BOTTOM"}
            ns.db.profile.modules[name]=true
            local f=CreateFrame("Frame", "DDingToolKit_"..name.."Frame", UIParent)
            f:SetSize(500,112); f:SetPoint("BOTTOM",UIParent,"BOTTOM",0,200)
            local mod={enabled=true, alertFrame=f, db=ns.db.profile[name]}
            function mod:CreateAlertFrame() end
            function mod:GetAlertPosition() return self.db.position or {point="BOTTOM",x=0,y=200} end
            function mod:EnterEditPreview() self.alertFrame:Show() end
            ns[name]=mod; ns.DDingToolKit.modules[name]=mod
        end
    ''')
    enter(lua)
    lua.execute('''
        local m=ns.ToolkitMovers
        for _,name in ipairs({"LFGAlert","MailAlert"}) do
            local overlay=_G["DDingToolKitMover_"..name]
            overlay:GetScript("OnClick")(overlay,"LeftButton")
            m:SetSelectedPosition(100,150)
            assert(ns.db.profile[name].position.x==100 and ns.db.profile[name].position.y==150)
            m:ResetSelected()
            assert(ns.db.profile[name].position.point=="TOP" and ns.db.profile[name].position.y==-100)
            m:Undo()
            assert(ns.db.profile[name].position.x==100 and ns.db.profile[name].position.y==150)
        end
    ''')


def test_public_spell_target_enables_sound_but_secret_target_is_not_branched():
    lua = calm_runtime()
    source = (ROOT / "Modules/CastingAlert/CastingAlert.lua").read_text(encoding="utf-8-sig")
    body = source.split("local function GetCurrentCastInfo(unit)", 1)[1].split("\nend", 1)[0]
    lua.execute('''
        secret=setmetatable({}, {__eq=function() error("secret compared") end})
        function IsSecretValue(v) return rawequal(v,secret) end
        function GetCurrentCastIdentity() return false,123,1 end
        function GetCastDurationObject() return {} end
        function GetTime() return 100 end
        function GetTargetName() return nil end
        function GetTargetsPlayer() return targetValue end
        function IsSpellImportant() return false end
        function UnitCastingInfo() return nil end
        function SecretBoolean(v) return v end
        function GetSpellName() return "spell" end
        function GetSpellTexture() return 123 end
        function HasValue() return false end
        function GetTargetClassColor() return nil end
        function GetUnitLevelScore() return 1 end
        function GetRaidTargetIndex() return nil end
        function ReadCast(unit)''' + body + "\nend")
    lua.execute('''
        targetValue=true; assert(ReadCast("nameplate1").targetsPlayerNamePlain)
        targetValue=false; assert(not ReadCast("nameplate1").targetsPlayerNamePlain)
        targetValue=secret; local info=ReadCast("nameplate1")
        assert(not info.targetsPlayerNamePlain and rawequal(info.targetsPlayerSecret,secret))
    ''')


def test_itemlevel_reset_keeps_table_and_restores_defaults():
    lua = calm_runtime()
    lua.execute('''
        getmetatable(UIParent).__index.SetOwner=function() end
        function GetInventorySlotInfo() return 1 end
        function wipe(t) for k in pairs(t) do t[k]=nil end end
        function ns.DDingToolKit:RegisterModule(name,mod) ns[name]=mod end
    ''')
    load(lua, "Modules/ItemLevel/ItemLevel.lua")
    lua.execute('''
        local m=ns.ItemLevel
        m.db={selfIlvlSize=44,inspectEnabled=false,obsolete=true}; local before=m.db
        m:ResetSettings()
        assert(m.db==before and m.db.obsolete==nil)
        assert(m.db.selfIlvlSize==ns.defaults.profile.ItemLevel.selfIlvlSize and m.db.inspectEnabled)
    ''')


def test_deleted_module_has_no_load_or_command_references():
    assert not (ROOT / "Modules/MythicPlusHelper/MythicPlusHelper.lua").exists()
    for rel in ("DDingUI_Toolkit.toc", "Core/SlashCommands.lua", "Core/Database.lua", "UI/Workspace.lua"):
        source = (ROOT / rel).read_text(encoding="utf-8-sig")
        assert "MythicPlusHelper" not in source and "AffixProbe" not in source
    for rel in ("Locales/koKR.lua", "Locales/enUS.lua"):
        assert not re.search(r'L\["(?:MYTHICPLUS_|TAB_MYTHICPLUS|MODULE_MYTHICPLUS)', (ROOT / rel).read_text(encoding="utf-8-sig"))


def test_party_master_and_live_settings_reach_both_healer_groups_and_lust():
    lua = calm_runtime()
    lua.execute("SlashCmdList={}")
    load(lua, "Modules/PartyTracker/PartyTracker.lua")
    lua.execute('''
        local m=ns.PartyTracker
        m.db=ns.db.profile.PartyTracker; m.db.enabled=false
        local created,started,visible=0,0,0
        m.CreateMainFrame=function() created=created+1 end
        m.StartUpdate=function() started=started+1 end
        m.UpdateVisibility=function() visible=visible+1 end
        m:OnEnable()
        assert(created==1 and started==1 and visible==1 and m.db.enabled==false)
        function SetUpvalue(fn,name,value)
            for i=1,100 do
                local key=debug.getupvalue(fn,i)
                if not key then break end
                if key==name then debug.setupvalue(fn,i,value); return end
            end
            error("upvalue missing: "..name)
        end
        local function Icon()
            local f=CreateFrame("Frame")
            for _,key in ipairs({"chargeText","mainText","subText","manaText","manaBar","manaBarBorder","iconFrame"}) do
                f[key]=CreateFrame("Frame")
            end
            f.manaBar.SetStatusBarTexture=function(self,path) self.texture=path end
            return f
        end
        local lust,a,b=Icon(),Icon(),Icon()
        SetUpvalue(m.UpdateFonts,"lustFrame",lust)
        SetUpvalue(m.UpdateFonts,"healerFrames",{a})
        SetUpvalue(m.UpdateFonts,"separateHealerFrames",{b})
        m.db.font="Fonts/Example.ttf"; m.db.fontSize=22; m.db.iconSize=46
        m.db.manaBarWidth=90; m.db.manaBarHeight=15
        m.db.manaBarOffsetX=9; m.db.manaBarOffsetY=12
        m.db.manaBarTexture="example-texture"
        m:UpdateFonts(); m:UpdateIconSize(); m:UpdateManaBarSize()
        m:UpdateManaBarPosition(); m:UpdateManaBarTexture()
        for _,f in ipairs({lust,a,b}) do
            assert(f.mainText.fontSize==22 and f.iconFrame.width==46)
        end
        for _,f in ipairs({a,b}) do
            assert(f.manaBar.width==90 and f.manaBar.height==15)
            assert(f.manaBarBorder.x==8 and f.manaBarBorder.y==12)
            assert(f.manaBar.texture=="example-texture")
        end
        local main,mana=CreateFrame("Frame"),CreateFrame("Frame")
        SetUpvalue(m.OnDisable,"mainFrame",main); SetUpvalue(m.OnDisable,"manaFrame",mana)
        m:OnDisable(); assert(not main:IsShown() and not mana:IsShown())
    ''')


def test_death_font_paths_and_default_sound_keep_explicit_silence():
    lua = calm_runtime()
    lua.execute('''
        LSM={Fetch=function(_,kind,key) if key=="NamedFont" then return "Fonts/named.ttf" end end}
        LibStub=function() return LSM end
        function ns:RequestSound(request) requested=request; return true end
    ''')
    load(lua, "Modules/DeathAlert/DeathAlert.lua")
    source = (ROOT / "Modules/DeathAlert/DeathAlert.lua").read_text(encoding="utf-8-sig")
    sound_helpers = source.split("-- Sound helpers", 1)[1].split("-- GUID", 1)[0]
    lua.execute("local LSM=LSM\n" + sound_helpers + "\nPlayCountSound=PlayDeathSound")
    lua.execute('''
        assert(PlayCountSound("","Master") and requested.soundKit==8959)
        requested=nil; assert(not PlayCountSound("None","Master") and not requested)
        assert(PlayCountSound("Interface/Sounds/custom.ogg","Master"))
        assert(requested.soundFile=="Interface/Sounds/custom.ogg" and not requested.soundKit)
        local f=CreateFrame("Frame"); f.text=CreateFrame("Frame")
        for i=1,30 do
            local key=debug.getupvalue(ns.DeathAlert.UpdateVisuals,i)
            if key=="msgFrame" then debug.setupvalue(ns.DeathAlert.UpdateVisuals,i,f); break end
        end
        ns.db.profile.DeathAlert.font="Fonts/custom.ttf"
        ns.DeathAlert:UpdateVisuals(); assert(f.text.font=="Fonts/custom.ttf")
        ns.db.profile.DeathAlert.font="NamedFont"
        ns.DeathAlert:UpdateVisuals(); assert(f.text.font=="Fonts/named.ttf")
    ''')

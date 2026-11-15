"""실제 추적 엔진을 실행해 비밀값, 출처, 장부, 모듈 분리와 편집을 검사한다."""
from pathlib import Path
import pytest

from ui_runtime import runtime
from test_edit_mode import HARNESS, STYLELIB

ROOT = Path(__file__).resolve().parents[1]


def load(lua, path):
    lua.execute((ROOT / path).read_text(encoding="utf-8-sig"), "DDingUI_Toolkit", lua.globals().ns)


def load_editor(lua):
    load(lua, "UI/Controls.lua")
    load(lua, "Core/Movers.lua")
    lua.execute('''
        function SetCombatPreview(value)
            for _, frame in ipairs(objects) do
                if frame.previewControl then frame.previewControl:SetValue(value, false) end
            end
            -- The mock does not advance animation groups; finish mover fades explicitly.
            for _, frame in ipairs(objects) do
                for _, key in ipairs({'_fadeAG', '_fadeOutAG'}) do
                    local animation=frame[key]
                    if animation and animation.playing then
                        animation:Stop(); animation:Fire('OnFinished')
                    end
                end
            end
        end
    ''')


# 12.1 비밀값 모의: 숨긴 값은 Lua에서 비교·연산·문자열화하면 오류가 나고, 엔진(상태 막대·투명도·
# C_CurveUtil)만 속값을 쓴다. 오라 묶음은 버프가 있으면 커서 아래로 커진 것처럼 IsMouseOver가 참이 된다.
HIDDEN_MOCK = r'''
local hidden = setmetatable({}, {__mode='k'})
local function Refuse() error('hidden value used in Lua') end
local meta = {__index=Refuse, __newindex=Refuse, __eq=Refuse, __lt=Refuse, __le=Refuse, __add=Refuse,
    __sub=Refuse, __mul=Refuse, __div=Refuse, __unm=Refuse, __concat=Refuse, __len=Refuse,
    __tostring=Refuse, __call=Refuse}
function Conceal(value) local box=setmetatable({}, meta); hidden[box]={value}; return box end
function Reveal(value) local box=hidden[value]; if box then return box[1] end; return value end
local plain=issecretvalue
function issecretvalue(value) return plain(value) or hidden[value]~=nil end
C_CurveUtil={EvaluateColorValueFromBoolean=function(condition, yes, no)
    assert(not plain(condition) and not plain(yes) and not plain(no))
    local result
    if Reveal(condition) then result=Reveal(yes) else result=Reveal(no) end
    if roundEval then result=math.floor(result*100+.5)/100 end
    if issecretvalue(condition) or issecretvalue(yes) or issecretvalue(no) then return Conceal(result) end
    return result
end}
function GetPhysicalScreenSize() return 1920, 1080 end
local M=getmetatable(UIParent).__index
function M:GetJustifyH() return self.justify end
function M:SetSpacing(value) self.spacing=value end
function M:GetStringHeight()
    local _, breaks=(self.text or ''):gsub('\n', '')
    return (self.fontSize or 12)*1.2*(breaks+1)+(self.spacing or 0)*breaks
end
function M:SetOrientation(value) self.orientation=value end
function M:SetReverseFill(value) self.reverseFill=value end
function M:SetClipsChildren(value) self.clips=value end
local function FillRect(texture)
    local bar=texture.bar
    local x, y, w, h=bar:Rect()
    local low, high, value=Reveal(bar.min or 0), Reveal(bar.max or 1), Reveal(bar.value or 0)
    local fraction=high>low and math.max(0, math.min(1, (value-low)/(high-low))) or 0
    if bar.orientation=='VERTICAL' then return x, y, w, h*fraction end
    if bar.reverseFill then return x+w*(1-fraction), y, w*fraction, h end
    return x, y, w*fraction, h
end
function M:GetStatusBarTexture()
    if not self.statusTexture then
        self.statusTexture=self:CreateTexture()
        self.statusTexture.bar=self
        self.statusTexture.Rect=FillRect
    end
    return self.statusTexture
end
buffs={}; hiddenAuras=false
function UnitExists(unit) return units[unit]~=nil end
function UnitCanAttack(_,unit) return units[unit] and units[unit].enemy==true end
function UnitCanAssist(_,unit) return not (units[unit] and units[unit].enemy==true) end
function UnitIsDeadOrGhost(unit) return units[unit] and units[unit].dead or false end
function UnitIsBossMob(unit) return units[unit] and units[unit].boss or false end
function UnitAffectingCombat(unit) return units[unit] and units[unit].fighting==true end
local baseMouseOver=M.IsMouseOver
function M:IsMouseOver(...)
    if self.kind~='AuraContainer' or self.group~='use' then return baseMouseOver(self, ...) end
    local filters, lit=self.config.candidateFilters, false
    for auraID in pairs(filters.includeSpellIDs) do
        local aura=self.enabled~=false and buffs[self.unit] and buffs[self.unit][auraID]
        if aura and self.auraFilter=='HARMFUL|!PLAYER' and aura.source=='player' then aura=nil end
        if aura and (not filters.maxDuration or aura.duration<=filters.maxDuration) then lit=true end
    end
    if hiddenAuras then return Conceal(lit) end
    return lit
end
'''

# 숨긴 타이머가 실제로 그리는 것: 숫자 창에 걸린 줄과 회색 덮개가 아이콘을 덮는지.
HIDDEN_READ = r'''
function IconOf(mod, index, id)
    for _, icon in ipairs(mod.rows[index].icons) do
        if icon:IsShown() and icon.texture.texture==id then return icon end
    end
end
function HiddenView(mod, index, id)
    local icon=IconOf(mod, index, id)
    local layer=icon and icon.hidden
    if not layer or not layer.root:IsShown() then return nil, false end
    local _, windowY=layer.win:Rect()
    local number, covered
    for k=1,2 do
        if Reveal(layer.text[k].alpha or 1)>0 then
            local _, stripY=layer.strip[k]:Rect()
            local line=(windowY-stripY)/layer.step+1
            local lines={}
            for text in layer.strip[k].text:gmatch('[^\n]+') do lines[#lines+1]=text end
            local whole=math.floor(line+.5)
            assert(math.abs(line-whole)<1e-6, 'strip line is not aligned with the window')
            if lines[#lines-whole+1] then assert(not number); number=lines[#lines-whole+1] end
        end
        if Reveal(layer.veil[k].alpha or 1)>0 then
            local _, veilY, _, veilH=layer.veil[k]:Rect()
            local _, iconY, _, iconH=icon.texture:Rect()
            if veilY<=iconY and veilY+veilH>=iconY+iconH then covered=true
            else assert(veilY>=iconY+iconH, 'grey cover cuts the icon') end
        end
    end
    return number, covered or false
end
function Aura(unit, id, duration)
    buffs[unit]=buffs[unit] or {}
    buffs[unit][id]=duration and {duration=duration} or nil
    Emit('UNIT_AURA', unit)
    -- 1/8 s steps stay exact, so whole-second rounding is deterministic.
    for _=1,4 do Advance(.125) end
end
function Settle() for _=1,6 do Advance(.125) end end
-- Stamps are whole seconds, so a fresh 2-minute use reads 2:00 or 1:59.
function Fresh(text, seconds)
    if type(seconds)~='number' then seconds=120 end
    for left=seconds-1,seconds do
        local whole=left>=60 and string.format('%d:%02d',math.floor(left/60),left%60) or tostring(left)
        if text==whole then return true end
    end
    return false
end
'''


def hidden_runtime(extra=None):
    lua = trace_runtime(hidden=extra or True)
    lua.execute(HIDDEN_READ)
    lua.execute('Settle()')
    return lua


def trace_runtime(locale="koKR", enabled=True, hidden=False):
    lua = runtime()
    lua.execute(HARNESS)
    for name in STYLELIB:
        load(lua, "Libs/DDingUI_StyleLib/" + name)
    lua.execute('''
        ns.modules=ns.DDingToolKit.modules
        function ns.DDingToolKit:RegisterModule(name,mod)
            ns.modules[name]=mod; mod.enabled=false
        end
        local oldLibStub=LibStub
        setmetatable(LibStub,{__call=function(_,key,silent)
            if key=="AceLocale-3.0" then return {NewLocale=function() return ns.L end} end
            return oldLibStub:GetLibrary(key,silent)
        end})
        local M=getmetatable(UIParent).__index
        local registerEvent=M.RegisterEvent
        function M:RegisterEvent(event)
            assert(event~='UNIT_SPECIALIZATION_CHANGED', 'unknown event: '..event)
            registerEvent(self,event)
        end
        min,max,tinsert,tremove=math.min,math.max,table.insert,table.remove
        function M:Clear() self.cd=nil; self.durationObject=nil end
        function M:SetCooldown(start,duration) self.cd={start,duration} end
        function M:SetCooldownFromDurationObject(duration) self.durationObject=duration end
        function M:SetDrawEdge(value) self.drawEdge=value end
        function M:SetDrawSwipe(value) self.drawSwipe=value end
        function M:SetReverse(value) self.reverse=value end
        function M:SetHideCountdownNumbers(value) self.hideNumbers=value end
        function M:SetStatusBarTexture(value) self.barTexture=value end
        function M:SetStatusBarColor(...) self.barColor={...} end
        function M:GetStatusBarTexture() self.statusTexture=self.statusTexture or self:CreateTexture(); return self.statusTexture end
        function M:SetIgnoreParentAlpha(value) self.ignoreParentAlpha=value end
        function M:SetFlipBookRows(v) self.flipRows=v end
        function M:SetFlipBookColumns(v) self.flipColumns=v end
        function M:SetFlipBookFrames(v) self.flipFrames=v end
        function M:SetChildKey(v) self.childKey=v end
        function M:SetAtlas(v) self.atlas=v end
        function M:IsPlaying() return self.playing==true end
        function M:SetTimerDuration(duration,interpolation,direction)
            self.timerDuration=duration; self.timerDirection=direction
        end
        local function AuraOwner(frame)
            while frame do
                if frame.kind=='AuraButton' then return frame end
                frame=frame.parent
            end
        end
        function M:SetParent(parent)
            assert(not AuraOwner(parent) or AuraOwner(self)==AuraOwner(parent),
                'Frame:SetParent(): Reparenting disallowed as child object would inherit forbidden aspects')
            self.parent=parent
        end
        local setScript=M.SetScript
        function M:SetScript(script,handler)
            assert(not AuraOwner(self) or not handler, 'AuraButton descendants forbid untrusted scripts')
            setScript(self,script,handler)
        end
        function M:SetLooping(value) self.looping=value end
        function M:SetFromAlpha(value) self.fromAlpha=value end
        function M:SetToAlpha(value) self.toAlpha=value end
        function M:SetDuration(value) self.duration=value end
        function M:SetOrder(value) self.order=value end
        function M:SetOffset(x,y) self.offsetX,self.offsetY=x,y end
        function M:CreateMaskTexture() return self:CreateTexture() end
        function M:GetNumMaskTextures() return #(self.masks or {}) end
        function M:GetMaskTexture(index) return self.masks[index] end
        function M:RemoveMaskTexture(mask)
            for i,value in ipairs(self.masks or {}) do
                if value==mask then table.remove(self.masks,i); return end
            end
        end
        function M:AddMaskTexture(mask) self.masks=self.masks or {}; table.insert(self.masks,mask) end
        function M:SetDrawLayer() end
        function CreateFramePool(kind,parent,template,reset)
            return {Acquire=function() return CreateFrame(kind,nil,parent,template),true end,
                Release=function(self,frame) if reset then reset(self,frame) end end}
        end
        function CreateTexturePool(parent,layer,sublevel,template,reset)
            return {Acquire=function() return parent:CreateTexture(nil,layer),true end,
                Release=function(self,texture) if reset then reset(self,texture) end end}
        end
        function M:SetFlowLayoutAnchorPoint(value) assert(not combat and not restrictions); self.flowAnchor=value end
        function M:SetFlowLayoutAxis(value) self.flowAxis=value end
        function M:SetFlowLayoutGrowthDirection(a,b) self.flowDirection={a,b} end
        function M:AddAuraGroup(key,options,config)
            assert(not combat and not restrictions)
            self.group=key; self.config=config; self.auraFilter=options
            -- All addon styling happens before any engine-owned aura data.
            self.buttons={}
            for i=1,config.maxFrameCount do
                local button=CreateFrame('AuraButton',nil,self)
                function button:SetIcon(icon) self.icon=icon end
                function button:SetDurationCooldown(cooldown) self.cooldown=cooldown end
                config.initializeFrame(button); self.buttons[i]=button; button:Hide()
            end
        end
        function M:SetAuraGroupLayout(key,layout) assert(not combat and not restrictions); self.config.layout=layout end
        function M:AddAuraSlot(key,filter,config)
            config.maxFrameCount=1
            self:AddAuraGroup(key,filter,config)
        end
        function EffectSlot(row,id)
            for _,o in ipairs(objects) do
                if o.parent==row.effects[id] and o.kind=='AuraContainer' then return o end
            end
            error('missing effect slot: '..id)
        end
        function M:SetUnit(unit)
            assert((not combat and not restrictions) or self.auraFilter=='HARMFUL|!PLAYER' or self.auraFilter=='HARMFUL')
            self.unit=unit
        end
        function M:UpdateAllAuras() end
        AnchorUtil={FlowLayoutAxis={Horizontal=1},FlowDirection={Right=1,Down=2}}
        C_AddOns={LoadAddOn=function() if loadFails then return nil end; return true end}
        raid=false; groupSize=3
        C_PartyInfo={IsDelveInProgress=function() return delve or false end, IsDelveComplete=function() return delveComplete or false end}
        function IsInRaid() return raid end
        C_LFGInfo={IsInLFGFollowerDungeon=function() return followerDungeon or false end}
        function UnitIsPlayer(unit)
            local info=units[unit]
            if info and info.isPlayer~=nil then return info.isPlayer end
            return info~=nil
        end
        function UnitName(unit) return units[unit] and units[unit].name end
        function UnitIsUnit(a,b)
            assert(not issecretvalue(a) and not issecretvalue(b))
            return a==b or (units[a] and units[b] and units[a].guid==units[b].guid) or false
        end
        cooldowns={}; known={}; baseCD={}; castSecrecy={}; auraSecrecy={}; publicAuras={}
        function IsPlayerSpell(id) return known[id] or false end
        function GetSpellBaseCooldown(id)
            if baseFails then error('unavailable') end
            return baseCD[id] or 120000
        end
        C_Spell.GetSpellTexture=function(id) return id end
        C_Spell.GetSpellCooldown=function(id) return cooldowns[id] or {isActive=false,isEnabled=true} end
        nativeDuration={engine=true}
        C_Spell.GetSpellCooldownDuration=function() return nativeDuration end
        chargeState={}
        C_Spell.GetSpellCharges=function(id) return chargeState[id] end
        C_Spell.GetSpellChargeDuration=function() return nativeDuration end
        C_Secrets.GetSpellAuraSecrecy=function(id) return auraSecrecy[id] or 1 end
        C_Secrets.GetSpellCastSecrecy=function(id) return castSecrecy[id] or 1 end
        C_UnitAuras.GetUnitAuraBySpellID=function(unit,id)
            assert(auraSecrecy[id]==0, 'secret aura must not be queried')
            return publicAuras[unit] and publicAuras[unit][id]
        end
        -- Card settings are nested; tests look at the flat field list.
        function FlatSettings(settings)
            local flat={}
            for _,s in ipairs(settings) do
                if s.type=='card' then for _,c in ipairs(s.settings) do flat[#flat+1]=c end
                else flat[#flat+1]=s end
            end
            return flat
        end
        units.player={guid='self',class='PRIEST',name='나'}
        units.party1={guid='warrior',class='WARRIOR',name='전사'}
        units.party2={guid='priest',class='PRIEST',name='사제'}
    ''')
    load(lua, "Libs/LibCustomGlow-1.0/LibCustomGlow-1.0.lua")
    load(lua, "Libs/DDingUI_StyleLib/GlowEffects.lua")
    load(lua, "Locales/enUS.lua")
    if locale == "koKR":
        load(lua, "Locales/koKR.lua")
    load(lua, "Core/Database.lua")
    lua.execute('''
        ns.db.profile.CooldownTrace=ns:DeepCopy(ns.defaults.profile.CooldownTrace)
        ns.db.profile.modules.CooldownTracker=false
        ns.db.profile.modules.DefensiveTracker=false
    ''')
    load(lua, "Modules/CooldownTrace/Data.lua")
    if hidden:
        lua.execute(HIDDEN_MOCK)
        if isinstance(hidden, str):
            lua.execute(hidden)
    load(lua, "Modules/CooldownTrace/Sensor.lua")
    load(lua, "Modules/CooldownTrace/Stops.lua")
    load(lua, "Modules/CooldownTrace/CooldownTrace.lua")
    load(lua, "Modules/CooldownTrace/Groups.lua")
    lua.execute('''
        -- Tracking behavior tests opt in; upgrade tests replace this profile before real startup.
        ns.db.profile.modules.SkillTracker=true
        ns.SkillTracker:Initialize()
        -- Single-category engines exercise the shared tracker without the OmniCD frame routing.
        for _, info in ipairs({{'CooldownTracker','cooldowns','CT_COOLDOWNS'},{'DefensiveTracker','defensives','CT_DEFENSIVES'}}) do
            local mod=ns.CooldownTraceEngine.New(info[1],info[2],info[3])
            ns.DDingToolKit:RegisterModule(info[1],mod); ns[info[1]]=mod
        end
        T=ns.CooldownTracker; D=ns.DefensiveTracker
        function EnableCommon()
            local mod=ns.modules.SkillTrace_common
            ns.db.profile.modules.SkillTracker=true
            if not mod.running then mod:OnEnable(); mod.enabled=true end
            return mod
        end
    ''')
    if enabled:
        lua.execute('''
            for _,mod in ipairs({T,D}) do
                ns.db.profile.modules[mod.moduleName]=true; mod:OnEnable(); mod.enabled=true
            end
        ''')
    return lua


def test_casts_split_modules_and_internal_timers_return_to_ready():
    lua = trace_runtime()
    lua.execute('''
        T.rows[2].observer:Fire('OnEvent','UNIT_SPELLCAST_SUCCEEDED',SECRET,SECRET,1719)
        D.rows[2].observer:Fire('OnEvent','UNIT_SPELLCAST_SUCCEEDED',SECRET,SECRET,1719)
        assert(T.ledger.warrior[1719].seconds==90 and D.ledger.warrior==nil)
        assert(T.rows[2].icons[1].text:GetText()=='1:30' and not T.rows[2].icons[1].unknown)
        D.rows[2].observer:Fire('OnEvent','UNIT_SPELLCAST_SUCCEEDED',SECRET,SECRET,97462)
        assert(D.ledger.warrior[97462] and not T.ledger.warrior[97462])
        Advance(121)
        -- A completed internal timer returns the icon to ready without hiding the selection.
        local icon=T.rows[2].icons[1]
        assert(icon.text:GetText()=='' and not icon.unknown and not icon.texture.desaturated)
        T:OnDisable()
        assert(not T.frame:IsShown() and D.running and D.frame:IsShown())
        assert(next(T.ledger)==nil)
        T:EnterEditPreview(); T:OnDisable(); T:OnEnable()
        assert(not T.rows[1].previewActive:IsShown())
    ''')


def test_display_options_default_on_for_existing_and_new_groups_and_stay_editable():
    lua = trace_runtime(enabled=False)
    load(lua, 'Config_Data.lua')
    lua.execute('''
        local G=ns.SkillTracker
        local db=ns.db.profile.CooldownTrace
        assert(ns.L.CT_DISPLAY_SETTINGS=='표시 조건' and ns.L.CT_SHOW_DELVE=='구렁에서 표시')
        assert(ns.L.CT_SHOW_PARTY=='파티에서 표시' and ns.L.CT_SHOW_RAID=='공격대에서 표시')
        db.cooldowns.showInParty=nil; db.cooldowns.showInRaid=nil; db.cooldowns.showInDelve=nil
        local position=db.cooldowns.position
        G:Initialize()
        assert(db.cooldowns.showInParty and db.cooldowns.showInRaid and db.cooldowns.showInDelve)
        assert(db.cooldowns.position==position)
        assert(db.cc.showInParty and db.common.showInRaid and db.cc.showInDelve)
        db.cooldowns.showInParty=false; G:Initialize()
        assert(db.cooldowns.showInParty==false)
        local tree=ns:InitConfigTree()
        for _,id in ipairs(db.groups) do
            local panel=tree.panels[G:Keys(id)]
            local fields={}
            for _,s in ipairs(FlatSettings(panel.settings)) do
                if s.key then fields[s.key:match('([^.]+)$')]=s end
            end
            for _,key in ipairs({'showInParty','showInRaid','showInDelve'}) do
                assert(fields[key].type=='toggle' and fields[key].onChange)
            end
            assert(not fields.showInSolo)
        end
    ''')


def test_display_context_toggles_and_solo_always_hides_even_in_combat_or_delves():
    lua = trace_runtime()
    lua.execute('''
        for _,mod in ipairs({T,D}) do
            assert(mod.frame:IsShown())
            mod.db.showInParty=false; mod:ApplySettings(); assert(not mod.frame:IsShown())
            delve=true; mod.events:Fire('OnEvent','SCENARIO_UPDATE'); assert(mod.frame:IsShown())
            mod.db.showInDelve=false; mod:ApplySettings(); assert(not mod.frame:IsShown())
            mod.db.showInParty=true; mod:ApplySettings(); assert(not mod.frame:IsShown())
            delve=false; delveComplete=true; mod:RefreshRoster(); assert(not mod.frame:IsShown())
            mod.db.showInDelve=true; mod:ApplySettings(); assert(mod.frame:IsShown())
            for _,finished in ipairs({false,true}) do
                delve=not finished; delveComplete=finished
                groupSize=1; combat=true
                mod.events:Fire('OnEvent','PLAYER_ENTERING_WORLD')
                assert(not mod.frame:IsShown())
                for _,row in ipairs(mod.rows) do assert(not row:IsVisible() and not row.guid) end
                Advance(1); assert(not mod.frame:IsShown())
                combat=false; groupSize=3; mod.events:Fire('OnEvent','PLAYER_REGEN_ENABLED')
                assert(mod.frame:IsShown())
            end
            delve=false; delveComplete=false; groupSize=1
            mod.events:Fire('OnEvent','GROUP_ROSTER_UPDATE'); assert(not mod.frame:IsShown())
            mod:EnterEditPreview(); assert(mod.frame:IsShown())
            mod:ExitEditPreview(); assert(not mod.frame:IsShown())
            groupSize=3; mod:RefreshRoster()
        end
    ''')


def test_raid_rows_track_all_members_once_and_use_self_cooldowns_and_native_anchors():
    lua = trace_runtime()
    lua.execute('''
        for index=1,40 do
            units['raid'..index]={guid='raider'..index,class='WARRIOR',name='공대원'}
        end
        units.raid17=units.player
        known[10060]=true; raid=true; groupSize=40
        local frame=CreateFrame('Button','CompactRaidFrame1',UIParent); frame.unit='raid1'
        local grouped=CreateFrame('Button','CompactRaidGroup8Member5',UIParent); grouped.unit='raid40'
        for _,mod in ipairs({T,D}) do
            mod.events:Fire('OnEvent','GROUP_ROSTER_UPDATE')
            assert(mod.frame:IsShown() and #mod.rows==45 and not mod.rows[1]:IsShown())
            assert(mod.rows[22].isPlayer and mod.rows[22].unit=='raid17')
            local seen={}
            for _,row in ipairs(mod.rows) do
                if row.guid then assert(not seen[row.guid]); seen[row.guid]=true end
            end
            local id=mod==T and 1719 or 97462
            mod.rows[45].observer:Fire('OnEvent','UNIT_SPELLCAST_SUCCEEDED',nil,nil,id)
            assert(mod.ledger.raider40[id] and mod.rows[45].icons[1]:IsShown())
            mod.db.showInRaid=false; mod:ApplySettings(); assert(not mod.frame:IsShown())
            mod.db.showInRaid=true; mod.db.attachTo='party'; mod:ApplySettings()
            assert(mod.rows[6].anchor==frame and mod.rows[45].anchor==grouped)
            mod.db.attachTo='screen'; mod:ApplySettings()
            groupSize=1; mod:RefreshRoster(); assert(not mod.frame:IsShown())
            groupSize=40
        end
        assert(T.rows[22].icons[1]:IsShown() and not T.rows[22].icons[1].unknown)
        raid=false; groupSize=3; T:RefreshRoster()
        assert(T.rows[1]:IsShown() and not T.rows[6]:IsShown())
    ''')


def test_raid_row_allocation_waits_for_combat_end():
    lua = trace_runtime()
    lua.execute('''
        units.raid1=units.player; units.raid2=units.party1; units.raid3=units.party2
        raid=true; combat=true
        T.events:Fire('OnEvent','GROUP_ROSTER_UPDATE')
        assert(#T.rows==5 and not T.frame:IsShown())
        combat=false; T.events:Fire('OnEvent','PLAYER_REGEN_ENABLED')
        assert(#T.rows==8 and T.frame:IsShown())
        units.raid4={guid='new',class='WARRIOR',name='새 공대원'}
        groupSize=4; combat=true; T:RefreshRoster(); assert(#T.rows==8)
        combat=false; T.events:Fire('OnEvent','PLAYER_REGEN_ENABLED')
        assert(#T.rows==9 and T.rows[9].guid=='new')
    ''')


def test_secret_values_are_discarded_before_branch_math_or_table_keys():
    lua = trace_runtime()
    lua.execute('''
        setmetatable(SECRET,{__tostring=function() error('secret string') end,
            __eq=function() error('secret equality') end,__lt=function() error('secret ordering') end,
            __sub=function() error('secret math') end,__add=function() error('secret math') end})
        T.rows[2].observer:Fire('OnEvent','UNIT_SPELLCAST_SUCCEEDED',SECRET,SECRET,SECRET)
        assert(T.ledger.warrior==nil)
        baseCD[1719]=SECRET
        T:Record(T.rows[2],1719,GetTime())
        assert(T.ledger.warrior[1719].seconds==90) -- public catalog fallback, never secret arithmetic
        units.party1.guid=SECRET
        T:RefreshRoster()
        assert(T.rows[2].guid==nil and T.ledger.warrior==nil)
        units.party1.guid='warrior'; units.party1.class=SECRET
        T:RefreshRoster()
        assert(T.rows[2].guid==nil)
        known[10060]=true; cooldowns[10060]={isActive=SECRET,isEnabled=true,duration=SECRET,startTime=SECRET}
        T:UpdateCooldowns()
        assert(T.rows[1].icons[1].unknown and T.rows[1].icons[1].text:GetText()=='')
    ''')


def test_public_aura_requires_own_source_and_does_not_restart_on_initial_scan():
    lua = trace_runtime()
    lua.execute('''
        auraSecrecy[10060]=0
        publicAuras.party2={[10060]={sourceUnit='player',duration=20,expirationTime=30}}
        T:ScanAuras(T.rows[3])
        assert(T.ledger.priest==nil) -- another priest's PI is not the recipient's cooldown
        publicAuras.party2={}; T:ScanAuras(T.rows[3])
        publicAuras.party2={[10060]={sourceUnit='party2',duration=20,expirationTime=30}}
        T:ScanAuras(T.rows[3])
        assert(T.ledger.priest[10060].started==10)
        Advance(.2); T:Record(T.rows[3],10060,GetTime())
        assert(T.ledger.priest[10060].started==10)
        T:Reset()
        assert(T.ledger.priest==nil) -- ongoing auras establish a baseline only
        publicAuras.party2={}; T:ScanAuras(T.rows[3])
        publicAuras.party2={[10060]={sourceUnit=SECRET,duration=SECRET,expirationTime=SECRET}}
        T:ScanAuras(T.rows[3]); assert(T.ledger.priest==nil)
    ''')


def test_aura_slots_initialize_without_reparenting_untrusted_glow_frames():
    lua = trace_runtime()
    lua.execute('''
        for _,mod in ipairs({T,D}) do
            assert(not mod.containerUnavailable, 'aura slot initialization failed')
            for _,row in ipairs(mod.rows) do
                if row.guid then
                    for _,id in ipairs(mod:Spells(row.class)) do
                        local button=EffectSlot(row,id).buttons[1]
                        assert(button.cooldown and not button._PixelGlow)
                        assert(button.glow.parent==button and not button.glow:GetScript('OnUpdate'))
                        assert(#button.glow.edges==4 and #button.glow.pixels>8)
                        for _,pixel in ipairs(button.glow.pixels) do
                            assert(pixel.color[1]==DDingUI_StyleLib.Colors.status.success[1])
                            assert(pixel:GetWidth()>0 and pixel:GetHeight()>0)
                            assert(pixel.animation.playing and pixel.animation.looping=='REPEAT')
                        end
                        assert(button.glow.animation.playing and button.glow.animation.looping=='BOUNCE')
                    end
                end
            end
        end
    ''')


def test_library_glow_on_normal_icons_keeps_options_and_protected_aura_fallback():
    lua = trace_runtime()
    lua.execute('''
        T.db.useGlow=true; T.db.useGlowColor={.2,.3,.4,.5}
        T.db.glowThickness=5; T.db.glowPulse=false; T.db.glowSpeed=1.2
        T:EnterEditPreview()
        local host=T.rows[1].icons[2].useGlow
        local pixel=host._PixelGlow
        assert(pixel and not host.edges and pixel.parent==host and #pixel.textures==8)
        assert(pixel.info.th==5 and pixel.textures[1].vertexColor[4]==.5)
        assert(pixel.textures[1].vertexColor[1]==.2)
        assert(host:IsVisible() and not host.animation.playing and host.pulseAlpha.duration==1.2)
        local timer=pixel.timer
        pixel:Fire('OnUpdate',.2); assert(pixel.timer~=timer)
        assert(T.rows[1].previewActive.glow._PixelGlow)
        T.db.useGlow=false; T.db.activeGlow=false; T:ApplySettings()
        assert(not host._PixelGlow and not pixel:IsShown() and not pixel:GetScript('OnUpdate'))
        assert(not T.rows[1].previewActive.glow._PixelGlow)
        T.db.useGlow=true; T.db.activeGlow=true; T.db.glowPulse=true; T:ApplySettings()
        assert(host._PixelGlow and host.animation.playing)
        T:ExitEditPreview()
        local button=EffectSlot(T.rows[2],1719).buttons[1]
        assert(button.glow.edges and not button.glow._PixelGlow)
        -- The real embedded library still fails at SetParent on a restricted aura descendant.
        local ok,err=pcall(DDingUI_StyleLib.ShowPixelGlow,button.glow,{1,1,1,1})
        assert(not ok and string.find(err,'Reparenting disallowed',1,true))
    ''')


def test_protected_glow_orbits_close_at_constant_speed_and_reuse_native_regions():
    lua = trace_runtime()
    lua.execute('''
        local glow=EffectSlot(T.rows[2],1719).buttons[1].glow
        local function NativeCount()
            local count=0
            for _,object in ipairs(objects) do
                local parent=object
                while parent and parent~=glow do parent=parent.parent end
                if parent then count=count+1 end
            end
            return count
        end
        function OrbitPosition(particle,seconds)
            local _,_,_,x,y=particle:GetPoint()
            local period=0
            for _,leg in ipairs(particle.legs) do period=period+leg.duration end
            seconds=seconds%period
            for _,leg in ipairs(particle.legs) do
                local progress=leg.duration==0 and 0 or math.min(1,seconds/leg.duration)
                x=x+leg.offsetX*progress; y=y+leg.offsetY*progress
                seconds=math.max(0,seconds-leg.duration)
            end
            return x,y,period
        end
        local function Check(particles,kind,size)
            for index,particle in ipairs(particles) do
                if particle:IsShown() then
                    assert(particle.animation.playing and not particle:GetScript('OnUpdate'))
                    local dx,dy,duration=0,0,0
                    for order,leg in ipairs(particle.legs) do
                        assert(leg.order==order)
                        dx=dx+leg.offsetX; dy=dy+leg.offsetY; duration=duration+leg.duration
                        assert(math.abs(math.abs(leg.offsetX)+math.abs(leg.offsetY)-leg.duration*size*4/
                            (kind=='pixel' and 4 or 8*(math.floor((index-1)/4)+1)))<.00001)
                    end
                    assert(math.abs(dx)<.00001 and math.abs(dy)<.00001)
                    assert(math.abs(duration-(kind=='pixel' and 4 or 8*(math.floor((index-1)/4)+1)))<.00001)
                    local x0,y0=OrbitPosition(particle,0)
                    for _,seconds in ipairs({.17,.83,1.49,2.21,3.57}) do
                        local x,y=OrbitPosition(particle,seconds)
                        assert(x>=-.00001 and y>=-.00001 and x<=size+.00001 and y<=size+.00001)
                        assert(math.min(math.abs(x),math.abs(y),math.abs(x-size),math.abs(y-size))<.00001)
                        assert(math.abs(x-x0)+math.abs(y-y0)>.00001)
                    end
                end
            end
        end
        T.db.glowPulse=false; T.db.scale=1
        for _,size in ipairs({8,30,96}) do
            T.db.pixelSize=size
            for _,kind in ipairs({'pixel','autocast'}) do
                T.db.glowType=kind; T:ApplySettings()
                assert(glow.nativeSize==size and not glow.animation.playing)
                Check(kind=='pixel' and glow.pixels or glow.sparks,kind,size)
                local count=NativeCount()
                T:ApplySettings(); assert(NativeCount()==count, 'native animations must be reused')
            end
        end
        T.db.activeGlow=false; T:ApplySettings()
        for _,particles in ipairs({glow.pixels,glow.sparks}) do
            for _,particle in ipairs(particles) do assert(not particle.animation.playing) end
        end
        T.db.activeGlow=true; T.db.glowType='normal'; T:ApplySettings()
        assert(glow.edges[1]:IsShown())
        for _,particles in ipairs({glow.pixels,glow.sparks}) do
            for _,particle in ipairs(particles) do assert(not particle:IsShown() and not particle.animation.playing) end
        end
    ''')


def test_native_player_cooldown_and_active_secret_effects_stay_in_engine():
    lua = trace_runtime()
    lua.execute('''
        known[10060]=true
        cooldowns[10060]={isActive=true,isEnabled=true,startTime=SECRET,duration=SECRET}
        T:UpdateCooldowns()
        local icon=T.rows[1].icons[1]
        assert(icon.cooldown.durationObject==nativeDuration and icon.text:GetText()=='' and not icon.unknown)
        cooldowns[10060]={isActive=false,isEnabled=false}
        T:UpdateCooldowns(); assert(icon.unknown and icon.text:GetText()=='')
        cooldowns[10060]={isActive=false,isEnabled=true}
        T:UpdateCooldowns(); assert(icon.text:GetText()=='' and not icon.cooldown.cd and not icon.unknown)
        chargeState[10060]={isActive=true,maxCharges=2,currentCharges=SECRET}
        T:UpdateCooldowns()
        assert(icon.cooldown.durationObject==nativeDuration and icon.text:GetText()=='')
        chargeState[10060]={isActive=false,maxCharges=2,currentCharges=SECRET}
        T:UpdateCooldowns(); assert(icon.text:GetText()=='' and icon.count:GetText()=='')
        chargeState[10060]={isActive=false,maxCharges=2,currentCharges=1}
        T:UpdateCooldowns(); assert(tostring(icon.count:GetText())=='1')
        chargeState[10060]=nil; T:UpdateCooldowns(); assert(icon.count:GetText()=='')
        local slot=EffectSlot(D.rows[2],97462)
        assert(slot.config.candidateFilters.includeSpellIDs[97463])
        assert(not slot.config.candidateFilters.includeSpellIDs[97462])
        slot=EffectSlot(T.rows[3],10060)
        assert(slot.unit=='party2')
        local button=slot.buttons[1]
        assert(button.cooldown and not button.mouse)
        assert(button.cooldown.drawSwipe and button.cooldown.reverse and not button.cooldown.hideNumbers)
        T:Record(T.rows[3],10060,GetTime())
        assert(button.glow and not button.glow:IsVisible())
        assert(button.glow:GetWidth()>0)
        button:Show(); assert(button.glow:IsVisible())
        button:Hide(); assert(not button.glow:IsVisible())
    ''')


def test_roster_swap_reset_unknown_base_charges_and_restriction_deferral():
    lua = trace_runtime()
    lua.execute('''
        D:Record(D.rows[2],97462,GetTime())
        units.party1={guid='replacement',class='WARRIOR',name='새 전사'}
        D:RefreshRoster()
        assert(D.ledger.warrior==nil and D.rows[2].guid=='replacement')
        baseFails=true
        D:Record(D.rows[2],97462,GetTime())
        assert(D.ledger.replacement[97462].seconds==180)
        units.party1={guid='druid',class='DRUID',name='드루이드'}; D:RefreshRoster()
        D:Record(D.rows[2],61336,GetTime())
        assert(D.ledger.druid[61336].seconds==nil)
        local oldSize=D.size
        combat=true; D.db.iconSize=44; D:ApplySettings()
        assert(D.pending and D.size==oldSize)
        combat=false; D.events:Fire('OnEvent','PLAYER_REGEN_ENABLED')
        assert(D.size==44 and not D.pending)
        D.events:Fire('OnEvent','ENCOUNTER_END')
        assert(next(D.ledger)==nil)
        units.raid1=units.player; units.raid2=units.party1; units.raid3=units.party2
        raid=true; D:RefreshRoster(); assert(D.frame:IsShown())
        assert(not D.rows[1]:IsShown() and D.rows[6].isPlayer)
        raid=false; D:RefreshRoster(); assert(D.frame:IsShown())
    ''')


def test_active_slots_follow_the_matching_icon_through_sort_wrap_and_roster_changes():
    lua = trace_runtime()
    lua.execute('''
        for _,mod in ipairs({T,D}) do
            local row=mod.rows[2]
            local spells=ns.CooldownTraceData[mod.kind].WARRIOR
            local first,second=spells[1],spells[2]
            local slot=EffectSlot(row,first)
            local effect=row.effects[first]
            assert(effect:IsShown() and not row.effects[10060])
            mod:Record(row,first,GetTime())
            local button=slot.buttons[1]
            button:Show() -- Only the simulated engine changes aura visibility.
            assert(button.glow:GetWidth()>0)
            assert(button.glow:IsVisible())
            assert(effect.target==row.icons[1] and select(2,effect:GetPoint())==row.icons[1].texture)
            assert(select(2,button:GetPoint())==effect)
            assert(effect:GetFrameLevel()>row.icons[1].cooldown:GetFrameLevel())
            local count=#objects
            combat=true; restrictions=true
            Advance(2); mod:Record(row,second,GetTime())
            assert(effect.target==row.icons[2] and select(2,effect:GetPoint())==row.icons[2].texture)
            assert(button.glow:IsVisible() and #objects==count)
            button:Hide(); assert(not button.glow:IsVisible())
            combat=false; restrictions=false
            mod.db.columns=1; mod.db.iconSize=48; mod.db.sortOrder='spell'
            mod:ApplySettings()
            assert(effect.target==row.icons[1] and effect:GetWidth()==48)
            mod:EnterEditPreview(); assert(not button.glow:IsVisible())
            mod:ExitEditPreview(); assert(effect.target==row.icons[1])
            mod:Reset(); assert(effect:IsShown() and effect.target:IsShown())
        end
        -- A new class arriving in combat must not reuse the previous unit's spell slots.
        combat=true; restrictions=true
        units.party1={guid='newmage',class='MAGE',name='새 마법사'}
        T:RefreshRoster(); T:Record(T.rows[2],365350,GetTime())
        assert(T.containerUnavailable and not T.rows[2].effects[365350])
        combat=false; restrictions=false
        T.events:Fire('OnEvent','PLAYER_REGEN_ENABLED')
        assert(not T.containerUnavailable and T.rows[2].effects[365350]:IsShown())
        assert(not T.rows[2].effects[107574]:IsShown())
        local slot=EffectSlot(T.rows[2],365350)
        assert(slot.unit=='party1')
        slot.buttons[1]:Show()
        assert(slot.buttons[1].glow:IsVisible())
        T:OnDisable(); assert(not slot.buttons[1].glow:IsVisible())
    ''')


def test_unobserved_ally_effects_have_visible_hosts_without_cooldown_evidence():
    lua = trace_runtime()
    lua.execute('''
        for _,mod in ipairs({T,D}) do
            local row=mod.rows[2]
            local spells=ns.CooldownTraceData[mod.kind].WARRIOR
            local effect=row.effects[spells[1]]
            local button=EffectSlot(row,spells[1]).buttons[1]
            assert(effect:IsVisible())
            assert(effect.target:IsShown() and mod.ledger.warrior==nil)
            button:Show() -- Simulated engine visibility, with no public cast or aura.
            button.IsShown=function() error('addon must not read engine visibility') end
            button.IsVisible=button.IsShown
            combat=true; restrictions=true
            now=now+2; mod:UpdateCooldowns()
            mod:Record(row,spells[2],GetTime())
            assert(effect:IsVisible() and effect.target==row.icons[2])
            assert(effect.target:IsShown() and mod.ledger.warrior[spells[1]]==nil)
            assert(row.icons[1]:IsShown() and row.icons[1].text:GetText()==(mod==T and '1:30' or '2:00'))
            button.IsShown=nil; button.IsVisible=nil
            assert(button:IsVisible() and button.glow:IsVisible())
            combat=false; restrictions=false
            mod.db.columns=1; mod.db.iconSize=48; mod.db.sortOrder='spell'
            mod:ApplySettings()
            assert(effect:IsVisible() and effect:GetWidth()==48)
            mod:Reset()
            assert(effect:IsVisible() and effect.target:IsShown() and next(mod.ledger)==nil)
            button:Hide()
            assert(effect:IsVisible() and effect.target:IsShown() and not button.glow:IsVisible())
            mod:EnterEditPreview(); assert(not effect:IsVisible())
            mod:ExitEditPreview(); assert(effect:IsVisible())
            mod:OnDisable(); assert(not effect:IsVisible())
        end
    ''')


def test_arcane_surge_aura_filter_and_public_evidence_use_cast_id():
    lua = trace_runtime()
    lua.execute('''
        units.party1={guid='mage',class='MAGE',name='마법사'}
        T:RefreshRoster()
        local row=T.rows[2]
        local slot=EffectSlot(row,365350)
        assert(slot.config.candidateFilters.includeSpellIDs[365362])
        assert(not slot.config.candidateFilters.includeSpellIDs[365350])
        slot.buttons[1]:Show()
        assert(slot.buttons[1]:IsVisible() and T.ledger.mage==nil)
        auraSecrecy[365362]=0
        publicAuras.party1={[365362]={sourceUnit='player',duration=15,expirationTime=25}}
        T:ScanAuras(row); assert(T.ledger.mage==nil)
        publicAuras.party1={}; T:ScanAuras(row)
        publicAuras.party1={[365362]={sourceUnit='party1',duration=15,expirationTime=25}}
        T:ScanAuras(row,true); assert(T.ledger.mage==nil)
        publicAuras.party1={}; T:ScanAuras(row)
        publicAuras.party1={[365362]={sourceUnit='party1',duration=15,expirationTime=25}}
        T:ScanAuras(row)
        assert(T.ledger.mage[365350] and not T.ledger.mage[365362])
    ''')


def test_independent_settings_and_common_edit_preview_preserve_positions():
    lua = trace_runtime()
    load(lua, "Config_Data.lua")
    load_editor(lua)
    lua.execute('''
        local tree=ns:InitConfigTree()
        assert(ns.ConfigModuleMap.cooldowntracker==nil and ns.ConfigModuleMap.defensivetracker==nil)
        assert(tree.panels.skilltracker.moduleEnableKey=='profile.modules.SkillTracker')
        for _,mod in ipairs({T,D}) do
            local p=mod.db.position
            mod:EnterEditPreview()
            assert(mod.preview and mod.frame:IsShown())
            assert(p==mod.db.position and p.x==mod.db.position.x)
            for _,row in ipairs(mod.rows) do
                assert(row:IsShown() and row:GetHeight()>=mod.size+10)
            end
            mod:ExitEditPreview()
            assert(mod.running and not mod.preview)
        end
        T.db.scale=.6; T:ApplySettings()
        assert(T.frame:GetScale()==.6 and D.frame:GetScale()==.8)
        -- Frame 0 and enabled screen bars get movers; their saved positions survive edit mode.
        local G=ns.SkillTracker
        local common=EnableCommon()
        G:SetEnabled('bar2',true); G:SetTypeFrame('cooldowns',2)
        local bar=ns.modules.SkillTrace_bar2
        local x=bar.db.position.x
        ns.ToolkitMovers:ToggleConfigMode()
        SetCombatPreview(true)
        assert(common.preview and bar.preview)
        assert(_G.DDingToolKitMover_SkillTrace_common:IsShown() and _G.DDingToolKitMover_SkillTrace_bar2:IsShown())
        local disabled=_G.DDingToolKitMover_SkillTrace_bar3
        assert(not disabled or not disabled:IsShown())
        _G.DDingToolKitMover_SkillTrace_bar2:Fire('OnClick','LeftButton')
        ns.ToolkitMovers:Nudge(1,0)
        assert(bar.db.position.x~=x and bar.db==ns.db.profile.CooldownTrace.extraBars.bar2)
        local saved=bar.db.position.x
        ns.ToolkitMovers:ToggleConfigMode()
        assert(not common.preview and not bar.preview)
        bar:ApplySettings(); assert(bar.db.position.x==saved)
        bar.db.unitBar=true; bar:ApplySettings()
        ns.ToolkitMovers:ToggleConfigMode(); SetCombatPreview(true)
        assert(not _G.DDingToolKitMover_SkillTrace_bar2:IsShown())
        ns.ToolkitMovers:ToggleConfigMode()
    ''')


def test_skill_tracker_groups_reuse_existing_settings_and_switch_independently():
    lua = trace_runtime()
    load(lua, 'Config_Data.lua')
    lua.execute('''
        local tree=ns:InitConfigTree()
        local panel=tree.panels.skilltracker
        assert(panel.title==ns.L.CT_SKILL_TRACKER and not panel.groups and panel.compact and panel.sectionColumns==2)
        local headers={}
        for _,s in ipairs(panel.settings) do if s.type=='header' then headers[#headers+1]=s.label end end
        local L=ns.L
        assert(#headers==2 and headers[1]==L.CT_TAB_BARS and headers[2]==L.CT_TRACKED_SPELLS)
        assert(L.CT_TAB_BARS=='그룹 설정' and L.CT_TAB_FRAME=='프레임' and L.CT_TAB_PRIORITY=='우선순위')
        assert(rawget(L,'CT_TAB_SETTINGS')==nil and rawget(L,'CT_TAB_EXTRA_BARS')==nil)
        assert(not tree.panels.cooldowntracker and not tree.panels.defensivetracker and not tree.panels.skilltrace_common)
        local menuCount=0
        for _,category in ipairs(tree.menu) do
            for _,entry in ipairs(category.children or {}) do
                if entry.key=='skilltracker' then menuCount=menuCount+1 end
            end
        end
        assert(menuCount==1 and ns.ConfigModuleMap.skilltracker=='SkillTracker')
    ''')
    home = (ROOT / 'UI/HomePanels.lua').read_text(encoding='utf-8-sig')
    counter = home.split('local function GetModuleCounts(', 1)[1].split('function HomePanels:RenderDashboard(', 1)[0]
    lua.execute('local function GetModuleCounts(' + counter + '\nCountGroups=GetModuleCounts')
    lua.execute('''
        local enabled,total=CountGroups({'skilltracker'}); assert(enabled==1 and total==1)
        local G=ns.SkillTracker
        local common=EnableCommon()
        G:SetEnabled(nil,false)
        enabled,total=CountGroups({'skilltracker'}); assert(enabled==0 and total==1)
        assert(not common.running and not common.frame:IsShown())
        G:SetEnabled(nil,true)
        assert(common.running)
    ''')


def test_live_group_and_master_toggles_preserve_selections_positions_and_timers():
    lua = trace_runtime()
    lua.execute('''
        local G,db=ns.SkillTracker,ns.db.profile.CooldownTrace
        local common=EnableCommon()
        local bar=ns.modules.SkillTrace_bar2
        local spells=db.cooldowns.spells
        common:Record(common.rows[2],1719,GetTime())
        local started=common.ledger.warrior[1719].started
        -- A disabled bar redirects its types to the party frame (OmniCD redirect default).
        assert(G:SetTypeFrame('cooldowns',2))
        assert(G:DisplayFrame(1719)==0 and not bar.running)
        assert(common.ledger.warrior[1719].started==started)
        G:SetEnabled('bar2',true)
        assert(bar.running and bar.enabled and bar.frame:IsShown())
        assert(bar.ledger.warrior[1719].started==started)
        for _,id in ipairs(common:Spells('WARRIOR')) do assert(id~=1719) end
        assert(#bar:Spells('WARRIOR')==#ns.CooldownTraceData.cooldowns.WARRIOR)
        Advance(3)
        db.extraBars.bar2.redirect=false
        G:SetEnabled('bar2',false)
        assert(not bar.running and not bar.events:IsShown() and next(bar.events.events)==nil)
        assert(G:DisplayFrame(1719)==nil)
        for _,id in ipairs(common:Spells('WARRIOR')) do assert(id~=1719) end
        db.extraBars.bar2.redirect=true; G:Refresh()
        assert(G:DisplayFrame(1719)==0 and common.ledger.warrior[1719].started==started)
        G:SetEnabled(nil,false)
        for _,definition in ipairs(G:Definitions()) do
            local mod=ns.modules[definition[2]]
            assert(not mod.running and not mod.enabled and (not mod.frame or not mod.frame:IsShown()))
            assert(not mod.events or next(mod.events.events)==nil)
            assert(not mod.ledger or next(mod.ledger)==nil)
        end
        -- Bar choices can change while the master is off without starting observers.
        G:SetEnabled('bar3',true)
        assert(ns.db.profile.modules.SkillTrace_bar3 and not ns.modules.SkillTrace_bar3.running)
        G:SetEnabled(nil,true)
        assert(common.running and ns.modules.SkillTrace_bar3.running and not bar.running)
        assert(next(common.ledger)==nil)
        assert(db.cooldowns.spells==spells and db.frames.cooldowns==2)
        G:SetEnabled('unknown',false); G:SetEnabled('bar9',true); G:SetEnabled(nil,'false')
        assert(ns.db.profile.modules.SkillTracker and ns.db.profile.modules.unknown==nil and ns.db.profile.modules.SkillTrace_bar9==nil)
    ''')


def test_live_first_enable_in_combat_finishes_on_regen_without_reload():
    lua = trace_runtime(enabled=False)
    lua.execute('''
        local G=ns.SkillTracker
        G:SetTypeFrame('cooldowns',2)
        local bar=ns.modules.SkillTrace_bar2
        combat=true; restrictions=true
        G:SetEnabled('bar2',true)
        assert(bar.running and bar.pending and not bar.frame:IsShown())
        Advance(.3)
        combat=false; restrictions=false
        bar.events:Fire('OnEvent','PLAYER_REGEN_ENABLED')
        assert(not bar.pending and bar.frame:IsShown())
        combat=true; restrictions=true
        G:SetEnabled('bar2',false)
        assert(not bar.running and not bar.frame:IsShown())
        G:SetEnabled('bar2',true)
        assert(bar.pending)
        combat=false; restrictions=false
        bar.events:Fire('OnEvent','PLAYER_REGEN_ENABLED')
        assert(bar.running and bar.frame:IsShown())
    ''')


@pytest.mark.parametrize("fresh", [False, True])
def test_new_tracker_stays_disabled_through_real_core_startup(fresh):
    lua = trace_runtime(enabled=False)
    lua.globals().fresh = fresh
    lua.execute('''
        if fresh then DDingUIToolkitDB=nil
        else DDingUIToolkitDB={profile={modules={PartyTracker=true}}} end
        C_AddOns.GetAddOnMetadata=function() return 'test' end
        function GetRealmName() return 'Test realm' end
        StaticPopupDialogs={}
    ''')
    for path in ('Core/Core.lua', 'Modules/CooldownTrace/CooldownTrace.lua', 'Modules/CooldownTrace/Groups.lua'):
        load(lua, path)
    lua.execute('''
        ns.DDingToolKit.CreateMinimapButton=function() end
        ns.DDingToolKit:OnInitialize(); ns.DDingToolKit:OnEnable()
        assert(ns.db.profile.modules.SkillTracker==false, 'new tracking must require opt-in')
        assert(ns.db.profile.modules.PartyTracker==true)
        for _,definition in ipairs(ns.SkillTracker:Definitions()) do
            local mod=ns.modules[definition[2]]
            assert(not mod.running and not mod.events and not mod.frame)
        end
        ns.SkillTracker:SetEnabled(nil,true)
        assert(ns.modules.SkillTrace_common.running)
        ns.SkillTracker:Initialize()
        assert(ns.db.profile.modules.SkillTracker==true)
        ns.SkillTracker:SetEnabled(nil,false)
        ns.SkillTracker:Initialize()
        assert(ns.db.profile.modules.SkillTracker==false)
    ''')


def test_disabled_master_survives_real_core_startup_and_hides_edit_movers():
    lua = trace_runtime(enabled=False)
    lua.execute('''
        ns.db.profile.modules.SkillTracker=false
        ns.db.profile.modules.SkillTrace_bar2=true
        ns.db.profile.CooldownTrace.frames.cooldowns=2
        DDingUIToolkitDB={profile=ns:DeepCopy(ns.db.profile)}
        C_AddOns.GetAddOnMetadata=function() return 'test' end
        function GetRealmName() return 'Test realm' end
        StaticPopupDialogs={}
    ''')
    for path in ('Core/Core.lua', 'Modules/CooldownTrace/CooldownTrace.lua', 'Modules/CooldownTrace/Groups.lua'):
        load(lua, path)
    lua.execute('''
        ns.DDingToolKit.CreateMinimapButton=function() end
        ns.DDingToolKit:OnInitialize(); ns.DDingToolKit:OnEnable()
        assert(ns.db.profile.modules.SkillTracker==false and ns.db.profile.modules.SkillTrace_bar2)
        for _,definition in ipairs(ns.SkillTracker:Definitions()) do
            local mod=ns.modules[definition[2]]
            assert(not mod.running and not mod.events and not mod.frame)
        end
    ''')
    load_editor(lua)
    lua.execute('''
        ns.ToolkitMovers:ToggleConfigMode(); SetCombatPreview(true)
        for _,definition in ipairs(ns.SkillTracker:Definitions()) do
            local mover=_G['DDingToolKitMover_'..definition[2]]
            assert(not mover or not mover:IsShown())
        end
        ns.ToolkitMovers:ToggleConfigMode()
        ns.SkillTracker:SetEnabled(nil,true)
        local bar=ns.modules.SkillTrace_bar2
        assert(bar.running and bar.frame:IsShown() and ns.modules.SkillTrace_common.running)
        assert(not ns.modules.SkillTrace_bar3.running)
    ''')


def test_fixed_categories_merge_split_timers_and_combat_guards():
    lua = trace_runtime()
    lua.execute('''
        local G,db=ns.SkillTracker,ns.db.profile.CooldownTrace
        local common=EnableCommon()
        G:SetEnabled('bar2',true)
        local bar=ns.modules.SkillTrace_bar2
        assert(not G.Create and not G.Rename and not G.Delete and not G.SetSeparate)
        assert(not G:SetSpells('cooldowns','PRIEST',33206,true))
        assert(not G:SetSpells('common','PRIEST',10060,true))
        common:Record(common.rows[2],1719,GetTime())
        assert(G:SetTypeFrame('cooldowns',2))
        assert(bar.frame:IsShown() and bar.ledger.warrior[1719].started==GetTime())
        Advance(3)
        assert(G:SetTypeFrame('cooldowns',0))
        assert(not bar.frame:IsShown() and common.ledger.warrior[1719])
        local found
        for _,icon in ipairs(common.rows[2].icons) do
            if icon:IsShown() and icon.texture.texture==1719 then found=icon end
        end
        assert(found and found.text:GetText()=='1:27')
        -- Per-spell overrides (OmniCD Spells tab) win until the type moves onto the same frame.
        assert(G:SetSpellFrame(1719,2))
        assert(db.spellFrame[1719]==2 and #bar:Spells('WARRIOR')==1 and bar:Spells('WARRIOR')[1]==1719)
        assert(G:SetSpellFrame(1719,0) and db.spellFrame[1719]==nil)
        G:SetSpellFrame(1719,2)
        assert(G:SetTypeFrame('cooldowns',2) and db.spellFrame[1719]==nil)
        assert(G:SetSpellPriority(1719,99) and db.spellPriority[1719]==99)
        assert(G:SetTypePriority('cooldowns',99) and db.spellPriority[1719]==nil)
        G:SetTypePriority('cooldowns',35)
        combat=true; restrictions=true
        assert(select(2,G:SetTypeFrame('cooldowns',0))=='CT_GROUP_COMBAT' and db.frames.cooldowns==2)
        assert(select(2,G:SetSpellFrame(1719,0))=='CT_GROUP_COMBAT')
        assert(select(2,G:SetSpells('defensives','PRIEST',33206,false))=='CT_GROUP_COMBAT')
        assert(G:SetSpellPriority(1719,70) and G:SetSpellGlow(1719,false))
        combat=false; restrictions=false
        assert(db.defensives.spells.PRIEST[4]==33206 and db.spellGlow[1719]==false and not G:Glow(1719))
        assert(G:SetSpellGlow(1719,true) and db.spellGlow[1719]==nil)
        assert(not G:SetTypeFrame('bogus',1) and not G:SetSpellFrame(999999,1))
        assert(G:SetTypeFrame('cc',99) and db.frames.cc==8)
    ''')


def test_common_editor_saves_position_and_hides_merged_category_movers():
    lua = trace_runtime()
    load(lua, 'Config_Data.lua')
    load_editor(lua)
    lua.execute('''
        local group=EnableCommon()
        ns.ToolkitMovers:ToggleConfigMode(); SetCombatPreview(true)
        local mover=_G.DDingToolKitMover_SkillTrace_common
        assert(mover:IsShown() and group.preview)
        local hidden=_G.DDingToolKitMover_CooldownTracker
        assert(not hidden or not hidden:IsShown())
        assert(mover:GetWidth()==group.frame:GetWidth()*group.frame:GetScale())
        mover:Fire('OnClick','LeftButton'); ns.ToolkitMovers:Nudge(1,0)
        assert(group.db.position.x~=0)
        local _,_,_,x,y=group.frame:GetPoint()
        assert(x==group.db.position.x and y==group.db.position.y)
        local saved=group.db.position.x
        SetCombatPreview(false); assert(not mover:IsShown() and not group.preview)
        SetCombatPreview(true); assert(mover:IsShown())
        ns.ToolkitMovers:ToggleConfigMode()
        group:ApplySettings(); assert(group.db.position.x==saved)
        group.db.attachTo='party'; group:ApplySettings()
        ns.ToolkitMovers:ToggleConfigMode()
        assert(not mover:IsShown() and not group.preview and group.attached)
        ns.ToolkitMovers:ToggleConfigMode()
    ''')


def test_cc_catalog_alias_cast_timer_and_no_hostile_aura_as_self_buff():
    lua = trace_runtime()
    lua.execute('''
        local cc=ns.CooldownTraceEngine.New('SkillTrace_ccTest','cc')
        cc:OnEnable(); cc.enabled=true
        assert(cc.rows[2].icons[1]:IsShown())
        baseCD[46968]=0
        cc.rows[2].observer:Fire('OnEvent','UNIT_SPELLCAST_SUCCEEDED',SECRET,SECRET,46968)
        assert(cc.ledger.warrior[46968].seconds==40)
        assert(cc.rows[2].icons[1].text:GetText()=='40')
        Advance(41)
        assert(cc.rows[2].icons[1].text:GetText()=='' and not cc.rows[2].icons[1].unknown)
        units.party1={guid='hunter',class='HUNTER',name='Hunter'}; cc:RefreshRoster()
        baseCD[19577]=0
        cc.rows[2].observer:Fire('OnEvent','UNIT_SPELLCAST_SUCCEEDED',SECRET,SECRET,474421)
        assert(cc.ledger.hunter[19577].seconds==60 and not cc.ledger.hunter[474421])
        cc:Record(cc.rows[2],SECRET,GetTime())
        assert(not cc.ledger.hunter[999999])
        for _,id in ipairs({118905,132168,105421,207685,204843,374776,127797,61391}) do
            for _,category in ipairs(ns.CooldownTraceData.categories) do
                for _,catalog in pairs(ns.CooldownTraceData[category]) do
                    for _,cast in ipairs(catalog) do assert(cast~=id) end
                end
            end
        end
    ''')


def test_migration_splits_old_selections_and_preserves_archived_custom_settings():
    lua = trace_runtime(enabled=False)
    lua.execute('''
        local G,db=ns.SkillTracker,ns.db.profile.CooldownTrace
        db.frameVersion=nil
        db.groups={'group7','bad.path','group7',5,'missing'}
        db.group7={name='Imported',iconSize=41,position={x=127,y=55},
            spells={PRIEST={10060,10060,33206,999999,'10060'},BAD={10060}}}
        local archive,position=db.group7,db.group7.position
        ns.db.profile.modules.SkillTrace_group7=true
        G:Initialize()
        assert(#db.groups==4 and db.groups[1]=='common')
        assert(db.group7==archive and db.group7.position==position and position.x==127)
        assert(db.group7.iconSize==41 and #db.group7.spells.PRIEST==5)
        assert(not ns.db.profile.modules.SkillTrace_group7 and not ns.modules.SkillTrace_group7)
        assert(#db.cooldowns.spells.PRIEST==1 and db.cooldowns.spells.PRIEST[1]==10060)
        assert(#db.defensives.spells.PRIEST==1 and db.defensives.spells.PRIEST[1]==33206)
        assert(ns.db.profile.modules.CooldownTracker and ns.db.profile.modules.DefensiveTracker)
        assert(db.cooldowns.spells.BAD==nil)
        -- Shown separate groups become enabled extra bars; cc was hidden so it stays hidden on an off bar.
        assert(db.frameVersion==1 and db.frames.defensives==2 and db.frames.cooldowns==3 and db.frames.cc==4)
        local modules=ns.db.profile.modules
        assert(modules.SkillTrace_bar2 and modules.SkillTrace_bar3 and not modules.SkillTrace_bar4)
        assert(db.extraBars.bar4.redirect==false and G:DisplayFrame(46968)==nil)
        G:SetSpells('cooldowns','PRIEST',10060,false)
        G:Initialize(); assert(#db.cooldowns.spells.PRIEST==0 and db.frames.cooldowns==3)
        -- An old empty list must not resurrect the deleted cooldown/defensive selections.
        db.groups={}; G:Initialize()
        assert(#db.cooldowns.spells.PRIEST==0 and #db.defensives.spells.PRIEST==0)
        assert(db.group7==archive)
    ''')


def test_frame_migration_keeps_shown_group_layouts_on_extra_bars():
    lua = trace_runtime(enabled=False)
    lua.execute('''
        local G,db,modules=ns.SkillTracker,ns.db.profile.CooldownTrace,ns.db.profile.modules
        db.frameVersion=nil
        db.groups={'common','defensives','cooldowns','cc'}
        local d,c,x=db.defensives,db.cooldowns,db.cc
        d.separate=true; d.attachTo='party'; d.attachSide='BOTTOM'; d.columns=5; d.iconSize=28; d.scale=1; d.gapX=0; d.offsetY=4
        c.separate=true; c.position={point='CENTER',relativePoint='CENTER',x=576,y=128}; c.iconSize=33; c.scale=1
        c.columns=7; c.sortOrder='spell'; c.displayStyle='bars'; c.barWidth=260; c.align='RIGHT'; c.grow='UP'
        x.separate=false
        modules.DefensiveTracker=true; modules.CooldownTracker=true; modules.SkillTrace_cc=true
        local spells=c.spells
        G:Initialize()
        assert(db.frames.defensives==2 and db.frames.cooldowns==3 and db.frames.cc==0)
        assert(modules.SkillTrace_bar2 and modules.SkillTrace_bar3 and modules.SkillTrace_common)
        local b2,b3=db.extraBars.bar2,db.extraBars.bar3
        assert(b2.unitBar and b2.anchor=='TOPLEFT' and b2.attach=='BOTTOMLEFT' and b2.offsetY==4)
        assert(b2.layout=='horizontal' and not b2.progressBar and b2.columns==5 and b2.paddingX==0)
        assert(math.abs(b2.scale-.78)<.001 and b2.name==ns.L.CT_CATEGORY_DEFENSIVES and b2.locked)
        -- Same screen spot: 576 at scale 1 becomes 576/0.92 at the bar scale.
        assert(b3.position.x==626.1 and b3.position.y==139.1 and b3.position~=c.position and b3.scale==.92)
        assert(b3.layout=='vertical' and b3.progressBar and b3.sortBy=='priority' and b3.statusBarWidth==227)
        assert(b3.growUpward and b3.growLeft and b3.name==ns.L.CT_CATEGORY_COOLDOWNS)
        assert(c.spells==spells and c.position.x==576 and d.attachTo=='party')
        -- Runs once: later edits survive the next login.
        G:SetTypeFrame('defensives',0); G:Initialize()
        assert(db.frames.defensives==0 and db.frames.cooldowns==3)
        -- A profile that showed nothing starts with everything on the party frame.
        db.frameVersion=nil; db.frames.cooldowns=5
        modules.DefensiveTracker=false; modules.CooldownTracker=false; modules.SkillTrace_cc=false
        G:Initialize()
        assert(db.frames.cooldowns==0 and db.frames.defensives==0 and db.frames.cc==0)
    ''')


def test_group_route_control_and_common_spell_picker_edit_fixed_categories():
    for locale in ('koKR', 'enUS'):
        lua = trace_runtime(locale)
        load(lua, 'Config_Data.lua')
        load(lua, 'UI/Controls.lua')
        lua.execute('''
            local G,db=ns.SkillTracker,ns.db.profile.CooldownTrace
            local common=EnableCommon()
            local host=CreateFrame('Frame',nil,UIParent); host:SetSize(600,600)
            local list=common:CreateSpellList(host)
            list:SetWidth(560); list:Fire('OnSizeChanged',560,600)
            list.classPicker:SetValue('PRIEST')
            list.categoryPicker:SetValue('defensives',false)
            local function Row(id)
                for _,row in ipairs(list.rows) do if row:IsShown() and row.spellID==id then return row end end
            end
            local row=Row(47788)
            assert(row and row.frame:GetValue()==0 and row.priority:GetValue()==60 and row.glow:GetChecked())
            row.frame:SetValue(2)
            assert(db.spellFrame[47788]==2 and G:Frame(47788)==2)
            assert(row.frame.valueBox.textColor[1]==DDingUI_StyleLib.GetAccent('MJToolkit')[1])
            row.priority:SetValue(50); assert(db.spellPriority[47788]==50)
            row.glow:Fire('OnClick','LeftButton'); assert(db.spellGlow[47788]==false)
            row.check:Fire('OnClick','LeftButton')
            assert(not G:IsSelected(47788,'PRIEST') and row.frame._disabled and row.icon.alpha<1)
            row.check:Fire('OnClick','LeftButton'); assert(G:IsSelected(47788,'PRIEST') and not row.frame._disabled)
            combat=true; restrictions=true
            row.frame:SetValue(4)
            assert(db.spellFrame[47788]==2 and row.frame:GetValue()==2)
            combat=false; restrictions=false
            list.clearSpells:Fire('OnClick','LeftButton')
            for _,category in ipairs(ns.CooldownTraceData.categories) do
                for class in pairs(ns.CooldownTraceData[category]) do assert(#db[category].spells[class]==0) end
            end
            assert(next(db.spellFrame)==nil and next(db.spellPriority)==nil and next(db.spellGlow)==nil)
            assert(not common.frame:IsShown())
            list.resetSpells:Fire('OnClick','LeftButton')
            for _,category in ipairs(ns.CooldownTraceData.categories) do
                assert(#db[category].spells.PRIEST==#ns.CooldownTraceData[category].PRIEST)
            end
            assert(common.frame:IsShown() and row.check:GetChecked())
            local head=list.header
            assert(head.frame.text==ns.L.CT_TAB_FRAME and head.priority.text==ns.L.CT_TAB_PRIORITY and head.glow.text==ns.L.CT_COLUMN_GLOW)
        ''')


def test_saved_groups_migrate_before_real_core_startup():
    lua = trace_runtime(enabled=False)
    lua.execute('''
        local db=ns.db.profile.CooldownTrace
        db.frameVersion=nil
        db.groups={'group1'}
        db.group1={name='Saved',spells={PRIEST={10060,33206}},position={x=127,y=55},iconSize=38}
        ns.db.profile.modules.SkillTracker=nil
        ns.db.profile.modules.SkillTrace_group1=true
        DDingUIToolkitDB={profile=ns:DeepCopy(ns.db.profile)}
        C_AddOns.GetAddOnMetadata=function() return 'test' end
        function GetRealmName() return 'Test realm' end
        StaticPopupDialogs={}
    ''')
    for path in ('Core/Core.lua', 'Modules/CooldownTrace/CooldownTrace.lua', 'Modules/CooldownTrace/Groups.lua'):
        load(lua, path)
    lua.execute('''
        ns.DDingToolKit.CreateMinimapButton=function() end
        ns.DDingToolKit:OnInitialize(); ns.DDingToolKit:OnEnable()
        local m=ns.modules
        assert(m.SkillTrace_bar2.running and m.SkillTrace_bar3.running and m.SkillTrace_common.running)
        assert(not m.SkillTrace_bar4.running and not m.SkillTrace_group1 and not m.SkillTrace_cc)
        local db=ns.db.profile.CooldownTrace
        assert(db.group1.position.x==127 and db.group1.iconSize==38)
        assert(#db.cooldowns.spells.PRIEST==1 and #db.defensives.spells.PRIEST==1)
        assert(db.frames.defensives==2 and db.frames.cooldowns==3)
    ''')


def test_1215_retired_casts_leave_catalog_and_saved_fixed_selections():
    lua = trace_runtime(enabled=False)
    lua.execute('''
        local retired={DEATHKNIGHT={63560},DRUID={197721},PRIEST={246287,64901,265202},
            SHAMAN={198067,192249,108270},EVOKER={374348},MAGE={414660},MONK={122278,122783}}
        local G,data=ns.SkillTracker,ns.CooldownTraceData
        local group=ns.db.profile.CooldownTrace.cooldowns
        group.iconSize,group.position.x=41,127
        local position=group.position
        for class,ids in pairs(retired) do
            for _,id in ipairs(ids) do
                for _,kind in ipairs(data.categories) do
                    for _,current in ipairs(data[kind][class]) do assert(current~=id) end
                    assert(not G:SetSpells(kind,class,id,true))
                end
                assert(not data.auraIDs[id] and not data.noEstimate[id])
            end
            group.spells[class]={unpack(ids)}
            table.insert(group.spells[class],data.cooldowns[class][1])
        end
        G:Initialize()
        assert(group.position==position and group.iconSize==41 and position.x==127)
        for class in pairs(retired) do assert(#group.spells[class]==1) end
        for class,id in pairs({DEATHKNIGHT=1233448,PRIEST=472433,MONK=123904,MAGE=12051}) do
            assert(G:SetSpells('cooldowns',class,id,true))
        end
        assert(G:SetSpells('defensives','MONK',115203,true))
        assert(G:SetSpells('defensives','EVOKER',363916,true))
    ''')


def test_defaults_existing_settings_and_toc_order():
    lua = trace_runtime(enabled=False)
    lua.execute('''
        assert(ns.defaults.profile.modules.CooldownTracker==false)
        assert(ns.defaults.profile.modules.DefensiveTracker==false)
        assert(ns.defaults.profile.PartyTracker and ns.defaults.profile.RaidDefensiveTracker)
        local old={cooldowns={iconSize=37,scale=.8,position={point='CENTER',x=101,y=-42}},
            defensives={iconSize=25,scale=1.2,position={point='CENTER',x=-33,y=19}}}
        local position=old.cooldowns.position
        ns:MergeDefaults(old,ns.defaults.profile.CooldownTrace)
        assert(old.cooldowns.position==position and position.x==101 and position.y==-42)
        assert(old.cooldowns.iconSize==37 and old.cooldowns.scale==.8)
        assert(old.cooldowns.attachTo=='screen' and old.defensives.columns==8)
    ''')
    toc = (ROOT / "DDingUI_Toolkit.toc").read_text(encoding="utf-8-sig")
    assert toc.index("Modules\\CooldownTrace\\Data.lua") < toc.index("Modules\\CooldownTrace\\CooldownTrace.lua")
    for category in ("cooldowns", "defensives", "cc"):
        data = lua.globals().ns.CooldownTraceData[category]
        assert len(list(data.keys())) == 13
        for _, spells in data.items():
            assert len(spells) <= 12
    source = (ROOT / "Modules/CooldownTrace/CooldownTrace.lua").read_text(encoding="utf-8")
    assert "COMBAT_LOG_EVENT" not in source and "SendAddonMessage" not in source


def test_loading_during_restrictions_retries_containers_after_combat():
    lua = trace_runtime(enabled=False)
    lua.execute('''
        restrictions=true
        T:OnEnable()
        assert(T.running and T.frame:IsShown() and T.rows[1].container==nil)
        assert(T.containerUnavailable)
        restrictions=false; loadFails=true
        T.events:Fire('OnEvent','PLAYER_REGEN_ENABLED')
        assert(T.rows[1].container==nil)
        loadFails=false
        T.events:Fire('OnEvent','PLAYER_REGEN_ENABLED')
        assert(T.rows[1].container and not T.containerUnavailable)
        T:EnterEditPreview()
        combat=true
        T.events:Fire('OnEvent','PLAYER_REGEN_DISABLED')
        assert(not T.preview and not T.rows[1].previewActive:IsShown())
    ''')


def test_grid_wrap_alignment_growth_spacing_and_sort_order():
    lua = trace_runtime()
    lua.execute('''
        local db=T.db
        db.columns=2; db.align='RIGHT'; db.gapX=7; db.gapY=9; db.rowSpacing=10
        T:ApplySettings(); T:EnterEditPreview()
        local row=T.rows[2]
        T:LayoutRow(row,3,24)
        local _,_,_,x,y=row.icons[3]:GetPoint()
        assert(x==43 and y==-52 and row:GetHeight()==95)
        assert(row.badge==nil)
        db.align='CENTER'; db.grow='UP'; T:ApplySettings(); T:LayoutRow(row,3,24)
        _,_,_,x,y=row.icons[3]:GetPoint()
        assert(x==21.5 and y==-7)
        local _,_,_,_,firstY=row.icons[1]:GetPoint()
        assert(firstY==-52)
        assert(D.columns==8 and D.gapX==3)
        T:ExitEditPreview()
        T:Record(T.rows[2],107574,GetTime()); Advance(2)
        T:Record(T.rows[2],1719,GetTime())
        assert(T.rows[2].icons[1].texture.texture==1719)
        db.sortOrder='spell'; T:ApplySettings()
        assert(T.rows[2].icons[1].texture.texture==107574)
        db.columns=100; db.gapX=-1; db.gapY=0/0; db.scale=math.huge
        T:ApplySettings()
        assert(T.columns==12 and T.gapX==0 and T.gapY==4 and T.frame:GetScale()==1)
        db.gapY=0; db.rowSpacing=0; T:ApplySettings(); T:LayoutRow(row,12,24)
        local _,_,_,_,top=row.icons[1]:GetPoint()
        assert(-top+T.size<=row:GetHeight())
    ''')


def test_selected_ally_list_counts_down_from_detected_casts_and_self_has_internal_fallback():
    lua = trace_runtime()
    lua.execute('''
        local row=T.rows[2]
        for index,id in ipairs(T:Spells(row.class)) do
            assert(row.icons[index]:IsShown() and row.icons[index].texture.texture==id)
            assert(row.icons[index].unknown and not row.icons[index].cooldown.cd)
        end
        baseCD[1719]=90000
        combat=true; restrictions=true
        row.observer:Fire('OnEvent','UNIT_SPELLCAST_SUCCEEDED','party1',SECRET,1719)
        local icon=row.icons[1]
        assert(icon.texture.texture==1719 and icon.text:GetText()=='1:30')
        assert(icon.cooldown.cd[1]==10 and icon.cooldown.cd[2]==90)
        Advance(30); assert(icon.text:GetText()=='1:00')
        row.observer:Fire('OnEvent','UNIT_SPELLCAST_SUCCEEDED','party1',SECRET,SECRET)
        assert(T.ledger.warrior[1719].started==10)
        Advance(60)
        assert(icon:IsShown() and not icon.unknown and icon.text:GetText()=='' and not icon.cooldown.cd)
        row.observer:Fire('OnEvent','UNIT_SPELLCAST_SUCCEEDED','party1',SECRET,1719)
        assert(icon.text:GetText()=='1:30' and icon.cooldown.cd[1]==100)
        -- A secret native cooldown cannot be read; a public cast can still start our timer.
        known[10060]=true; cooldowns[10060]={isActive=SECRET,isEnabled=SECRET}
        T.rows[1].observer:Fire('OnEvent','UNIT_SPELLCAST_SUCCEEDED','player',SECRET,10060)
        assert(T.rows[1].icons[1].text:GetText()=='2:00')
        assert(T.rows[1].icons[1].cooldown.cd[2]==120)
        T:Reset()
        assert(icon:IsShown() and icon.unknown and not icon.cooldown.cd)
        assert(next(T.ledger)==nil)
    ''')


def test_kira_colors_follow_cooldowns_without_changing_unknown_opacity_or_saved_keys():
    lua = trace_runtime()
    lua.execute('''
        local cc=ns.CooldownTraceEngine.New('SkillTrace_ccTest','cc')
        cc:OnEnable(); cc.enabled=true
        for _,mod in ipairs({D,T,cc}) do
            local db=mod.db
            local keys={}; for k in pairs(db) do keys[k]=true end
            local position,spells=db.position,db.spells
            db.unknownAlpha=.35; db.showNumbers=true
            for _,style in ipairs({'icons','bars'}) do
                db.displayStyle=style; mod:ApplySettings(); mod:Reset()
                local row=mod.rows[2]
                local id
                for _,spell in ipairs(mod:Spells(row.class)) do
                    if ns.CooldownTraceSensor.Seconds(spell) then id=spell; break end
                end
                if id then
                    local icon=row.icons[1]
                    assert(icon.unknown and not icon.texture.desaturated and icon.alpha==.35)
                    if style=='bars' then assert(icon.bar:GetValue()==1) end
                    mod:Record(row,id,GetTime()); icon=row.icons[1]
                    assert(not icon.unknown and icon.texture.desaturated and icon.alpha==1)
                    assert(icon.text:GetText()~='')
                    db.showNumbers=false; db.showSwipe=false; mod:ApplySettings()
                    assert(icon.texture.desaturated and icon.text:GetText()=='' and not icon.cooldown.drawSwipe)
                    Advance(120)
                    assert(not icon.texture.desaturated and icon.alpha==1 and not icon.cooldown.cd)
                    db.showNumbers=true; db.showSwipe=true
                end
                mod:EnterEditPreview()
                assert(mod.rows[1].icons[1].texture.desaturated)
                assert(not mod.rows[1].icons[2].texture.desaturated)
                mod:ExitEditPreview()
            end
            assert(db.position==position and db.spells==spells)
            for k in pairs(db) do assert(keys[k]) end
        end
        known[10060]=true; T:ApplySettings()
        local icon=T.rows[1].icons[1]
        cooldowns[10060]={isActive=true}; T:UpdateCooldowns()
        assert(icon.texture.desaturated and icon.cooldown.durationObject==nativeDuration)
        cooldowns[10060]={isActive=false,isEnabled=true}; T:UpdateCooldowns()
        assert(not icon.texture.desaturated and not icon.cooldown.durationObject)
        cooldowns[10060]={isActive=SECRET,isEnabled=SECRET}; T:UpdateCooldowns()
        assert(icon.unknown and not icon.texture.desaturated and icon.alpha==.35)
    ''')


def test_catalog_fallbacks_and_kira_buff_ids_keep_public_evidence_and_charge_limits():
    lua = trace_runtime()
    lua.execute('''
        local data=ns.CooldownTraceData
        local catalog={}
        for _,kind in ipairs(data.categories) do
            for _,spells in pairs(data[kind]) do
                for _,id in ipairs(spells) do catalog[id]=true end
            end
        end
        for id,seconds in pairs(data.baseCooldowns) do
            assert(catalog[id] and type(seconds)=='number' and seconds>1.5)
        end
        for _,value in ipairs({0,SECRET}) do
            T:Reset(); baseCD[1719]=value
            T:Record(T.rows[2],1719,GetTime())
            assert(T.ledger.warrior[1719].seconds==90)
        end
        baseFails=true; T:Reset()
        T:Record(T.rows[2],107574,GetTime())
        assert(T.ledger.warrior[107574].seconds==nil) -- no invented fallback
        GetSpellBaseCooldown=nil; T:Reset()
        T:Record(T.rows[2],1719,GetTime())
        assert(T.ledger.warrior[1719].seconds==90)
        units.party1={guid='mage',class='MAGE',name='mage'}; D:RefreshRoster()
        auraSecrecy[342246]=0
        publicAuras.party1={[342246]={sourceUnit='player',duration=10,expirationTime=20}}
        D:ScanAuras(D.rows[2]); assert(D.ledger.mage==nil)
        publicAuras.party1={}; D:ScanAuras(D.rows[2])
        publicAuras.party1={[342246]={sourceUnit='party1',duration=10,expirationTime=20}}
        D:ScanAuras(D.rows[2]); assert(D.ledger.mage[342245].seconds==60)
    ''')


def test_follower_and_player_lists_assume_ready_until_a_detected_cast():
    lua = trace_runtime()
    lua.execute('''
        followerDungeon=true; units.party1.isPlayer=false
        units.party1.guid='Creature-0-1-2-3-4-5'
        for _,mod in ipairs({T,D}) do
            mod:RefreshRoster()
            local row=mod.rows[2]
            assert(row.guid==units.party1.guid and mod.ledger[row.guid]==nil)
            for index,id in ipairs(mod:Spells('WARRIOR')) do
                local icon=row.icons[index]
                assert(icon:IsVisible() and icon.texture.texture==id)
                assert(icon.unknown and not icon.texture.desaturated and not icon.cooldown.cd)
                assert(icon.text:GetText()=='')
            end
            assert(mod.rows[3].icons[1]:IsShown() and mod.rows[3].icons[1].unknown)
            local id=mod:Spells('WARRIOR')[2]
            row.observer:Fire('OnEvent','UNIT_SPELLCAST_SUCCEEDED',row.unit,nil,id)
            assert(mod.ledger[row.guid][id] and not row.icons[1].unknown)
            mod:Reset()
            assert(row.icons[1]:IsVisible() and row.icons[1].unknown and next(mod.ledger)==nil)
        end
        for _,value in ipairs({true, SECRET}) do
            units.party1.isPlayer=value
            T:RefreshRoster(); assert(T.rows[2].icons[1]:IsShown() and T.rows[2].icons[1].unknown)
        end
        units.party1.isPlayer=false; followerDungeon=SECRET
        T:RefreshRoster(); assert(T.rows[2].icons[1]:IsShown() and T.rows[2].icons[1].unknown)
        followerDungeon=false
        T:RefreshRoster(); assert(T.rows[2].icons[1]:IsShown() and T.rows[2].icons[1].unknown)
        followerDungeon=true; T:RefreshRoster()
        units.party1=nil; T:RefreshRoster()
        assert(not T.rows[2]:IsShown())
        units.party1={guid='replacement',class='WARRIOR',name='교체된 파티원'}
        T:RefreshRoster(); assert(T.rows[2].icons[1]:IsShown() and T.rows[2].icons[1].unknown)
    ''')


def test_party_zero_offsets_touch_icon_edges_for_all_sides_and_short_rows():
    lua = trace_runtime()
    lua.execute('''
        local anchor=CreateFrame('Button',nil,UIParent)
        anchor.unit='player'; anchor:SetSize(120,40); anchor:SetPoint('CENTER',UIParent,'CENTER')
        CompactPartyFrame={memberUnitFrames={anchor}}
        T.db.attachTo='party'; T.db.offsetX=0; T.db.offsetY=0; T.db.scale=1
        T.db.spells={}
        local spells={228260,10060,263165,421453,472433,64843,200183,47585,19236,586}
        for _,side in ipairs({'LEFT','RIGHT','TOP','BOTTOM'}) do
            for _,align in ipairs({'LEFT','CENTER','RIGHT'}) do
                for _,grow in ipairs({'UP','DOWN'}) do
                    for _,count in ipairs({1,3,10}) do
                        T.db.attachSide=side; T.db.align=align; T.db.grow=grow
                        T.db.spells.PRIEST={}; wipe(known)
                        for i=1,count do T.db.spells.PRIEST[i]=spells[i]; known[spells[i]]=true end
                        T:ApplySettings()
                        local row=T.rows[1]
                        local x,y,w,h=row.icons[1]:Rect()
                        local ax,ay,aw,ah=anchor:Rect()
                        if side=='LEFT' then assert(x+w==ax and y+h/2==ay+ah/2)
                        elseif side=='RIGHT' then assert(x==ax+aw and y+h/2==ay+ah/2)
                        else
                            local left,bottom,width,height=row:Rect()
                            assert(left+width/2==ax+aw/2)
                            if side=='TOP' then assert(bottom==ay+ah)
                            else assert(bottom+height==ay) end
                            local edge=row.icons[grow=='UP' and 1 or count]
                            local _,ey,_,eh=edge:Rect()
                            if side=='TOP' then assert(ey==ay+ah)
                            else
                                edge=row.icons[grow=='UP' and count or 1]
                                _,ey,_,eh=edge:Rect(); assert(ey+eh==ay)
                            end
                        end
                        if count>1 and side=='LEFT' then
                            assert(select(1,row.icons[2]:Rect())<x) -- Icons extend away from the frame.
                            if count==10 then
                                local spare=(T.columns-2)*(T.size+T.gapX)
                                local expected=align=='RIGHT' and spare or align=='CENTER' and spare/2 or 0
                                assert(select(4,row.icons[count]:GetPoint())==expected)
                            end
                        end
                    end
                end
            end
        end
    ''')


def test_party_attachment_matches_sorted_units_and_preserves_screen_position():
    lua = trace_runtime()
    lua.execute('''
        CompactPartyFrame={memberUnitFrames={}}
        for i,unit in ipairs({'party2','player','party1'}) do
            local f=CreateFrame('Button',nil,UIParent)
            f.unit=unit; f:SetSize(120,40); f:SetPoint('CENTER',UIParent,'CENTER',-300,200-i*100)
            CompactPartyFrame.memberUnitFrames[i]=f
        end
        local position=T.db.position
        T.db.attachTo='party'; T.db.offsetX=13; T.db.offsetY=-4
        T:ApplySettings()
        local row=T.rows[2]
        assert(row.anchor==CompactPartyFrame.memberUnitFrames[3])
        local p,anchor,rp,x,y=row:GetPoint()
        assert(p=='TOPLEFT' and rp=='RIGHT' and x==13 and y==-4+36/2)
        assert(anchor.unit=='party1' and row.badge==nil)
        for side,point in pairs({LEFT='TOPRIGHT',TOP='BOTTOM',BOTTOM='TOP'}) do
            T.db.attachSide=side; T:ApplySettings()
            assert(row:GetPoint()==point)
        end
        T.db.attachSide='RIGHT'; T.db.grow='UP'; T:ApplySettings()
        p,_,_,_,y=row:GetPoint(); assert(p=='BOTTOMLEFT' and y==-4-18)
        T.db.grow='DOWN'; T:ApplySettings()
        anchor:Hide(); T:UpdateCooldowns(); assert(not row:IsShown())
        anchor:Show(); T:RefreshAnchors(); T:UpdateCooldowns(); assert(row:IsShown())
        T.db.attachTo='screen'; T:ApplySettings()
        assert(T.db.position==position and position.x==-260)
        assert(row.badge==nil and select(4,row.icons[1]:GetPoint())==0)
        assert(select(2,row:GetPoint())==T.frame)
    ''')


def test_party_rebinding_and_setting_changes_wait_for_combat():
    lua = trace_runtime()
    lua.execute('''
        local f=CreateFrame('Button',nil,UIParent); f.unit='party1'
        PartyFrame={MemberFrame1=f}
        T.db.attachTo='party'; T:ApplySettings()
        local row=T.rows[2]
        assert(row.anchor==f and row:IsShown())
        local clear=row.ClearAllPoints
        row.ClearAllPoints=function(self) assert(not combat); return clear(self) end
        combat=true
        T.db.columns=2; T.db.attachSide='LEFT'; T:ApplySettings()
        assert(T.columns==8 and T.pending)
        T:Record(row,1719,GetTime()); Advance(2)
        assert(row.anchor==f and row:IsShown())
        f.unit='party2'; T:UpdateCooldowns(); assert(not row:IsShown())
        combat=false
        T.events:Fire('OnEvent','PLAYER_REGEN_ENABLED')
        assert(T.columns==2 and not T.pending and row.anchor==nil)
        f.unit='party1'; Advance(2)
        assert(row.anchor==f and row:IsShown() and row:GetPoint()=='TOPRIGHT')
        T:EnterEditPreview(); assert(T.preview and not T.attached)
        combat=true; T.events:Fire('OnEvent','PLAYER_REGEN_DISABLED')
        assert(T.suspended and not T.preview and not T.frame:IsShown())
        combat=false; T.events:Fire('OnEvent','PLAYER_REGEN_ENABLED')
        assert(not T.suspended and T.attached and T.frame:IsShown())
    ''')


def test_party_native_player_library_fallback_and_secret_unit():
    lua = trace_runtime()
    lua.execute('''
        PlayerFrame=CreateFrame('Button',nil,UIParent); PlayerFrame.unit='player'
        local custom=CreateFrame('Button',nil,UIParent); custom.unit='party1'
        local lib=LibStub:NewLibrary('LibGetFrame-1.0',78)
        lib.GetUnitFrame=function(unit,options)
            assert(options.ignorePlayerFrame==false)
            if unit=='party1' then return custom end
            error('unavailable')
        end
        T.db.attachTo='party'; T:ApplySettings()
        assert(T.rows[1].anchor==PlayerFrame and T.rows[2].anchor==custom)
        custom.GetAttribute=function() return SECRET end
        T:RefreshAnchors(); T:UpdateCooldowns()
        assert(T.rows[2].anchor==nil and not T.rows[2]:IsShown())
        PlayerFrame:Hide(); T:RefreshAnchors(); T:UpdateCooldowns()
        assert(not T.rows[1]:IsShown())
    ''')


def test_layout_controls_are_independent_and_party_mode_hides_screen_mover():
    lua = trace_runtime()
    load(lua, 'Config_Data.lua')
    load_editor(lua)
    lua.execute('''
        local tree=ns:InitConfigTree()
        local function SettingsSection(panel)
            local list,headers={},0
            for _,s in ipairs(panel.settings) do
                if s.type=='header' then headers=headers+1 elseif headers==1 and (s.barPage or 0)==0 then list[#list+1]=s end
            end
            return list
        end
        do
            local settings={}
            for _,setting in ipairs(FlatSettings(SettingsSection(tree.panels.skilltracker))) do
                if setting.key then settings[setting.key:match('([^.]+)$')]=setting end
            end
            assert(settings.columns and settings.align and settings.sortOrder and settings.grow)
            assert(settings.gapX and settings.gapY and settings.rowSpacing)
            assert(not settings.attachSide.visible())
        end
        local common=EnableCommon()
        local position=common.db.position
        common.db.attachTo='party'; common:ApplySettings()
        ns.ToolkitMovers:ToggleConfigMode()
        SetCombatPreview(true)
        local mover=_G.DDingToolKitMover_SkillTrace_common
        assert(not mover or not mover:IsShown())
        assert(not common.preview and common.db.position==position)
        ns.ToolkitMovers:ToggleConfigMode()
        position=T.db.position
        T.db.attachTo='party'; T:ApplySettings()
        T:EnterEditPreview(); assert(T.preview and not T.attached)
        T:ExitEditPreview(); assert(T.attached and T.db.position==position)
    ''')


def test_preview_shows_swipe_ready_without_text_and_glowing_active_duration():
    lua = trace_runtime()
    load(lua, 'Config_Data.lua')
    lua.execute('''
        local tree=ns:InitConfigTree()
        for index,mod in ipairs({T,D}) do
            mod:EnterEditPreview()
            local row=mod.rows[1]
            assert(row.icons[1].cooldown.drawSwipe and row.icons[1].cooldown.cd[2]==120)
            assert(row.icons[1].text:GetText()=='42' and not row.icons[1]._PixelGlow)
            assert(row.icons[2].text:GetText()=='' and not row.icons[2].cooldown.cd)
            assert(row.previewActive.glow:IsVisible())
            assert(row.previewActive.cooldown.cd[2]==12 and row.previewActive.cooldown.reverse)
            assert(not row.previewActive.cooldown.hideNumbers and row.previewActive.text:GetText()=='')
            assert(row.previewActive:GetParent()==row.icons[1])
            assert(select(2,row.previewActive:GetPoint())==row.icons[1].texture)
            assert(row.previewActive:GetFrameLevel()>row.icons[1].cooldown:GetFrameLevel())
            local headers={}
            for _,setting in ipairs(tree.panels.skilltracker.settings) do
                if setting.type=='header' then headers[#headers+1]=setting.label end
            end
            assert(#headers==2 and headers[1]==ns.L.CT_TAB_BARS and headers[2]==ns.L.CT_TRACKED_SPELLS)
            assert(tree.panels.skilltracker.compact)
            mod:ExitEditPreview()
            assert(not row.previewActive.glow:IsVisible())
        end
        known[10060]=true
        T:UpdateCooldowns()
        local icon=T.rows[1].icons[1]
        assert(icon.text:GetText()=='' and not icon.cooldown.cd and not icon.cooldown.hideNumbers)
    ''')


def test_spell_picker_matches_catalog_tooltips_loading_and_category_selection():
    for locale in ('koKR', 'enUS'):
        lua = trace_runtime(locale, enabled=False)
        load(lua, 'Config_Data.lua')
        load(lua, 'UI/Controls.lua')
        load(lua, 'UI/Dropdown.lua')
        lua.execute('''
            local host=CreateFrame('Frame',nil,UIParent)
            host:SetSize(560,500)
            LOCALIZED_CLASS_NAMES_MALE={PRIEST='Priest'}
            local tooltipID
            GameTooltip.SetSpellByID=function(_,id) tooltipID=id end
            local getInfo=C_Spell.GetSpellInfo
            local missing,requests=true,0
            C_Spell.GetSpellInfo=function(id)
                if missing and id==10060 then return nil end
                return getInfo(id)
            end
            C_Spell.RequestLoadSpellData=function(id) assert(id==10060); requests=requests+1 end
            local G,data=ns.SkillTracker,ns.CooldownTraceData
            local tree=ns:InitConfigTree()
            local settings=tree.panels.skilltracker.settings
            local list=settings[#settings].render(host)
            list:SetWidth(540)
            assert(list.classPicker:GetValue()=='PRIEST')
            local common=ns.modules.SkillTrace_common
            for _,kind in ipairs(data.categories) do
                local db=ns.db.profile.CooldownTrace[kind]
                local position=db.position
                list.categoryPicker:SetValue(kind,false)
                for class,spells in pairs(data[kind]) do
                    -- Exercise the same callback used by a real class chip.
                    list.classPicker:SetValue(class, false)
                    for i,row in ipairs(list.rows) do
                        assert(row:IsShown()==(spells[i]~=nil))
                        if spells[i] then
                            assert(row.spellID==spells[i] and row.id==nil)
                            assert(row.icon.texture==spells[i] and row.name:GetText()~='')
                            assert(row.frame:GetValue()==G:Frame(spells[i]) and row.priority:GetValue()==G:Priority(spells[i]))
                        end
                    end
                end
                list.classPicker:SetValue('PRIEST', false)
                local first=list.rows[1]
                for _,o in ipairs(objects) do
                    if o.parent==first and o:GetScript('OnEnter') and not o.box and not o.slider then o:Fire('OnEnter') end
                end
                assert(tooltipID==first.spellID)
                if kind=='cooldowns' then
                    local row=list.rows[2]
                    assert(requests>0 and row.name:GetText()=='…')
                    local count=requests
                    list:Fire('OnEvent','SPELL_DATA_LOAD_RESULT',10060,false)
                    list:Fire('OnEvent','SPELL_DATA_LOAD_RESULT',1,true)
                    assert(requests==count)
                    missing=false
                    list:Fire('OnEvent','SPELL_DATA_LOAD_RESULT',10060,true)
                    assert(row.name:GetText()==getInfo(10060).name)
                end
                list:Hide(); list:Show()
                assert(db.position==position and not common.running and not common.frame and not common.events)
                assert(db.class==nil and db.spells)
                assert(first.spellID==data[kind].PRIEST[1])
                local selectedID=first.spellID
                first.check:Fire('OnClick','LeftButton')
                assert(not G:IsSelected(selectedID,'PRIEST'))
                for _,id in ipairs(common:Spells('PRIEST')) do assert(id~=selectedID) end
                -- Unselected spells are dimmed; hovering must not undo it.
                first.check:Fire('OnEnter'); first.check:Fire('OnLeave')
                assert(first.icon.alpha<1 and first.frame._disabled and first.priority._disabled and first.glow._disabled)
                combat=true; restrictions=true
                first.check:Fire('OnClick','LeftButton')
                assert(not first.check:GetChecked() and not G:IsSelected(selectedID,'PRIEST'))
                combat=false; restrictions=false
                first.check:Fire('OnClick','LeftButton')
                assert(first.check:GetChecked() and G:IsSelected(selectedID,'PRIEST'))
                assert(db.position==position)
            end
        ''')


def test_settings_cards_keep_fields_visibility_and_reset_position():
    for locale in ('koKR', 'enUS'):
        lua = trace_runtime(locale, enabled=False)
        load(lua, 'Config_Data.lua')
        load(lua, 'UI/Controls.lua')
        lua.execute('''
            local host=CreateFrame('Frame',nil,UIParent)
            host:SetSize(430,258)
            assert(not T.CreateSettingsPreview)
            local tree=ns:InitConfigTree()
            local function SettingsSection(panel)
            local list,headers={},0
            for _,s in ipairs(panel.settings) do
                if s.type=='header' then headers=headers+1 elseif headers==1 and (s.barPage or 0)==0 then list[#list+1]=s end
            end
            return list
        end
            do
                local section=SettingsSection(tree.panels.skilltracker)
                local cards={}
                for _,s in ipairs(section) do if s.type=='card' then cards[#cards+1]=s end end
                assert(#cards==8 and cards[1].label==ns.L.CT_POSITION_SETTINGS)
                assert(cards[2].label==ns.L.CT_LAYOUT_SETTINGS and cards[3].label==ns.L.CT_ICON_SETTINGS)
                local fields={}
                for _,s in ipairs(FlatSettings(section)) do
                    if s.key then fields[s.key:match('([^.]+)$')]=s end
                    if s.positionButtons then fields.edit=s; fields.reset=s end
                end
                assert(fields.attachTo.type=='segmented' and fields.edit.visible() and fields.reset.visible())
                assert(fields.align.type=='segmented' and fields.grow.type=='segmented' and fields.sortOrder.type=='segmented')
                local kind='common'
                local db=ns.db.profile.CooldownTrace[kind]
                local position=db.position
                position.x=777; position.y=55
                local host2=CreateFrame('Frame',nil,UIParent); host2:SetWidth(300)
                local buttons=fields.reset.render(host2,fields.reset)
                assert(buttons.edit.label.text==ns.L.CT_EDIT_POSITION and buttons.reset.label.text==ns.L.RESET_POSITION)
                buttons.reset:Fire('OnClick','LeftButton')
                assert(db.position==position and position.x==ns.defaults.profile.CooldownTrace[kind].position.x)
                assert(position.y==-180)
                db.attachTo='party'
                assert(not fields.edit.visible() and not fields.reset.visible() and fields.attachSide.visible())
                assert(not fields.rowSpacing.visible() and fields.offsetX.visible())
            end
            local row=ns.ToolkitControls.CreateSegmentedControl(host,'MJToolkit','',{
                {text=ns.L.CT_SCREEN,value='screen'}, {text=ns.L.CT_PARTY_FRAME,value='party'},
            },'screen',{onChange=function(v) selected=v end})
            for _,width in ipairs({360,560,710}) do
                row:SetWidth(width); row:Fire('OnSizeChanged',width,64)
                assert(row.buttons[1]:GetWidth()+row.buttons[2]:GetWidth()==width)
            end
            row.buttons[2]:Fire('OnClick','LeftButton')
            assert(selected=='party' and row:GetValue()=='party')
            row.buttons[1]:Fire('OnClick','RightButton')
            assert(selected=='party')
        ''')


def test_effect_options_configure_existing_and_new_aura_slots_without_reading_secrets():
    lua = trace_runtime()
    lua.execute('''
        local db=T.db
        local position,spells,ledger=db.position,db.spells,T.ledger
        local old=EffectSlot(T.rows[2],107574).buttons[1]
        old:Show()
        db.activeGlow=false; db.showSwipe=false; db.showNumbers=false
        db.glowPulse=false; db.glowThickness=5; db.glowSpeed=1.2; db.glowColor={.2,.3,.4,.5}
        T:ApplySettings()
        assert(not old.glow:IsShown() and not old.cooldown.drawSwipe and old.cooldown.hideNumbers)
        assert(not old.glow.animation.playing and old.glow.pulseAlpha.duration==1.2)
        assert(old.glow.edges[1]:GetHeight()==5 and old.glow.edges[3]:GetWidth()==5)
        assert(old.glow.edges[1].color[3]==.4 and old.glow.edges[1].color[4]==.5)
        units.party3={guid='new',class='WARRIOR',name='new'}
        T:RefreshRoster()
        local fresh=EffectSlot(T.rows[4],107574).buttons[1]
        assert(not fresh.glow:IsShown() and not fresh.cooldown.drawSwipe and fresh.cooldown.hideNumbers)
        db.activeGlow=true; db.glowPulse=true; db.glowThickness=0/0; db.glowSpeed=math.huge
        db.glowColor={SECRET or {},-9,4,0/0}
        T:ApplySettings()
        assert(old.glow:IsShown() and old.glow.animation.playing)
        assert(old.glow.edges[1]:GetHeight()==2 and old.glow.pulseAlpha.duration==.4)
        assert(old.glow.edges[1].color[2]==0 and old.glow.edges[1].color[3]==1)
        assert(db.position==position and db.spells==spells and T.ledger==ledger)
        local before=old.glow.edges[1]:GetHeight()
        combat=true; restrictions=true; db.glowThickness=6; db.activeGlow=false
        T:ApplySettings()
        assert(T.pending and old.glow:IsShown() and old.glow.edges[1]:GetHeight()==before)
        combat=false; restrictions=false
        T.events:Fire('OnEvent','PLAYER_REGEN_ENABLED')
        assert(not old.glow:IsShown() and old.glow.edges[1]:GetHeight()==6)
    ''')


def test_use_glow_expires_and_does_not_guess_from_aura_visibility_or_previous_roster():
    lua = trace_runtime()
    lua.execute('''
        T.db.useGlow=true; T.db.useGlowDuration=.6; T:ApplySettings()
        local row=T.rows[2]
        local button=EffectSlot(row,107574).buttons[1]
        button:Show(); T:UpdateCooldowns()
        for _,icon in ipairs(row.icons) do assert(not icon.useGlow:IsShown()) end
        T:Record(row,107574,GetTime())
        local icon=row.icons[1]
        assert(icon.texture.texture==107574 and icon.useGlow:IsShown())
        Advance(.7); assert(not icon.useGlow:IsShown())
        T:Record(row,1719,GetTime()); assert(row.icons[1].useGlow:IsShown())
        units.party1={guid='replacement',class='WARRIOR',name='replacement'}
        T:RefreshRoster()
        for _,other in ipairs(row.icons) do assert(not other.useGlow:IsShown()) end
        T:EnterEditPreview(); assert(T.rows[1].icons[2].useGlow:IsShown())
        T.db.useGlow=false; T:ApplySettings()
        for _,other in ipairs(T.rows[1].icons) do assert(not other.useGlow:IsShown()) end
        T:ExitEditPreview(); T:OnDisable()
        assert(not icon.useGlow:IsVisible())
    ''')


def test_display_options_cover_native_estimated_preview_and_unknown_icons():
    lua = trace_runtime()
    lua.execute('''
        local db=T.db
        known[10060]=true; known[228260]=true
        chargeState[10060]={isActive=false,maxCharges=2,currentCharges=1}
        db.showSwipe=false; db.showNumbers=false; db.showCharges=false; db.unknownAlpha=.35
        T:ApplySettings(); T:Record(T.rows[2],107574,GetTime())
        assert(T.rows[1].icons[1].count:GetText()=='' and T.rows[1].icons[1].cooldown.hideNumbers)
        assert(T.rows[2].icons[1].text:GetText()=='' and not T.rows[2].icons[1].cooldown.drawSwipe)
        cooldowns[228260]={isActive=false,isEnabled=false}; T:UpdateCooldowns()
        assert(T.rows[1].icons[2].unknown and T.rows[1].icons[2].alpha==.35)
        assert(T.rows[1].icons[1].alpha==1)
        T:EnterEditPreview()
        assert(T.rows[1].icons[1].text:GetText()=='' and not T.rows[1].previewActive.cooldown.drawSwipe)
        assert(T.rows[1].previewActive.cooldown.hideNumbers)
        db.showNumbers=true; db.showSwipe=true; db.showCharges=true; T:ApplySettings()
        assert(T.rows[1].icons[1].text:GetText()=='42' and T.rows[1].previewActive.cooldown.drawSwipe)
        T:ExitEditPreview()
        assert(T.rows[1].icons[1].count:GetText()==1)
    ''')


def test_member_layout_packs_without_losing_owners_timers_anchors_or_movers():
    lua = trace_runtime()
    load_editor(lua)
    lua.execute('''
        local db=T.db
        local position,selection,ledger=db.position,db.spells,T.ledger
        local f=CreateFrame('Button',nil,UIParent); f.unit='party1'
        PartyFrame={MemberFrame1=f}
        db.attachTo='party'; T:ApplySettings()
        T:Record(T.rows[2],1719,GetTime())
        local observer,effect=T.rows[2].observer,T.rows[2].effects[1719]
        db.memberLayout='all'; db.columns=3; db.sortOrder='spell'; db.align='LEFT'
        T:ApplySettings()
        assert(T.combined and not T.attached and db.attachTo=='party')
        assert(T.rows[2].observer==observer and T.rows[2].effects[1719]==effect)
        local total=0
        for _,row in ipairs(T.rows) do
            if row.guid then
                for _,icon in ipairs(row.icons) do
                    if icon:IsShown() then
                        local point,_,_,x,y=icon:GetPoint()
                        assert(point=='TOPLEFT' and x==(total%3)*39 and y==-math.floor(total/3)*39)
                        assert(icon.owner:GetText()==UnitName(row.unit))
                        total=total+1
                    end
                end
            end
        end
        assert(T.frame:GetHeight()==math.ceil(total/3)*39-3)
        assert(T.ledger==ledger and T.ledger.warrior[1719] and db.position==position and db.spells==selection)
        for _,align in ipairs({'LEFT','CENTER','RIGHT'}) do
            db.align=align; db.grow='UP'; T:ApplySettings()
            local i=0
            for _,row in ipairs(T.rows) do
                if row.guid then for _,icon in ipairs(row.icons) do if icon:IsShown() then
                    local p,_,_,x,y=icon:GetPoint()
                    local spare=(3-math.min(3,total-math.floor(i/3)*3))*39
                    assert(p=='BOTTOMLEFT' and y==math.floor(i/3)*39)
                    assert(x==(i%3)*39+(align=='RIGHT' and spare or align=='CENTER' and spare/2 or 0))
                    i=i+1
                end end end
            end
        end
        T:EnterEditPreview(); assert(T.preview and T.combined)
        T:ExitEditPreview()
        db.memberLayout='each'; T:ApplySettings()
        assert(T.attached and T.rows[2].anchor==f and not T.rows[2].icons[1].owner:IsShown())
        assert(T.ledger.warrior[1719] and db.position==position)
    ''')


def test_bars_render_public_timers_native_duration_unknowns_and_square_aura_art():
    lua = trace_runtime()
    lua.execute('''
        known[10060]=true; known[228260]=true
        T.db.displayStyle='bars'; T.db.memberLayout='all'; T.db.barWidth=260
        T:ApplySettings()
        local row=T.rows[2]
        assert(T.columns==1 and T.width==260 and row.icons[1]:GetWidth()==260)
        local icon=row.icons[1]
        assert(icon.bar:IsShown() and icon.bar:GetValue()==1 and icon.unknown)
        assert(icon.label:GetText():find('전사',1,true) and not icon.owner:IsShown())
        T:Record(row,1719,GetTime()); icon=row.icons[1]
        assert(icon.bar:GetValue()==90 and icon.text:GetText()=='1:30' and not icon.cooldown.drawSwipe)
        Advance(30); assert(icon.bar:GetValue()==60 and icon.text:GetText()=='1:00')
        Advance(91); assert(icon.bar:GetValue()==90 and icon.text:GetText()=='')
        local effect=row.effects[1719]
        assert(select(2,effect:GetPoint())==icon.texture)
        assert(icon.texture:GetWidth()==36 and icon.cooldown:GetWidth()==36)
        cooldowns[10060]={isActive=true}; T:UpdateCooldowns()
        local own=T.rows[1].icons[1]
        assert(own.bar.timerDuration==nativeDuration and own.bar.timerDirection==1)
        assert(own.cooldown.durationObject==nativeDuration)
        T.db.showNumbers=false; T:ApplySettings(); T:Record(row,1719,GetTime())
        assert(row.icons[1].text:GetText()=='' and own.cooldown.hideNumbers)
        for _,size in ipairs({20,36,48}) do
            T.db.iconSize=size; T:ApplySettings(); T:EnterEditPreview()
            assert(T.rows[1].icons[1]:GetHeight()==size and T.rows[1].icons[1].bar:GetValue()==42)
            assert(select(2,T.rows[1].previewActive:GetPoint())==T.rows[1].icons[1].texture)
            T:ExitEditPreview()
        end
        combat=true; T.db.displayStyle='icons'; T:ApplySettings()
        assert(T.pending and T.bars)
        combat=false; T.events:Fire('OnEvent','PLAYER_REGEN_ENABLED')
        assert(not T.bars and not row.icons[1].bar:IsShown() and row.icons[1]:GetWidth()==48)
        units.party1.name=SECRET; T:RefreshRoster()
        assert(row.displayName==nil and row.icons[1].owner:GetText()=='')
        T.db.displayStyle='bars'; T.db.barWidth=math.huge; T:ApplySettings()
        assert(T.width==220)
        raid=true; groupSize=4
        for i=1,4 do units['raid'..i]={guid='raid'..i,class='WARRIOR',name='공대'..i} end
        T:RefreshRoster()
        assert(T.rows[6].icons[1].label:GetText():find('공대1',1,true))
        units.raid2=nil; T:RefreshRoster()
        assert(not T.rows[7]:IsShown() and T.rows[8].icons[1]:IsVisible())
    ''')


def test_layout_and_glow_fields_migrate_in_place_and_keep_visibility_rules():
    lua = trace_runtime()
    load(lua, 'Config_Data.lua')
    lua.execute('''
        local db=T.db
        local position,spells=db.position,db.spells
        db.memberLayout=nil; db.displayStyle=nil; db.glowType=nil; db.useGlowType=nil
        db.nameClassColor=nil; db.barClassColor=nil
        ns.SkillTracker:Initialize()
        assert(db.memberLayout=='each' and db.displayStyle=='icons' and db.barWidth==220)
        assert(db.glowType=='pixel' and db.useGlowType=='pixel' and db.position==position and db.spells==spells)
        for _,kind in ipairs({'common','cooldowns','defensives','cc'}) do
            local group=ns.db.profile.CooldownTrace[kind]
            assert(group.nameClassColor==false and group.barClassColor==false)
        end
        local function SettingsSection(panel)
            local list,headers={},0
            for _,s in ipairs(panel.settings) do
                if s.type=='header' then headers=headers+1 elseif headers==1 and (s.barPage or 0)==0 then list[#list+1]=s end
            end
            return list
        end
        local common=EnableCommon()
        db=common.db
        local fields={}
        for _,s in ipairs(FlatSettings(SettingsSection(ns:InitConfigTree().panels.skilltracker))) do
            if s.key then fields[s.key:match('([^.]+)$')]=s end
            if s.positionButtons then fields.edit=s end
        end
        assert(fields.memberLayout and fields.displayStyle and #fields.glowType.options==4)
        assert(#fields.useGlowType.options==4 and fields.columns.visible() and not fields.barWidth.visible())
        assert(not fields.nameClassColor.visible() and not fields.barClassColor.visible())
        db.attachTo='party'; db.memberLayout='all'; db.displayStyle='bars'
        assert(not fields.attachTo.visible() and not fields.attachSide.visible() and fields.edit.visible())
        assert(not fields.columns.visible() and fields.barWidth.visible() and not fields.rowSpacing.visible())
        assert(fields.nameClassColor.visible() and fields.barClassColor.visible())
        fields.memberLayout.onChange(); fields.displayStyle.onChange()
        assert(common.combined and common.bars and not common.attached)
    ''')


def test_bar_nicknames_and_independent_class_colors_live_preview_and_roster_changes():
    lua = trace_runtime()
    load(lua, 'Config_Data.lua')
    lua.execute('''
        local colors={WARRIOR={r=.78,g=.61,b=.43},PRIEST={r=1,g=1,b=1}}
        C_ClassColor={GetClassColor=function(class) return colors[class] end}
        local function SettingsSection(panel)
            local list,headers={},0
            for _,s in ipairs(panel.settings) do
                if s.type=='header' then headers=headers+1 elseif headers==1 and (s.barPage or 0)==0 then list[#list+1]=s end
            end
            return list
        end
        local T=EnableCommon()
        local db=T.db
        local position,spells=db.position,ns.db.profile.CooldownTrace.cooldowns.spells
        db.displayStyle='bars'; db.sortOrder='spell'
        units.party1.name='닉네임'; T:RefreshRoster()
        local fields={}
        for _,s in ipairs(FlatSettings(SettingsSection(ns:InitConfigTree().panels.skilltracker))) do
            if s.key then fields[s.key:match('([^.]+)$')]=s end
        end
        local function Check(icon,name,class,nameColor,barColor)
            assert(icon.label:GetText()==name)
            local c=colors[class]
            local text=nameColor and {c.r,c.g,c.b,1} or DDingUI_StyleLib.Colors.text.highlight
            local bar=barColor and {c.r,c.g,c.b,1} or DDingUI_StyleLib.Colors.status.success
            for i=1,4 do
                assert(icon.label.textColor[i]==text[i] and icon.bar.barColor[i]==bar[i])
            end
        end
        for _,layout in ipairs({'each','all'}) do
            db.memberLayout=layout
            for _,nameColor in ipairs({false,true}) do
                for _,barColor in ipairs({false,true}) do
                    db.nameClassColor=nameColor; db.barClassColor=barColor
                    fields.nameClassColor.onChange(); fields.barClassColor.onChange()
                    Check(T.rows[2].icons[1],'닉네임','WARRIOR',nameColor,barColor)
                    T:Record(T.rows[2],1719,GetTime()); Advance(12)
                    Check(T.rows[2].icons[1],'닉네임','WARRIOR',nameColor,barColor)
                    T:EnterEditPreview()
                    Check(T.rows[2].icons[1],ns.L.CT_CLASS_SHORT_WARRIOR,'WARRIOR',nameColor,barColor)
                    T:ExitEditPreview()
                end
            end
        end
        -- Reused rows must pick up the new member's color and clear inaccessible names.
        units.party1={guid='replacement',class='PRIEST',name='교체됨'}; T:RefreshRoster()
        Check(T.rows[2].icons[1],'교체됨','PRIEST',true,true)
        units.party1.name=SECRET; T:RefreshRoster()
        Check(T.rows[2].icons[1],'…','PRIEST',true,true)
        C_ClassColor=nil; RAID_CLASS_COLORS=colors; T:ApplySettings()
        Check(T.rows[2].icons[1],'…','PRIEST',true,true)
        RAID_CLASS_COLORS=nil; T:ApplySettings()
        Check(T.rows[2].icons[1],'…','PRIEST',false,false)
        db.nameClassColor=false; db.barClassColor=false; ns.SkillTracker:Initialize()
        assert(db.nameClassColor==false and db.barClassColor==false)
        assert(db.position==position and ns.db.profile.CooldownTrace.cooldowns.spells==spells)
    ''')


def test_glow_types_switch_and_stop_on_normal_and_protected_icons():
    lua = trace_runtime()
    lua.execute('''
        T.db.useGlow=true; T:ApplySettings()
        local protected=EffectSlot(T.rows[2],1719).buttons[1].glow
        for _,kind in ipairs({'normal','autocast','button','pixel','invalid'}) do
            T.db.glowType=kind; T.db.useGlowType=kind
            T:ApplySettings(); T:EnterEditPreview()
            local glow=T.rows[1].previewActive.glow
            local expected=kind=='invalid' and 'pixel' or kind
            assert(glow.effectType==expected and protected.effectType==expected)
            if expected=='normal' then
                assert(glow._slGlow:IsShown() and protected.edges[1]:GetHeight()==4)
                assert(protected.edges[1].color[4]==.45)
            elseif expected=='autocast' then
                assert(glow._AutoCastGlow and protected.sparks[1]:IsShown() and not protected.edges[1]:IsShown())
            elseif expected=='button' then
                assert(glow._ButtonGlow and protected.ants:IsShown() and protected.ants.animation.playing)
                assert(protected.ants.flipbook.flipFrames==30)
            else assert(glow._PixelGlow and protected.pixels[1]:IsShown() and not protected.edges[1]:IsShown()) end
            assert(T.rows[1].icons[2].useGlow.effectType==expected)
            T:ExitEditPreview()
        end
        T.db.glowType='autocast'; T.db.glowPulse=false; T:ApplySettings()
        assert(not protected.animation.playing)
        assert(protected.sparks[1].animation.playing, 'orbit must run with pulse disabled')
        combat=true; restrictions=true; T.db.glowType='button'; T:ApplySettings()
        assert(protected.effectType=='autocast' and T.pending)
        combat=false; restrictions=false; T.events:Fire('OnEvent','PLAYER_REGEN_ENABLED')
        assert(protected.effectType=='button')
        T.db.activeGlow=false; T.db.useGlow=false; T:ApplySettings()
        assert(not protected:IsShown() and not protected.ants.animation.playing)
    ''')


def test_extra_bar_status_bars_sort_and_color_like_omnicd():
    lua = trace_runtime()
    lua.execute('''
        local G,db=ns.SkillTracker,ns.db.profile.CooldownTrace
        local colors={WARRIOR={r=.78,g=.61,b=.43},PRIEST={r=1,g=1,b=1}}
        RAID_CLASS_COLORS=colors
        EnableCommon()
        G:SetEnabled('bar2',true); G:SetTypeFrame('defensives',2)
        local bar=ns.modules.SkillTrace_bar2
        local cfg=db.extraBars.bar2
        assert(bar.combined and bar.vertical and bar.bars and bar.frame:GetScale()==.6 and bar.size==36)
        assert(bar.itemWidth==36+205 and bar.gapX==-1 and bar.gapY==-1)
        local function Order()
            local list={}
            for _,row in ipairs(bar.rows) do
                for _,icon in ipairs(row.icons) do
                    if icon:IsShown() then
                        local point,_,_,x,y=icon:GetPoint()
                        list[#list+1]={icon=icon,row=row,x=x,y=y,point=point,id=icon.texture.texture}
                    end
                end
            end
            table.sort(list,function(a,b) if a.x~=b.x then return a.x<b.x end return a.y>b.y end)
            return list
        end
        local list=Order()
        local expected=#ns.CooldownTraceData.defensives.WARRIOR+#ns.CooldownTraceData.defensives.PRIEST
        assert(#list==expected)
        -- Priority ties sort by class then spell ID; vertical bars fill a column of 15, then the next.
        for i=2,#list do
            local a,b=list[i-1],list[i]
            assert(a.row.class<b.row.class or (a.row.class==b.row.class and a.id<b.id))
        end
        assert(list[1].point=='TOPLEFT' and list[1].x==0 and list[1].y==0 and list[2].y==-35)
        assert(bar.frame:GetWidth()==math.ceil(expected/15)*(241-1)+1 or bar.frame:GetWidth()>0)
        local ready=list[1].icon
        assert(ready.bar:GetValue()==1 and ready.label:GetText()==units.party2.name)
        for i=1,3 do assert(ready.bar.barColor[i]==({1,1,1})[i]) end
        -- Remaining cooldown > priority: ready spells first, then the soonest to finish.
        cfg.sortBy='remaining_priority'; bar:ApplySettings()
        bar:Record(bar.rows[2],118038,GetTime())
        Advance(30)
        list=Order()
        local cooling=list[#list].icon
        assert(list[#list].id==118038 and cooling.text:GetText()=='1:30')
        assert(cooling.bar:GetValue()==90 and cooling.bar.max==120 and cooling.spark:IsShown())
        local c=colors.WARRIOR
        assert(cooling.bar.barColor[1]==c.r and cooling.bar.barColor[2]==c.g)
        assert(cooling.barBG.color[4]==.5 and cooling.barBG.color[1]==0)
        assert(cooling.label.textColor[1]==1 and cooling.label:GetText()==units.party1.name)
        assert(cooling.texture.desaturated and cooling.cooldown.drawSwipe and cooling.cooldown.hideNumbers)
        cfg.sortDirection='dsc'; bar:ApplySettings()
        assert(Order()[1].id==118038)
        cfg.reverseFill=false; cfg.hideSpark=true; cfg.hideBorder=true; bar:ApplySettings()
        assert(cooling.bar:GetValue()==30 and not cooling.spark:IsShown() and not cooling.barBorder:IsShown())
        cfg.barColors.useClassColor.active=false; bar:UpdateCooldowns()
        assert(cooling.bar.barColor[1]==1 and cooling.bar.barColor[2]==0)
        cfg.statusBarWidth=100; cfg.truncateStatusBarName=1; bar:ApplySettings()
        assert(cooling:GetWidth()==136 and cooling.bar:GetWidth()==100 and cooling.label:GetText()==units.party1.name:sub(1,3))
        -- Name bar: only the name stays, no timer fill or bar-end countdown.
        cfg.nameBar=true; bar:ApplySettings()
        assert(not cooling.bar:GetStatusBarTexture():IsShown() and not cooling.barCooldown:IsShown() and cooling.label:IsShown())
        assert(cooling.barBG.color[4]==0)
        -- Horizontal layout drops the status bar timer and shows truncated, class-colored icon names.
        cfg.nameBar=false; cfg.layout='horizontal'; cfg.columns=4; cfg.truncateIconName=2; bar:ApplySettings()
        assert(not bar.bars and bar.showNames and cooling.owner:IsShown())
        assert(cooling.owner:GetText()==units.party1.name:sub(1,6) and cooling.owner.textColor[1]==c.r)
        list=Order()
        local at={}
        for _,item in ipairs(list) do at[item.x..','..(item.y==0 and 0 or item.y)]=true end
        assert(at['35,0'] and at['105,0'] and not at['140,0'] and at['0,-35'])
        cfg.growLeft=true; cfg.growUpward=true; bar:ApplySettings()
        assert(Order()[1].point=='BOTTOMRIGHT')
        cfg.showName=false; bar:ApplySettings()
        assert(not cooling.owner:IsShown() and bar.itemHeight==36)
        cfg.scale=5; bar:ApplySettings(); assert(bar.frame:GetScale()==2)
        assert(db.defensives.spells.WARRIOR and bar.ledger.warrior[118038])
    ''')


def test_unit_bar_attaches_at_omnicd_points_and_unlocked_tab_moves_bar():
    lua = trace_runtime()
    lua.execute('''
        local G,db=ns.SkillTracker,ns.db.profile.CooldownTrace
        local f1=CreateFrame('Button',nil,UIParent); f1.unit='party1'
        local f2=CreateFrame('Button',nil,UIParent); f2.unit='party2'
        PartyFrame={MemberFrame1=f1,MemberFrame2=f2}
        EnableCommon()
        G:SetEnabled('bar3',true); G:SetTypeFrame('cc',3)
        local bar=ns.modules.SkillTrace_bar3
        local cfg=db.extraBars.bar3
        cfg.unitBar=true; cfg.offsetX=-2; cfg.layout='horizontal'; cfg.columns=1
        bar:ApplySettings()
        assert(bar.attached and not bar.combined and not (bar.barTab and bar.barTab:IsShown()))
        local point,anchor,relative,x,y=bar.rows[2]:GetPoint()
        assert(point=='TOPRIGHT' and anchor==f1 and relative=='TOPLEFT' and x==-2 and y==0)
        local p1,_,_,x1,y1=bar.rows[2].icons[1]:GetPoint()
        local p2,_,_,x2,y2=bar.rows[2].icons[2]:GetPoint()
        assert(p1=='TOPRIGHT' and x1==0 and y1==0 and p2=='TOPRIGHT' and x2==0 and y2==-35)
        cfg.columns=4; bar:ApplySettings()
        _,_,_,x2,y2=bar.rows[2].icons[2]:GetPoint()
        assert(x2==-35 and y2==0)
        cfg.anchor='TOPLEFT'; cfg.attach='TOPRIGHT'; cfg.growUpward=true; bar:ApplySettings()
        point,anchor,relative=bar.rows[2]:GetPoint()
        _,_,_,x2,y2=bar.rows[2].icons[5]:GetPoint()
        assert(point=='TOPLEFT' and relative=='TOPRIGHT' and x2==0 and y2==35)
        combat=true; cfg.anchor='BOTTOMLEFT'; bar:ApplySettings()
        assert(bar.pending and select(1,bar.rows[2]:GetPoint())=='TOPLEFT')
        combat=false; bar.events:Fire('OnEvent','PLAYER_REGEN_ENABLED')
        assert(select(1,bar.rows[2]:GetPoint())=='BOTTOMLEFT')
        -- Movement is available only in edit mode, regardless of the saved locked value.
        cfg.unitBar=false; bar:ApplySettings()
        assert(not (bar.barTab and bar.barTab:IsShown()))
        bar:EnterEditPreview()
        local tab=bar.barTab
        assert(tab and tab:IsShown() and tab.text:GetText()=='3' and tab.text.textColor[2]==.824)
        G:RenameBar(3,'CC기'); assert(tab.text:GetText()=='CC기' and G:BarName(3)=='CC기')
        G:RenameBar(3,'  '); assert(cfg.name==nil and G:BarName(1)==ns.L.CT_BAR_INTERRUPTS)
        tab:Fire('OnDragStart'); assert(bar.frame.moving)
        bar.frame:ClearAllPoints(); bar.frame:SetPoint('TOPLEFT',UIParent,'BOTTOMLEFT',123.4,456.6)
        tab:Fire('OnDragStop')
        local p=cfg.position
        assert(p.point=='TOPLEFT' and p.relativePoint=='BOTTOMLEFT' and p.x==123 and p.y==457)
        combat=true; bar.frame.moving=false; tab:Fire('OnDragStart'); assert(not bar.frame.moving)
        combat=false
        cfg.locked=true; bar:ExitEditPreview(); assert(not tab:IsShown())
        G:ResetBarPosition(3); assert(cfg.position.x==ns.defaults.profile.CooldownTrace.extraBars.bar3.position.x)
        G:ResetBar(3)
        assert(db.extraBars.bar3~=cfg and db.extraBars.bar3.locked==false and db.frames.cc==3)
    ''')


def test_extra_bar_show_player_own_effects_and_preview():
    lua = trace_runtime()
    lua.execute('''
        local G,db=ns.SkillTracker,ns.db.profile.CooldownTrace
        known[33206]=true; known[47788]=true
        local common=EnableCommon()
        G:SetEnabled('bar2',true); G:SetTypeFrame('defensives',2)
        local bar=ns.modules.SkillTrace_bar2
        assert(bar.rows[1].guid=='self' and bar.rows[1].icons[1]:IsShown())
        db.extraBars.bar2.showPlayer=false; bar:ApplySettings()
        assert(bar.rows[1].guid==nil and not bar.rows[1]:IsShown() and bar.rows[2].guid)
        db.extraBars.bar2.showPlayer=true; bar:ApplySettings()
        -- [REFACTOR] Each bar owns its effect and context options; frame 0 no longer drives them.
        local own=db.extraBars.bar2
        assert(bar.fx==own and bar.db==own and own~=common.db)
        for _,field in ipairs(G.FX_FIELDS) do assert(own[field]~=nil) end
        local slot=EffectSlot(bar.rows[2],871)
        local glow=slot.buttons[1].glow
        assert(glow:IsShown())
        G:SetSpellGlow(871,false); assert(not glow:IsShown())
        G:SetSpellGlow(871,true); assert(glow:IsShown())
        common.db.activeGlow=false; G:Refresh(); assert(glow:IsShown())
        own.activeGlow=false; G:Refresh(); assert(not glow:IsShown())
        own.activeGlow=true; common.db.showNumbers=false; G:Refresh()
        assert(not bar.rows[2].icons[1].barCooldown.hideNumbers and common.rows[2].icons[1].cooldown.hideNumbers)
        own.showNumbers=false; G:Refresh()
        assert(bar.rows[2].icons[1].barCooldown.hideNumbers)
        bar:Record(bar.rows[2],871,GetTime())
        for _,icon in ipairs(bar.rows[2].icons) do if icon.texture.texture==871 then assert(icon.text:GetText()=='') end end
        own.showNumbers=true; common.db.showNumbers=true; common.db.activeGlow=true
        common.db.showInParty=false; G:Refresh(); assert(bar.frame:IsShown() and not common.frame:IsShown())
        own.showInParty=false; G:Refresh(); assert(not bar.frame:IsShown())
        own.showInParty=true; common.db.showInParty=true; G:Refresh(); assert(bar.frame:IsShown())
        bar:EnterEditPreview()
        local row=bar.rows[1]
        assert(bar.preview and bar.frame:IsShown() and row.icons[1].bar:GetValue()==42 and row.icons[1].bar.max==120)
        assert(row.previewActive:IsShown() and row.icons[1].label:GetText()==ns.L.CT_CLASS_SHORT_PRIEST)
        bar:ExitEditPreview()
        assert(not bar.preview and not row.previewActive:IsShown())
    ''')


def test_bars_adopt_frame_zero_effects_once_then_edit_independently():
    lua = trace_runtime()
    lua.execute('''
        local G,db=ns.SkillTracker,ns.db.profile.CooldownTrace
        local common=db.common
        common.glowType='autocast'; common.glowColor={.1,.2,.3,.4}; common.showSwipe=false
        common.showInRaid=false; common.borderThickness=4; common.unknownAlpha=.5
        local bars={}
        for index=1,G.BAR_COUNT do
            local bar=db.extraBars['bar'..index]
            for _,field in ipairs(G.FX_FIELDS) do bar[field]=nil end
            bars[index]=bar
        end
        local position,columns=bars[3].position,bars[3].columns
        db.extraBars.bar5=nil -- a never-saved bar also starts from frame 0's look
        G:Initialize()
        bars[5]=db.extraBars.bar5
        for index=1,G.BAR_COUNT do
            local bar=db.extraBars['bar'..index]
            assert(bar.glowType=='autocast' and bar.showSwipe==false and bar.showInRaid==false)
            assert(bar.borderThickness==4 and bar.unknownAlpha==.5 and bar.glowColor[3]==.3)
            assert(bar.glowColor~=common.glowColor)
            for _,field in ipairs(G.FX_FIELDS) do assert(bar[field]~=nil) end
        end
        assert(bars[3].position==position and bars[3].columns==columns)
        -- Adoption runs only for missing fields: later edits stay per frame.
        bars[3].glowType='button'; common.glowType='normal'
        G:Initialize()
        assert(bars[3].glowType=='button' and bars[4].glowType=='autocast')
        bars[3].glowColor[1]=.9; assert(common.glowColor[1]==.1 and bars[4].glowColor[1]==.1)
        -- Bar reset returns to the default look, not frame 0's custom one.
        G:ResetBar(3)
        local reset=db.extraBars.bar3
        local defaults=ns.defaults.profile.CooldownTrace.common
        assert(reset.glowType==defaults.glowType and reset.showSwipe==true and reset.borderThickness==defaults.borderThickness)
        assert(ns.defaults.profile.CooldownTrace.extraBars.bar3.glowType==nil)
    ''')


def test_icon_border_is_square_per_frame_and_applies_after_combat():
    lua = trace_runtime()
    lua.execute('''
        local common=EnableCommon()
        ns.SkillTracker:SetEnabled('bar2',true)
        ns.SkillTracker:SetTypeFrame('defensives',2)
        local bar=ns.modules.SkillTrace_bar2
        -- [REFACTOR] Frame 0 and each bar keep their own border options.
        local db=bar.db
        for _,cfg in ipairs({common.db,db}) do cfg.borderThickness=3; cfg.borderColor={.3,.5,.7,.8} end
        ns.SkillTracker:Refresh()
        for _,mod in ipairs({common,bar}) do
            local icon=mod.rows[2].icons[1]
            local _,anchor,_,x,y=icon.border:GetPoint()
            assert(anchor==icon.texture and math.abs(x)==3 and math.abs(y)==3)
            assert(icon.border.color[1]==.3 and icon.border.color[4]==.8 and icon.border:IsShown())
            assert(icon.border:GetWidth()==mod.size+6)
            mod:EnterEditPreview()
            assert(mod.rows[1].previewActive.border.color[3]==.7)
            mod:ExitEditPreview()
        end
        combat=true; db.showBorder=false; ns.SkillTracker:Refresh()
        assert(bar.pending and bar.rows[2].icons[1].border:IsShown())
        combat=false; bar.events:Fire('OnEvent','PLAYER_REGEN_ENABLED')
        assert(not bar.rows[2].icons[1].border:IsShown() and common.rows[2].icons[1].border:IsShown())
        db.showBorder=true; db.borderThickness=math.huge; db.borderColor={SECRET,-2,5,SECRET}
        bar:ApplySettings()
        local border=bar.rows[2].icons[1].border
        assert(border.color[2]==0 and border.color[3]==1 and border.color[4]==1)
        assert(border:GetWidth()==bar.size+2)
    ''')


def test_pixel_sizes_and_name_text_are_independent_and_zero_gap_touches_icons():
    lua = trace_runtime()
    load(lua, 'Config_Data.lua')
    lua.execute('''
        local G,db=ns.SkillTracker,ns.db.profile.CooldownTrace
        local common=EnableCommon()
        G:SetEnabled('bar2',true); G:SetTypeFrame('defensives',2)
        G:SetEnabled('bar3',true); G:SetTypeFrame('cc',3)
        local a,b=ns.modules.SkillTrace_bar2,ns.modules.SkillTrace_bar3
        local cfg=db.extraBars.bar2
        local width,scale=a.statusWidth,a.frame:GetScale()
        local other=b.size
        cfg.pixelSize=42; common.db.pixelSize=28
        G:Refresh()
        assert(math.abs(a.size*scale-42)<.0001 and a.statusWidth==width and b.size==other)
        assert(math.abs(common.size*common.frame:GetScale()-28)<.0001)
        assert(a.frame:GetScale()==scale and cfg.scale==scale)
        cfg.layout='horizontal'; cfg.columns=1; cfg.paddingY=0; cfg.classColor=false
        cfg.nameFont='Fonts\\\\FRIZQT__.TTF'; cfg.nameFontSize=18
        cfg.nameOfsX=9; cfg.nameOfsY=7; cfg.nameColor={.2,.4,.6,.8}
        a:ApplySettings()
        local one,two=a.rows[2].icons[1],a.rows[2].icons[2]
        local _,_,_,_,y1=one:GetPoint(); local _,_,_,_,y2=two:GetPoint()
        assert(math.abs(y2-y1)==a.size and a.itemHeight==a.size)
        local _,anchor,_,x,y=one.owner:GetPoint()
        assert(anchor==one.texture and x==9 and y==5)
        assert(one.owner.fontPath==cfg.nameFont and one.owner.fontSize==18)
        assert(one.owner.textColor[1]==.2 and one.owner.textColor[4]==.8)
        cfg.nameOfsY=-30; cfg.showName=false; a:ApplySettings()
        assert(a.itemHeight==a.size and not one.owner:IsShown())
        cfg.showName=true; cfg.growUpward=true; a:ApplySettings()
        _,_,_,_,y1=one:GetPoint(); _,_,_,_,y2=two:GetPoint()
        assert(math.abs(y2-y1)==a.size)
        local pos,selection=cfg.position,db.defensives.spells
        G:Initialize()
        assert(cfg.pixelSize==42 and cfg.position==pos and db.defensives.spells==selection)
        local fields={}
        for _,s in ipairs(FlatSettings(ns:InitConfigTree().panels.skilltracker.settings)) do
            if s.key then fields[s.key]=s end
        end
        assert(fields['profile.CooldownTrace.extraBars.bar2.pixelSize'].step==1)
        assert(not fields['profile.CooldownTrace.extraBars.bar2.scale'])
        assert(not fields['profile.CooldownTrace.extraBars.bar2.locked'])
        cfg.pixelSize=math.huge; a:ApplySettings()
        assert(a.size==36)
        common.db.pixelSize=96; common.db.scale=.5; common.db.displayStyle='bars'; common.db.barWidth=140
        common:ApplySettings()
        assert(common.itemWidth>=common.size+60 and common.rows[2].icons[1].label:GetWidth()>0)
    ''')


def test_all_tracker_frames_register_specialization_event_on_enable_and_reenable():
    lua = trace_runtime(enabled=False)
    lua.execute('''
        for _,kind in ipairs({'common','bar1','bar2','bar3','bar4','bar5','bar6','bar7','bar8'}) do
            local mod=ns.modules['SkillTrace_'..kind]
            for attempt=1,2 do
                mod:OnEnable()
                assert(mod.running and mod.events.events.PLAYER_SPECIALIZATION_CHANGED)
                assert(mod.events.events.INSPECT_READY)
                mod:OnDisable()
                assert(not mod.running and not next(mod.events.events))
            end
        end
    ''')


def test_specializations_filter_known_unknown_secret_and_changed_party_members():
    lua = trace_runtime()
    lua.execute('''
        local G=ns.SkillTracker
        local spec={party1=72,party2=258}
        GetInspectSpecialization=function(unit) return spec[unit] or 0 end
        CanInspect=function() return true end
        inspectCalls={}
        NotifyInspect=function(unit) inspectCalls[#inspectCalls+1]=unit end
        local function Has(mod,row,id)
            for _,icon in ipairs(mod.rows[row].icons) do
                if icon:IsShown() and icon.texture.texture==id then return true end
            end
            return false
        end
        T:RefreshRoster(); D:RefreshRoster()
        D.events:Fire('OnEvent','PLAYER_SPECIALIZATION_CHANGED',SECRET)
        assert(T.rows[2].specID==72 and T.rows[3].specID==258)
        assert(Has(T,2,1719) and not Has(T,2,167105))
        assert(Has(D,2,184364) and not Has(D,2,871))
        assert(Has(T,3,228260) and not Has(T,3,64843) and not Has(T,3,421453))
        assert(Has(D,3,47585) and not Has(D,3,33206) and not Has(D,3,47788))
        -- Inspect data is transient; cached GUIDs survive another unit's inspection.
        spec.party2=0; D:RefreshRoster(); assert(D.rows[3].specID==258)
        spec.party2=256; D.events:Fire('OnEvent','PLAYER_SPECIALIZATION_CHANGED','party2')
        assert(Has(D,3,33206) and not Has(D,3,47585))
        units.party2={guid='new',class='PRIEST',name='new'}; spec.party2=SECRET
        D:RefreshRoster()
        assert(D.rows[3].specID==nil and Has(D,3,19236) and not Has(D,3,33206))
        assert(#inspectCalls==1)
        -- Unknown specs may show a publicly observed cast, never all spec candidates.
        D:Record(D.rows[3],47788,GetTime())
        assert(Has(D,3,47788) and not Has(D,3,33206))
        spec.party2=257; D.events:Fire('OnEvent','INSPECT_READY','new')
        assert(D.rows[3].specID==257 and Has(D,3,47788))
        combat=true; units.party1.guid='other'; spec.party1=0
        Advance(5); D:RefreshRoster(); assert(#inspectCalls==1)
        combat=false; spec.party1=73
        D.events:Fire('OnEvent','PLAYER_REGEN_ENABLED')
        assert(Has(D,2,871) and not Has(D,2,184364))
        assert(ns.CooldownTraceData.specs[1264949][254] and ns.CooldownTraceData.specs[1264949][255])
        assert(ns.CooldownTraceData.specs[1221150][1480] and ns.CooldownTraceData.specs[1233448][252])
    ''')


def test_confirmation_uses_escape_close_without_protected_keyboard_calls():
    lua = trace_runtime(enabled=False)
    lua.execute('''
        local M=getmetatable(UIParent).__index
        function M:EnableKeyboard() error('keyboard capture is forbidden') end
        function M:SetPropagateKeyboardInput() error('protected keyboard call') end
        function M:Raise() end
        function M:GetStringHeight() return 20 end
        function M:Click() self:Fire('OnClick','LeftButton') end
        ns.UI={colors={panel={0,0,0,1},border={1,1,1,1},text={1,1,1,1}}}
    ''')
    load(lua, 'UI/Templates.lua')
    lua.execute('''
        local ui=ns.UI
        accepted,cancelled=0,0
        ui:ShowConfirmation('first',{text='first',onCancel=function() cancelled=cancelled+1 end})
        ui:ShowConfirmation('second',{text='second',onAccept=function() accepted=accepted+1 end})
        local f=DDingToolKitConfirmationDialog
        assert(f:IsShown() and not f:GetScript('OnKeyDown'))
        local found=false
        for _,name in ipairs(UISpecialFrames) do if name==f.name then found=true end end
        assert(found)
        combat=true; f:Hide()
        assert(cancelled==1 and f:IsShown() and f.message:GetText()=='second')
        f.accept:Click()
        assert(accepted==1 and cancelled==1 and not f:IsShown())
        ui:ShowConfirmation('third',{text='third'})
        ui:HideConfirmation('third'); assert(not f:IsShown())
    ''')


def test_hidden_party_buff_edge_draws_engine_countdown_and_grey_cover_without_reading_secrets():
    lua = hidden_runtime()
    lua.execute('''
        local S=ns.CooldownTraceSensor
        assert(S.available and not S.broken and S.faults==0)
        -- Party1 (warrior) and party2 (priest) spells are watched; the player's own spells are not.
        assert(S.timers.party1[1719].active and S.timers.party2[10060].active and not S.timers.player)
        combat=true; hiddenAuras=true
        Aura('party1',1719,12)
        local timer=S.timers.party1[1719]
        assert(issecretvalue(timer.slots[1].c) and issecretvalue(timer.pub) and T.ledger.warrior==nil)
        T:UpdateCooldowns()
        local number,covered=HiddenView(T,2,1719)
        assert(number=='1:30' and covered, tostring(number))
        -- The cover and numbers are clipped to the icon; the step is whole screen pixels.
        local icon=IconOf(T,2,1719)
        local layer=icon.hidden
        assert(layer.win.clips and layer.veil[1].clips and layer.grey[1].desaturated)
        local ppu=icon:GetEffectiveScale()*1080/768
        assert(math.abs(layer.step*ppu-math.floor(layer.step*ppu+.5))<1e-6)
        assert(layer.veil[1]:GetFrameLevel()<icon.overlay:GetFrameLevel())
        assert(layer.win:GetFrameLevel()>icon.timerLayer:GetFrameLevel())
        -- The buff ending is not a use; the cooldown keeps counting from the rising edge.
        Aura('party1',1719,nil)
        Advance(29); T:UpdateCooldowns() -- 30 s after the stamp (the aura reads took about 1 s)
        number,covered=HiddenView(T,2,1719); assert(number=='1:00' and covered, tostring(number))
        Advance(59); T:UpdateCooldowns()
        number,covered=HiddenView(T,2,1719); assert(number=='1' and covered, tostring(number))
        Advance(1); T:UpdateCooldowns()
        number,covered=HiddenView(T,2,1719); assert(number==nil and not covered)
        -- Untouched spells of the same member and other members draw nothing.
        assert(HiddenView(T,2,107574)==nil and HiddenView(T,3,10060)==nil)
        assert(T.ledger.warrior==nil and S.faults==0)
    ''')


def test_public_buff_edges_use_the_ledger_and_hidden_uses_fade_older_public_timers():
    lua = hidden_runtime()
    lua.execute('''
        local S=ns.CooldownTraceSensor
        Aura('party1',1719,12)
        assert(T.ledger.warrior[1719] and T.ledger.warrior[1719].seconds==90)
        T:UpdateCooldowns()
        local icon=IconOf(T,2,1719)
        assert(icon.text:GetText()=='1:30' and icon.texture.desaturated and HiddenView(T,2,1719)=='1:30')
        assert(icon.timerLayer.alpha==0 and icon.cooldown.alpha==0)
        Aura('party1',1719,nil); Advance(60)
        -- A shorter talented cooldown: the next use is hidden while the public timer still runs.
        combat=true; hiddenAuras=true
        Aura('party1',1719,12); T:UpdateCooldowns()
        local number,covered=HiddenView(T,2,1719)
        assert(number=='1:30' and covered)
        assert(Reveal(icon.timerLayer.alpha)==0 and Reveal(icon.cooldown.alpha)==0)
        -- A newer public record replaces the hidden stamp on the same renderer.
        Advance(5); T:Record(T.rows[2],1719,GetTime()); T:UpdateCooldowns()
        assert(HiddenView(T,2,1719)=='1:30' and icon.timerLayer.alpha==0 and icon.text:GetText()=='1:30')
        -- Party icons released by roster changes keep no faded public layer.
        units.party1=nil; groupSize=2; T:RefreshRoster()
        assert(not S.timers.party1[1719].active and S:Timer('party1','warrior',1719)==nil)
        assert(S.faults==0)
    ''')


def test_running_buffs_at_watch_start_or_roster_join_are_baselines_not_uses():
    lua = hidden_runtime("buffs.party1={[1719]={duration=12}}")
    lua.execute('''
        local S=ns.CooldownTraceSensor
        assert(S.timers.party1[1719].primed and T.ledger.warrior==nil)
        T:UpdateCooldowns(); assert(HiddenView(T,2,1719)==nil)
        Aura('party1',1719,nil); Aura('party1',1719,12)
        assert(T.ledger.warrior[1719])
        -- A member joining with a running cooldown buff starts from a baseline too.
        units.party3={guid='mage',class='MAGE',name='법사'}; groupSize=4
        buffs.party3={[365362]={duration=6}}
        -- Sensors are built outside combat; the answers are already hidden (key restrictions).
        hiddenAuras=true
        T:RefreshRoster(); Settle(); T:UpdateCooldowns()
        combat=true
        assert(S.timers.party3[365350].active and HiddenView(T,4,365350)==nil)
        -- Encounter resets drop hidden stamps and re-arm on the current buffs.
        Aura('party3',365362,nil); Aura('party3',365362,6); T:UpdateCooldowns()
        assert(Fresh(HiddenView(T,4,365350),90))
        T.events:Fire('OnEvent','ENCOUNTER_END'); Settle(); T:UpdateCooldowns()
        assert(HiddenView(T,4,365350)==nil and S.timers.party3[365350].primed)
        assert(S.faults==0)
    ''')


def test_external_zone_others_and_short_proc_rules_follow_kira_buff_rules():
    lua = hidden_runtime()
    lua.execute('''
        local S=ns.CooldownTraceSensor
        combat=true; hiddenAuras=true
        -- Pain Suppression lands on the tank: the priest's defensive starts.
        Aura('party1',33206,8); D:UpdateCooldowns()
        assert(Fresh(HiddenView(D,3,33206),180))
        -- Guardian Spirit never counts on the caster, only on another member.
        Aura('party2',47788,10); D:UpdateCooldowns()
        assert(HiddenView(D,3,47788)==nil)
        Aura('player',47788,10); D:UpdateCooldowns()
        assert(Fresh(HiddenView(D,3,47788),180))
        assert(S.sensors.party2[47788]==nil or S.sensors.party2[47788].main==nil)
        -- Combustion procs (8 s or shorter) are not casts; the real cast is.
        units.party3={guid='mage',class='MAGE',name='법사'}; groupSize=4
        combat=false; T:RefreshRoster(); D:RefreshRoster(); Settle(); combat=true
        Aura('party3',190319,6); T:UpdateCooldowns()
        assert(HiddenView(T,4,190319)==nil)
        Aura('party3',190319,nil); Aura('party3',190319,12); T:UpdateCooldowns()
        assert(Fresh(HiddenView(T,4,190319)))
        assert(S.faults==0)
    ''')


def test_hidden_stamps_roll_windows_and_bar_styles_draw_remaining_fill():
    lua = hidden_runtime("ns.CooldownTraceData.baseCooldowns[1719]=30")
    lua.execute('''
        local S=ns.CooldownTraceSensor
        local timer=S.timers.party1[1719]
        assert(timer.seconds==30 and timer.u==1 and timer.period==254)
        combat=true; hiddenAuras=true
        Aura('party1',1719,12); Aura('party1',1719,nil)
        Advance(260)
        -- A use after the first 254-step window goes to the second slot and still reads exactly.
        Aura('party1',1719,12); T:UpdateCooldowns()
        assert(timer.cur==2 and HiddenView(T,2,1719)=='30')
        Advance(10); T:UpdateCooldowns()
        assert(HiddenView(T,2,1719)=='20')
        -- DDingUI bars: numbers at the bar end, the bar shows the remaining part.
        combat=false; T.db.displayStyle='bars'; T:ApplySettings(); combat=true; T:UpdateCooldowns()
        local icon=IconOf(T,2,1719)
        local number,covered=HiddenView(T,2,1719)
        assert(number=='20' and covered and icon.hidden.strip[2].justify=='RIGHT')
        local cover=icon.hidden.cover[2]
        assert(cover:IsShown() and cover.reverseFill and cover.orientation=='HORIZONTAL')
        local x,_,w=cover:Rect()
        local fx,_,fw=cover:GetStatusBarTexture():Rect()
        assert(math.abs(fw/w-10/30)<.04 and math.abs(fx+fw-(x+w))<1e-6)
        Advance(20); T:UpdateCooldowns()
        number,covered=HiddenView(T,2,1719)
        assert(number==nil and not covered)
        assert(S.faults==0)
    ''')


def test_omnicd_bars_preview_raid_and_unavailable_clients_keep_hidden_timers_off():
    lua = hidden_runtime()
    lua.execute('''
        local S,G=ns.CooldownTraceSensor,ns.SkillTracker
        EnableCommon()
        G:SetEnabled('bar2',true); G:SetTypeFrame('defensives',2)
        local bar=ns.modules.SkillTrace_bar2
        assert(S.engines[bar] and S.timers.party1[118038].active)
        Settle(); combat=true; hiddenAuras=true
        Aura('party1',118038,8); bar:UpdateCooldowns()
        local icon=IconOf(bar,2,118038)
        local number,covered=HiddenView(bar,2,118038)
        assert(Fresh(number) and covered and icon.hidden.cover[1]:IsShown())
        -- The remaining part uses the OmniCD active bar color, like a public timer.
        local r,g,b=bar:StateColor('barColors','active',{0,1,0,1},'WARRIOR')
        local shown=icon.hidden.coverBG[1].color
        assert(shown[1]==r and shown[2]==g and shown[3]==b and icon.hidden.cover[1].reverseFill)
        combat=false; hiddenAuras=false
        bar:EnterEditPreview()
        assert(not icon.hidden.root:IsShown() and S.wants[bar]==nil)
        bar:ExitEditPreview()
        assert(S.wants[bar] and S.wants[bar].party1[118038])
        -- Raid rows never ask for sensors (KiraUI is party-only too).
        for index=1,3 do units['raid'..index]=units[({'player','party1','party2'})[index]] end
        raid=true; groupSize=3
        for _,mod in ipairs({T,D,bar}) do mod:RefreshRoster() end
        assert(not S.timers.party1[118038].active and S:Timer('party1','warrior',118038)==nil)
        raid=false
        G:SetEnabled('bar2',false)
        assert(not S.engines[bar] and S.wants[bar]==nil)
    ''')
    lua = hidden_runtime("roundEval=true")
    lua.execute('''
        local S=ns.CooldownTraceSensor
        assert(not S.available and next(S.sensors)==nil and next(S.timers)==nil)
        Aura('party1',1719,12)
        T.rows[2].observer:Fire('OnEvent','UNIT_SPELLCAST_SUCCEEDED',nil,nil,1719)
        assert(T.ledger.warrior[1719] and HiddenView(T,2,1719)==nil)
    ''')


def test_toc_loads_sensor_between_catalog_and_engine():
    toc = (ROOT / "DDingUI_Toolkit.toc").read_text(encoding="utf-8-sig")
    assert (toc.index("Modules\\CooldownTrace\\Data.lua") < toc.index("Modules\\CooldownTrace\\Sensor.lua")
            < toc.index("Modules\\CooldownTrace\\Stops.lua")
            < toc.index("Modules\\CooldownTrace\\CooldownTrace.lua"))
    source = (ROOT / "Modules/CooldownTrace/Sensor.lua").read_text(encoding="utf-8")
    assert "COMBAT_LOG_EVENT" not in source and "SendAddonMessage" not in source


def test_fixed_base_seconds_and_public_party_uses_share_the_stamp_renderer():
    lua = hidden_runtime()
    lua.execute('''
        local S=ns.CooldownTraceSensor
        GetSpellBaseCooldown=function() error('observer base cooldown must not be read') end
        assert(S.Seconds(1719)==90 and S.Seconds(107574)==nil)
        -- Public cast events and readable aura APIs cannot bypass the party sensors.
        T.rows[2].observer:Fire('OnEvent','UNIT_SPELLCAST_SUCCEEDED','party1',nil,1719)
        assert(T.ledger.warrior==nil)
        Aura('party1',1719,12)
        T:UpdateCooldowns()
        local icon=IconOf(T,2,1719)
        assert(T.ledger.warrior[1719].seconds==90)
        assert(HiddenView(T,2,1719)=='1:30' and icon.timerLayer.alpha==0)
        Aura('party1',1719,nil)
        Advance(91); T:UpdateCooldowns()
        assert(HiddenView(T,2,1719)==nil and S.faults==0)
    ''')


def test_aura_churn_uses_two_delayed_reads_and_vanish_gets_three_quick_frames():
    lua = hidden_runtime("units.party3={guid='rogue',class='ROGUE',name='도적'}; groupSize=4")
    lua.execute('''
        local S=ns.CooldownTraceSensor
        -- No polling while idle or for updated-only payloads.
        local version=S.timers.party1[1719].version
        Emit('UNIT_AURA','party1',{updatedAuraInstanceIDs={1}})
        Advance(.1)
        assert((S.pending.party1 or 0)==0 and S.timers.party1[1719].version==version)
        buffs.party1={[1719]={duration=12}}
        Emit('UNIT_AURA','party1',{addedAuras={}})
        Advance(.1); assert(T.ledger.warrior==nil and S.pending.party1==2)
        Advance(.1); assert(T.ledger.warrior[1719] and S.pending.party1==1)
        Advance(.2); assert(S.pending.party1==0)
        -- A sub-0.2-second Vanish can be seen on the next frame.
        combat=true; hiddenAuras=true
        buffs.party3={[11327]={duration=.05}}
        Emit('UNIT_AURA','party3',{addedAuras={}})
        Advance(.01); assert(S.quick.party3==2)
        D:UpdateCooldowns(); assert(Fresh(HiddenView(D,4,1856)))
        buffs.party3={}; Advance(.01); Advance(.01)
        assert(S.quick.party3==0 and S.faults==0)
    ''')


def test_hostile_cc_debuffs_exclude_self_and_share_anonymous_edges_across_owners():
    lua = hidden_runtime("units.party2={guid='warrior2',class='WARRIOR',name='전사2'}")
    lua.execute('''
        local S=ns.CooldownTraceSensor
        units.nameplate1={enemy=true,fighting=true}
        local cc=ns.CooldownTraceEngine.New('SkillTrace_ccTest','cc')
        cc:OnEnable(); cc.enabled=true; Settle()
        local feed=S.stops.feeds[46968]
        assert(#feed.probes==4 and feed.probes[1].on)
        assert(feed.probes[1].container.auraFilter=='HARMFUL|!PLAYER')
        combat=true; hiddenAuras=true
        Aura('nameplate1',132168,2); cc:UpdateCooldowns()
        assert(Fresh(HiddenView(cc,2,46968),40) and Fresh(HiddenView(cc,3,46968),40))
        assert(cc.ledger.warrior==nil and cc.ledger.warrior2==nil)
        -- The same debuff on several enemies, or a falling edge, cannot restart it.
        local timer=S.timers.party1[46968]
        local stamp=Reveal(timer.slots[timer.cur].c)
        units.nameplate2={enemy=true,fighting=true}; Emit('NAME_PLATE_UNIT_ADDED','nameplate2')
        Aura('nameplate2',132168,2); Aura('nameplate1',132168,nil)
        assert(Reveal(timer.slots[timer.cur].c)==stamp)
        Aura('nameplate2',132168,nil)
        -- A player's own CC is not a party member's use.
        buffs.nameplate1={[132168]={duration=2,source='player'}}
        Settle()
        assert(Reveal(timer.slots[timer.cur].c)==stamp)
        -- Existing probes rebind during combat, without constructing protected aura groups.
        units.nameplate1=nil; Emit('NAME_PLATE_UNIT_REMOVED','nameplate1')
        units.nameplate3={enemy=true,fighting=true}; Emit('NAME_PLATE_UNIT_ADDED','nameplate3')
        buffs.nameplate2={}; Settle()
        Aura('nameplate3',132168,2); cc:UpdateCooldowns()
        assert(Fresh(HiddenView(cc,2,46968),40) and S.faults==0)
        cc:OnDisable()
        assert(not S.stops.running and not feed.probes[1].on)
    ''')


def test_cc_pool_filters_enemies_handles_delay_blind_and_resets():
    lua = hidden_runtime("units.party1={guid='shaman',class='SHAMAN',name='주술사'}; "
                         "units.party2={guid='rogue',class='ROGUE',name='도적'}")
    lua.execute('''
        local S=ns.CooldownTraceSensor
        local cc=ns.CooldownTraceEngine.New('SkillTrace_ccTest','cc')
        cc:OnEnable(); cc.enabled=true
        units.nameplate1={enemy=false,fighting=true}
        units.nameplate2={enemy=true,fighting=true,dead=true}
        units.nameplate3={enemy=true,fighting=true,boss=true}
        units.nameplate4={enemy=true,fighting=true}
        for index=1,4 do Emit('NAME_PLATE_UNIT_ADDED','nameplate'..index) end
        Settle()
        assert(#S.stops.slots==1 and S.stops.slots[1]=='nameplate4')
        assert(#S.stops.feeds[2094].probes==10)
        combat=true; hiddenAuras=true
        Advance(3); Aura('nameplate4',118905,3); cc:UpdateCooldowns()
        -- Capacitor is detected at impact, two seconds after its cooldown started.
        local text=HiddenView(cc,2,192058)
        assert(text=='58' or text=='57',tostring(text))
        -- Blind already running when a nameplate is assigned establishes a baseline.
        units.nameplate5={enemy=true,fighting=false}
        buffs.nameplate5={[2094]={duration=30}}
        Emit('NAME_PLATE_UNIT_ADDED','nameplate5'); Settle(); cc:UpdateCooldowns()
        assert(HiddenView(cc,3,2094)==nil)
        Aura('nameplate5',2094,nil); Aura('nameplate5',2094,30); cc:UpdateCooldowns()
        assert(Fresh(HiddenView(cc,3,2094)))
        -- A key reset waits two seconds before taking a new baseline.
        cc.events:Fire('OnEvent','CHALLENGE_MODE_START')
        Settle(); cc:UpdateCooldowns()
        assert(not S.timers.party2[2094].primed and HiddenView(cc,3,2094)==nil)
        Advance(2); Settle(); assert(S.timers.party2[2094].primed and S.faults==0)
    ''')


def test_reused_party_sensors_recover_combat_roster_swaps_and_hidden_names_use_active_color():
    lua = hidden_runtime()
    lua.execute('''
        local S,G=ns.CooldownTraceSensor,ns.SkillTracker
        EnableCommon(); G:SetEnabled('bar2',true); G:SetTypeFrame('cooldowns',2)
        local bar=ns.modules.SkillTrace_bar2
        local cfg=ns.db.profile.CooldownTrace.extraBars.bar2
        cfg.textColors.useClassColor.active=false; cfg.textColors.activeColor={.3,.4,.5,1}
        bar:ApplySettings(); Settle()
        combat=true; hiddenAuras=true
        units.party1={guid='newwarrior',class='WARRIOR',name='새 전사'}
        bar:RefreshRoster(); Settle()
        assert(S.timers.party1[1719].primed)
        Aura('party1',1719,12); bar:UpdateCooldowns()
        assert(Fresh(HiddenView(bar,2,1719),90))
        local icon=IconOf(bar,2,1719)
        local name=icon.hidden.names[S.timers.party1[1719].cur]
        assert(name:IsShown() and name.clips and name.text:GetText()==units.party1.name)
        assert(name.text.textColor[1]==.3 and name.text.textColor[2]==.4 and Reveal(name.alpha)==1)
        assert(S.faults==0)
    ''')


def test_first_probes_deferred_during_combat_take_running_effects_as_baselines():
    lua = hidden_runtime("units.party1={guid='firstmage',class='MAGE',name='법사1'}")
    lua.execute('''
        local S=ns.CooldownTraceSensor
        local cc=ns.CooldownTraceEngine.New('SkillTrace_ccTest','cc')
        cc:OnEnable(); cc.enabled=true; Settle()
        combat=true; hiddenAuras=true
        units.party1={guid='warrior',class='WARRIOR',name='전사'}
        units.party3={guid='mage',class='MAGE',name='법사'}; groupSize=4
        buffs.party3={[365362]={duration=15}}
        T:RefreshRoster(); cc:RefreshRoster(); Settle()
        units.nameplate1={enemy=true,fighting=true}
        buffs.nameplate1={[132168]={duration=4}}
        Emit('NAME_PLATE_UNIT_ADDED','nameplate1'); Settle()
        assert(#S.stops.feeds[46968].probes==0 and not S.timers.party1[46968].primed)
        combat=false
        T:ApplySettings(); cc:ApplySettings(); Settle()
        T:UpdateCooldowns(); cc:UpdateCooldowns()
        assert(S.timers.party3[365350].primed and HiddenView(T,4,365350)==nil)
        assert(S.timers.party1[46968].primed and HiddenView(cc,2,46968)==nil)
        Aura('party3',365362,nil); Aura('party3',365362,15); T:UpdateCooldowns()
        assert(Fresh(HiddenView(T,4,365350),90) and S.faults==0)
    ''')


def test_group_spell_picker_moves_only_selected_spells_and_bulk_actions_keep_other_groups():
    for locale in ('koKR', 'enUS'):
        lua = trace_runtime(locale)
        load(lua, 'UI/Controls.lua')
        lua.execute('''
            local G,db=ns.SkillTracker,ns.db.profile.CooldownTrace
            local common=EnableCommon()
            G:SetTypeFrame('defensives',2)
            G:SetSpellFrame(47788,3)
            G:SetSpellPriority(47788,41); G:SetSpellGlow(47788,false)
            G:SetSpellPriority(33206,42); G:SetSpellGlow(33206,false)
            local position,bar,spells=db.common.position,db.extraBars.bar2,db.defensives.spells.PRIEST
            local host=CreateFrame('Frame',nil,UIParent); host:SetSize(600,600)
            local list=common:CreateSpellList(host,2)
            list.classPicker:SetValue('PRIEST'); list.categoryPicker:SetValue('defensives',false)
            local function Row(id)
                for _,row in ipairs(list.rows) do if row.spellID==id then return row end end
            end
            local own,other=Row(33206),Row(47788)
            assert(own.check:GetChecked() and not other.check:GetChecked())
            assert(not own.frame:IsShown() and not list.header.frame:IsShown())
            combat=true; restrictions=true
            other.check:Fire('OnClick','LeftButton')
            assert(G:Frame(47788)==3 and not other.check:GetChecked())
            assert(not G:ResetSpells(false,2) and G:IsSelected(33206,'PRIEST'))
            combat=false; restrictions=false
            other.check:Fire('OnClick','LeftButton')
            assert(G:Frame(47788)==2 and G:IsSelected(47788,'PRIEST') and other.check:GetChecked())
            assert(db.spellPriority[47788]==41 and db.spellGlow[47788]==false)
            G:SetSpellFrame(47788,3); list.Populate()
            list.clearSpells:Fire('OnClick','LeftButton')
            assert(not G:IsSelected(33206,'PRIEST') and G:IsSelected(47788,'PRIEST'))
            assert(db.spellPriority[33206]==nil and db.spellGlow[33206]==nil)
            assert(db.spellPriority[47788]==41 and db.spellGlow[47788]==false and G:Frame(47788)==3)
            list.resetSpells:Fire('OnClick','LeftButton')
            assert(G:IsSelected(33206,'PRIEST') and G:IsSelected(47788,'PRIEST'))
            assert(not other.check:GetChecked() and own.check:GetChecked())
            assert(db.common.position==position and db.extraBars.bar2==bar and db.defensives.spells.PRIEST==spells)
            assert(not G:SetSpells('defensives','PRIEST',47788,true,9))
            G:SetSpells('defensives','PRIEST',nil,false,2)
            assert(not G:IsSelected(33206,'PRIEST') and G:IsSelected(47788,'PRIEST'))
            G:ResetSpells(false,0)
            assert(G:IsSelected(47788,'PRIEST') and G:Frame(47788)==3)
        ''')

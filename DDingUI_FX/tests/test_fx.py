"""Execute the shipped TOC, Lua 5.1 UI and runtime with mock WoW APIs.

python DDingUI_FX/tests/test_fx.py
Pillow checks the delivered TGA atlas; WoW rendering/taint/secret-engine remain in-game checks.
"""
from pathlib import Path
from PIL import Image
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
EXTRA = r'''
FX={}; auras={}; registrations={}; added=0; removed=0; restrictions=false
playingSounds={}
C_Sound={IsPlaying=function(handle) return playingSounds[handle] or false end}
local playSoundFile=PlaySoundFile
function PlaySoundFile(path,channel)
    if soundFails then return false end
    local played,handle=playSoundFile(path,channel)
    if played then playingSounds[handle]=true end
    return played,handle
end
function StopSound(handle) playingSounds[handle]=nil end
WOW_PROJECT_ID=1; WOW_PROJECT_MAINLINE=1
Minimap=CreateFrame('Frame','Minimap',UIParent)
Minimap:SetSize(140,140); Minimap:SetPoint('TOPRIGHT',UIParent,'TOPRIGHT',-20,-20)
function IsShiftKeyDown() return shiftDown or false end
function methods:GetSize() return self:GetWidth(),self:GetHeight() end
function methods:GetVertexColor() return unpack(self.vertexColor or {1,1,1,1}) end
function methods:SetVertexColor(...) self.vertexColor={...} end
function methods:SetDesaturated(v) self.desaturated=v end
function methods:CreateAnimationGroup() return CreateFrame('AnimationGroup',nil,self) end
function methods:CreateAnimation() return CreateFrame('Animation',nil,self) end
function methods:Play() self.playing=true end
function methods:Stop() self.playing=false end
for _,key in ipairs({'SetFixedFrameStrata','SetFixedFrameLevel','SetHighlightTexture','SetOrder','SetDuration','SetFromAlpha','SetToAlpha','SetStartDelay','SetToFinalAlpha','LockHighlight','UnlockHighlight'}) do methods[key]=function() end end
local originalXpcall=xpcall
function xpcall(callback,handler,...)
    local args,n={...},select('#',...)
    return originalXpcall(function() return callback(unpack(args,1,n)) end,handler)
end
function wipe(t) for k in pairs(t) do t[k]=nil end return t end
function geterrorhandler() return error end
function IsMouseButtonDown() return false end
function methods:GetFont() return self.fontPath,self.fontSize,self.fontFlags end
function methods:GetBottom() local _,y=self:Rect(); return y end
function methods:GetTop() local _,y,_,h=self:Rect(); return y+h end
function methods:GetStringWidth() return Measure(self.text or '',self.fontSize or 12) end
function methods:GetVerticalScrollRange() return math.max(0,(self.scrollChild and self.scrollChild:GetHeight() or 0)-self:GetHeight()) end
function methods:SetScale(v) self.scale=v end
function methods:GetScale() return self.scale or 1 end
function methods:GetEffectiveScale() return (self.scale or 1)*(self.parent and self.parent:GetEffectiveScale() or 1) end
function methods:SetValue(v) self.value=v; self:Fire('OnValueChanged',v) end
function methods:GetValue() return self.value end
function methods:RegisterUnitEvent(event,unit) self.events[event]=unit end
function methods:SetTexCoord(...) self.texCoord={...} end
function methods:SetBlockingLoadsRequested(value) self.blockingLoads=value end
function methods:SetTexture(path,wrapX,wrapY,filter)
    self.texture=path; self.filter=filter; self.textureWrites=(self.textureWrites or 0)+1
    return not missingTexture and (not missingTexturePath or path~=missingTexturePath)
end
function methods:SetMinMaxValues(a,b) self.min,self.max=a,b end
function methods:SetThumbTexture(t) self.thumb=t end
for _,key in ipairs({'SetTextInsets','SetNumeric','SetMaxLetters','EnableKeyboard','HighlightText','SetValueStep','SetObeyStepOnDrag','SetOrientation','SetHitRectInsets','SetClipsChildren','SetToplevel','SetNormalAtlas','SetPushedAtlas','SetBlendMode'}) do methods[key]=function() end end
function methods:SetFocus() self.focus=true; self:Fire('OnEditFocusGained') end
function methods:HasFocus() return self.focus end
function methods:SetAltArrowKeyMode(value) self.altArrowKeyMode=value end
-- StyleLib 1.4 edit remote: anchor readback, formatted HUD text, keyboard capture.
function methods:GetPoint() local p,a=next(self.points); if p then return p,a[1],a[2],a[3],a[4] end end
function methods:SetFormattedText(fmt,...) self.text=string.format(fmt,...) end
for _,key in ipairs({'SetPropagateKeyboardInput','SetClampRectInsets'}) do methods[key]=function() end end
function GetCurrentKeyBoardFocus() return nil end
function IsControlKeyDown() return ctrlDown or false end
function Key(key) local r=FX.editor.remote; r:GetScript('OnKeyDown')(r,key) end
function Check(label)
    for _,o in ipairs(objects) do
        if o.box and o.label and o.label.text==label and o.parent==FX.editor.remote then o.box:Fire('OnClick'); return o end
    end
    error('Checkbox not found: '..label)
end
function methods:ClearFocus()
    if self.focus then self.focus=false; self:Fire('OnEditFocusLost') end
end
function Commit(row,text)
    row.editBox:SetFocus(); row.editBox:SetText(text); row.editBox:Fire('OnEnterPressed')
end
function Advance(seconds)
    now=now+seconds
    for _,frame in ipairs(objects) do
        if frame:IsVisible() then frame:Fire('OnUpdate',seconds) end
    end
end
C_Timer.After=function(_,callback) callback() end
C_Spell={GetSpellInfo=function(input)
    local id=tonumber(input) or (input=='테스트 스킬' and 100)
    if id then return {spellID=id,name='테스트 스킬 '..id,iconID=123} end
end, RequestLoadSpellData=function() end}
C_Secrets={ShouldAurasBeSecret=function() return restrictions end,
    ShouldSpellAuraBeSecret=function() return auraRestricted or false end}
Enum={UnitAuraSoundTrigger={Added=0}}
C_UnitAuras={GetPlayerAuraBySpellID=function(id)
    if auraError then error('restricted') end
    return auras[id]
end, AddAuraSound=function(trigger,info)
    assert(not combat and not restrictions)
    if addError then error('registration unavailable') end
    added=added+1; registrations[added]={trigger=trigger,info=info}; return added
end, RemoveAuraSound=function(id)
    assert(not combat and not restrictions)
    if removeError then error('removal unavailable') end
    registrations[id]=nil; removed=removed+1
end}
function Emit(event,...) FX.events:Fire('OnEvent',event,...) end
function ClickText(text,parent)
    for _,o in ipairs(objects) do
        if o.label and o.label.text==text and (not parent or o.parent==parent) then
            o:Fire('OnClick','LeftButton'); return o
        end
    end
    error('Button not found: '..text)
end
'''


def runtime(saved=""):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().Measure = lambda text, size: len(text) * size * .65
    lua.execute((ROOT / "tests/wow_mock.lua").read_text(encoding="utf-8"))
    lua.execute(EXTRA)
    for line in (ROOT / "DDingUI_FX.toc").read_text(encoding="utf-8").splitlines():
        if not line or line.startswith("#"):
            continue
        path = ROOT / line.replace("\\", "/")
        assert path.is_file(), path
        lua.execute('assert(loadstring(...))("DDingUI_FX",FX)', path.read_text(encoding="utf-8-sig"))
    lua.execute(saved)
    lua.execute('Emit("ADDON_LOADED","DDingUI_FX")')
    return lua


def check():
    lua = runtime(r'''
        FX.Catalog.mine={name='내 TGA',path='Interface/AddOns/DDingUI_FX/Media/mine.tga',columns=4,rows=2,frames=6,fps=10}
    ''')
    lua.execute(r'''
        assert(#FX.db.rules==0 and next(FX.db.presets)==nil)
        assert(DDingUI_StyleLib==nil) -- private embedded library must not replace the suite's style
        assert(FX.events.events.UNIT_SPELLCAST_START=='player')
        assert(not FX.events.events.COMBAT_LOG_EVENT_UNFILTERED)
        FX:ToggleUI()
        w=FX.window
        assert(w:IsShown() and not w.hover:IsShown() and not w.hover.player.playing)
        assert(not w.save and type(w.enabled)~='table' and not w.stage and not FX.OpenPresetEditor)
        assert(not w.geometry and not w.speed)
        assert(#w.cards==9 and w.cards[1].key=='')
        local minazukiCard
        for _,card in ipairs(w.cards) do if card.key=='minazuki' then minazukiCard=card end end
        assert(minazukiCard and minazukiCard.image.texture:find('Minazuki_2.tga',1,true))
        assert(minazukiCard.image.texCoord[1]==0 and minazukiCard.image.texCoord[3]==.25)
        local voidCard
        for _,card in ipairs(w.cards) do if card.key=='unlimitedVoid' then voidCard=card end end
        assert(voidCard and voidCard.image.texture:find('UnlimitedVoid_3.tga',1,true))
        assert(voidCard.image.texCoord[1]==0 and voidCard.image.texCoord[2]==.25
            and voidCard.image.texCoord[3]==0 and voidCard.image.texCoord[4]==.25) -- frame 32, page 3
        voidCard:Fire('OnEnter')
        assert(w.hover.player.playing and w.hover.player.preset==FX.presets.unlimitedVoid)
        assert(#w.hover.player.textures==4 and w.hover.player.frameIndex==0)
        voidCard:Fire('OnLeave'); assert(not w.hover.player.playing)
        local rewindCard
        for _,card in ipairs(w.cards) do if card.key=='timeRewind' then rewindCard=card end end
        assert(rewindCard and rewindCard.image.texture==FX.presets.timeRewind.path)
        assert(rewindCard.image.texCoord[1]==6/8 and rewindCard.image.texCoord[3]==3/8) -- frame 30, halfway
        local soundCount=#sounds
        rewindCard:Fire('OnEnter')
        assert(w.hover.player.playing and w.hover.player.loop and #sounds==soundCount)
        rewindCard:Fire('OnLeave'); assert(not w.hover.player.playing)
        local zoltraakCard
        for _,card in ipairs(w.cards) do if card.key=='zoltraak' then zoltraakCard=card end end
        assert(zoltraakCard and zoltraakCard.image.texture==FX.presets.zoltraak.path)
        assert(zoltraakCard.image.texCoord[1]==0 and zoltraakCard.image.texCoord[3]==6/8) -- frame 48, halfway
        local hollowCard
        for _,card in ipairs(w.cards) do if card.key=='hollowPurple' then hollowCard=card end end
        assert(hollowCard and hollowCard.image.texture==FX.presets.hollowPurple.path)
        assert(hollowCard.image.texCoord[1]==0 and hollowCard.image.texCoord[3]==3/8) -- frame 24, halfway
        local mineCard
        for _,card in ipairs(w.cards) do if card.key=='mine' then mineCard=card end end
        assert(mineCard)
        local thumbnailPreset=FX.presets.mine
        for _,case in ipairs({{6,1,.75,1,0,.5},{20,3,.5,.75,0,.5},{1,1,0,.25,0,.5}}) do
            thumbnailPreset.frames,thumbnailPreset.pages=case[1],case[2]
            FX:RefreshPresets()
            local path=case[1]==20 and thumbnailPreset.path:sub(1,-5)..'_2.tga' or thumbnailPreset.path
            assert(mineCard.image.texture==path)
            for i=1,4 do assert(mineCard.image.texCoord[i]==case[i+2]) end
            assert(not w.cards[1].image:IsShown() and w.cards[1].none:IsShown())
        end
        thumbnailPreset.frames,thumbnailPreset.pages=6,1
        FX:RefreshPresets()
        w.mode.buttons[2]:Fire('OnClick','LeftButton'); assert(FX.draft.trigger=='AURA' and #w.trigger.items==1)
        w.mode.buttons[1]:Fire('OnClick','LeftButton'); assert(FX.draft.trigger=='SUCCESS' and #w.trigger.items==2)
        assert(#FX.db.rules==0) -- empty draft is not persisted
        assert(FX:ResolveSpell('테스트 스킬')==100)
        assert(FX:ResolveSpell('not a spell')==nil)
        assert(FX:ResolveSpell('-3')==nil)
        FX.LSM:Register('sound','FX test sound','Interface\\test.ogg')
        assert(#w.sound.items>=2) -- late media registration refreshes the actual dropdown
        w.sound:Open(); w.sound:ApplyFilter('FX test sound')
        assert(#w.sound.filtered==1 and w.sound.filtered[1].value=='FX test sound')
        w.sound.rows[1].soundButton:Fire('OnClick'); assert(#sounds==1)
        w.sound.rows[1]:Fire('OnClick','LeftButton'); assert(FX.draft.sound=='FX test sound')
        assert(not w.sound.listFrame:IsShown())

        p=FX.presets.mine
        local before=#sounds
        mineCard:Fire('OnEnter')
        assert(w.hover:IsShown() and w.hover.player.playing and w.hover.player.loop)
        assert(w.hover.player.frameIndex==0)
        assert(FX.draft.preset=='' and #FX.db.rules==0 and #sounds==before)
        w.hover.player:Fire('OnUpdate',.41)
        assert(w.hover.player.frameIndex==4 and w.hover.player.texture.texCoord[3]==.5)
        w.hover.player:Fire('OnUpdate',.25); assert(w.hover.player.frameIndex==0)
        mineCard:Fire('OnLeave'); assert(w.hover.player:GetScript('OnUpdate')==nil)
        mineCard:Fire('OnEnter'); w.gallery:Fire('OnMouseWheel',-1)
        assert(not w.hover:IsShown() and not w.hover.player.playing)
        mineCard:Fire('OnEnter'); w:Hide(); Advance(.2); assert(not w.hover.player.playing)
        w:Show(); assert(not w.hover.player.playing)
        missingTexture=true; mineCard:Fire('OnEnter')
        assert(not w.hover.player.playing and w.hover.error:IsShown())
        missingTexture=false; mineCard:Fire('OnLeave')
        mineCard:Fire('OnClick'); assert(FX.draft.preset=='mine')
        local bad=FX:ValidatePreset({name='bad',path='C:\\test.tga',columns=4,rows=2,frames=6,fps=10})
        assert(not bad)
        assert(not FX:ValidatePreset({name='bad',path=p.path,columns=0,rows=2,frames=6,fps=10}))
        assert(not FX:ValidatePreset({name='bad',path=p.path,columns=4,rows=2,frames=6,fps=0/0}))
        assert(not FX:NormalizeRule({spellID=100000001,trigger='SUCCESS'}))

        Commit(w.spell,'100')
        w.editMode:Fire('OnClick','LeftButton'); e=FX.editor
        Commit(e.inputs.x,'82'); Commit(e.inputs.scale,'125%')
        assert(#FX.db.rules==1 and FX.db.rules[1].x==82 and FX.db.rules[1].scale==125)
        assert(FX.db.rules[1].opacity==100 and e.player:GetAlpha()==1)
        assert(w.rows[1].icon.texture==123 and w.rows[1].delete)
        Commit(e.inputs.x,'bad'); assert(FX.db.rules[1].x==82 and e.inputs.x.editBox:GetText()=='82')
        e.inputs.y.editBox:SetFocus(); e.inputs.y.editBox:SetText('64')
        e.done:Fire('OnClick','LeftButton'); Advance(.2)
        Commit(w.spell,'invalid'); assert(FX.db.rules[1].spellID==100 and w.spell:GetValue()=='100')
        w.test:Fire('OnClick','LeftButton')
        assert(not w:IsShown() and FX.active[FX.testRule].playing and FX.db.rules[1].y==64)
        assert(FX.active[FX.testRule]:GetWidth()==320 and FX.active[FX.testRule]:GetHeight()==320)
        assert(sounds[#sounds][1]=='Interface\\test.ogg')
        FX.active[FX.testRule]:Fire('OnUpdate',1); assert(not FX.active[FX.testRule].playing)
        FX.events:Fire('OnUpdate',0); assert(not w:IsShown()) -- wait for the longer sound
        playingSounds[FX.previewSoundHandle]=nil
        FX.events:Fire('OnUpdate',0)
        assert(w:IsShown() and not FX.testing and not FX.events:GetScript('OnUpdate'))
        w.editMode:Fire('OnClick','LeftButton')
        e.inputs.speed.editBox:SetFocus(); e.inputs.speed.editBox:SetText('2.5'); e.inputs.speed.editBox:ClearFocus()
        assert(FX.db.rules[1].speed==2.5)
        e.inputs.speed.editBox:SetFocus(); e.inputs.speed.editBox:SetText('bad'); e.inputs.speed.editBox:ClearFocus()
        assert(FX.db.rules[1].speed==2.5)
        Commit(e.inputs.speed,'2.53'); assert(math.abs(FX.db.rules[1].speed-2.55)<.001)
        assert(e.inputs.speed.editBox:GetText()=='2.55' and e.player.speed==FX.db.rules[1].speed)
        Commit(e.inputs.speed,'1'); e.done:Fire('OnClick','LeftButton'); Advance(.2)
        rule=FX.db.rules[1]
        local before=#sounds
        Emit('UNIT_SPELLCAST_SUCCEEDED','target','cast',100); assert(#sounds==before)
        Emit('UNIT_SPELLCAST_SUCCEEDED',SECRET,'cast',100); assert(#sounds==before)
        Emit('UNIT_SPELLCAST_SUCCEEDED','player','cast',SECRET); assert(#sounds==before)
        Emit('UNIT_SPELLCAST_START','player','cast',100); assert(#sounds==before)
        Emit('UNIT_SPELLCAST_SUCCEEDED','player','cast',100)
        assert(#sounds==before+1 and FX.active[rule].playing)
        live=FX.active[rule]; live:Fire('OnUpdate',.61); assert(not live.playing)
        Emit('UNIT_SPELLCAST_SUCCEEDED','player','cast2',100)
        assert(FX.active[rule]==live and live.playing and live.frameIndex==0)

        FX:ApplyChange('trigger','START'); rule=FX.db.rules[1]
        for _,event in ipairs({'UNIT_SPELLCAST_START','UNIT_SPELLCAST_CHANNEL_START','UNIT_SPELLCAST_EMPOWER_START'}) do
            local n=#sounds; Emit(event,'player','cast',100); assert(#sounds==n+1)
        end
        combat=true
        assert(not FX:SaveRule(1,FX.draft)); assert(not FX:DeleteRule(1))
        Commit(w.spell,'200'); assert(FX.db.rules[1].spellID==100 and w.spell:GetValue()=='100')
        w.cards[1]:Fire('OnClick'); assert(FX.draft.preset=='mine')
        combat=false
        FX:ApplyChange('trigger','AURA'); rule=FX.db.rules[1]
        assert(added==1 and registrations[1].info.spellID==100)
        local before=#sounds
        auras[100]={spellId=100,isHelpful=true}; Emit('UNIT_AURA','player')
        assert(FX.active[rule].playing and #sounds==before) -- native sound must not be replayed by Lua
        FX.active[rule]:Stop(); Emit('UNIT_AURA','player'); assert(not FX.active[rule].playing)
        auras[100]=nil; Emit('UNIT_AURA','player')
        auras[100]={spellId=100,isHelpful=true}; Emit('UNIT_AURA','player'); assert(FX.active[rule].playing)
        FX.active[rule]:Stop(); auraRestricted=true
        auras[100]=nil; Emit('UNIT_AURA','player'); assert(FX.auraState[100]==nil)
        auraRestricted=false; auras[100]={spellId=100,isHelpful=true}
        Emit('UNIT_AURA','player'); assert(not FX.active[rule].playing) -- becoming readable is not a fresh gain
        auras[100]=SECRET; Emit('UNIT_AURA','player'); assert(FX.auraState[100]==nil)
        auras[100]={spellId=SECRET,isHelpful=true}; Emit('UNIT_AURA','player'); assert(FX.auraState[100]==nil)
        auraError=true; Emit('UNIT_AURA','player'); assert(FX.auraState[100]==nil); auraError=false
        auras[100]=nil
        assert(FX:SaveRule(nil,rule)==2 and added==1) -- identical native registration is deduplicated
        FX:SyncSounds(); assert(added==1)
        removeError=true
        FX:DeleteRule(2); FX:DeleteRule(1)
        assert(FX.soundPending and registrations[1])
        removeError=false; Emit('PLAYER_REGEN_ENABLED'); assert(not FX.soundPending and not registrations[1])
        assert(#FX.db.rules==0 and next(FX.db.presets)==nil)
        addError=true
        local r={spellID=100,trigger='AURA',sound='FX test sound'}
        assert(FX:SaveRule(nil,r) and FX.soundPending)
        restrictions=true; addError=false; local attempts=added
        Emit('ADDON_RESTRICTION_STATE_CHANGED'); assert(added==attempts)
        restrictions=false; Emit('ADDON_RESTRICTION_STATE_CHANGED')
        assert(added==attempts+1 and not FX.soundPending)
        FX:DeleteRule(1)
        FX:SelectRule(nil)
        w:Hide(); Advance(.2); assert(not w.sound.listFrame:IsShown() and w.hover.player:GetScript('OnUpdate')==nil)
        w:Show()
        for _,id in ipairs({101,202,303}) do
            local count=#FX.db.rules
            w.add:Fire('OnClick','LeftButton'); assert(#FX.db.rules==count and not FX.selected)
            Commit(w.spell,tostring(id))
        end
        assert(#FX.db.rules==3 and FX.selected==3)
        w.search:SetText('202'); assert(w.rows[1].index==2)
        w.rows[1].delete:Fire('OnClick','LeftButton')
        assert(#FX.db.rules==2 and FX.selected==2 and FX.draft.spellID==303)
        w.search:SetText(''); w.rows[2].delete:Fire('OnClick','LeftButton')
        assert(FX.selected==1 and FX.draft.spellID==101)
        w.rows[1].delete:Fire('OnClick','LeftButton')
        assert(#FX.db.rules==0 and not FX.selected and not FX.draft.spellID and w.add:IsVisible())
        w.add:Fire('OnClick','LeftButton'); w.spell.editBox:SetText('404'); w:Hide(); Advance(.2)
        assert(#FX.db.rules==1 and FX.db.rules[1].spellID==404)
        w:Show(); w.editMode:Fire('OnClick','LeftButton')
        Commit(e.inputs.x,'123'); e.done:Fire('OnClick','LeftButton'); Advance(.2)
        mineCard:Fire('OnClick','LeftButton')
        assert(FX.db.rules[1].x==123 and FX.db.rules[1].preset=='mine')
        mineCard:Fire('OnEnter'); w.cards[1]:Fire('OnEnter')
        assert(not w.hover:IsShown() and not w.hover.player.playing)
        -- Real LDB/LibDBIcon code is loaded, including drag and saved angle.
        local icons=LibStub('LibDBIcon-1.0')
        assert(icons:IsRegistered('DDingUI_FX') and FX.minimapButton.db==FX.db.minimap)
        assert(FX.minimapButton.icon.desaturated and w.titleBar.titleText:IsShown())
        assert(w.titleBar.titleText:GetText()==FX.Style.CreateGradientText('FX','FX'))
        assert(w.titleBar.brandTexture.texture=='Interface\\AddOns\\DDingUI_FX\\Media\\logo_wordmark.tga')
        -- C12: the edit-mode entry is the series title-bar button (close · edit · GUI scale · search).
        local bar=w.titleBar
        assert(w.search:GetParent()==bar and w.editMode==bar.editButton and w.editMode:GetParent()==bar)
        assert(bar.editButton.points.RIGHT[1]==bar.closeBtn and bar.scaleControl.points.RIGHT[1]==bar.editButton)
        assert(w.editMode.label:GetText()=='편집 모드')
        local tx,ty,tw,th=w.test:Rect()
        assert(tw==700)
        assert(w.gallery:GetBottom()>ty+th)
        local color=FX.Style.GetAccent('FX')
        assert(color[1]==77/255 and color[2]==141/255 and color[3]==1)
        for _,o in ipairs(objects) do if o.events.PLAYER_LOGIN then o:Fire('OnEvent','PLAYER_LOGIN') end end
        assert(FX.minimapButton.points.CENTER and FX.minimapButton:IsShown())
        local cx,cy=600,500
        function GetCursorPosition() return cx,cy end
        FX.minimapButton:Fire('OnDragStart'); FX.minimapButton:Fire('OnUpdate',.1)
        assert(FX.db.minimap.minimapPos>=0 and FX.db.minimap.minimapPos<360)
        FX.minimapButton:Fire('OnDragStop'); assert(not FX.minimapButton:GetScript('OnUpdate'))
        FX.minimapButton:Fire('OnClick','LeftButton'); Advance(.2); assert(not w:IsShown())
        FX.minimapButton:Fire('OnClick','LeftButton'); assert(w:IsShown())

        local before=#sounds
        w.editMode:Fire('OnClick','LeftButton')
        e=FX.editor
        assert(e:IsShown() and not w:IsShown() and e.player.playing and #sounds==before)
        assert(e:GetAlpha()==0 and e.grid:GetAlpha()==0 and #e.grid.lines>20)
        Advance(.09); assert(e:GetAlpha()>0 and e:GetAlpha()<1)
        Advance(.8); assert(e:GetAlpha()==1 and e.grid:GetAlpha()==1)
        assert(not e._ddslMotionJobs.editor and not e.grid._ddslMotionJobs.alpha)
        -- C12 remote: one rounded 300px panel at TOP -55 (no saved position yet).
        local rp,_,_,rx,ry=e.remote:GetPoint(1)
        assert(e.remote:IsShown() and e.remote:GetWidth()==300 and rp=='TOP' and rx==0 and ry==-55)
        assert(e.remote.buttons['초기화'] and e.remote.buttons['실행 취소'] and e.remote.buttons['다시 실행'] and e.done)
        assert(e.remote.gridCheck.checked and e.grid:IsShown() and e.gridSpacing==32)
        e.snap.enabled=false
        for _,title in ipairs({w.titleBar,e.titleBar}) do
            local text=title.titleText:GetText()
            assert(not text:find('DDing',1,true) and title.brandTexture:IsShown())
            assert(text:find('|cff4d8dffF|r',1,true)) -- only addon name uses FX blue
            -- StyleLib 1.3: two ring pieces tinted with the FX accent instead of a desaturated logo
            assert(title.brandLogo.leftRing and title.brandLogo.rightRing and not title.brandUI and title.titleText:IsShown())
        end
        assert(e.rule~=FX.db.rules[1] and e.rule.x==123)
        function IsMouseButtonDown() return true end
        local oldX,oldY=e.rule.x,e.rule.y
        UIParent:SetScale(.8)
        e.mover:Fire('OnMouseDown','LeftButton'); cx=cx+80; cy=cy+40
        e.mover:Fire('OnUpdate',.1)
        assert(e.rule.x==oldX+100 and e.rule.y==oldY+50)
        assert(FX.db.rules[1].x==oldX) -- only persist completed drag
        e.mover:Fire('OnMouseUp','LeftButton')
        assert(FX.db.rules[1].x==oldX+100 and not e.mover:GetScript('OnUpdate'))
        UIParent:SetScale(1)
        Commit(e.inputs.scale,'150'); assert(FX.db.rules[1].scale==150 and e.mover:GetWidth()==384 and e.mover:GetHeight()==384)
        Commit(e.inputs.scale,'wrong'); assert(FX.db.rules[1].scale==150 and e.inputs.scale:GetValue()==150)
        assert(FX.draft.scale==150 and not e.inputs.width and not e.inputs.height)
        Commit(e.inputs.opacity,'0'); assert(FX.db.rules[1].opacity==0 and e.player:GetAlpha()==0)
        assert(e.mover:GetAlpha()==1 and e.remote:GetAlpha()==1 and e.hud:IsShown())
        Commit(e.inputs.opacity,'150'); assert(FX.db.rules[1].opacity==100 and e.player:GetAlpha()==1)
        Commit(e.inputs.opacity,'-10'); assert(FX.db.rules[1].opacity==0)
        Commit(e.inputs.opacity,'40%'); assert(FX.db.rules[1].opacity==40 and e.player:GetAlpha()==.4)
        Commit(e.inputs.opacity,'bad'); assert(e.inputs.opacity:GetValue()==40 and e.player:GetAlpha()==.4)
        Key('RIGHT'); assert(FX.db.rules[1].x==oldX+101) -- remote keyboard nudge
        shiftDown=true; Key('UP'); shiftDown=false
        assert(FX.db.rules[1].y==oldY+60)
        e.inputs.y.editBox:SetFocus(); e.inputs.y.editBox:SetText('77')
        e.done:Fire('OnClick','LeftButton')
        assert(e.closing and e:IsShown()); Advance(.2)
        assert(not e:IsShown() and not e.player.playing and w:IsShown() and FX.db.rules[1].y==77)
        assert(FX.draft.y==77 and FX.draft.opacity==40)
        mineCard:Fire('OnEnter'); assert(w.hover.player:GetAlpha()==.4); mineCard:Fire('OnLeave')
        FX:FireRule(FX.db.rules[1]); assert(FX.active[FX.db.rules[1]]:GetAlpha()==.4)
        FX.minimapButton:Fire('OnClick','RightButton'); assert(e:IsShown())
        e.inputs.x.editBox:SetFocus(); e.inputs.x.editBox:SetText('88'); e:Hide() -- Escape commits text
        assert(FX.db.rules[1].x==88 and e.closing and e:IsShown()) -- same fade path as "편집 완료"
        Advance(.2); assert(not e:IsShown() and w:IsShown() and not e.player:GetScript('OnUpdate'))
        FX.minimapButton:Fire('OnClick','RightButton'); assert(e:IsShown())
        e.mover:Fire('OnMouseDown','LeftButton'); cx=cx+30; e.mover:Fire('OnUpdate',.1)
        combat=true; Emit('PLAYER_REGEN_DISABLED')
        assert(not e:IsShown() and FX.db.rules[1].x==88 and not e.mover:GetScript('OnUpdate'))
        FX:ToggleEditMode(); assert(not e:IsShown())
        combat=false; restrictions=true; FX:ToggleEditMode(); assert(not e:IsShown()); restrictions=false
        FX:ToggleUI(); FX:ToggleEditMode(); assert(e:IsShown())
        FX.minimapButton:Fire('OnClick','LeftButton'); Advance(.2); assert(not e:IsShown() and w:IsShown())
        FX:ToggleEditMode(); Advance(.8)
        e.snap.enabled=true; assert(e.gridEnabled)
        e.center:Fire('OnClick','LeftButton'); assert(e.rule.x==0 and e.rule.y==0)
        e.mover:Fire('OnMouseDown','LeftButton'); cx=cx+30; cy=cy+3
        e.mover:Fire('OnUpdate',.1)
        assert(e.rule.x==32 and e.rule.y==0 and e.guides:IsShown())
        e.mover:Fire('OnMouseUp','LeftButton'); assert(not e.guides:IsShown())
        shiftDown=true
        e.mover:Fire('OnMouseDown','LeftButton'); cx=cx+2
        e.mover:Fire('OnUpdate',.1); assert(e.rule.x==34)
        e.mover:Fire('OnMouseUp','LeftButton'); shiftDown=false
        e.remote.gridCheck.box:Fire('OnClick'); Advance(.3); assert(not e.gridEnabled and not e.grid:IsShown())
        e.remote.gridCheck.box:Fire('OnClick'); Advance(.8); assert(e.grid:IsShown() and e.grid:GetAlpha()==1)
        Check('스냅'); assert(not e.snap.enabled)
        Commit(e.inputs.scale,'500'); assert(e.rule.scale==400)
        Commit(e.inputs.scale,'0'); assert(e.rule.scale==10)
        Commit(e.inputs.scale,'1%2'); assert(e.rule.scale==10)
        Commit(e.inputs.scale,'125%'); assert(e.rule.scale==125)
        e.inputs.x.editBox:SetFocus(); e.inputs.x.editBox:SetText('47')
        e.inputs.scale.slider:SetValue(150)
        assert(e.rule.x==47 and e.rule.scale==150) -- other pending fields are committed
        -- StyleMover surface: selected (2px + corner brackets), hover brightens.
        assert(e.moverStyle.selected and e.moverStyle.brackets[1]:IsShown())
        e.mover:Fire('OnEnter'); assert(e.moverStyle.hover)
        e.mover:Fire('OnLeave'); assert(not e.moverStyle.hover)
        e.done:Fire('OnClick','LeftButton'); e.done:Fire('OnClick','LeftButton')
        combat=true; Emit('PLAYER_REGEN_DISABLED'); Advance(1)
        assert(not e:IsShown() and not w:IsShown() and not e.player.playing)
        assert(next(e._ddslMotionJobs)==nil and next(e.grid._ddslMotionJobs)==nil)
        assert(not e.remote:IsShown() and not e.grid:IsShown())
        combat=false; FX:ToggleUI(); FX:ToggleEditMode(); Advance(.8)
        assert(e:GetAlpha()==1 and e.remote:IsShown() and e.remote:GetAlpha()==1)
        e:Hide(); Advance(1); assert(not e:IsShown() and not e.mover:GetScript('OnUpdate'))
    ''')
    spec = runtime(r'''
        specIndex=2; specReady=false
        C_SpecializationInfo={
            IsInitialized=function() return specReady end,
            GetSpecialization=function() return specIndex end,
            GetSpecializationInfo=function(index)
                if index==2 then return 63,'화염' elseif index==3 then return 64,'냉기' end
            end,
        }
        DDingUI_FXDB={rules={
            {spellID=100,trigger='SUCCESS',preset='hollowPurple',sound='DD_Hollow Purple',x=11,scale=125,opacity=40},
            {spellID=200,trigger='AURA',preset='timeRewind',sound='DD_Time Rewind',x=-31,scale=80,opacity=75,speed=2},
            {spellID=300,trigger='START',enabled=false},
        },minimap={minimapPos=42}}
    ''')
    spec.execute(r'''
        assert(not FX.db.specID and #FX.db.rules==3) -- delayed login data preserves legacy rules
        specReady=true; Emit('PLAYER_ENTERING_WORLD')
        assert(FX.db.specID==63 and #FX.db.rules==3 and next(FX.db.specRules)==nil)
        assert(added==1 and registrations[1].info.spellID==200)
        FX:ToggleUI(); local w=FX.window
        assert(w.listHeading:GetText()=='화염 · 스킬 목록')
        FX:SelectRule(nil); FX:ToggleEditMode() -- minimap/edit entry also works from the empty add draft
        local e=FX.editor; local picker=e.rulePicker
        assert(e:IsShown() and e.index==1 and #picker.items==3 and e.icon.texture==123)
        assert(e.presetName:GetText():find('화염',1,true))
        local soundsBefore=#sounds
        e.inputs.x.editBox:SetFocus(); e.inputs.x.editBox:SetText('88')
        picker:Open(); picker:ApplyFilter('200'); assert(#picker.filtered==1)
        picker.rows[1]:Fire('OnClick','LeftButton')
        assert(e.index==2 and FX.selected==2 and picker.currentValue==2 and not picker.listFrame:IsShown())
        assert(FX.db.rules[1].x==88 and e.rule.x==-31 and e.rule.scale==80 and e.rule.opacity==75)
        assert(e.player.preset==FX.presets.timeRewind and e.player.speed==2 and e.player:GetAlpha()==.75)
        assert(e.player.loop and #sounds==soundsBefore and math.abs(e.mover:GetWidth()-307.2)<.0001)
        picker:Open(); picker:ApplyFilter('시간 역행'); assert(#picker.filtered==1); picker:Close()
        assert(FX:SelectEditRule(3) and not e.player.playing) -- disabled/sound-only rules are still selectable
        assert(not FX:SelectEditRule(999) and e.index==3 and picker.currentValue==3)
        combat=true; assert(not FX:SelectEditRule(1) and e.index==3); combat=false
        assert(FX:SelectEditRule(2))
        FX:CloseEditMode(true); assert(not FX:SelectEditRule(1)); Advance(.2)
        w.search:SetText('no matches'); FX:ToggleEditMode()
        e.inputs.opacity.editBox:SetFocus(); e.inputs.opacity.editBox:SetText('60')
        picker:Open(); FX:FireRule(FX.db.rules[1]); local oldPlayer=FX.active[FX.db.rules[1]]
        specIndex=3; Emit('PLAYER_SPECIALIZATION_CHANGED','party1'); Emit('PLAYER_SPECIALIZATION_CHANGED',SECRET)
        assert(FX.db.specID==63 and e:IsShown())
        Emit('PLAYER_SPECIALIZATION_CHANGED','player')
        assert(FX.db.specID==64 and #FX.db.rules==0 and #FX.db.specRules[63]==3 and not FX.db.specRules[64])
        assert(FX.db.specRules[63][2].opacity==60 and not oldPlayer.playing and next(FX.active)==nil)
        assert(not e:IsShown() and not e.player.playing and not picker.listFrame:IsShown())
        assert(w:IsShown() and w.search:GetText()=='' and w.listHeading:GetText()=='냉기 · 스킬 목록')
        assert(not FX.selected and not FX.draft.spellID and next(registrations)==nil)
        Emit('UNIT_SPELLCAST_SUCCEEDED','player','cast',100); assert(next(FX.active)==nil)
        FX:ToggleEditMode(); assert(not e:IsShown()) -- a new specialization starts empty
        assert(FX:SaveRule(nil,{spellID=100,trigger='SUCCESS',preset='unlimitedVoid',x=250,opacity=25})==1)
        assert(FX:SaveRule(nil,{spellID=400,trigger='AURA',sound='DD_Makora'})==2)
        FX:SelectRule(1); FX:ToggleEditMode()
        assert(#picker.items==2 and e.rule.x==250 and e.player.preset==FX.presets.unlimitedVoid)
        e.inputs.x.editBox:SetFocus(); e.inputs.x.editBox:SetText('999')
        combat=true; specIndex=2; Emit('PLAYER_SPECIALIZATION_CHANGED','player')
        assert(FX.db.specID==63 and FX.db.specRules[64][1].x==250 and FX.soundPending) -- restricted edits discarded
        assert(#FX.db.rules==3 and FX.db.rules[1].x==88 and FX.db.rules[2].opacity==60)
        combat=false; Emit('PLAYER_REGEN_ENABLED')
        assert(next(registrations))
        for _,registration in pairs(registrations) do assert(registration.info.spellID==200) end
        assert(not FX.soundPending and not FX.spellRules.SUCCESS[400] and not FX.auraRules[400])
        Emit('UNIT_SPELLCAST_SUCCEEDED','player','cast',100)
        assert(FX.active[FX.db.rules[1]].preset==FX.presets.hollowPurple)
        local current=FX.db.rules
        Emit('PLAYER_SPECIALIZATION_CHANGED','player'); assert(FX.db.rules==current) -- duplicate events keep selection
        specIndex=SECRET; Emit('PLAYER_SPECIALIZATION_CHANGED','player'); assert(FX.db.rules==current)
        specIndex=3; Emit('PLAYER_SPECIALIZATION_CHANGED','player')
        assert(#FX.db.rules==2 and FX.db.rules[1].x==250 and not FX.db.specRules[64])
        assert(FX.db.minimap.minimapPos==42 and FX.presets.hollowPurple and FX.presets.unlimitedVoid)
        assert(FX:DeleteRule(1) and #FX.db.rules==1 and #FX.db.specRules[63]==3)
        -- Reinitialize the saved schema while the current specialization differs from the last saved one.
        w:HideImmediately(); specIndex=2; FX:Initialize()
        assert(FX.db.specID==63 and #FX.db.rules==3 and #FX.db.specRules[64]==1 and not FX.db.specRules[63])
        FX:ToggleUI(); FX:ToggleEditMode(); assert(#picker.items==3 and e.index==1)
        assert(FX.db.rules[1].x==88 and FX.db.rules[2].opacity==60)
        -- Legacy global API fallback and missing specialization info must not erase either list.
        GetSpecialization=C_SpecializationInfo.GetSpecialization
        GetSpecializationInfo=C_SpecializationInfo.GetSpecializationInfo; C_SpecializationInfo=nil
        specIndex=nil; assert(not FX:RefreshSpecialization() and FX.db.specID==63)
        specIndex=3; Emit('PLAYER_SPECIALIZATION_CHANGED','player')
        assert(FX.db.specID==64 and #FX.db.rules==1 and #FX.db.specRules[63]==3)
    ''')
    autocomplete = runtime(r'''
        DDingUI_FXDB={rules={{spellID=400,trigger='AURA'}}}
        local names={[100]='화염구',[101]='화염 작렬',[102]='강화 화염구',[400]='화염 보호막'}
        C_Spell.GetSpellInfo=function(id)
            if id==999 then return {spellID=id,name=SECRET,iconID=SECRET} end
            if id=='화염구' then id=100 end
            if names[id] then return {spellID=id,name=names[id],iconID=id+1000} end
        end
        Enum.SpellBookSpellBank={Player=0}; Enum.SpellBookItemType={Spell=1}
        book={100,101,102,100,999,SECRET}
        C_SpellBook={
            GetNumSpellBookSkillLines=function() return 2 end,
            GetSpellBookSkillLineInfo=function(tab)
                return {itemIndexOffset=0,numSpellBookItems=#book,shouldHide=tab==2}
            end,
            GetSpellBookItemInfo=function(slot,bank)
                assert(bank==0); return {itemType=1,spellID=book[slot]}
            end
        }
    ''')
    autocomplete.execute(r'''
        FX:ToggleUI(); FX:SelectRule(nil)
        local w=FX.window
        local input,popup=w.spell.editBox,w.spell.suggestions
        local function Type(text)
            input:SetFocus(); input:SetText(text); input:Fire('OnTextChanged',true)
        end
        Type('화염')
        assert(popup:IsShown() and #popup.matches==4 and #FX.db.rules==1)
        assert(popup.matches[4].id==102) -- prefix matches before substring matches
        assert(popup.rows[1].icon.texture==popup.matches[1].id+1000)
        assert(popup.rows[1].name:GetText()==popup.matches[1].name)
        input:Fire('OnArrowPressed','DOWN'); assert(popup.selected==2)
        local picked=popup.matches[2].id
        input:Fire('OnEnterPressed')
        assert(#FX.db.rules==2 and FX.db.rules[2].spellID==picked and not popup:IsShown())
        assert(not input:HasFocus())
        Type('화염구'); assert(popup.matches[1].id==100) -- exact match first
        popup.rows[1]:Fire('OnMouseDown','LeftButton')
        assert(FX.db.rules[2].spellID==100 and not popup:IsShown())
        Type('화염')
        picked=popup.matches[3].id
        mouseOver=popup.rows[3]; input:ClearFocus(); mouseOver=nil
        popup.rows[3]:Fire('OnMouseDown','LeftButton') -- focus-before-click ordering
        assert(FX.db.rules[2].spellID==picked and #FX.db.rules==2 and not popup:IsShown())
        Type('화염구'); input:Fire('OnEscapePressed')
        assert(FX.db.rules[2].spellID==picked and not popup:IsShown() and not input:HasFocus())
        Type('없는 주문'); assert(popup:IsShown() and #popup.matches==0)
        input:Fire('OnEnterPressed')
        assert(FX.db.rules[2].spellID==picked and not popup:IsShown())
        Type(''); assert(not popup:IsShown())
        Type('101'); input:Fire('OnTabPressed'); assert(FX.db.rules[2].spellID==101)
        Type('화염'); input:Fire('OnArrowPressed','UP'); assert(popup.selected==4)
        input:Fire('OnArrowPressed','DOWN'); assert(popup.selected==1)
        input:Fire('OnEscapePressed')
        Type('화염구'); combat=true; input:Fire('OnEnterPressed'); combat=false
        assert(FX.db.rules[2].spellID==101 and not popup:IsShown())
        Type('화염'); w:Hide(); Advance(.2); assert(not popup:IsShown())
        w:Show(); Type('화염구'); input:SetText('101'); input:Fire('OnEnterPressed')
        assert(FX.db.rules[2].spellID==101) -- no stale suggestion after programmatic change
        C_Spell.GetSpellInfo=function(id)
            if type(id)=='number' then return {spellID=id,name='추가 주문 '..id,iconID=123} end
        end
        book={201,202,203,204,205,206,207,208,209,210}
        Type('추가') -- refocusing refreshes the spellbook (talents/spec changes)
        assert(#popup.matches==12 and #popup.rows==8 and popup.hint:GetText():find('8',1,true))
        Type('추가 주문 210'); assert(#popup.matches==1 and popup.matches[1].id==210)
        input:Fire('OnEnterPressed'); assert(FX.db.rules[2].spellID==210)
    ''')
    time_sound = runtime(r'''
        DDingUI_FXDB={rules={{spellID=100,trigger='SUCCESS',preset='timeRewind',sound=''}}}
    ''')
    time_sound.execute(r'''
        local path=[[Interface\AddOns\DDingUI_FX\Media\DD_Time_Rewind.mp3]]
        assert(FX.LSM:Fetch('sound','DD_Time Rewind',true)==path)
        assert(FX.db.rules[1].sound=='') -- registering new media preserves saved choices
        FX:ToggleUI(); local w=FX.window
        w.sound:Open(); w.sound:ApplyFilter('DD_Time Rewind')
        assert(#w.sound.filtered==1 and w.sound.filtered[1].value=='DD_Time Rewind')
        w.sound.rows[1].soundButton:Fire('OnClick')
        assert(sounds[#sounds][1]==path and sounds[#sounds][2]=='Master')
        w.sound.rows[1]:Fire('OnClick','LeftButton')
        assert(FX.db.rules[1].sound=='DD_Time Rewind')
        FX:FireRule(FX.db.rules[1])
        assert(sounds[#sounds][1]==path and FX.active[FX.db.rules[1]].playing)
        FX:StopLive()
    ''')
    assert (ROOT / 'Media/DD_Time_Rewind.mp3').is_file()
    empty = runtime('FX.Catalog={}')
    empty.execute('FX:ToggleUI(); assert(#FX.window.cards==1 and FX.window.galleryEmpty:IsShown()); FX:ToggleEditMode(); assert(not FX.editor)')
    reload = runtime(r'''
        DDingUI_FXDB={rules={{spellID=100,trigger='SUCCESS',speed=2,x=30,width=320,height=180},{spellID='bad'}},
          presets={mine={name='Saved',path='Interface\\mine.tga',columns=4,rows=4,frames=16,fps=24},bad={}},nextPreset=2,
          minimap={minimapPos=120,hide=true}}
    ''')
    reload.execute(r'''
        assert(#FX.db.rules==1 and FX.db.rules[1].speed==2 and FX.db.rules[1].x==30)
        assert(FX.db.presets.mine and FX.db.invalidPresets.bad and #FX.db.invalidRules==1)
        FX:ToggleUI(); FX:ToggleEditMode(); assert(FX.editor.inputs.x.editBox:GetText()=='30')
        assert(FX.db.rules[1].scale==100 and FX.db.rules[1].opacity==100)
        local width,height=FX:EffectSize(FX.db.rules[1]); assert(width==320 and height==180)
        Commit(FX.editor.inputs.scale,'200')
        width,height=FX:EffectSize(FX.db.rules[1]); assert(width==640 and height==360)
        local normalized=FX:NormalizeRule(FX.db.rules[1])
        assert(normalized.scale==200 and normalized.width==320 and normalized.height==180)
        FX.editor.done:Fire('OnClick','LeftButton'); Advance(.2)
        FX:ApplyChange('preset','hollowPurple'); FX:TestEffect()
        assert(FX.active[FX.testRule]:GetWidth()==640 and FX.active[FX.testRule]:GetHeight()==360)
        for _,o in ipairs(objects) do if o.events.PLAYER_LOGIN then o:Fire('OnEvent','PLAYER_LOGIN') end end
        assert(FX.db.minimap.minimapPos==120 and not FX.minimapButton:IsShown())
    ''')
    preview = runtime(r'''
        DDingUI_FXDB={rules={{spellID=100,trigger='SUCCESS',preset='hollowPurple',
            sound='DD_Makora',speed=2,opacity=35}}}
    ''')
    preview.execute(r'''
        FX:ToggleUI(); local w=FX.window
        assert(FX.db.rules[1].opacity==35)
        w.test:Fire('OnClick','LeftButton')
        local player=FX.active[FX.testRule]
        assert(FX.testing and not w:IsShown() and player:GetAlpha()==.35)
        playingSounds[FX.previewSoundHandle]=nil -- sound finishes before the animation
        player:Fire('OnUpdate',.99); FX.events:Fire('OnUpdate',0); assert(not w:IsShown())
        player:Fire('OnUpdate',.02); FX.events:Fire('OnUpdate',0)
        assert(w:IsShown() and not FX.testing and not FX.events:GetScript('OnUpdate'))

        missingTexture=true; soundFails=true; FX:TestEffect(); FX.events:Fire('OnUpdate',0)
        assert(w:IsShown() and not FX.testing) -- unavailable media cannot strand the GUI
        missingTexture=false; soundFails=false
        FX:ApplyChange('preset',''); FX:TestEffect(); FX.events:Fire('OnUpdate',0)
        assert(not w:IsShown()) -- sound-only test
        playingSounds[FX.previewSoundHandle]=nil; FX.events:Fire('OnUpdate',0)
        assert(w:IsShown())
        FX:ApplyChange('sound',''); FX:TestEffect(); FX.events:Fire('OnUpdate',0)
        assert(w:IsShown() and not FX.testing) -- neither motion nor sound

        FX:ApplyChange('preset','hollowPurple'); FX:TestEffect()
        FX.active[FX.testRule]:Fire('OnUpdate',1.01); FX.events:Fire('OnUpdate',0)
        assert(w:IsShown()) -- animation-only test
        FX:ApplyChange('sound','DD_Makora'); FX:TestEffect()
        local handle=FX.previewSoundHandle
        FX:ToggleUI()
        assert(w:IsShown() and not FX.testing and not C_Sound.IsPlaying(handle))
        w:HideImmediately(); Advance(3); assert(not w:IsShown()) -- no delayed reopen

        w:Show(); FX:TestEffect(); FX:ToggleEditMode()
        assert(FX.editor:IsShown() and not w:IsShown() and not FX.testing)
        assert(not FX.events:GetScript('OnUpdate') and FX.editor.player:GetAlpha()==.35)
        Advance(3); assert(not w:IsShown())
        FX:CloseEditMode(true); Advance(.2)
        FX:TestEffect(); combat=true; Advance(.1)
        assert(not FX.testing and not w:IsShown())
        combat=false; Advance(3); assert(not w:IsShown())
        w:Show(); FX:TestEffect(); Emit('PLAYER_ENTERING_WORLD')
        assert(not FX.testing and not FX.events:GetScript('OnUpdate'))
        Advance(3); assert(not w:IsShown())
        local rule=FX.db.rules[1]
        rule.opacity=SECRET; assert(FX:NormalizeRule(rule).opacity==100)
        rule.opacity=0/0; assert(FX:NormalizeRule(rule).opacity==100)
        rule.opacity=0; assert(FX:NormalizeRule(rule).opacity==0)
    ''')
    for page in range(3):
        suffix = f'_{page+1}' if page else ''
        with Image.open(ROOT / f'Media/Minazuki{suffix}.tga') as sheet:
            assert sheet.mode == 'RGBA' and sheet.size == (2048, 2048)
            for i in range(16):
                x, y = i % 4 * 512, i // 4 * 512
                alpha = sheet.crop((x, y, x+512, y+512)).getchannel('A')
                box = alpha.getbbox()
                if page * 16 + i < 40:
                    assert box and min(box[:2]) >= 32 and max(box[2:]) <= 480
                else:
                    assert box is None
    reload.execute('''
        local p=FX.presets.minazuki
        assert(p.name=='만해 · 미나즈키' and p.frames==40 and p.fps==11)
        assert(p.columns==4 and p.rows==4 and p.pages==3 and p.displayScale==2)
        local sound=FX.LSM:Fetch('sound','DD_Minazuki',true)
        assert(sound and sound:find('DD_Minazuki.mp3',1,true))
        local player=FX:CreatePlayer(UIParent)
        assert(player:Play(p,1,false) and #player.textures==3)
        player:Fire('OnUpdate',16/11+.001)
        assert(player.page==2 and player.frameIndex==16)
        assert(player.texture.texCoord[1]==0 and player.texture.texCoord[3]==0)
        player:Fire('OnUpdate',16/11)
        assert(player.page==3 and player.frameIndex==32)
        player:Fire('OnUpdate',7/11)
        assert(player.frameIndex==39 and player.playing)
        player:Fire('OnUpdate',1/11)
        assert(not player.playing and not player:GetScript('OnUpdate'))
        assert(player:Play(p,1,true))
        player:Fire('OnUpdate',40/11+.001)
        assert(player.page==1 and player.frameIndex==0 and player.playing)
        player:Stop()
    ''')
    media = ROOT / 'Media/HollowPurple.tga'
    header = media.read_bytes()[:18]
    assert header[2] == 2 and header[16] == 32 and header[17] & 15 == 8
    with Image.open(media) as sheet:
        assert sheet.mode == 'RGBA' and sheet.size == (4096, 4096)
        unique = set()
        for index in range(64):
            x,y = index % 8 * 512, index // 8 * 512
            frame = sheet.crop((x,y,x+512,y+512))
            alpha = frame.getchannel('A')
            if index >= 48:
                assert alpha.getbbox() is None
                continue
            assert alpha.getextrema()[0] == 0 and alpha.getextrema()[1] > 0
            for edge in [(0,0,512,32),(0,480,512,512),(0,0,32,512),(480,0,512,512)]:
                assert alpha.crop(edge).getextrema() == (0,0)
            unique.add(frame.tobytes())
        assert len(unique) == 48
    reload.execute('''
        local p=FX.presets.holyWings
        assert(p.name=='신성한 날개' and p.path:find('HolyWings.tga',1,true))
        local wings=FX:CreatePlayer(UIParent)
        assert(wings:Play(p,1,true) and wings.texture.filter=='NEAREST')
        local first,second=wings.textures[1],wings.textures[2]
        assert(first.blockingLoads and second.blockingLoads and second.filter=='NEAREST')
        assert(second.texture:find('HolyWings_2.tga',1,true) and first:IsShown() and not second:IsShown())
        local firstWrites,secondWrites=first.textureWrites,second.textureWrites
        assert(p.frames == 120 and p.columns == 8 and p.rows == 8 and p.pages == 2 and p.fps == 30 and p.frames / p.fps == 4)
        wings:Fire('OnUpdate',1.5); assert(wings.frameIndex==45)
        wings:Fire('OnUpdate',1.5); assert(wings.frameIndex==90 and wings.playing)
        assert(wings.page==2 and wings.texture.texture:find('HolyWings_2.tga',1,true))
        assert(not first:IsShown() and second:IsShown())
        assert(wings.texture.texCoord[1]==2/8 and wings.texture.texCoord[3]==3/8)
        wings:Fire('OnUpdate',1); assert(wings.frameIndex==0 and wings.playing)
        assert(wings.page==1 and wings.texture.texture==p.path)
        assert(first:IsShown() and not second:IsShown())
        local width,height=FX:EffectSize({width=256,height=256,scale=100,preset='holyWings'})
        assert(width==384 and height==384)
        width,height=FX:EffectSize({width=256,height=256,scale=200,preset='holyWings'})
        assert(width==768 and height==768)
        wings:Fire('OnUpdate',63/30); assert(wings.page==1 and wings.frameIndex==63)
        missingTexture=true; wings:Fire('OnUpdate',1/30)
        assert(wings.playing and wings.frameIndex==64 and wings.texture==second)
        assert(not first:IsShown() and second:IsShown())
        assert(second.texCoord[1]==0 and second.texCoord[3]==0)
        assert(first.textureWrites==firstWrites and second.textureWrites==secondWrites) -- no loading at either page boundary
        missingTexture=false
        missingTexturePath=second.texture
        assert(not wings:Play(p,1,true) and not wings.playing and not wings:IsShown() and not wings:GetScript('OnUpdate'))
        missingTexturePath=nil
        assert(wings:Play(p,1,true) and wings.page==1)
        assert(first:IsShown() and not second:IsShown())
        assert(not FX:ValidatePreset({name='bad',path=p.path,columns=8,rows=8,pages=0,frames=96,fps=24}))
        assert(not FX:ValidatePreset({name='bad',path=p.path,columns=8,rows=8,pages=2,frames=129,fps=24}))
        assert(not FX:ValidatePreset({name='bad',path=p.path,columns=8,rows=8,pages=2,frames=96,fps=24,displayScale=0}))
        wings:Play(p,1,false); wings:Fire('OnUpdate',3.99); assert(wings.playing and wings.frameIndex==119)
        wings:Fire('OnUpdate',.01); assert(not wings.playing)
        p=FX.presets.hollowPurple
        assert(p.columns==8 and p.rows==8 and p.frames==48 and p.fps==24)
        assert(wings:Play(p,1,false) and not second:IsShown() and second.texture==nil)
        local player=FX:CreatePlayer(UIParent)
        assert(player:Play(p,1,false))
        player:Fire('OnUpdate',.99); assert(player.frameIndex==23)
        player:Fire('OnUpdate',1.01); assert(not player.playing and not player:GetScript('OnUpdate'))
        p=FX.presets.timeRewind
        assert(p.name=='시간 역행' and p.path:find('TimeRewind.tga',1,true))
        assert(p.columns==8 and p.rows==8 and p.frames==60 and p.fps==20)
        width,height=FX:EffectSize({width=256,height=256,scale=100,preset='timeRewind'})
        assert(width==384 and height==384)
        assert(player:Play(p,1,true) and player.texture.filter=='NEAREST')
        player:Fire('OnUpdate',1.5); assert(player.frameIndex==30 and player.page==1)
        player:Fire('OnUpdate',1.5); assert(player.frameIndex==0 and player.playing)
        assert(player:Play(p,1,false))
        player:Fire('OnUpdate',2.99); assert(player.frameIndex==59 and player.playing)
        player:Fire('OnUpdate',.02); assert(not player.playing and not player:GetScript('OnUpdate'))
        p=FX.presets.mahoraga
        assert(p.name=='후루베 유라유라 · 마허라' and p.path:find('Mahoraga.tga',1,true))
        assert(p.columns==8 and p.rows==8 and p.pages==2 and p.frames==120 and p.fps==24)
        assert(player:Play(p,1,true) and player.textures[2].texture:find('Mahoraga_2.tga',1,true))
        player:Fire('OnUpdate',2.7); assert(player.frameIndex==64 and player.page==2)
        assert(player.texture.texCoord[1]==0 and player.texture.texCoord[3]==0)
        player:Fire('OnUpdate',2.3); assert(player.frameIndex==0 and player.page==1 and player.playing)
        assert(player:Play(p,1,false))
        player:Fire('OnUpdate',4.99); assert(player.playing and player.frameIndex==119)
        player:Fire('OnUpdate',.02); assert(not player.playing and not player:GetScript('OnUpdate'))
        p=FX.presets.zoltraak
        assert(p.name=='졸트라크' and p.path:find('Zoltraak.tga',1,true))
        assert(p.columns==8 and p.rows==8 and p.pages==2 and p.frames==96 and p.fps==24)
        width,height=FX:EffectSize({width=256,height=256,scale=100,preset='zoltraak'})
        assert(width==512 and height==512)
        assert(player:Play(p,1,true) and player.textures[2].texture:find('Zoltraak_2.tga',1,true))
        firstWrites,secondWrites=player.textures[1].textureWrites,player.textures[2].textureWrites
        player:Fire('OnUpdate',2.7); assert(player.frameIndex==64 and player.page==2)
        assert(player.texture.texCoord[1]==0 and player.texture.texCoord[3]==0)
        player:Fire('OnUpdate',1.3); assert(player.frameIndex==0 and player.page==1 and player.playing)
        assert(player.textures[1].textureWrites==firstWrites and player.textures[2].textureWrites==secondWrites)
        assert(player:Play(p,1,false))
        player:Fire('OnUpdate',3.99); assert(player.playing and player.frameIndex==95)
        player:Fire('OnUpdate',.02); assert(not player.playing and not player:GetScript('OnUpdate'))
    ''')
    reload.execute('''
        local p=FX.presets.unlimitedVoid
        local player=FX:CreatePlayer(UIParent)
        local width,height=FX:EffectSize({width=256,height=256,scale=100,preset='unlimitedVoid'})
        assert(width==512 and height==512 and p.frames/p.fps==3.2)
        assert(player:Play(p,1,true) and #player.textures==4)
        local writes={}
        for page,texture in ipairs(player.textures) do
            local expected=page==1 and p.path or p.path:sub(1,-5)..'_'..page..'.tga'
            assert(texture.texture==expected and texture.blockingLoads)
            writes[page]=texture.textureWrites
        end
        for page=2,4 do
            player:Fire('OnUpdate',.805)
            assert(player.page==page and player.frameIndex==(page-1)*16)
            assert(player.texture.texCoord[1]==0 and player.texture.texCoord[3]==0)
        end
        player:Fire('OnUpdate',.8)
        assert(player.page==1 and player.frameIndex==0 and player.playing)
        for page,texture in ipairs(player.textures) do
            assert(texture.textureWrites==writes[page])
        end
        assert(player:Play(p,1,false))
        player:Fire('OnUpdate',3.19); assert(player.frameIndex==63 and player.playing)
        player:Fire('OnUpdate',.02); assert(not player.playing and not player:GetScript('OnUpdate'))
    ''')
    polish = runtime(r"""
        DDingUI_FXDB={rules={{spellID=100,trigger='SUCCESS'},{spellID=200,trigger='AURA'}}}
    """)
    polish.execute(r"""
        assert(FX.db.guiScale==1)
        FX:ToggleUI(); Advance(.3); local w=FX.window
        -- Title-bar GUI scale: left of close, drag previews, release/wheel saves the one new key.
        local sc=w.titleBar.scaleControl
        assert(sc and sc.points.RIGHT[1]==w.titleBar.editButton and w.search.points.RIGHT[1]==sc)
        assert(w:GetScale()==1)
        sc.slider:Fire('OnMouseWheel',-1)
        assert(math.abs(FX.db.guiScale-.95)<1e-9 and math.abs(w:GetScale()-.95)<1e-9)
        sc.slider:SetValue(1.3); assert(math.abs(FX.db.guiScale-.95)<1e-9)
        sc.slider:Fire('OnMouseUp')
        assert(math.abs(FX.db.guiScale-1.3)<1e-9 and math.abs(w:GetScale()-1.3)<1e-9)
        w:Hide(); Advance(.2); w:Show(); Advance(.3); assert(math.abs(w:GetScale()-1.3)<1e-9)
        -- One sliding selection bar, stagger on selection, 0.09s row hover.
        local bar=w.indicator
        assert(bar:IsShown() and bar.points.TOPLEFT[1]==w.listChild and bar.points.TOPLEFT[4]==0)
        w.rows[2]:Fire('OnClick','LeftButton'); assert(FX.selected==2)
        assert(w.detailRows[1]:GetAlpha()==0 and w.detailRows[5]:GetAlpha()==0)
        Advance(.09)
        local y=bar.points.TOPLEFT[4]; assert(y<0 and y>-56)
        assert(w.detailRows[1]:GetAlpha()>0 and w.detailRows[5]:GetAlpha()==0)
        Advance(.4); assert(bar.points.TOPLEFT[4]==-56)
        for _,row in ipairs(w.detailRows) do assert(row:GetAlpha()==1) end
        assert(w.test:GetParent()==w.detailRows[5] and w.spell:GetParent()==w.detailRows[1])
        w.rows[1]:Fire('OnClick','LeftButton'); Advance(.05); w.rows[1]:Fire('OnClick','LeftButton')
        Advance(.5); assert(bar.points.TOPLEFT[4]==0)
        for _,row in ipairs(w.detailRows) do assert(row:GetAlpha()==1) end
        local C=FX.Style.Colors
        -- 시안 7: rounded rows tinted (not replaced) by RowHover; the selected row stays clear over the pill.
        w.rows[2]:Fire('OnEnter'); Advance(.1)
        for i=1,4 do assert(math.abs(w.rows[2].bg.vertexColor[i]-C.bg.hover[i])<1e-6) end
        w.rows[2]:Fire('OnLeave'); Advance(.1)
        assert(math.abs(w.rows[2].bg.vertexColor[4])<1e-6)
        w.rows[1]:Fire('OnEnter'); Advance(.1)
        assert(w.rows[1].bg.vertexColor[4]==0)
        w.rows[1]:Fire('OnLeave'); Advance(.1)
        -- 시안 7 rounded surfaces: window, cards, pill, rows, preset cards, controls, watermark.
        local Style=FX.Style
        local function Round(o,r) return o._ddslRounded and o._ddslRounded.radius==r end
        local function Tex(t,name) return t and t.texture==Style.MediaPath..name end
        assert(Round(w,14) and not w.titleBar.bg:IsShown())
        for _,card in ipairs({w.sidebar,w.detail}) do
            local p=card.points.TOPLEFT
            assert(Round(card,10) and p[1]==w and p[4]==-44 and 44+card.height==712)
        end
        assert(w.sidebar.points.TOPLEFT[3]==8 and w.sidebar.width==232)
        assert(w.detail.points.TOPLEFT[3]==248 and 248+w.detail.width==992)
        assert(w.status.parent==w.detail and w.detail.parent==w)
        assert(Tex(bar,'ddsl_round8') and bar.width==212 and math.abs(bar.vertexColor[4]-.18)<1e-6)
        assert(bar.layer=='BACKGROUND' and bar.parent==w.listChild)
        assert(Round(w.rows[1],8) and Tex(w.rows[1].bg,'ddsl_round8'))
        assert(Round(w.cards[1],8) and Round(w.hover,10))
        local selectedCard
        for _,card in ipairs(w.cards) do if card.key==FX.draft.preset then selectedCard=card end end
        local accent=Style.GetAccent('FX')
        for i=1,3 do assert(selectedCard._ddslRounded.border[i]==accent[i]) end
        assert(Round(w.add,6) and Round(w.spell.editBox,6) and Round(w.mode.buttons[1],6) and Round(w.search,6))
        local watermark, bullet
        for _,o in ipairs(objects) do
            if o.kind=='Texture' and o.parent==w.detail and Tex(o,'ddsl_rings') then watermark=o end
            if o.kind=='Texture' and Tex(o,'ddsl_rings') and o.parent and o.parent.label
                and o.parent.label.text=='모션 프리셋' then bullet=o end
        end
        assert(watermark and watermark.points.BOTTOMRIGHT and bullet)
        w.search:SetText('200'); assert(not bar:IsShown()); w.search:SetText('')
        assert(bar:IsShown() and bar.points.TOPLEFT[4]==0)
        -- Series slider spec in edit mode and HUD badge.
        FX:ToggleEditMode(); Advance(.8); local e=FX.editor
        local s=e.inputs.scale
        -- Series SliderSpec: 180px track, 28px hit area (6px track + 11px above/below).
        assert(s.slider:GetWidth()==180 and s.slider.points.TOPLEFT[4]==11 and s.slider.points.BOTTOMRIGHT[4]==-11)
        assert(s.valueBox.width==56 and s.valueBox.height==24)
        -- StyleLib slider: solid thumb grows on hover; rounded track stays intact.
        local thumb=s.slider.thumb
        assert(not thumb.texture and thumb.width==16 and thumb.height==16)
        s.slider:Fire('OnEnter'); Advance(.1); assert(thumb.width>16)
        s.slider:Fire('OnLeave'); Advance(.1); assert(thumb.width==16)
        assert(Round(s.valueBox,6) and Round(e.remote,14) and not e.titleBar.bg:IsShown())
        local track=s.slider.points.TOPLEFT[1]
        assert(Round(track,2))
        local fills=0
        for _,o in ipairs(objects) do
            if o.kind=='Texture' and o.parent==track and o.layer=='ARTWORK' then
                assert(Tex(o,'ddsl_round2') and o.points.TOPLEFT[4]==0 and o.points.BOTTOMLEFT[4]==0)
                fills=fills+1
            end
        end
        assert(fills==1)
        -- C5 HUD is exactly "X  Y · W×H"; the size percent moved to the remote selection info.
        local hud=e.hud.box.text
        assert(hud:GetText()=='X 0  Y 0  ·  256×256' and e.hud:IsShown() and e.hud.box.width==178)
        assert(e.remote.nameText:GetText()=='테스트 스킬 100' and e.remote.infoText:GetText():find('크기 100%',1,true))
        Commit(e.inputs.scale,'150'); assert(hud:GetText()=='X 0  Y 0  ·  384×384')
        assert(e.remote.infoText:GetText():find('크기 150%',1,true) and e.remote.infoText:GetText():find('384×384',1,true))
        -- No settings text below the 12pt series minimum.
        local function Under(o,root) while o do if o==root then return true end o=o.parent end end
        for _,o in ipairs(objects) do
            if o.kind=='FontString' and (Under(o,w) or Under(o,e) or Under(o,e.remote)) and o.fontSize then
                assert(o.fontSize>=12,o.text)
            end
        end
        -- Escape takes the "편집 완료" path and reopens the GUI.
        local listed=false
        for _,name in ipairs(UISpecialFrames) do listed=listed or name=='DDingUI_FXEditMode' end
        assert(listed); DDingUI_FXEditMode:Hide()
        assert(e.closing and e:IsShown()); Advance(.2)
        assert(not e:IsShown() and w:IsShown() and FX.db.rules[1].scale==150)
    """)
    series = runtime(r"""
        DDingUI_FXDB={rules={{spellID=100,trigger='SUCCESS'},{spellID=200,trigger='AURA'}}}
    """)
    series.execute(r"""
        -- C12 slash entry: "/dfx edit" toggles edit mode, anything else the settings window.
        SlashCmdList.DDINGUI_FX(' EDIT '); local e=FX.editor
        assert(e and e:IsShown() and not FX.window:IsShown() and FX.window.editMode.label:GetText()=='편집 중')
        SlashCmdList.DDINGUI_FX('edit'); assert(e.closing); Advance(.3)
        assert(not e:IsShown() and FX.window:IsShown() and FX.window.editMode.label:GetText()=='편집 모드')
        SlashCmdList.DDINGUI_FX(''); Advance(.3); assert(not FX.window:IsShown())
        combat=true; SlashCmdList.DDINGUI_FX('edit'); assert(not e:IsShown()); combat=false
        SlashCmdList.DDINGUI_FX('edit'); Advance(.8); assert(e:IsShown() and e.remote:IsShown())
        -- Snap distance 8 from the shared spec; grid snap uses the visible spacing and screen-centre origin.
        assert(FX.Style.EditModeSpec.snapThreshold==8)
        local cx,cy=600,500
        function GetCursorPosition() return cx,cy end
        function IsMouseButtonDown() return true end
        local function Drag(dx,dy)
            e.mover:Fire('OnMouseDown','LeftButton'); cx=cx+dx; cy=cy+dy
            e.mover:Fire('OnUpdate',.1); e.mover:Fire('OnMouseUp','LeftButton')
        end
        Drag(37,7); assert(e.rule.x==32 and e.rule.y==0 and FX.db.rules[1].x==32) -- 5px/7px: inside 8
        FX:SetEditValues({x=0,y=0}); Drag(41,0); assert(e.rule.x==41) -- 9px from 32: outside 8
        e.remote.gridSpacingBtn:Fire('OnClick') -- 32 -> 64
        assert(e.gridSpacing==64 and e.grid:GetSpacing()==64)
        FX:SetEditValues({x=0,y=0}); Drag(58,0); assert(e.rule.x==64)
        Check('격자'); FX:SetEditValues({x=0,y=0}); Drag(58,0); assert(e.rule.x==58) -- grid snap off
        Check('중앙'); FX:SetEditValues({x=0,y=0}); Drag(0,5); assert(e.rule.y==5) -- centre and grid snap off
        Check('격자'); Check('중앙')
        for _,o in ipairs(objects) do assert(not (o.box and o.label and o.label.text=='프레임' and o.parent==e.remote)) end
        -- Undo / redo / reset share one history per effect; slider drags merge into one step.
        FX:SetEditValues({x=10,y=20})
        local undo=#e.undo
        Key('RIGHT'); assert(FX.db.rules[1].x==11 and #e.undo==undo+1)
        ctrlDown=true; Key('Z'); assert(FX.db.rules[1].x==10 and #e.redo==1)
        Key('Y'); assert(FX.db.rules[1].x==11 and #e.redo==0); ctrlDown=false
        undo=#e.undo
        e.inputs.scale.slider:SetValue(120); Advance(.1); e.inputs.scale.slider:SetValue(140)
        assert(FX.db.rules[1].scale==140 and #e.undo==undo+1)
        e.remote.buttons['실행 취소']:Fire('OnClick'); assert(FX.db.rules[1].scale==100)
        e.remote.buttons['다시 실행']:Fire('OnClick'); assert(FX.db.rules[1].scale==140)
        Commit(e.inputs.opacity,'50'); e.remote.buttons['초기화']:Fire('OnClick')
        local r=FX.db.rules[1]
        assert(r.x==0 and r.y==0 and r.scale==100 and r.opacity==100 and r.speed==1)
        e.remote.buttons['실행 취소']:Fire('OnClick'); assert(FX.db.rules[1].opacity==50 and FX.db.rules[1].x==11)
        assert(FX:SelectEditRule(2) and #e.undo==0 and #e.redo==0)
        -- Typed X/Y accept negative offsets.
        Commit(e.inputs.x,'-120'); assert(FX.db.rules[2].x==-120 and e.hud.box.text:GetText():find('^X %-120  Y 0  '))
        -- Remote position: drag stop saves {point,x,y}; reload restores it.
        e.remote:ClearAllPoints(); e.remote:SetPoint('TOPLEFT',UIParent,'TOPLEFT',40.4,-80.6)
        e.titleBar:Fire('OnDragStop')
        local pos=FX.db.editRemotePos
        assert(pos.point=='TOPLEFT' and pos.x==40 and pos.y==-81)
        Key('ESCAPE'); assert(e.closing and FX.window.editMode.label:GetText()=='편집 모드')
        Advance(.3); assert(not e:IsShown() and FX.window:IsShown() and not e.remote:IsShown() and not e.grid:IsShown())
        -- Title-bar button enters; the remote's own X ends edit mode through onDone (same fade + reopen).
        FX.window.editMode:Fire('OnClick','LeftButton'); Advance(.8)
        assert(e:IsShown() and FX.window.editMode.label:GetText()=='편집 중')
        e.titleBar.closeBtn:Fire('OnClick'); assert(e.closing); Advance(.3)
        assert(not e:IsShown() and FX.window:IsShown())
    """)
    moved = runtime("DDingUI_FXDB={rules={{spellID=100,trigger='SUCCESS'}},editRemotePos={point='TOPLEFT',x=40,y=-81}}")
    moved.execute("""
        FX:ToggleEditMode(); local p,_,_,x,y=FX.editor.remote:GetPoint(1)
        assert(p=='TOPLEFT' and x==40 and y==-81)
    """)
    broken = runtime("DDingUI_FXDB={rules={{spellID=100,trigger='SUCCESS'}},editRemotePos={point='NOWHERE',x='a'}}")
    broken.execute("""
        FX:ToggleEditMode(); local p,_,_,x,y=FX.editor.remote:GetPoint(1)
        assert(p=='TOP' and x==0 and y==-55)
    """)
    stored = runtime("DDingUI_FXDB={guiScale=1.2}")
    stored.execute("FX:ToggleUI(); Advance(.3); assert(math.abs(FX.window:GetScale()-1.2)<1e-9)")
    clamped = runtime("DDingUI_FXDB={guiScale=9}")
    clamped.execute("assert(FX.db.guiScale==1.5)")
    print("PASS: specialization migration/switch/reload, edit preview picker, percent sizing/legacy aspect ratio, edit grid/snap/fades/cleanup, spell autocomplete, RGBA TGA, TOC/Lua 5.1, branding/minimap, autosave/hover/list, playback/events/aura secrets/sounds/combat guards, GUI scale/indicator/stagger/row hover/slider spec/12pt/Escape fade, series edit remote/HUD format/snap 8/undo, /dfx edit, remote position")
    return lua


if __name__ == "__main__":
    check()

"""기존 UI 모의를 재사용하며 테스트에서 다른 애드온을 로드하지 않는다."""
from pathlib import Path
import re
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
EXTRA = "\nFX={}; auras={}; registrations={}; added=0; removed=0; restrictions=false\nplayingSounds={}\nC_Sound={IsPlaying=function(handle) return playingSounds[handle] or false end}\nlocal playSoundFile=PlaySoundFile\nfunction PlaySoundFile(path,channel)\n    if soundFails then return false end\n    local played,handle=playSoundFile(path,channel)\n    if played then playingSounds[handle]=true end\n    return played,handle\nend\nfunction StopSound(handle) playingSounds[handle]=nil end\nWOW_PROJECT_ID=1; WOW_PROJECT_MAINLINE=1\nMinimap=CreateFrame('Frame','Minimap',UIParent)\nMinimap:SetSize(140,140); Minimap:SetPoint('TOPRIGHT',UIParent,'TOPRIGHT',-20,-20)\nfunction IsShiftKeyDown() return shiftDown or false end\nfunction methods:GetSize() return self:GetWidth(),self:GetHeight() end\nfunction methods:GetVertexColor() return unpack(self.vertexColor or {1,1,1,1}) end\nfunction methods:SetVertexColor(...) self.vertexColor={...} end\nfunction methods:SetDesaturated(v) self.desaturated=v end\nfunction methods:CreateAnimationGroup() return CreateFrame('AnimationGroup',nil,self) end\nfunction methods:CreateAnimation() return CreateFrame('Animation',nil,self) end\nfunction methods:Play() self.playing=true end\nfunction methods:Stop() self.playing=false end\nfor _,key in ipairs({'SetFixedFrameStrata','SetFixedFrameLevel','SetHighlightTexture','SetOrder','SetDuration','SetFromAlpha','SetToAlpha','SetStartDelay','SetToFinalAlpha','LockHighlight','UnlockHighlight'}) do methods[key]=function() end end\nlocal originalXpcall=xpcall\nfunction xpcall(callback,handler,...)\n    local args,n={...},select('#',...)\n    return originalXpcall(function() return callback(unpack(args,1,n)) end,handler)\nend\nfunction wipe(t) for k in pairs(t) do t[k]=nil end return t end\nfunction geterrorhandler() return error end\nfunction IsMouseButtonDown() return false end\nfunction methods:GetFont() return self.fontPath,self.fontSize,self.fontFlags end\nfunction methods:GetBottom() local _,y=self:Rect(); return y end\nfunction methods:GetTop() local _,y,_,h=self:Rect(); return y+h end\nfunction methods:GetStringWidth() return Measure(self.text or '',self.fontSize or 12) end\nfunction methods:GetVerticalScrollRange() return math.max(0,(self.scrollChild and self.scrollChild:GetHeight() or 0)-self:GetHeight()) end\nfunction methods:SetScale(v) self.scale=v end\nfunction methods:GetScale() return self.scale or 1 end\nfunction methods:GetEffectiveScale() return (self.scale or 1)*(self.parent and self.parent:GetEffectiveScale() or 1) end\nfunction methods:SetValue(v) self.value=v; self:Fire('OnValueChanged',v) end\nfunction methods:GetValue() return self.value end\nfunction methods:RegisterUnitEvent(event,unit) self.events[event]=unit end\nfunction methods:SetTexCoord(...) self.texCoord={...} end\nfunction methods:SetBlockingLoadsRequested(value) self.blockingLoads=value end\nfunction methods:SetTexture(path,wrapX,wrapY,filter)\n    self.texture=path; self.filter=filter; self.textureWrites=(self.textureWrites or 0)+1\n    return not missingTexture and (not missingTexturePath or path~=missingTexturePath)\nend\nfunction methods:SetMinMaxValues(a,b) self.min,self.max=a,b end\nfunction methods:SetThumbTexture(t) self.thumb=t end\nfor _,key in ipairs({'SetTextInsets','SetNumeric','SetMaxLetters','EnableKeyboard','HighlightText','SetValueStep','SetObeyStepOnDrag','SetOrientation','SetHitRectInsets','SetClipsChildren','SetToplevel','SetNormalAtlas','SetPushedAtlas','SetBlendMode'}) do methods[key]=function() end end\nfunction methods:SetFocus() self.focus=true; self:Fire('OnEditFocusGained') end\nfunction methods:HasFocus() return self.focus end\nfunction methods:SetAltArrowKeyMode(value) self.altArrowKeyMode=value end\n-- StyleLib 1.4 edit remote: anchor readback, formatted HUD text, keyboard capture.\nfunction methods:GetPoint() local p,a=next(self.points); if p then return p,a[1],a[2],a[3],a[4] end end\nfunction methods:SetFormattedText(fmt,...) self.text=string.format(fmt,...) end\nfor _,key in ipairs({'SetPropagateKeyboardInput','SetClampRectInsets'}) do methods[key]=function() end end\nfunction GetCurrentKeyBoardFocus() return nil end\nfunction IsControlKeyDown() return ctrlDown or false end\nfunction Key(key) local r=FX.editor.remote; r:GetScript('OnKeyDown')(r,key) end\nfunction Check(label)\n    for _,o in ipairs(objects) do\n        if o.box and o.label and o.label.text==label and o.parent==FX.editor.remote then o.box:Fire('OnClick'); return o end\n    end\n    error('Checkbox not found: '..label)\nend\nfunction methods:ClearFocus()\n    if self.focus then self.focus=false; self:Fire('OnEditFocusLost') end\nend\nfunction Commit(row,text)\n    row.editBox:SetFocus(); row.editBox:SetText(text); row.editBox:Fire('OnEnterPressed')\nend\nfunction Advance(seconds)\n    now=now+seconds\n    for _,frame in ipairs(objects) do\n        if frame:IsVisible() then frame:Fire('OnUpdate',seconds) end\n    end\nend\nC_Timer.After=function(_,callback) callback() end\nC_Spell={GetSpellInfo=function(input)\n    local id=tonumber(input) or (input=='테스트 스킬' and 100)\n    if id then return {spellID=id,name='테스트 스킬 '..id,iconID=123} end\nend, RequestLoadSpellData=function() end}\nC_Secrets={ShouldAurasBeSecret=function() return restrictions end,\n    ShouldSpellAuraBeSecret=function() return auraRestricted or false end}\nEnum={UnitAuraSoundTrigger={Added=0}}\nC_UnitAuras={GetPlayerAuraBySpellID=function(id)\n    if auraError then error('restricted') end\n    return auras[id]\nend, AddAuraSound=function(trigger,info)\n    assert(not combat and not restrictions)\n    if addError then error('registration unavailable') end\n    added=added+1; registrations[added]={trigger=trigger,info=info}; return added\nend, RemoveAuraSound=function(id)\n    assert(not combat and not restrictions)\n    if removeError then error('removal unavailable') end\n    registrations[id]=nil; removed=removed+1\nend}\nfunction Emit(event,...) FX.events:Fire('OnEvent',event,...) end\nfunction ClickText(text,parent)\n    for _,o in ipairs(objects) do\n        if o.label and o.label.text==text and (not parent or o.parent==parent) then\n            o:Fire('OnClick','LeftButton'); return o\n        end\n    end\n    error('Button not found: '..text)\nend\n"


def runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().Measure = lambda text, size: len(text) * size * .65
    lua.execute((ROOT / "tests/wow_mock.lua").read_text(encoding="utf-8-sig"))
    lua.execute(EXTRA)
    lua.execute((ROOT / "Libs/LibStub/LibStub.lua").read_text(encoding="utf-8-sig"))
    return lua


FILES = ("Core.lua", "Colors.lua", "Gradient.lua", "Motion.lua", "Widgets.lua", "EditMode.lua")


def load_bundle(bundle):
    lua = runtime()
    lua.globals().Measure = lambda text, size: len(re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", text)) * size * .65
    # 모의 런타임에 없는 API 보강 (키보드·포커스·포맷 텍스트·GetPoint)
    lua.execute('''
        local M = getmetatable(UIParent).__index
        function M:GetPoint(i)
            local p, a = next(self.points)
            if not p then return nil end
            return p, a[1], a[2], a[3], a[4]
        end
        function M:SetFormattedText(fmt, ...) self.text = string.format(fmt, ...) end
        function M:HasFocus() return false end
        for _, k in ipairs({ "EnableKeyboard", "SetPropagateKeyboardInput", "SetClampRectInsets", "SetFrameLevel", "StartMoving", "StopMovingOrSizing" }) do
            if not M[k] then M[k] = function() end end
        end
        GetCurrentKeyBoardFocus = function() return nil end
        IsShiftKeyDown = function() return false end
        IsControlKeyDown = function() return false end
    ''')
    owner = bundle.relative_to(ROOT.parent).parts[0]
    core = (bundle / "Core.lua").read_text(encoding="utf-8-sig")
    major = re.search(r'local MAJOR(?:, MINOR)? = "([^"]+)"', core)[1]
    for name in FILES:
        lua.execute('local source,owner=...; assert(loadstring(source))(owner)',
                    (bundle / name).read_text(encoding="utf-8-sig"), owner)
    return lua, lua.globals().LibStub.GetLibrary(lua.globals().LibStub, major)[0]

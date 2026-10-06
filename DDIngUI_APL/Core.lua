-- [12.1] Isolated alpha addon and per-character settings. No other addon's DB is touched.
local addonName, A = ...
_G.DDIngUI_APL = A
A.name, A.version = addonName, "2.2.0"
A.DEFAULT_X, A.DEFAULT_Y = 0, -150 -- [STYLE] display default (CENTER offset, display-scale units); C12 edit-mode reset
A.T = function(ko,en) return GetLocale() == "koKR" and ko or en end
function A:Print(message) print("DDIngUI APL: "..message) end
function A:Profile()
    local key=self.spec or 0
    if type(self.db.profiles[key]) ~= "table" then self.db.profiles[key]={} end
    return self.db.profiles[key]
end
function A:RefreshProfile()
    if self.display then self.display.lastNative=nil end
    if InCombatLockdown() then self.pending=true; self.pack=nil; self.keys={}; return end
    local oldSpec=self.spec
    self.spec=self.API.Spec()
    if oldSpec ~= self.spec and self.options then self.options:Hide() end
    self.source=self.Packs.specs[self.spec]
    local profile=self:Profile()
    local raw=type(profile.raw) == "string" and profile.raw or self.source and self.source.raw or ""
    self.pack=self.Engine.Compile(raw)
    local aliasError
    self.aliases,aliasError=self.API.Aliases(profile.aliases)
    if not self.aliases then
        self.aliases={}
        self.pack.valid=false
        table.insert(self.pack.issues,1,{line=0,message=aliasError})
    end
    self.bindings=self.API.Bind(self.pack,self.aliases)
    self.keys=self.API.Keys()
    self.keysPending=nil
    self.pending=false
    if self.ApplyAuraCue then self:ApplyAuraCue() end
    self:Tick()
end
function A:Import(raw, aliases)
    if InCombatLockdown() then return false,self.T("전투가 끝나면 적용할 수 있어요.","Apply after combat.") end
    local compiled=self.Engine.Compile(raw)
    if not compiled.valid then return false,self:CompileReport(compiled) end
    local map,err=self.API.Aliases(aliases)
    if not map then return false,err end
    local profile=self:Profile()
    profile.previous={raw=profile.raw,aliases=profile.aliases}
    profile.raw,profile.aliases=raw,aliases or ""
    self.db.mode="strict"
    self:RefreshProfile()
    return true,self.T("개인 APL 적용 · APL 전용 모드로 전환했습니다.\n","Personal APL applied · switched to APL-only mode.\n")..self:CompileReport(compiled)
end
function A:CompileReport(pack)
    local lines={}
    for i,issue in ipairs(pack.issues) do
        if i > 12 then lines[#lines+1]="…"; break end
        lines[#lines+1]=issue.line..": "..issue.message
    end
    if #lines == 0 then
        lines[1]=self.T("구문 통과 · 실전 실행 가능 여부는 별도입니다.","Syntax valid · live execution is checked separately.")
        for i,warning in ipairs(pack.warnings or {}) do
            if i > 8 then lines[#lines+1]="…"; break end
            lines[#lines+1]=warning.list..":"..warning.line.." · "..warning.message
        end
    end
    return table.concat(lines,"\n")
end
function A:ResetProfile(undo)
    if InCombatLockdown() then return end
    local profile=self:Profile()
    if undo then
        if type(profile.previous) ~= "table" then return end
        local previous=profile.previous
        profile.raw,profile.aliases=previous.raw,previous.aliases
        profile.previous=nil
    else
        profile.previous={raw=profile.raw,aliases=profile.aliases}
        profile.raw,profile.aliases=nil,nil
    end
    self:RefreshProfile()
end
function A:Evaluate()
    self.aplResult,self.snapshot=nil,nil
    if self.preview then
        local demo=self.Engine.Demo(self.demoPower or 2)
        local ids={generator=35395,spender=85256}
        for _,step in ipairs(demo) do step.spellID=ids[step.action]; step.source="PREVIEW" end
        return {kind="preview",source="PREVIEW",reason=self.T("가상 자원 모델 · 실전 추천 아님","Synthetic resource model"),queue=demo}
    end
    local result
    if self.db.mode ~= "native" and self.pack then
        if self.pack.valid then
            self.snapshot=self.API.Snapshot(self.pack,self.bindings,self.db)
            result=self.Engine.Select(self.pack,self.snapshot)
        else result=self.Engine.Select(self.pack,{}) end
        result.source="APL"
        self.aplResult=result
        if result.kind == "action" then
            result.spellID=self.bindings[result.action]
            result.queue={ {spellID=result.spellID,action=result.action,source="APL"} }
            result.reason=(result.list or "default")..":"..result.line.." · "..result.action
            return result
        end
    end
    result=result or {kind="unknown",source="APL",reason=self.pending and "configuration pending after combat" or "no specialization APL"}
    if self.db.mode ~= "strict" then
        local id,reason,status=self.API.Native()
        if id then
            return {kind="action",source="BLIZZARD",nativeStatus=status,spellID=id,queue={{spellID=id,source="BLIZZARD"}},
                reason=self.db.mode == "native" and self.T("블리자드 기본 추천","Blizzard Assisted Combat")
                    or self.T("APL 대기: ","APL unresolved: ")..(result.line and (result.list or "default")..":"..result.line.." · " or "")..result.reason}
        end
        result.nativeReason=reason
        result.nativeStatus=status
    end
    return result
end
function A:Tick()
    if not self.db then return end
    local ok,result=pcall(self.Evaluate,self)
    if not ok then
        result={kind="error",source="APL",reason="evaluation error"}
        self.runtimeError=true
    end
    self.last=result
    if self.Render then self:Render(result) end
end
function A:Diagnostics()
    local lines={self.name.." "..self.version, "source build: "..self.Packs.build,
        "SimC commit: "..self.Packs.commit, "specID: "..(self.spec or 0),
        "mode: "..self.db.mode, "manual targets: "..self.db.targets,
        "source: "..(self:Profile().raw and "personal" or (self.source and self.source.source ~= "" and self.source.source or "no upstream APL")),
        "last: "..(self.last and self.last.source or "?").." / "..(self.last and self.last.kind or "?"),
        "reason: "..(self.last and self.last.reason or ""),
        "native: "..(self.last and self.last.nativeReason or ""), "",
        self.T("40개 전문화 연결 / 34개 공개 APL / 실전 검증 전","40 specs / 34 upstream APLs / not validated in game")}
    if self.pack then lines[#lines+1]=self:CompileReport(self.pack) end
    local apl=self.aplResult
    if apl then
        lines[#lines+1]="\nAPL: "..apl.kind.." / "..(apl.list or "?")..":"..(apl.line or 0).." / "..(apl.action or "?")
        lines[#lines+1]="APL reason: "..(apl.reason or "")
    end
    if self.pack and self.snapshot then
        local missing,unbound={},{}
        for ref in pairs(self.pack.refs) do
            if not ref:match("^variable%.") and ref ~= "true" and ref ~= "false" and self.snapshot.values[ref] == nil then missing[#missing+1]=ref end
        end
        for token in pairs(self.pack.actions) do
            if self.bindings[token] == nil then unbound[#unbound+1]=token end
        end
        table.sort(missing); table.sort(unbound)
        lines[#lines+1]="unresolved spell tokens: "..#unbound.." · "..table.concat(unbound,", ",1,math.min(20,#unbound))
        lines[#lines+1]="unavailable inputs (includes unused lists): "..#missing.." · "..table.concat(missing,", ",1,math.min(30,#missing))
    end
    lines[#lines+1]="native sample: "..(self.last and self.last.nativeStatus or "not requested")
    local hasButton=self.API.Query(C_ActionBar and C_ActionBar.HasAssistedCombatActionButtons)
    local highlight=self.API.Query(GetCVarBool,"assistedCombatHighlight")
    lines[#lines+1]="assistant placed: "..tostring(hasButton).." / highlight: "..tostring(highlight)
    if self.auraStatus then lines[#lines+1]="AuraContainer: "..self.auraStatus end
    return table.concat(lines,"\n")
end
function A:SetOption(key,value)
    if InCombatLockdown() then self:Print(self.T("전투가 끝나면 설정해 주세요.","Change settings after combat.")); return end
    self.db[key]=value
    if self.display then self.display.lastNative=nil end
    if self.ApplyLayout then self:ApplyLayout() end
    self:Tick()
end
local frame=CreateFrame("Frame")
A.events=frame
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent",function(_,event,arg)
    if event == "ADDON_LOADED" then
        if arg ~= addonName then return end
        DDIngUI_APLDB=type(DDIngUI_APLDB) == "table" and DDIngUI_APLDB or {}
        A.db=DDIngUI_APLDB
        local db=A.db
        db.profiles=type(db.profiles) == "table" and db.profiles or {}
        if db.mode ~= "auto" and db.mode ~= "strict" and db.mode ~= "native" then db.mode="strict" end
        if type(db.targets) ~= "number" or db.targets < 1 or db.targets > 20 then db.targets=1 end
        if type(db.scale) ~= "number" or db.scale < 0.6 or db.scale > 2 then db.scale=1 end
        if type(db.enabled) ~= "boolean" then db.enabled=true end
        if type(db.locked) ~= "boolean" then db.locked=true end
        if type(db.x) ~= "number" then db.x=A.DEFAULT_X end
        if type(db.y) ~= "number" then db.y=A.DEFAULT_Y end
        if db.editRemotePos ~= nil and type(db.editRemotePos) ~= "table" then db.editRemotePos=nil end -- [STYLE] C12 remote position (optional key)
        if type(db.minimap) ~= "table" then db.minimap={hide=false} end -- [STYLE] LibDBIcon saved position only
        if type(db.guiScale) ~= "number" or db.guiScale < 0.5 or db.guiScale > 1.5 then db.guiScale=1 end -- [STYLE] title-bar GUI scale
        A:CreateDisplay()
        A:CreateMinimapButton() -- [STYLE] series minimap button
        for _,name in ipairs({"PLAYER_ENTERING_WORLD","PLAYER_SPECIALIZATION_CHANGED","SPELLS_CHANGED",
            "TRAIT_CONFIG_UPDATED","UPDATE_BINDINGS","ACTIONBAR_SLOT_CHANGED","PLAYER_REGEN_ENABLED",
            "PLAYER_REGEN_DISABLED","PLAYER_TARGET_CHANGED","PLAYER_DEAD","ACTIONBAR_PAGE_CHANGED"}) do frame:RegisterEvent(name) end
        frame:UnregisterEvent("ADDON_LOADED")
        SLASH_DDINGUI_APL1="/ddapl"
        SlashCmdList.DDINGUI_APL=function(text)
            local command,value=text:match("^(%S*)%s*(.-)$")
            if command == "preview" then
                if not InCombatLockdown() then A.preview=not A.preview; A:ApplyLayout(); A:Tick() end
            elseif command == "status" then A:Print(A:Diagnostics())
            elseif command == "mode" and (value == "strict" or value == "auto" or value == "native") then A:SetOption("mode",value)
            elseif command == "targets" and tonumber(value) then
                A:SetOption("targets",math.min(20,math.max(1,math.floor(tonumber(value)))))
            elseif command == "lock" then A:ToggleDisplayLock() -- [STYLE] lock toggle stays here and on the options button
            elseif command == "edit" then A:ToggleEditMode() -- [STYLE] C12 series edit mode
            else A:OpenOptions() end
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        A.preview=false
        if A.editing then A:StopEditMode(true) end -- [STYLE] C12: combat ends edit mode without motion or reopen
        if A.options then -- [STYLE] C4: combat start skips the close motion
            if A.options.HideImmediately then A.options:HideImmediately() else A.options:Hide() end
        end
        if A.display then A.display:StopMovingOrSizing() end
        A:Tick()
    elseif event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_DEAD" then
        if A.display then A.display.lastNative=nil end
        A:Tick()
    elseif event == "UPDATE_BINDINGS" or event == "ACTIONBAR_SLOT_CHANGED" or event == "ACTIONBAR_PAGE_CHANGED" then
        -- [FIX] Native assist buttons can emit slot changes at rotation cadence.
        -- These events invalidate key labels, not the active APL or its spell bindings.
        if InCombatLockdown() then A.keysPending=true; A.keys={}
        else A.keys=A.API.Keys() end
    elseif event == "SPELLS_CHANGED" and InCombatLockdown() then
        -- The spell set can update during a rotation. Refresh public ID bindings without
        -- tearing down the immutable APL or touching configuration/protected frames.
        A.pending=true
        if A.pack and A.pack.valid then A.bindings=A.API.Bind(A.pack,A.aliases) end
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" and (not A.API.Public(arg) or (arg ~= nil and arg ~= "player")) then
        return
    elseif event == "PLAYER_REGEN_ENABLED" and not A.pending then
        if A.keysPending then A.keys=A.API.Keys(); A.keysPending=nil end
        A:Tick()
    else A:RefreshProfile() end
end)
local elapsed=0
frame:SetScript("OnUpdate",function(_,delta)
    elapsed=elapsed+delta
    if elapsed < 0.1 then return end
    elapsed=0
    if A.db and A.db.enabled then
        -- ponytail: capped 10 Hz, only while a target/combat/preview can affect the recommendation.
        if A.preview or InCombatLockdown() or A.API.Query(UnitExists,"target") == true then A:Tick() end
    end
end)

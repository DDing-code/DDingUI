local _, FX = ...
local W, SL = FX.Controls, FX.Style
local C = SL.Colors
local Motion = SL.Motion
-- [STYLE] Series edit mode (C12): StyleLib 1.4 remote, mover surface, HUD, grid, guides and snap math.
local SPEC = SL.EditModeSpec
local SNAP = SPEC.snapThreshold
local PAD = 14
local EDIT_KEYS = {"x","y","scale","opacity","speed"}
local POINTS = {TOPLEFT=true,TOP=true,TOPRIGHT=true,LEFT=true,CENTER=true,RIGHT=true,BOTTOMLEFT=true,BOTTOM=true,BOTTOMRIGHT=true}

local function Snapshot(rule)
    local copy = {}
    for _,key in ipairs(EDIT_KEYS) do copy[key] = rule[key] end
    return copy
end

local function Same(a,b)
    for _,key in ipairs(EDIT_KEYS) do if a[key] ~= b[key] then return false end end
    return true
end

local function FormatValue(key,value)
    if key == "speed" then return tostring(tonumber(string.format("%.2f",value))) end
    return tostring(math.floor(value+.5))
end

function FX:RefreshEditRulePicker()
    local e = self.editor
    if not e then return end
    local options = {}
    local triggers = {START="시전 시작",SUCCESS="사용 성공",AURA="버프 활성화"}
    for index, rule in ipairs(self.db.rules) do
        local preset = self.presets[rule.preset]
        options[#options+1] = {value=index, text=self:SpellName(rule.spellID) .. " · " .. rule.spellID .. " · " .. triggers[rule.trigger]
            .. " · " .. (preset and preset.name or "모션 없음")}
    end
    e.rulePicker:SetOptions(options,e.index)
end

function FX:SelectEditRule(index)
    local e = self.editor
    if not e or not e:IsShown() then return false end
    if e.closing or not self:CanEdit() then e.rulePicker:SetValue(e.index,true); return false end
    self:FinishEditDrag(); self:FlushEditInputs()
    if e.rule and self.db.rules[e.index] ~= e.source then
        self:Message("편집 중인 스킬이 변경되었습니다. 다시 선택하세요.")
        e.rulePicker:SetValue(e.index,true)
        return false
    end
    local source = type(index) == "number" and self.db.rules[index]
    if not source then e.rulePicker:SetValue(e.index,true); return false end
    e.index, e.source, e.rule = index, source, self:NormalizeRule(source)
    -- Undo history belongs to one effect; switching effects starts a new one.
    e.undo, e.redo = {}, {}
    self:SelectRule(index)
    local name, icon = self:SpellName(source.spellID)
    e.name = name
    e.moverStyle:SetLabel(name)
    e.icon:SetTexture(not self.IsSecret(icon) and icon or 134400)
    local preset = self.presets[source.preset]
    e.presetName:SetText((self.specName and self.specName .. " · " or "")
        .. (preset and (preset.name .. " · 무음 미리보기") or "모션 없음 · 선택 영역으로 위치와 크기 조절"))
    self:RefreshEditRulePicker(); self:RefreshEditMode()
    e.player:Play(preset,source.speed,true)
    return true
end

function FX:RefreshEditGrid(animate)
    local e = self.editor
    local grid = e.grid
    if e.gridEnabled then
        grid:SetSpacing(e.gridSpacing)
        if animate or not grid:IsShown() then
            -- [STYLE] Series grid: centred accent lines + 0.18 dim, 0.75s fade from transparent.
            Motion.StopAll(grid); grid:SetAlpha(0); grid:ShowAnimated()
        end
    elseif grid:IsShown() then
        grid:HideAnimated()
    end
end

function FX:RefreshEditHistory()
    local e = self.editor
    if e and e.undo then e.remote:SetUndoState(#e.undo > 0,#e.redo > 0) end
end

function FX:RefreshEditMode()
    local e = self.editor
    if not e or not e.rule then return end
    local r = e.rule
    local width, height = self:EffectSize(r)
    e.mover:ClearAllPoints()
    e.mover:SetPoint("CENTER",UIParent,"CENTER",r.x,r.y)
    e.mover:SetSize(width,height)
    e.player:SetAlpha(r.opacity / 100)
    e.player.speed = r.speed
    -- [STYLE] C5 HUD "X %d  Y %d · W×H" (centre offset); FX's size percent lives in the remote info line.
    e.hud:Update(r.x,r.y,width,height); e.hud:Show()
    if e.drag then
        e.guides:ShowAt(UIParent:GetWidth()/2+r.x,UIParent:GetHeight()/2+r.y)
    else
        e.guides:Hide()
    end
    e.remote:SetSelection({name=e.name,anchor=string.format("화면 중앙 기준  ·  크기 %d%%",math.floor(r.scale+.5)),
        x=r.x,y=r.y,w=width,h=height})
    for _,key in ipairs({"scale","opacity","speed"}) do e.inputs[key]:SetValue(r[key]) end
    self:RefreshEditHistory()
end

-- merge: consecutive slider drags of one setting become a single undo step.
function FX:CommitEditMode(merge, noHistory)
    local e = self.editor
    if not e or not e.rule then return end
    if not self:CanEdit() then return false end
    if self.db.rules[e.index] ~= e.source then
        self:Message("편집 중인 스킬이 변경되었습니다. 다시 선택하세요.")
        return false
    end
    local before = Snapshot(e.source)
    local index, err = self:SaveRule(e.index,e.rule)
    if not index then
        e.rule = self:NormalizeRule(e.source)
        self:RefreshEditMode(); self:Message(err)
        return false
    end
    e.source = self.db.rules[index]
    if not noHistory and not Same(before,e.source) then
        local now = GetTime()
        if not (merge and e.mergeKey == merge and now - (e.mergeTime or 0) < .6) then
            e.undo[#e.undo+1] = before
            if #e.undo > 50 then table.remove(e.undo,1) end
        end
        e.mergeKey, e.mergeTime, e.redo = merge, now, {}
    end
    self.selected, self.draft = index, self:NormalizeRule(e.source)
    self:RefreshControls(); self:RefreshList()
    return true
end

function FX:FinishEditDrag()
    local e = self.editor
    if not e or not e.drag then return end
    e.drag = nil
    e.mover:SetScript("OnUpdate",nil)
    self:CommitEditMode()
    self:RefreshEditMode()
end

local function Editable(self)
    local e = self.editor
    return e and e.rule and not e.closing and self:CanEdit() and e
end

function FX:ChangeEditSetting(key,value,merge)
    local e = Editable(self)
    if not e then return end
    self:FlushEditInputs(e.inputs[key] and e.inputs[key].editBox)
    if (key == "scale" or key == "opacity") and type(value) == "string" then
        value = value:gsub("%s*%%%s*$", "")
    end
    local low, high = 10, 400
    if key == "x" or key == "y" then low, high = -4096, 4096
    elseif key == "opacity" then low, high = 0, 100
    elseif key == "speed" then low, high = .25, 4 end
    local n = self.Number(value,low,high)
    if not n then self:RefreshEditMode(); self:Message("숫자로 입력하세요."); return end
    e.rule[key] = key == "speed" and .25 + math.floor((n-.25)/.05+.5)*.05 or math.floor(n+.5)
    self:CommitEditMode(merge); self:RefreshEditMode()
end

--- One commit (one undo step) for a position or full-value change.
function FX:SetEditValues(values)
    local e = Editable(self)
    if not e then return end
    self:FinishEditDrag(); self:FlushEditInputs()
    local changed = false
    for key, value in pairs(values) do
        if key == "x" or key == "y" then value = math.floor(self.Number(value,-4096,4096,e.rule[key])+.5) end
        changed = changed or e.rule[key] ~= value
        e.rule[key] = value
    end
    if changed then self:CommitEditMode() end
    self:RefreshEditMode()
end

function FX:NudgeEdit(dx,dy)
    local e = Editable(self)
    if not e then return end
    self:SetEditValues({x=e.rule.x+dx,y=e.rule.y+dy})
end

function FX:StepEditHistory(from,to)
    local e = Editable(self)
    if not e then return end
    self:FinishEditDrag(); self:FlushEditInputs()
    local snapshot = table.remove(e[from])
    if not snapshot then self:RefreshEditHistory(); return end
    e[to][#e[to]+1] = Snapshot(e.source)
    for key, value in pairs(snapshot) do e.rule[key] = value end
    self:CommitEditMode(nil,true)
    e.mergeKey = nil
    self:RefreshEditMode()
end

function FX:CloseEditMode(reopen)
    local e = self.editor
    if not e or not e:IsShown() then return end
    -- Restricted entry hides immediately; ordinary completion gets Toolkit's 0.18s fade.
    if not self:CanEdit() then e:HideImmediately(); return end
    if e.closing then return end
    self:FinishEditDrag(); self:FlushEditInputs()
    e.closing = true
    e.remote:Hide()
    if e.grid:IsShown() then e.grid:HideAnimated() end
    if FX.window then FX.window.editMode:Refresh() end
    Motion.FadeOut(e,.18,{key="editor",onFinish=function()
        e:HideImmediately()
        if reopen then FX.window:Show() end
    end})
end

function FX:FlushEditInputs(except)
    local e = self.editor
    if not e or not e.rule or e.flushing then return end
    e.flushing = true
    for _,input in pairs(e.inputs) do
        if input.editBox ~= except and input.editBox:HasFocus() then input.editBox:ClearFocus() end
    end
    e.flushing = false
end

-- FX-only controls inside the series remote (opts.extra): effect picker, sliders, centre.
local function BuildExtra(e, parent, top)
    local inner = parent:GetWidth() - PAD*2
    local y = top
    local header = SL.CreateSectionHeader(parent,"FX","효과 미리보기",{showLine=true})
    header:SetPoint("TOPLEFT",parent,"TOPLEFT",PAD,y); header:SetPoint("RIGHT",parent,"RIGHT",-PAD,0)
    y = y - 34
    e.icon = parent:CreateTexture(nil,"ARTWORK")
    e.icon:SetSize(28,28); e.icon:SetPoint("TOPLEFT",parent,"TOPLEFT",PAD,y)
    -- FX's searchable picker: StyleLib's dropdown has no search for up to 128 effects.
    e.rulePicker = W.CreateDropdown(parent,"FX","",{},nil,{width=inner-36,searchable=true,
        placeholder="미리볼 효과 선택",onChange=function(index) FX:SelectEditRule(index) end})
    e.rulePicker:SetPoint("TOPLEFT",parent,"TOPLEFT",PAD+36,y-2); e.rulePicker:SetSize(inner-36,24)
    W.SetTooltip(e.rulePicker,"현재 전문화에 등록한 스킬·버프 효과를 검색하고 선택하여 미리보기와 편집 대상을 전환합니다.")
    y = y - 34
    e.presetName = W.MakeFont(parent,SL.Font.small,C.text.dim,"")
    e.presetName:SetPoint("TOPLEFT",parent,"TOPLEFT",PAD,y); e.presetName:SetWidth(inner)
    e.presetName:SetWordWrap(false); e.presetName:SetJustifyH("LEFT")
    y = y - 24
    for _, field in ipairs({
        {"scale","크기 (%)",10,400,1,100,"100% = 기본 크기 · 가로·세로 비율을 유지합니다.\n기존에 조절한 크기는 100% 기준으로 보존됩니다."},
        {"opacity","투명도 (%)",0,100,1,100,"0% = 보이지 않음 · 100% = 원래 진하기\n모션에만 적용되며 편집 영역과 효과음은 유지됩니다."},
        {"speed","재생 속도",.25,4,.05,1,"1 = 원래 속도 · 0.25~4배"},
    }) do
        local key = field[1]
        local input = SL.CreateSlider(parent,"FX",field[2],field[3],field[4],field[5],field[6],{
            onChange=function(value) if not e.syncing then FX:ChangeEditSetting(key,value,key) end end})
        input:SetPoint("TOPLEFT",parent,"TOPLEFT",PAD,y)
        input.editBox = input.valueBox
        -- Validate typed values ("125%", out of range) before the slider clamps them.
        input.editBox:SetScript("OnEnterPressed",function(box) FX:ChangeEditSetting(key,box:GetText()); box:ClearFocus() end)
        input.editBox:SetScript("OnEditFocusLost",function(box) FX:ChangeEditSetting(key,box:GetText()) end)
        input.editBox:SetScript("OnEscapePressed",function(box)
            if e.rule then box:SetText(FormatValue(key,e.rule[key])) end
            box:ClearFocus()
        end)
        function input:SetValue(value)
            e.syncing = true; self.slider:SetValue(value); e.syncing = false
            if not self.editBox:HasFocus() then self.editBox:SetText(FormatValue(key,value)) end
        end
        function input:GetValue() return self.slider:GetValue() end
        W.SetTooltip(input.slider,field[7])
        e.inputs[key] = input
        y = y - 52
    end
    e.center = SL.CreateButton(parent,"FX","중앙으로",function() FX:SetEditValues({x=0,y=0}) end,{width=96,height=26})
    e.center:SetPoint("TOPLEFT",parent,"TOPLEFT",PAD,y)
    y = y - 34
    return top - y
end

function FX:CreateEditMode()
    local e = CreateFrame("Frame","DDingUI_FXEditMode",UIParent)
    self.editor = e
    e:SetAllPoints(UIParent); e:SetFrameStrata("DIALOG"); e:EnableMouse(false)
    e:Hide()
    -- [STYLE] Escape (UISpecialFrames calls :Hide) uses the same fade + GUI reopen as "완료".
    e.HideImmediately, e.Hide = e.Hide, function() FX:CloseEditMode(true) end
    table.insert(UISpecialFrames,"DDingUI_FXEditMode")
    e.gridEnabled, e.gridSpacing = true, SPEC.gridSpacing
    e.snap = {enabled=true,center=true,grid=true,frames=false}
    e.inputs, e.undo, e.redo = {}, {}, {}
    e.grid = SL.CreateEditGrid("FX")
    e.guides = SL.CreateEditGuides("FX")

    local mover = CreateFrame("Button",nil,e)
    e.mover = mover
    mover:SetFrameLevel(100); mover:EnableMouse(true)
    e.moverStyle = SL.StyleMover(mover,"FX",{label=""})
    e.moverStyle:SetSelected(true)
    mover:SetScript("OnEnter",function() e.moverStyle:SetHover(true) end)
    mover:SetScript("OnLeave",function() e.moverStyle:SetHover(false) end)
    -- The preview sits above the mover fill so the selection tint frames the motion, not covers it.
    e.player = self:CreatePlayer(e)
    e.player:SetFrameLevel(101); e.player:SetAllPoints(mover)
    e.hud = SL.CreateMoverHUD(mover,"FX")
    mover:SetScript("OnMouseDown",function(_,button)
        if button ~= "LeftButton" or e.closing or not FX:CanEdit() then return end
        FX:FlushEditInputs()
        local x,y = GetCursorPosition()
        e.drag = {x=x,y=y,oldX=e.rule.x,oldY=e.rule.y}
        mover:SetScript("OnUpdate",function()
            if not FX:CanEdit() then FX:CloseEditMode(false); return end
            if not IsMouseButtonDown("LeftButton") then FX:FinishEditDrag(); return end
            local cx,cy = GetCursorPosition()
            local scale = UIParent:GetEffectiveScale()
            e.rule.x = math.floor(FX.Number(e.drag.oldX+(cx-e.drag.x)/scale,-4096,4096,0)+.5)
            e.rule.y = math.floor(FX.Number(e.drag.oldY+(cy-e.drag.y)/scale,-4096,4096,0)+.5)
            -- Centre offsets share the grid origin (screen centre), so grid lines and snap agree.
            if e.snap.enabled and not IsShiftKeyDown() then
                for _,key in ipairs({"x","y"}) do
                    local value, hit = e.rule[key], false
                    if e.snap.center then value, hit = SL.SnapToCenter(value,SNAP) end
                    if not hit and e.snap.grid and e.gridEnabled then value = SL.SnapToGrid(value,e.gridSpacing,SNAP) end
                    e.rule[key] = value
                end
            end
            FX:RefreshEditMode()
        end)
    end)
    mover:SetScript("OnMouseUp",function(_,button) if button == "LeftButton" then FX:FinishEditDrag() end end)
    W.SetTooltip(mover,"드래그로 위치 이동 · Shift를 누르면 스냅을 잠시 해제합니다.")

    local remote = SL.CreateEditRemote("FX",{
        title="DDingUI FX 편집 모드", version=self.version,
        onNudge=function(dx,dy) FX:NudgeEdit(dx,dy) end,
        onApplyXY=function(x,y) FX:SetEditValues({x=x,y=y}) end,
        onReset=function() FX:SetEditValues({x=0,y=0,scale=100,opacity=100,speed=1}) end,
        onUndo=function() FX:StepEditHistory("undo","redo") end,
        onRedo=function() FX:StepEditHistory("redo","undo") end,
        onDone=function() FX:CloseEditMode(true) end,
        grid={enabled=true,spacing=SPEC.gridSpacing,
            onToggle=function(on) e.gridEnabled = on and true or false; FX:RefreshEditGrid(true) end,
            onSpacing=function(spacing) e.gridSpacing = spacing; FX:RefreshEditGrid(false) end},
        -- FX edits one effect at a time: no other frames to snap to, so no "프레임" check.
        snap={enabled=true,center=true,grid=true,frames=false,noFrames=true,
            onChange=function(key,on) e.snap[key] = on and true or false end},
        extra=function(parent,top) return BuildExtra(e,parent,top) end,
        loadPosition=function()
            local saved = FX.db.editRemotePos
            if type(saved) ~= "table" or not POINTS[saved.point] then return end
            local x, y = FX.Number(saved.x,-4096,4096), FX.Number(saved.y,-4096,4096)
            if x and y then return saved.point, x, y end
        end,
        savePosition=function(point,x,y) FX.db.editRemotePos = {point=point,x=x,y=y} end,
    })
    e.remote, e.titleBar, e.done = remote, remote.titleBar, remote.buttons["완료"]
    -- Typed X/Y commit on Enter or focus loss like FX's other fields.
    e.inputs.x, e.inputs.y = remote.xField, remote.yField
    for key, field in pairs({x=remote.xField,y=remote.yField}) do
        field.editBox:HookScript("OnEditFocusLost",function(box) FX:ChangeEditSetting(key,box:GetText()) end)
    end

    e:SetScript("OnHide",function()
        FX:FinishEditDrag()
        for _,input in pairs(e.inputs) do input.editBox:ClearFocus() end
        e.player:Stop(); mover:SetScript("OnUpdate",nil); e.drag = nil
        Motion.StopAll(e); Motion.StopAll(mover); Motion.StopAll(e.grid)
        e:SetAlpha(1); e.grid:Hide(); e.grid:SetAlpha(1); e.guides:Hide()
        remote:HideImmediately()
        e.rule, e.closing = nil, nil
        W.CloseDropdowns(); GameTooltip:Hide()
        if FX.window then FX.window.editMode:Refresh() end
    end)
    return e
end

function FX:ToggleEditMode()
    if not self.db then return end
    if self.editor and self.editor:IsShown() then self:CloseEditMode(true); return end
    if not self.window then self:CreateUI() end
    self:FlushInputs()
    if not self:CanEdit() then self:RefreshStatus(); return end
    local index = self.selected or (#self.db.rules > 0 and 1)
    local source = index and self.db.rules[index]
    if not source then
        self.window:Show(); self:Message("스킬을 추가하거나 목록에서 편집할 스킬을 선택하세요.")
        return
    end
    local e = self.editor or self:CreateEditMode()
    self.window:HideImmediately()
    self:StopLive()
    e:Show()
    self:SelectEditRule(index)
    e:SetAlpha(0)
    Motion.FadeIn(e,.18,{key="editor",fromAlpha=0})
    e.remote:Show()
    -- C12: the grid is on whenever edit mode opens (fires onToggle → animated reveal).
    e.remote:SetGridState(true)
    self.window.editMode:Refresh()
end

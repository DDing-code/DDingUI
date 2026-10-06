-- [STYLE] C12 series edit mode built from the shared StyleLib 1.4 parts (EditMode.lua).
-- Position model stays APL's own: db.x/db.y are CENTER offsets in display-scale units.
-- The mover, HUD and remote work in UIParent units (offset * db.scale) and convert back on save.
local _, A = ...
local S=LibStub("DDingUI-StyleLib-1.0")
local T=A.T
local POINTS={TOP=true,BOTTOM=true,LEFT=true,RIGHT=true,CENTER=true,TOPLEFT=true,TOPRIGHT=true,BOTTOMLEFT=true,BOTTOMRIGHT=true}

-- [12.0.1] Positions only come from the cursor and typed numbers; still refuse secret/NaN/inf values.
local function finite(value)
    if value == nil or (issecretvalue and issecretvalue(value)) then return nil end
    value=tonumber(value)
    if not value or value ~= value or value == math.huge or value == -math.huge then return nil end
    return value
end
local function round(value) return math.floor(value+.5) end
local function spec() return S.EditModeSpec or {} end

--- Mover size and CENTER offset in UIParent units.
function A:GetEditRect()
    local scale=self.db.scale
    return self.db.x*scale,self.db.y*scale,self.display:GetWidth()*scale,self.display:GetHeight()*scale
end

--- Writes the saved position (display-scale units) and moves the display. Out of combat only.
function A:MoveEditDB(x,y,record)
    local e=self.edit
    x,y=finite(x),finite(y)
    if not (e and self.editing and x and y) or InCombatLockdown() then return false end
    if record and (x ~= self.db.x or y ~= self.db.y) then
        e.undo[#e.undo+1]={x=self.db.x,y=self.db.y}
        e.redo={}
    end
    self.db.x,self.db.y=x,y
    self.display:ClearAllPoints()
    self.display:SetPoint("CENTER",UIParent,"CENTER",x,y)
    self:RefreshEditMover()
    return true
end

--- Same as MoveEditDB but takes a mover offset (UIParent units), rounded and kept on screen.
function A:SetEditPosition(x,y,record)
    x,y=finite(x),finite(y)
    if not (x and y) then return false end
    local _,_,w,h=self:GetEditRect()
    local maxX=math.max(0,(UIParent:GetWidth()-w)/2)
    local maxY=math.max(0,(UIParent:GetHeight()-h)/2)
    x=round(math.max(-maxX,math.min(maxX,x)))
    y=round(math.max(-maxY,math.min(maxY,y)))
    local scale=self.db.scale
    return self:MoveEditDB(x/scale,y/scale,record)
end

--- Center / grid / screen-edge snap for a dragged mover offset (Shift bypasses it while dragging).
function A:SnapEditOffset(x,y,w,h)
    local e=self.edit
    local snap=e.snap
    if not snap.enabled or IsShiftKeyDown() then return x,y end
    local threshold=spec().snapThreshold or 8
    local sx,sy=false,false
    if snap.center then
        x,sx=S.SnapToCenter(x,threshold)
        y,sy=S.SnapToCenter(y,threshold)
    end
    if snap.grid and e.gridOn then -- same spacing and origin (screen centre) as the visible grid
        if not sx then x,sx=S.SnapToGrid(x,e.spacing,threshold) end
        if not sy then y,sy=S.SnapToGrid(y,e.spacing,threshold) end
    end
    if not (sx and sy) then -- APL has one frame: the hidden "프레임" option becomes an always-on screen-edge snap
        local W,H=UIParent:GetWidth(),UIParent:GetHeight()
        local dx,dy=S.SnapToRects({W/2+x-w/2,H/2+y-h/2,w,h},{{0,0,W,H}},threshold)
        if not sx then x=x+dx end
        if not sy then y=y+dy end
    end
    return x,y
end

function A:RefreshEditMover()
    local e=self.edit
    if not (e and self.editing) then return end
    local x,y,w,h=self:GetEditRect()
    e.overlay:SetSize(w,h)
    e.overlay:ClearAllPoints()
    e.overlay:SetPoint("CENTER",UIParent,"CENTER",x,y)
    e.mover:SetDisabled(not self.db.enabled,not self.db.enabled and T("표시 꺼짐","Display off") or nil)
    e.hud:Update(x,y,w,h)
    e.remote:SetSelection({name=T("APL 표시창","APL display"),anchor="UIParent · CENTER",x=x,y=y,w=w,h=h})
    e.remote:SetUndoState(#e.undo > 0,#e.redo > 0)
end

function A:UpdateEditDrag()
    local e=self.edit
    local drag=e and e.drag
    if not drag then return end
    if InCombatLockdown() then self:StopEditMode(true); return end
    if not IsMouseButtonDown("LeftButton") then self:FinishEditDrag(); return end
    local cx,cy=GetCursorPosition()
    cx,cy=finite(cx),finite(cy)
    local uiScale=finite(UIParent:GetEffectiveScale())
    if not (cx and cy and uiScale and uiScale > 0) then return end
    local _,_,w,h=self:GetEditRect()
    local x,y=self:SnapEditOffset(drag.x+(cx-drag.cx)/uiScale,drag.y+(cy-drag.cy)/uiScale,w,h)
    if self:SetEditPosition(x,y,false) then
        local nx,ny=self:GetEditRect()
        e.guides:ShowAt(UIParent:GetWidth()/2+nx,UIParent:GetHeight()/2+ny)
    end
end

function A:FinishEditDrag()
    local e=self.edit
    local drag=e and e.drag
    if not drag then return end
    e.drag=nil
    e.overlay:SetScript("OnUpdate",nil)
    e.guides:Hide()
    if drag.fromX ~= self.db.x or drag.fromY ~= self.db.y then
        e.undo[#e.undo+1]={x=drag.fromX,y=drag.fromY}
        e.redo={}
    end
    self:RefreshEditMover()
end

function A:StepEditHistory(from,to)
    local e=self.edit
    if not (e and self.editing) or InCombatLockdown() then return end
    self:FinishEditDrag()
    local entry=table.remove(e[from])
    if not entry then return end
    e[to][#e[to]+1]={x=self.db.x,y=self.db.y}
    self:MoveEditDB(entry.x,entry.y,false)
end

function A:CreateEditMode()
    local e={undo={},redo={},spacing=spec().gridSpacing or 32,gridOn=true,
        snap={enabled=true,center=true,grid=true}}
    self.edit=e
    e.grid=S.CreateEditGrid(self.name)
    e.guides=S.CreateEditGuides(self.name)
    local overlay=CreateFrame("Frame","DDIngUI_APLEditMover",UIParent)
    e.overlay=overlay
    overlay:SetFrameStrata("HIGH")
    overlay:EnableMouse(true)
    overlay:Hide()
    e.mover=S.StyleMover(overlay,self.name,{label=T("APL 표시창","APL display")})
    e.hud=S.CreateMoverHUD(overlay,self.name)
    overlay:SetScript("OnEnter",function() e.mover:SetHover(true) end)
    overlay:SetScript("OnLeave",function() e.mover:SetHover(false) end)
    overlay:SetScript("OnMouseDown",function(_,button)
        if button ~= "LeftButton" or not self.editing or InCombatLockdown() then return end
        local cx,cy=GetCursorPosition()
        cx,cy=finite(cx),finite(cy)
        if not (cx and cy) then return end
        local x,y=self:GetEditRect()
        e.drag={cx=cx,cy=cy,x=x,y=y,fromX=self.db.x,fromY=self.db.y}
        overlay:SetScript("OnUpdate",function() self:UpdateEditDrag() end)
    end)
    overlay:SetScript("OnMouseUp",function(_,button) if button == "LeftButton" then self:FinishEditDrag() end end)
    e.remote=S.CreateEditRemote(self.name,{
        title="DDingUI APL 편집 모드", version=self.version,
        onNudge=function(dx,dy)
            local x,y=self:GetEditRect()
            self:SetEditPosition(x+dx,y+dy,true)
        end,
        onApplyXY=function(x,y) self:SetEditPosition(x,y,true) end,
        onReset=function() self:MoveEditDB(self.DEFAULT_X,self.DEFAULT_Y,true) end,
        onUndo=function() self:StepEditHistory("undo","redo") end,
        onRedo=function() self:StepEditHistory("redo","undo") end,
        onDone=function() self:StopEditMode() end,
        grid={enabled=true,spacing=e.spacing,
            onToggle=function(on)
                e.gridOn=on and true or false
                if on then e.grid:ShowAnimated() else e.grid:HideAnimated() end
            end,
            onSpacing=function(n) e.spacing=n; e.grid:SetSpacing(n) end},
        snap={enabled=true,center=true,grid=true,noFrames=true,onChange=function(key,on) e.snap[key]=on and true or false end},
        loadPosition=function()
            local p=self.db.editRemotePos
            if type(p) ~= "table" or not POINTS[p.point] then return nil end -- series format { point=, x=, y= }
            local x,y=finite(p.x),finite(p.y)
            if not (x and y) then return nil end
            return p.point,x,y
        end,
        savePosition=function(point,x,y) self.db.editRemotePos={point=point,x=x,y=y} end,
    })
    return e
end

function A:StartEditMode()
    if not (self.db and self.display) then return end
    if InCombatLockdown() then self:Print(T("편집 모드는 전투가 끝나면 열 수 있어요.","Edit mode is available after combat.")); return end
    local e=self.edit or self:CreateEditMode()
    local options=self.options
    e.reopen=options and options:IsShown() and not options._ddslPanelClosing or false
    if options and options:IsShown() then -- C12: the settings window steps aside (FX handoff)
        if options.HideImmediately then options:HideImmediately() else options:Hide() end
    end
    self.editing=true
    e.undo,e.redo,e.drag={}, {},nil
    e.gridOn=true
    e.remote:SetGridState(true,e.spacing)
    e.grid:SetSpacing(e.spacing)
    e.grid:ShowAnimated() -- C12: grid on at entry, 0.75s reveal
    e.overlay:Show()
    e.mover:SetSelected(true)
    e.hud:Show()
    self:RefreshEditMover()
    e.remote:Show()
    self:RefreshEditButton()
end

--- C12 title-bar "편집 모드"/"편집 중" label.
function A:RefreshEditButton()
    local bar=self.options and self.options.titleBar
    if bar and bar.editButton then bar.editButton:Refresh() end
end

--- immediate=true: combat/teardown (no motion, no settings reopen).
function A:StopEditMode(immediate)
    local e=self.edit
    if not (e and self.editing) then return end
    self:FinishEditDrag()
    self.editing=false
    e.overlay:SetScript("OnUpdate",nil)
    e.overlay:Hide(); e.hud:Hide(); e.guides:Hide()
    e.mover:SetSelected(false); e.mover:SetHover(false)
    if immediate then
        if S.Motion and S.Motion.StopAll then S.Motion.StopAll(e.grid) end
        e.grid:Hide()
        if e.remote.HideImmediately then e.remote:HideImmediately() else e.remote:Hide() end
    else
        e.grid:HideAnimated()
        e.remote:Hide() -- BindPanel close motion (the remote title-bar X calls onDone)
    end
    self:RefreshEditButton()
    local reopen=e.reopen
    e.reopen=nil
    local options=self.options
    if reopen and not immediate and not InCombatLockdown() and options and not options:IsShown() then
        self:OpenOptions()
    elseif options and options:IsShown() and options.refresh then
        options.refresh()
    end
end

function A:ToggleEditMode()
    if self.editing then self:StopEditMode() else self:StartEditMode() end
end

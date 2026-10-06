-- [STYLE] Standalone StyleLib UI. All interactive controls are addon-owned.
local _, A = ...
local S=LibStub("DDingUI-StyleLib-1.0")
S.RegisterAddon(A.name,S.AccentPresets.CDM)
local C,T=S.Colors,A.T
local function background(frame,color)
    frame:SetBackdrop({bgFile=S.Textures.flat,edgeFile=S.Textures.flat,edgeSize=1})
    frame:SetBackdropColor(unpack(color or C.bg.main))
    frame:SetBackdropBorderColor(unpack(C.border.default))
end
local function label(parent,text,x,y,width,size,color)
    local fs=parent:CreateFontString(nil,"OVERLAY")
    fs:SetFont(S:GetFont("primary"),size or 13,"")
    fs:SetTextColor(unpack(color or C.text.normal))
    fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
    fs:SetPoint("TOPLEFT",x,y)
    if width then fs:SetWidth(width) end
    fs:SetText(text)
    if parent.rows then parent.rows[#parent.rows+1]=fs end -- [STYLE] settings rows for StaggerIn
    return fs
end
local function button(parent,text,x,y,width,callback)
    local b=S.CreateButton(parent,A.name,text,callback,{width=width,height=26})
    b:SetPoint("TOPLEFT",x,y)
    if parent.rows then parent.rows[#parent.rows+1]=b end -- [STYLE] settings rows for StaggerIn
    return b
end
-- [STYLE] 시안 7 page selector: rounded row (Radius.row), clear at rest, RowHover (bg tween + 2px label
-- nudge), and a rounded accent pill (alpha 0.18) on the selected page.
local function navRow(parent,text,x,y,width,callback)
    local b=CreateFrame("Button",nil,parent)
    b:SetSize(width,28); b:SetPoint("TOPLEFT",x,y)
    local radius,hover,accent=S.Radius.row,C.bg.hover,S.GetAccent(A.name)
    local bg=b:CreateTexture(nil,"BACKGROUND")
    bg:SetAllPoints(); S.RoundTexture(bg,radius)
    bg:SetVertexColor(hover[1],hover[2],hover[3],0)
    local pill=b:CreateTexture(nil,"BORDER")
    pill:SetAllPoints(); S.RoundTexture(pill,radius)
    pill:SetVertexColor(accent[1],accent[2],accent[3],.18); pill:Hide()
    b.pill=pill
    local fs=b:CreateFontString(nil,"OVERLAY")
    fs:SetFont(S:GetFont("primary"),S.Font.normal,"")
    fs:SetTextColor(unpack(C.text.normal))
    fs:SetPoint("CENTER",0,0); fs:SetText(text)
    b.label=fs
    b:SetScript("OnClick",callback)
    function b:SetSelected(on)
        pill:SetShown(on)
        fs:SetTextColor(unpack(on and C.text.highlight or C.text.normal))
    end
    -- RowHover tints through SetColorTexture, which would replace the rounded mask; route it to the vertex colour.
    local tint={SetColorTexture=function(_,r,g,bl,a) bg:SetVertexColor(r,g,bl,a) end}
    if S.RowHover then S.RowHover(b,{bg=tint,label=fs,normal={hover[1],hover[2],hover[3],0},hover=hover}) end
    return b
end
local function editor(parent,x,y,width,height,max)
    local box=CreateFrame("Frame",nil,parent,"BackdropTemplate")
    box:SetPoint("TOPLEFT",x,y); box:SetSize(width,height)
    S.MakeRounded(box,S.Radius.control,C.bg.input,C.border.default) -- [STYLE] 시안 7 rounded input
    local scroll=CreateFrame("ScrollFrame",nil,box,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",8,-8); scroll:SetPoint("BOTTOMRIGHT",-28,8)
    local edit=CreateFrame("EditBox",nil,scroll)
    edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetMaxLetters(max or 262144)
    edit:SetFont(S:GetFont("primary"),12,"")
    edit:SetTextColor(unpack(C.text.normal))
    edit:SetWidth(width-42); edit:SetHeight(height-16)
    edit:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    edit:SetScript("OnCursorChanged",function(self,_,ypos,_,h)
        local top=scroll:GetVerticalScroll()
        local cursor=-ypos
        if cursor < top then scroll:SetVerticalScroll(cursor)
        elseif cursor+h > top+scroll:GetHeight() then scroll:SetVerticalScroll(cursor+h-scroll:GetHeight()) end
    end)
    scroll:SetScrollChild(edit)
    box:SetScript("OnMouseDown",function() edit:SetFocus() end)
    if parent.rows then parent.rows[#parent.rows+1]=box end -- [STYLE] settings rows for StaggerIn
    return edit
end
function A:CreateDisplay()
    local f=CreateFrame("Frame","DDIngUI_APLDisplay",UIParent,"BackdropTemplate")
    self.display=f
    f:SetSize(236,144); background(f) -- [STYLE] +2px so the 12pt reason keeps two lines
    f:SetMovable(true); f:SetClampedToScreen(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",function()
        if not self.db.locked and not InCombatLockdown() then f:StartMoving() end
    end)
    f:SetScript("OnDragStop",function()
        f:StopMovingOrSizing()
        if InCombatLockdown() then return end
        local x,y=f:GetCenter()
        local parentX,parentY=UIParent:GetCenter()
        self.db.x=x-parentX/self.db.scale
        self.db.y=y-parentY/self.db.scale
    end)
    f:SetScript("OnMouseUp",function(_,mouse) if mouse == "RightButton" then self:OpenOptions() end end)
    f.heading=label(f,"DDIngUI · APL",10,-8,218,12,S.GetAccent(A.name))
    f.badge=label(f,"",10,-26,218,12,C.text.dim) -- [STYLE] series 12pt minimum
    f.slots={}
    for i=1,3 do
        local slot=CreateFrame("Frame",nil,f,"BackdropTemplate")
        slot:SetSize(56,56); slot:SetPoint("TOPLEFT",12+(i-1)*76,-46); background(slot,C.bg.widget)
        slot.icon=slot:CreateTexture(nil,"ARTWORK"); slot.icon:SetPoint("TOPLEFT",3,-3); slot.icon:SetPoint("BOTTOMRIGHT",-3,3)
        slot.icon:SetTexCoord(.08,.92,.08,.92)
        slot.key=label(slot,"",3,-3,50,12,C.text.highlight) -- [STYLE] series 12pt minimum
        slot.empty=label(slot,"—",19,-18,30,16,C.text.dim)
        f.slots[i]=slot
    end
    f.forecastNote=label(f,T("다음 한 수\n후속 예측 미지원","Next action\nForecast unavailable"),88,-57,136,12,C.text.dim)
    f.reason=label(f,"",10,-108,218,12,C.text.dim) -- [STYLE] series 12pt minimum
    f.reason:SetHeight(30)
    f:SetScript("OnEnter",function()
        GameTooltip:SetOwner(f,"ANCHOR_TOP")
        GameTooltip:SetText("DDIngUI_Attack Priority List")
        GameTooltip:AddLine(self.last and self.last.reason or "",nil,nil,nil,true)
        GameTooltip:AddLine(T("우클릭: 설정 · /ddapl","Right click: options · /ddapl"))
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave",function() GameTooltip:Hide() end)
    self:ApplyLayout()
end
function A:ToggleDisplayLock() -- [STYLE] /ddapl lock (minimap right-click is the C12 edit mode)
    if InCombatLockdown() then self:Print(T("전투가 끝나면 설정해 주세요.","Change settings after combat.")); return end
    self:SetOption("locked",not self.db.locked)
    if self.options and self.options:IsShown() then self.options.refresh() end -- [STYLE] keep lock button label in sync
    self:Print(self.db.locked and T("위치 잠김","Position locked") or T("드래그 가능","Drag enabled")) -- [STYLE] existing lock wording
end
function A:CreateMinimapButton() -- [STYLE] StyleLib helper owns the button and tooltip
    S.CreateMinimapButton({
        key="DDIngUI_APL", addonKey=self.name, displayName="APL",
        icon="Interface\\AddOns\\DDIngUI_APL\\Media\\APL_Icon.tga",
        db=self.db.minimap,
        onLeftClick=function() self:OpenOptions() end,
        onRightClick=function() self:ToggleEditMode() end, -- [STYLE] C12: matches the default "편집 모드 · 위치 조정" tooltip
    })
end
function A:ApplyLayout()
    if InCombatLockdown() or not self.display then return end
    self.display:ClearAllPoints()
    self.display:SetScale(self.db.scale)
    self.display:SetPoint("CENTER",UIParent,"CENTER",self.db.x,self.db.y)
    self.display:SetShown(self.db.enabled)
    if self.auraProxy then self.auraProxy:SetShown(self.db.enabled and not self.preview and self.auraSpell == self.db.auraSpellID) end
    if self.editing and self.RefreshEditMover then self:RefreshEditMover() end -- [STYLE] C12 mover follows scale/visibility
end
function A:Render(result)
    local f=self.display
    if not f then return end
    f:SetShown(self.db.enabled)
    local source=result.source or "APL"
    local queue=result.queue
    local held=false
    local now=GetTime()
    if self.db.enabled and result.kind == "action" and source == "BLIZZARD" then
        f.lastNative={step=queue[1],time=now}
    elseif self.db.enabled and not self.preview and self.db.mode ~= "strict"
        and result.nativeStatus == "empty" and f.lastNative and now-f.lastNative.time <= 0.4
        and self.API.Query(UnitExists,"target") == true
        and self.API.Query(UnitIsDeadOrGhost,"target") == false
        and self.API.Query(UnitIsDeadOrGhost,"player") == false then
        -- [FIX] Presentation-only grace for a brief empty native sample. The engine and
        -- A.last remain unresolved. Never retain a restricted/failed sample as a recommendation.
        queue={f.lastNative.step}; source="BLIZZARD"; held=true
    else f.lastNative=nil end
    f.badge:SetText(source.." · "..(held and T("갱신 대기","Waiting for update") or T("대상 수동 ","manual targets ")..self.db.targets))
    f.badge:SetTextColor(unpack(source == "APL" and result.kind == "action" and C.status.success or C.status.warning))
    f.reason:SetText(held and T("직전 표시 유지 · 현재 추천 대기","Previous icon · awaiting recommendation") or result.reason or result.nativeReason or "")
    f.forecastNote:SetShown(not self.preview)
    for i,slot in ipairs(f.slots) do
        slot:SetShown(i == 1 or self.preview == true)
        local step=queue and queue[i]
        local id=step and step.spellID
        local texture=id and (slot.spellID == id and slot.texture or self.API.Query(C_Spell and C_Spell.GetSpellTexture,id))
        if slot.texture ~= texture then slot.icon:SetTexture(texture) end
        slot.spellID,slot.texture=id,texture
        slot.icon:SetDesaturated(held)
        slot.empty:SetShown(not texture)
        slot.key:SetText(id and not self.preview and self.keys and self.keys[id] or "")
    end
end
function A:OpenOptions()
    if InCombatLockdown() then self:Print(T("설정은 전투가 끝나면 열 수 있어요.","Open options after combat.")); return end
    local f=self.options
    if f then -- [STYLE] C4: x, Esc, /ddapl and minimap all go through Motion.BindPanel Show/Hide
        if f:IsShown() and not f._ddslPanelClosing then f:Hide(); return end
        local wasHidden=not f:IsShown()
        f:Show(); f.refresh()
        if wasHidden then f.stagger() end
        return
    end
    f=CreateFrame("Frame","DDIngUI_APLOptions",UIParent,"BackdropTemplate")
    self.options=f
    f:SetSize(760,670); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    if S.AllowOffscreen then S.AllowOffscreen(f) else f:SetClampedToScreen(true) end -- [STYLE] 화면 밖으로 걸쳐 두기
    S.MakeRounded(f,S.Radius.window,C.bg.main,C.border.default) -- [STYLE] 시안 7 rounded window
    f:EnableMouse(true); f:SetMovable(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",function() if not InCombatLockdown() then f:StartMoving() end end)
    f:SetScript("OnDragStop",function() f:StopMovingOrSizing() end)
    tinsert(UISpecialFrames,"DDIngUI_APLOptions")
    -- [STYLE] Minimal title-bar area (no fill, so nothing reaches the rounded corners) holding the
    -- series logo rings, the "GUI 크기" control and the close button.
    local titleBar=CreateFrame("Frame",nil,f)
    titleBar:SetPoint("TOPLEFT",0,0); titleBar:SetPoint("TOPRIGHT",0,0); titleBar:SetHeight(54)
    f.titleBar=titleBar
    f.logo=S.CreateLogoRings(titleBar,20,S.GetAccent(self.name)) -- [STYLE] 시안 7 logo motif; PlayLink on open
    f.logo:SetPoint("TOPLEFT",16,-15)
    local title=label(f,"DDIngUI_Attack Priority List",48,-15,nil,18,S.GetAccent(self.name))
    local subtitle=label(f,self.version.." · 12.1 · "..T("게임 내 검증 전","in-game validation pending"),48,-40,nil,12,C.text.dim) -- [STYLE] 12pt minimum
    titleBar.closeBtn=button(titleBar,"×",718,-12,26,function() f:Hide() end)
    -- [STYLE] C12 title-bar edit button: same widget and order as StyleLib CreateTitleBar opts.editMode
    -- (close · edit mode · GUI scale, right to left). This window keeps its own title bar (logo rings).
    local editButton=S.CreateButton(titleBar,self.name,T("편집 모드","Edit mode"),function() self:ToggleEditMode() end,{width=76,height=22})
    editButton:SetPoint("RIGHT",titleBar.closeBtn,"LEFT",-8,0)
    function editButton:Refresh()
        if self.label then self.label:SetText(A.editing and T("편집 중","Editing") or T("편집 모드","Edit mode")) end
    end
    editButton:Refresh()
    titleBar.editButton=editButton
    titleBar.scaleControl=S.CreateTitleScaleControl(titleBar,self.name,{
        get=function() return self.db.guiScale end,
        set=function(value) self.db.guiScale=value end,
        target=f,
    })
    titleBar.scaleControl:SetPoint("RIGHT",editButton,"LEFT",-8,0)
    title:SetPoint("TOPRIGHT",titleBar.scaleControl,"TOPLEFT",-4,-2)
    subtitle:SetPoint("TOPRIGHT",titleBar.scaleControl,"TOPLEFT",-4,-27)
    -- [STYLE] 시안 7: page tabs and page body are rounded cards (Radius.card) 8px inside the window.
    local function card(y,height)
        local c=CreateFrame("Frame",nil,f)
        c:SetPoint("TOPLEFT",8,y); c:SetSize(744,height)
        S.MakeRounded(c,S.Radius.card,C.bg.sidebar,C.border.separator)
        return c
    end
    f.tabCard=card(-58,40)
    f.body=card(-106,556)
    f.watermark=S.AddWatermark(f.body,self.name)
    local pages,refreshers,tabs={},{},{}
    f.tabs=tabs
    local function selectPage(index)
        f.page=index
        for i,page in ipairs(pages) do page:SetShown(i == index) end
        for i,tab in ipairs(tabs) do tab:SetSelected(i == index) end
        if refreshers[index] then refreshers[index]() end
    end
    for i,title in ipairs({T("일반","General"),"APL",T("전문화 팩","Spec packs"),T("진단","Diagnostics")}) do
        local index=i
        tabs[i]=navRow(f.tabCard,title,8+(i-1)*183,-6,177,function() selectPage(index) end)
        local page=CreateFrame("Frame",nil,f.body)
        page:SetPoint("TOPLEFT",10,-8); page:SetSize(724,540); page:Hide()
        page.rows={}
        pages[i]=page
    end
    local general=pages[1]
    local summary=label(general,"",0,0,714,13)
    label(general,T("자동: 자체 APL 평가 → 불확실하면 기본 추천\n엄격: 자체 APL만 사용 · 기본: 블리자드 추천만 사용",
        "Auto: evaluate APL, then fall back if unresolved\nStrict: APL only · Native: Blizzard recommendation only"),0,-52,714,12,C.text.dim)
    local mode=S.CreateDropdown(general,self.name,T("모드","Mode"),
        {{text=T("자동 대체","Auto fallback"),value="auto"},{text=T("APL 전용","APL only"),value="strict"},{text=T("블리자드","Blizzard"),value="native"}},
        self.db.mode,{width=140,onChange=function(value) self:SetOption("mode",value) end})
    mode:SetPoint("TOPLEFT",0,-104)
    general.rows[#general.rows+1]=mode
    local enabled=button(general,"",0,-146,175,function() self:SetOption("enabled",not self.db.enabled); refreshers[1]() end)
    local locked=button(general,"",188,-146,175,function() self:SetOption("locked",not self.db.locked); refreshers[1]() end)    button(general,T("대상 −","Targets −"),0,-187,110,function() self:SetOption("targets",math.max(1,self.db.targets-1)); refreshers[1]() end)
    button(general,T("대상 +","Targets +"),122,-187,110,function() self:SetOption("targets",math.min(20,self.db.targets+1)); refreshers[1]() end)
    button(general,T("크기 −","Scale −"),256,-187,110,function() self:SetOption("scale",math.max(.6,self.db.scale-.1)); refreshers[1]() end)
    button(general,T("크기 +","Scale +"),378,-187,110,function() self:SetOption("scale",math.min(2,self.db.scale+.1)); refreshers[1]() end)
    button(general,T("미리보기 전환","Toggle preview"),0,-228,175,function()
        self.preview=not self.preview; self:ApplyLayout(); self:Tick(); refreshers[1]()
    end)
    button(general,T("가상 자원 +1","Demo resource +1"),188,-228,175,function()
        self.demoPower=((self.demoPower or 2)+1)%6; self.preview=true; self:ApplyLayout(); self:Tick(); refreshers[1]()
    end)
    label(general,T("실전은 다음 1수만 표시합니다. 3수 예측은 가상 미리보기에서만 동작합니다.\n대상 수는 수동 값이며 기본 추천에는 적용되지 않습니다.",
        "Live mode shows one next action. Three-step forecasting is a synthetic preview only.\nTarget count is manual and does not change Blizzard's recommendation."),0,-272,714,12,C.text.dim)
    label(general,T("AuraContainer · 별도 실제 버프 표시","AuraContainer · separate live buff display"),0,-338,714,14,S.GetAccent(self.name))
    local auraID=S.CreateInputField(general,self.name,"Spell ID",tostring(self.db.auraSpellID or ""),{width=300,inputWidth=160})
    auraID:SetPoint("TOPLEFT",0,-370)
    general.rows[#general.rows+1]=auraID
    local auraMessage=label(general,"",0,-408,714,12,C.text.dim)
    button(general,T("연결","Bind"),340,-368,110,function()
        local text=auraID.editBox:GetText():match("^%s*(.-)%s*$")
        local id=tonumber(text)
        if text ~= "" and (not id or id < 1 or id > 10000000 or id ~= math.floor(id)) then auraMessage:SetText("Invalid spell ID"); return end
        self.db.auraSpellID=id
        self:ApplyAuraCue()
        auraMessage:SetText(self.auraStatus or "")
    end)
    label(general,T("이 표시의 숨김·중첩·시간은 Blizzard가 처리합니다.\n표시 결과를 읽어 APL 조건으로 되돌리지 않습니다. 연결 변경 후 /reload가 필요할 수 있습니다.",
        "Blizzard manages aura visibility, stacks and cooldown.\nThe display is not read back as an APL condition. Changing a binding may require /reload."),0,-449,714,12,C.text.dim)
    refreshers[1]=function()
        mode:SetValue(self.db.mode)
        summary:SetText((self.source and self.source.name or "No specialization").." · "..T("대상 ","Targets ")..self.db.targets
            .." · "..string.format("%.1f",self.db.scale).."x\n"..T("가상 자원: ","Demo resource: ")..(self.demoPower or 2))
        enabled.label:SetText(self.db.enabled and T("표시 켜짐","Display on") or T("표시 꺼짐","Display off"))
        locked.label:SetText(self.db.locked and T("위치 잠김","Position locked") or T("드래그 가능","Drag enabled"))        auraMessage:SetText(self.auraStatus or "")
    end

    local apl=pages[2]
    label(apl,T("개인 APL · 전문화별 저장 · SimC actions 문법","Personal APL · saved per spec · SimC actions syntax"),0,0,714,13)
    local raw=editor(apl,0,-25,724,264)
    label(apl,T("별칭: token=spellID (선택)","Aliases: token=spellID (optional)"),0,-300,714,12)
    local aliases=editor(apl,0,-322,724,65,8192)
    local report=label(apl,"",0,-432,714,12,C.text.dim)
    report:SetHeight(104)
    local function readProfile()
        local profile=self:Profile()
        f.editorSpec=self.spec
        raw:SetText(profile.raw or self.source and self.source.raw or "")
        aliases:SetText(profile.aliases or "")
        raw:ClearFocus(); aliases:ClearFocus()
    end
    button(apl,T("검증","Validate"),0,-397,105,function()
        report:SetText(self:CompileReport(self.Engine.Compile(raw:GetText())))
    end)
    button(apl,T("저장 / 적용","Save / apply"),117,-397,135,function()
        if f.editorSpec ~= self.spec then report:SetText(T("전문화 변경됨. 다시 열어주세요.","Spec changed. Reopen the editor.")); return end
        local _,message=self:Import(raw:GetText(),aliases:GetText())
        report:SetText(message)
    end)
    button(apl,T("기본 팩","Use upstream"),264,-397,125,function() self:ResetProfile(false); readProfile(); report:SetText(self:CompileReport(self.pack)) end)
    button(apl,T("이전 복원","Undo apply"),401,-397,125,function() self:ResetProfile(true); readProfile(); report:SetText("") end)
    button(apl,T("다시 읽기","Reload text"),538,-397,140,function() readProfile(); report:SetText("") end)
    refreshers[2]=function() if f.editorSpec ~= self.spec or not f.editorLoaded then readProfile(); f.editorLoaded=true end end

    local sources=editor(pages[3],0,0,724,538)
    refreshers[3]=function()
        local rows={T("40개 전문화 연결 / 34개 원문 팩","40 specs connected / 34 original APL packs"),
            "SimulationCraft "..self.Packs.build.." · GPL-3.0-or-later", "",
            T("원문 포함은 실행 검증 완료를 뜻하지 않습니다.","Bundled source does not mean verified live execution."),""}
        local ids={}
        for id in pairs(self.Packs.specs) do ids[#ids+1]=id end
        table.sort(ids)
        for _,id in ipairs(ids) do
            local spec=self.Packs.specs[id]
            local status=T("공개 기본 APL 없음","no upstream default APL")
            if spec.raw ~= "" then
                local compiled=self.Engine.Compile(spec.raw)
                status=compiled.valid and T("구문 통과 / 실행 제한 ","parsed / runtime limitations ")..#compiled.warnings
                    or T("구문 오류","syntax error")
            end
            rows[#rows+1]=id.." · "..spec.name.." · "..status
        end
        rows[#rows+1]="\n"..self.Packs.repository.."/tree/"..self.Packs.commit.."/ActionPriorityLists/default"
        sources:SetText(table.concat(rows,"\n")); sources:ClearFocus()
    end
    local diagnostics=editor(pages[4],0,0,724,490)
    button(pages[4],T("새로 고침","Refresh"),0,-505,140,function() self:Tick(); diagnostics:SetText(self:Diagnostics()); diagnostics:ClearFocus() end)
    refreshers[4]=function() diagnostics:SetText(self:Diagnostics()); diagnostics:ClearFocus() end
    f.refresh=function() if refreshers[f.page or 1] then refreshers[f.page or 1]() end end
    -- [STYLE] Open motion: page rows fade in one after another (whole cascade <= 0.21s).
    f.stagger=function()
        f.logo:PlayLink() -- [STYLE] 시안 7: the logo rings link up on every open
        if not S.StaggerIn then return end
        local list={}
        for _,tab in ipairs(tabs) do list[#list+1]=tab end
        for _,row in ipairs(pages[f.page or 1].rows) do list[#list+1]=row end
        S.StaggerIn(list,{step=math.min(.03,.21/math.max(1,#list-1))})
    end
    if S.Motion and S.Motion.BindPanel then S.Motion.BindPanel(f) end -- [STYLE] C4 series open/close motion
    if f.HideImmediately then f:HideImmediately() else f:Hide() end
    if f.SetBaseScale then f:SetBaseScale(self.db.guiScale) else f:SetScale(self.db.guiScale) end
    selectPage(1)
    f:Show()
    f.stagger()
end

-- [12.1] Only the native engine can inspect a protected aura slot's live state.
function A:ApplyAuraCue()
    if InCombatLockdown() then return end
    local id=self.API.Number(self.db.auraSpellID)
    if not id or id < 1 then
        if self.auraProxy then self.auraProxy:Hide() end
        self.auraStatus=T("연결 안 됨","Not bound"); return
    end
    if self.auraProxy then
        self.auraProxy:SetShown(self.db.enabled and not self.preview and self.auraSpell == id)
        self.auraStatus=self.auraSpell == id and T("연결됨 · 실제 전투 검증 전","Bound · unverified in game") or T("새 버프 적용: /reload","Apply changed buff: /reload")
        return
    end
    local proxy=CreateFrame("Frame",nil,UIParent)
    proxy:SetPoint("BOTTOMLEFT",self.display,"TOPLEFT",0,8); proxy:SetSize(40,40); proxy:Hide()
    local ok=pcall(function()
        local container=CreateFrame("AuraContainer",nil,proxy,"CustomAuraContainerTemplate")
        container:Hide(); container:SetPoint("CENTER",proxy,"CENTER"); container:SetSize(1,1)
        container:AddAuraSlot("tracked","HELPFUL",{
            candidateFilters={includeSpellIDs={[id]=true}},
            initializeFrame=function(frame)
                frame:SetSize(40,40); frame:SetPoint("CENTER",proxy,"CENTER"); frame:EnableMouse(false)
                local icon=frame:CreateTexture(nil,"ARTWORK")
                icon:SetAllPoints(frame); frame:SetIcon(icon)
                local cooldown=CreateFrame("Cooldown",nil,frame,"CooldownFrameTemplate")
                cooldown:SetAllPoints(frame); cooldown:SetDrawEdge(false); cooldown:SetDrawBling(false)
                frame:SetDurationCooldown(cooldown)
                local count=label(frame,"",3,-3,34,12,C.text.highlight)
                frame:SetApplicationCount(count,{})
            end,
        })
        container:SetUnit("player")
        if container.SetEnabled then container:SetEnabled(true) end
        container:Show(); container:UpdateAllAuras()
    end)
    if ok then
        self.auraProxy,self.auraSpell=proxy,id
        proxy:SetShown(self.db.enabled and not self.preview)
        self.auraStatus=T("연결됨 · 실제 전투 검증 전","Bound · unverified in game")
    else
        proxy:Hide()
        self.auraStatus=T("AuraContainer API 연결 실패 · 진단 필요","AuraContainer binding unavailable")
    end
end

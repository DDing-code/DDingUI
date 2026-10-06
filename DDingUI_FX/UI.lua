local _, FX = ...
local SL, W = FX.Style, FX.Controls
local C = SL.Colors
local accent = SL.GetAccent("FX")
local triggers = {START="시전 시작", SUCCESS="사용 성공 직후", AURA="버프 활성화"}
local Motion = SL.Motion
local SMALL = SL.Font.small -- [STYLE] 12pt series minimum for settings text
local R = W.Radius -- [STYLE] StyleLib 1.3 radii (시안 7): window 14 · card 10 · row 8 · control 6
-- [STYLE] List rows are transparent until hovered; the selection is the accent pill beneath them.
local ROW_CLEAR = {C.bg.hover[1],C.bg.hover[2],C.bg.hover[3],0}

-- [STYLE] Row/card backgrounds: selected colour, otherwise the current hover blend.
local function RowColor(frame, active, normal, selected)
    if active then return unpack(selected or C.bg.selected) end
    local t, hover = frame._ddslHoverProgress or 0, C.bg.hover
    return normal[1]+(hover[1]-normal[1])*t, normal[2]+(hover[2]-normal[2])*t,
        normal[3]+(hover[3]-normal[3])*t, (normal[4] or 1)+((hover[4] or 1)-(normal[4] or 1))*t
end
-- [STYLE] Rounded row/card surface; its fill is the RowHover target (StyleLib tints it).
local function RowBackground(frame, fill, border)
    W.ApplyBackdrop(frame,fill or ROW_CLEAR,border or {0,0,0,0},R.row)
    local bg = frame._ddslRounded and frame._ddslRounded.fill
    if not bg then -- square fallback without StyleLib 1.3
        bg = frame:CreateTexture(nil,"BACKGROUND")
        bg:SetPoint("TOPLEFT",1,-1); bg:SetPoint("BOTTOMRIGHT",-1,1)
    end
    return bg
end

local function Label(parent, text, x, y, size, color)
    local label = W.MakeFont(parent, size or 13, color or C.text.normal, text)
    label:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    label:SetJustifyH("LEFT")
    return label
end
-- [STYLE] Content cards are rounded (Radius.card) so no square fill reaches the window corners.
local function Panel(parent, x, y, width, height, color, border)
    local panel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    panel:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    panel:SetSize(width, height)
    W.ApplyBackdrop(panel, color or C.bg.sidebar, border or C.border.separator, R.card)
    return panel
end
local function Input(parent, text, x, y, width, inputWidth, key)
    local row = W.CreateInputField(parent, "FX", text, "", {inputWidth=inputWidth,
        onChange=function(value) FX:ApplyChange(key, value) end})
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    row:SetWidth(width)
    row.label:ClearAllPoints()
    row.label:SetPoint("LEFT", 0, 0)
    row.label:SetPoint("RIGHT", row.editBox, "LEFT", -12, 0)
    return row
end
local function Scroll(parent, x, y, width, height)
    local scroll = CreateFrame("ScrollFrame", nil, parent)
    scroll:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -y)
    scroll:SetSize(width, height)
    scroll:SetClipsChildren(true)
    local child = CreateFrame("Frame", nil, scroll)
    child:SetSize(width-4, 1)
    scroll:SetScrollChild(child)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        self:SetVerticalScroll(math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll()-delta*42)))
        FX:HideHover()
    end)
    return scroll, child
end

local function AttachSpellAutocomplete(field)
    local input = field.editBox
    local popup = CreateFrame("Frame",nil,field,"BackdropTemplate")
    field.suggestions = popup
    popup:SetPoint("TOPLEFT",input,"BOTTOMLEFT",0,-3)
    popup:SetWidth(320); popup:SetFrameStrata("TOOLTIP"); popup:EnableMouse(true)
    W.ApplyBackdrop(popup,C.bg.main,C.border.default,R.row) -- [STYLE] rounded popup
    popup.rows, popup.matches = {}, {}
    popup.hint = Label(popup,"",8,8,SMALL,C.text.dim)
    popup:Hide()
    local candidates = {}
    local function AddSpell(list, seen, id)
        if FX.IsSecret(id) or type(id) ~= "number" or id <= 0 or seen[id] then return end
        local ok, info = pcall(C_Spell.GetSpellInfo,id)
        if not ok or FX.IsSecret(info) or type(info) ~= "table" or FX.IsSecret(info.name)
            or type(info.name) ~= "string" then return end
        seen[id] = true
        list[#list+1] = {id=id,name=info.name,lower=info.name:lower(),
            icon=not FX.IsSecret(info.iconID) and info.iconID or 134400}
    end
    local function Collect()
        candidates = {}
        local seen = {}
        -- Same spellbook enumeration as UF's spell picker; refresh on every focus.
        if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
            local bank = Enum.SpellBookSpellBank.Player
            for tab=1,C_SpellBook.GetNumSpellBookSkillLines() do
                local line = C_SpellBook.GetSpellBookSkillLineInfo(tab)
                if line and not line.shouldHide then
                    for slot=line.itemIndexOffset+1,line.itemIndexOffset+line.numSpellBookItems do
                        local item = C_SpellBook.GetSpellBookItemInfo(slot,bank)
                        if item and item.itemType == Enum.SpellBookItemType.Spell then
                            AddSpell(candidates,seen,item.spellID)
                        end
                    end
                end
            end
        end
        -- ponytail: search the spellbook and saved rules, not millions of global spell IDs.
        -- Add a curated spell database only if cross-class partial-name search is needed.
        for _,rule in ipairs(FX.db.rules) do AddSpell(candidates,seen,rule.spellID) end
    end
    local function Highlight(index)
        popup.selected = index
        for i,row in ipairs(popup.rows) do
            W.ApplyBackdrop(row,i == index and C.bg.selected or C.bg.main,C.border.separator)
        end
    end
    local function Choose(index)
        local spell = popup.matches[index]
        if not popup:IsShown() or not spell then return false end
        popup:Hide()
        field:SetValue(spell.id,true)
        FX:ApplyChange("spellID",tostring(spell.id))
        input:ClearFocus()
        return true
    end
    local function Update()
        if FX.updating or not input:HasFocus() or not FX:CanEdit() then popup:Hide(); return end
        local query = input:GetText():match("^%s*(.-)%s*$"):lower()
        if query == "" then popup:Hide(); return end
        local matches, seen = {}, {}
        local exact = FX:ResolveSpell(query)
        if exact then AddSpell(matches,seen,exact) end
        for _,spell in ipairs(candidates) do
            if not seen[spell.id] and (spell.lower:find(query,1,true) or tostring(spell.id):find(query,1,true)) then
                matches[#matches+1] = spell; seen[spell.id] = true
            end
        end
        table.sort(matches,function(a,b)
            if a.id == exact or b.id == exact then return a.id == exact and b.id ~= exact end
            local ap, bp = a.lower:sub(1,#query) == query, b.lower:sub(1,#query) == query
            if ap ~= bp then return ap end
            if a.name == b.name then return a.id < b.id end
            return a.name < b.name
        end)
        popup.matches = matches
        local count = math.min(8,#matches)
        for i=1,count do
            local row = popup.rows[i]
            if not row then
                row = CreateFrame("Button",nil,popup,"BackdropTemplate")
                row:SetSize(304,38); row:SetPoint("TOPLEFT",8,-8-(i-1)*40)
                -- [STYLE] Rounded once; Highlight's later ApplyBackdrop calls only recolour it.
                W.ApplyBackdrop(row,C.bg.main,C.border.separator,R.control)
                row.icon = row:CreateTexture(nil,"ARTWORK")
                row.icon:SetSize(28,28); row.icon:SetPoint("LEFT",5,0)
                row.name = Label(row,"",41,4,12,C.text.highlight)
                row.name:SetWidth(255); row.name:SetWordWrap(false)
                row.id = Label(row,"",41,21,SMALL,C.text.dim)
                row:SetScript("OnEnter",function() Highlight(i) end)
                row:SetScript("OnMouseDown",function(_,button) if button == "LeftButton" then Choose(i) end end)
                popup.rows[i] = row
            end
            local spell = matches[i]
            row.icon:SetTexture(spell.icon); row.name:SetText(spell.name); row.id:SetText("ID " .. spell.id)
            row:Show()
        end
        for i=count+1,#popup.rows do popup.rows[i]:Hide() end
        popup.hint:ClearAllPoints(); popup.hint:SetPoint("TOPLEFT",8,-8-count*40)
        popup.hint:SetText(count == 0 and "검색 결과 없음 · 정확한 주문 ID를 입력하세요."
            or (#matches > 8 and "상위 8개 · 이름을 더 입력해 좁혀보세요." or "↑↓ 선택 · Enter / Tab 적용"))
        popup:SetHeight(count*40+32)
        Highlight(count > 0 and 1 or nil)
        W.CloseDropdowns(); FX:HideHover(); popup:Show()
    end
    input:HookScript("OnEditFocusGained",function() Collect(); Update() end)
    input:HookScript("OnTextChanged",function(_,userInput) if userInput then Update() else popup:Hide() end end)
    local enter, lost, escape = input:GetScript("OnEnterPressed"), input:GetScript("OnEditFocusLost"), input:GetScript("OnEscapePressed")
    input:SetScript("OnEnterPressed",function(self) if not Choose(popup.selected) then enter(self) end end)
    input:SetScript("OnTabPressed",function(self) if not Choose(popup.selected) then enter(self) end end)
    input:SetScript("OnEscapePressed",function(self) popup:Hide(); escape(self) end)
    input:SetAltArrowKeyMode(false)
    input:SetScript("OnArrowPressed",function(_,key)
        if not popup:IsShown() or not popup.selected or (key ~= "UP" and key ~= "DOWN") then return end
        Highlight((popup.selected-1+(key == "DOWN" and 1 or -1))%math.min(8,#popup.matches)+1)
    end)
    input:SetScript("OnEditFocusLost",function(self)
        -- A suggestion click may move focus before its mouse-down handler runs.
        if popup:IsShown() and not FX.flushing then
            for i,row in ipairs(popup.rows) do
                if row:IsShown() and row:IsMouseOver() then Choose(i); break end
            end
        end
        popup:Hide(); lost(self)
    end)
    input:HookScript("OnHide",function() popup:Hide() end)
end

function FX:CreateTitleBar(parent, label, opts)
    local title = SL.CreateTitleBar(parent,"FX","DDingUI " .. (label or "FX"),self.version,opts)
    title:SetHeight(42)
    title:EnableMouse(true); title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart",function() parent:StartMoving() end)
    title:SetScript("OnDragStop",function() parent:StopMovingOrSizing() end)
    return title
end

function FX:RefreshStatus()
    if not self.window then return end
    self.window.listHeading:SetText((self.specName and self.specName .. " · " or "") .. "스킬 목록")
    if not self:CanEdit() then self:Message("전투·제한 상태가 끝나면 설정을 변경할 수 있습니다.")
    elseif self.soundPending then self:Message("버프 효과음 등록 대기 중 · 제한 해제 시 다시 등록합니다.")
    elseif self.draft and self.draft.trigger == "AURA" then
        self:Message("자동 적용 · 공개된 버프만 모션 재생 / 제한된 버프는 효과음 지원")
    elseif not self.draft or not self.draft.spellID then self:Message("스킬 이름 또는 ID를 입력하면 목록에 추가됩니다.")
    else self:Message("변경사항이 자동 적용됩니다. 입력은 Enter 또는 다른 곳을 클릭하여 완료하세요.") end
end

function FX:FlushInputs(except)
    if self.flushing or not self.window then return end
    self.flushing = true
    for _, input in ipairs(self.window.inputs) do
        if input ~= except and input:HasFocus() then input:ClearFocus() end
    end
    self.flushing = false
end

function FX:RefreshControls()
    local w, r = self.window, self.draft
    w.spell.suggestions:Hide()
    self.updating = true
    w.spell:SetValue(r.spellID or "", true)
    local aura = r.trigger == "AURA"
    w.mode:SetValue(aura and "AURA" or "SPELL", true)
    w.trigger:SetOptions(aura and {{text=triggers.AURA,value="AURA"}} or {
        {text=triggers.SUCCESS,value="SUCCESS"},{text=triggers.START,value="START"}
    }, r.trigger)
    self:RefreshSounds()
    self.updating = false
end

function FX:ApplyChange(key, value)
    if self.updating or not self.draft then return end
    self:FlushInputs(key == "spellID" and self.window.spell.editBox)
    local candidate = {}
    for k, v in pairs(self.draft) do candidate[k] = v end
    local err
    if key == "spellID" then
        value = self:ResolveSpell(value)
        if not value then err = "스킬 이름을 확인하거나 정확한 주문 ID를 입력하세요." end
    end
    if not self:CanEdit() then err = "전투·제한 상태가 끝나면 설정을 변경할 수 있습니다." end
    if not err then
        candidate[key] = value
        if candidate.spellID then
            local index
            index, err = self:SaveRule(self.selected, candidate)
            if index then self.selected = index; self.draft = self.db.rules[index] end
        else self.draft = candidate end
    end
    self:RefreshControls(); self:RefreshList(); self:RefreshPresets(); self:RefreshStatus()
    if err then self:Message(err) end
end

function FX:SelectRule(index)
    self:FlushInputs()
    self:HideHover()
    -- A new selection (or a fresh "+ 스킬 추가" draft) is a page change for the detail area.
    local changed = index ~= self.selected or not index
    self.selected = index
    local source = index and self.db.rules[index]
    self.draft = self:NormalizeRule(source or {spellID=1,trigger="SUCCESS"})
    if not source then self.draft.spellID = nil end
    self:RefreshControls(); self:RefreshList(); self:RefreshPresets(); self:RefreshStatus()
    local w = self.window
    if changed and w and w.detailRows and w:IsVisible() then
        -- [STYLE] Finish any running stagger first so its offset never becomes the new base.
        for _, row in ipairs(w.detailRows) do Motion.Stop(row,"staggerIn",true) end
        Motion.StaggerIn(w.detailRows,{step=.03,offset=4})
    end
end

function FX:RemoveListRule(index)
    self:FlushInputs()
    local ok, err = self:DeleteRule(index)
    if not ok then self:Message(err); return end
    local selected = self.selected
    if selected == index then selected = #self.db.rules > 0 and math.min(index, #self.db.rules) or nil
    elseif selected and selected > index then selected = selected - 1 end
    self:SelectRule(selected)
end

function FX:RefreshList()
    if not self.window or not self.db then return end
    local w, shown, selectedRow = self.window, 0, nil
    local query = w.search:GetText():lower()
    for index, rule in ipairs(self.db.rules) do
        local name, icon = self:SpellName(rule.spellID)
        if (name .. " " .. rule.spellID):lower():find(query, 1, true) then
            shown = shown + 1
            local row = w.rows[shown]
            if not row then
                row = CreateFrame("Button", nil, w.listChild, "BackdropTemplate")
                row:SetSize(212, 52)
                row.bg = RowBackground(row)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(28,28); row.icon:SetPoint("LEFT", 8, 0)
                row.text = Label(row, "", 44, 10, 12)
                row.text:SetWidth(138); row.text:SetWordWrap(false)
                row.detail = Label(row, "", 44, 30, SMALL, C.text.dim)
                row.detail:SetWidth(138); row.detail:SetWordWrap(false)
                row.delete = CreateFrame("Button", nil, row)
                row.delete:SetSize(24,42); row.delete:SetPoint("RIGHT", -2, 0)
                row.delete.label = W.MakeFont(row.delete,12,C.text.dim,"X")
                row.delete.label:SetPoint("CENTER")
                row.delete:SetScript("OnClick", function() FX:RemoveListRule(row.index) end)
                row.delete:SetScript("OnEnter", function(self) self.label:SetTextColor(unpack(C.status.error)) end)
                row.delete:SetScript("OnLeave", function(self) self.label:SetTextColor(unpack(C.text.dim)) end)
                W.SetTooltip(row.delete, "이 스킬 삭제")
                row:SetScript("OnClick", function(self) FX:SelectRule(self.index) end)
                -- [STYLE] 0.09s rounded row hover; the selected row shows the pill underneath.
                Motion.RowHover(row,{bg=row.bg,label=row.text,normal=ROW_CLEAR,hover=C.bg.hover,
                    isActive=function(self) return self.index == FX.selected end})
                w.rows[shown] = row
            end
            row.index = index
            row:SetPoint("TOPLEFT", 0, -(shown-1)*56)
            row.icon:SetTexture(not FX.IsSecret(icon) and icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.text:SetText(name)
            row.detail:SetText(triggers[rule.trigger] .. (rule.enabled and "" or " · 꺼짐"))
            W.Tint(row.bg,RowColor(row,index == self.selected,ROW_CLEAR,ROW_CLEAR))
            if index == self.selected then selectedRow = row end
            row:Show()
        end
    end
    for i=shown+1,#w.rows do w.rows[i]:Hide() end
    w.add:SetPoint("TOPLEFT", 0, -shown*56)
    w.listChild:SetHeight((shown+1)*56)
    w.list:SetVerticalScroll(math.min(w.list:GetVerticalScroll(),w.list:GetVerticalScrollRange()))
    -- [STYLE] One rounded accent pill slides (0.18s) to the new selection instead of per-row markers.
    if selectedRow then
        w.indicator:MoveTo(selectedRow,w.indicatorIndex ~= self.selected)
    else w.indicator:HideIndicator() end
    w.indicatorIndex = selectedRow and self.selected or nil
end

function FX:RefreshSounds()
    if not self.window or not self.draft then return end
    local options, names = {{text="없음",value=""}}, {}
    for name in pairs(self.LSM:HashTable("sound")) do if name ~= "None" then names[#names+1] = name end end
    table.sort(names)
    for _, name in ipairs(names) do options[#options+1] = {text=name,value=name} end
    if self.draft.sound ~= "" and not self.LSM:Fetch("sound", self.draft.sound, true) then
        options[#options+1] = {text="[미등록] " .. self.draft.sound, value=self.draft.sound}
    end
    self.window.sound:SetOptions(options, self.draft.sound)
end

function FX:HideHover()
    if self.window and self.window.hover then self.window.hover:Hide() end
end

function FX:ShowHover(card)
    self:HideHover()
    local preset = self.presets[card.key]
    if not preset then return end
    local hover = self.window.hover
    hover:ClearAllPoints(); hover:SetPoint("TOPLEFT",card,"TOPRIGHT",8,0)
    hover.name:SetText(preset.name)
    hover:Show()
    hover.player:SetAlpha(self.draft.opacity / 100)
    local played = hover.player:Play(preset, self.draft.speed, true)
    hover.error:SetShown(not played)
end

function FX:RefreshPresets()
    local w = self.window
    if not w then return end
    local keys = {""}
    for key in pairs(self.presets) do if key ~= "" then keys[#keys+1] = key end end
    table.sort(keys, function(a,b)
        if a == "" then return b ~= "" end
        if b == "" then return false end
        if self.presets[a].name == self.presets[b].name then return a < b end
        return self.presets[a].name < self.presets[b].name
    end)
    for index, key in ipairs(keys) do
        local card = w.cards[index]
        if not card then
            card = CreateFrame("Button", nil, w.galleryChild, "BackdropTemplate")
            card:SetSize(164,112)
            -- [STYLE] The card itself is the rounded (radius 8) surface; selection = rounded accent border.
            card.bg = RowBackground(card,C.bg.input,C.border.default)
            card.image = card:CreateTexture(nil, "ARTWORK")
            card.image:SetSize(80,80); card.image:SetPoint("TOP",0,-4)
            card.name = Label(card,"",10,90,12)
            card.name:SetWidth(144); card.name:SetWordWrap(false)
            card.none = W.MakeFont(card,22,C.text.disabled,"—"); card.none:SetPoint("TOP",0,-28)
            card:SetScript("OnClick",function(self) FX:ApplyChange("preset",self.key) end)
            card:SetScript("OnEnter",function(self) FX:ShowHover(self) end)
            card:SetScript("OnLeave",function() FX:HideHover() end)
            card:SetScript("OnHide",function() FX:HideHover() end)
            -- [STYLE] Same 0.09s hover as list rows; grid cards keep the accent border as selection.
            Motion.RowHover(card,{bg=card.bg,normal=C.bg.input,hover=C.bg.hover,nudge=0,
                isActive=function(self) return FX.draft and FX.draft.preset == self.key end})
            w.cards[index] = card
        end
        card.key = key
        card:SetPoint("TOPLEFT",((index-1)%4)*176,-math.floor((index-1)/4)*124)
        local preset = self.presets[key]
        card.name:SetText(preset and preset.name or "모션 없음")
        card.none:SetShown(not preset)
        if preset then
            local index = math.floor(preset.frames / 2)
            local capacity = preset.columns * preset.rows
            local page, cell = math.floor(index / capacity) + 1, index % capacity
            local col, row = cell % preset.columns, math.floor(cell / preset.columns)
            local path = page == 1 and preset.path or preset.path:sub(1, -5) .. "_" .. page .. ".tga"
            card.image:SetTexture(path)
            card.image:SetTexCoord(col / preset.columns, (col + 1) / preset.columns,
                row / preset.rows, (row + 1) / preset.rows)
        end
        card.image:SetShown(preset ~= nil)
        W.Tint(card.bg,RowColor(card,self.draft.preset == key,C.bg.input))
        card:SetBackdropBorderColor(unpack(self.draft.preset == key and accent or C.border.default))
        card:Show()
    end
    for i=#keys+1,#w.cards do w.cards[i]:Hide() end
    w.galleryChild:SetHeight(math.ceil(#keys/4)*124)
    w.galleryEmpty:SetShown(#keys == 1)
end

function FX:StopTest()
    self.testing = nil
    self.events:SetScript("OnUpdate",nil)
    if self.testRule and self.active[self.testRule] then self.active[self.testRule]:Stop() end
    self:StopPreviewSound()
end

function FX:TestEffect()
    self:FlushInputs()
    if not self:CanEdit() then self:RefreshStatus(); return end
    self:HideHover()
    self.testRule = self.testRule or {}
    for k,v in pairs(self.draft) do self.testRule[k] = v end
    self.window:HideImmediately()
    self.testing = true
    self:FireRule(self.testRule,true)
    self:PreviewSoundFile(self.LSM:Fetch("sound",self.draft.sound,true))
    self.events:SetScript("OnUpdate",function()
        if not FX:CanEdit() then FX:StopTest(); return end
        local player = FX.active[FX.testRule]
        if player and player.playing then return end
        if FX.previewSoundHandle and C_Sound.IsPlaying(FX.previewSoundHandle) then return end
        FX:StopTest()
        FX.window:Show()
    end)
end

function FX:CreateUI()
    if self.window then return self.window end
    local w = CreateFrame("Frame","DDingUI_FXWindow",UIParent,"BackdropTemplate")
    self.window = w
    w:SetSize(1000,720); w:SetPoint("CENTER")
    -- Small screens keep the fitted size as the 100% base of the user GUI scale.
    local fit = math.min(1,(UIParent:GetWidth()-32)/1000,(UIParent:GetHeight()-32)/720)
    w:SetScale(fit)
    w:SetFrameStrata("DIALOG")
    if SL and SL.AllowOffscreen then SL.AllowOffscreen(w) else w:SetClampedToScreen(true) end -- [STYLE] 화면 밖으로 걸쳐 두기
    w:SetMovable(true); w:EnableMouse(true)
    -- [STYLE] 시안 7: rounded window before the title bar, so StyleLib drops the square bar fill.
    W.ApplyBackdrop(w,C.bg.main,C.border.default,R.window)
    -- [STYLE] Series title-bar "GUI 크기" left of close: drag previews, release/wheel saves.
    local title = self:CreateTitleBar(w,nil,{scale={
        get=function() return FX.db.guiScale end,
        set=function(value) FX.db.guiScale = value end,
        target={SetBaseScale=function(_,value) w:SetBaseScale(value*fit) end},
    -- [STYLE] C12: series title-bar "편집 모드"/"편집 중" button (close · edit · GUI scale).
    },editMode={onClick=function() FX:ToggleEditMode() end,
        isActive=function() return FX.editor and FX.editor:IsShown() and not FX.editor.closing or false end}})
    w.titleBar = title
    w.editMode = title.editButton
    W.SetTooltip(w.editMode,"위치·크기·투명도·재생 속도를 실제 화면에서 조절합니다.")
    w.search = W.CreateSearchBox(title,200,{placeholder="스킬 이름 / ID 검색"})
    w.search:SetPoint("RIGHT",title.scaleControl,"LEFT",-12,0)
    w.search:SetOnTextChanged(function() FX:RefreshList() end)
    table.insert(UISpecialFrames,"DDingUI_FXWindow")

    -- [STYLE] 시안 7: two rounded cards 8px inside the window's left/right/bottom edges, 8px apart,
    -- directly under the title bar, so no square fill reaches the rounded window corners.
    local sidebar = Panel(w,8,44,232,668,C.bg.sidebar)
    w.sidebar = sidebar
    w.listHeading = Label(sidebar,"스킬 목록",14,18,14,C.text.highlight)
    w.listHeading:SetWidth(204); w.listHeading:SetWordWrap(false)
    Label(sidebar,"스킬을 선택해 효과를 설정하세요.",14,41,SMALL,C.text.dim)
    w.list,w.listChild = Scroll(sidebar,10,70,216,584)
    w.rows = {}
    -- [STYLE] Selection pill (accent α0.18, radius 8) drawn under the transparent rows.
    w.indicator = Motion.CreateIndicator(w.listChild,212,52,{accent[1],accent[2],accent[3],.18},
        {radius=R.row,layer="BACKGROUND"})
    w.add = W.CreateButton(w.listChild,"FX","+  스킬 추가",function()
        FX:SelectRule(nil); w.search:SetText(""); w.spell.editBox:SetFocus()
    end,{width=212,height=48})
    W.SetTooltip(w.add,"새 스킬 또는 버프 추가")

    local detail = Panel(w,248,44,744,668,C.bg.titlebar)
    w.detail = detail
    SL.AddWatermark(detail,"FX") -- [STYLE] faint series rings, bottom-right of the detail card
    local content = CreateFrame("Frame",nil,detail)
    content:SetPoint("TOPLEFT",detail,"TOPLEFT",17,-18); content:SetSize(710,626)
    -- [STYLE] Detail rows share content's origin so StaggerIn can fade each visual row.
    w.detailRows = {}
    local function DetailRow()
        local row = CreateFrame("Frame",nil,content)
        row:SetPoint("TOPLEFT",content,"TOPLEFT",0,0); row:SetSize(710,626)
        w.detailRows[#w.detailRows+1] = row
        return row
    end
    local rowSpell, rowTrigger, rowHeader, rowGallery, rowActions = DetailRow(), DetailRow(), DetailRow(), DetailRow(), DetailRow()
    w.spell = Input(rowSpell,"이름 또는 ID",0,0,352,232,"spellID")
    AttachSpellAutocomplete(w.spell)
    w.mode = W.CreateSegmentedControl(rowSpell,"FX","",{{text="스킬",value="SPELL"},{text="버프",value="AURA"}},"SPELL",
        {width=144,onChange=function(value)
            FX:ApplyChange("trigger",value == "AURA" and "AURA" or "SUCCESS")
        end})
    w.mode:SetPoint("TOPLEFT",366,0); w.mode.label:Hide(); w.mode:SetHeight(30)
    w.mode.control:ClearAllPoints(); w.mode.control:SetPoint("TOPLEFT",0,0)
    Label(rowTrigger,"발동 조건",0,50,12,C.text.dim)
    w.trigger = W.CreateDropdown(rowTrigger,"FX","",{},"SUCCESS",{width=336,searchable=false,
        onChange=function(value) FX:ApplyChange("trigger",value) end})
    w.trigger:SetSize(336,28); w.trigger:SetPoint("TOPLEFT",0,-72)
    W.SetTooltip(w.trigger,"스킬: 시전 시작(채널링·강화 포함) / 사용 성공 직후\n버프: 내 캐릭터에게 새로 활성화될 때")
    Label(rowTrigger,"효과음",364,50,12,C.text.dim)
    w.sound = W.CreateDropdown(rowTrigger,"FX","",{},"",{width=336,mediaType="sound",searchable=true,
        placeholder="효과음 검색",onChange=function(value) FX:ApplyChange("sound",value) end})
    w.sound:SetSize(336,28); w.sound:SetPoint("TOPLEFT",364,-72)

    local header = W.CreateSectionHeader(rowHeader,"FX","모션 프리셋",{width=700})
    header:SetPoint("TOPLEFT",0,-125); header:SetSize(700,32)
    Label(rowHeader,"마우스를 올리면 움직이는 미리보기",402,132,SMALL,C.text.dim)
    w.gallery,w.galleryChild = Scroll(rowGallery,0,170,704,380)
    w.cards = {}
    w.galleryEmpty = Label(rowGallery,"아직 준비된 모션이 없습니다.",196,217,12,C.text.dim)
    w.galleryEmpty:SetWidth(450)
    local hover = Panel(w,0,0,272,302,C.bg.main,C.border.default)
    w.hover = hover
    hover:SetFrameStrata("TOOLTIP"); hover:SetClampedToScreen(true); hover:EnableMouse(false)
    hover.name = Label(hover,"",12,12,13,C.text.highlight)
    hover.name:SetWidth(248); hover.name:SetWordWrap(false)
    hover.player = self:CreatePlayer(hover)
    hover.player:SetSize(248,248); hover.player:SetPoint("TOPLEFT",12,-40)
    hover.error = Label(hover,"TGA 파일을 불러올 수 없습니다.",12,144,12,C.text.dim)
    hover.error:SetWidth(248)
    hover:SetScript("OnHide",function() hover.player:Stop() end)
    hover:Hide()

    w.inputs = {w.spell.editBox}
    -- The edit-mode entry moved to the title bar (C12); the test button takes the full action row.
    w.test = W.CreateButton(rowActions,"FX","실제 화면 테스트",function() FX:TestEffect() end,{width=700,height=32})
    w.test:SetPoint("TOPLEFT",0,-574)
    W.SetTooltip(w.test,"모션과 효과음을 한 번 재생한 뒤 설정창으로 돌아옵니다.")
    w.status = Label(detail,"",17,638,SMALL,C.text.dim); w.status:SetWidth(710); w.status:SetHeight(28)
    w:SetScript("OnHide",function()
        FX:FlushInputs(); W.CloseDropdowns(); FX:HideHover(); FX:StopTest()
    end)
    w:SetScript("OnShow",function()
        if FX.testing then FX:StopTest() end
        FX:RefreshStatus()
    end)
    self:SelectRule(#self.db.rules > 0 and 1 or nil)
    w:Hide()
    SL.Motion.BindPanel(w)
    w:SetBaseScale(self.db.guiScale*fit)
    w:Show()
    return w
end

function FX:ToggleUI()
    if not self.db then return end
    if self.editor and self.editor:IsShown() then self:CloseEditMode(true); return end
    if not self.window then self:CreateUI(); return end
    self.window:SetShown(not self.window:IsShown() or self.window._ddslPanelClosing)
end

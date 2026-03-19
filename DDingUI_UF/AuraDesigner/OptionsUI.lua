local addonName, ns = ...

-- ============================================================
-- AURA DESIGNER - OPTIONS UI BUILDER
-- Frame Preview, Drag System, Tab Panel, Effect Cards, Spell Picker
-- ============================================================

local pairs, ipairs, type = pairs, ipairs, type
local wipe = wipe
local tinsert = table.insert
local tremove = table.remove
local max, min = math.max, math.min
local sort = table.sort

local Widgets = ns.Widgets

-- Wait for Options.lua data module
local O  -- = ns.AuraDesignerOptions (set in BuildPage)

-- ============================================================
-- UI STATE
-- ============================================================
local activeTab = "effects"
local activeFilter = "all"
local expandedCards = {}
local expandedGroups = {}
local spellPickerActive = false
local spellPickerType = nil
local spellPickerMode = "placed"

-- Frame references (populated during build)
local mainFrame, leftPanel, rightPanel
local framePreview, dragHintText
local tabBar, tabButtons, tabContentFrame, tabScrollFrame
local spellPickerView
local anchorDots = {}
local placedIndicators = {}

-- ============================================================
-- DRAG STATE
-- ============================================================
local dragState = {
    isDragging = false, auraName = nil, auraInfo = nil,
    specKey = nil, dropAnchor = nil, moveIndicatorID = nil, indicatorType = nil,
}
local dragGhost, dragUpdateFrame

-- Forward declarations
local SwitchTab, ShowSpellPicker, HideSpellPicker
local BuildEffectsTab, BuildGlobalTab, BuildLayoutGroupsTab
local PopulateSpellGrid, CreateEffectCard
local RefreshPlacedIndicators, RefreshPreviewEffects, EndDrag

-- ============================================================
-- REFRESH ALL
-- ============================================================
local function ADRefreshAll()
    local Engine = ns.AuraDesigner and ns.AuraDesigner.Engine
    if Engine then Engine:UpdateAllGroupFrames() end
end

local function RefreshPage()
    if not mainFrame then return end
    -- Re-switch to current tab to rebuild content
    if SwitchTab then SwitchTab(activeTab) end
    if RefreshPlacedIndicators then RefreshPlacedIndicators() end
    if RefreshPreviewEffects then RefreshPreviewEffects() end
end

-- ============================================================
-- DRAG GHOST
-- ============================================================
local function CreateDragGhost()
    if dragGhost then return dragGhost end
    dragGhost = CreateFrame("Frame", "DDingUIADDragGhost", UIParent, "BackdropTemplate")
    dragGhost:SetSize(36, 36)
    dragGhost:SetFrameStrata("TOOLTIP")
    dragGhost:SetFrameLevel(1000)
    dragGhost:EnableMouse(false)
    dragGhost:Hide()
    Widgets:StylizeFrame(dragGhost)

    local icon = dragGhost:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 3, -3)
    icon:SetPoint("BOTTOMRIGHT", -3, 3)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    dragGhost.icon = icon

    local label = dragGhost:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
    label:SetPoint("TOP", dragGhost, "BOTTOM", 0, -2)
    dragGhost.label = label

    return dragGhost
end

-- ============================================================
-- START/END DRAG
-- ============================================================
local function StartDrag(auraName, auraInfo, specKey, indicatorType)
    if dragState.isDragging then return end
    dragState.isDragging = true
    dragState.auraName = auraName
    dragState.auraInfo = auraInfo
    dragState.specKey = specKey
    dragState.dropAnchor = nil
    dragState.indicatorType = indicatorType or "icon"

    local ghost = CreateDragGhost()
    local iconTex = O.GetAuraIcon(specKey, auraName)
    if iconTex then ghost.icon:SetTexture(iconTex)
    else ghost.icon:SetColorTexture(0.3, 0.3, 0.3, 1) end
    ghost.label:SetText(auraInfo.display or auraName)
    ghost:Show()

    if dragHintText then
        dragHintText:SetText(auraInfo.display .. " 배치: 앵커에 드롭하세요")
    end

    for _, dotFrame in pairs(anchorDots) do
        dotFrame:Show()
        dotFrame.dot:SetSize(10, 10)
        dotFrame.dot:SetColorTexture(0.45, 0.45, 0.95, 0.5)
    end

    if not dragUpdateFrame then dragUpdateFrame = CreateFrame("Frame") end
    dragUpdateFrame:SetScript("OnUpdate", function()
        if not dragState.isDragging then dragUpdateFrame:Hide(); return end
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        ghost:ClearAllPoints()
        ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x/scale + 10, y/scale - 10)
        if not IsMouseButtonDown("LeftButton") then EndDrag() end
    end)
    dragUpdateFrame:Show()
end

local function StartMoveDrag(auraName, indicatorID, specKey)
    if dragState.isDragging then return end
    dragState.isDragging = true
    dragState.auraName = auraName
    dragState.moveIndicatorID = indicatorID
    dragState.specKey = specKey
    dragState.dropAnchor = nil

    local ghost = CreateDragGhost()
    local iconTex = O.GetAuraIcon(specKey, auraName)
    if iconTex then ghost.icon:SetTexture(iconTex)
    else ghost.icon:SetColorTexture(0.3, 0.3, 0.3, 1) end
    ghost.label:SetText(auraName)
    ghost:Show()

    for _, dotFrame in pairs(anchorDots) do
        dotFrame:Show()
        dotFrame.dot:SetSize(10, 10)
        dotFrame.dot:SetColorTexture(0.45, 0.45, 0.95, 0.5)
    end

    if not dragUpdateFrame then dragUpdateFrame = CreateFrame("Frame") end
    dragUpdateFrame:SetScript("OnUpdate", function()
        if not dragState.isDragging then dragUpdateFrame:Hide(); return end
        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        ghost:ClearAllPoints()
        ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x/scale + 10, y/scale - 10)
        if not IsMouseButtonDown("LeftButton") then EndDrag() end
    end)
    dragUpdateFrame:Show()
end

EndDrag = function()
    if not dragState.isDragging then return end
    local auraName = dragState.auraName
    local dropAnchor = dragState.dropAnchor
    local moveID = dragState.moveIndicatorID
    local indicatorType = dragState.indicatorType or "icon"

    dragState.isDragging = false
    dragState.auraName = nil
    dragState.auraInfo = nil
    dragState.specKey = nil
    dragState.dropAnchor = nil
    dragState.moveIndicatorID = nil
    dragState.indicatorType = nil

    if dragGhost then dragGhost:Hide() end
    if dragUpdateFrame then dragUpdateFrame:Hide(); dragUpdateFrame:SetScript("OnUpdate", nil) end
    if dragHintText then dragHintText:SetText("") end

    for _, dotFrame in pairs(anchorDots) do
        dotFrame:Hide()
        dotFrame.dot:SetSize(6, 6)
        dotFrame.dot:SetColorTexture(0.45, 0.45, 0.95, 0.3)
    end

    if auraName and dropAnchor then
        if moveID then
            local inst = O.GetIndicatorByID(auraName, moveID)
            if inst then inst.anchor = dropAnchor; inst.offsetX = 0; inst.offsetY = 0 end
        else
            local inst = O.CreateIndicatorInstance(auraName, indicatorType)
            if inst then inst.anchor = dropAnchor end
        end
    end

    RefreshPage()
    ADRefreshAll()
end

-- ============================================================
-- FRAME PREVIEW
-- ============================================================
local function CreateFramePreview(parent, yOffset, rightInset)
    local partyDB = ns.db and ns.db.party or {}
    local FRAME_W = partyDB.frameWidth or 125
    local FRAME_H = partyDB.frameHeight or 64

    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, yOffset)
    container:SetPoint("RIGHT", parent, "RIGHT", -(rightInset or 0), 0)
    container:SetHeight(max(FRAME_H * 1.8, 160))
    Widgets:StylizeFrame(container)

    local previewLabel = container:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
    previewLabel:SetPoint("TOPLEFT", 8, -4)
    previewLabel:SetText("프레임 프리뷰")

    -- Mock frame
    local mockFrame = CreateFrame("Frame", nil, container, "BackdropTemplate")
    mockFrame:SetSize(FRAME_W, FRAME_H)
    mockFrame:SetPoint("CENTER", container, "CENTER", 0, -4)
    Widgets:StylizeFrame(mockFrame)
    container.mockFrame = mockFrame

    -- Health bar
    local healthFill = mockFrame:CreateTexture(nil, "ARTWORK")
    healthFill:SetPoint("TOPLEFT", 1, -1)
    healthFill:SetPoint("BOTTOMLEFT", 1, 1)
    healthFill:SetWidth(FRAME_W * 0.72)
    healthFill:SetColorTexture(0.18, 0.80, 0.44, 0.85)
    container.healthFill = healthFill

    -- Name text
    local nameText = mockFrame:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
    nameText:SetPoint("TOP", mockFrame, "TOP", 0, -10)
    nameText:SetText("DDingUI")
    nameText:SetTextColor(0.18, 0.80, 0.44, 1)
    container.nameText = nameText

    -- HP text
    local hpText = mockFrame:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
    hpText:SetPoint("CENTER", mockFrame, "CENTER", 0, 4)
    hpText:SetText("72%")
    container.hpText = hpText

    -- Border overlay
    container.borderOverlay = CreateFrame("Frame", nil, mockFrame)
    container.borderOverlay:SetAllPoints()
    container.borderOverlay:SetFrameLevel(mockFrame:GetFrameLevel() + 5)
    container.borderOverlay:Hide()

    -- 9 anchor dots
    wipe(anchorDots)
    for anchorName, pos in pairs(O.ANCHOR_POSITIONS) do
        local dotFrame = CreateFrame("Frame", nil, mockFrame)
        dotFrame:SetSize(20, 20)
        dotFrame:SetFrameLevel(mockFrame:GetFrameLevel() + 10)
        dotFrame:SetPoint(anchorName, mockFrame, anchorName, 0, 0)

        local dot = dotFrame:CreateTexture(nil, "OVERLAY")
        dot:SetSize(6, 6)
        dot:SetPoint("CENTER", 0, 0)
        dot:SetColorTexture(0.45, 0.45, 0.95, 0.3)
        dotFrame.dot = dot

        local hoverBtn = CreateFrame("Button", nil, dotFrame)
        hoverBtn:SetAllPoints()
        local capturedAnchor = anchorName
        hoverBtn:SetScript("OnEnter", function()
            if dragState.isDragging then
                dot:SetSize(14, 14)
                dot:SetColorTexture(0.3, 0.8, 0.3, 0.9)
                dragState.dropAnchor = capturedAnchor
            else
                dot:SetSize(10, 10)
                dot:SetColorTexture(0.45, 0.45, 0.95, 0.7)
            end
        end)
        hoverBtn:SetScript("OnLeave", function()
            if dragState.isDragging then
                dot:SetSize(10, 10)
                dot:SetColorTexture(0.45, 0.45, 0.95, 0.5)
                dragState.dropAnchor = nil
            else
                dot:SetSize(6, 6)
                dot:SetColorTexture(0.45, 0.45, 0.95, 0.3)
            end
        end)

        dotFrame.anchorName = anchorName
        dotFrame:Hide()
        anchorDots[anchorName] = dotFrame
    end

    -- Drag hint text
    dragHintText = container:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
    dragHintText:SetPoint("TOP", mockFrame, "BOTTOM", 0, -6)
    dragHintText:SetText("")

    -- Preview Scale slider
    local scaleSlider = Widgets:CreateSlider("프리뷰 스케일", container, 0.5, 2.0, 130, 0.1,
        function(v) mockFrame:SetScale(v) end,
        function(v) mockFrame:SetScale(v) end)
    scaleSlider:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -8, 6)
    scaleSlider:SetValue(1.0)

    -- Instructions
    local instrText = container:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
    instrText:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 8, 6)
    instrText:SetJustifyH("LEFT")
    instrText:SetText("좌클릭=설정 | 드래그=이동 | 우클릭=삭제")

    return container
end

-- ============================================================
-- REFRESH PLACED INDICATORS (on preview)
-- ============================================================
local function ClearPlacedIndicators()
    for _, ind in ipairs(placedIndicators) do ind:Hide() end
    wipe(placedIndicators)
end

-- ============================================================
-- [FIX] LIVE PREVIEW TIMER — 쿨다운 순환 애니메이션
-- 15초 주기로 mock 데이터 갱신 → 쿨다운 스와이프 실시간 반복
-- ============================================================
local PREVIEW_CYCLE_DURATION = 15  -- 순환 주기 (초)
local previewTimerFrame = CreateFrame("Frame")
local previewTimerElapsed = 0
previewTimerFrame:Hide()

previewTimerFrame:SetScript("OnUpdate", function(self, elapsed)
    previewTimerElapsed = previewTimerElapsed + elapsed
    if previewTimerElapsed >= PREVIEW_CYCLE_DURATION then
        previewTimerElapsed = 0
        -- 프리뷰 인디케이터 쿨다운 갱신 (순환)
        if framePreview and framePreview:IsVisible() and RefreshPlacedIndicators then
            RefreshPlacedIndicators()
        end
    end
end)

-- 프리뷰 라이브 타이머 시작/중지
local function StartPreviewTimer()
    previewTimerElapsed = 0
    previewTimerFrame:Show()
end

local function StopPreviewTimer()
    previewTimerFrame:Hide()
    previewTimerElapsed = 0
end

RefreshPlacedIndicators = function()
    ClearPlacedIndicators()
    if not framePreview or not framePreview.mockFrame then return end
    local mockFrame = framePreview.mockFrame
    local spec = O.ResolveSpec()
    if not spec then return end

    local AD = ns.AuraDesigner
    local Indicators = AD and AD.Indicators
    local adDB = O.GetAuraDesignerDB()
    if not Indicators or not adDB then return end

    local trackable = AD.TrackableAuras and AD.TrackableAuras[spec]
    if not trackable then return end
    local infoLookup = {}
    for _, info in ipairs(trackable) do infoLookup[info.name] = info end

    for auraName, auraCfg in pairs(O.GetSpecAuras(spec)) do
        local info = infoLookup[auraName]
        if type(auraCfg) == "table" and info and auraCfg.indicators then
            for _, indicator in ipairs(auraCfg.indicators) do
                local instanceKey = auraName .. "#" .. indicator.id
                local capturedAura = auraName
                local capturedID = indicator.id

                if indicator.type == "icon" then
                    local tex = O.GetAuraIcon(spec, auraName)
                    local mockData = { spellId = 0, icon = tex, duration = PREVIEW_CYCLE_DURATION, expirationTime = GetTime() + PREVIEW_CYCLE_DURATION, stacks = 3 }
                    Indicators:ApplyIcon(mockFrame, indicator, mockData, adDB.defaults, instanceKey)
                    local iconMap = mockFrame.dfAD_icons or mockFrame.ddAD_icons
                    local icon = iconMap and iconMap[instanceKey]
                    if icon then
                        icon:EnableMouse(true)
                        icon:SetScript("OnMouseUp", function(_, button)
                            if dragState.isDragging then return end
                            if button == "RightButton" then
                                if not O.GetIndicatorLayoutGroup(capturedAura, capturedID) then
                                    O.RemoveIndicatorInstance(capturedAura, capturedID)
                                    RefreshPage(); ADRefreshAll()
                                end
                            elseif button == "LeftButton" then
                                wipe(expandedCards)
                                expandedCards["placed:" .. capturedAura .. "#" .. capturedID] = true
                                activeTab = "effects"
                                RefreshPage()
                            end
                        end)
                        icon:RegisterForDrag("LeftButton")
                        icon:SetScript("OnDragStart", function()
                            StartMoveDrag(capturedAura, capturedID, spec)
                        end)
                        tinsert(placedIndicators, icon)
                    end
                elseif indicator.type == "square" then
                    local mockData = { spellId = 0, icon = nil, duration = PREVIEW_CYCLE_DURATION, expirationTime = GetTime() + PREVIEW_CYCLE_DURATION, stacks = 3 }
                    Indicators:ApplySquare(mockFrame, indicator, mockData, adDB.defaults, instanceKey)
                    local sqMap = mockFrame.dfAD_squares or mockFrame.ddAD_squares
                    local sq = sqMap and sqMap[instanceKey]
                    if sq then
                        sq:EnableMouse(true)
                        sq:SetScript("OnMouseUp", function(_, button)
                            if dragState.isDragging then return end
                            if button == "RightButton" then
                                if not O.GetIndicatorLayoutGroup(capturedAura, capturedID) then
                                    O.RemoveIndicatorInstance(capturedAura, capturedID)
                                    RefreshPage(); ADRefreshAll()
                                end
                            elseif button == "LeftButton" then
                                wipe(expandedCards)
                                expandedCards["placed:" .. capturedAura .. "#" .. capturedID] = true
                                activeTab = "effects"
                                RefreshPage()
                            end
                        end)
                        sq:RegisterForDrag("LeftButton")
                        sq:SetScript("OnDragStart", function()
                            StartMoveDrag(capturedAura, capturedID, spec)
                        end)
                        tinsert(placedIndicators, sq)
                    end
                elseif indicator.type == "bar" then
                    local mockData = { spellId = 0, icon = nil, duration = PREVIEW_CYCLE_DURATION, expirationTime = GetTime() + PREVIEW_CYCLE_DURATION, stacks = 0 }
                    Indicators:ApplyBar(mockFrame, indicator, mockData, adDB.defaults, instanceKey)
                    local barMap = mockFrame.dfAD_bars or mockFrame.ddAD_bars
                    local bar = barMap and barMap[instanceKey]
                    if bar then
                        bar:EnableMouse(true)
                        bar:SetScript("OnMouseUp", function(_, button)
                            if dragState.isDragging then return end
                            if button == "RightButton" then
                                if not O.GetIndicatorLayoutGroup(capturedAura, capturedID) then
                                    O.RemoveIndicatorInstance(capturedAura, capturedID)
                                    RefreshPage(); ADRefreshAll()
                                end
                            elseif button == "LeftButton" then
                                wipe(expandedCards)
                                expandedCards["placed:" .. capturedAura .. "#" .. capturedID] = true
                                activeTab = "effects"
                                RefreshPage()
                            end
                        end)
                        bar:RegisterForDrag("LeftButton")
                        bar:SetScript("OnDragStart", function()
                            StartMoveDrag(capturedAura, capturedID, spec)
                        end)
                        tinsert(placedIndicators, bar)
                    end
                end
            end
        end
    end
end

-- ============================================================
-- REFRESH PREVIEW EFFECTS (frame-level)
-- ============================================================
RefreshPreviewEffects = function()
    if not framePreview then return end
    -- Reset defaults
    if framePreview.healthFill then framePreview.healthFill:SetVertexColor(0.18, 0.80, 0.44, 0.85) end
    if framePreview.nameText then framePreview.nameText:SetTextColor(0.18, 0.80, 0.44, 1) end
    if framePreview.mockFrame then framePreview.mockFrame:SetAlpha(1) end

    for _, auraCfg in pairs(O.GetSpecAuras()) do
        if type(auraCfg) == "table" then
            if auraCfg.healthbar and framePreview.healthFill then
                local clr = auraCfg.healthbar.color or {r=1,g=1,b=1,a=1}
                framePreview.healthFill:SetVertexColor(clr.r, clr.g, clr.b, clr.a or 1)
            end
            if auraCfg.nametext and framePreview.nameText then
                local clr = auraCfg.nametext.color or {r=1,g=1,b=1,a=1}
                framePreview.nameText:SetTextColor(clr.r, clr.g, clr.b, clr.a or 1)
            end
            if auraCfg.framealpha and framePreview.mockFrame then
                framePreview.mockFrame:SetAlpha(auraCfg.framealpha.alpha or 0.5)
            end
        end
    end
end

-- Set forward reference
ns.AuraDesignerOptions_RefreshPreviewLightweight = function()
    RefreshPlacedIndicators()
    RefreshPreviewEffects()
    ADRefreshAll()
end

-- ============================================================
-- CLEAR TAB CONTENT
-- ============================================================
local function ClearTabContent()
    if not tabContentFrame then return end
    for _, child in ipairs({tabContentFrame:GetChildren()}) do child:Hide(); child:ClearAllPoints() end
    for _, region in ipairs({tabContentFrame:GetRegions()}) do region:Hide() end
end

-- ============================================================
-- HIDE/SHOW SPELL PICKER
-- ============================================================
HideSpellPicker = function()
    if not spellPickerView then return end
    spellPickerActive = false
    spellPickerView:Hide()
    if tabBar then tabBar:Show() end
    if tabScrollFrame then tabScrollFrame:Show() end
end

ShowSpellPicker = function(typeKey, mode)
    if not spellPickerView then return end
    spellPickerActive = true
    spellPickerType = typeKey
    spellPickerMode = mode or "placed"
    if tabBar then tabBar:Hide() end
    if tabScrollFrame then tabScrollFrame:Hide() end

    local label = O.PLACED_TYPE_LABELS[typeKey] or O.FRAME_LEVEL_LABELS[typeKey] or typeKey
    if spellPickerView.title then spellPickerView.title:SetText("스펠 선택: " .. label) end
    PopulateSpellGrid()
    spellPickerView:Show()
end

-- ============================================================
-- SWITCH TAB
-- ============================================================
SwitchTab = function(tabKey)
    activeTab = tabKey
    if spellPickerActive then HideSpellPicker() end

    for key, btn in pairs(tabButtons or {}) do
        if key == tabKey then
            btn:SetBackdropBorderColor(0.3, 0.8, 0.3, 1)
        else
            btn:SetBackdropBorderColor(0, 0, 0, 1)
        end
    end

    ClearTabContent()

    if tabKey == "effects" then BuildEffectsTab()
    elseif tabKey == "layout" then BuildLayoutGroupsTab()
    elseif tabKey == "global" then BuildGlobalTab()
    end

    if tabScrollFrame then tabScrollFrame:SetVerticalScroll(0) end
end

-- ============================================================
-- POPULATE SPELL GRID
-- ============================================================
PopulateSpellGrid = function()
    if not spellPickerView or not spellPickerView.gridFrame then return end
    local grid = spellPickerView.gridFrame
    for _, child in ipairs({grid:GetChildren()}) do child:Hide() end
    for _, region in ipairs({grid:GetRegions()}) do region:Hide() end

    local spec = O.ResolveSpec()
    local AD = ns.AuraDesigner
    local auras = spec and AD and AD.TrackableAuras and AD.TrackableAuras[spec]
    if not auras or #auras == 0 then return end

    -- Separate whitelisted vs secret auras
    local whitelist, secret = {}, {}
    local SecretAuras = AD and AD.SecretAuras
    local secretSet = {}
    if SecretAuras then
        for _, info in ipairs(SecretAuras) do secretSet[info.name or info] = true end
    end
    for _, info in ipairs(auras) do
        if secretSet[info.name] then tinsert(secret, info)
        else tinsert(whitelist, info) end
    end

    -- Check which auras already have placed indicators
    local specAuras = O.GetSpecAuras(spec)
    local function IsAuraPlaced(auraName)
        local cfg = specAuras[auraName]
        if cfg and cfg.indicators and #cfg.indicators > 0 then return true end
        return false
    end

    local CARD_W, CARD_H, GAP = 78, 78, 6
    local gridWidth = grid:GetWidth()
    if gridWidth < 100 then gridWidth = 260 end
    local cols = max(2, math.floor((gridWidth + GAP) / (CARD_W + GAP)))
    local totalY = 0

    -- Determine trigger mode
    local isTriggerMode = spellPickerMode and spellPickerMode:find("trigger:") == 1
    local triggerAuraName, triggerTypeKey
    if isTriggerMode then
        local rest = spellPickerMode:sub(9)
        triggerAuraName, triggerTypeKey = rest:match("^(.+):(.+)$")
    end

    local function BuildSection(sectionAuras, sectionTitle, startY)
        if #sectionAuras == 0 then return startY end

        -- Section header
        local secLabel = grid:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
        secLabel:SetPoint("TOPLEFT", 0, startY)
        secLabel:SetText("|cff88ccff" .. sectionTitle .. "|r (" .. #sectionAuras .. ")")
        startY = startY - 18

        for i, auraInfo in ipairs(sectionAuras) do
            local idx0 = i - 1
            local row = math.floor(idx0 / cols)
            local col = idx0 % cols
            local x = col * (CARD_W + GAP)
            local cy = startY - (row * (CARD_H + GAP))

            local card = CreateFrame("Button", nil, grid, "BackdropTemplate")
            card:SetSize(CARD_W, CARD_H)
            card:SetPoint("TOPLEFT", x, cy)
            Widgets:StylizeFrame(card)

            local iconTex = O.GetAuraIcon(spec, auraInfo.name)
            local icon = card:CreateTexture(nil, "ARTWORK")
            icon:SetSize(42, 42)
            icon:SetPoint("TOP", 0, -6)
            if iconTex then
                icon:SetTexture(iconTex)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            else
                icon:SetColorTexture(0.3, 0.3, 0.3, 1)
            end

            local name = card:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
            name:SetPoint("BOTTOM", 0, 4)
            name:SetWidth(CARD_W - 6)
            name:SetWordWrap(true)
            name:SetText(auraInfo.display or auraInfo.name)

            -- "Placed" overlay for already-placed auras
            if IsAuraPlaced(auraInfo.name) then
                local overlay = card:CreateTexture(nil, "OVERLAY", nil, 7)
                overlay:SetAllPoints()
                overlay:SetColorTexture(0.3, 0.8, 0.3, 0.15)
                local placedLabel = card:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
                placedLabel:SetPoint("TOPRIGHT", -2, -2)
                placedLabel:SetText("|cff66ff66✓|r")
            end

            local capturedAura = auraInfo
            local capturedType = spellPickerType

            if isTriggerMode then
                -- Trigger add mode
                card:SetScript("OnClick", function()
                    if triggerAuraName and triggerTypeKey then
                        O.AddFrameEffectTrigger(triggerAuraName, triggerTypeKey, capturedAura.name)
                    end
                    HideSpellPicker()
                    SwitchTab("effects")
                    ADRefreshAll()
                end)
            elseif spellPickerMode == "placed" then
                card:RegisterForDrag("LeftButton")
                card:SetScript("OnDragStart", function()
                    HideSpellPicker()
                    SwitchTab("effects")
                    StartDrag(capturedAura.name, capturedAura, spec, capturedType)
                end)
                card:SetScript("OnClick", function()
                    local inst = O.CreateIndicatorInstance(capturedAura.name, capturedType)
                    if inst then expandedCards["placed:" .. capturedAura.name .. "#" .. inst.id] = true end
                    HideSpellPicker()
                    SwitchTab("effects")
                    RefreshPlacedIndicators()
                    RefreshPreviewEffects()
                    ADRefreshAll()
                end)
            else
                card:SetScript("OnClick", function()
                    O.EnsureTypeConfig(capturedAura.name, capturedType)
                    expandedCards["frame:" .. capturedType .. ":" .. capturedAura.name] = true
                    HideSpellPicker()
                    SwitchTab("effects")
                    RefreshPreviewEffects()
                    ADRefreshAll()
                end)
            end
        end

        local totalRows = math.ceil(#sectionAuras / cols)
        return startY - (totalRows * (CARD_H + GAP)) - 4
    end

    totalY = BuildSection(whitelist, "추적 오라", totalY)
    totalY = BuildSection(secret, "비밀 오라", totalY)

    grid:SetHeight(math.abs(totalY) + 10)
end

-- ============================================================
-- BUILD EFFECTS TAB
-- ============================================================
BuildEffectsTab = function()
    if not tabContentFrame then return end
    local parent = tabContentFrame
    local yPos = -10

    -- ── "+ 인디케이터 추가" 통합 버튼 (DandersFrames 패턴) ──
    local addBtn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    addBtn:SetHeight(32)
    addBtn:SetPoint("TOPLEFT", 8, yPos)
    addBtn:SetPoint("RIGHT", parent, "RIGHT", -8, 0)
    Widgets:StylizeFrame(addBtn)
    addBtn:SetBackdropColor(0.05, 0.15, 0.05, 1)
    addBtn:SetBackdropBorderColor(0.20, 0.55, 0.20, 0.8)

    local addBtnText = addBtn:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
    addBtnText:SetPoint("CENTER", 0, 0)
    addBtnText:SetText("+ 인디케이터 추가")
    addBtnText:SetTextColor(0.3, 0.85, 0.45, 1)

    addBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.10, 0.22, 0.10, 1)
        self:SetBackdropBorderColor(0.35, 0.75, 0.35, 1)
        addBtnText:SetTextColor(1, 1, 1)
    end)
    addBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.05, 0.15, 0.05, 1)
        self:SetBackdropBorderColor(0.20, 0.55, 0.20, 0.8)
        addBtnText:SetTextColor(0.3, 0.85, 0.45, 1)
    end)

    -- 드롭다운 메뉴
    local menuFrame = CreateFrame("Frame", nil, addBtn, "BackdropTemplate")
    menuFrame:SetPoint("TOPLEFT", addBtn, "BOTTOMLEFT", 0, -2)
    menuFrame:SetPoint("TOPRIGHT", addBtn, "BOTTOMRIGHT", 0, -2)
    menuFrame:SetFrameStrata("DIALOG")
    menuFrame:SetFrameLevel(100)
    Widgets:StylizeFrame(menuFrame)
    menuFrame:SetBackdropColor(0.08, 0.08, 0.10, 0.98)
    menuFrame:Hide()
    menuFrame:EnableMouse(true)

    local PLACED_ITEMS = {
        { label = "아이콘",   type = "icon"   },
        { label = "사각형",   type = "square" },
        { label = "바",       type = "bar"    },
    }
    local FRAME_ITEMS = {
        { label = "테두리",       type = "border"     },
        { label = "체력바 색상",  type = "healthbar"  },
        { label = "이름 색상",    type = "nametext"   },
        { label = "HP 텍스트",    type = "healthtext" },
        { label = "투명도",       type = "framealpha" },
    }

    local bc = O.BADGE_COLORS or {}
    local my = -6

    -- 섹션: 배치 인디케이터
    local placedHeader = menuFrame:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
    placedHeader:SetPoint("TOPLEFT", 10, my)
    placedHeader:SetText("프레임에 배치")
    placedHeader:SetTextColor(0.5, 0.5, 0.6)
    my = my - 16

    for _, item in ipairs(PLACED_ITEMS) do
        local menuBtn = CreateFrame("Button", nil, menuFrame)
        menuBtn:SetHeight(24)
        menuBtn:SetPoint("TOPLEFT", 4, my)
        menuBtn:SetPoint("RIGHT", menuFrame, "RIGHT", -4, 0)
        local itemBC = bc[item.type] or {0.7, 0.7, 0.7}
        local lbl = menuBtn:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
        lbl:SetPoint("LEFT", 8, 0)
        lbl:SetText(item.label)
        if type(itemBC) == "table" and itemBC[1] then
            lbl:SetTextColor(itemBC[1], itemBC[2], itemBC[3])
        else
            lbl:SetTextColor(0.7, 0.7, 0.7)
        end
        local hl = menuBtn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)
        local capturedType = item.type
        menuBtn:SetScript("OnClick", function()
            menuFrame:Hide()
            ShowSpellPicker(capturedType, "placed")
        end)
        my = my - 24
    end

    -- 구분선
    my = my - 4
    local mdiv = menuFrame:CreateTexture(nil, "ARTWORK")
    mdiv:SetPoint("TOPLEFT", 8, my)
    mdiv:SetPoint("RIGHT", menuFrame, "RIGHT", -8, 0)
    mdiv:SetHeight(1)
    mdiv:SetColorTexture(0.25, 0.25, 0.35, 0.6)
    my = my - 6

    -- 섹션: 프레임 효과
    local frameHeader = menuFrame:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
    frameHeader:SetPoint("TOPLEFT", 10, my)
    frameHeader:SetText("프레임 효과")
    frameHeader:SetTextColor(0.5, 0.5, 0.6)
    my = my - 16

    for _, item in ipairs(FRAME_ITEMS) do
        local menuBtn = CreateFrame("Button", nil, menuFrame)
        menuBtn:SetHeight(24)
        menuBtn:SetPoint("TOPLEFT", 4, my)
        menuBtn:SetPoint("RIGHT", menuFrame, "RIGHT", -4, 0)
        local itemBC = bc[item.type] or {0.7, 0.7, 0.7}
        local lbl = menuBtn:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
        lbl:SetPoint("LEFT", 8, 0)
        lbl:SetText(item.label)
        if type(itemBC) == "table" and itemBC[1] then
            lbl:SetTextColor(itemBC[1], itemBC[2], itemBC[3])
        else
            lbl:SetTextColor(0.7, 0.7, 0.7)
        end
        local hl = menuBtn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)
        local capturedType = item.type
        menuBtn:SetScript("OnClick", function()
            menuFrame:Hide()
            ShowSpellPicker(capturedType, "frame")
        end)
        my = my - 24
    end

    menuFrame:SetHeight(math.abs(my) + 6)

    addBtn:SetScript("OnClick", function()
        if menuFrame:IsShown() then menuFrame:Hide() else menuFrame:Show() end
    end)

    yPos = yPos - 44

    -- ── "활성 인디케이터" 헤더 ──
    local activeHeader = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
    activeHeader:SetPoint("TOPLEFT", 10, yPos)
    activeHeader:SetText("활성 인디케이터")
    activeHeader:SetTextColor(0.5, 0.5, 0.6)
    yPos = yPos - 16

    -- ── 필터 칩 (플로우 레이아웃) ──
    local chipsFrame = CreateFrame("Frame", nil, parent)
    chipsFrame:SetPoint("TOPLEFT", 8, yPos)
    chipsFrame:SetPoint("RIGHT", parent, "RIGHT", -8, 0)

    local FILTER_CHIPS = {
        { key = "all",         label = "전체"   },
        { key = "icon",        label = "아이콘" },
        { key = "square",      label = "사각형" },
        { key = "bar",         label = "바"     },
        { key = "border",      label = "테두리" },
        { key = "healthbar",   label = "체력바" },
        { key = "nametext",    label = "이름"   },
        { key = "healthtext",  label = "HP"     },
        { key = "framealpha",  label = "투명도" },
    }

    local CHIP_H = 22
    local CHIP_GAP = 4
    local CHIP_ROW_GAP = 4
    local chipBtns = {}

    for _, chip in ipairs(FILTER_CHIPS) do
        local chipBtn = CreateFrame("Button", nil, chipsFrame, "BackdropTemplate")
        chipBtn:SetHeight(CHIP_H)
        Widgets:StylizeFrame(chipBtn)

        local chipTxt = chipBtn:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
        chipTxt:SetPoint("CENTER", 0, 0)
        chipTxt:SetText(chip.label)

        local tw = chipTxt:GetStringWidth()
        chipBtn:SetWidth(max(tw + 16, 32))

        if activeFilter == chip.key then
            chipBtn:SetBackdropColor(0.00, 0.20, 0.35, 1)
            chipBtn:SetBackdropBorderColor(0.00, 0.50, 0.75, 1)
            chipTxt:SetTextColor(0.00, 0.83, 1.00)
        else
            chipBtn:SetBackdropColor(0.10, 0.10, 0.12, 1)
            chipBtn:SetBackdropBorderColor(0.20, 0.20, 0.25, 1)
            chipTxt:SetTextColor(0.75, 0.75, 0.80)
        end

        local capturedKey = chip.key
        chipBtn:SetScript("OnClick", function()
            activeFilter = capturedKey
            SwitchTab("effects")
        end)
        chipBtn:SetScript("OnEnter", function(self)
            if activeFilter ~= capturedKey then
                self:SetBackdropColor(0.14, 0.14, 0.18, 1)
            end
        end)
        chipBtn:SetScript("OnLeave", function(self)
            if activeFilter ~= capturedKey then
                self:SetBackdropColor(0.10, 0.10, 0.12, 1)
            end
        end)

        tinsert(chipBtns, chipBtn)
    end

    -- 플로우 레이아웃: 칩 자동 줄바꿈
    local function LayoutChips()
        local maxW = chipsFrame:GetWidth()
        if maxW < 20 then maxW = 260 end
        local cx, cy = 0, 0
        for _, btn in ipairs(chipBtns) do
            local bw = btn:GetWidth()
            if cx > 0 and (cx + bw) > maxW then
                cx = 0
                cy = cy - (CHIP_H + CHIP_ROW_GAP)
            end
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", chipsFrame, "TOPLEFT", cx, cy)
            cx = cx + bw + CHIP_GAP
        end
        chipsFrame:SetHeight(max(-cy + CHIP_H, CHIP_H))
    end
    LayoutChips()
    chipsFrame:SetScript("OnSizeChanged", LayoutChips)

    yPos = yPos - (chipsFrame:GetHeight() + 10)

    -- ── 이펙트 리스트 (필터 적용) ──
    local effects = O.CollectAllEffects()
    local filtered = {}
    for _, effect in ipairs(effects) do
        if activeFilter == "all" or effect.typeKey == activeFilter then
            tinsert(filtered, effect)
        end
    end

    if #filtered == 0 then
        local empty = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
        empty:SetPoint("TOP", parent, "TOP", 0, yPos - 30)
        empty:SetWidth(220)
        empty:SetJustifyH("CENTER")

        local spec = O.ResolveSpec()
        if not spec then
            empty:SetText("HoT 추적은 힐러 전문화와\n증강 기원사를 지원합니다.\n\n위 드롭다운에서 전문화를\n선택하세요.")
        elseif activeFilter == "all" then
            empty:SetText("효과가 없습니다.\n'+ 인디케이터 추가'를 클릭하세요.")
        else
            local filterLabel = (O.PLACED_TYPE_LABELS and O.PLACED_TYPE_LABELS[activeFilter])
                or (O.FRAME_LEVEL_LABELS and O.FRAME_LEVEL_LABELS[activeFilter])
                or activeFilter
            empty:SetText(filterLabel .. " 효과가 없습니다.")
        end
        empty:SetTextColor(0.45, 0.45, 0.50, 0.7)
    else
        for _, effect in ipairs(filtered) do
            yPos = CreateEffectCard(parent, yPos, effect)
            yPos = yPos - 4
        end
    end

    parent:SetHeight(max(math.abs(yPos) + 20, 200))
end

-- ============================================================
-- CREATE EFFECT CARD
-- ============================================================
CreateEffectCard = function(parent, yPos, effect)
    local isPlaced = (effect.source == "placed")
    local cardKey = isPlaced
        and ("placed:" .. effect.auraName .. "#" .. effect.indicatorID)
        or ("frame:" .. effect.typeKey .. ":" .. effect.auraName)
    local isExpanded = expandedCards[cardKey] or false

    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetPoint("TOPLEFT", 4, yPos)
    card:SetPoint("RIGHT", parent, "RIGHT", -4, 0)

    -- Header
    local header = CreateFrame("Button", nil, card, "BackdropTemplate")
    header:SetHeight(28)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    Widgets:StylizeFrame(header)

    -- Badge color
    local bc = O.BADGE_COLORS[effect.typeKey] or {0.5, 0.5, 0.5}
    local typeLabel = isPlaced and (O.PLACED_TYPE_LABELS[effect.typeKey] or effect.typeKey)
        or (O.FRAME_LEVEL_LABELS[effect.typeKey] or effect.typeKey)

    -- Left accent bar (type color)
    local accentBar = header:CreateTexture(nil, "ARTWORK")
    accentBar:SetSize(3, 22)
    accentBar:SetPoint("LEFT", 2, 0)
    accentBar:SetColorTexture(bc[1], bc[2], bc[3], 0.8)

    -- Chevron (expand/collapse)
    local chevron = header:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
    chevron:SetPoint("LEFT", 8, 0)
    chevron:SetText(isExpanded and "▼" or "▶")
    chevron:SetTextColor(0.6, 0.6, 0.65)

    -- Badge
    local badge = header:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
    badge:SetPoint("LEFT", chevron, "RIGHT", 4, 0)
    badge:SetText("[" .. typeLabel .. "]")
    badge:SetTextColor(bc[1], bc[2], bc[3])

    -- Aura name
    local info = header:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
    info:SetPoint("LEFT", badge, "RIGHT", 6, 0)
    info:SetPoint("RIGHT", header, "RIGHT", -30, 0)
    local infoStr = effect.displayName or effect.auraName
    if isPlaced and effect.anchor then
        infoStr = infoStr .. " - " .. (O.ANCHOR_LABELS[effect.anchor] or effect.anchor)
    end
    info:SetText(infoStr)

    -- Delete button (X-shaped rotated textures)
    local delBtn = CreateFrame("Button", nil, header)
    delBtn:SetSize(20, 20)
    delBtn:SetPoint("RIGHT", -4, 0)
    delBtn:SetFrameLevel(header:GetFrameLevel() + 2)

    local xSize, xThick = 10, 1.5
    local line1 = delBtn:CreateTexture(nil, "OVERLAY")
    line1:SetSize(xSize, xThick)
    line1:SetPoint("CENTER")
    line1:SetColorTexture(0.50, 0.30, 0.30, 1)
    line1:SetRotation(math.rad(45))
    local line2 = delBtn:CreateTexture(nil, "OVERLAY")
    line2:SetSize(xSize, xThick)
    line2:SetPoint("CENTER")
    line2:SetColorTexture(0.50, 0.30, 0.30, 1)
    line2:SetRotation(math.rad(-45))

    delBtn:SetScript("OnEnter", function()
        line1:SetColorTexture(1, 0.40, 0.40, 1)
        line2:SetColorTexture(1, 0.40, 0.40, 1)
    end)
    delBtn:SetScript("OnLeave", function()
        line1:SetColorTexture(0.50, 0.30, 0.30, 1)
        line2:SetColorTexture(0.50, 0.30, 0.30, 1)
    end)
    delBtn:SetScript("OnClick", function()
        if isPlaced then
            O.RemoveIndicatorInstance(effect.auraName, effect.indicatorID)
        else
            local auraCfg = O.GetSpecAuras()[effect.auraName]
            if auraCfg then auraCfg[effect.typeKey] = nil end
        end
        expandedCards[cardKey] = nil
        RefreshPage()
        ADRefreshAll()
    end)

    -- Header hover feedback
    header:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.12, 0.12, 0.18, 1)
    end)
    header:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.07, 0.07, 0.14, 1)
    end)

    -- Toggle expand
    header:SetScript("OnClick", function()
        expandedCards[cardKey] = not expandedCards[cardKey]
        SwitchTab("effects")
    end)

    local totalCardH = 28

    -- Expanded body
    if isExpanded then
        local body = CreateFrame("Frame", nil, card, "BackdropTemplate")
        body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
        body:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, 0)
        Widgets:StylizeFrame(body)

        local proxy
        if isPlaced then
            proxy = O.CreateInstanceProxy(effect.auraName, effect.indicatorID)
        else
            proxy = O.CreateProxy(effect.auraName, effect.typeKey)
        end

        local bodyH = BuildTypeWidgets(body, effect.typeKey, effect.auraName, proxy, isPlaced, effect.indicatorID)
        body:SetHeight(bodyH)
        totalCardH = totalCardH + bodyH
    end

    card:SetHeight(totalCardH)
    return yPos - totalCardH
end

-- ============================================================
-- COLLAPSIBLE GROUP WIDGET (DandersFrames AddGroup pattern)
-- ============================================================
local collapsedGroups = {}

local function CreateCollapsibleGroup(parent, title, buildFn, y)
    local groupKey = title
    local isCollapsed = collapsedGroups[groupKey] or false

    -- Group header with accent bar
    local header = CreateFrame("Button", nil, parent, "BackdropTemplate")
    header:SetHeight(22)
    header:SetPoint("TOPLEFT", 4, y)
    header:SetPoint("RIGHT", parent, "RIGHT", -4, 0)
    Widgets:StylizeFrame(header)

    -- Left accent bar (orange)
    local accent = header:CreateTexture(nil, "ARTWORK")
    accent:SetSize(3, 16)
    accent:SetPoint("LEFT", 2, 0)
    accent:SetColorTexture(0.91, 0.66, 0.25, 0.9)

    local arrow = header:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
    arrow:SetPoint("LEFT", 8, 0)
    arrow:SetText(isCollapsed and "▶" or "▼")
    arrow:SetTextColor(0.7, 0.7, 0.7)

    local titleText = header:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
    titleText:SetPoint("LEFT", arrow, "RIGHT", 4, 0)
    titleText:SetText(title)
    titleText:SetTextColor(0.91, 0.82, 0.58)

    header:SetScript("OnClick", function()
        collapsedGroups[groupKey] = not collapsedGroups[groupKey]
        SwitchTab("effects")
    end)
    header:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.12, 0.12, 0.18, 1)
    end)
    header:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.07, 0.07, 0.14, 1)
    end)

    y = y - 26

    if not isCollapsed then
        y = buildFn(y)
        y = y - 6
    end

    return y
end

-- ============================================================
-- COPY APPEARANCE UI
-- ============================================================
local function BuildCopyAppearanceUI(parent, y, auraName, typeKey, indicatorID)
    -- Find other same-type indicators to copy from
    local candidates = {}
    local spec = O.ResolveSpec()
    local AD = ns.AuraDesigner
    local trackable = spec and AD and AD.TrackableAuras and AD.TrackableAuras[spec]
    local displayNames = {}
    if trackable then for _, info in ipairs(trackable) do displayNames[info.name] = info.display end end

    for srcAura, auraCfg in pairs(O.GetSpecAuras(spec)) do
        if type(auraCfg) == "table" and auraCfg.indicators then
            for _, inst in ipairs(auraCfg.indicators) do
                if inst.type == typeKey and not (srcAura == auraName and inst.id == indicatorID) then
                    local label = (displayNames[srcAura] or srcAura) .. " #" .. inst.id
                    tinsert(candidates, { value = srcAura .. ":" .. inst.id, text = label, auraName = srcAura, id = inst.id })
                end
            end
        end
    end

    if #candidates == 0 then return y end

    local copyBtn = Widgets:CreateButton(parent, "외형 복사", "accent-hover", { 90, 22 })
    copyBtn:SetPoint("TOPLEFT", 8, y)
    copyBtn:SetScript("OnClick", function()
        -- Create dropdown popup
        local drop = CreateFrame("Frame", nil, copyBtn, "BackdropTemplate")
        drop:SetWidth(180)
        Widgets:StylizeFrame(drop)
        local dy = -4
        for _, cand in ipairs(candidates) do
            local btn = CreateFrame("Button", nil, drop, "BackdropTemplate")
            btn:SetSize(172, 20)
            btn:SetPoint("TOPLEFT", 4, dy)
            Widgets:StylizeFrame(btn)
            local lbl = btn:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
            lbl:SetPoint("LEFT", 4, 0)
            lbl:SetText(cand.text)
            local capturedCand = cand
            btn:SetScript("OnClick", function()
                O.CopyIndicatorAppearance(capturedCand.auraName, capturedCand.id, auraName, indicatorID)
                drop:Hide()
                RefreshPage(); ADRefreshAll()
            end)
            dy = dy - 22
        end
        drop:SetHeight(math.abs(dy) + 8)
        drop:SetPoint("TOPLEFT", copyBtn, "BOTTOMLEFT", 0, -2)
        drop:Show()
        drop:SetScript("OnHide", function() drop._ownerBtn = nil end)
    end)
    y = y - 26
    return y
end

-- ============================================================
-- EXPIRING THRESHOLD ROW (PERCENT/SECONDS toggle + slider)
-- ============================================================
local function BuildExpiringThresholdRow(parent, y, proxy, W)
    -- Mode toggle label
    local modeLbl = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
    modeLbl:SetPoint("TOPLEFT", 10, y)
    modeLbl:SetText("임계값 모드")
    modeLbl:SetTextColor(0.7, 0.7, 0.7)
    y = y - 16
    local modeDD = Widgets:CreateDropdown(parent, 100)
    modeDD:SetPoint("TOPLEFT", 10, y)
    modeDD:SetItems(O.EXPIRING_MODE_OPTIONS)
    modeDD:SetSelected(proxy.expiringThresholdMode or "PERCENT")
    modeDD:SetOnSelect(function(val)
        proxy.expiringThresholdMode = val
        RefreshPage()
        ADRefreshAll()
    end)
    y = y - 32

    -- Threshold slider
    local isPercent = (proxy.expiringThresholdMode or "PERCENT") == "PERCENT"
    local lo, hi, step, label
    if isPercent then lo, hi, step, label = 5, 100, 5, "만료 임계값(%)"
    else lo, hi, step, label = 1, 60, 1, "만료 임계값(초)" end
    local s = Widgets:CreateSlider(label, parent, lo, hi, W, step,
        function(v) proxy.expiringThreshold = v end,
        function(v) proxy.expiringThreshold = v; ADRefreshAll() end)
    s:SetPoint("TOPLEFT", 10, y)
    s:SetValue(proxy.expiringThreshold or lo)
    y = y - 50
    return y
end

-- ============================================================
-- TRIGGER TAGS UI (AND/OR + tag flow + add trigger)
-- ============================================================
local function BuildTriggerUI(parent, y, auraName, typeKey, W)
    local triggers = O.GetFrameEffectTriggers(auraName, typeKey)

    -- "트리거:" 라벨 (dim 색상)
    local trigLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
    trigLabel:SetPoint("TOPLEFT", 8, y)
    trigLabel:SetText("트리거:")
    trigLabel:SetTextColor(0.5, 0.5, 0.6)

    -- AND/OR toggle (2개 이상일 때만 표시)
    local typeCfg = O.EnsureTypeConfig(auraName, typeKey)
    if #triggers > 1 then
        local isAnd = typeCfg.triggerLogic == "AND"
        local opBtn = CreateFrame("Button", nil, parent, "BackdropTemplate")
        opBtn:SetHeight(18)
        opBtn:SetPoint("LEFT", trigLabel, "RIGHT", 6, 0)
        Widgets:StylizeFrame(opBtn)

        local opText = opBtn:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
        opText:SetPoint("CENTER", 0, 0)
        opText:SetText(isAnd and "ALL (AND)" or "ANY (OR)")
        if isAnd then
            opText:SetTextColor(0.9, 0.7, 0.5)
            opBtn:SetBackdropColor(0.14, 0.12, 0.10, 1)
            opBtn:SetBackdropBorderColor(0.35, 0.28, 0.20, 0.8)
        else
            opText:SetTextColor(0.5, 0.7, 0.9)
            opBtn:SetBackdropColor(0.10, 0.12, 0.14, 1)
            opBtn:SetBackdropBorderColor(0.20, 0.28, 0.35, 0.8)
        end

        local opW = opText:GetStringWidth() + 16
        if opW < 52 then opW = 52 end
        opBtn:SetWidth(opW)

        opBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.18, 0.18, 0.22, 1)
        end)
        opBtn:SetScript("OnLeave", function(self)
            if typeCfg.triggerLogic == "AND" then
                self:SetBackdropColor(0.14, 0.12, 0.10, 1)
            else
                self:SetBackdropColor(0.10, 0.12, 0.14, 1)
            end
        end)
        opBtn:SetScript("OnClick", function()
            typeCfg.triggerLogic = (typeCfg.triggerLogic == "AND") and "OR" or "AND"
            RefreshPage(); ADRefreshAll()
        end)
    end
    y = y - 16

    -- 태그 플로우 레이아웃
    local TAG_H = 20
    local TAG_GAP = 4
    local TAG_ROW_GAP = 3
    local tagX, tagY = 0, y
    local canRemove = #triggers > 1
    local bodyWidth = W or 230

    -- Display name lookup
    local spec = O.ResolveSpec()
    local AD = ns.AuraDesigner
    local trackable = spec and AD and AD.TrackableAuras and AD.TrackableAuras[spec]
    local displayNames = {}
    if trackable then
        for _, info in ipairs(trackable) do displayNames[info.name] = info.display end
    end

    for _, trigName in ipairs(triggers) do
        local tagFrame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        tagFrame:SetHeight(TAG_H)
        Widgets:StylizeFrame(tagFrame)
        tagFrame:SetBackdropColor(0.14, 0.14, 0.17, 1)
        tagFrame:SetBackdropBorderColor(0.30, 0.30, 0.35, 0.8)

        local tagText = tagFrame:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
        tagText:SetPoint("LEFT", 6, 0)
        tagText:SetText(displayNames[trigName] or trigName)
        tagText:SetTextColor(0.85, 0.85, 0.90)

        local tagW = tagText:GetStringWidth() + 12
        if canRemove then tagW = tagW + 16 end
        tagW = max(tagW, 40)

        -- 줄바꿈 체크
        if tagX > 0 and (tagX + tagW) > bodyWidth then
            tagX = 0
            tagY = tagY - (TAG_H + TAG_ROW_GAP)
        end

        tagFrame:SetPoint("TOPLEFT", 8 + tagX, tagY)
        tagFrame:SetWidth(tagW)

        -- 제거 × 버튼 (2개 이상일 때만, X자 회전 텍스쳐)
        if canRemove then
            local removeBtn = CreateFrame("Button", nil, tagFrame)
            removeBtn:SetSize(14, 14)
            removeBtn:SetPoint("RIGHT", -2, 0)
            local rx1 = removeBtn:CreateTexture(nil, "OVERLAY")
            rx1:SetSize(8, 1.5)
            rx1:SetPoint("CENTER")
            rx1:SetColorTexture(0.50, 0.30, 0.30, 1)
            rx1:SetRotation(math.rad(45))
            local rx2 = removeBtn:CreateTexture(nil, "OVERLAY")
            rx2:SetSize(8, 1.5)
            rx2:SetPoint("CENTER")
            rx2:SetColorTexture(0.50, 0.30, 0.30, 1)
            rx2:SetRotation(math.rad(-45))
            removeBtn:SetScript("OnEnter", function()
                rx1:SetColorTexture(1, 0.40, 0.40, 1)
                rx2:SetColorTexture(1, 0.40, 0.40, 1)
            end)
            removeBtn:SetScript("OnLeave", function()
                rx1:SetColorTexture(0.50, 0.30, 0.30, 1)
                rx2:SetColorTexture(0.50, 0.30, 0.30, 1)
            end)
            local capturedTrig = trigName
            removeBtn:SetScript("OnClick", function()
                O.RemoveFrameEffectTrigger(auraName, typeKey, capturedTrig)
                RefreshPage(); ADRefreshAll()
            end)
        end

        tagX = tagX + tagW + TAG_GAP
    end

    -- "+ 트리거 추가" 버튼 (플로우에 포함)
    local addTrigW = 90
    if tagX > 0 and (tagX + addTrigW) > bodyWidth then
        tagX = 0
        tagY = tagY - (TAG_H + TAG_ROW_GAP)
    end

    local addTrigBtn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    addTrigBtn:SetSize(addTrigW, TAG_H)
    addTrigBtn:SetPoint("TOPLEFT", 8 + tagX, tagY)
    Widgets:StylizeFrame(addTrigBtn)
    addTrigBtn:SetBackdropColor(0.08, 0.12, 0.08, 1)
    addTrigBtn:SetBackdropBorderColor(0.20, 0.40, 0.20, 0.8)

    local addTrigText = addTrigBtn:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
    addTrigText:SetPoint("CENTER", 0, 0)
    addTrigText:SetText("+ 트리거 추가")
    addTrigText:SetTextColor(0.5, 0.8, 0.5)

    addTrigBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.12, 0.18, 0.12, 1)
        addTrigText:SetTextColor(0.7, 1.0, 0.7)
    end)
    addTrigBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.08, 0.12, 0.08, 1)
        addTrigText:SetTextColor(0.5, 0.8, 0.5)
    end)
    addTrigBtn:SetScript("OnClick", function()
        ShowSpellPicker(typeKey, "trigger:" .. auraName .. ":" .. typeKey)
    end)

    y = tagY - TAG_H - 8
    return y
end

-- ============================================================
-- BUILD TYPE WIDGETS (per-indicator settings) — COMPLETE
-- ============================================================
function BuildTypeWidgets(parent, typeKey, auraName, proxy, isPlaced, indicatorID)
    local y = -8
    local W = 230

    local function AddSlider(label, lo, hi, step, key)
        local val = proxy[key] or lo
        local s = Widgets:CreateSlider(label, parent, lo, hi, W, step,
            function(v) proxy[key] = v end,
            function(v) proxy[key] = v; ADRefreshAll() end)
        s:SetPoint("TOPLEFT", 10, y)
        s:SetValue(val)
        y = y - 50
        return s
    end

    local function AddCheck(label, key)
        local cb = Widgets:CreateCheckButton(parent, label, function(checked)
            proxy[key] = checked
            ADRefreshAll()
        end)
        cb:SetPoint("TOPLEFT", 10, y)
        cb:SetChecked(proxy[key] or false)
        y = y - 26
        return cb
    end

    local function AddColor(label, key, hasAlpha)
        local clr = proxy[key] or {r=1,g=1,b=1,a=1}
        local cp = Widgets:CreateColorPicker(parent, label, hasAlpha, function(r, g, b, a)
            if not proxy[key] then proxy[key] = {} end
            proxy[key].r = r; proxy[key].g = g; proxy[key].b = b; proxy[key].a = a or 1
            ADRefreshAll()
        end)
        cp:SetPoint("TOPLEFT", 10, y)
        cp:SetColor(clr.r or 1, clr.g or 1, clr.b or 1, clr.a or 1)
        y = y - 28
        return cp
    end

    local function AddDropdown(label, key, items, onChangeCb)
        local lbl = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
        lbl:SetPoint("TOPLEFT", 10, y)
        lbl:SetText(label)
        lbl:SetTextColor(0.7, 0.7, 0.7)
        y = y - 16
        local dd = Widgets:CreateDropdown(parent, W)
        dd:SetPoint("TOPLEFT", 10, y)
        dd:SetItems(items)
        dd:SetSelected(proxy[key] or items[1].value)
        dd:SetOnSelect(function(val)
            proxy[key] = val
            if onChangeCb then onChangeCb(val) end
            ADRefreshAll()
        end)
        y = y - 32
        return dd
    end

    local function AddAnchorDropdown(key)
        return AddDropdown("기준점", key, O.ANCHOR_OPTIONS)
    end

    local function AddFontDropdown(label, key)
        local fonts = {}
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            for _, name in ipairs(LSM:List("font")) do
                tinsert(fonts, { value = LSM:Fetch("font", name), text = name })
            end
        end
        if #fonts == 0 then
            tinsert(fonts, { value = "Fonts\\FRIZQT__.TTF", text = "기본 폰트" })
        end
        return AddDropdown(label, key, fonts)
    end

    local function AddTextureDropdown(label, key)
        local textures = {}
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            for _, name in ipairs(LSM:List("statusbar")) do
                tinsert(textures, { value = LSM:Fetch("statusbar", name), text = name })
            end
        end
        if #textures == 0 then
            tinsert(textures, { value = "Interface\\TargetingFrame\\UI-StatusBar", text = "기본 텍스처" })
        end
        return AddDropdown(label, key, textures)
    end

    local layoutGroup = isPlaced and indicatorID and O.GetIndicatorLayoutGroup(auraName, indicatorID)

    -- ===== Copy Appearance (placed only) =====
    if isPlaced and indicatorID then
        y = BuildCopyAppearanceUI(parent, y, auraName, typeKey, indicatorID)
    end

    -- ===== Trigger UI (frame-level only) =====
    if not isPlaced then
        y = BuildTriggerUI(parent, y, auraName, typeKey, W)

        -- Border mode toggle (border 타입 전용)
        if typeKey == "border" then
            local bmLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
            bmLabel:SetPoint("TOPLEFT", 10, y)
            bmLabel:SetText("테두리 모드:")
            bmLabel:SetTextColor(0.5, 0.5, 0.6)

            local auraCfgBM = O.GetSpecAuras()[auraName]
            local typeCfgBM = auraCfgBM and auraCfgBM[typeKey]
            local isCustom = typeCfgBM and typeCfgBM.borderMode == "custom"

            local sharedBtn = CreateFrame("Button", nil, parent, "BackdropTemplate")
            sharedBtn:SetHeight(20)
            sharedBtn:SetPoint("LEFT", bmLabel, "RIGHT", 6, 0)
            Widgets:StylizeFrame(sharedBtn)
            local sharedText = sharedBtn:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
            sharedText:SetPoint("CENTER")
            sharedText:SetText("공유")
            local sharedW = sharedText:GetStringWidth() + 16
            if sharedW < 50 then sharedW = 50 end
            sharedBtn:SetWidth(sharedW)

            local customBtn = CreateFrame("Button", nil, parent, "BackdropTemplate")
            customBtn:SetHeight(20)
            customBtn:SetPoint("LEFT", sharedBtn, "RIGHT", 4, 0)
            Widgets:StylizeFrame(customBtn)
            local customText = customBtn:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
            customText:SetPoint("CENTER")
            customText:SetText("커스텀")
            local customW = customText:GetStringWidth() + 16
            if customW < 50 then customW = 50 end
            customBtn:SetWidth(customW)

            if isCustom then
                customBtn:SetBackdropColor(0.12, 0.18, 0.12, 1)
                customBtn:SetBackdropBorderColor(0.30, 0.50, 0.30, 0.9)
                customText:SetTextColor(0.6, 1.0, 0.6)
                sharedBtn:SetBackdropColor(0.10, 0.10, 0.12, 1)
                sharedBtn:SetBackdropBorderColor(0.20, 0.20, 0.25, 0.6)
                sharedText:SetTextColor(0.5, 0.5, 0.6)
            else
                sharedBtn:SetBackdropColor(0.12, 0.18, 0.12, 1)
                sharedBtn:SetBackdropBorderColor(0.30, 0.50, 0.30, 0.9)
                sharedText:SetTextColor(0.6, 1.0, 0.6)
                customBtn:SetBackdropColor(0.10, 0.10, 0.12, 1)
                customBtn:SetBackdropBorderColor(0.20, 0.20, 0.25, 0.6)
                customText:SetTextColor(0.5, 0.5, 0.6)
            end

            sharedBtn:SetScript("OnClick", function()
                local cfg = O.EnsureTypeConfig(auraName, typeKey)
                cfg.borderMode = nil
                RefreshPage(); ADRefreshAll()
            end)
            customBtn:SetScript("OnClick", function()
                local cfg = O.EnsureTypeConfig(auraName, typeKey)
                cfg.borderMode = "custom"
                RefreshPage(); ADRefreshAll()
            end)
            y = y - 28
        end

        -- Priority 슬라이더 (프레임레벨 전용)
        AddSlider("우선순위", 1, 10, 1, "priority")
    end

    if typeKey == "icon" then
        -- Position
        y = CreateCollapsibleGroup(parent, "위치", function(gy)
            if layoutGroup then
                local note = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
                note:SetPoint("TOPLEFT", 8, gy)
                note:SetTextColor(0.91, 0.66, 0.25, 0.8)
                note:SetText("위치: " .. (layoutGroup.name or "레이아웃 그룹") .. "에서 관리")
                return gy - 18
            end
            y = gy
            AddAnchorDropdown("anchor")
            AddSlider("오프셋 X", -150, 150, 1, "offsetX")
            AddSlider("오프셋 Y", -150, 150, 1, "offsetY")
            return y
        end, y)

        -- Appearance
        y = CreateCollapsibleGroup(parent, "외형", function(gy)
            y = gy
            AddSlider("크기", 8, 64, 1, "size")
            AddSlider("스케일", 0.5, 3.0, 0.05, "scale")
            AddSlider("투명도", 0, 1, 0.05, "alpha")
            AddSlider("프레임 레벨", -10, 30, 1, "frameLevel")
            AddDropdown("프레임 스트라타", "frameStrata", O.FRAME_STRATA_OPTIONS)
            AddCheck("쿨다운 숨기기", "hideSwipe")
            AddCheck("아이콘 숨기기 (텍스트만)", "hideIcon")
            return y
        end, y)

        -- Border
        y = CreateCollapsibleGroup(parent, "테두리", function(gy)
            y = gy
            AddCheck("테두리 표시", "borderEnabled")
            AddSlider("테두리 두께", 1, 5, 1, "borderThickness")
            AddSlider("테두리 인셋", -3, 5, 1, "borderInset")
            return y
        end, y)

        -- Duration Text
        y = CreateCollapsibleGroup(parent, "지속시간 텍스트", function(gy)
            y = gy
            AddCheck("지속시간 표시", "showDuration")
            AddFontDropdown("지속시간 폰트", "durationFont")
            AddSlider("지속시간 스케일", 0.5, 2.0, 0.1, "durationScale")
            AddDropdown("지속시간 외곽선", "durationOutline", O.OUTLINE_OPTIONS)
            AddDropdown("지속시간 기준점", "durationAnchor", O.ANCHOR_OPTIONS)
            AddSlider("지속시간 오프셋 X", -150, 150, 1, "durationX")
            AddSlider("지속시간 오프셋 Y", -150, 150, 1, "durationY")
            AddCheck("시간별 색상", "durationColorByTime")
            AddColor("지속시간 텍스트 색상", "durationColor", true)
            AddCheck("임계값 이상 숨기기", "durationHideAboveEnabled")
            AddSlider("숨기기 기준 (초)", 1, 60, 1, "durationHideAboveThreshold")
            return y
        end, y)

        -- Stack Count
        y = CreateCollapsibleGroup(parent, "중첩", function(gy)
            y = gy
            AddCheck("중첩 표시", "showStacks")
            AddSlider("최소 중첩", 1, 10, 1, "stackMinimum")
            AddFontDropdown("중첩 폰트", "stackFont")
            AddSlider("중첩 스케일", 0.5, 2.0, 0.1, "stackScale")
            AddDropdown("중첩 외곽선", "stackOutline", O.OUTLINE_OPTIONS)
            AddDropdown("중첩 기준점", "stackAnchor", O.ANCHOR_OPTIONS)
            AddSlider("중첩 오프셋 X", -150, 150, 1, "stackX")
            AddSlider("중첩 오프셋 Y", -150, 150, 1, "stackY")
            AddColor("중첩 텍스트 색상", "stackColor", true)
            return y
        end, y)

        -- Expiring
        y = CreateCollapsibleGroup(parent, "만료 효과", function(gy)
            y = gy
            AddCheck("만료 색상 활성화", "expiringEnabled")
            y = BuildExpiringThresholdRow(parent, y, proxy, W)
            AddColor("만료 색상", "expiringColor", true)
            AddCheck("테두리 펄스", "expiringPulsate")
            AddCheck("전체 알파 펄스", "expiringWholeAlphaPulse")
            AddCheck("바운스", "expiringBounce")
            return y
        end, y)

    elseif typeKey == "square" then
        -- Position
        y = CreateCollapsibleGroup(parent, "위치", function(gy)
            if layoutGroup then
                local note = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
                note:SetPoint("TOPLEFT", 8, gy)
                note:SetTextColor(0.91, 0.66, 0.25, 0.8)
                note:SetText("위치: " .. (layoutGroup.name or "레이아웃 그룹") .. "에서 관리")
                return gy - 18
            end
            y = gy
            AddAnchorDropdown("anchor")
            AddSlider("오프셋 X", -150, 150, 1, "offsetX")
            AddSlider("오프셋 Y", -150, 150, 1, "offsetY")
            return y
        end, y)

        -- Appearance
        y = CreateCollapsibleGroup(parent, "외형", function(gy)
            y = gy
            AddSlider("크기", 8, 64, 1, "size")
            AddSlider("스케일", 0.5, 3.0, 0.05, "scale")
            AddColor("색상", "color", true)
            AddSlider("투명도", 0, 1, 0.05, "alpha")
            AddSlider("프레임 레벨", -10, 30, 1, "frameLevel")
            AddDropdown("프레임 스트라타", "frameStrata", O.FRAME_STRATA_OPTIONS)
            AddCheck("쿨다운 숨기기", "hideSwipe")
            AddCheck("아이콘 숨기기 (텍스트만)", "hideIcon")
            return y
        end, y)

        -- Border
        y = CreateCollapsibleGroup(parent, "테두리", function(gy)
            y = gy
            AddCheck("테두리 표시", "showBorder")
            AddSlider("테두리 두께", 1, 5, 1, "borderThickness")
            AddSlider("테두리 인셋", -3, 5, 1, "borderInset")
            return y
        end, y)

        -- Duration Text
        y = CreateCollapsibleGroup(parent, "지속시간 텍스트", function(gy)
            y = gy
            AddCheck("지속시간 표시", "showDuration")
            AddFontDropdown("지속시간 폰트", "durationFont")
            AddSlider("지속시간 스케일", 0.5, 2.0, 0.1, "durationScale")
            AddDropdown("지속시간 외곽선", "durationOutline", O.OUTLINE_OPTIONS)
            AddDropdown("지속시간 기준점", "durationAnchor", O.ANCHOR_OPTIONS)
            AddSlider("지속시간 오프셋 X", -150, 150, 1, "durationX")
            AddSlider("지속시간 오프셋 Y", -150, 150, 1, "durationY")
            AddCheck("시간별 색상", "durationColorByTime")
            AddColor("지속시간 텍스트 색상", "durationColor", true)
            AddCheck("임계값 이상 숨기기", "durationHideAboveEnabled")
            AddSlider("숨기기 기준 (초)", 1, 60, 1, "durationHideAboveThreshold")
            return y
        end, y)

        -- Stack Count
        y = CreateCollapsibleGroup(parent, "중첩", function(gy)
            y = gy
            AddCheck("중첩 표시", "showStacks")
            AddSlider("최소 중첩", 1, 10, 1, "stackMinimum")
            AddFontDropdown("중첩 폰트", "stackFont")
            AddSlider("중첩 스케일", 0.5, 2.0, 0.1, "stackScale")
            AddDropdown("중첩 외곽선", "stackOutline", O.OUTLINE_OPTIONS)
            AddDropdown("중첩 기준점", "stackAnchor", O.ANCHOR_OPTIONS)
            AddSlider("중첩 오프셋 X", -150, 150, 1, "stackX")
            AddSlider("중첩 오프셋 Y", -150, 150, 1, "stackY")
            AddColor("중첩 텍스트 색상", "stackColor", true)
            return y
        end, y)

        -- Expiring
        y = CreateCollapsibleGroup(parent, "만료 효과", function(gy)
            y = gy
            AddCheck("만료 색상 활성화", "expiringEnabled")
            y = BuildExpiringThresholdRow(parent, y, proxy, W)
            AddColor("만료 색상", "expiringColor", true)
            AddCheck("채움 펄스", "expiringPulsate")
            AddCheck("전체 알파 펄스", "expiringWholeAlphaPulse")
            AddCheck("바운스", "expiringBounce")
            return y
        end, y)

    elseif typeKey == "bar" then
        -- Position
        y = CreateCollapsibleGroup(parent, "위치", function(gy)
            if layoutGroup then
                local note = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
                note:SetPoint("TOPLEFT", 8, gy)
                note:SetTextColor(0.91, 0.66, 0.25, 0.8)
                note:SetText("위치: " .. (layoutGroup.name or "레이아웃 그룹") .. "에서 관리")
                return gy - 18
            end
            y = gy
            AddAnchorDropdown("anchor")
            AddSlider("오프셋 X", -150, 150, 1, "offsetX")
            AddSlider("오프셋 Y", -150, 150, 1, "offsetY")
            return y
        end, y)

        -- Size & Orientation
        y = CreateCollapsibleGroup(parent, "크기 & 방향", function(gy)
            y = gy
            AddDropdown("방향", "orientation", O.BAR_ORIENT_OPTIONS, function()
                -- Swap width/height on orientation change
                local w, h = proxy.width, proxy.height
                proxy.width = h; proxy.height = w
                local mw, mh = proxy.matchFrameWidth, proxy.matchFrameHeight
                proxy.matchFrameWidth = mh; proxy.matchFrameHeight = mw
                RefreshPage()
            end)
            AddSlider("너비", 0, 200, 1, "width")
            AddSlider("높이", 1, 30, 1, "height")
            AddCheck("프레임 너비 맞춤", "matchFrameWidth")
            AddCheck("프레임 높이 맞춤", "matchFrameHeight")
            return y
        end, y)

        -- Texture & Colors
        y = CreateCollapsibleGroup(parent, "텍스처 & 색상", function(gy)
            y = gy
            AddTextureDropdown("바 텍스처", "texture")
            AddColor("채움 색상", "fillColor", true)
            AddColor("배경 색상", "bgColor", true)
            AddSlider("투명도", 0, 1, 0.05, "alpha")
            AddSlider("프레임 레벨", -10, 30, 1, "frameLevel")
            AddDropdown("프레임 스트라타", "frameStrata", O.FRAME_STRATA_OPTIONS)
            return y
        end, y)

        -- Border
        y = CreateCollapsibleGroup(parent, "테두리", function(gy)
            y = gy
            AddCheck("테두리 표시", "showBorder")
            AddSlider("테두리 두께", 1, 4, 1, "borderThickness")
            AddColor("테두리 색상", "borderColor", true)
            return y
        end, y)

        -- Expiring
        y = CreateCollapsibleGroup(parent, "만료 효과", function(gy)
            y = gy
            AddCheck("시간별 바 색상", "barColorByTime")
            AddCheck("만료 색상 활성화", "expiringEnabled")
            y = BuildExpiringThresholdRow(parent, y, proxy, W)
            AddColor("만료 색상", "expiringColor", true)
            return y
        end, y)

        -- Duration Text
        y = CreateCollapsibleGroup(parent, "지속시간 텍스트", function(gy)
            y = gy
            AddCheck("지속시간 표시", "showDuration")
            AddFontDropdown("지속시간 폰트", "durationFont")
            AddSlider("지속시간 스케일", 0.5, 2.0, 0.1, "durationScale")
            AddDropdown("지속시간 외곽선", "durationOutline", O.OUTLINE_OPTIONS)
            AddDropdown("지속시간 기준점", "durationAnchor", O.ANCHOR_OPTIONS)
            AddSlider("지속시간 오프셋 X", -150, 150, 1, "durationX")
            AddSlider("지속시간 오프셋 Y", -150, 150, 1, "durationY")
            AddCheck("시간별 색상", "durationColorByTime")
            AddCheck("임계값 이상 숨기기", "durationHideAboveEnabled")
            AddSlider("숨기기 기준 (초)", 1, 60, 1, "durationHideAboveThreshold")
            return y
        end, y)

    elseif typeKey == "border" then
        -- Appearance
        y = CreateCollapsibleGroup(parent, "외형", function(gy)
            y = gy
            AddDropdown("스타일", "style", O.BORDER_STYLE_OPTIONS)
            AddColor("색상", "color", true)
            AddSlider("두께", 1, 8, 1, "thickness")
            AddSlider("인셋", 0, 8, 1, "inset")
            return y
        end, y)

        -- Expiring
        y = CreateCollapsibleGroup(parent, "만료 효과", function(gy)
            y = gy
            AddCheck("만료 색상 활성화", "expiringEnabled")
            y = BuildExpiringThresholdRow(parent, y, proxy, W)
            AddColor("만료 색상", "expiringColor", true)
            AddCheck("펄스", "expiringPulsate")
            return y
        end, y)

    elseif typeKey == "healthbar" then
        -- Appearance
        y = CreateCollapsibleGroup(parent, "외형", function(gy)
            y = gy
            local blendSlider
            AddDropdown("모드", "mode", O.HEALTHBAR_MODE_OPTIONS, function(val)
                if blendSlider then
                    if val == "Replace" then blendSlider:Hide() else blendSlider:Show() end
                end
            end)
            AddColor("색상", "color", true)
            blendSlider = AddSlider("블렌드 %", 0, 1, 0.05, "blend")
            if (proxy.mode or "Replace") == "Replace" then blendSlider:Hide(); y = y + 44 end
            return y
        end, y)

        -- Expiring
        y = CreateCollapsibleGroup(parent, "만료 효과", function(gy)
            y = gy
            AddCheck("만료 색상 활성화", "expiringEnabled")
            y = BuildExpiringThresholdRow(parent, y, proxy, W)
            AddColor("만료 색상", "expiringColor", true)
            AddCheck("펄스", "expiringPulsate")
            return y
        end, y)

    elseif typeKey == "nametext" then
        -- Appearance
        y = CreateCollapsibleGroup(parent, "외형", function(gy)
            y = gy
            AddColor("색상", "color", true)
            return y
        end, y)

        -- Expiring
        y = CreateCollapsibleGroup(parent, "만료 효과", function(gy)
            y = gy
            AddCheck("만료 색상 활성화", "expiringEnabled")
            y = BuildExpiringThresholdRow(parent, y, proxy, W)
            AddColor("만료 색상", "expiringColor", true)
            return y
        end, y)

    elseif typeKey == "healthtext" then
        -- Appearance
        y = CreateCollapsibleGroup(parent, "외형", function(gy)
            y = gy
            AddColor("색상", "color", true)
            return y
        end, y)

        -- Expiring
        y = CreateCollapsibleGroup(parent, "만료 효과", function(gy)
            y = gy
            AddCheck("만료 색상 활성화", "expiringEnabled")
            y = BuildExpiringThresholdRow(parent, y, proxy, W)
            AddColor("만료 색상", "expiringColor", true)
            return y
        end, y)

    elseif typeKey == "framealpha" then
        -- Appearance
        y = CreateCollapsibleGroup(parent, "외형", function(gy)
            y = gy
            AddSlider("투명도", 0, 1, 0.05, "alpha")
            return y
        end, y)

        -- Expiring
        y = CreateCollapsibleGroup(parent, "만료 효과", function(gy)
            y = gy
            AddCheck("만료 투명도 활성화", "expiringEnabled")
            y = BuildExpiringThresholdRow(parent, y, proxy, W)
            AddSlider("만료 투명도", 0, 1, 0.05, "expiringAlpha")
            return y
        end, y)
    end

    y = y - 10
    return math.abs(y)
end

-- ============================================================
-- BUILD LAYOUT GROUPS TAB
-- ============================================================
BuildLayoutGroupsTab = function()
    if not tabContentFrame then return end
    local yPos = -10
    local groups = O.GetSpecLayoutGroups()

    -- "+ 그룹 생성" 버튼 (오렌지 테마)
    local newBtn = CreateFrame("Button", nil, tabContentFrame, "BackdropTemplate")
    newBtn:SetHeight(32)
    newBtn:SetPoint("TOPLEFT", 8, yPos)
    newBtn:SetPoint("RIGHT", tabContentFrame, "RIGHT", -8, 0)
    Widgets:StylizeFrame(newBtn)
    newBtn:SetBackdropColor(0.12, 0.08, 0.03, 1)
    newBtn:SetBackdropBorderColor(0.45, 0.33, 0.12, 0.8)

    local newBtnText = newBtn:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
    newBtnText:SetPoint("CENTER")
    newBtnText:SetText("+ 그룹 생성")
    newBtnText:SetTextColor(0.91, 0.66, 0.25)

    newBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.18, 0.13, 0.06, 1)
        self:SetBackdropBorderColor(0.65, 0.48, 0.20, 1)
        newBtnText:SetTextColor(1, 1, 1)
    end)
    newBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.08, 0.03, 1)
        self:SetBackdropBorderColor(0.45, 0.33, 0.12, 0.8)
        newBtnText:SetTextColor(0.91, 0.66, 0.25)
    end)
    newBtn:SetScript("OnClick", function()
        local group = O.CreateLayoutGroup()
        if group then expandedGroups[group.id] = true end
        SwitchTab("layout")
        ADRefreshAll()
    end)
    yPos = yPos - 42

    if #groups == 0 then
        local empty = tabContentFrame:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
        empty:SetPoint("TOP", tabContentFrame, "TOP", 0, yPos - 30)
        empty:SetWidth(220)
        empty:SetJustifyH("CENTER")
        empty:SetText("레이아웃 그룹이 없습니다.\n'+ 그룹 생성'을 클릭하세요.")
        empty:SetTextColor(0.45, 0.45, 0.50, 0.7)
    else
        for gi, group in ipairs(groups) do
            local isExpanded = expandedGroups[group.id] or false
            local gCard = CreateFrame("Frame", nil, tabContentFrame, "BackdropTemplate")
            gCard:SetPoint("TOPLEFT", 6, yPos)
            gCard:SetPoint("RIGHT", tabContentFrame, "RIGHT", -6, 0)
            Widgets:StylizeFrame(gCard)

            -- 헤더 (셰브론 + 그룹명 + 멤버 수)
            local gHeader = CreateFrame("Button", nil, gCard, "BackdropTemplate")
            gHeader:SetHeight(30)
            gHeader:SetPoint("TOPLEFT", 0, 0)
            gHeader:SetPoint("TOPRIGHT", 0, 0)
            Widgets:StylizeFrame(gHeader)
            gHeader:SetBackdropBorderColor(0.45 * 0.35, 0.33 * 0.35, 0.12 * 0.35, 0.5)

            -- 오렌지 악센트 바
            local gAccent = gHeader:CreateTexture(nil, "ARTWORK")
            gAccent:SetSize(3, 24)
            gAccent:SetPoint("LEFT", 2, 0)
            gAccent:SetColorTexture(0.91, 0.66, 0.25, 0.8)

            -- 셰브론
            local gChevron = gHeader:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
            gChevron:SetPoint("LEFT", 8, 0)
            gChevron:SetText(isExpanded and "▼" or "▶")
            gChevron:SetTextColor(0.91, 0.66, 0.25)

            -- 그룹명 + 멤버 수
            local gTitle = gHeader:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
            gTitle:SetPoint("LEFT", gChevron, "RIGHT", 6, 0)
            gTitle:SetPoint("RIGHT", gHeader, "RIGHT", -30, 0)
            local memberCount = group.members and #group.members or 0
            gTitle:SetText((group.name or ("그룹 " .. group.id)) .. "  —  " .. memberCount .. "개")
            gTitle:SetTextColor(0.85, 0.85, 0.90)

            -- X 삭제 버튼
            local gDel = CreateFrame("Button", nil, gHeader)
            gDel:SetSize(22, 22)
            gDel:SetPoint("RIGHT", -4, 0)
            gDel:SetFrameLevel(gHeader:GetFrameLevel() + 2)
            local gl1 = gDel:CreateTexture(nil, "OVERLAY")
            gl1:SetSize(12, 2)
            gl1:SetPoint("CENTER")
            gl1:SetColorTexture(0.55, 0.20, 0.20, 1)
            gl1:SetRotation(math.rad(45))
            local gl2 = gDel:CreateTexture(nil, "OVERLAY")
            gl2:SetSize(12, 2)
            gl2:SetPoint("CENTER")
            gl2:SetColorTexture(0.55, 0.20, 0.20, 1)
            gl2:SetRotation(math.rad(-45))
            gDel:SetScript("OnEnter", function()
                gl1:SetColorTexture(1, 0.35, 0.35, 1)
                gl2:SetColorTexture(1, 0.35, 0.35, 1)
            end)
            gDel:SetScript("OnLeave", function()
                gl1:SetColorTexture(0.55, 0.20, 0.20, 1)
                gl2:SetColorTexture(0.55, 0.20, 0.20, 1)
            end)
            local capturedGroupID = group.id
            gDel:SetScript("OnClick", function()
                O.DeleteLayoutGroup(capturedGroupID)
                expandedGroups[capturedGroupID] = nil
                SwitchTab("layout")
                ADRefreshAll()
            end)

            -- 헤더 호버
            gHeader:SetScript("OnEnter", function(self)
                self:SetBackdropColor(0.12, 0.12, 0.18, 1)
            end)
            gHeader:SetScript("OnLeave", function(self)
                self:SetBackdropColor(0.07, 0.07, 0.14, 1)
            end)
            gHeader:SetScript("OnClick", function()
                expandedGroups[group.id] = not expandedGroups[group.id]
                SwitchTab("layout")
            end)

            local cardH = 30
            if isExpanded then
                local body = CreateFrame("Frame", nil, gCard)
                body:SetPoint("TOPLEFT", gHeader, "BOTTOMLEFT", 0, 0)
                body:SetPoint("RIGHT", gCard, "RIGHT", 0, 0)

                local by = -8
                -- Anchor dropdown
                local anchorDD = Widgets:CreateDropdown(body, 180)
                anchorDD:SetPoint("TOPLEFT", 8, by)
                anchorDD:SetItems(O.ANCHOR_OPTIONS)
                anchorDD:SetSelected(group.anchor or "TOPLEFT")
                anchorDD:SetOnSelect(function(val) group.anchor = val; ADRefreshAll() end)
                by = by - 28

                -- Offsets
                local oxS = Widgets:CreateSlider("오프셋 X", body, -150, 150, 160, 1,
                    function(v) group.offsetX = v end,
                    function(v) group.offsetX = v; ADRefreshAll() end)
                oxS:SetPoint("TOPLEFT", 8, by)
                oxS:SetValue(group.offsetX or 0)
                by = by - 44

                local oyS = Widgets:CreateSlider("오프셋 Y", body, -150, 150, 160, 1,
                    function(v) group.offsetY = v end,
                    function(v) group.offsetY = v; ADRefreshAll() end)
                oyS:SetPoint("TOPLEFT", 8, by)
                oyS:SetValue(group.offsetY or 0)
                by = by - 44

                -- Growth direction
                local growDD = Widgets:CreateDropdown(body, 180)
                growDD:SetPoint("TOPLEFT", 8, by)
                growDD:SetItems(O.GROWTH_OPTIONS)
                growDD:SetSelected(group.growDirection or "RIGHT")
                growDD:SetOnSelect(function(val) group.growDirection = val; ADRefreshAll() end)
                by = by - 28

                -- Spacing
                local spS = Widgets:CreateSlider("간격", body, 0, 20, 160, 1,
                    function(v) group.spacing = v end,
                    function(v) group.spacing = v; ADRefreshAll() end)
                spS:SetPoint("TOPLEFT", 8, by)
                spS:SetValue(group.spacing or 2)
                by = by - 44

                -- Members
                local memLabel = body:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
                memLabel:SetPoint("TOPLEFT", 8, by)
                memLabel:SetText("멤버:")
                memLabel:SetTextColor(0.5, 0.5, 0.6)
                by = by - 16

                if group.members then
                    for mi, member in ipairs(group.members) do
                        local mRow = CreateFrame("Frame", nil, body)
                        mRow:SetPoint("TOPLEFT", 8, by)
                        mRow:SetPoint("RIGHT", body, "RIGHT", -8, 0)
                        mRow:SetHeight(20)

                        local mText = mRow:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_SMALL")
                        mText:SetPoint("LEFT", 4, 0)
                        mText:SetText(member.auraName .. " #" .. member.indicatorID)

                        -- Remove member (X 텍스쳐)
                        local mDel = CreateFrame("Button", nil, mRow)
                        mDel:SetSize(16, 16)
                        mDel:SetPoint("RIGHT", -2, 0)
                        local ml1 = mDel:CreateTexture(nil, "OVERLAY")
                        ml1:SetSize(8, 1.5)
                        ml1:SetPoint("CENTER")
                        ml1:SetColorTexture(0.50, 0.30, 0.30, 1)
                        ml1:SetRotation(math.rad(45))
                        local ml2 = mDel:CreateTexture(nil, "OVERLAY")
                        ml2:SetSize(8, 1.5)
                        ml2:SetPoint("CENTER")
                        ml2:SetColorTexture(0.50, 0.30, 0.30, 1)
                        ml2:SetRotation(math.rad(-45))
                        mDel:SetScript("OnEnter", function()
                            ml1:SetColorTexture(1, 0.40, 0.40, 1)
                            ml2:SetColorTexture(1, 0.40, 0.40, 1)
                        end)
                        mDel:SetScript("OnLeave", function()
                            ml1:SetColorTexture(0.50, 0.30, 0.30, 1)
                            ml2:SetColorTexture(0.50, 0.30, 0.30, 1)
                        end)
                        local cGID, cAN, cIID = group.id, member.auraName, member.indicatorID
                        mDel:SetScript("OnClick", function()
                            O.RemoveGroupMember(cGID, cAN, cIID)
                            SwitchTab("layout"); ADRefreshAll()
                        end)

                        by = by - 22
                    end
                end

                body:SetHeight(math.abs(by) + 10)
                cardH = cardH + math.abs(by) + 10
            end

            gCard:SetHeight(cardH)
            yPos = yPos - cardH - 4
        end
    end

    tabContentFrame:SetHeight(max(math.abs(yPos) + 20, 200))
end

-- ============================================================
-- BUILD GLOBAL TAB
-- ============================================================
BuildGlobalTab = function()
    if not tabContentFrame then return end
    local adDB = O.GetAuraDesignerDB()
    if not adDB then return end
    if not adDB.defaults then adDB.defaults = {} end
    local defaults = adDB.defaults

    local y = -5
    local W = 230

    local function AddSlider(label, lo, hi, step, key)
        local s = Widgets:CreateSlider(label, tabContentFrame, lo, hi, W, step,
            function(v) defaults[key] = v end,
            function(v) defaults[key] = v; RefreshPlacedIndicators(); ADRefreshAll() end)
        s:SetPoint("TOPLEFT", 8, y)
        s:SetValue(defaults[key] or lo)
        y = y - 44
    end

    local function AddCheck(label, key, defaultVal)
        local cb = Widgets:CreateCheckButton(tabContentFrame, label, function(checked)
            defaults[key] = checked
            RefreshPlacedIndicators(); ADRefreshAll()
        end)
        cb:SetPoint("TOPLEFT", 8, y)
        cb:SetChecked(defaults[key] ~= nil and defaults[key] or defaultVal)
        y = y - 22
    end

    local sep1 = Widgets:CreateSeparator(tabContentFrame, "일반", W)
    sep1:SetPoint("TOPLEFT", 8, y)
    y = y - 22

    AddSlider("기본 아이콘 크기", 8, 64, 1, "iconSize")
    AddSlider("기본 스케일", 0.5, 3.0, 0.05, "iconScale")
    AddCheck("지속시간 표시", "showDuration", true)
    AddCheck("중첩 표시", "showStacks", true)
    AddCheck("쿨다운 숨기기", "hideSwipe", false)

    local sep2 = Widgets:CreateSeparator(tabContentFrame, "액션", W)
    sep2:SetPoint("TOPLEFT", 8, y)
    y = y - 22

    -- Reset All
    local resetBtn = Widgets:CreateButton(tabContentFrame, "모든 오라 설정 초기화", "red", { W, 24 })
    resetBtn:SetPoint("TOPLEFT", 8, y)
    resetBtn:SetScript("OnClick", function()
        local adDB2 = O.GetAuraDesignerDB()
        if adDB2 and adDB2.auras then wipe(adDB2.auras) end
        RefreshPage(); ADRefreshAll()
    end)
    y = y - 30

    tabContentFrame:SetHeight(math.abs(y) + 20)
end

-- ============================================================
-- BUILD AURA DESIGNER PAGE (Main entry point)
-- ============================================================
function ns.BuildAuraDesignerPage(parent)
    O = ns.AuraDesignerOptions
    if O.Init then O:Init() end
    mainFrame = parent

    local AD = ns.AuraDesigner
    local Engine = AD and AD.Engine
    local Presets = AD and AD.Presets

    local yOffset = -50

    -- ===== Enable toggle =====
    local adDB = ns.db.auraDesigner or {}
    local enableCheck = Widgets:CreateCheckButton(parent, "HoT 추적 활성화", function(checked)
        if not ns.db.auraDesigner then
            ns.db.auraDesigner = { enabled = false, spec = "auto", auras = {}, layoutGroups = {}, defaults = {} }
        end
        ns.db.auraDesigner.enabled = checked
        if Engine then
            if checked then Engine:UpdateAllGroupFrames()
            else Engine:ClearAllGroupFrames() end
        end
    end)
    enableCheck:SetPoint("TOPLEFT", 10, yOffset)
    enableCheck:SetChecked(adDB.enabled or false)
    yOffset = yOffset - 28

    -- ===== Spec dropdown =====
    local HOT_SPEC_DISPLAY = {
        ["RestorationDruid"] = "회복 드루이드",
        ["PreservationEvoker"] = "보존 기원사",
        ["AugmentationEvoker"] = "증강 기원사",
        ["HolyPaladin"] = "신성 성기사",
        ["HolyPriest"] = "신성 사제",
        ["DisciplinePriest"] = "수양 사제",
        ["RestorationShaman"] = "복원 주술사",
        ["MistweaverMonk"] = "운무 수도사",
    }

    local specItems = {{ value = "auto", text = "자동 감지" }}
    for _, specKey in ipairs({
        "PreservationEvoker", "AugmentationEvoker", "RestorationDruid",
        "DisciplinePriest", "HolyPriest", "MistweaverMonk",
        "RestorationShaman", "HolyPaladin"
    }) do
        tinsert(specItems, { value = specKey, text = HOT_SPEC_DISPLAY[specKey] or specKey })
    end

    local specLabel = parent:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
    specLabel:SetPoint("TOPLEFT", 10, yOffset)
    specLabel:SetText("전문화:")

    local specDropdown = Widgets:CreateDropdown(parent, 170)
    specDropdown:SetPoint("LEFT", specLabel, "RIGHT", 8, 0)
    specDropdown:SetItems(specItems)
    specDropdown:SetSelected(adDB.spec or "auto")
    specDropdown:SetOnSelect(function(value)
        if not ns.db.auraDesigner then ns.db.auraDesigner = {} end
        ns.db.auraDesigner.spec = value
        wipe(expandedCards)
        RefreshPage()
    end)

    -- Preset restore button
    local presetBtn = Widgets:CreateButton(parent, "프리셋 복원", "accent", { 85, 22 })
    presetBtn:SetPoint("LEFT", specDropdown, "RIGHT", 10, 0)
    presetBtn:SetScript("OnClick", function()
        local spec = O.ResolveSpec()
        if Presets and spec then
            Presets:ResetToPreset(spec)
            RefreshPage(); ADRefreshAll()
        end
    end)

    yOffset = yOffset - 32

    -- ===== Layout: left (preview) + right (tabs) =====
    local RIGHT_PANEL_W = 290

    -- Right panel (tabs + content)
    rightPanel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    rightPanel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, yOffset)
    rightPanel:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    rightPanel:SetWidth(RIGHT_PANEL_W)
    Widgets:StylizeFrame(rightPanel)

    -- Tab bar
    tabBar = CreateFrame("Frame", nil, rightPanel)
    tabBar:SetPoint("TOPLEFT", 0, 0)
    tabBar:SetPoint("TOPRIGHT", 0, 0)
    tabBar:SetHeight(28)

    tabButtons = {}
    local tabs = {
        { key = "effects", label = "효과" },
        { key = "layout",  label = "레이아웃" },
        { key = "global",  label = "글로벌" },
    }
    local tabW = RIGHT_PANEL_W / #tabs
    for i, tab in ipairs(tabs) do
        local btn = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
        btn:SetSize(tabW, 26)
        btn:SetPoint("TOPLEFT", (i-1) * tabW, 0)
        Widgets:StylizeFrame(btn)
        local lbl = btn:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
        lbl:SetPoint("CENTER")
        lbl:SetText(tab.label)
        btn.label = lbl
        local capturedKey = tab.key
        btn:SetScript("OnClick", function() SwitchTab(capturedKey) end)
        tabButtons[tab.key] = btn
    end

    -- Scroll frame for tab content
    local scrollFrame = CreateFrame("ScrollFrame", nil, rightPanel)
    scrollFrame:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", rightPanel, "BOTTOMRIGHT", 0, 0)
    scrollFrame:EnableMouseWheel(true)
    tabScrollFrame = scrollFrame

    tabContentFrame = CreateFrame("Frame", nil, scrollFrame)
    tabContentFrame:SetWidth(RIGHT_PANEL_W - 2)
    tabContentFrame:SetHeight(1)
    scrollFrame:SetScrollChild(tabContentFrame)

    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxS = max(0, tabContentFrame:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(max(0, min(maxS, cur - delta * 40)))
    end)

    -- Spell picker overlay
    spellPickerView = CreateFrame("Frame", nil, rightPanel, "BackdropTemplate")
    spellPickerView:SetAllPoints(rightPanel)
    spellPickerView:SetFrameLevel(rightPanel:GetFrameLevel() + 5)
    Widgets:StylizeFrame(spellPickerView)
    spellPickerView:Hide()

    local spTitle = spellPickerView:CreateFontString(nil, "OVERLAY", "DDINGUI_UF_FONT_NORMAL")
    spTitle:SetPoint("TOPLEFT", 10, -8)
    spTitle:SetText("스펠 선택")
    spellPickerView.title = spTitle

    local spBack = Widgets:CreateButton(spellPickerView, "← 돌아가기", "accent-hover", { 90, 22 })
    spBack:SetPoint("TOPRIGHT", -5, -5)
    spBack:SetScript("OnClick", function() HideSpellPicker() end)

    local spScroll = CreateFrame("ScrollFrame", nil, spellPickerView)
    spScroll:SetPoint("TOPLEFT", 0, -32)
    spScroll:SetPoint("BOTTOMRIGHT", 0, 0)
    spScroll:EnableMouseWheel(true)

    local spGrid = CreateFrame("Frame", nil, spScroll)
    spGrid:SetWidth(RIGHT_PANEL_W - 2)
    spGrid:SetHeight(1)
    spScroll:SetScrollChild(spGrid)
    spellPickerView.gridFrame = spGrid

    spScroll:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxS = max(0, spGrid:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(max(0, min(maxS, cur - delta * 40)))
    end)

    -- Left panel (frame preview)
    framePreview = CreateFramePreview(parent, yOffset, RIGHT_PANEL_W + 6)
    leftPanel = framePreview

    -- Initial build
    SwitchTab("effects")
    RefreshPlacedIndicators()
    RefreshPreviewEffects()

    -- [FIX] 라이브 프리뷰 타이머 시작 (쿨다운 순환 애니메이션)
    StartPreviewTimer()
    parent:HookScript("OnHide", function()
        StopPreviewTimer()
    end)

    parent:SetHeight(math.abs(yOffset) + 500)
end

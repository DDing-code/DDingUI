local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local LibEditModeOverride = LibStub("LibEditModeOverride-1.0", true)
local strtrim = strtrim

-- Advanced positioning state (copied from EditModeMore style)
local advanced = {
    point = "CENTER",
    attachPoint = "CENTER",
    attachFrame = UIParent,
    xOffset = 0,
    yOffset = 0,
    scale = 1, -- size of 1 px in UI units
}

local advancedUI = {}
local NudgeFrame

local function toActualPixel(value)
    return math.floor(value / advanced.scale + 0.5)
end

local function toRoundedNumber(text)
    local num = tonumber(text)
    if num == nil then
        return nil
    else
        -- 소숫점 1자리까지 허용 (0.1 단위)
        return math.floor(num * 10 + 0.5) / 10
    end
end

local function updateScale()
    local _, height = GetPhysicalScreenSize()
    local uiScale = UIParent:GetScale()

    advanced.scale = 768 / uiScale / height -- size of 1 px
end

-- Store the currently selected frame
local currentSelectedFrame = nil
local currentSelectedFrameName = nil
local lastUpdatedFrame = nil -- Track when we last updated the advanced UI

-- Click detector frame (like EditModeTweaks)
local clickDetector = CreateFrame("Frame")
clickDetector:Hide()
local lastMouseOverFrame = nil

-- Walk up frame hierarchy to find a frame with systemInfo (Edit Mode system frame)
local function FindSystemFrame(frame)
    if not frame then return nil end
    
    -- Root frames we should never select and should stop at
    local rootFrames = {
        UIParent = true,
        WorldFrame = true,
        GlueParent = true,
    }
    
    local currentFrame = frame
    local maxDepth = 20 -- Prevent infinite loops
    local depth = 0
    local bestFrame = nil
    
    while currentFrame and depth < maxDepth do
        local frameName = currentFrame:GetName()
        
        -- Stop if we hit a root frame
        if frameName and rootFrames[frameName] then
            break
        end
        
        -- Check if this frame has systemInfo (Edit Mode system frame)
        if currentFrame.systemInfo then
            bestFrame = currentFrame
            -- Continue walking up to see if there's a better parent with systemInfo
        end
        
        -- Try to get the parent
        local parent = currentFrame:GetParent()
        if not parent or parent == currentFrame then
            break
        end
        currentFrame = parent
        depth = depth + 1
    end
    
    return bestFrame
end

-- Select a frame for nudging (based on EditModeTweaks approach)
local function SelectFrame(frame)
    if not frame then return end

    -- Filter out frames we don't want to select
    local frameName = frame:GetName()
    local nudgeFrameName = ADDON_NAME .. "NudgeFrame"
    if frameName == nudgeFrameName or
       frameName == "EditModeManagerFrame" or
       frameName == "EditModeSystemSettingsDialog" or
       (NudgeFrame and frame == NudgeFrame) or
       (EditModeManagerFrame and frame == EditModeManagerFrame) then
        return
    end

    -- 알려진 CooldownViewer 프레임이면 직접 사용
    local knownViewers = {
        ["EssentialCooldownViewer"] = true,
        ["UtilityCooldownViewer"] = true,
        ["BuffIconCooldownViewer"] = true,
    }
    if frameName and knownViewers[frameName] then
        currentSelectedFrame = frame
        currentSelectedFrameName = frameName
        return
    end

    -- Walk up the hierarchy to find the Edit Mode system frame
    local systemFrame = FindSystemFrame(frame)

    if systemFrame then
        currentSelectedFrame = systemFrame
        currentSelectedFrameName = systemFrame:GetName() or "Anonymous Frame"
    else
        -- If no system frame found, use the clicked frame if it has systemInfo
        -- or if it's a named frame that could be positioned
        if frame.systemInfo or (frameName and frameName ~= "" and frame.SetPoint) then
            currentSelectedFrame = frame
            currentSelectedFrameName = frameName or "Anonymous Frame"
        else
            currentSelectedFrame = nil
            currentSelectedFrameName = nil
        end
    end
end

-- Scan for frames with isSelected = true (Edit Mode's selection)
local function ScanForSelectedFrame()
    if not EditModeManagerFrame or not EditModeManagerFrame.editModeActive then
        return nil
    end

    -- 방법 0: EditModeSystemSettingsDialog에서 직접 가져오기 (여러 속성 시도)
    if EditModeSystemSettingsDialog and EditModeSystemSettingsDialog:IsShown() then
        -- 여러 가능한 속성 이름 시도
        local possibleProps = {"attachedToSystem", "system", "systemFrame", "selectedSystem", "editModeSystem"}
        for _, prop in ipairs(possibleProps) do
            local ok, sys = pcall(function()
                return EditModeSystemSettingsDialog[prop]
            end)
            if ok and sys and type(sys) == "table" and sys.GetName then
                return sys
            end
        end
    end

    -- 방법 1: EditModeManagerFrame의 내부 선택 상태 확인
    local success, selectedSystem = pcall(function()
        if EditModeManagerFrame.selectedSystem then
            return EditModeManagerFrame.selectedSystem
        end
        return nil
    end)
    if success and selectedSystem then
        return selectedSystem
    end

    -- 방법 2: 알려진 CooldownViewer 프레임들 - Selection 박스 체크
    local knownViewers = {
        "EssentialCooldownViewer",
        "UtilityCooldownViewer",
        "BuffIconCooldownViewer",
    }
    for _, viewerName in ipairs(knownViewers) do
        local viewer = _G[viewerName]
        if viewer then
            -- Selection 박스가 보이는지 확인 (더 안전한 방법)
            local ok, hasSelection = pcall(function()
                if viewer.Selection and viewer.Selection:IsShown() then
                    return true
                end
                if viewer.HighlightTexture and viewer.HighlightTexture:IsShown() then
                    return true
                end
                return false
            end)
            if ok and hasSelection then
                return viewer
            end
        end
    end

    -- 방법 3: 클릭 감지로 fallback (OnUpdate에서 처리)
    return nil
end

-- Enable click detection when Edit Mode is active
local function EnableClickDetection()
    if not EditModeManagerFrame or not EditModeManagerFrame.editModeActive then
        return
    end
    
    clickDetector:Show()
    clickDetector:SetScript("OnUpdate", function(self, elapsed)
        -- First, check for Edit Mode's isSelected frames (priority)
        local editModeSelected = ScanForSelectedFrame()
        local nudgeFrame = _G[ADDON_NAME .. "NudgeFrame"] or DDingUI.nudgeFrame
        
        if editModeSelected then
            -- Only update when selection changes
            if currentSelectedFrame ~= editModeSelected then
                currentSelectedFrame = editModeSelected
                currentSelectedFrameName = editModeSelected:GetName() or "Anonymous Frame"
                if nudgeFrame then
                    nudgeFrame:UpdateVisibility()
                end
            end
        else
            -- No Edit Mode selection - clear it and refresh the embedded panel
            if currentSelectedFrame then
                currentSelectedFrame = nil
                currentSelectedFrameName = nil
                if nudgeFrame then
                    nudgeFrame:UpdateVisibility()
                end
            end
            
            -- If no Edit Mode selection, use click detection
            if IsMouseButtonDown("LeftButton") then
                local frames = GetMouseFoci()
                if frames and #frames > 0 then
                    local frame = frames[1]
                    if frame and frame ~= WorldFrame and frame ~= lastMouseOverFrame then
                        lastMouseOverFrame = frame
                        SelectFrame(frame)
                        -- Update nudge frame display
                        if nudgeFrame then
                            nudgeFrame:UpdateVisibility()
                        end
                    end
                end
            else
                lastMouseOverFrame = nil
            end
        end
    end)
end

-- Disable click detection when Edit Mode is inactive
local function DisableClickDetection()
    clickDetector:Hide()
    clickDetector:SetScript("OnUpdate", nil)
    lastMouseOverFrame = nil
    currentSelectedFrame = nil
    currentSelectedFrameName = nil
end

local function GetSelectedEditModeFrame()
    return currentSelectedFrame, currentSelectedFrameName
end

local function GetFrameDisplayName(frame, frameName)
    if not frame then return "No frame selected" end
    
    frameName = frameName or frame:GetName()
    if not frameName or frameName == "Anonymous Frame" then
        return "Selected Frame"
    end
    
    -- Try to get a nice display name
    if frameName == "PlayerFrame" then
        return "Player"
    elseif frameName == "TargetFrame" then
        return "Target"
    elseif frameName == "FocusFrame" then
        return "Focus"
    elseif frameName == "PetFrame" then
        return "Pet"
    else
        return frameName:gsub("CooldownViewer", ""):gsub("Icon", " Icon")
    end
end

-- Helpers for EditModeMore style UI
local function setupLabel(label)
    label:SetJustifyH("LEFT")
    label:SetJustifyV("MIDDLE")
end

local function setupEditBox(editBox)
    editBox:SetAutoFocus(false)
    editBox:EnableKeyboard(true)
    editBox:SetPropagateKeyboardInput(false)

    editBox:SetScript("OnEditFocusGained", function(self)
        advanced.oldText = self:GetText()
    end)
    editBox:HookScript("OnEscapePressed", function(self)
        self:SetText(advanced.oldText)
        self:ClearFocus()
    end)
end

local function setupPointDropdown(dropdown)
    local function isSelected(index)
        if advanced.point == "CENTER" then
            return index == 0
        elseif advanced.point == "TOP" then
            return index == 1
        elseif advanced.point == "BOTTOM" then
            return index == 2
        elseif advanced.point == "LEFT" then
            return index == 3
        elseif advanced.point == "RIGHT" then
            return index == 4
        elseif advanced.point == "TOPLEFT" then
            return index == 5
        elseif advanced.point == "TOPRIGHT" then
            return index == 6
        elseif advanced.point == "BOTTOMLEFT" then
            return index == 7
        elseif advanced.point == "BOTTOMRIGHT" then
            return index == 8
        end
    end

    local function SetSelected(index)
        if index == 0 then
            advanced.point = "CENTER"
        elseif index == 1 then
            advanced.point = "TOP"
        elseif index == 2 then
            advanced.point = "BOTTOM"
        elseif index == 3 then
            advanced.point = "LEFT"
        elseif index == 4 then
            advanced.point = "RIGHT"
        elseif index == 5 then
            advanced.point = "TOPLEFT"
        elseif index == 6 then
            advanced.point = "TOPRIGHT"
        elseif index == 7 then
            advanced.point = "BOTTOMLEFT"
        elseif index == 8 then
            advanced.point = "BOTTOMRIGHT"
        end

        DDingUI:ApplyAdvancedNudgeSettings()
    end

    dropdown:SetupMenu(function(_, rootDescription)
        rootDescription:CreateRadio("CENTER", isSelected, SetSelected, 0);
        rootDescription:CreateRadio("TOP", isSelected, SetSelected, 1);
        rootDescription:CreateRadio("BOTTOM", isSelected, SetSelected, 2);
        rootDescription:CreateRadio("LEFT", isSelected, SetSelected, 3);
        rootDescription:CreateRadio("RIGHT", isSelected, SetSelected, 4);
        rootDescription:CreateRadio("TOPLEFT", isSelected, SetSelected, 5);
        rootDescription:CreateRadio("TOPRIGHT", isSelected, SetSelected, 6);
        rootDescription:CreateRadio("BOTTOMLEFT", isSelected, SetSelected, 7);
        rootDescription:CreateRadio("BOTTOMRIGHT", isSelected, SetSelected, 8);
    end)
end

local function setupRelativePointDropdown(dropdown)
    local function isSelected(index)
        if advanced.attachPoint == "CENTER" then
            return index == 0
        elseif advanced.attachPoint == "TOP" then
            return index == 1
        elseif advanced.attachPoint == "BOTTOM" then
            return index == 2
        elseif advanced.attachPoint == "LEFT" then
            return index == 3
        elseif advanced.attachPoint == "RIGHT" then
            return index == 4
        elseif advanced.attachPoint == "TOPLEFT" then
            return index == 5
        elseif advanced.attachPoint == "TOPRIGHT" then
            return index == 6
        elseif advanced.attachPoint == "BOTTOMLEFT" then
            return index == 7
        elseif advanced.attachPoint == "BOTTOMRIGHT" then
            return index == 8
        end
    end

    local function SetSelected(index)
        if index == 0 then
            advanced.attachPoint = "CENTER"
        elseif index == 1 then
            advanced.attachPoint = "TOP"
        elseif index == 2 then
            advanced.attachPoint = "BOTTOM"
        elseif index == 3 then
            advanced.attachPoint = "LEFT"
        elseif index == 4 then
            advanced.attachPoint = "RIGHT"
        elseif index == 5 then
            advanced.attachPoint = "TOPLEFT"
        elseif index == 6 then
            advanced.attachPoint = "TOPRIGHT"
        elseif index == 7 then
            advanced.attachPoint = "BOTTOMLEFT"
        elseif index == 8 then
            advanced.attachPoint = "BOTTOMRIGHT"
        end

        DDingUI:ApplyAdvancedNudgeSettings()
    end

    dropdown:SetupMenu(function(_, rootDescription)
        rootDescription:CreateRadio("CENTER", isSelected, SetSelected, 0);
        rootDescription:CreateRadio("TOP", isSelected, SetSelected, 1);
        rootDescription:CreateRadio("BOTTOM", isSelected, SetSelected, 2);
        rootDescription:CreateRadio("LEFT", isSelected, SetSelected, 3);
        rootDescription:CreateRadio("RIGHT", isSelected, SetSelected, 4);
        rootDescription:CreateRadio("TOPLEFT", isSelected, SetSelected, 5);
        rootDescription:CreateRadio("TOPRIGHT", isSelected, SetSelected, 6);
        rootDescription:CreateRadio("BOTTOMLEFT", isSelected, SetSelected, 7);
        rootDescription:CreateRadio("BOTTOMRIGHT", isSelected, SetSelected, 8);
    end)
end

local function setAdvancedEnabled(enabled)
    if not advancedUI then return end
    local method = enabled and "Enable" or "Disable"
    if advancedUI.pointDropdown then advancedUI.pointDropdown[method](advancedUI.pointDropdown) end
    if advancedUI.attachFrameEditBox then advancedUI.attachFrameEditBox[method](advancedUI.attachFrameEditBox) end
    if advancedUI.attachPointDropdown then advancedUI.attachPointDropdown[method](advancedUI.attachPointDropdown) end
    if advancedUI.frameNameEditBox then advancedUI.frameNameEditBox[method](advancedUI.frameNameEditBox) end
end

local function resolveFrame(frameOrName)
    if type(frameOrName) == "string" then
        return _G[frameOrName]
    end
    return frameOrName
end

function DDingUI:ApplyAdvancedNudgeSettings()
    local selectedFrame = currentSelectedFrame
    if not selectedFrame or not selectedFrame.systemInfo then return end

    -- Bail out early if frame cannot be moved (matches EditModeMore behavior)
    if selectedFrame.CanBeMoved and not selectedFrame:CanBeMoved() then
        return
    end

    -- Managed frames must be broken out before we can change anchors
    if selectedFrame.isManagedFrame and selectedFrame:IsInDefaultPosition() then
        if selectedFrame.BreakFromFrameManager then
            selectedFrame:BreakFromFrameManager()
        end
    end

    -- Clear any snapping/drag state so the new anchor sticks immediately
    if selectedFrame.ClearFrameSnap then
        selectedFrame:ClearFrameSnap()
    end
    if selectedFrame.StopMovingOrSizing then
        selectedFrame:StopMovingOrSizing()
    end

    -- ensure frame reference is valid
    local attachFrameObj = resolveFrame(advanced.attachFrame) or UIParent

    -- 자기 자신에게 anchor하려는 시도 방지
    if attachFrameObj == selectedFrame then
        attachFrameObj = UIParent
    end

    advanced.attachFrame = attachFrameObj

    -- Use LEMO for taint-safe reanchoring (WoW 12.0+: direct writes to systemInfo.anchorInfo
    -- or hasActiveChanges cause secret value errors in HideSystemSelections)
    local lemoSaved = false
    if LibEditModeOverride and LibEditModeOverride.AreLayoutsLoaded and LibEditModeOverride:AreLayoutsLoaded() then
        local ok = pcall(function()
            LibEditModeOverride:ReanchorFrame(selectedFrame, advanced.point, attachFrameObj, advanced.attachPoint, advanced.xOffset, advanced.yOffset)
            LibEditModeOverride:SaveOnly()
        end)
        lemoSaved = ok
    end

    -- Visual move (immediate feedback) — SetPoint on EditMode frames is safe outside combat
    selectedFrame:ClearAllPoints()
    selectedFrame:SetPoint(advanced.point, attachFrameObj, advanced.attachPoint, advanced.xOffset, advanced.yOffset)

    -- Notify EditMode of position change (safe method calls, not property writes)
    pcall(function()
        if selectedFrame.OnSystemPositionChange then
            selectedFrame:OnSystemPositionChange()
        elseif EditModeManagerFrame and EditModeManagerFrame.OnSystemPositionChange then
            EditModeManagerFrame:OnSystemPositionChange(selectedFrame)
        end
    end)

    if self.nudgeFrame and self.nudgeFrame:IsShown() then
        self.nudgeFrame:UpdateInfo()
        self.nudgeFrame:UpdatePosition()
    end
end

local function updateAdvancedFromSelection()
    if not advancedUI or not advancedUI.pointDropdown then return end
    local selectedFrame = currentSelectedFrame
    if not selectedFrame then
        setAdvancedEnabled(false)
        if advancedUI.frameNameEditBox then advancedUI.frameNameEditBox:SetText("") end
        if advancedUI.attachFrameEditBox then advancedUI.attachFrameEditBox:SetText("") end
        if advancedUI.pointDropdown then advancedUI.pointDropdown:GenerateMenu() end
        if advancedUI.attachPointDropdown then advancedUI.attachPointDropdown:GenerateMenu() end
        return
    end

    -- 먼저 활성화 (이후 에러가 나도 활성화 상태 유지)
    setAdvancedEnabled(true)
    updateScale()

    -- GetPoint를 pcall로 보호
    local anchor = selectedFrame.systemInfo and selectedFrame.systemInfo.anchorInfo or {}
    local point, relativeTo, relativePoint, xOfs, yOfs

    local ok, err = pcall(function()
        point, relativeTo, relativePoint, xOfs, yOfs = selectedFrame:GetPoint(1)
    end)

    if not ok then
        -- GetPoint 실패 시 기본값 사용
        point = "CENTER"
        relativeTo = UIParent
        relativePoint = "CENTER"
        xOfs = 0
        yOfs = 0
    end

    advanced.point = point or anchor.point or "CENTER"
    advanced.attachPoint = relativePoint or anchor.relativePoint or advanced.point

    -- attachFrame 결정: 자기 자신에게 anchor된 경우 UIParent 사용
    local resolvedAttachFrame = resolveFrame(relativeTo or anchor.relativeTo or UIParent) or UIParent
    if resolvedAttachFrame == selectedFrame then
        resolvedAttachFrame = UIParent
    end
    advanced.attachFrame = resolvedAttachFrame

    -- GetPoint 값 우선 (anchorInfo는 LEMO 넛지 후 스테일 될 수 있음)
    advanced.xOffset = xOfs or anchor.offsetX or 0
    advanced.yOffset = yOfs or anchor.offsetY or 0

    -- UI 업데이트도 pcall로 보호
    pcall(function()
        advancedUI.pointDropdown:GenerateMenu()
        advancedUI.attachPointDropdown:GenerateMenu()

        local attachFrameName = "UIParent"
        if advanced.attachFrame and advanced.attachFrame.GetName then
            attachFrameName = advanced.attachFrame:GetName() or "UIParent"
        end
        advancedUI.attachFrameEditBox:SetText(attachFrameName)

        local frameName = "Frame"
        if selectedFrame and selectedFrame.GetName then
            frameName = selectedFrame:GetName() or "Frame"
        end
        advancedUI.frameNameEditBox:SetText(frameName)
    end)
end

local function createAdvancedControls(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -168)
    frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -168)
    frame:SetHeight(110)

    -- point
    local pointContainer = CreateFrame("Frame", nil, frame)
    pointContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    pointContainer:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    pointContainer:SetHeight(26)

    local pointLabel = pointContainer:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    setupLabel(pointLabel)
    pointLabel:SetText("Self Point")
    pointLabel:SetPoint("TOPLEFT", pointContainer, "TOPLEFT", 0, 0)
    pointLabel:SetSize(90, 24)

    local pointDropdown = CreateFrame("DropdownButton", nil, pointContainer, "WowStyle1DropdownTemplate")
    setupPointDropdown(pointDropdown)
    pointDropdown:SetPoint("LEFT", pointLabel, "RIGHT", 4, 0)
    pointDropdown:SetSize(210, 22)

    -- attach frame
    local attachFrameContainer = CreateFrame("Frame", nil, frame)
    attachFrameContainer:SetPoint("TOPLEFT", pointContainer, "BOTTOMLEFT", 0, -6)
    attachFrameContainer:SetPoint("TOPRIGHT", pointContainer, "BOTTOMRIGHT", 0, -6)
    attachFrameContainer:SetHeight(26)

    local attachFrameLabel = attachFrameContainer:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    setupLabel(attachFrameLabel)
    attachFrameLabel:SetText("Anchor to")
    attachFrameLabel:SetPoint("TOPLEFT", attachFrameContainer, "TOPLEFT", 0, 0)
    attachFrameLabel:SetSize(90, 24)

    local attachFrameEditBox = CreateFrame("EditBox", nil, attachFrameContainer, "InputBoxTemplate")
    setupEditBox(attachFrameEditBox)
    attachFrameEditBox:SetPoint("LEFT", attachFrameLabel, "RIGHT", 6, 0)
    attachFrameEditBox:SetSize(210, 22)
    attachFrameEditBox:SetScript("OnEnterPressed", function(self)
        local frameName = strtrim(self:GetText() or "")
        local target = frameName == "UIParent" and UIParent or _G[frameName]

        -- Accept any real frame (C_Widget.IsFrameWidget when available)
        local isFrame = target ~= nil
            and type(target) == "table"
            and ((C_Widget and C_Widget.IsFrameWidget and C_Widget.IsFrameWidget(target)) or target.GetObjectType)

        if isFrame then
            advanced.attachFrame = target
            DDingUI:ApplyAdvancedNudgeSettings()
        else
            self:SetText(advanced.oldText)
        end

        self:ClearFocus()
    end)

    -- attach point
    local attachPointContainer = CreateFrame("Frame", nil, frame)
    attachPointContainer:SetPoint("TOPLEFT", attachFrameContainer, "BOTTOMLEFT", 0, -6)
    attachPointContainer:SetPoint("TOPRIGHT", attachFrameContainer, "BOTTOMRIGHT", 0, -6)
    attachPointContainer:SetHeight(26)

    local attachPointLabel = attachPointContainer:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    setupLabel(attachPointLabel)
    attachPointLabel:SetText("Anchor Point")
    attachPointLabel:SetPoint("TOPLEFT", attachPointContainer, "TOPLEFT", 0, 0)
    attachPointLabel:SetSize(90, 24)

    local attachPointDropdown = CreateFrame("DropdownButton", nil, attachPointContainer, "WowStyle1DropdownTemplate")
    setupRelativePointDropdown(attachPointDropdown)
    attachPointDropdown:SetPoint("LEFT", attachPointLabel, "RIGHT", 4, 0)
    attachPointDropdown:SetSize(210, 22)

    -- frame name copy
    local frameNameContainer = CreateFrame("Frame", nil, frame)
    frameNameContainer:SetPoint("TOPLEFT", attachPointContainer, "BOTTOMLEFT", 0, -6)
    frameNameContainer:SetPoint("TOPRIGHT", attachPointContainer, "BOTTOMRIGHT", 0, -6)
    frameNameContainer:SetHeight(26)

    local frameNameLabel = frameNameContainer:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    setupLabel(frameNameLabel)
    frameNameLabel:SetText("Frame Name")
    frameNameLabel:SetPoint("TOPLEFT", frameNameContainer, "TOPLEFT", 0, 0)
    frameNameLabel:SetSize(90, 24)

    local frameNameEditBox = CreateFrame("EditBox", nil, frameNameContainer, "InputBoxTemplate")
    setupEditBox(frameNameEditBox)
    frameNameEditBox:SetPoint("LEFT", frameNameLabel, "RIGHT", 6, 0)
    frameNameEditBox:SetSize(210, 22)
    frameNameEditBox:SetScript("OnEnterPressed", function(self)
        self:SetText(advanced.oldText)
        self:ClearFocus()
    end)

    advancedUI.pointDropdown = pointDropdown
    advancedUI.attachFrameEditBox = attachFrameEditBox
    advancedUI.attachPointDropdown = attachPointDropdown
    advancedUI.frameNameEditBox = frameNameEditBox

    setAdvancedEnabled(false)
end

local function UpdateSettingsDialogLayout()
    if not NudgeFrame or not EditModeSystemSettingsDialog then return end

    NudgeFrame:SetParent(EditModeSystemSettingsDialog)
    NudgeFrame:SetFrameStrata(EditModeSystemSettingsDialog:GetFrameStrata())
    NudgeFrame:SetFrameLevel(EditModeSystemSettingsDialog:GetFrameLevel())

    NudgeFrame:ClearAllPoints()
    local anchor = EditModeSystemSettingsDialog.Buttons or EditModeSystemSettingsDialog
    NudgeFrame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    NudgeFrame:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", 0, -2)

    if EditModeSystemSettingsDialog:GetTop() and NudgeFrame:GetBottom() then
        EditModeSystemSettingsDialog:SetHeight(EditModeSystemSettingsDialog:GetTop() - NudgeFrame:GetBottom() + 20)
    end
end

local function HookSettingsDialog()
    if not EditModeSystemSettingsDialog or (NudgeFrame and NudgeFrame._settingsHooked) then
        return
    end

    NudgeFrame._settingsHooked = true

    EditModeSystemSettingsDialog:HookScript("OnShow", function()
        UpdateSettingsDialogLayout()
        NudgeFrame:UpdateVisibility()
    end)

    EditModeSystemSettingsDialog:HookScript("OnHide", function()
        NudgeFrame:Hide()
    end)

    hooksecurefunc(EditModeSystemSettingsDialog, "UpdateDialog", function()
        UpdateSettingsDialogLayout()
        NudgeFrame:UpdateVisibility()
    end)
end

local nudgeParent = EditModeSystemSettingsDialog or UIParent
NudgeFrame = CreateFrame("Frame", ADDON_NAME .. "NudgeFrame", nudgeParent, "BackdropTemplate")
DDingUI.nudgeFrame = NudgeFrame

-- Slightly roomier footprint for clarity
NudgeFrame:SetHeight(300)
NudgeFrame:SetFrameStrata("DIALOG")
NudgeFrame:EnableMouse(true)
NudgeFrame:Hide()

function NudgeFrame:UpdatePosition()
    if EditModeSystemSettingsDialog then
        UpdateSettingsDialogLayout()
    else
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

local title = NudgeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOP", 0, -8)
title:SetText("Nudge Frame")

-- Keep an info slot for future use but hide it (frame name edit box serves as display)
local infoText = NudgeFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
infoText:Hide()
NudgeFrame.infoText = infoText

local coordsContainer = CreateFrame("Frame", nil, NudgeFrame)
coordsContainer:SetPoint("TOP", title, "BOTTOM", 0, -10)
coordsContainer:SetSize(240, 28)
NudgeFrame.coordsContainer = coordsContainer

local xLabel = coordsContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
xLabel:SetPoint("LEFT", coordsContainer, "LEFT", 0, 0)
xLabel:SetWidth(14)
xLabel:SetJustifyH("LEFT")
xLabel:SetText("X")

local xEditBox = CreateFrame("EditBox", nil, coordsContainer, "InputBoxTemplate")
setupEditBox(xEditBox)
xEditBox:SetPoint("LEFT", xLabel, "RIGHT", 4, 0)
xEditBox:SetSize(80, 24)
xEditBox:SetScript("OnEnterPressed", function(self)
    local val = toRoundedNumber(self:GetText())
    if val == nil then
        self:SetText(advanced.oldText or "")
    else
        advanced.xOffset = val
        DDingUI:ApplyAdvancedNudgeSettings()
    end
    self:ClearFocus()
end)
NudgeFrame.xEditBox = xEditBox

local yLabel = coordsContainer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
yLabel:SetPoint("LEFT", xEditBox, "RIGHT", 12, 0)
yLabel:SetWidth(14)
yLabel:SetJustifyH("LEFT")
yLabel:SetText("Y")

local yEditBox = CreateFrame("EditBox", nil, coordsContainer, "InputBoxTemplate")
setupEditBox(yEditBox)
yEditBox:SetPoint("LEFT", yLabel, "RIGHT", 4, 0)
yEditBox:SetSize(80, 24)
yEditBox:SetScript("OnEnterPressed", function(self)
    local val = toRoundedNumber(self:GetText())
    if val == nil then
        self:SetText(advanced.oldText or "")
    else
        advanced.yOffset = val
        DDingUI:ApplyAdvancedNudgeSettings()
    end
    self:ClearFocus()
end)
NudgeFrame.yEditBox = yEditBox

local function CreateArrowButton(parent, direction, anchorFrame, x, yOffset)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(28, 28)
    if anchorFrame then
        button:SetPoint("TOP", anchorFrame, "BOTTOM", x, yOffset or -10)
    else
        button:SetPoint("TOP", parent, "TOP", x, yOffset or -10)
    end
    
    button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    
    local texture = button:GetNormalTexture()
    if direction == "UP" then
        texture:SetRotation(math.rad(90))
        button:GetPushedTexture():SetRotation(math.rad(90))
    elseif direction == "DOWN" then
        texture:SetRotation(math.rad(270))
        button:GetPushedTexture():SetRotation(math.rad(270))
    elseif direction == "LEFT" then
        texture:SetRotation(math.rad(180))
        button:GetPushedTexture():SetRotation(math.rad(180))
    elseif direction == "RIGHT" then
        texture:SetRotation(math.rad(0))
        button:GetPushedTexture():SetRotation(math.rad(0))
    end
    
    button:SetScript("OnClick", function()
        DDingUI:NudgeSelectedFrame(direction)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)
    
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Nudge " .. direction:lower())
        GameTooltip:AddLine("Move selected frame 1 pixel " .. direction:lower(), 1, 1, 1)
        GameTooltip:Show()
    end)
    
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    return button
end

-- Tighten arrow cluster spacing
local arrowAnchor = coordsContainer
NudgeFrame.upButton = CreateArrowButton(NudgeFrame, "UP", arrowAnchor, 0, -10)
NudgeFrame.downButton = CreateArrowButton(NudgeFrame, "DOWN", arrowAnchor, 0, -58)
NudgeFrame.leftButton = CreateArrowButton(NudgeFrame, "LEFT", arrowAnchor, -24, -34)
NudgeFrame.rightButton = CreateArrowButton(NudgeFrame, "RIGHT", arrowAnchor, 24, -34)

-- advanced controls (EditModeMore copy)
createAdvancedControls(NudgeFrame)

function NudgeFrame:UpdateInfo()
    local selectedFrame, frameName = GetSelectedEditModeFrame()

    if selectedFrame then
        -- Always read from GetPoint (reflects actual position after nudges;
        -- systemInfo.anchorInfo goes stale after LEMO:ReanchorFrame)
        local xOfs, yOfs = 0, 0

        local ok = pcall(function()
            local _, _, _, x, y = selectedFrame:GetPoint(1)
            xOfs = x or 0
            yOfs = y or 0
        end)

        if not ok then
            xOfs, yOfs = 0, 0
        end

        advanced.xOffset = xOfs
        advanced.yOffset = yOfs
        if self.xEditBox then
            self.xEditBox:SetText(string.format("%.1f", xOfs))
            self.xEditBox:Enable()
        end
        if self.yEditBox then
            self.yEditBox:SetText(string.format("%.1f", yOfs))
            self.yEditBox:Enable()
        end

        self.upButton:Enable()
        self.downButton:Enable()
        self.leftButton:Enable()
        self.rightButton:Enable()

        -- Only update advanced UI when the selected frame changes
        if lastUpdatedFrame ~= selectedFrame then
            lastUpdatedFrame = selectedFrame
            updateAdvancedFromSelection()
        end
    else
        if self.xEditBox then
            self.xEditBox:SetText("")
            self.xEditBox:Disable()
        end
        if self.yEditBox then
            self.yEditBox:SetText("")
            self.yEditBox:Disable()
        end

        self.upButton:Disable()
        self.downButton:Disable()
        self.leftButton:Disable()
        self.rightButton:Disable()

        -- Clear the last updated frame when no frame is selected
        if lastUpdatedFrame ~= nil then
            lastUpdatedFrame = nil
            updateAdvancedFromSelection()
        end
    end
end

function NudgeFrame:UpdateVisibility()
    -- Embed into the settings dialog instead of floating separately
    if not EditModeManagerFrame or not EditModeManagerFrame.editModeActive then
        self:Hide()
        return
    end

    if EditModeSystemSettingsDialog and EditModeSystemSettingsDialog:IsShown() then
        self:UpdatePosition()
        self:Show()
        self:UpdateInfo()
    else
        self:Hide()
    end
end

NudgeFrame:SetScript("OnShow", function(self)
    self:UpdatePosition()
    self:UpdateInfo()
end)

-- (EnsureEditModeReady 제거됨 - 미사용 데드코드. 실제 체크는 인라인으로 수행)

function DDingUI:NudgeSelectedFrame(direction)
    local selectedFrame, frameName = GetSelectedEditModeFrame()
    if not selectedFrame then return false end

    -- Must be in Edit Mode
    if not EditModeManagerFrame or not EditModeManagerFrame.editModeActive then
        return false
    end

    local amount = 1
    local systemFrame = selectedFrame

    if not systemFrame.systemInfo then
        return false
    end

    -- Read current position from GetPoint (reflects actual position after previous nudges;
    -- systemInfo.anchorInfo is NOT updated by LEMO:ReanchorFrame so it goes stale)
    local currentPoint, currentRelativeTo, currentRelativePoint, xOffset, yOffset
    local readOk = pcall(function()
        currentPoint, currentRelativeTo, currentRelativePoint, xOffset, yOffset = systemFrame:GetPoint(1)
    end)

    if not readOk then
        currentPoint = nil
        xOffset = 0
        yOffset = 0
    end

    currentPoint = currentPoint or "CENTER"
    currentRelativePoint = currentRelativePoint or currentPoint
    local relativeFrame = resolveFrame(currentRelativeTo) or UIParent
    if relativeFrame == systemFrame then
        relativeFrame = UIParent
    end

    -- Apply the nudge
    if direction == "UP" then
        yOffset = yOffset + amount
    elseif direction == "DOWN" then
        yOffset = yOffset - amount
    elseif direction == "LEFT" then
        xOffset = xOffset - amount
    elseif direction == "RIGHT" then
        xOffset = xOffset + amount
    end

    -- Use LEMO for taint-safe saving (do NOT write to systemInfo.anchorInfo or hasActiveChanges directly)
    if LibEditModeOverride and LibEditModeOverride.AreLayoutsLoaded and LibEditModeOverride:AreLayoutsLoaded() then
        pcall(function()
            LibEditModeOverride:ReanchorFrame(systemFrame, currentPoint, relativeFrame, currentRelativePoint, xOffset, yOffset)
            LibEditModeOverride:SaveOnly()
        end)
    end

    -- Visual move (immediate feedback)
    systemFrame:ClearAllPoints()
    systemFrame:SetPoint(currentPoint, relativeFrame, currentRelativePoint, xOffset, yOffset)

    -- Update advanced state for UI display
    advanced.point = currentPoint
    advanced.attachPoint = currentRelativePoint
    advanced.attachFrame = relativeFrame
    advanced.xOffset = xOffset
    advanced.yOffset = yOffset

    -- Update nudge frame display
    if self.nudgeFrame and self.nudgeFrame:IsShown() then
        self.nudgeFrame:UpdateInfo()
        self.nudgeFrame:UpdatePosition()
    end

    return true
end

local function SetupEditModeHooks()
    if not EditModeManagerFrame then return end
    HookSettingsDialog()
    
    hooksecurefunc(EditModeManagerFrame, "EnterEditMode", function()
        if LibEditModeOverride and LibEditModeOverride:IsReady() then
            if not LibEditModeOverride:AreLayoutsLoaded() then
                LibEditModeOverride:LoadLayouts()
            end
        end
        
        -- Enable click detection
        EnableClickDetection()
        
        -- Initial update
        NudgeFrame:UpdateVisibility()
    end)
    
    hooksecurefunc(EditModeManagerFrame, "ExitEditMode", function()
        -- Disable click detection
        DisableClickDetection()

        NudgeFrame:Hide()
        currentSelectedFrame = nil
        currentSelectedFrameName = nil
        lastUpdatedFrame = nil
    end)
end

if EditModeManagerFrame then
    SetupEditModeHooks()
else
    local waitFrame = CreateFrame("Frame")
    waitFrame:RegisterEvent("ADDON_LOADED")
    waitFrame:SetScript("OnEvent", function(self, event, addon)
        if addon == "Blizzard_EditMode" and EditModeManagerFrame then
            SetupEditModeHooks()
            self:UnregisterAllEvents()
        end
    end)
end

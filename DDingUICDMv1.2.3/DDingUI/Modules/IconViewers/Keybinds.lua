-- Keybinds

local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
local SL = _G.DDingUI_StyleLib -- [12.0.1]

DDingUI.Keybinds = DDingUI.Keybinds or {}
local Keybinds = DDingUI.Keybinds

local LSM = LibStub("LibSharedMedia-3.0", true)

-- Weak table to store keybind frames without tainting Blizzard icon frames
local keybindFrames = setmetatable({}, { __mode = "k" })

local CMC_KEYBIND_DEBUG = false
local PrintDebug = function(...)
    if CMC_KEYBIND_DEBUG then
        print("[DDingUI Keybinds]", ...)
    end
end
local isModuleKeybindsEnabled = false
local areHooksInitialized = false

local NUM_ACTIONBAR_BUTTONS = 12
local MAX_ACTION_SLOTS = 180

local viewersSettingKey = {
    EssentialCooldownViewer = "Essential",
    UtilityCooldownViewer = "Utility",
}
local DEFAULT_FONT_PATH = (SL and SL.Font and SL.Font.default) or "Fonts\\FRIZQT__.TTF" -- [12.0.1]

local function GetFontPath(fontName)
    if not fontName or fontName == "" then
        return DEFAULT_FONT_PATH
    end

    if LSM then
        local fontPath = LSM:Fetch("font", fontName)
        if fontPath then
            return fontPath
        end
    end
    return DEFAULT_FONT_PATH
end

-- Caches avoid re-scanning all action slots/bindings on every icon update.
-- They are rebuilt on binding/state/layout changes.

local bindingKeyCache = {} -- {ACTIONBUTTON1 = "SHIFT-F",...}
local bindingCacheValid = false

local slotMappingCache = {}
local slotMappingCacheKey = 0

local keybindCache = {} -- {<slot_number> = "SHIFT-F",...} -- important for class specific bars
local keybindCacheValid = false

local iconSpellCache = {} -- {EssentialCooldownViewer= {1,2,3 = {keybind, spellID}}}

local cachedStateData = {
    page = 1,
    bonusOffset = 0,
    form = 0,
    hasOverride = false,
    hasVehicle = false,
    hasTemp = false,
    hash = 0,
    valid = false,
}
local function IsKeybindEnabledForAnyViewer()
    if not DDingUI.db or not DDingUI.db.profile then
        return false
    end

    for _, viewerSettingName in pairs(viewersSettingKey) do
        local enabledKey = "cooldownManager_showKeybinds_" .. viewerSettingName
        if DDingUI.db.profile[enabledKey] then
            return true
        end
    end
    return false
end

local function GetKeybindSettings(viewerSettingName)
    local defaults = {
        anchor = "CENTER",
        fontSize = 14,
        offsetX = 0,
        offsetY = 0,
        fontColor = {1, 1, 1, 1},
        fontName = "Friz Quadrata TT",
    }

    if not DDingUI.db or not DDingUI.db.profile then
        return defaults
    end

    local fontName = DDingUI.db.profile["cooldownManager_keybindFontName_" .. viewerSettingName]
    if not fontName or fontName == "" then
        fontName = DDingUI.db.profile.cooldownManager_keybindFontName or defaults.fontName
    end

    local fontColor = DDingUI.db.profile["cooldownManager_keybindFontColor_" .. viewerSettingName]
    if not fontColor then
        fontColor = DDingUI.db.profile.cooldownManager_keybindFontColor or defaults.fontColor
    end

    return {
        anchor = DDingUI.db.profile["cooldownManager_keybindAnchor_" .. viewerSettingName] or defaults.anchor,
        fontSize = DDingUI.db.profile["cooldownManager_keybindFontSize_" .. viewerSettingName] or defaults.fontSize,
        offsetX = DDingUI.db.profile["cooldownManager_keybindOffsetX_" .. viewerSettingName] or defaults.offsetX,
        offsetY = DDingUI.db.profile["cooldownManager_keybindOffsetY_" .. viewerSettingName] or defaults.offsetY,
        fontColor = fontColor,
        fontName = fontName,
    }
end

local function UpdateCachedState()
    cachedStateData.page = GetActionBarPage and GetActionBarPage() or 1
    cachedStateData.bonusOffset = GetBonusBarOffset and GetBonusBarOffset() or 0
    cachedStateData.form = GetShapeshiftFormID and GetShapeshiftFormID() or 0
    cachedStateData.hasOverride = HasOverrideActionBar and HasOverrideActionBar() or false
    cachedStateData.hasVehicle = HasVehicleActionBar and HasVehicleActionBar() or false
    cachedStateData.hasTemp = HasTempShapeshiftActionBar and HasTempShapeshiftActionBar() or false

    cachedStateData.hash = cachedStateData.page + (cachedStateData.bonusOffset * 100) + (cachedStateData.form * 10000)
    if cachedStateData.hasOverride then
        cachedStateData.hash = cachedStateData.hash + 1000000
    end
    if cachedStateData.hasVehicle then
        cachedStateData.hash = cachedStateData.hash + 2000000
    end
    if cachedStateData.hasTemp then
        cachedStateData.hash = cachedStateData.hash + 4000000
    end

    cachedStateData.valid = true
end

local function GetCachedStateHash()
    if not cachedStateData.valid then
        UpdateCachedState()
    end
    return cachedStateData.hash
end

local function RebuildBindingCache()
    wipe(bindingKeyCache)

    local patterns = {
        "ACTIONBUTTON",
        "MULTIACTIONBAR1BUTTON", -- Bar 2
        "MULTIACTIONBAR2BUTTON", -- Bar 3
        "MULTIACTIONBAR3BUTTON", -- Bar 4
        "MULTIACTIONBAR4BUTTON", -- Bar 5
        "MULTIACTIONBAR5BUTTON", -- Bar 6
        "MULTIACTIONBAR6BUTTON", -- Bar 7
        "MULTIACTIONBAR7BUTTON", -- Bar 8
    }

    for i, pattern in ipairs(patterns) do
        for j = 1, NUM_ACTIONBAR_BUTTONS do
            local bindingKey = pattern .. j
            bindingKeyCache[bindingKey] = GetBindingKey(bindingKey) or ""
        end
    end

    for barNum = 1, 10 do
        for buttonNum = 1, 12 do
            local bindingKey = "CLICK BT4Button" .. ((barNum - 1) * 12 + buttonNum) .. ":LeftButton"
            local key = GetBindingKey(bindingKey)
            if key then
                bindingKeyCache["BT4Bar" .. barNum .. "Button" .. buttonNum] = key
            end
        end
    end

    bindingCacheValid = true
end

local function GetCachedBindingKey(bindingKey)
    if not bindingCacheValid then
        RebuildBindingCache()
    end
    return bindingKeyCache[bindingKey] or ""
end

local function CalculateActionSlot(buttonID, barType)
    if not cachedStateData.valid then
        UpdateCachedState()
    end
    local page = 1

    -- Paging rules vary by override/bonus/vehicle bars and expansion layouts.
    if barType == "main" then
        page = cachedStateData.page
        if cachedStateData.bonusOffset > 0 then
            page = 6 + cachedStateData.bonusOffset
        end
    elseif barType == "multibarbottomleft" then
        page = 6 -- Action Bar 2
    elseif barType == "multibarbottomright" then
        page = 5 -- Action Bar 3
    elseif barType == "multibarright" then
        page = 3 -- Action Bar 4
    elseif barType == "multibarleft" then
        page = 4 -- Action Bar 5
    elseif barType == "multibar5" then
        page = 13 -- Action Bar 6
    elseif barType == "multibar6" then
        page = 14 -- Action Bar 7
    elseif barType == "multibar7" then
        page = 15 -- Action Bar 8
    end

    if LE_EXPANSION_LEVEL_CURRENT >= 11 then
        if barType == "multibarbottomleft" then
            page = 5
        elseif barType == "multibarbottomright" then
            page = 6
        end
    end

    local safePage = math.max(1, page)
    local safeButtonID = math.max(1, math.min(buttonID, NUM_ACTIONBAR_BUTTONS))
    return safeButtonID + ((safePage - 1) * NUM_ACTIONBAR_BUTTONS)
end

local function GetCachedSlotMapping()
    local currentHash = GetCachedStateHash()
    if slotMappingCacheKey == currentHash and slotMappingCache then
        return slotMappingCache
    end

    local mapping = {} -- slot → { pattern1, pattern2, ... }

    local function addMapping(slot, pattern)
        if not mapping[slot] then
            mapping[slot] = {}
        end
        mapping[slot][#mapping[slot] + 1] = pattern
    end

    -- 메인바 먼저 (ACTIONBUTTON = 가장 기본 키바인드)
    for buttonID = 1, NUM_ACTIONBAR_BUTTONS do
        local slot = CalculateActionSlot(buttonID, "main")
        addMapping(slot, "ACTIONBUTTON" .. buttonID)
    end

    local barMappings = {
        { barType = "multibarbottomleft", pattern = "MULTIACTIONBAR1BUTTON" },
        { barType = "multibarbottomright", pattern = "MULTIACTIONBAR2BUTTON" },
        { barType = "multibarright", pattern = "MULTIACTIONBAR3BUTTON" },
        { barType = "multibarleft", pattern = "MULTIACTIONBAR4BUTTON" },
        { barType = "multibar5", pattern = "MULTIACTIONBAR5BUTTON" },
        { barType = "multibar6", pattern = "MULTIACTIONBAR6BUTTON" },
        { barType = "multibar7", pattern = "MULTIACTIONBAR7BUTTON" },
    }

    if LE_EXPANSION_LEVEL_CURRENT >= 11 then
        barMappings[1].pattern = "MULTIACTIONBAR2BUTTON" -- BotLeft
        barMappings[2].pattern = "MULTIACTIONBAR1BUTTON" -- BotRight
    end

    for _, barData in ipairs(barMappings) do
        for buttonID = 1, NUM_ACTIONBAR_BUTTONS do
            local slot = CalculateActionSlot(buttonID, barData.barType)
            addMapping(slot, barData.pattern .. buttonID)
        end
    end

    slotMappingCache = mapping
    slotMappingCacheKey = currentHash
    return mapping
end

local function ValidateAndBuildKeybindCache()
    if keybindCacheValid then
        return
    end

    wipe(keybindCache)
    local slotMapping = GetCachedSlotMapping()
    -- 각 슬롯에 매핑된 모든 바인딩 패턴 중 가장 짧은(= 편한) 키 선택
    for slot, patterns in pairs(slotMapping) do
        local bestKey = nil
        for _, pattern in ipairs(patterns) do
            local key = GetCachedBindingKey(pattern)
            if key and key ~= "" then
                if not bestKey or #key < #bestKey then
                    bestKey = key
                end
            end
        end
        if bestKey then
            keybindCache[slot] = bestKey
        end
    end
    keybindCacheValid = true
end

local function GetKeybindForSlot(slot)
    if not slot or slot < 1 or slot > MAX_ACTION_SLOTS then
        return nil
    end
    return keybindCache[slot]
end

local function GetFormattedKeybind(key)
    if not key or key == "" then
        return ""
    end

    local upperKey = key:upper()

    upperKey = upperKey:gsub("SHIFT%-", "S")
    upperKey = upperKey:gsub("CTRL%-", "C")
    upperKey = upperKey:gsub("ALT%-", "A")
    upperKey = upperKey:gsub("STRG%-", "S") -- German Ctrl

    upperKey = upperKey:gsub("MOUSE%s?WHEEL%s?UP", "MWU")
    upperKey = upperKey:gsub("MOUSE%s?WHEEL%s?DOWN", "MWD")
    upperKey = upperKey:gsub("MOUSE%s?BUTTON%s?", "M")
    upperKey = upperKey:gsub("BUTTON", "M")

    upperKey = upperKey:gsub("NUMPAD%s?PLUS", "N+")
    upperKey = upperKey:gsub("NUMPAD%s?MINUS", "N-")
    upperKey = upperKey:gsub("NUMPAD%s?MULTIPLY", "N*")
    upperKey = upperKey:gsub("NUMPAD%s?DIVIDE", "N/")
    upperKey = upperKey:gsub("NUMPAD%s?DECIMAL", "N.")
    upperKey = upperKey:gsub("NUMPAD%s?ENTER", "NEnt")
    upperKey = upperKey:gsub("NUMPAD%s?", "N")
    upperKey = upperKey:gsub("NUM%s?", "N")

    upperKey = upperKey:gsub("PAGE%s?UP", "PGU")
    upperKey = upperKey:gsub("PAGE%s?DOWN", "PGD")
    upperKey = upperKey:gsub("INSERT", "INS")
    upperKey = upperKey:gsub("DELETE", "DEL")
    upperKey = upperKey:gsub("SPACEBAR", "Spc")
    upperKey = upperKey:gsub("ENTER", "Ent")
    upperKey = upperKey:gsub("ESCAPE", "Esc")
    upperKey = upperKey:gsub("TAB", "Tab")
    upperKey = upperKey:gsub("CAPS%s?LOCK", "Caps")
    upperKey = upperKey:gsub("HOME", "Hom")
    upperKey = upperKey:gsub("END", "End")

    return upperKey
end

function Keybinds:GetActionsTableBySpellId()
    PrintDebug("Building Actions Table By Spell ID")
    ValidateAndBuildKeybindCache()

    local startSlot = 1
    local endSlot = 12

    if GetBonusBarOffset() > 0 then
        startSlot = 72 + (GetBonusBarOffset() - 1) * NUM_ACTIONBAR_BUTTONS + 1
        endSlot = startSlot + NUM_ACTIONBAR_BUTTONS - 1
    end

    local result = {}

    -- 같은 주문이 여러 슬롯에 있으면 키바인드가 짧은(= 편한) 쪽 우선
    local function addSpellSlot(spellID, slot)
        if not spellID then return end
        if issecretvalue and issecretvalue(spellID) then return end
        if result[spellID] then
            local existingKey = keybindCache[result[spellID]]
            local newKey = keybindCache[slot]
            if newKey and newKey ~= "" then
                if not existingKey or existingKey == "" or #newKey < #existingKey then
                    result[spellID] = slot
                end
            end
            return
        end
        result[spellID] = slot
    end

    -- BUG FIX: 매크로는 항상 GetMacroSpell로 spellID 조회
    -- (이전: actionType=="macro" and subType=="spell"에서 macroIndex를 spellID로 잘못 저장)
    for slot = startSlot, endSlot do
        local actionType, id = GetActionInfo(slot)
        if actionType == "spell" then
            addSpellSlot(id, slot)
        elseif actionType == "macro" then
            local macroSpellID = GetMacroSpell(id)
            if macroSpellID then
                addSpellSlot(macroSpellID, slot)
            end
        end
    end

    for slot = 13, MAX_ACTION_SLOTS do
        if (slot <= 72 or slot > 120) and HasAction(slot) then
            local actionType, id = GetActionInfo(slot)
            if actionType == "spell" then
                addSpellSlot(id, slot)
            elseif actionType == "macro" then
                local macroSpellID = GetMacroSpell(id)
                if macroSpellID then
                    addSpellSlot(macroSpellID, slot)
                end
            end
        end
    end
    return result
end
function Keybinds:FindKeybindForSpell(spellID, spellIdToSlotTable)
    -- Secret value 체크 - 비교/연산 전에 반드시 확인
    if not spellID then
        return ""
    end
    if issecretvalue and issecretvalue(spellID) then
        return ""
    end
    if spellID == 0 then
        return ""
    end

    -- Action buttons/macros may reference base or override spell IDs; treat them as equivalent.
    local overrideSpellID, baseSpellID
    pcall(function()
        overrideSpellID = C_Spell.GetOverrideSpell(spellID)
        -- Secret value 체크
        if overrideSpellID and issecretvalue and issecretvalue(overrideSpellID) then
            overrideSpellID = nil
        end
    end)
    pcall(function()
        baseSpellID = C_Spell.GetBaseSpell(spellID)
        -- Secret value 체크
        if baseSpellID and issecretvalue and issecretvalue(baseSpellID) then
            baseSpellID = nil
        end
    end)

    local match = nil
    if spellIdToSlotTable[spellID] then
        match = spellIdToSlotTable[spellID]
    elseif overrideSpellID and spellIdToSlotTable[overrideSpellID] then
        match = spellIdToSlotTable[overrideSpellID]
    elseif baseSpellID and spellIdToSlotTable[baseSpellID] then
        match = spellIdToSlotTable[baseSpellID]
    end
    if match then
        -- if spellID == 190984 then
        --     PrintDebug("Found action slot for spellID wrath:", match)
        -- end
        local key = GetKeybindForSlot(match)
        if key and key ~= "" then
            local bestKey = GetFormattedKeybind(key)
            return bestKey
        end
    end

    return ""
end

local function GetOrCreateKeybindText(icon, viewerSettingName)
    if keybindFrames[icon] and keybindFrames[icon].text then
        return keybindFrames[icon].text
    end

    local settings = GetKeybindSettings(viewerSettingName)
    -- Parent to UIParent instead of icon to avoid Blizzard's EditMode child iteration
    -- which causes "EnableSpellRangeCheck" errors when it encounters non-icon frames
    keybindFrames[icon] = CreateFrame("Frame", nil, UIParent)
    keybindFrames[icon]:SetFrameLevel(icon:GetFrameLevel() + 4)
    keybindFrames[icon]:SetAllPoints(icon)  -- Follow icon position
    local keybindText = keybindFrames[icon]:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    keybindText:SetPoint(settings.anchor, icon, settings.anchor, settings.offsetX, settings.offsetY)
    keybindText:SetTextColor(unpack(settings.fontColor))
    keybindText:SetShadowColor(0, 0, 0, 0)
    keybindText:SetShadowOffset(0, 0)
    keybindText:SetDrawLayer("OVERLAY", 7)

    keybindFrames[icon].text = keybindText

    -- Sync visibility and alpha with icon (alpha follows parent chain,
    -- so FlightHide fading the viewer will also fade keybind text)
    keybindFrames[icon]:SetScript("OnUpdate", function(self)
        self:SetShown(icon:IsShown())
        self:SetAlpha(icon:GetEffectiveAlpha())
    end)

    return keybindFrames[icon].text
end

local function ApplyKeybindTextSettings(icon, viewerSettingName)
    if not keybindFrames[icon] then
        return
    end

    local settings = GetKeybindSettings(viewerSettingName)
    local keybindText = GetOrCreateKeybindText(icon, viewerSettingName)

    keybindFrames[icon]:Show()
    keybindText:ClearAllPoints()
    keybindText:SetPoint(settings.anchor, icon, settings.anchor, settings.offsetX, settings.offsetY)
    local fontPath = GetFontPath(settings.fontName)
    -- Always use OUTLINE for 1 pixel black outline, combine with any other font flags
    local fontFlags = DDingUI.db.profile.cooldownManager_keybindFontFlags or {}
    local fontFlag = "OUTLINE"
    for n, v in pairs(fontFlags) do
        if v == true and n ~= "OUTLINE" then
            fontFlag = fontFlag .. "," .. n
        end
    end
    keybindText:SetFont(fontPath, settings.fontSize, fontFlag)
    keybindText:SetTextColor(unpack(settings.fontColor))
    keybindText:SetShadowColor(0, 0, 0, 0)
    keybindText:SetShadowOffset(0, 0)
end

-- Only call when it's safe (may touch restricted/secure state in combat).
local function ExtractSpellIDFromIcon(icon)
    -- Skip during combat to prevent Blizzard CooldownViewer taint
    if InCombatLockdown() then return nil end

    -- Use pcall to safely access cooldownID without triggering taint
    local success, spellID = pcall(function()
        if icon.cooldownID then
            local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(icon.cooldownID)
            if info and info.spellID then
                -- Secret value 체크 - 비교/연산 전에 반드시 확인
                if issecretvalue and issecretvalue(info.spellID) then
                    return nil
                end
                return info.spellID
            end
        end
        return nil
    end)
    if success and spellID then
        -- 추가 안전 체크
        if issecretvalue and issecretvalue(spellID) then
            return nil
        end
        return spellID
    end
    -- Everything is secret below
    -- if icon.spellID then
    --     PrintDebug("Extracted spellID from icon.spellID:", icon.spellID)
    --     return icon.spellID
    -- end
    -- if icon.GetSpellID and type(icon.GetSpellID) == "function" then
    --     PrintDebug("Extracted spellID from icon:GetSpellID():", icon:GetSpellID())
    --     return icon:GetSpellID()
    -- end
    return nil
end

local function InjectCachedDataOntoIcons()
    local injectedCount = 0

    for viewerName, viewerData in pairs(iconSpellCache) do
        local viewerFrame = _G[viewerName]
        if viewerFrame then
            local children = { viewerFrame:GetChildren() }
            local childIndex = 0

            for _, child in ipairs(children) do
                if child.Icon then
                    childIndex = childIndex + 1
                    local layoutIndex = child.layoutIndex or child:GetName() or tostring(child)

                    -- Try multiple key formats to match saved data
                    local cachedData = viewerData[tostring(layoutIndex)]
                        or viewerData[layoutIndex]
                        or viewerData[tostring(childIndex)]
                        or viewerData[childIndex]

                    if cachedData then
                        -- Preserve existing keybind if cached one is empty
                        if cachedData.keybind and cachedData.keybind ~= "" then
                            child._cmc_keybind = cachedData.keybind
                        elseif not child._cmc_keybind then
                            child._cmc_keybind = ""
                        end
                        injectedCount = injectedCount + 1
                    end
                end
            end
        end
    end

    PrintDebug("[DDingUI Keybinds] Injected cached data onto", injectedCount, "icons")

    return injectedCount
end

local function BuildIconSpellCacheForViewer(viewerName)
    local viewerFrame = _G[viewerName]
    if not viewerFrame then
        return
    end
    PrintDebug(
        "|cffff0000 BuildIconSpellCacheForViewer called for",
        viewerName,
        "inLockdown:",
        tostring(InCombatLockdown())
    )
    local settingName = viewersSettingKey[viewerName]
    if not settingName then
        return
    end

    iconSpellCache[viewerName] = iconSpellCache[viewerName] or {}
    wipe(iconSpellCache[viewerName])

    local children = { viewerFrame:GetChildren() }
    local actionsTableBySpellId = Keybinds:GetActionsTableBySpellId()
    for _, child in ipairs(children) do
        if child.Icon then
            local layoutIndex = child.layoutIndex or child:GetName() or tostring(child)

            local rawSpellID = ExtractSpellIDFromIcon(child)
            if rawSpellID then
                local keybind = Keybinds:FindKeybindForSpell(rawSpellID, actionsTableBySpellId)

                -- Preserve existing keybind if new one is empty
                local existingKeybind = (
                    iconSpellCache[viewerName]
                    and iconSpellCache[viewerName][layoutIndex]
                    and iconSpellCache[viewerName][layoutIndex].keybind
                ) or child._cmc_keybind
                local finalKeybind = (keybind and keybind ~= "") and keybind or (existingKeybind or "")

                -- if rawSpellID == 190984 then
                --     PrintDebug("Found keybind for spellID wrath:", finalKeybind)
                --     PrintDebug(keybind, existingKeybind)
                -- end
                iconSpellCache[viewerName][layoutIndex] = {
                    spellID = rawSpellID,
                    keybind = finalKeybind,
                }

                child._cmc_keybind = finalKeybind
            end
        end
    end
end

local function BuildAllIconSpellCaches()
    PrintDebug("|cffffff00 BuildAllIconSpellCaches called inLockdown:", tostring(InCombatLockdown()))

    ValidateAndBuildKeybindCache()
    for viewerName, _ in pairs(viewersSettingKey) do
        BuildIconSpellCacheForViewer(viewerName)
    end

    return true
end

local function UpdateIconKeybind(icon, viewerSettingName)
    if not icon then
        return
    end

    local enabledKey = "cooldownManager_showKeybinds_" .. viewerSettingName
    if not DDingUI.db.profile[enabledKey] then
        if keybindFrames[icon] then
            keybindFrames[icon]:Hide()
            -- 텍스트도 지워서 완전히 숨김
            if keybindFrames[icon].text then
                keybindFrames[icon].text:SetText("")
                keybindFrames[icon].text:Hide()
            end
        end
        return
    end

    local keybind = icon._cmc_keybind

    if not keybind or keybind == "" then
        if keybindFrames[icon] then
            keybindFrames[icon]:Hide()
        end
        return
    end

    local keybindText = GetOrCreateKeybindText(icon, viewerSettingName)
    keybindFrames[icon]:Show()
    keybindText:SetText(keybind)
    keybindText:Show()
end

function Keybinds:UpdateViewerKeybinds(viewerName)
    local viewerFrame = _G[viewerName]
    if not viewerFrame then
        return
    end

    local settingName = viewersSettingKey[viewerName]
    if not settingName then
        return
    end

    local children = { viewerFrame:GetChildren() }
    for _, child in ipairs(children) do
        if child.Icon then
            UpdateIconKeybind(child, settingName)
        end
    end
end

function Keybinds:UpdateAllKeybinds()
    for viewerName, _ in pairs(viewersSettingKey) do
        self:UpdateViewerKeybinds(viewerName)
        self:ApplyKeybindSettings(viewerName)
    end
end

function Keybinds:ApplyKeybindSettings(viewerName)
    local viewerFrame = _G[viewerName]
    if not viewerFrame then
        return
    end

    local settingName = viewersSettingKey[viewerName]
    if not settingName then
        return
    end

    local children = { viewerFrame:GetChildren() }
    for _, child in ipairs(children) do
        if keybindFrames[child] then
            keybindFrames[child]:Show()
            ApplyKeybindTextSettings(child, settingName)
        end
    end
end

local eventFrame = CreateFrame("Frame")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if not isModuleKeybindsEnabled then
        return
    end

    if event == "EDIT_MODE_LAYOUTS_UPDATED" then
        PrintDebug("[DDingUI Keybinds] EditMode layout changed - rebuilding cache")
        BuildAllIconSpellCaches()
        Keybinds:UpdateAllKeybinds()
    elseif event == "UPDATE_BINDINGS" then
        bindingCacheValid = false
        keybindCacheValid = false
        BuildAllIconSpellCaches()
        Keybinds:UpdateAllKeybinds()
    elseif event == "PLAYER_ENTERING_WORLD" then
        BuildAllIconSpellCaches()
        Keybinds:UpdateAllKeybinds()
        PrintDebug(
            "[DDingUI Keybinds] PLAYER_ENTERING_WORLD - LoadOrBuild result:",
            "inLockdown:",
            tostring(InCombatLockdown())
        )
    elseif
        event == "UPDATE_SHAPESHIFT_FORM"
        or event == "UPDATE_BONUS_ACTIONBAR"
        or event == "PLAYER_MOUNT_DISPLAY_CHANGED"
    then
        keybindCacheValid = false
        cachedStateData.valid = false
        BuildAllIconSpellCaches()
        Keybinds:UpdateAllKeybinds()
    elseif
        event == "PLAYER_TALENT_UPDATE"
        or event == "SPELLS_CHANGED"
        or event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_REGEN_DISABLED"
        or event == "ACTIONBAR_HIDEGRID" -- eg. Dropping a spell on action bar
    then
        C_Timer.After(0, function()
            bindingCacheValid = false
            keybindCacheValid = false
            cachedStateData.valid = false
            BuildAllIconSpellCaches()
            Keybinds:UpdateAllKeybinds()
        end)
    end
end)

function Keybinds:Shutdown()
    PrintDebug("[DDingUI Keybinds] Shutting down module")

    isModuleKeybindsEnabled = false

    eventFrame:UnregisterAllEvents()

    wipe(bindingKeyCache)
    bindingCacheValid = false
    wipe(slotMappingCache)
    slotMappingCacheKey = 0
    wipe(keybindCache)
    keybindCacheValid = false
    wipe(iconSpellCache)
    cachedStateData.valid = false

    if DDingUI.db and DDingUI.db.profile and DDingUI.db.profile.keybindCache then
        DDingUI.db.profile.keybindCache = nil

        PrintDebug("[DDingUI Keybinds] Wiped DB cache")
    end

    for viewerName, _ in pairs(viewersSettingKey) do
        local viewerFrame = _G[viewerName]
        if viewerFrame then
            local children = { viewerFrame:GetChildren() }
            for _, child in ipairs(children) do
                if keybindFrames[child] then
                    keybindFrames[child]:Hide()
                    -- 텍스트도 지워서 완전히 숨김
                    if keybindFrames[child].text then
                        keybindFrames[child].text:SetText("")
                        keybindFrames[child].text:Hide()
                    end
                end
            end
        end
    end
end

function Keybinds:Enable()
    if isModuleKeybindsEnabled then
        return
    end
    PrintDebug("[DDingUI Keybinds] Enabling module")

    isModuleKeybindsEnabled = true

    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    eventFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    eventFrame:RegisterEvent("UPDATE_BINDINGS")
    eventFrame:RegisterEvent("PLAYER_TALENT_UPDATE")
    eventFrame:RegisterEvent("SPELLS_CHANGED")
    eventFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    eventFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
    eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    eventFrame:RegisterEvent("ACTIONBAR_HIDEGRID")

    if not areHooksInitialized then
        areHooksInitialized = true

        for viewerName, settingName in pairs(viewersSettingKey) do
            local viewerFrame = _G[viewerName]
            if viewerFrame then
                hooksecurefunc(viewerFrame, "RefreshLayout", function()
                    if not isModuleKeybindsEnabled then
                        return
                    end

                    PrintDebug("[DDingUI Keybinds] RefreshLayout called for viewer:", viewerName)

                    -- if not InCombatLockdown() then
                    BuildIconSpellCacheForViewer(viewerName)
                    -- end
                    Keybinds:UpdateViewerKeybinds(viewerName)
                end)
            end
        end
    end

    BuildAllIconSpellCaches()
    Keybinds:UpdateAllKeybinds()
end

function Keybinds:Disable()
    if not isModuleKeybindsEnabled then
        return
    end
    PrintDebug("[DDingUI Keybinds] Disabling module")

    self:Shutdown()
end

function Keybinds:Initialize()
    if not IsKeybindEnabledForAnyViewer() then
        PrintDebug("[DDingUI Keybinds] Not initializing - no viewers enabled")
        return
    end

    PrintDebug("[DDingUI Keybinds] Initializing module")

    self:Enable()

    --  CLEANUPS:
    if DDingUI.db and DDingUI.db.profile then
        DDingUI.db.profile.keybindCache = nil
    end
end

function Keybinds:OnSettingChanged(viewerSettingName)
    local shouldBeEnabled = IsKeybindEnabledForAnyViewer()

    if shouldBeEnabled and not isModuleKeybindsEnabled then
        self:Enable()
    elseif not shouldBeEnabled and isModuleKeybindsEnabled then
        self:Disable()
    elseif isModuleKeybindsEnabled then
        if viewerSettingName then
            for viewerName, settingName in pairs(viewersSettingKey) do
                if settingName == viewerSettingName then
                    self:UpdateViewerKeybinds(viewerName)
                    self:ApplyKeybindSettings(viewerName)
                    return
                end
            end
        end
        self:UpdateAllKeybinds()
    end
end

local ADDON_NAME, ns = ...
local DDingUI = ns.Addon

local LSM = LibStub("LibSharedMedia-3.0")

-- Register fonts
LSM:Register("font","Expressway", [[Interface\AddOns\DDingUI\Fonts\Expressway.TTF]])

-- Register sounds (WoW built-in sounds for buff tracking)
LSM:Register("sound", "None", [[]])
LSM:Register("sound", "Alarm Clock Warning 1", [[Sound\Interface\AlarmClockWarning1.ogg]])
LSM:Register("sound", "Alarm Clock Warning 2", [[Sound\Interface\AlarmClockWarning2.ogg]])
LSM:Register("sound", "Alarm Clock Warning 3", [[Sound\Interface\AlarmClockWarning3.ogg]])
LSM:Register("sound", "Auction Window Close", [[Sound\Interface\AuctionWindowClose.ogg]])
LSM:Register("sound", "Auction Window Open", [[Sound\Interface\AuctionWindowOpen.ogg]])
LSM:Register("sound", "Bell Toll Alliance", [[Sound\Doodad\BellTollAlliance.ogg]])
LSM:Register("sound", "Bell Toll Horde", [[Sound\Doodad\BellTollHorde.ogg]])
LSM:Register("sound", "Humm", [[Sound\Spells\SimonGame_Visual_GameStart.ogg]])
LSM:Register("sound", "igCharacterInfo", [[Sound\Interface\igCharacterInfoTab.ogg]])
LSM:Register("sound", "igQuestLogOpen", [[Sound\Interface\igQuestLogOpen.ogg]])
LSM:Register("sound", "Levelup", [[Sound\Interface\Levelup.ogg]])
LSM:Register("sound", "Levelup2", [[Sound\Interface\Levelup2.ogg]])
LSM:Register("sound", "Map Ping", [[Sound\Interface\MapPing.ogg]])
LSM:Register("sound", "Murloc", [[Sound\Creature\Murloc\mMurlocAggroOld.ogg]])
LSM:Register("sound", "PvP Flag Taken", [[Sound\Spells\PVPFlagTaken.ogg]])
LSM:Register("sound", "Raid Warning", [[Sound\Interface\RaidWarning.ogg]])
LSM:Register("sound", "Ready Check", [[Sound\Interface\ReadyCheck.ogg]])
LSM:Register("sound", "Short Circuit", [[Sound\Spells\SimonGame_Visual_BadPress.ogg]])
LSM:Register("sound", "Wisp", [[Sound\Event Sounds\Wisp\WispPissed1.ogg]])

function DDingUI:GetGlobalFont()
    local fontName = self.db.profile.general.globalFont or "Expressway"
    return LSM:Fetch("font", fontName) or [[Interface\AddOns\DDingUI\Fonts\Expressway.TTF]]
end

function DDingUI:GetGlobalTexture()
    local textureName = self.db.profile.general.globalTexture or "Meli"
    return LSM:Fetch("statusbar", textureName) or "Interface\\RaidFrame\\Raid-Bar-Hp-Fill"
end

-- Helper function to get font with override support
-- If overrideFont is provided and valid, use it; otherwise use global font
function DDingUI:GetFont(overrideFont)
    if overrideFont and overrideFont ~= "" then
        local font = LSM:Fetch("font", overrideFont)
        if font then
            return font
        end
    end
    return self:GetGlobalFont()
end

-- Helper function to get texture with override support
-- If overrideTexture is provided and valid, use it; otherwise use global texture
function DDingUI:GetTexture(overrideTexture)
    if overrideTexture and overrideTexture ~= "" then
        -- User has set a specific override texture
        local tex = LSM:Fetch("statusbar", overrideTexture)
        if tex then
            return tex
        end
    end
    -- Default to global texture
    return self:GetGlobalTexture()
end

local COOLDOWN_VIEWER_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

local function ForEachOwnedCooldownFrame(callback)
    local seen = {}

    local function VisitCooldown(frame)
        if not frame or seen[frame] or not frame.GetObjectType then
            return
        end
        if frame.IsForbidden and frame:IsForbidden() then
            return
        end
        if frame:GetObjectType() ~= "Cooldown" then
            return
        end

        seen[frame] = true
        callback(frame)
    end

    local function VisitIcon(icon)
        if not icon then
            return
        end

        VisitCooldown(icon.Cooldown)
        VisitCooldown(icon.cooldown)
        if icon.Icon and icon.Icon ~= icon then
            VisitCooldown(icon.Icon.Cooldown)
            VisitCooldown(icon.Icon.cooldown)
        end
    end

    for _, viewerName in ipairs(COOLDOWN_VIEWER_NAMES) do
        local viewer = _G[viewerName]
        local pool = viewer and viewer.itemFramePool
        if pool and pool.EnumerateActive then
            for icon in pool:EnumerateActive() do
                VisitIcon(icon)
            end
        end
    end

    local controller = DDingUI.FrameController
    local iconMap = controller and controller.GetIconMap and controller:GetIconMap()
    if type(iconMap) == "table" then
        for _, icon in pairs(iconMap) do
            VisitIcon(icon)
        end
    end

    local customIcons = DDingUI.CustomIcons
    local customFrames = customIcons and customIcons.GetAllIconFrames and customIcons:GetAllIconFrames()
    if type(customFrames) == "table" then
        for _, icon in pairs(customFrames) do
            VisitIcon(icon)
        end
    end

    local targetFrame = _G.DDingUI_Target
    if targetFrame then
        for _, icon in ipairs(targetFrame.buffIcons or {}) do
            VisitIcon(icon)
        end
        for _, icon in ipairs(targetFrame.debuffIcons or {}) do
            VisitIcon(icon)
        end
    end
end

function DDingUI:ApplyGlobalFont()
    local fontPath = self:GetGlobalFont()
    if not fontPath then return end

    -- Check if user wants to apply global font to Blizzard UI
    local applyToBlizzard = self.db and self.db.profile and self.db.profile.general and self.db.profile.general.applyGlobalFontToBlizzard

    -- Apply fonts to Blizzard's global font objects (only if toggle is enabled)
    if applyToBlizzard then
        if GameFontNormal then
        local _, size, flags = GameFontNormal:GetFont()
        if size and flags then
            GameFontNormal:SetFont(fontPath, size, flags)
        end
    end

    if GameFontHighlight then
        local _, size, flags = GameFontHighlight:GetFont()
        if size and flags then
            GameFontHighlight:SetFont(fontPath, size, flags)
        end
    end

    if GameFontNormalSmall then
        local _, size, flags = GameFontNormalSmall:GetFont()
        if size and flags then
            GameFontNormalSmall:SetFont(fontPath, size, flags)
        end
    end

    if GameFontHighlightSmall then
        local _, size, flags = GameFontHighlightSmall:GetFont()
        if size and flags then
            GameFontHighlightSmall:SetFont(fontPath, size, flags)
        end
    end

    if GameFontNormalLarge then
        local _, size, flags = GameFontNormalLarge:GetFont()
        if size and flags then
            GameFontNormalLarge:SetFont(fontPath, size, flags)
        end
    end

    if GameFontHighlightLarge then
        local _, size, flags = GameFontHighlightLarge:GetFont()
        if size and flags then
            GameFontHighlightLarge:SetFont(fontPath, size, flags)
        end
    end

    if GameFontDisable then
        local _, size, flags = GameFontDisable:GetFont()
        if size and flags then
            GameFontDisable:SetFont(fontPath, size, flags)
        end
    end

    if GameFontDisableSmall then
        local _, size, flags = GameFontDisableSmall:GetFont()
        if size and flags then
            GameFontDisableSmall:SetFont(fontPath, size, flags)
        end
    end

    if GameFontDisableLarge then
        local _, size, flags = GameFontDisableLarge:GetFont()
        if size and flags then
            GameFontDisableLarge:SetFont(fontPath, size, flags)
        end
    end

    if NumberFontNormal then
        local _, size, flags = NumberFontNormal:GetFont()
        if size and flags then
            NumberFontNormal:SetFont(fontPath, size, flags)
        end
    end

    if NumberFontNormalSmall then
        local _, size, flags = NumberFontNormalSmall:GetFont()
        if size and flags then
            NumberFontNormalSmall:SetFont(fontPath, size, flags)
        end
    end

    if NumberFontNormalLarge then
        local _, size, flags = NumberFontNormalLarge:GetFont()
        if size and flags then
            NumberFontNormalLarge:SetFont(fontPath, size, flags)
        end
    end

    if NumberFontNormalHuge then
        local _, size, flags = NumberFontNormalHuge:GetFont()
        if size and flags then
            NumberFontNormalHuge:SetFont(fontPath, size, flags)
        end
    end

    if NumberFontNormalSmallGray then
        local _, size, flags = NumberFontNormalSmallGray:GetFont()
        if size and flags then
            NumberFontNormalSmallGray:SetFont(fontPath, size, flags)
        end
    end

    if ObjectiveTrackerFont then
        local _, size, flags = ObjectiveTrackerFont:GetFont()
        if size and flags then
            ObjectiveTrackerFont:SetFont(fontPath, size, flags)
        end
    end

    if QuestFont then
        local _, size, flags = QuestFont:GetFont()
        if size and flags then
            QuestFont:SetFont(fontPath, size, flags)
        end
    end

    if QuestFontHighlight then
        local _, size, flags = QuestFontHighlight:GetFont()
        if size and flags then
            QuestFontHighlight:SetFont(fontPath, size, flags)
        end
    end

    if QuestFontNormalSmall then
        local _, size, flags = QuestFontNormalSmall:GetFont()
        if size and flags then
            QuestFontNormalSmall:SetFont(fontPath, size, flags)
        end
    end

    if QuestFontHighlightSmall then
        local _, size, flags = QuestFontHighlightSmall:GetFont()
        if size and flags then
            QuestFontHighlightSmall:SetFont(fontPath, size, flags)
        end
    end

    if GameTooltipHeaderText then
        local _, size, flags = GameTooltipHeaderText:GetFont()
        if size and flags then
            GameTooltipHeaderText:SetFont(fontPath, size, flags)
        end
    end

    if GameTooltipText then
        local _, size, flags = GameTooltipText:GetFont()
        if size and flags then
            GameTooltipText:SetFont(fontPath, size, flags)
        end
    end

    if GameTooltipTextSmall then
        local _, size, flags = GameTooltipTextSmall:GetFont()
        if size and flags then
            GameTooltipTextSmall:SetFont(fontPath, size, flags)
        end
    end

    if ChatFontNormal then
        local _, size, flags = ChatFontNormal:GetFont()
        if size and flags then
            ChatFontNormal:SetFont(fontPath, size, flags)
        end
    end

    if ChatFontSmall then
        local _, size, flags = ChatFontSmall:GetFont()
        if size and flags then
            ChatFontSmall:SetFont(fontPath, size, flags)
        end
    end

    if ChatFontLarge then
        local _, size, flags = ChatFontLarge:GetFont()
        if size and flags then
            ChatFontLarge:SetFont(fontPath, size, flags)
        end
    end
    end -- End of applyToBlizzard conditional

    local function IsSafeCooldownFrame(cooldownFrame)
        if not cooldownFrame then return false end

        local ok, forbidden = pcall(function()
            if cooldownFrame.IsForbidden then
                return cooldownFrame:IsForbidden()
            end
            return false
        end)

        return ok and not forbidden
    end

    local function SafeGetParent(frame)
        if not frame then return nil end

        local ok, parent = pcall(function()
            return frame:GetParent()
        end)

        return ok and parent or nil
    end

    local function SafeGetName(frame)
        if not frame then return nil end

        local ok, name = pcall(function()
            return frame:GetName()
        end)

        return ok and name or nil
    end

    local function SafeGetObjectType(frame)
        if not frame then return nil end

        local ok, objectType = pcall(function()
            return frame:GetObjectType()
        end)

        return ok and objectType or nil
    end

    local function SafeGetRegions(frame)
        if not IsSafeCooldownFrame(frame) then return nil end

        local regions
        local ok = pcall(function()
            regions = { frame:GetRegions() }
        end)

        return ok and regions or nil
    end

    local function SafeGetChildren(frame)
        if not frame then return nil end

        local children
        local ok = pcall(function()
            children = { frame:GetChildren() }
        end)

        return ok and children or nil
    end

    local function SafeClearCooldownFontCache(cooldownFrame)
        if not IsSafeCooldownFrame(cooldownFrame) then return false end

        return pcall(function()
            cooldownFrame._ddingui_fontString = nil
        end)
    end

    local function ResolveRGBA(color, fallback)
        fallback = fallback or {1, 1, 1, 1}
        if type(color) ~= "table" then
            return fallback[1] or 1, fallback[2] or 1, fallback[3] or 1, fallback[4] or 1
        end

        if color.GetRGBA then
            local ok, r, g, b, a = pcall(color.GetRGBA, color)
            if ok and r ~= nil and g ~= nil and b ~= nil then
                return r, g, b, a or 1
            end
        end

        if color[1] ~= nil and color[2] ~= nil and color[3] ~= nil then
            return color[1], color[2], color[3], color[4] or 1
        end

        if color.r ~= nil and color.g ~= nil and color.b ~= nil then
            return color.r, color.g, color.b, color.a or color.opacity or 1
        end

        return fallback[1] or 1, fallback[2] or 1, fallback[3] or 1, fallback[4] or 1
    end

    local function SafeSetTextColor(fontString, color)
        if not fontString or not fontString.SetTextColor then return end
        local r, g, b, a = ResolveRGBA(color)
        if pcall(fontString.SetTextColor, fontString, r, g, b, a) then return end
        if CreateColor then
            pcall(fontString.SetTextColor, fontString, CreateColor(r, g, b, a), a)
        end
    end

    local GROUP_TO_VIEWER = {
        ["Cooldowns"] = "EssentialCooldownViewer",
        ["Buffs"] = "BuffIconCooldownViewer",
        ["Utility"] = "UtilityCooldownViewer",
    }

    local function GetDynamicIconData(iconKey)
        if not iconKey or not self.db or not self.db.profile then return nil end
        local dynamicIcons = self.db.profile.dynamicIcons
        return dynamicIcons and dynamicIcons.iconData and dynamicIcons.iconData[tostring(iconKey)] or nil
    end

    local function GetManagedIconKey(iconFrame)
        if not iconFrame then return nil end
        local iconKey
        pcall(function()
            iconKey = iconFrame._iconKey or iconFrame._ddIconKey
        end)
        return iconKey
    end

    local function BuildManagedSource(iconFrame, groupName)
        local iconKey = GetManagedIconKey(iconFrame)
        local sourceViewer
        pcall(function()
            sourceViewer = iconFrame and iconFrame._ddSourceViewer
        end)
        if iconKey and groupName then
            return "customIcon:" .. tostring(iconKey) .. ":group:" .. tostring(groupName)
        elseif iconKey then
            return "customIcon:" .. tostring(iconKey)
        elseif groupName then
            local suffix = sourceViewer == "BuffIconCooldownViewer" and ":buff" or ""
            return "group:" .. tostring(groupName) .. suffix
        end
        return nil
    end

    local function ShouldUseDurationText(groupName, iconData, sourceViewer)
        return groupName == "Buffs"
            or (iconData and iconData.type == "aura")
            or sourceViewer == "BuffIconCooldownViewer"
    end

    local function ResolveGroupCooldownSettings(groupName, iconData, sourceViewer)
        if not groupName or not self.db or not self.db.profile then return nil end

        local profile = self.db.profile
        local viewers = profile.viewers
        local general = viewers and viewers.general
        local groupSettings = profile.groupSystem and profile.groupSystem.groups and profile.groupSystem.groups[groupName]
        local viewerName = GROUP_TO_VIEWER[groupName]
        local viewerSettings = viewerName and viewers and viewers[viewerName]

        if not groupSettings and not viewerSettings then return nil end

        local fontSize = 18
        local textColor = {1, 1, 1, 1}
        local shadowOffsetX = 1
        local shadowOffsetY = -1
        local fontName = nil
        local textFormat = "auto"

        if ShouldUseDurationText(groupName, iconData, sourceViewer) then
            fontSize = (groupSettings and groupSettings.durationTextSize)
                or (viewerSettings and viewerSettings.durationTextSize)
                or (groupSettings and groupSettings.cooldownFontSize)
                or (viewerSettings and viewerSettings.cooldownFontSize)
                or (general and general.cooldownFontSize)
                or fontSize
            textColor = (groupSettings and groupSettings.durationTextColor)
                or (viewerSettings and viewerSettings.durationTextColor)
                or (groupSettings and groupSettings.cooldownTextColor)
                or (viewerSettings and viewerSettings.cooldownTextColor)
                or (general and general.cooldownTextColor)
                or textColor
            fontName = (groupSettings and groupSettings.durationTextFont)
                or (viewerSettings and viewerSettings.durationTextFont)
                or (groupSettings and groupSettings.cooldownFont)
                or (viewerSettings and viewerSettings.cooldownFont)
                or (general and general.cooldownFont)
        else
            fontSize = (groupSettings and groupSettings.cooldownFontSize)
                or (viewerSettings and viewerSettings.cooldownFontSize)
                or (general and general.cooldownFontSize)
                or fontSize
            textColor = (groupSettings and groupSettings.cooldownTextColor)
                or (viewerSettings and viewerSettings.cooldownTextColor)
                or (general and general.cooldownTextColor)
                or textColor
            fontName = (groupSettings and groupSettings.cooldownFont)
                or (viewerSettings and viewerSettings.cooldownFont)
                or (general and general.cooldownFont)
        end

        shadowOffsetX = (viewerSettings and viewerSettings.cooldownShadowOffsetX)
            or (general and general.cooldownShadowOffsetX)
            or shadowOffsetX
        shadowOffsetY = (viewerSettings and viewerSettings.cooldownShadowOffsetY)
            or (general and general.cooldownShadowOffsetY)
            or shadowOffsetY
        textFormat = (groupSettings and groupSettings.cooldownTextFormat)
            or (viewerSettings and viewerSettings.cooldownTextFormat)
            or (general and general.cooldownTextFormat)
            or textFormat

        return fontSize, textColor, shadowOffsetX, shadowOffsetY, fontName, textFormat
    end

    -- Always apply fonts to DDingUI's own elements (cooldown viewers, target auras, etc.)
    if not self._cooldownFontHooked then
        local function IdentifyCooldownSource(cooldownFrame)
            if not IsSafeCooldownFrame(cooldownFrame) then return nil end

            local parent = SafeGetParent(cooldownFrame)
            if not parent then return nil end

            -- [REPARENT] DDingUI GroupSystem: 관리 아이콘 → 소속 뷰어 resolve
            -- UIParent reparent 후 GetParent()는 UIParent → _ddContainerRef 우선
            local container
            pcall(function()
                container = parent._ddContainerRef
            end)
            container = container or SafeGetParent(parent)

            local isDDContainer, groupName
            pcall(function()
                isDDContainer = container and container._isDDContainer
                groupName = container and container._groupName
            end)
            if container and isDDContainer and groupName then
                return BuildManagedSource(parent, groupName)
            end

            local iconFrame = parent
            local hasIcon, hasCooldownRef
            pcall(function()
                hasIcon = iconFrame.icon or iconFrame.Icon
                hasCooldownRef = iconFrame.cooldown == cooldownFrame
            end)

            if hasIcon or hasCooldownRef then
                -- DDingUI CustomIcons: inherit GroupSystem text settings while managed.
                local managedGroupName
                pcall(function()
                    managedGroupName = iconFrame._ddGroupName
                    if not managedGroupName and iconFrame._ddContainerRef then
                        managedGroupName = iconFrame._ddContainerRef._groupName
                    end
                end)
                local managedSource = BuildManagedSource(iconFrame, managedGroupName)
                if managedSource then
                    return managedSource
                end

                local viewerFrame = SafeGetParent(iconFrame)
                if viewerFrame then
                    local viewerName = SafeGetName(viewerFrame)
                    if viewerName then
                        if viewerName == "EssentialCooldownViewer" then
                            return "EssentialCooldownViewer"
                        elseif viewerName == "UtilityCooldownViewer" then
                            return "UtilityCooldownViewer"
                        elseif viewerName == "BuffIconCooldownViewer" then
                            return "BuffIconCooldownViewer"
                            elseif viewerName == "DDingUI_Target" then
                                if viewerFrame.buffIcons or viewerFrame.debuffIcons then
                                    local isInArray = false
                                    if viewerFrame.buffIcons then
                                        for _, buffIcon in ipairs(viewerFrame.buffIcons) do
                                            if buffIcon == iconFrame then
                                                isInArray = true
                                                break
                                            end
                                        end
                                    end
                                    if not isInArray and viewerFrame.debuffIcons then
                                        for _, debuffIcon in ipairs(viewerFrame.debuffIcons) do
                                            if debuffIcon == iconFrame then
                                                isInArray = true
                                                break
                                            end
                                        end
                                    end
                                    if isInArray or (viewerFrame.buffIcons and #viewerFrame.buffIcons > 0) or (viewerFrame.debuffIcons and #viewerFrame.debuffIcons > 0) then
                                        return "targetAuras"
                                    end
                                end
                            end
                        end

                        -- Also check if viewerFrame's parent is DDingUI_Target (in case of nested frames)
                        local targetFrame = SafeGetParent(viewerFrame)
                        if targetFrame then
                            local targetFrameName = SafeGetName(targetFrame)
                            if targetFrameName == "DDingUI_Target" then
                                -- Check if this icon frame is in buffIcons or debuffIcons
                                if targetFrame.buffIcons or targetFrame.debuffIcons then
                                    -- Double-check by seeing if iconFrame is in the arrays
                                    local isInArray = false
                                    if targetFrame.buffIcons then
                                        for _, buffIcon in ipairs(targetFrame.buffIcons) do
                                            if buffIcon == iconFrame then
                                                isInArray = true
                                                break
                                            end
                                        end
                                    end
                                    if not isInArray and targetFrame.debuffIcons then
                                        for _, debuffIcon in ipairs(targetFrame.debuffIcons) do
                                            if debuffIcon == iconFrame then
                                                isInArray = true
                                                break
                                            end
                                        end
                                    end
                                    if isInArray or (targetFrame.buffIcons and #targetFrame.buffIcons > 0) or (targetFrame.debuffIcons and #targetFrame.debuffIcons > 0) then
                                        return "targetAuras"
                                    end
                                end
                            end
                        end
                end
            else
                local viewerName = SafeGetName(parent)
                if viewerName then
                    if viewerName == "EssentialCooldownViewer" then
                        return "EssentialCooldownViewer"
                    elseif viewerName == "UtilityCooldownViewer" then
                        return "UtilityCooldownViewer"
                    elseif viewerName == "BuffIconCooldownViewer" then
                        return "BuffIconCooldownViewer"
                    elseif viewerName == "DDingUI_Target" then
                        if parent.buffIcons or parent.debuffIcons then
                            return "targetAuras"
                        end
                    end
                end

                local targetFrame = SafeGetParent(parent)
                if targetFrame then
                    local targetFrameName = SafeGetName(targetFrame)
                    if targetFrameName == "DDingUI_Target" then
                        if targetFrame.buffIcons or targetFrame.debuffIcons then
                            return "targetAuras"
                        end
                    end
                end
            end

            return nil
        end

        local function GetCooldownSettings(source)
            local fontSize = 18
            local textColor = {1, 1, 1, 1}
            local shadowOffsetX = 1
            local shadowOffsetY = -1
            local fontName = nil
            local textFormat = "auto"

            if source and type(source) == "string" then
                local iconKey, groupName = source:match("^customIcon:([^:]+):group:(.+)$")
                if iconKey and groupName then
                    local iconData = GetDynamicIconData(iconKey)
                    local gFontSize, gTextColor, gShadowX, gShadowY, gFontName, gTextFormat = ResolveGroupCooldownSettings(groupName, iconData)
                    if gFontSize then
                        return gFontSize, gTextColor, gShadowX, gShadowY, gFontName, gTextFormat
                    end
                end

                local sourceGroup = source:match("^group:(.+):buff$")
                local sourceViewer = sourceGroup and "BuffIconCooldownViewer" or nil
                sourceGroup = sourceGroup or source:match("^group:(.+)$")
                if sourceGroup then
                    local gFontSize, gTextColor, gShadowX, gShadowY, gFontName, gTextFormat =
                        ResolveGroupCooldownSettings(sourceGroup, nil, sourceViewer)
                    if gFontSize then
                        return gFontSize, gTextColor, gShadowX, gShadowY, gFontName, gTextFormat
                    end
                    source = GROUP_TO_VIEWER[sourceGroup] or source
                end

                local iconKey = source:match("^customIcon:(.+)$")
                if iconKey then
                    -- Use per-icon settings where available; fallback to global viewer general settings.
                    local iconData = GetDynamicIconData(iconKey)

                    local cds = iconData and iconData.settings and iconData.settings.cooldownSettings
                    fontSize = (cds and cds.size) or 12
                    textColor = (cds and cds.color) or { 1, 1, 1, 1 }

                    if self.db and self.db.profile and self.db.profile.viewers and self.db.profile.viewers.general then
                        shadowOffsetX = self.db.profile.viewers.general.cooldownShadowOffsetX or shadowOffsetX
                        shadowOffsetY = self.db.profile.viewers.general.cooldownShadowOffsetY or shadowOffsetY
                        fontName = self.db.profile.viewers.general.cooldownFont
                        textFormat = self.db.profile.viewers.general.cooldownTextFormat or "auto"
                    end

                    return fontSize, textColor, shadowOffsetX, shadowOffsetY, fontName, textFormat
                end
            end

            if source == "targetAuras" then
                -- Get from target auras settings
                if self.db and self.db.profile and self.db.profile.unitFrames and
                   self.db.profile.unitFrames.target and self.db.profile.unitFrames.target.Auras then
                    local auraSettings = self.db.profile.unitFrames.target.Auras
                    fontSize = auraSettings.cooldownFontSize or
                              (self.db.profile.viewers.general and self.db.profile.viewers.general.cooldownFontSize) or 18
                    textColor = auraSettings.cooldownTextColor or
                               (self.db.profile.viewers.general and self.db.profile.viewers.general.cooldownTextColor) or {1, 1, 1, 1}
                    shadowOffsetX = auraSettings.cooldownShadowOffsetX or
                                   (self.db.profile.viewers.general and self.db.profile.viewers.general.cooldownShadowOffsetX) or 1
                    shadowOffsetY = auraSettings.cooldownShadowOffsetY or
                                   (self.db.profile.viewers.general and self.db.profile.viewers.general.cooldownShadowOffsetY) or -1
                    fontName = auraSettings.cooldownFont or
                              (self.db.profile.viewers.general and self.db.profile.viewers.general.cooldownFont)
                end
            elseif source and (source == "EssentialCooldownViewer" or source == "UtilityCooldownViewer" or source == "BuffIconCooldownViewer") then
                -- Get from viewer-specific settings
                if self.db and self.db.profile and self.db.profile.viewers and self.db.profile.viewers[source] then
                    local viewerSettings = self.db.profile.viewers[source]
                    fontSize = viewerSettings.cooldownFontSize or
                              (self.db.profile.viewers.general and self.db.profile.viewers.general.cooldownFontSize) or 18
                    textColor = viewerSettings.cooldownTextColor or
                               (self.db.profile.viewers.general and self.db.profile.viewers.general.cooldownTextColor) or {1, 1, 1, 1}
                    shadowOffsetX = viewerSettings.cooldownShadowOffsetX or
                                   (self.db.profile.viewers.general and self.db.profile.viewers.general.cooldownShadowOffsetX) or 1
                    shadowOffsetY = viewerSettings.cooldownShadowOffsetY or
                                   (self.db.profile.viewers.general and self.db.profile.viewers.general.cooldownShadowOffsetY) or -1
                    fontName = viewerSettings.cooldownFont or
                              (self.db.profile.viewers.general and self.db.profile.viewers.general.cooldownFont)
                    textFormat = viewerSettings.cooldownTextFormat or
                                (self.db.profile.viewers.general and self.db.profile.viewers.general.cooldownTextFormat) or "auto"
                end
            else
                -- Fallback to general settings
                if self.db and self.db.profile and self.db.profile.viewers and self.db.profile.viewers.general then
                    fontSize = self.db.profile.viewers.general.cooldownFontSize or 18
                    textColor = self.db.profile.viewers.general.cooldownTextColor or {1, 1, 1, 1}
                    shadowOffsetX = self.db.profile.viewers.general.cooldownShadowOffsetX or 1
                    shadowOffsetY = self.db.profile.viewers.general.cooldownShadowOffsetY or -1
                    fontName = self.db.profile.viewers.general.cooldownFont
                    textFormat = self.db.profile.viewers.general.cooldownTextFormat or "auto"
                end
            end

            return fontSize, textColor, shadowOffsetX, shadowOffsetY, fontName, textFormat
        end

        local function GetCooldownFontString(cooldownFrame)
            if not IsSafeCooldownFrame(cooldownFrame) then return nil end

            local cachedFontString
            pcall(function()
                cachedFontString = cooldownFrame._ddingui_fontString
            end)
            if cachedFontString then return cachedFontString end

            local regions = SafeGetRegions(cooldownFrame)
            if not regions then return nil end

            for _, region in ipairs(regions) do
                if SafeGetObjectType(region) == "FontString" then
                    pcall(function()
                        cooldownFrame._ddingui_fontString = region
                    end)
                    return region
                end
            end

            return nil
        end

        -- Format cooldown time based on format setting
        local function FormatCooldownTime(seconds, format)
            if not seconds or seconds <= 0 then return "" end

            if format == "seconds" then
                -- Always show seconds only
                return string.format("%d", math.ceil(seconds))
            elseif format == "mmss" then
                -- Always show MM:SS format
                local mins = math.floor(seconds / 60)
                local secs = math.ceil(seconds % 60)
                if secs == 60 then
                    mins = mins + 1
                    secs = 0
                end
                return string.format("%d:%02d", mins, secs)
            elseif format == "decimal" then
                -- Show decimal for under 10 seconds
                if seconds < 10 then
                    return string.format("%.1f", seconds)
                elseif seconds < 60 then
                    return string.format("%d", math.ceil(seconds))
                else
                    local mins = math.floor(seconds / 60)
                    local secs = math.ceil(seconds % 60)
                    if secs == 60 then
                        mins = mins + 1
                        secs = 0
                    end
                    return string.format("%d:%02d", mins, secs)
                end
            end

            -- "auto" - return nil to use Blizzard default
            return nil
        end

        -- Hook fontstring SetText for custom format
        local function HookCooldownTextFormat(cooldownFrame, fontString, format)
            if not fontString then return end
            fontString._ddingui_textFormat = format or "auto"
            fontString._ddingui_cooldown = cooldownFrame
            if format == "auto" then return end
            if fontString._ddingui_textFormatHooked then return end

            fontString._ddingui_textFormatHooked = true

            hooksecurefunc(fontString, "SetText", function(self, text)
                if self._ddingui_skipFormat then return end

                local fmt = self._ddingui_textFormat
                if not fmt or fmt == "auto" then return end

                local cd = self._ddingui_cooldown
                if not cd then return end

                -- Get remaining time from cooldown frame
                -- Wrap in pcall: GetCooldownTimes() returns secret values during combat (WoW 12.0+)
                local ok, newText = pcall(function()
                    local start, duration = cd:GetCooldownTimes()
                    if not start or not duration or duration == 0 then return nil end

                    local remaining = (start + duration) / 1000 - GetTime()
                    if remaining <= 0 then return nil end

                    return FormatCooldownTime(remaining, fmt)
                end)
                if ok and newText and newText ~= text then
                    self._ddingui_skipFormat = true
                    self:SetText(newText)
                    self._ddingui_skipFormat = nil
                end
            end)
        end

        local function ApplyCooldownFont(cooldownFrame)
            if not IsSafeCooldownFrame(cooldownFrame) then return end

            -- Skip action button cooldowns to avoid taint
            local parent = SafeGetParent(cooldownFrame)
            if parent then
                local parentName = SafeGetName(parent) or ""
                -- Check if this is an action button cooldown
                if parentName:match("ActionButton") or parentName:match("MultiBar") or
                   parentName:match("PetActionButton") or parentName:match("StanceButton") then
                    return
                end
            end

            -- Only apply to DDingUI frames - skip if source is nil
            local source = IdentifyCooldownSource(cooldownFrame)
            if not source then
                return -- Not a DDingUI frame, don't modify
            end

            local fontString = GetCooldownFontString(cooldownFrame)
            if not fontString then
                C_Timer.After(0, function()
                    local delayedFontString = GetCooldownFontString(cooldownFrame)
                    if delayedFontString then
                        local delayedSource = IdentifyCooldownSource(cooldownFrame)
                        if not delayedSource then return end
                        local fontSize, textColor, shadowOffsetX, shadowOffsetY, fontName, textFormat = GetCooldownSettings(delayedSource)
                        local currentFontPath = self:GetFont(fontName)
                        if currentFontPath then
                            local _, existingSize, flags = delayedFontString:GetFont()
                            if flags then
                                delayedFontString:SetFont(currentFontPath, fontSize, flags)
                            else
                                delayedFontString:SetFont(currentFontPath, fontSize)
                            end

                            SafeSetTextColor(delayedFontString, textColor)
                            delayedFontString:SetShadowOffset(shadowOffsetX, shadowOffsetY)

                            -- Hook text format
                            HookCooldownTextFormat(cooldownFrame, delayedFontString, textFormat)
                        end
                    end
                end)
                return
            end

            local fontSize, textColor, shadowOffsetX, shadowOffsetY, fontName, textFormat = GetCooldownSettings(source)
            local currentFontPath = self:GetFont(fontName)
            if currentFontPath then
                local _, existingSize, flags = fontString:GetFont()
                if flags then
                    fontString:SetFont(currentFontPath, fontSize, flags)
                else
                    fontString:SetFont(currentFontPath, fontSize)
                end

                SafeSetTextColor(fontString, textColor)
                fontString:SetShadowOffset(shadowOffsetX, shadowOffsetY)

                -- Hook text format
                HookCooldownTextFormat(cooldownFrame, fontString, textFormat)
            end
        end

        if CooldownFrame_Set then
            hooksecurefunc("CooldownFrame_Set", function(cooldownFrame, start, duration, enable, forceShowDrawEdge, modRate)
                if not IsSafeCooldownFrame(cooldownFrame) then
                    return
                end

                -- Use pcall to safely handle any errors during combat
                pcall(function()
                    SafeClearCooldownFontCache(cooldownFrame)
                    C_Timer.After(0, function()
                        if IsSafeCooldownFrame(cooldownFrame) then
                            pcall(ApplyCooldownFont, cooldownFrame)
                        end
                    end)
                end)
            end)
        end

        if CooldownFrame_SetTimer then
            hooksecurefunc("CooldownFrame_SetTimer", function(cooldownFrame, start, duration, enable, forceShowDrawEdge, modRate)
                if not IsSafeCooldownFrame(cooldownFrame) then
                    return
                end

                -- Use pcall to safely handle any errors during combat
                pcall(function()
                    SafeClearCooldownFontCache(cooldownFrame)
                    C_Timer.After(0, function()
                        if IsSafeCooldownFrame(cooldownFrame) then
                            pcall(ApplyCooldownFont, cooldownFrame)
                        end
                    end)
                end)
            end)
        end

        -- Don't wrap ActionButton_UpdateCooldown as it causes taint issues
        -- Action button cooldowns should be handled by the ActionBars module if needed

        hooksecurefunc("CreateFrame", function(frameType, name, parent, template)
            if frameType == "Cooldown" then
                C_Timer.After(0, function()
                    -- Skip action button cooldowns to avoid taint
                    local frameName = name or ""
                    if frameName:match("ActionButton") or frameName:match("MultiBar") or
                       frameName:match("PetActionButton") or frameName:match("StanceButton") then
                        return
                    end

                    local cooldownFrame = name and _G[name] or nil
                    if not cooldownFrame and parent then
                        local children = SafeGetChildren(parent)
                        for _, child in ipairs(children or {}) do
                            if SafeGetObjectType(child) == "Cooldown" then
                                cooldownFrame = child
                                break
                            end
                        end
                    end
                    if cooldownFrame then
                        ApplyCooldownFont(cooldownFrame)
                    end
                end)
            end
        end)

        local function ApplyFontToExistingCooldowns()
            local currentFontPath = self:GetGlobalFont()
            if currentFontPath then
                ForEachOwnedCooldownFrame(function(frame)
                    SafeClearCooldownFontCache(frame)
                    ApplyCooldownFont(frame)
                end)
            end
        end

        C_Timer.After(1.0, ApplyFontToExistingCooldowns)

        if DDingUI.UnitFrames and DDingUI.UnitFrames.UpdateTargetAuras then
            local originalUpdateTargetAuras = DDingUI.UnitFrames.UpdateTargetAuras
            DDingUI.UnitFrames.UpdateTargetAuras = function(frame, ...)
                local result = originalUpdateTargetAuras(frame, ...)
                C_Timer.After(0.1, function()
                    if frame and (frame.buffIcons or frame.debuffIcons) then
                        local allIcons = {}
                        if frame.buffIcons then
                            for _, iconFrame in ipairs(frame.buffIcons) do
                                if iconFrame.cooldown then
                                    table.insert(allIcons, iconFrame.cooldown)
                                end
                            end
                        end
                        if frame.debuffIcons then
                            for _, iconFrame in ipairs(frame.debuffIcons) do
                                if iconFrame.cooldown then
                                    table.insert(allIcons, iconFrame.cooldown)
                                end
                            end
                        end
                        for _, cooldownFrame in ipairs(allIcons) do
                            SafeClearCooldownFontCache(cooldownFrame)
                            ApplyCooldownFont(cooldownFrame)
                        end
                    end
                end)
                return result
            end
        end

        -- [REPARENT] GroupSystem reparent 후 쿨다운 폰트 재적용 API
        DDingUI.ReapplyCooldownFonts = ApplyFontToExistingCooldowns

        self._cooldownFontHooked = true
    else
        local currentFontPath = self:GetGlobalFont()
        if currentFontPath then
            local function IdentifyCooldownSource(cooldownFrame)
                if not IsSafeCooldownFrame(cooldownFrame) then return nil end

                local parent = SafeGetParent(cooldownFrame)
                if not parent then return nil end

                -- [REPARENT] DDingUI GroupSystem: 관리 아이콘 → 소속 뷰어 resolve
                -- UIParent reparent 후 GetParent()는 UIParent → _ddContainerRef 우선
                local container
                pcall(function()
                    container = parent._ddContainerRef
                end)
                container = container or SafeGetParent(parent)

                local isDDContainer, groupName
                pcall(function()
                    isDDContainer = container and container._isDDContainer
                groupName = container and container._groupName
            end)
            if container and isDDContainer and groupName then
                    return BuildManagedSource(parent, groupName)
                end

                -- Check if parent is an icon frame (has icon texture or cooldown property)
                -- For target auras: iconFrame is parent of cooldown, and iconFrame's parent is DDingUI_Target
                local iconFrame = parent
                local hasIcon, hasCooldownRef
                pcall(function()
                    hasIcon = iconFrame.icon or iconFrame.Icon
                    hasCooldownRef = iconFrame.cooldown == cooldownFrame
                end)

                if hasIcon or hasCooldownRef then
                    local managedGroupName
                    pcall(function()
                        managedGroupName = iconFrame._ddGroupName
                        if not managedGroupName and iconFrame._ddContainerRef then
                            managedGroupName = iconFrame._ddContainerRef._groupName
                        end
                    end)
                    local managedSource = BuildManagedSource(iconFrame, managedGroupName)
                    if managedSource then
                        return managedSource
                    end

                    -- This is likely an icon frame, check its parent
                    local viewerFrame = SafeGetParent(iconFrame)
                    if viewerFrame then
                        local viewerName = SafeGetName(viewerFrame)
                        if viewerName then
                            -- Check if it's one of our viewers
                            if viewerName == "EssentialCooldownViewer" then
                                return "EssentialCooldownViewer"
                            elseif viewerName == "UtilityCooldownViewer" then
                                return "UtilityCooldownViewer"
                            elseif viewerName == "BuffIconCooldownViewer" then
                                return "BuffIconCooldownViewer"
                            elseif viewerName == "DDingUI_Target" then
                                -- This is a target aura icon frame
                                -- Verify by checking if the frame has buffIcons or debuffIcons
                                -- Also check if this iconFrame is actually in those arrays
                                if viewerFrame.buffIcons or viewerFrame.debuffIcons then
                                    -- Double-check by seeing if iconFrame is in the arrays
                                    local isInArray = false
                                    if viewerFrame.buffIcons then
                                        for _, buffIcon in ipairs(viewerFrame.buffIcons) do
                                            if buffIcon == iconFrame then
                                                isInArray = true
                                                break
                                            end
                                        end
                                    end
                                    if not isInArray and viewerFrame.debuffIcons then
                                        for _, debuffIcon in ipairs(viewerFrame.debuffIcons) do
                                            if debuffIcon == iconFrame then
                                                isInArray = true
                                                break
                                            end
                                        end
                                    end
                                    if isInArray or (viewerFrame.buffIcons and #viewerFrame.buffIcons > 0) or (viewerFrame.debuffIcons and #viewerFrame.debuffIcons > 0) then
                                        return "targetAuras"
                                    end
                                end
                            end
                        end

                        -- Also check if viewerFrame's parent is DDingUI_Target (in case of nested frames)
                        local targetFrame = SafeGetParent(viewerFrame)
                        if targetFrame then
                            local targetFrameName = SafeGetName(targetFrame)
                            if targetFrameName == "DDingUI_Target" then
                                -- Check if this icon frame is in buffIcons or debuffIcons
                                if targetFrame.buffIcons or targetFrame.debuffIcons then
                                    -- Double-check by seeing if iconFrame is in the arrays
                                    local isInArray = false
                                    if targetFrame.buffIcons then
                                        for _, buffIcon in ipairs(targetFrame.buffIcons) do
                                            if buffIcon == iconFrame then
                                                isInArray = true
                                                break
                                            end
                                        end
                                    end
                                    if not isInArray and targetFrame.debuffIcons then
                                        for _, debuffIcon in ipairs(targetFrame.debuffIcons) do
                                            if debuffIcon == iconFrame then
                                                isInArray = true
                                                break
                                            end
                                        end
                                    end
                                    if isInArray or (targetFrame.buffIcons and #targetFrame.buffIcons > 0) or (targetFrame.debuffIcons and #targetFrame.debuffIcons > 0) then
                                        return "targetAuras"
                                    end
                                end
                            end
                        end
                    end
                else
                    -- Parent might be the viewer frame directly
                    local viewerName = SafeGetName(parent)
                    if viewerName then
                        if viewerName == "EssentialCooldownViewer" then
                            return "EssentialCooldownViewer"
                        elseif viewerName == "UtilityCooldownViewer" then
                            return "UtilityCooldownViewer"
                        elseif viewerName == "BuffIconCooldownViewer" then
                            return "BuffIconCooldownViewer"
                        elseif viewerName == "DDingUI_Target" then
                            -- Direct child of target frame - check if it has aura properties
                            if parent.buffIcons or parent.debuffIcons then
                                return "targetAuras"
                            end
                        end
                    end

                    -- Check if parent is part of target auras
                    local targetFrame = SafeGetParent(parent)
                    if targetFrame then
                        local targetFrameName = SafeGetName(targetFrame)
                        if targetFrameName == "DDingUI_Target" then
                            if targetFrame.buffIcons or targetFrame.debuffIcons then
                                return "targetAuras"
                            end
                        end
                    end
                end

                return nil
            end

            local function GetCooldownSettings(source)
                local fontSize = 18
                local textColor = {1, 1, 1, 1}
                local shadowOffsetX = 1
                local shadowOffsetY = -1
                local fontName = nil

                if source and type(source) == "string" then
                    local iconKey, groupName = source:match("^customIcon:([^:]+):group:(.+)$")
                    if iconKey and groupName then
                        local iconData = GetDynamicIconData(iconKey)
                        local gFontSize, gTextColor, gShadowX, gShadowY, gFontName = ResolveGroupCooldownSettings(groupName, iconData)
                        if gFontSize then
                            return gFontSize, gTextColor, gShadowX, gShadowY, gFontName
                        end
                    end

                    local sourceGroup = source:match("^group:(.+):buff$")
                    local sourceViewer = sourceGroup and "BuffIconCooldownViewer" or nil
                    sourceGroup = sourceGroup or source:match("^group:(.+)$")
                    if sourceGroup then
                        local gFontSize, gTextColor, gShadowX, gShadowY, gFontName =
                            ResolveGroupCooldownSettings(sourceGroup, nil, sourceViewer)
                        if gFontSize then
                            return gFontSize, gTextColor, gShadowX, gShadowY, gFontName
                        end
                        source = GROUP_TO_VIEWER[sourceGroup] or source
                    end
                end

                if source == "targetAuras" then
                    -- Get from target auras settings
                    if self.db and self.db.profile and self.db.profile.unitFrames and
                       self.db.profile.unitFrames.target and self.db.profile.unitFrames.target.Auras then
                        local auraSettings = self.db.profile.unitFrames.target.Auras
                        fontSize = auraSettings.cooldownFontSize or
                                  (self.db.profile.viewers.general and self.db.profile.viewers.general.cooldownFontSize) or 18
                        textColor = auraSettings.cooldownTextColor or
                                   (self.db.profile.viewers.general and self.db.profile.viewers.general.cooldownTextColor) or {1, 1, 1, 1}
                        shadowOffsetX = auraSettings.cooldownShadowOffsetX or
                                       (self.db.profile.viewers.general and self.db.profile.viewers.general.cooldownShadowOffsetX) or 1
                        shadowOffsetY = auraSettings.cooldownShadowOffsetY or
                                       (self.db.profile.viewers.general and self.db.profile.viewers.general.cooldownShadowOffsetY) or -1
                        fontName = auraSettings.cooldownFont or
                                  (self.db.profile.viewers.general and self.db.profile.viewers.general.cooldownFont)
                    end
                elseif source and (source == "EssentialCooldownViewer" or source == "UtilityCooldownViewer" or source == "BuffIconCooldownViewer") then
                    -- Get from viewer-specific settings
                    if self.db and self.db.profile and self.db.profile.viewers and self.db.profile.viewers[source] then
                        local viewerSettings = self.db.profile.viewers[source]
                        fontSize = viewerSettings.cooldownFontSize or
                                  (self.db.profile.viewers.general and self.db.profile.viewers.general.cooldownFontSize) or 18
                        textColor = viewerSettings.cooldownTextColor or
                                   (self.db.profile.viewers.general and self.db.profile.viewers.general.cooldownTextColor) or {1, 1, 1, 1}
                        shadowOffsetX = viewerSettings.cooldownShadowOffsetX or
                                       (self.db.profile.viewers.general and self.db.profile.viewers.general.cooldownShadowOffsetX) or 1
                        shadowOffsetY = viewerSettings.cooldownShadowOffsetY or
                                       (self.db.profile.viewers.general and self.db.profile.viewers.general.cooldownShadowOffsetY) or -1
                        fontName = viewerSettings.cooldownFont or
                                  (self.db.profile.viewers.general and self.db.profile.viewers.general.cooldownFont)
                    end
                else
                    if self.db and self.db.profile and self.db.profile.viewers and self.db.profile.viewers.general then
                        fontSize = self.db.profile.viewers.general.cooldownFontSize or 18
                        textColor = self.db.profile.viewers.general.cooldownTextColor or {1, 1, 1, 1}
                        shadowOffsetX = self.db.profile.viewers.general.cooldownShadowOffsetX or 1
                        shadowOffsetY = self.db.profile.viewers.general.cooldownShadowOffsetY or -1
                        fontName = self.db.profile.viewers.general.cooldownFont
                    end
                end

                return fontSize, textColor, shadowOffsetX, shadowOffsetY, fontName
            end

            local function GetCooldownFontString(cooldownFrame)
                if not IsSafeCooldownFrame(cooldownFrame) then return nil end

                local cachedFontString
                pcall(function()
                    cachedFontString = cooldownFrame._ddingui_fontString
                end)
                if cachedFontString then return cachedFontString end

                local regions = SafeGetRegions(cooldownFrame)
                if not regions then return nil end

                for _, region in ipairs(regions) do
                    if SafeGetObjectType(region) == "FontString" then
                        pcall(function()
                            cooldownFrame._ddingui_fontString = region
                        end)
                        return region
                    end
                end
                return nil
            end

            local function ApplyFontToExistingCooldowns()
                ForEachOwnedCooldownFrame(function(frame)
                    local source = IdentifyCooldownSource(frame)
                    if source then
                        SafeClearCooldownFontCache(frame)
                        local fontString = GetCooldownFontString(frame)
                        if fontString then
                            local fontSize, textColor, shadowOffsetX, shadowOffsetY, fontName = GetCooldownSettings(source)
                            local fontPath = self:GetFont(fontName)

                            local _, existingSize, flags = fontString:GetFont()
                            if flags then
                                fontString:SetFont(fontPath, fontSize, flags)
                            else
                                fontString:SetFont(fontPath, fontSize)
                            end
                            SafeSetTextColor(fontString, textColor)
                            fontString:SetShadowOffset(shadowOffsetX, shadowOffsetY)
                        end
                    end
                end)
            end
            ApplyFontToExistingCooldowns()
        end
    end

    -- Apply fonts to Blizzard's quest/tooltip/chat (only if toggle is enabled)
    if applyToBlizzard then
        if not self._questFontHooked then
        if ObjectiveTracker_Update then
            hooksecurefunc("ObjectiveTracker_Update", function()
                if not (self.db and self.db.profile and self.db.profile.general and self.db.profile.general.applyGlobalFontToBlizzard) then
                    return
                end
                local currentFontPath = self:GetGlobalFont()
                if currentFontPath and ObjectiveTrackerFrame then
                    local function ApplyFontToFrame(frame)
                        if not frame then return end
                        local children = {frame:GetChildren()}
                        for _, child in ipairs(children) do
                            if child:IsObjectType("FontString") then
                                local _, size, flags = child:GetFont()
                                if size and flags then
                                    child:SetFont(currentFontPath, size, flags)
                                end
                            end
                            ApplyFontToFrame(child)
                        end
                    end
                    ApplyFontToFrame(ObjectiveTrackerFrame)
                end
            end)
        end
        self._questFontHooked = true
        end

        if not self._tooltipFontHooked then
        if GameTooltip_SetDefaultAnchor then
            hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, owner)
                if not (self.db and self.db.profile and self.db.profile.general and self.db.profile.general.applyGlobalFontToBlizzard) then
                    return
                end
                local currentFontPath = self:GetGlobalFont()
                if currentFontPath and tooltip then
                    local function ApplyFontToTooltip(tip)
                        if not tip then return end
                        local children = {tip:GetChildren()}
                        for _, child in ipairs(children) do
                            if child:IsObjectType("FontString") then
                                local _, size, flags = child:GetFont()
                                if size and flags then
                                    child:SetFont(currentFontPath, size, flags)
                                end
                            end
                            ApplyFontToTooltip(child)
                        end
                    end
                    ApplyFontToTooltip(tooltip)
                end
            end)
        end

        if GameTooltip_OnLoad then
            hooksecurefunc("GameTooltip_OnLoad", function(tooltip)
                if not (self.db and self.db.profile and self.db.profile.general and self.db.profile.general.applyGlobalFontToBlizzard) then
                    return
                end
                local currentFontPath = self:GetGlobalFont()
                if currentFontPath and tooltip then
                    local function ApplyFontToTooltip(tip)
                        if not tip then return end
                        local children = {tip:GetChildren()}
                        for _, child in ipairs(children) do
                            if child:IsObjectType("FontString") then
                                local _, size, flags = child:GetFont()
                                if size and flags then
                                    child:SetFont(currentFontPath, size, flags)
                                end
                            end
                            ApplyFontToTooltip(child)
                        end
                    end
                    ApplyFontToTooltip(tooltip)
                end
            end)
        end
        self._tooltipFontHooked = true
        end

        if not self._chatFontHooked then
        if FCF_SetChatWindowFontSize then
            hooksecurefunc("FCF_SetChatWindowFontSize", function(frame, size)
                if not (self.db and self.db.profile and self.db.profile.general and self.db.profile.general.applyGlobalFontToBlizzard) then
                    return
                end
                local currentFontPath = self:GetGlobalFont()
                if currentFontPath and frame and frame:GetFont() then
                    local _, currentSize, flags = frame:GetFont()
                    if currentSize and flags then
                        frame:SetFont(currentFontPath, currentSize, flags)
                    end
                end
            end)
        end

        -- Apply fonts to existing chat frames (only if toggle is enabled)
        if applyToBlizzard then
            local numChatWindows = NUM_CHAT_WINDOWS
            if not numChatWindows then
                numChatWindows = 10
            end
            for i = 1, numChatWindows do
                local chatFrame = _G["ChatFrame" .. i]
                if chatFrame then
                    local _, size, flags = chatFrame:GetFont()
                    if size and flags then
                        chatFrame:SetFont(fontPath, size, flags)
                    end
                end
            end

            if DEFAULT_CHAT_FRAME then
                local _, size, flags = DEFAULT_CHAT_FRAME:GetFont()
                if size and flags then
                    DEFAULT_CHAT_FRAME:SetFont(fontPath, size, flags)
                end
            end
        end

        self._chatFontHooked = true
        end
    end -- End of applyToBlizzard conditional for quest/tooltip/chat hooks
end

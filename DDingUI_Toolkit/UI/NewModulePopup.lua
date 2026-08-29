-- DDingUI Toolkit - one-time update notice for newly added modules

local addonName, ns = ...
local L = ns.L
local Lib = LibStub("DDingUI-StyleLib-1.0")
local SOLID = Lib.Textures and Lib.Textures.flat or "Interface\\Buttons\\WHITE8x8"
local FONT = Lib.Font and Lib.Font.path or "Fonts\\2002.TTF"

local Popup = {}
ns.NewModulePopup = Popup

local MODULES = {
    {
        id = "PremadeGroupFilter-2.1.2",
        introducedVersion = "2.1.2",
        module = "PremadeGroupFilter",
        titleKey = "PGF_TITLE",
        descKey = "NEW_MODULE_POPUP_PGF_DESC",
        icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend",
    },
    {
        id = "CombatStateAlert-2.1.2",
        introducedVersion = "2.1.2",
        module = "CombatStateAlert",
        titleKey = "CSA_TITLE",
        descKey = "NEW_MODULE_POPUP_CSA_DESC",
        spellID = 6673,
    },
    {
        id = "StasisTracker-2.1.2",
        introducedVersion = "2.1.2",
        module = "StasisTracker",
        titleKey = "STASISTRACKER_TITLE",
        descKey = "NEW_MODULE_POPUP_STASIS_DESC",
        spellID = 370537,
    },
    {
        id = "BloodlustTimer-2.1.2",
        introducedVersion = "2.1.2",
        module = "BloodlustTimer",
        titleKey = "BLT_TITLE",
        descKey = "NEW_MODULE_POPUP_BLOODLUST_DESC",
        spellID = 2825,
    },
    {
        id = "ReadyCheckAssistant-2.1.2",
        introducedVersion = "2.1.2",
        module = "ReadyCheckAssistant",
        titleKey = "RCA_TITLE",
        descKey = "NEW_MODULE_POPUP_READY_DESC",
        icon = "Interface\\Icons\\INV_Misc_Note_01",
    },
    {
        id = "RaidGroups-2.1.3",
        introducedVersion = "2.1.3",
        module = "RaidGroups",
        titleKey = "RAIDGROUPS_TITLE",
        descKey = "NEW_MODULE_POPUP_RAIDGROUPS_DESC",
        icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend",
    },
    {
        id = "RaidPreparation-2.1.3",
        introducedVersion = "2.1.3",
        module = "RaidPreparation",
        titleKey = "RAIDPREP_TITLE",
        descKey = "NEW_MODULE_POPUP_RAIDPREP_DESC",
        icon = "Interface\\Icons\\INV_Misc_Note_01",
    },
    {
        id = "RaidPartyTooltip-2.1.3",
        introducedVersion = "2.1.3",
        module = "RaidPartyTooltip",
        titleKey = "RPT_TITLE",
        descKey = "NEW_MODULE_POPUP_RPT_DESC",
        icon = "Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend",
    },
    {
        id = "RaidDefensiveTracker-2.1.4",
        introducedVersion = "2.1.4",
        module = "RaidDefensiveTracker",
        titleKey = "RDT_TITLE",
        descKey = "NEW_MODULE_POPUP_RDT_DESC",
        spellID = 97462,
    },
    {
        id = "VoidcoreHelper-2.1.5",
        introducedVersion = "2.1.5",
        module = "VoidcoreHelper",
        titleKey = "VCH_TITLE",
        descKey = "NEW_MODULE_POPUP_VCH_DESC",
        icon = "Interface\\Icons\\INV_Misc_Gem_Amethyst_02",
    },
}

local function VersionParts(version)
    local parts = {}
    for number in tostring(version or ""):gmatch("%d+") do
        parts[#parts + 1] = tonumber(number) or 0
    end
    return parts
end

local function IsVersionAtLeast(currentVersion, requiredVersion)
    local current = VersionParts(currentVersion)
    local required = VersionParts(requiredVersion)
    local count = math.max(#current, #required)

    for index = 1, count do
        local currentPart = current[index] or 0
        local requiredPart = required[index] or 0
        if currentPart ~= requiredPart then
            return currentPart > requiredPart
        end
    end
    return true
end

local function ResolveIcon(entry)
    if entry.icon then return entry.icon end

    local texture
    if C_Spell and C_Spell.GetSpellTexture then
        texture = C_Spell.GetSpellTexture(entry.spellID)
    elseif GetSpellTexture then
        texture = GetSpellTexture(entry.spellID)
    end
    return texture or 134400
end

local function DisablePixelSnap(texture)
    if not texture then return end
    if texture.SetSnapToPixelGrid then
        texture:SetSnapToPixelGrid(false)
        texture:SetTexelSnappingBias(0)
    end
end

local function AddFont(parent, size, color, text)
    local fontString = parent:CreateFontString(nil, "OVERLAY")
    fontString:SetFont(FONT, size, "")
    fontString:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    fontString:SetText(text or "")
    fontString:SetShadowOffset(1, -1)
    fontString:SetShadowColor(0, 0, 0, 0.9)
    return fontString
end

local function GetNoticeState()
    local global = ns.db and ns.db.global
    if type(global) ~= "table" then return nil end

    if type(global.newModuleNotices) ~= "table" then
        global.newModuleNotices = {}
    end
    if type(global.newModuleNotices.seen) ~= "table" then
        global.newModuleNotices.seen = {}
    end
    return global.newModuleNotices.seen
end

function Popup:GetEligibleEntries(includeSeen)
    local seen = GetNoticeState()
    if not seen then return {} end

    local currentVersion = ns.DDingToolKit and ns.DDingToolKit.version or "0"
    local entries = {}
    for _, entry in ipairs(MODULES) do
        if IsVersionAtLeast(currentVersion, entry.introducedVersion)
            and (includeSeen or not seen[entry.id]) then
            entries[#entries + 1] = entry
        end
    end
    return entries
end

function Popup:MarkSeen(entries)
    local seen = GetNoticeState()
    if not seen then return end

    for _, entry in ipairs(entries) do
        seen[entry.id] = true
    end
end

function Popup:CreateFrame(entries)
    local P = ns.UI and ns.UI.popupColors or {
        background = { 0.10, 0.10, 0.10, 0.985 }, control = { 0.06, 0.06, 0.06, 0.94 },
        hover = { 0.14, 0.14, 0.15, 0.96 }, border = { 0.30, 0.30, 0.32, 0.82 },
        borderSoft = { 0.25, 0.25, 0.25, 0.50 }, separator = { 0.20, 0.20, 0.20, 0.40 },
        accent = { 0.16, 0.58, 0.68, 0.80 }, accentText = { 0.42, 0.76, 0.82, 1 },
        text = { 0.85, 0.85, 0.85, 1 }, textBright = { 1, 1, 1, 1 }, textDim = { 0.60, 0.60, 0.60, 1 },
    }
    local frameHeight = 156 + (#entries * 60)
    local frame = CreateFrame("Frame", "DDingUIToolkitNewModulePopup", UIParent, "BackdropTemplate")
    frame:SetSize(540, frameHeight)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(120)
    frame:SetClampedToScreen(true)
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetBackdrop({
        bgFile = SOLID,
        edgeFile = SOLID,
        edgeSize = 1,
    })
    frame:SetBackdropColor(unpack(P.background))
    frame:SetBackdropBorderColor(unpack(P.border))

    local accent = frame:CreateTexture(nil, "OVERLAY")
    accent:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
    accent:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
    accent:SetHeight(2)
    accent:SetColorTexture(unpack(P.accent))
    DisablePixelSnap(accent)

    local title = AddFont(frame, 20, P.textBright, L["NEW_MODULE_POPUP_TITLE"])
    title:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -20)

    local version = AddFont(
        frame,
        12,
        P.accentText,
        string.format(L["NEW_MODULE_POPUP_VERSION"], ns.DDingToolKit.version)
    )
    version:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -48, -24)

    local subtitle = AddFont(
        frame,
        12,
        P.textDim,
        string.format(L["NEW_MODULE_POPUP_SUBTITLE"], #entries)
    )
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetPoint("RIGHT", frame, "RIGHT", -24, 0)
    subtitle:SetHeight(34)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetJustifyV("TOP")
    subtitle:SetWordWrap(true)

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(28, 28)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -9, -9)
    close:RegisterForClicks("LeftButtonUp")
    local closeText = AddFont(close, 18, P.textDim, "x")
    closeText:SetPoint("CENTER", close, "CENTER", 0, 1)
    close:SetScript("OnEnter", function()
        closeText:SetTextColor(1, 1, 1, 1)
    end)
    close:SetScript("OnLeave", function()
        closeText:SetTextColor(unpack(P.textDim))
    end)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)

    local separator = frame:CreateTexture(nil, "ARTWORK")
    separator:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -92)
    separator:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -24, -92)
    separator:SetHeight(1)
    separator:SetColorTexture(unpack(P.separator))
    DisablePixelSnap(separator)

    local previous
    for _, entry in ipairs(entries) do
        local moduleName = entry.module
        local row = CreateFrame("Button", nil, frame, "BackdropTemplate")
        row:SetSize(492, 54)
        if previous then
            row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -6)
        else
            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 24, -102)
        end
        row:RegisterForClicks("LeftButtonUp")
        row:SetBackdrop({
            bgFile = SOLID,
            edgeFile = SOLID,
            edgeSize = 1,
        })
        row:SetBackdropColor(unpack(P.control))
        row:SetBackdropBorderColor(unpack(P.borderSoft))

        local iconBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
        iconBorder:SetSize(40, 40)
        iconBorder:SetPoint("LEFT", row, "LEFT", 7, 0)
        iconBorder:SetBackdrop({ edgeFile = SOLID, edgeSize = 1 })
        iconBorder:SetBackdropBorderColor(unpack(P.accent))

        local icon = iconBorder:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", iconBorder, "TOPLEFT", 1, -1)
        icon:SetPoint("BOTTOMRIGHT", iconBorder, "BOTTOMRIGHT", -1, 1)
        icon:SetTexture(ResolveIcon(entry))
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local rowTitle = AddFont(row, 14, P.textBright, L[entry.titleKey])
        rowTitle:SetPoint("TOPLEFT", row, "TOPLEFT", 58, -9)
        rowTitle:SetPoint("RIGHT", row, "RIGHT", -120, 0)
        rowTitle:SetJustifyH("LEFT")
        rowTitle:SetWordWrap(false)

        local description = AddFont(row, 11, P.textDim, L[entry.descKey])
        description:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 58, 9)
        description:SetPoint("RIGHT", row, "RIGHT", -120, 0)
        description:SetJustifyH("LEFT")
        description:SetWordWrap(false)

        local openText = AddFont(row, 11, P.accentText, L["NEW_MODULE_POPUP_OPEN"])
        openText:SetPoint("RIGHT", row, "RIGHT", -12, 0)

        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(unpack(P.hover))
            self:SetBackdropBorderColor(unpack(P.border))
            openText:SetTextColor(unpack(P.textBright))
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropColor(unpack(P.control))
            self:SetBackdropBorderColor(unpack(P.borderSoft))
            openText:SetTextColor(unpack(P.accentText))
        end)
        row:SetScript("OnClick", function()
            frame:Hide()
            ns.DDingToolKit:OpenConfig(moduleName)
        end)

        previous = row
    end

    local confirm = ns.ToolkitControls.CreateButton(
        frame,
        "MJToolkit",
        L["NEW_MODULE_POPUP_CLOSE"],
        function()
            frame:Hide()
        end,
        { width = 116, height = 30 }
    )
    confirm:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -24, 18)

    table.insert(UISpecialFrames, frame:GetName())
    self.frame = frame
    return frame
end

function Popup:Show(entries)
    if self._shown or not entries or #entries == 0 then return end
    self._shown = true
    self:MarkSeen(entries)
    self:CreateFrame(entries):Show()
end

function Popup:TryShow(entries)
    if self._shown then return end
    if InCombatLockdown and InCombatLockdown() then
        C_Timer.After(2, function()
            Popup:TryShow(entries)
        end)
        return
    end
    self:Show(entries)
end

function Popup:Queue()
    if self._queued then return end

    local eligible = self:GetEligibleEntries(false)
    if #eligible == 0 then return end

    self._queued = true
    if ns.isFreshInstall then
        self:MarkSeen(eligible)
        return
    end

    C_Timer.After(1.5, function()
        Popup:TryShow(eligible)
    end)
end

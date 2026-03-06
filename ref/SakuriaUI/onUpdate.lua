SakuriaUI_OnUpdate = SakuriaUI_OnUpdate or {}

-- Notice to myself; needs bump to show popup again
local UPDATE_POPUP_VERSION = 1

-- Content
local UPDATE_TITLE = "|cffffffffSakuria|r|cFFF4B6CBUI|r"
local UPDATE_BODY = [[
New Update:

- Added a fancy update popup
- Icon improvements (desaturation/alpha)
- Various bug fixes & code cleaning

|cFFF4B6CB...and I also had to reset your settings
Type |cffffffff/sui|r to configure them again!|r

Have fun and don't forget to tell me how awesome I am!

For questions or suggestions visit |cFFF4B6CBdiscord.gg/sakuria|r

Much Love XOXO
]]

local BORDER_SIZE = 1
local BG_R, BG_G, BG_B = 42 / 255, 44 / 255, 44 / 255 -- #2A2C2C
local ACCENT_R, ACCENT_G, ACCENT_B = 244 / 255, 182 / 255, 203 / 255 -- #F4B6CB
local FRAME_W, FRAME_H = 500, 400

local frame

local function EnsureDB()
    if SakuriaUI and SakuriaUI.GetDB then
        SakuriaUI:GetDB()
    else
        SakuriaUI_DB = SakuriaUI_DB or {}
    end
end

local function CreateFlatButton(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, h)

    b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    b:SetBackdropColor(0.22, 0.22, 0.22, 1)

    local edge = CreateFrame("Frame", nil, b, "BackdropTemplate")
    edge:SetPoint("TOPLEFT", -1, 1)
    edge:SetPoint("BOTTOMRIGHT", 1, -1)
    edge:SetFrameLevel(b:GetFrameLevel() - 1)
    edge:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    edge:SetBackdropColor(ACCENT_R, ACCENT_G, ACCENT_B, 1)
    b._edge = edge

    local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("CENTER", b, "CENTER", 0, 0)
    label:SetText(text)
    label:SetTextColor(1, 1, 1, 1)
    b:SetFontString(label)

    b:SetScript("OnEnter", function(self)
        self:GetFontString():SetTextColor(0.9, 0.9, 0.9, 1)
        self:SetBackdropColor(0.26, 0.26, 0.26, 1)
    end)

    b:SetScript("OnLeave", function(self)
        self:GetFontString():SetTextColor(1, 1, 1, 1)
        self:SetBackdropColor(0.22, 0.22, 0.22, 1)
    end)

    return b
end

local function MarkSeenAndHide()
    EnsureDB()
    SakuriaUI_DB.__lastSeenUpdatePopup = UPDATE_POPUP_VERSION
    if frame then frame:Hide() end
end

local function EnsureFrame()
    if frame then return end

    frame = CreateFrame("Frame", "SakuriaUI_UpdatePopup", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_W, FRAME_H)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 140)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(80)
    frame:EnableMouse(true)
    frame:SetMovable(false)
    frame:Hide()

    -- Background
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        insets = { left = BORDER_SIZE, right = BORDER_SIZE, top = BORDER_SIZE, bottom = BORDER_SIZE },
    })
    frame:SetBackdropColor(BG_R, BG_G, BG_B, 1)

    -- Border
    local border = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -BORDER_SIZE, BORDER_SIZE)
    border:SetPoint("BOTTOMRIGHT", BORDER_SIZE, -BORDER_SIZE)
    border:SetFrameStrata(frame:GetFrameStrata())
    border:SetFrameLevel(frame:GetFrameLevel() - 1)
    border:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    border:SetBackdropColor(0, 0, 0, 1)

    -- Header
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -16)
    title:SetText(UPDATE_TITLE)

    -- Logo
    local logo = frame:CreateTexture(nil, "ARTWORK")
    logo:SetTexture("Interface\\AddOns\\SakuriaUI\\media\\sakuLogo.png")
    logo:SetSize(48, 48)
    logo:SetPoint("TOP", title, "BOTTOM", 0, -6)

    -- Close button
    local close = CreateFrame("Button", nil, frame)
    close:SetSize(34, 34)
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -6, -6)
    close:SetFrameLevel(frame:GetFrameLevel() + 50)

    local closeText = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    closeText:SetPoint("CENTER", close, "CENTER", 0, 0)
    closeText:SetText("×")
    closeText:SetTextColor(1, 1, 1, 1)
    do
        local font, _, flags = closeText:GetFont()
        closeText:SetFont(font, 26, flags or "OUTLINE")
    end

    close:SetScript("OnEnter", function() closeText:SetTextColor(0.9, 0.9, 0.9, 1) end)
    close:SetScript("OnLeave", function() closeText:SetTextColor(1, 1, 1, 1) end)
    close:SetScript("OnClick", MarkSeenAndHide)

    local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -96)
    body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -18, 60)
    body:SetJustifyH("LEFT")
    body:SetJustifyV("TOP")
    body:SetSpacing(4)
    body:SetWordWrap(true)
    body:SetTextColor(1, 1, 1, 1)
    body:SetText(UPDATE_BODY)

    -- OKAY button
    local ok = CreateFlatButton(frame, "OKAY", 140, 28)
    ok:SetPoint("BOTTOM", frame, "BOTTOM", 0, 22)
    ok:SetScript("OnClick", MarkSeenAndHide)
end

function SakuriaUI_OnUpdate.Show(force)
    EnsureDB()
    EnsureFrame()

    if force then
        frame:Show()
        frame:Raise()
        return
    end

    local lastSeen = tonumber(SakuriaUI_DB.__lastSeenUpdatePopup) or 0
    if lastSeen < UPDATE_POPUP_VERSION then
        frame:Show()
        frame:Raise()
    end
end

function SakuriaUI_OnUpdate.MaybeShow()
    SakuriaUI_OnUpdate.Show(false)
end

SLASH_SAKURIAUIUPDATE1 = "/suiupdate"
SlashCmdList["SAKURIAUIUPDATE"] = function()
    SakuriaUI_OnUpdate.Show(true)
end
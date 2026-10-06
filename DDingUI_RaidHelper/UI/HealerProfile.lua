local _, ns = ...

local HealerProfileUI = {}
ns.HealerProfileUI = HealerProfileUI

local FRAME_WIDTH = 620
local FRAME_HEIGHT = 218

local function UnpackColor(color)
    return color[1], color[2], color[3], color[4] or 1
end

local function FormatStat(value)
    return value and BreakUpLargeNumbers and BreakUpLargeNumbers(value) or tostring(value or "-")
end

function HealerProfileUI:GetSummary(profile)
    if not profile then return "현재 전문화의 수집 데이터가 없습니다." end
    local stats = profile.secondaryStats or {}
    local itemLevel = profile.averageItemLevel and string.format(" · 평균 아이템 레벨 %.1f", profile.averageItemLevel) or ""
    return string.format(
        "치명타 %s · 가속 %s · 특화 %s · 유연성 %s%s",
        FormatStat(stats.criticalStrike),
        FormatStat(stats.haste),
        FormatStat(stats.mastery),
        FormatStat(stats.versatility),
        itemLevel
    )
end

function HealerProfileUI:Refresh()
    if not self.frame then return end

    local model = ns.Engine and ns.Engine:GetModel()
    local profile = ns.Engine and ns.Engine:GetHealerProfile()
    local encounterName = ns.Engine and ns.Engine.encounterName or (model and model.name)
    self.frame.encounterText:SetText(encounterName or "선택된 보스 없음")
    self.frame.summaryText:SetText(self:GetSummary(profile))

    if not profile then
        self.frame.sampleText:SetText("현재 전문화에 맞는 상위 기록 표본이 없습니다.")
        self.frame.codeInput.editBox:SetText("")
        self.frame.selectButton:SetDisabledState(true)
        return
    end

    local build = profile.talentBuilds and profile.talentBuilds[1]
    local buildUsage = build and build.usage and string.format(" · 대표 빌드 사용률 %.0f%%", build.usage * 100) or ""
    local limited = (profile.sampleCount or 0) < 10 and " · 표본 제한" or ""
    self.frame.sampleText:SetText(
        string.format(
            "%s %s · 전문화 상위 %d명%s%s",
            profile.className or "",
            (ns.Engine and ns.Engine.playerSpecName) or profile.specName or "",
            profile.sampleCount or 0,
            buildUsage,
            limited
        )
    )

    local code, errorText = ns.TalentExport:Generate(profile, 1)
    self.frame.codeInput.editBox:SetText(code or "")
    self.frame.selectButton:SetDisabledState(code == nil)
    self.frame.helpText:SetText(
        code and "버튼을 누른 뒤 Ctrl+C로 복사해서 게임 특성 가져오기에 붙여 넣으세요."
        or (errorText or "대표 특성 코드를 만들 수 없습니다.")
    )
end

function HealerProfileUI:Show()
    if not self.initialized then self:Initialize() end
    if not self.frame then return false end
    self:Refresh()
    self.frame:Show()
    return true
end

function HealerProfileUI:Toggle()
    if self.frame and self.frame:IsShown() then
        self.frame:Hide()
        return
    end
    self:Show()
end

function HealerProfileUI:Initialize()
    if self.initialized then return end

    local styleLib = ns.GetStyleLib and ns:GetStyleLib()
        or _G.DDingUI_RaidHelperStyleLib -- [REFACTOR] private embedded copy only
    if not styleLib or not styleLib.Colors or not styleLib.CreateButton or not styleLib.CreateInputField then return end
    local colors = styleLib.Colors
    local fontPath = styleLib.GetFont and styleLib:GetFont("primary") or styleLib.Font.path
    local titleSize = styleLib.GetFontSize and styleLib:GetFontSize("title") or styleLib.Font.title
    local normalSize = styleLib.GetFontSize and styleLib:GetFontSize("normal") or styleLib.Font.normal
    local smallSize = styleLib.GetFontSize and styleLib:GetFontSize("small") or styleLib.Font.small
    local flat = styleLib.GetTexture and styleLib:GetTexture("flat") or "Interface\\Buttons\\WHITE8x8"

    local frame = CreateFrame("Frame", "DDingUI_RaidHelperHealerProfile", UIParent, "BackdropTemplate")
    frame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetBackdrop({ bgFile = flat, edgeFile = flat, edgeSize = 1 })
    frame:SetBackdropColor(UnpackColor(colors.bg.main))
    frame:SetBackdropBorderColor(UnpackColor(colors.border.default))
    frame:Hide()

    local accentFrom, accentTo = styleLib.GetAccent("RaidHelper")
    if styleLib.CreateHorizontalGradient then
        local accent = styleLib.CreateHorizontalGradient(frame, accentFrom, accentTo, 2, "OVERLAY")
        accent:SetPoint("TOPLEFT")
        accent:SetPoint("TOPRIGHT")
    end

    frame:SetScript("OnDragStart", function(currentFrame)
        if InCombatLockdown and InCombatLockdown() then return end
        currentFrame:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(currentFrame)
        currentFrame:StopMovingOrSizing()
    end)
    frame:SetScript("OnHide", function()
        if frame.codeInput then frame.codeInput.editBox:ClearFocus() end
    end)

    local title = frame:CreateFontString(nil, "ARTWORK")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetFont(fontPath, titleSize, "OUTLINE")
    title:SetTextColor(UnpackColor(colors.text.highlight))
    title:SetText("상위 전문화 빌드")

    local encounterText = frame:CreateFontString(nil, "ARTWORK")
    encounterText:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    encounterText:SetFont(fontPath, normalSize, "OUTLINE")
    encounterText:SetTextColor(UnpackColor(colors.text.normal))

    local sampleText = frame:CreateFontString(nil, "ARTWORK")
    sampleText:SetPoint("TOPLEFT", encounterText, "BOTTOMLEFT", 0, -5)
    sampleText:SetFont(fontPath, smallSize, "OUTLINE")
    sampleText:SetTextColor(UnpackColor(colors.text.dim))

    local summaryText = frame:CreateFontString(nil, "ARTWORK")
    summaryText:SetPoint("TOPLEFT", sampleText, "BOTTOMLEFT", 0, -10)
    summaryText:SetFont(fontPath, normalSize, "OUTLINE")
    summaryText:SetTextColor(UnpackColor(colors.text.highlight))

    local codeInput = styleLib.CreateInputField(frame, "RaidHelper", "특성 코드", "", {
        width = 570,
        inputWidth = 470,
    })
    codeInput:SetPoint("TOPLEFT", summaryText, "BOTTOMLEFT", 0, -14)

    local selectButton = styleLib.CreateButton(frame, "RaidHelper", "코드 전체 선택", function()
        codeInput.editBox:SetFocus()
        codeInput.editBox:HighlightText()
    end, { width = 128, height = 24 })
    selectButton:SetPoint("TOPLEFT", codeInput, "BOTTOMLEFT", 0, -12)

    local closeButton = styleLib.CreateButton(frame, "RaidHelper", "닫기", function()
        frame:Hide()
    end, { width = 70, height = 24 })
    closeButton:SetPoint("LEFT", selectButton, "RIGHT", 8, 0)

    local helpText = frame:CreateFontString(nil, "ARTWORK")
    helpText:SetPoint("LEFT", closeButton, "RIGHT", 12, 0)
    helpText:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    helpText:SetJustifyH("LEFT")
    helpText:SetFont(fontPath, smallSize, "OUTLINE")
    helpText:SetTextColor(UnpackColor(colors.text.dim))

    frame.encounterText = encounterText
    frame.sampleText = sampleText
    frame.summaryText = summaryText
    frame.codeInput = codeInput
    frame.selectButton = selectButton
    frame.helpText = helpText
    self.frame = frame
    self.initialized = true
end

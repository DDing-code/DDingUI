local DUI = unpack(DDingUI_Profile)

function DUI:IsAddOnEnabled(addon)
    return C_AddOns.IsAddOnLoaded(addon)
end

function DUI:GetPlayerClass()
    local _, classFilename = UnitClass("player")
    return classFilename
end

function DUI:GetPlayerClassName()
    local classFilename = self:GetPlayerClass()
    return self.classNames[classFilename] or classFilename
end

function DUI:GetPlayerSpecID()
    local specIndex = GetSpecialization()
    if not specIndex then return nil end
    local specID = GetSpecializationInfo(specIndex)
    return specID
end

function DUI:GetSpecInfo(specID)
    return self.specInfo[specID]
end

function DUI:GetSpecLabel(specID)
    local info = self.specInfo[specID]
    if not info then return "알 수 없음" end
    local className = self.classNames[info.class] or info.class
    return format("%s %s", info.specName, className)
end

function DUI:LoadProfiles()
    -- [12.0.1] 전투 중 프로필 로드 방지
    if InCombatLockdown() then
        local SL = _G.DDingUI_StyleLib -- [STYLE]
        local prefix = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("Profile", "Profile") or "|cffffffffDDing|r|cffffa300UI|r |cff00ccffProfile|r: " -- [STYLE]
        print(prefix .. "|cffff0000전투 중에는 프로필을 로드할 수 없습니다.|r") -- [STYLE]
        return
    end

    local SE = self:GetModule("Setup")

    for addon in pairs(self.db.global.profiles) do
        if addon == "Blizzard_EditMode" then
            -- 전문화별 레이아웃은 현재 전문화로 적용
            SE:Setup(addon)
        elseif self:IsAddOnEnabled(addon) then
            SE:Setup(addon)
        end
    end

    self.db.char.loaded = true
    ReloadUI()
end

function DUI:Print(msg)
    local SL = _G.DDingUI_StyleLib -- [STYLE]
    local prefix = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("Profile", "Profile") or "|cffffffffDDing|r|cffffa300UI|r |cff00ccffProfile|r: " -- [STYLE]
    print(prefix .. msg) -- [STYLE]
end

------------------------------------------------------
-- [12.0.1] 공통 복사 프레임 헬퍼
------------------------------------------------------
do
    local SL = _G.DDingUI_StyleLib
    local FLAT = (SL and SL.Textures and SL.Textures.flat) or [[Interface\Buttons\WHITE8x8]]
    local FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"
    local bgMain = (SL and SL.Colors and SL.Colors.bg and SL.Colors.bg.main) or {0.10, 0.10, 0.10, 0.95}
    local bgInput = (SL and SL.Colors and SL.Colors.bg and SL.Colors.bg.input) or {0.06, 0.06, 0.06, 0.80}
    local borderDef = (SL and SL.Colors and SL.Colors.border and SL.Colors.border.default) or {0.25, 0.25, 0.25, 0.50}
    local textNormal = (SL and SL.Colors and SL.Colors.text and SL.Colors.text.normal) or {0.85, 0.85, 0.85, 1.0}

    --- 텍스트 복사 프레임 생성/표시
    --- @param cacheKey string  DUI[cacheKey]에 프레임 캐싱
    --- @param frameName string  전역 프레임 이름
    --- @param titleText string  제목 문자열
    --- @param descText string  설명 문자열
    --- @param content string  에딧박스에 넣을 텍스트
    function DUI:ShowCopyFrame(cacheKey, frameName, titleText, descText, content)
        if not self[cacheKey] then
            local f = CreateFrame("Frame", frameName, UIParent, "BackdropTemplate")
            f:SetSize(520, 130)
            f:SetPoint("CENTER", 0, 400)
            f:SetFrameStrata("FULLSCREEN_DIALOG")
            f:SetFrameLevel(999)
            f:EnableMouse(true)
            f:SetMovable(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", f.StartMoving)
            f:SetScript("OnDragStop", f.StopMovingOrSizing)

            f:SetBackdrop({
                bgFile = FLAT, edgeFile = FLAT,
                tile = false, edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            f:SetBackdropColor(unpack(bgMain))
            f:SetBackdropBorderColor(0, 0, 0)

            local title = f:CreateFontString(nil, "OVERLAY")
            title:SetFont(FONT, 15, "OUTLINE")
            title:SetPoint("TOP", 0, -14)
            title:SetText(titleText)

            local desc = f:CreateFontString(nil, "OVERLAY")
            desc:SetFont(FONT, 12, "")
            desc:SetPoint("TOP", title, "BOTTOM", 0, -8)
            desc:SetWidth(480)
            desc:SetTextColor(unpack(textNormal))
            desc:SetText(descText)

            local ebBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
            ebBg:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", -5, -8)
            ebBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 42)
            ebBg:SetBackdrop({
                bgFile = FLAT, edgeFile = FLAT,
                tile = false, edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            ebBg:SetBackdropColor(unpack(bgInput))
            ebBg:SetBackdropBorderColor(unpack(borderDef))

            local eb = CreateFrame("EditBox", frameName .. "EditBox", ebBg)
            eb:SetPoint("LEFT", 6, 0)
            eb:SetPoint("RIGHT", -6, 0)
            eb:SetHeight(20)
            eb:SetAutoFocus(true)
            eb:SetFont(FONT, 11, "")
            eb:SetTextColor(1, 1, 1)
            eb:SetMaxLetters(999999)
            eb:SetScript("OnEscapePressed", function() f:Hide() end)

            f.editBox = eb

            local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            btn:SetSize(100, 24)
            btn:SetPoint("BOTTOM", 0, 10)
            btn:SetText("확인")
            btn:SetScript("OnClick", function() f:Hide() end)

            self[cacheKey] = f
        end

        local frame = self[cacheKey]
        frame:SetFrameStrata("FULLSCREEN_DIALOG")
        frame:SetFrameLevel(999)
        frame:Raise()
        frame.editBox:SetText(content)
        frame.editBox:HighlightText()
        frame.editBox:SetFocus()
        frame:Show()
    end
end

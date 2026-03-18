-- DDingUI_Essential: ActionBars Module -- [ESSENTIAL]
-- SakuriaUI 참조 전면 재설계: 아이콘 클린업, 쿨다운 시각효과, 키바인드 축약, 바 페이드, 메뉴/가방 숨기기
-- 참조: SakuriaUI/modules/clean_icons.lua, fade_actionbars.lua, bindings.lua, hideMenu.lua

local _, ns = ...

local ActionBars = {}

------------------------------------------------------------------------
-- StyleLib 참조 -- [ESSENTIAL]
------------------------------------------------------------------------
local SL      = _G.DDingUI_StyleLib
local C       = SL and SL.Colors
local F       = SL and SL.Font
local FLAT    = SL and SL.Textures and SL.Textures.flat or "Interface\\Buttons\\WHITE8x8"

local function GetC(category, key)
    return (C and C[category] and C[category][key]) or nil
end

local function Unpack(tbl, fr, fg, fb, fa)
    if tbl then return tbl[1], tbl[2], tbl[3], tbl[4] or 1 end
    return fr or 0.1, fg or 0.1, fb or 0.1, fa or 0.9
end

-- 악센트 캐시 -- [ESSENTIAL]
local accentFrom

------------------------------------------------------------------------
-- 바 구성 테이블 -- [ESSENTIAL]
------------------------------------------------------------------------
local BAR_CONFIG = {
    { key = "MainActionBar",       frame = "MainMenuBar",              prefix = "ActionButton",              count = 12 },
    { key = "MultiBarBottomLeft",  frame = "MultiBarBottomLeft",       prefix = "MultiBarBottomLeftButton",  count = 12 },
    { key = "MultiBarBottomRight", frame = "MultiBarBottomRight",      prefix = "MultiBarBottomRightButton", count = 12 },
    { key = "MultiBarRight",       frame = "MultiBarRight",            prefix = "MultiBarRightButton",       count = 12 },
    { key = "MultiBarLeft",        frame = "MultiBarLeft",             prefix = "MultiBarLeftButton",        count = 12 },
    { key = "MultiBar5",           frame = "MultiBar5",                prefix = "MultiBar5Button",           count = 12 },
    { key = "MultiBar6",           frame = "MultiBar6",                prefix = "MultiBar6Button",           count = 12 },
    { key = "MultiBar7",           frame = "MultiBar7",                prefix = "MultiBar7Button",           count = 12 },
}

local STANCE_BAR = { prefix = "StanceButton",   count = 10 }
local PET_BAR    = { prefix = "PetActionButton", count = 10 }

------------------------------------------------------------------------
-- 1. 아이콘 마스크 제거 -- [ESSENTIAL]
-- SakuriaUI clean_icons.lua: StripIconMasks 패턴
------------------------------------------------------------------------
local MASK_CANDIDATES = { "IconMask", "CircleMask", "SlotArtMask", "NormalTextureMask" }

local function StripIconMasks(icon, btn)
    if not icon or not icon.GetNumMaskTextures then return end
    -- 동적 마스크 전부 제거
    for i = icon:GetNumMaskTextures(), 1, -1 do
        local mask = icon:GetMaskTexture(i)
        if mask then
            icon:RemoveMaskTexture(mask)
        end
    end
    -- 명명된 마스크 후보 제거
    if btn then
        for _, name in ipairs(MASK_CANDIDATES) do
            local mask = btn[name]
            if mask then
                icon:RemoveMaskTexture(mask)
                if mask.Hide then mask:Hide() end
            end
        end
    end
end

------------------------------------------------------------------------
-- 2. 쿨다운 시각 효과 (흑백 + 투명도 감소) -- [ESSENTIAL]
-- SakuriaUI clean_icons.lua: C_CurveUtil + C_ActionBar API 패턴
------------------------------------------------------------------------
-- C_CurveUtil 기반 쿨다운 판정 (GCD 자동 필터링, 네이티브 API) -- [ESSENTIAL]
local desatCurve, alphaCurve
if C_CurveUtil and C_CurveUtil.CreateCurve then
    desatCurve = C_CurveUtil.CreateCurve()
    desatCurve:SetType(Enum.LuaCurveType.Step)
    desatCurve:AddPoint(0, 0)
    desatCurve:AddPoint(0.001, 1)

    alphaCurve = C_CurveUtil.CreateCurve()
    alphaCurve:SetType(Enum.LuaCurveType.Step)
    alphaCurve:AddPoint(0, 1)
    alphaCurve:AddPoint(0.001, 0.8)
end

local function ResetCooldownVisual(btn)
    local icon = btn.icon or btn.Icon
    if icon then
        if icon.SetDesaturation then
            icon:SetDesaturation(0)
        elseif icon.SetDesaturated then
            icon:SetDesaturated(false)
        end
    end
    if btn then btn:SetAlpha(1) end
end

local function UpdateCooldownVisual(btn)
    if not btn then return end
    local icon = btn.icon or btn.Icon
    if not icon then return end

    local db = ns.db and ns.db.actionbars or {}
    if db.cooldownDesaturate == false then
        ResetCooldownVisual(btn)
        return
    end

    -- C_CurveUtil + C_ActionBar API 사용 (정확한 GCD 필터링) -- [ESSENTIAL]
    if desatCurve and btn.action then
        local durationObj
        local actionType, actionID = GetActionInfo(btn.action)
        if actionType == "item" and C_Item and C_Item.GetItemCooldown then
            local startTime, durationSecond = C_Item.GetItemCooldown(actionID)
            if durationSecond and durationSecond > 1.5 and C_DurationUtil and C_DurationUtil.CreateDuration then
                durationObj = C_DurationUtil.CreateDuration()
                durationObj:SetTimeFromStart(startTime, durationSecond)
            end
        elseif actionType and C_ActionBar and C_ActionBar.GetActionCooldown then
            local cooldown = C_ActionBar.GetActionCooldown(btn.action)
            if cooldown and not cooldown.isOnGCD and C_ActionBar.GetActionCooldownDuration then
                durationObj = C_ActionBar.GetActionCooldownDuration(btn.action)
            end
        end

        if durationObj then
            local desat = durationObj:EvaluateRemainingDuration(desatCurve)
            local alpha = durationObj:EvaluateRemainingDuration(alphaCurve)
            -- Secret number 방어 (EvaluateRemainingDuration이 secret 반환 가능) -- [ESSENTIAL]
            if issecretvalue and (issecretvalue(desat) or issecretvalue(alpha)) then
                ResetCooldownVisual(btn)
                return
            end
            -- db 설정 반영 -- [ESSENTIAL]
            local dimAlpha = db.cooldownDimAlpha or 0.8
            if alpha < 1 then alpha = dimAlpha end
            if icon.SetDesaturation then
                icon:SetDesaturation(desat)
            elseif icon.SetDesaturated then
                icon:SetDesaturated(desat > 0)
            end
            btn:SetAlpha(alpha)
        else
            ResetCooldownVisual(btn)
        end
        return
    end

    -- 폴백: GetCooldownTimes (C_CurveUtil 미지원 시) -- [ESSENTIAL]
    local cd = btn.cooldown or btn.Cooldown
    if not cd then
        ResetCooldownVisual(btn)
        return
    end

    local start, duration = cd:GetCooldownTimes()
    if not start or not duration then
        ResetCooldownVisual(btn)
        return
    end

    start = start / 1000
    duration = duration / 1000

    if duration <= 1.6 then
        ResetCooldownVisual(btn)
        return
    end

    local remaining = (start + duration) - GetTime()
    if remaining > 0 then
        if icon.SetDesaturation then
            icon:SetDesaturation(1)
        elseif icon.SetDesaturated then
            icon:SetDesaturated(true)
        end
        btn:SetAlpha(db.cooldownDimAlpha or 0.8)
    else
        ResetCooldownVisual(btn)
    end
end

local function HookCooldownVisuals(btn)
    if btn._deCDHooked then return end
    btn._deCDHooked = true

    -- UpdateAction 훅: 액션 변경 시 즉시 갱신 -- [ESSENTIAL]
    if btn.UpdateAction then
        hooksecurefunc(btn, "UpdateAction", function()
            UpdateCooldownVisual(btn)
        end)
    end

    -- OnCooldownDone 훅: 쿨다운 종료 즉시 반응 -- [ESSENTIAL]
    local cd = btn.cooldown or btn.Cooldown
    if cd then
        hooksecurefunc(cd, "SetCooldown", function()
            UpdateCooldownVisual(btn)
        end)
        if cd.HookScript then
            cd:HookScript("OnCooldownDone", function()
                ResetCooldownVisual(btn)
            end)
        end
    end

    UpdateCooldownVisual(btn)
end

------------------------------------------------------------------------
-- 3. 개별 액션 버튼 스킨 (풀 클린업) -- [ESSENTIAL]
------------------------------------------------------------------------
local function SkinActionButton(button)
    if not button or button._deSkinned then return end
    button._deSkinned = true

    local db = ns.db and ns.db.actionbars or {}
    local icon = button.icon or button.Icon

    -- 아이콘 마스크 제거 -- [ESSENTIAL]
    if db.cleanIcons ~= false and icon then
        StripIconMasks(icon, button)
    end

    -- 아이콘 TexCoord 트림 + 픽셀 퍼펙트 (SakuriaUI 패턴) -- [ESSENTIAL]
    if icon then
        if db.iconTrim ~= false then
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        icon:SetDrawLayer("BACKGROUND", 0)
        if icon.SetSnapToPixelGrid then
            icon:SetSnapToPixelGrid(true)
            icon:SetTexelSnappingBias(0)
        end
    end

    -- NormalTexture 숨기기 -- [ESSENTIAL]
    local normal = button:GetNormalTexture()
    if normal then
        normal:SetAlpha(0)
    end

    -- HighlightTexture 숨기기 -- [ESSENTIAL]
    local highlight = button:GetHighlightTexture()
    if highlight then
        highlight:SetAlpha(0)
    end

    -- CheckedTexture 숨기기 -- [ESSENTIAL]
    local checked = button.GetCheckedTexture and button:GetCheckedTexture()
    if checked then
        checked:SetAlpha(0)
    end

    -- Border 텍스처 숨기기 -- [ESSENTIAL]
    if button.Border then
        button.Border:SetAlpha(0)
    end

    -- Flash 숨기기 -- [ESSENTIAL]
    if button.Flash then
        button.Flash:SetAlpha(0)
    end

    -- SlotBackground 교체 (SakuriaUI 패턴: 플랫 다크) -- [ESSENTIAL]
    if button.SlotBackground and db.cleanIcons ~= false then
        button.SlotBackground:SetTexture(FLAT)
        button.SlotBackground:SetVertexColor(0, 0, 0, 1)
        button.SlotBackground:ClearAllPoints()
        button.SlotBackground:SetAllPoints(button)
        button.SlotBackground:SetDrawLayer("BACKGROUND", -1)
        button.SlotBackground:SetAlpha(db.slotBackgroundAlpha or 0.35)
        if button.SlotBackground.SetSnapToPixelGrid then
            button.SlotBackground:SetSnapToPixelGrid(true)
            button.SlotBackground:SetTexelSnappingBias(0)
        end
    end

    -- Pushed 텍스처 오버라이드 (SakuriaUI 패턴) -- [ESSENTIAL]
    local pushed = button:GetPushedTexture()
    if pushed then
        pushed:SetTexture(FLAT)
        pushed:SetVertexColor(0, 0, 0, 0.6)
        pushed:SetBlendMode("BLEND")
        pushed:ClearAllPoints()
        pushed:SetAllPoints(button)
        pushed:SetDrawLayer("ARTWORK", 2)
    end

    -- 쿨다운 스타일 (SakuriaUI 패턴: 정렬 + 레벨 + 스와이프) -- [ESSENTIAL]
    local cd = button.cooldown or button.Cooldown
    if cd then
        cd:ClearAllPoints()
        cd:SetAllPoints(button)
        cd:SetFrameLevel(button:GetFrameLevel() + 4)
        cd:SetSwipeColor(0, 0, 0, 0.75)
        cd:SetDrawEdge(false)
        if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
        if cd.SetSnapToPixelGrid then
            cd:SetSnapToPixelGrid(true)
            cd:SetTexelSnappingBias(0)
        end
    end

    -- ChargeCooldown 동일 처리 (SakuriaUI 패턴) -- [ESSENTIAL]
    local charge = button.chargeCooldown or button.ChargeCooldown
    if charge then
        charge:ClearAllPoints()
        charge:SetAllPoints(button)
        charge:SetFrameLevel(button:GetFrameLevel() + 4)
        if charge.SetSwipeColor then charge:SetSwipeColor(0, 0, 0, 0.75) end
        if charge.SetDrawEdge then charge:SetDrawEdge(false) end
        if charge.SetDrawSwipe then charge:SetDrawSwipe(true) end
    end

    -- 1px 블랙 테두리 (SakuriaUI 패턴: 높은 프레임 레벨) -- [ESSENTIAL]
    local bd = CreateFrame("Frame", nil, button, BackdropTemplateMixin and "BackdropTemplate" or nil)
    bd:SetAllPoints()
    bd:SetFrameLevel(button:GetFrameLevel() + 10)
    bd:SetBackdrop({ edgeFile = FLAT, edgeSize = 1 })
    bd:SetBackdropBorderColor(0, 0, 0, 1)
    if bd.SetSnapToPixelGrid then
        bd:SetSnapToPixelGrid(true)
        bd:SetTexelSnappingBias(0)
    end
    button._deBorder = bd

    -- HotKey 폰트 + 그림자 -- [ESSENTIAL]
    local hotkey = button.HotKey
    if hotkey then
        ns.SetFont(hotkey, db.hotkeyFontSize or 11, "OUTLINE")
        hotkey:SetShadowColor(0, 0, 0, 0.8)
        hotkey:SetShadowOffset(1, -1)
    end

    -- 매크로 이름 폰트 + 그림자 -- [ESSENTIAL]
    local name = button.Name
    if name then
        if db.macroName ~= false then
            ns.SetFont(name, db.macroNameFontSize or 10, "OUTLINE")
            name:SetShadowColor(0, 0, 0, 0.8)
            name:SetShadowOffset(1, -1)
        else
            name:SetAlpha(0)
        end
    end

    -- 스택 카운트 폰트 + 오버레이 레이어 (SakuriaUI 패턴) -- [ESSENTIAL]
    local count = button.Count
    if count then
        ns.SetFont(count, db.countFontSize or 14, "OUTLINE")
        count:SetDrawLayer("OVERLAY", 7)
        count:SetShadowColor(0, 0, 0, 0.8)
        count:SetShadowOffset(1, -1)
    end

    -- 쿨다운 시각 효과 훅 -- [ESSENTIAL]
    if db.cooldownDesaturate ~= false then
        HookCooldownVisuals(button)
    end
end

------------------------------------------------------------------------
-- 4. 스탠스 버튼 스킨 -- [ESSENTIAL]
------------------------------------------------------------------------
local function SkinStanceButton(button)
    if not button or button._deSkinned then return end
    button._deSkinned = true

    local db = ns.db and ns.db.actionbars or {}
    local icon = button.icon or button.Icon

    if db.cleanIcons ~= false and icon then
        StripIconMasks(icon, button)
    end

    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetDrawLayer("BACKGROUND", 0)
        if icon.SetSnapToPixelGrid then
            icon:SetSnapToPixelGrid(true)
            icon:SetTexelSnappingBias(0)
        end
    end

    local normal = button:GetNormalTexture()
    if normal then
        normal:SetAlpha(0)
    end

    local highlight = button:GetHighlightTexture()
    if highlight then
        highlight:SetAlpha(0)
    end

    -- Checked 텍스처: 악센트 반투명 -- [ESSENTIAL]
    local checked = button.GetCheckedTexture and button:GetCheckedTexture()
    if checked then
        local r, g, b
        if accentFrom then
            r, g, b = accentFrom[1], accentFrom[2], accentFrom[3]
        else
            r, g, b = 1.00, 0.82, 0.20 -- [ESSENTIAL-DESIGN] Essential accent 노란색 (SL 미로드 시 fallback)
        end
        checked:SetColorTexture(r, g, b, 0.3)
    end

    if button.Border then button.Border:SetAlpha(0) end
    if button.Flash then button.Flash:SetAlpha(0) end

    -- Pushed (SakuriaUI 패턴) -- [ESSENTIAL]
    local pushed = button:GetPushedTexture()
    if pushed then
        pushed:SetTexture(FLAT)
        pushed:SetVertexColor(0, 0, 0, 0.6)
        pushed:SetBlendMode("BLEND")
        pushed:ClearAllPoints()
        pushed:SetAllPoints(button)
        pushed:SetDrawLayer("ARTWORK", 2)
    end

    -- 쿨다운 스타일 (SakuriaUI 패턴) -- [ESSENTIAL]
    local cd = button.cooldown or button.Cooldown
    if cd then
        cd:ClearAllPoints()
        cd:SetAllPoints(button)
        cd:SetFrameLevel(button:GetFrameLevel() + 4)
        cd:SetSwipeColor(0, 0, 0, 0.75)
        cd:SetDrawEdge(false)
        if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
    end

    -- 1px 블랙 테두리 (SakuriaUI 패턴) -- [ESSENTIAL]
    local bd = CreateFrame("Frame", nil, button, BackdropTemplateMixin and "BackdropTemplate" or nil)
    bd:SetAllPoints()
    bd:SetFrameLevel(button:GetFrameLevel() + 10)
    bd:SetBackdrop({ edgeFile = FLAT, edgeSize = 1 })
    bd:SetBackdropBorderColor(0, 0, 0, 1)
    button._deBorder = bd

    local hotkey = button.HotKey
    if hotkey then
        ns.SetFont(hotkey, db.hotkeyFontSize or 11, "OUTLINE")
        hotkey:SetShadowColor(0, 0, 0, 0.8)
        hotkey:SetShadowOffset(1, -1)
    end

    if db.cooldownDesaturate ~= false then
        HookCooldownVisuals(button)
    end
end

------------------------------------------------------------------------
-- 5. 펫바 버튼 스킨 -- [ESSENTIAL]
------------------------------------------------------------------------
local function SkinPetButton(button)
    if not button or button._deSkinned then return end
    button._deSkinned = true

    local db = ns.db and ns.db.actionbars or {}
    local icon = button.icon or button.Icon

    if db.cleanIcons ~= false and icon then
        StripIconMasks(icon, button)
    end

    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        icon:SetDrawLayer("BACKGROUND", 0)
        if icon.SetSnapToPixelGrid then
            icon:SetSnapToPixelGrid(true)
            icon:SetTexelSnappingBias(0)
        end
    end

    local normal = button:GetNormalTexture()
    if normal then normal:SetAlpha(0) end

    local highlight = button:GetHighlightTexture()
    if highlight then highlight:SetAlpha(0) end

    if button.Border then button.Border:SetAlpha(0) end
    if button.Flash then button.Flash:SetAlpha(0) end

    -- Pushed (SakuriaUI 패턴) -- [ESSENTIAL]
    local pushed = button:GetPushedTexture()
    if pushed then
        pushed:SetTexture(FLAT)
        pushed:SetVertexColor(0, 0, 0, 0.6)
        pushed:SetBlendMode("BLEND")
        pushed:ClearAllPoints()
        pushed:SetAllPoints(button)
        pushed:SetDrawLayer("ARTWORK", 2)
    end

    -- 쿨다운 스타일 (SakuriaUI 패턴) -- [ESSENTIAL]
    local cd = button.cooldown or button.Cooldown
    if cd then
        cd:ClearAllPoints()
        cd:SetAllPoints(button)
        cd:SetFrameLevel(button:GetFrameLevel() + 4)
        cd:SetSwipeColor(0, 0, 0, 0.75)
        cd:SetDrawEdge(false)
        if cd.SetDrawSwipe then cd:SetDrawSwipe(true) end
    end

    -- 1px 블랙 테두리 (SakuriaUI 패턴) -- [ESSENTIAL]
    local bd = CreateFrame("Frame", nil, button, BackdropTemplateMixin and "BackdropTemplate" or nil)
    bd:SetAllPoints()
    bd:SetFrameLevel(button:GetFrameLevel() + 10)
    bd:SetBackdrop({ edgeFile = FLAT, edgeSize = 1 })
    bd:SetBackdropBorderColor(0, 0, 0, 1)
    button._deBorder = bd

    local hotkey = button.HotKey
    if hotkey then
        ns.SetFont(hotkey, db.hotkeyFontSize or 11, "OUTLINE")
        hotkey:SetShadowColor(0, 0, 0, 0.8)
        hotkey:SetShadowOffset(1, -1)
    end

    local name = button.Name
    if name then
        if db.macroName ~= false then
            ns.SetFont(name, 10, "OUTLINE")
            name:SetShadowColor(0, 0, 0, 0.8)
            name:SetShadowOffset(1, -1)
        else
            name:SetAlpha(0)
        end
    end

    if db.cooldownDesaturate ~= false then
        HookCooldownVisuals(button)
    end
end

------------------------------------------------------------------------
-- 6. 키바인드 축약 -- [ESSENTIAL]
-- SakuriaUI bindings.lua: ShortenKeybind + ShortenMacro + CleanText 패턴
------------------------------------------------------------------------
-- WoW 이스케이프 시퀀스 정리 (|A, |T, |c, |r) -- [ESSENTIAL]
local function CleanText(s)
    if not s or s == "" then return s end
    return s
        :gsub("|A.-|a", "")
        :gsub("|T.-|t", "")
        :gsub("|c%x%x%x%x%x%x%x%x", "")
        :gsub("|r", "")
end

local function ShortenKeybind(text)
    if not text or text == "" then return text end
    text = text
        :gsub("SHIFT%-", "S")
        :gsub("CTRL%-", "C")
        :gsub("ALT%-", "A")
        :gsub("NUMPAD", "N")
        :gsub("Mouse Wheel Up", "MU")
        :gsub("Mouse Wheel Down", "MD")
        :gsub("MOUSEWHEELUP", "MU")
        :gsub("MOUSEWHEELDOWN", "MD")
        :gsub("Mouse Button (%d+)", "M%1")
        :gsub("MOUSEBUTTON(%d+)", "M%1")
        :gsub("BUTTON(%d+)", "M%1")
        :gsub("Middle Mouse", "M3")
        :gsub("Right Mouse", "M2")
        :gsub("Left Mouse", "M1")
        :gsub("PLUS", "+")
        :gsub("MINUS", "-")
        :gsub("MULTIPLY", "*")
        :gsub("DIVIDE", "/")
        :gsub("[%-]", "")
    return text
end

-- UTF8 안전 문자열 자르기 -- [ESSENTIAL]
local function UTF8Sub(str, maxChars)
    if not str then return "" end
    local len = 0
    local bytePos = 1
    local strLen = #str
    while bytePos <= strLen and len < maxChars do
        local byte = str:byte(bytePos)
        local charBytes
        if byte < 128 then
            charBytes = 1
        elseif byte < 224 then
            charBytes = 2
        elseif byte < 240 then
            charBytes = 3
        else
            charBytes = 4
        end
        if bytePos + charBytes - 1 > strLen then break end
        bytePos = bytePos + charBytes
        len = len + 1
    end
    return str:sub(1, bytePos - 1)
end

local function ShortenMacro(text, maxChars)
    if not text or text == "" then return text end
    text = CleanText(text)
    if not text or text == "" then return "" end
    return UTF8Sub(text, maxChars or 5)
end

-- 핫키 색상 강제 (Blizzard가 덮어쓰기 방지) -- [ESSENTIAL]
local function EnforceHotkeyColor(fs)
    if not fs or fs._deColorEnforced then return end
    fs._deColorEnforced = true

    local function Apply(self)
        if self._deColorLock then return end
        self._deColorLock = true
        self:SetTextColor(1, 1, 1)
        self._deColorLock = nil
    end

    hooksecurefunc(fs, "SetTextColor", function(self, r, g, b)
        if self._deColorLock then return end
        if r ~= 1 or g ~= 1 or b ~= 1 then
            Apply(self)
        end
    end)

    if fs.SetVertexColor then
        hooksecurefunc(fs, "SetVertexColor", function(self, r, g, b)
            if self._deColorLock then return end
            if r ~= 1 or g ~= 1 or b ~= 1 then
                Apply(self)
            end
        end)
    end

    Apply(fs)
end

-- 매크로 이름 SetText + SetFormattedText 훅 -- [ESSENTIAL]
local function EnforceMacroShortening(fs, maxChars)
    if not fs or fs._deMacroEnforced then return end
    fs._deMacroEnforced = true

    hooksecurefunc(fs, "SetText", function(self, newText)
        if self._deMacroLock then return end
        local truncated = ShortenMacro(newText or "", maxChars)
        if truncated ~= (newText or "") then
            self._deMacroLock = true
            self:SetText(truncated)
            self._deMacroLock = nil
        end
        self:SetMaxLines(1)
        self:SetWordWrap(false)
    end)

    -- SetFormattedText 훅 (매크로 이름 완전 제어) -- [ESSENTIAL]
    if fs.SetFormattedText then
        hooksecurefunc(fs, "SetFormattedText", function(self, fmt, ...)
            if self._deMacroLock then return end
            local candidate = string.format(fmt or "", ...)
            local truncated = ShortenMacro(candidate or "", maxChars)
            if truncated ~= candidate then
                self._deMacroLock = true
                self:SetText(truncated)
                self._deMacroLock = nil
            end
            self:SetMaxLines(1)
            self:SetWordWrap(false)
        end)
    end
end

-- 단일 버튼에 키바인드/매크로 축약 적용 -- [ESSENTIAL]
local function StyleAndShortenButton(btn)
    if not btn then return end
    local db = ns.db and ns.db.actionbars or {}

    -- 핫키 축약 -- [ESSENTIAL]
    local hotkey = btn.HotKey
    if hotkey and hotkey.GetText and hotkey.SetText then
        local text = hotkey:GetText()
        if text and text ~= "" then
            local shortened = ShortenKeybind(text)
            if shortened ~= text then
                hotkey:SetText(shortened)
            end
        end
        -- SetText 훅으로 지속적 축약 보장 -- [ESSENTIAL]
        if not hotkey._deShortHooked then
            hotkey._deShortHooked = true
            hooksecurefunc(hotkey, "SetText", function(self, newText)
                if not self._deShortening then
                    self._deShortening = true
                    local short = ShortenKeybind(newText)
                    if short ~= newText then
                        self:SetText(short)
                    end
                    self._deShortening = nil
                end
            end)
        end
        hotkey:SetMaxLines(1)
        hotkey:SetWordWrap(false)
        EnforceHotkeyColor(hotkey)
    end

    -- 매크로 이름 축약 -- [ESSENTIAL]
    local nameFS = btn.Name
    if nameFS and db.macroName ~= false and nameFS.GetText then
        local macroMax = db.macroNameMaxChars or 5
        EnforceMacroShortening(nameFS, macroMax)
        -- 즉시 적용
        local curText = nameFS:GetText()
        if curText and curText ~= "" then
            local short = ShortenMacro(curText, macroMax)
            if short ~= curText then
                nameFS:SetText(short)
            end
        end
    end
end

local function SweepAllButtons()
    local db = ns.db and ns.db.actionbars or {}
    if not db.shortenKeybinds then return end

    for _, barInfo in ipairs(BAR_CONFIG) do
        for i = 1, barInfo.count do
            StyleAndShortenButton(_G[barInfo.prefix .. i])
        end
    end
    for _, barInfo in ipairs({ STANCE_BAR, PET_BAR }) do
        for i = 1, barInfo.count do
            StyleAndShortenButton(_G[barInfo.prefix .. i])
        end
    end
end

local function ApplyKeybindShortening()
    local db = ns.db and ns.db.actionbars or {}
    if not db.shortenKeybinds then return end

    -- 즉시 전체 적용 -- [ESSENTIAL]
    C_Timer.After(0.2, SweepAllButtons)

    -- ActionBarActionButtonMixin.UpdateAction 훅 (Retail) -- [ESSENTIAL]
    if ActionBarActionButtonMixin and not ns._deBindRetailHooked then
        ns._deBindRetailHooked = true
        hooksecurefunc(ActionBarActionButtonMixin, "UpdateAction", function(self)
            StyleAndShortenButton(self)
        end)
    end

    -- 이벤트 기반 리프레시 (바인딩/매크로/액션 변경 시) -- [ESSENTIAL]
    if not ns._deBindEventFrame then
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
        f:RegisterEvent("UPDATE_BINDINGS")
        f:RegisterEvent("CVAR_UPDATE")
        f:RegisterEvent("UPDATE_MACROS")
        f:RegisterEvent("SPELLS_CHANGED")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")
        f:SetScript("OnEvent", function(_, event, arg1)
            if event == "CVAR_UPDATE" and arg1 ~= "SHOW_MACRO_NAMES" then return end
            if InCombatLockdown() then
                ns._deBindNeedsRefresh = true
                return
            end
            SweepAllButtons()
        end)
        ns._deBindEventFrame = f
    end
end

------------------------------------------------------------------------
-- 7. 바 페이드 시스템 -- [ESSENTIAL]
-- SakuriaUI fade_actionbars.lua: UIFrameFadeIn/Out + InCombatLockdown 패턴
------------------------------------------------------------------------
local fadeStates = {} -- key → { active = true, mouseOver = false }

local function FadeFrame(frame, show, db)
    if not frame then return end
    if InCombatLockdown() then return end -- 전투 중 EnableMouse 변경 불가

    local fadeDuration = db and db.fadeDuration or 0.3
    local fadeAlpha = db and db.fadeAlpha or 0

    if show then
        if SL then
            SL.FadeIn(frame, fadeDuration, frame:GetAlpha(), 1)
        else
            frame:SetAlpha(1)
        end
        frame:EnableMouse(true)
    else
        if SL then
            SL.FadeOut(frame, fadeDuration, frame:GetAlpha(), fadeAlpha, false)
        else
            frame:SetAlpha(fadeAlpha)
        end
        if fadeAlpha == 0 then
            frame:EnableMouse(false)
        end
    end
end

local function SetupBarFade(barKey, barFrame, prefix, count)
    local db = ns.db and ns.db.actionbars or {}
    if not db.fadeBars or not db.fadeBars[barKey] then return end
    if not barFrame then return end

    fadeStates[barKey] = { active = true, mouseOver = false }

    local function OnEnter()
        fadeStates[barKey].mouseOver = true
        FadeFrame(barFrame, true, db)
    end

    local function OnLeave()
        fadeStates[barKey].mouseOver = false
        -- 약간의 딜레이로 깜빡임 방지
        C_Timer.After(0.1, function()
            if fadeStates[barKey] and not fadeStates[barKey].mouseOver then
                FadeFrame(barFrame, false, db)
            end
        end)
    end

    -- 바 프레임 자체에 훅 -- [ESSENTIAL]
    barFrame:HookScript("OnEnter", OnEnter)
    barFrame:HookScript("OnLeave", OnLeave)

    -- 각 버튼에도 훅 -- [ESSENTIAL]
    for i = 1, count do
        local btn = _G[prefix .. i]
        if btn then
            btn:HookScript("OnEnter", OnEnter)
            btn:HookScript("OnLeave", OnLeave)
        end
    end

    -- 초기 상태: 페이드 아웃 -- [ESSENTIAL]
    FadeFrame(barFrame, false, db)
end

local function SetupStanceBarFade()
    local db = ns.db and ns.db.actionbars or {}
    if not db.fadeStanceBar then return end

    local stanceBar = _G["StanceBar"] or _G["StanceBarFrame"]
    if not stanceBar then return end

    fadeStates["StanceBar"] = { active = true, mouseOver = false }

    local function OnEnter()
        fadeStates["StanceBar"].mouseOver = true
        FadeFrame(stanceBar, true, db)
    end

    local function OnLeave()
        fadeStates["StanceBar"].mouseOver = false
        C_Timer.After(0.1, function()
            if fadeStates["StanceBar"] and not fadeStates["StanceBar"].mouseOver then
                FadeFrame(stanceBar, false, db)
            end
        end)
    end

    stanceBar:HookScript("OnEnter", OnEnter)
    stanceBar:HookScript("OnLeave", OnLeave)

    for i = 1, STANCE_BAR.count do
        local btn = _G[STANCE_BAR.prefix .. i]
        if btn then
            btn:HookScript("OnEnter", OnEnter)
            btn:HookScript("OnLeave", OnLeave)
        end
    end

    FadeFrame(stanceBar, false, db)
end

local function SetupPetBarFade()
    local db = ns.db and ns.db.actionbars or {}
    if not db.fadePetBar then return end

    local petBar = _G["PetActionBar"] or _G["PetActionBarFrame"]
    if not petBar then
        -- WoW 12.x: PetActionBarButtonContainer 사용 가능
        petBar = _G["PetActionBarButtonContainer"]
    end
    if not petBar then return end

    fadeStates["PetBar"] = { active = true, mouseOver = false }

    local function OnEnter()
        fadeStates["PetBar"].mouseOver = true
        FadeFrame(petBar, true, db)
    end

    local function OnLeave()
        fadeStates["PetBar"].mouseOver = false
        C_Timer.After(0.1, function()
            if fadeStates["PetBar"] and not fadeStates["PetBar"].mouseOver then
                FadeFrame(petBar, false, db)
            end
        end)
    end

    petBar:HookScript("OnEnter", OnEnter)
    petBar:HookScript("OnLeave", OnLeave)

    for i = 1, PET_BAR.count do
        local btn = _G[PET_BAR.prefix .. i]
        if btn then
            btn:HookScript("OnEnter", OnEnter)
            btn:HookScript("OnLeave", OnLeave)
        end
    end

    FadeFrame(petBar, false, db)
end

-- 전투 종료 시 페이드 상태 복원 -- [ESSENTIAL]
local fadeEventFrame = CreateFrame("Frame")
fadeEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
fadeEventFrame:SetScript("OnEvent", function()
    local db = ns.db and ns.db.actionbars or {}
    if not db.fadeBars then return end

    for _, barInfo in ipairs(BAR_CONFIG) do
        local state = fadeStates[barInfo.key]
        if state and state.active and not state.mouseOver then
            local barFrame = _G[barInfo.frame]
            if barFrame then
                FadeFrame(barFrame, false, db)
            end
        end
    end

    if fadeStates["StanceBar"] and fadeStates["StanceBar"].active and not fadeStates["StanceBar"].mouseOver then
        local stanceBar = _G["StanceBar"] or _G["StanceBarFrame"]
        if stanceBar then FadeFrame(stanceBar, false, db) end
    end

    if fadeStates["PetBar"] and fadeStates["PetBar"].active and not fadeStates["PetBar"].mouseOver then
        local petBar = _G["PetActionBar"] or _G["PetActionBarFrame"] or _G["PetActionBarButtonContainer"]
        if petBar then FadeFrame(petBar, false, db) end
    end
end)

------------------------------------------------------------------------
-- 8. 마이크로 메뉴 / 가방바 숨기기 -- [ESSENTIAL]
-- SakuriaUI hideMenu.lua: 프록시 + 자식 프레임 제어 + 동적 레벨 패턴
------------------------------------------------------------------------
local MENU_FADE_IN  = 0.15
local MENU_FADE_OUT = 0.30
local MENU_LEAVE_DELAY = 0.20

-- 자식 프레임 포함 EnableMouse 제어 -- [ESSENTIAL]
local function SetInteractive(frame, on)
    if not frame then return end
    frame:EnableMouse(on)
    for _, child in ipairs({ frame:GetChildren() }) do
        if child and child.EnableMouse then
            child:EnableMouse(on)
        end
    end
end

-- 프록시 프레임 레벨 동적 조절 -- [ESSENTIAL]
local function SetProxyLevel(proxy, target, above)
    if not proxy or not target then return end
    if above then
        proxy:SetFrameLevel(target:GetFrameLevel() + 50)
    else
        local lvl = target:GetFrameLevel() - 1
        if lvl < 0 then lvl = 0 end
        proxy:SetFrameLevel(lvl)
    end
end

local function PositionProxy(proxy, target)
    if not proxy or not target then return end
    proxy:ClearAllPoints()
    proxy:SetAllPoints(target)
    proxy:SetFrameStrata(target:GetFrameStrata())
end

local function ShowUIFrame(frame)
    if not frame then return end
    if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(frame) end
    frame:Show()
    if SL then
        SL.FadeIn(frame, MENU_FADE_IN, frame:GetAlpha(), 1)
    else
        frame:SetAlpha(1)
    end
    SetInteractive(frame, true)
end

local function HideUIFrame(frame)
    if not frame then return end
    if UIFrameFadeRemoveFrame then UIFrameFadeRemoveFrame(frame) end
    if SL then
        SL.FadeOut(frame, MENU_FADE_OUT, frame:GetAlpha(), 0, false)
    else
        frame:SetAlpha(0)
    end
    SetInteractive(frame, false)
end

local function HideMenuBar()
    local menuBar = _G["MicroMenuContainer"]
    if not menuBar then return end

    local menuEnabled = true

    local proxy = CreateFrame("Frame", nil, UIParent)
    proxy:SetAlpha(0)
    proxy:EnableMouse(true)
    PositionProxy(proxy, menuBar)

    local function ShouldHide()
        if not menuEnabled then return false end
        if proxy:IsMouseOver() then return false end
        if menuBar:IsMouseOver() then return false end
        return true
    end

    proxy:SetScript("OnEnter", function()
        if menuEnabled then
            ShowUIFrame(menuBar)
            SetProxyLevel(proxy, menuBar, false)
        end
    end)

    proxy:SetScript("OnLeave", function()
        C_Timer.After(MENU_LEAVE_DELAY, function()
            if menuEnabled and ShouldHide() then
                HideUIFrame(menuBar)
                SetProxyLevel(proxy, menuBar, true)
            end
        end)
    end)

    -- 자식 프레임 Leave도 처리 -- [ESSENTIAL]
    if not menuBar._deFaderHooked then
        menuBar._deFaderHooked = true
        local function DelayedHide()
            C_Timer.After(MENU_LEAVE_DELAY, function()
                if menuEnabled and ShouldHide() then
                    HideUIFrame(menuBar)
                    SetProxyLevel(proxy, menuBar, true)
                end
            end)
        end
        menuBar:HookScript("OnLeave", DelayedHide)
        for _, child in ipairs({ menuBar:GetChildren() }) do
            if child and child.HookScript then
                child:HookScript("OnLeave", DelayedHide)
            end
        end
    end

    -- 초기 숨김 -- [ESSENTIAL]
    HideUIFrame(menuBar)
    SetProxyLevel(proxy, menuBar, true)

    -- UI 스케일 변경 시 프록시 위치 재조정 -- [ESSENTIAL]
    if not ns._deMenuProxyUpdater then
        local u = CreateFrame("Frame")
        u:RegisterEvent("UI_SCALE_CHANGED")
        u:RegisterEvent("DISPLAY_SIZE_CHANGED")
        u:SetScript("OnEvent", function()
            if menuEnabled and proxy then
                PositionProxy(proxy, menuBar)
            end
        end)
        ns._deMenuProxyUpdater = u
    end
end

local function HideBagBar()
    local bagBar = _G["BagsBar"] or _G["MicroButtonAndBagsBar"]
    if not bagBar then return end

    local bagEnabled = true

    local proxy = CreateFrame("Frame", nil, UIParent)
    proxy:SetAlpha(0)
    proxy:EnableMouse(true)
    PositionProxy(proxy, bagBar)

    local function ShouldHide()
        if not bagEnabled then return false end
        if proxy:IsMouseOver() then return false end
        if bagBar:IsMouseOver() then return false end
        return true
    end

    proxy:SetScript("OnEnter", function()
        if bagEnabled then
            ShowUIFrame(bagBar)
            SetProxyLevel(proxy, bagBar, false)
        end
    end)

    proxy:SetScript("OnLeave", function()
        C_Timer.After(MENU_LEAVE_DELAY, function()
            if bagEnabled and ShouldHide() then
                HideUIFrame(bagBar)
                SetProxyLevel(proxy, bagBar, true)
            end
        end)
    end)

    -- 자식 프레임 Leave도 처리 -- [ESSENTIAL]
    if not bagBar._deFaderHooked then
        bagBar._deFaderHooked = true
        local function DelayedHide()
            C_Timer.After(MENU_LEAVE_DELAY, function()
                if bagEnabled and ShouldHide() then
                    HideUIFrame(bagBar)
                    SetProxyLevel(proxy, bagBar, true)
                end
            end)
        end
        bagBar:HookScript("OnLeave", DelayedHide)
        for _, child in ipairs({ bagBar:GetChildren() }) do
            if child and child.HookScript then
                child:HookScript("OnLeave", DelayedHide)
            end
        end
    end

    -- 초기 숨김 -- [ESSENTIAL]
    HideUIFrame(bagBar)
    SetProxyLevel(proxy, bagBar, true)
end

------------------------------------------------------------------------
-- 9. Blizzard 장식 요소 숨기기 -- [ESSENTIAL]
------------------------------------------------------------------------
local function HideBlizzardArt()
    if MainMenuBarArtFrame then
        ns.StripTextures(MainMenuBarArtFrame)
    end
    if MainMenuBarArtFrameBackground then
        MainMenuBarArtFrameBackground:Hide()
    end

    if StatusTrackingBarManager then
        ns.StripTextures(StatusTrackingBarManager)
    end

    local artButtons = {
        ActionBarDownButton,
        ActionBarUpButton,
    }
    for _, btn in ipairs(artButtons) do
        if btn and btn.Hide then
            btn:Hide()
        end
    end
end

------------------------------------------------------------------------
-- 10. 동적 스킨 훅 -- [ESSENTIAL]
------------------------------------------------------------------------
local function HookDynamicSkinning()
    -- ActionBarButtonEventsFrame 동적 갱신 -- [ESSENTIAL]
    if ActionBarButtonEventsFrame then
        hooksecurefunc(ActionBarButtonEventsFrame, "RegisterFrame", function(_, button)
            if button then
                button._deSkinned = nil
                SkinActionButton(button)
            end
        end)
    end

    -- NormalTexture 재설정 방어 훅 -- [ESSENTIAL]
    for _, barInfo in ipairs(BAR_CONFIG) do
        for i = 1, barInfo.count do
            local button = _G[barInfo.prefix .. i]
            if button and not button._deNormalHooked then
                button._deNormalHooked = true
                hooksecurefunc(button, "SetNormalTexture", function(btn)
                    local n = btn:GetNormalTexture()
                    if n then
                        n:SetAlpha(0)
                    end
                end)
            end
        end
    end

    -- 쿨다운 이벤트 감시 (아이콘 흑백/투명도 갱신) -- [ESSENTIAL]
    -- [PERF] debounce: 동일 프레임 내 중복 이벤트 병합
    local db = ns.db and ns.db.actionbars or {}
    if db.cooldownDesaturate ~= false then
        local cdFrame = CreateFrame("Frame")
        local cdPending = false
        cdFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
        cdFrame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
        cdFrame:SetScript("OnEvent", function()
            if cdPending then return end
            cdPending = true
            C_Timer.After(0, function()
                cdPending = false
                for _, barInfo in ipairs(BAR_CONFIG) do
                    for i = 1, barInfo.count do
                        local btn = _G[barInfo.prefix .. i]
                        if btn then
                            UpdateCooldownVisual(btn)
                        end
                    end
                end
            end)
        end)
    end

    -- 전투 종료 시 바인드 리프레시 (전투 중 지연된 갱신 처리) -- [ESSENTIAL]
    if not ns._deRegenBindHooked then
        ns._deRegenBindHooked = true
        local regenFrame = CreateFrame("Frame")
        regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        regenFrame:SetScript("OnEvent", function()
            if ns._deBindNeedsRefresh then
                ns._deBindNeedsRefresh = nil
                SweepAllButtons()
            end
        end)
    end
end

------------------------------------------------------------------------
-- Enable -- [ESSENTIAL]
------------------------------------------------------------------------
function ActionBars:Enable()
    -- StyleLib 재확인 -- [ESSENTIAL]
    if not SL then
        SL = _G.DDingUI_StyleLib
        C = SL and SL.Colors
        F = SL and SL.Font
        FLAT = SL and SL.Textures and SL.Textures.flat or FLAT
    end

    -- 악센트 캐시 -- [ESSENTIAL]
    if SL and SL.GetAccent then
        local from = SL.GetAccent("Essential")
        accentFrom = from
    end

    local db = ns.db and ns.db.actionbars or {}

    -- 1. 메인 액션바 버튼 스킨 -- [ESSENTIAL]
    for _, barInfo in ipairs(BAR_CONFIG) do
        for i = 1, barInfo.count do
            SkinActionButton(_G[barInfo.prefix .. i])
        end
    end

    -- 2. 스탠스바 -- [ESSENTIAL]
    for i = 1, STANCE_BAR.count do
        SkinStanceButton(_G[STANCE_BAR.prefix .. i])
    end

    -- 3. 펫바 -- [ESSENTIAL]
    for i = 1, PET_BAR.count do
        SkinPetButton(_G[PET_BAR.prefix .. i])
    end

    -- 4. Blizzard 장식 숨기기 -- [ESSENTIAL]
    if db.hideBlizzardArt ~= false then
        HideBlizzardArt()
    end

    -- 5. 키바인드 축약 -- [ESSENTIAL]
    ApplyKeybindShortening()

    -- 6. 바 페이드 -- [ESSENTIAL]
    for _, barInfo in ipairs(BAR_CONFIG) do
        local barFrame = _G[barInfo.frame]
        if barFrame then
            SetupBarFade(barInfo.key, barFrame, barInfo.prefix, barInfo.count)
        end
    end
    SetupStanceBarFade()
    SetupPetBarFade()

    -- 7. 메뉴/가방바 숨기기 -- [ESSENTIAL]
    if db.hideMenuBar then
        HideMenuBar()
    end
    if db.hideBagBar then
        HideBagBar()
    end

    -- 8. 동적 스킨 훅 -- [ESSENTIAL]
    HookDynamicSkinning()

    -- 9. 사거리 체크 (빨간 틴트) -- [ESSENTIAL]
    if db.rangeCheck ~= false then
        local rangeFrame = CreateFrame("Frame")
        rangeFrame:RegisterEvent("ACTIONBAR_UPDATE_USABLE")
        rangeFrame:SetScript("OnEvent", function()
            for _, barInfo in ipairs(BAR_CONFIG) do
                for i = 1, barInfo.count do
                    local btn = _G[barInfo.prefix..i]
                    if btn then
                        local action = btn.action
                        if action and HasAction(action) then
                            local icon = btn.icon or btn.Icon
                            if icon then
                                if IsActionInRange(action) == false then
                                    icon:SetVertexColor(0.8, 0.1, 0.1)
                                else
                                    icon:SetVertexColor(1, 1, 1)
                                end
                            end
                        end
                    end
                end
            end
        end)
    end
end

function ActionBars:Disable()
    -- ReloadUI 필요 -- [ESSENTIAL]
end

ns:RegisterModule("actionbars", ActionBars)

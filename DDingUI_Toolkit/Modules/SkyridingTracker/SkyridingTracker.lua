--[[
    DDingToolKit - SkyridingTracker Module
    활공 비행 기력/재기의 바람/소용돌이 쇄도를 원형 HUD로 표시
    -- [12.0.1]
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local L = ns.L

local SkyridingTracker = {}
ns.SkyridingTracker = SkyridingTracker

local MEDIA = "Interface\\AddOns\\DDingUI_Toolkit\\Media\\SkyridingTracker\\"

------------------------------------------------------
-- API
------------------------------------------------------
local function GetVigorInfo()
    local d = C_Spell.GetSpellCharges(372608)
    if not d then return false, 0, 6, 0, 0 end
    return d.currentCharges < d.maxCharges, d.currentCharges, d.maxCharges, d.cooldownStartTime, d.cooldownDuration
end

local function GetSecondWindInfo()
    local d = C_Spell.GetSpellCharges(425782)
    if not d then return false, 0, 3, 0, 0 end
    return d.currentCharges < d.maxCharges, d.currentCharges, d.maxCharges, d.cooldownStartTime, d.cooldownDuration
end

local function GetWhirlingSurgeInfo()
    local d = C_Spell.GetSpellCooldown(361584)
    if not d then return 0, 0, false end
    -- GCD (1.5초 이하) 무시
    if d.duration and d.duration > 0 and d.duration <= 1.5 then
        return 0, 0, false
    end
    local onCD = d.startTime and d.startTime > 0 and d.duration and d.duration > 0
    return d.startTime or 0, d.duration or 0, onCD
end

-- 비행 감지 (CDM hideWhileFlying 동일 조건)
local function IsActivelyFlying()
    if not GetBonusBarIndex or GetBonusBarIndex() ~= 11 then
        return false
    end
    return IsFlying()
end

------------------------------------------------------
-- Lifecycle
------------------------------------------------------
function SkyridingTracker:OnInitialize()
    self.db = ns.db.profile.SkyridingTracker or {}
    self._wasFlying = false
    self._currentAlpha = 0
    self._targetAlpha = 0
    -- 플래시 추적
    self._lastVigorCh = -1
    self._lastWindCh = -1
    self._vigorFlash = {}
    self._windFlash = {}
    self._lastSurgeOnCD = false
    self._surgeFlash = nil
end

function SkyridingTracker:OnEnable()
    self:CreateHUD()
    self:ApplySettings()
end

function SkyridingTracker:OnDisable()
    if self.frame then self.frame:SetAlpha(0) end
end

------------------------------------------------------
-- DB color helper
------------------------------------------------------
local function GetColor(db, key, fallback)
    local c = db[key]
    if c and type(c) == "table" then
        return c[1] or c.r or fallback[1],
               c[2] or c.g or fallback[2],
               c[3] or c.b or fallback[3]
    end
    return fallback[1], fallback[2], fallback[3]
end

------------------------------------------------------
-- Settings
------------------------------------------------------
function SkyridingTracker:ApplySettings()
    if not self.frame then return end
    self.db = ns.db.profile.SkyridingTracker or {}
    self.frame:SetScale(self.db.scale or 1.0)
    self:ApplyPosition()
    self:UpdateSurgeTexture()
    self:ApplyColors()
end

function SkyridingTracker:ApplyPosition()
    if not self.frame then return end
    local x = (self.db and self.db.posX) or 0
    local y = (self.db and self.db.posY) or 0
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", x, y)
end

function SkyridingTracker:UpdateSurgeTexture()
    if not self.surgeBg then return end
    local pos = self.db.surgePosition or "bottom"
    local file = MEDIA .. "surge_" .. pos .. ".tga"
    self.surgeBg:SetTexture(file)
    self.surgeFg:SetTexture(file)
end

------------------------------------------------------
-- 색상 적용
------------------------------------------------------
function SkyridingTracker:ApplyColors()
    if not self.frame then return end
    local db = ns.db.profile.SkyridingTracker or {}

    self._cVigor    = { GetColor(db, "vigorColor",    { 0.20, 0.80, 1.00 }) }
    self._cVigorDim = { GetColor(db, "vigorDimColor", { 0.06, 0.15, 0.22 }) }
    self._cWind     = { GetColor(db, "windColor",     { 0.40, 1.00, 0.55 }) }
    self._cWindDim  = { GetColor(db, "windDimColor",  { 0.08, 0.20, 0.12 }) }
    self._cSurge    = { GetColor(db, "surgeColor",    { 1.00, 0.55, 0.10 }) }
    self._cSurgeDim = { GetColor(db, "surgeDimColor", { 0.20, 0.12, 0.03 }) }

    if self.vigorBg then
        for i = 1, 6 do
            self.vigorBg[i]:SetVertexColor(self._cVigorDim[1], self._cVigorDim[2], self._cVigorDim[3], 1)
        end
    end
    if self.windBg then
        for i = 1, 3 do
            self.windBg[i]:SetVertexColor(self._cWindDim[1], self._cWindDim[2], self._cWindDim[3], 1)
        end
    end
    if self.surgeBg then
        self.surgeBg:SetVertexColor(self._cSurgeDim[1], self._cSurgeDim[2], self._cSurgeDim[3], 1)
    end
end

------------------------------------------------------
-- HUD 생성
------------------------------------------------------
function SkyridingTracker:CreateHUD()
    if self.frame then return end

    local f = CreateFrame("Frame", "DDingUI_SkyridingTracker", UIParent)
    f:SetSize(160, 160)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(100)
    f:SetAlpha(0)
    f:SetClampedToScreen(true)
    f:Show()

    local x = self.db.posX or 0
    local y = self.db.posY or 0
    f:SetPoint("CENTER", UIParent, "CENTER", x, y)

    self.frame = f

    local function MakeTex(file, layer, alpha)
        local t = f:CreateTexture(nil, layer)
        t:SetAllPoints()
        t:SetTexture(MEDIA .. file)
        t:SetAlpha(alpha or 1)
        return t
    end

    -- Vigor
    self.vigorBg, self.vigorFg = {}, {}
    for i = 1, 6 do
        local file = "vigor_" .. i .. ".tga"
        self.vigorBg[i] = MakeTex(file, "BACKGROUND", 0.5)
        self.vigorFg[i] = MakeTex(file, "ARTWORK", 0)
    end

    -- Wind
    self.windBg, self.windFg = {}, {}
    for i = 1, 3 do
        local file = "wind_" .. i .. ".tga"
        self.windBg[i] = MakeTex(file, "BACKGROUND", 0.5)
        self.windFg[i] = MakeTex(file, "ARTWORK", 0)
    end

    -- Surge
    local surgeFile = "surge_" .. (self.db.surgePosition or "bottom") .. ".tga"
    self.surgeBg = MakeTex(surgeFile, "BACKGROUND", 0.5)
    self.surgeFg = MakeTex(surgeFile, "ARTWORK", 1)

    -- OnUpdate: 비행 감지 + 페이드 + 데이터 갱신
    self._currentAlpha = 0
    self._targetAlpha = 0
    local abs = math.abs

    f:SetScript("OnUpdate", function(_, elapsed)
        if not ns:GetDBValue("profile.modules.SkyridingTracker") then
            f:SetAlpha(0)
            return
        end

        local flying = IsActivelyFlying()

        local isFull = false
        if self.db.hideWhenFull then
            local _, ch, mx = GetVigorInfo()
            local _, wCh, wM = GetSecondWindInfo()
            local _, _, onCD = GetWhirlingSurgeInfo()
            isFull = (ch == mx) and (wCh == wM) and not onCD
        end

        local shouldShow = flying and not isFull

        if shouldShow and not self._wasFlying then
            self._wasFlying = true
            self._targetAlpha = 1
        elseif not shouldShow and self._wasFlying then
            self._wasFlying = false
            self._targetAlpha = 0
        end

        -- 페이드
        if self._currentAlpha ~= self._targetAlpha then
            local fadeIn = 0.3
            local fadeOut = self.db.fadeOutDuration or 0.7
            local speed
            if self._targetAlpha > self._currentAlpha then
                speed = fadeIn > 0 and (elapsed / fadeIn) or 999
            else
                speed = fadeOut > 0 and (elapsed / fadeOut) or 999
            end
            local diff = self._targetAlpha - self._currentAlpha
            if abs(diff) <= speed then
                self._currentAlpha = self._targetAlpha
            else
                self._currentAlpha = self._currentAlpha + (diff > 0 and speed or -speed)
            end
            f:SetAlpha(self._currentAlpha)
            f:EnableMouse(self._currentAlpha > 0.1 and not self.db.locked)
        end

        if self._currentAlpha <= 0 then return end
        self:UpdateData()
    end)
end

------------------------------------------------------
-- Lerp
------------------------------------------------------
local function LerpC(from, to, t)
    return from[1] + (to[1] - from[1]) * t,
           from[2] + (to[2] - from[2]) * t,
           from[3] + (to[3] - from[3]) * t
end
local WHITE = { 1, 1, 1 }
local FLASH_DURATION = 0.3  -- 반짝 지속 시간

------------------------------------------------------
-- 데이터 갱신
------------------------------------------------------
function SkyridingTracker:UpdateData()
    local cV = self._cVigor  or { 0.20, 0.80, 1.00 }
    local cW = self._cWind   or { 0.40, 1.00, 0.55 }
    local cS = self._cSurge  or { 1.00, 0.55, 0.10 }

    -- Vigor
    local isC, ch, mx, cs, cd = GetVigorInfo()
    local cVd = self._cVigorDim or { 0.06, 0.15, 0.22 }
    local now = GetTime()

    -- 충전 완료 감지 → 플래시 등록
    if self._lastVigorCh >= 0 and ch > self._lastVigorCh then
        for idx = self._lastVigorCh + 1, ch do
            self._vigorFlash[idx] = now
        end
    end
    self._lastVigorCh = ch

    for i = 1, 6 do
        local fg = self.vigorFg[i]
        if i <= ch then
            -- 충전 완료: 색상 표시 (플래시: 흰색→색상)
            local flashStart = self._vigorFlash[i]
            if flashStart and (now - flashStart) < FLASH_DURATION then
                local ft = (now - flashStart) / FLASH_DURATION
                fg:SetAlpha(1)
                fg:SetVertexColor(LerpC(WHITE, cV, ft))
            else
                self._vigorFlash[i] = nil
                fg:SetAlpha(1)
                fg:SetVertexColor(cV[1], cV[2], cV[3], 1)
            end
        elseif i == ch + 1 and isC and cd > 0 then
            -- 충전 중: dim→흰색 Lerp
            local p = math.min(1, (now - cs) / cd)
            fg:SetAlpha(1)
            fg:SetVertexColor(LerpC(cVd, WHITE, p))
        else
            fg:SetAlpha(0)
        end
    end

    -- Wind (역방향)
    local wC, wCh, wM, wS, wD = GetSecondWindInfo()
    local cWd = self._cWindDim or { 0.08, 0.20, 0.12 }

    if self._lastWindCh >= 0 and wCh > self._lastWindCh then
        for idx = self._lastWindCh + 1, wCh do
            self._windFlash[4 - idx] = now  -- 역방향 인덱스
        end
    end
    self._lastWindCh = wCh

    for i = 1, 3 do
        local displayIdx = 4 - i
        local fg = self.windFg[displayIdx]
        if i <= wCh then
            -- 충전 완료: 색상 표시 (플래시: 흰색→색상)
            local flashStart = self._windFlash[displayIdx]
            if flashStart and (now - flashStart) < FLASH_DURATION then
                local ft = (now - flashStart) / FLASH_DURATION
                fg:SetAlpha(1)
                fg:SetVertexColor(LerpC(WHITE, cW, ft))
            else
                self._windFlash[displayIdx] = nil
                fg:SetAlpha(1)
                fg:SetVertexColor(cW[1], cW[2], cW[3], 1)
            end
        elseif i == wCh + 1 and wC and wD > 0 then
            -- 충전 중: dim→흰색 Lerp
            local p = math.min(1, (now - wS) / wD)
            fg:SetAlpha(1)
            fg:SetVertexColor(LerpC(cWd, WHITE, p))
        else
            fg:SetAlpha(0)
        end
    end

    -- Surge
    local sS, sD, onCD = GetWhirlingSurgeInfo()

    -- 쿨다운 완료 감지 → 플래시
    if self._lastSurgeOnCD and not onCD then
        self._surgeFlash = now
    end
    self._lastSurgeOnCD = onCD

    if onCD then
        local cSd = self._cSurgeDim or { 0.20, 0.12, 0.03 }
        -- 충전 중: dim→흰색 Lerp
        if now < sS + sD then
            local p = (now - sS) / sD
            self.surgeFg:SetAlpha(p)
            self.surgeFg:SetVertexColor(LerpC(cSd, WHITE, p))
        else
            self.surgeFg:SetAlpha(1)
            self.surgeFg:SetVertexColor(1, 1, 1, 1)
        end
    else
        -- 충전 완료: 색상 표시 (플래시: 흰색→색상)
        local flashStart = self._surgeFlash
        if flashStart and (now - flashStart) < FLASH_DURATION then
            local ft = (now - flashStart) / FLASH_DURATION
            self.surgeFg:SetAlpha(1)
            self.surgeFg:SetVertexColor(LerpC(WHITE, cS, ft))
        else
            self._surgeFlash = nil
            self.surgeFg:SetAlpha(1)
            self.surgeFg:SetVertexColor(cS[1], cS[2], cS[3], 1)
        end
    end
end

------------------------------------------------------
-- Reset
------------------------------------------------------
function SkyridingTracker:ResetPosition()
    if self.frame then
        ns:SetDBValue("profile.SkyridingTracker.posX", 0)
        ns:SetDBValue("profile.SkyridingTracker.posY", 0)
        self.db.posX = 0
        self.db.posY = 0
        self:ApplyPosition()
    end
end

DDingToolKit:RegisterModule("SkyridingTracker", SkyridingTracker)

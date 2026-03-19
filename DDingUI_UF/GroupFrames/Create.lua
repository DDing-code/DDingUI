--[[
	ddingUI UnitFrames
	GroupFrames/Create.lua — 프레임 요소 생성

	DandersFrames CreateFrameElements 패턴 차용
	StyleLib 기반 색상/텍스처
]]

local _, ns = ...
local GF = ns.GroupFrames
local C = ns.Constants       -- [REFACTOR] 아이콘 세트 등 상수 참조
local unpack = unpack

local SL = _G.DDingUI_StyleLib
local FLAT = SL and SL.Textures.flat or "Interface\\Buttons\\WHITE8x8"
local SL_FONT = SL and SL.Font.path or "Fonts\\2002.TTF"

local CreateFrame = CreateFrame
local GameFontNormalSmall = GameFontNormalSmall

-----------------------------------------------
-- SafeSetFont (DF 패턴: pcall 보호)
-----------------------------------------------

local function SafeSetFont(fontString, fontPath, fontSize, flags)
	if not fontString then return end
	local ok = pcall(fontString.SetFont, fontString, fontPath or SL_FONT, fontSize or 11, flags or "OUTLINE")
	if not ok then
		pcall(fontString.SetFont, fontString, "Fonts\\FRIZQT__.TTF", fontSize or 11, flags or "OUTLINE")
	end
end

GF.SafeSetFont = SafeSetFont

-----------------------------------------------
-- CreateFrameElements
-----------------------------------------------

function GF:CreateFrameElements(frame)
	if not frame then return end
	if frame.gfElementsCreated then return end

	local db = self:GetFrameDB(frame)

	-- ========================================
	-- BACKGROUND
	-- ========================================
	frame.background = frame:CreateTexture(nil, "BACKGROUND")
	frame.background:SetAllPoints()
	local bgColor = db.background and db.background.color or { 0.08, 0.08, 0.08, 0.85 }
	frame.background:SetTexture(FLAT)
	frame.background:SetVertexColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.85)

	-- ========================================
	-- HEALTH BAR
	-- ========================================
	frame.healthBar = CreateFrame("StatusBar", nil, frame)
	frame.healthBar:SetPoint("TOPLEFT", 0, 0)
	frame.healthBar:SetPoint("BOTTOMRIGHT", 0, 0)
	frame.healthBar:SetStatusBarTexture(FLAT)
	frame.healthBar:SetMinMaxValues(0, 100)
	frame.healthBar:SetValue(100)
	frame.healthBar:SetFrameLevel(frame:GetFrameLevel() + 1)

	-- ========================================
	-- HEAL PREDICTION BAR (힐 예측) 	-- [FIX] DandersFrames 패턴: parent를 frame으로 설정 (healthBar 자식이면 텍스처 bleeding 발생)
	-- ========================================
	frame.healPredictionBar = CreateFrame("StatusBar", nil, frame)
	frame.healPredictionBar:SetStatusBarTexture(FLAT)
	-- [FIX] DandersFrames 패턴: 타일링 비활성화 → pixel bleeding 방지
	local hpBarTex = frame.healPredictionBar:GetStatusBarTexture()
	if hpBarTex then
		hpBarTex:SetHorizTile(false)
		hpBarTex:SetVertTile(false)
		hpBarTex:SetTexCoord(0, 1, 0, 1)
	end
	frame.healPredictionBar:SetStatusBarColor(0, 1, 0.5, 0.4)
	frame.healPredictionBar:SetMinMaxValues(0, 1)
	frame.healPredictionBar:SetValue(0)
	frame.healPredictionBar:SetFrameLevel(frame.healthBar:GetFrameLevel() + 1)
	frame.healPredictionBar:EnableMouse(false)

	-- ========================================
	-- ABSORB BAR (보호막) 	-- [FIX] DandersFrames 패턴: parent를 frame으로 설정
	-- ========================================
	frame.absorbBar = CreateFrame("StatusBar", nil, frame)
	frame.absorbBar:SetStatusBarTexture(FLAT)
	-- [FIX] pixel bleeding 방지
	local abBarTex = frame.absorbBar:GetStatusBarTexture()
	if abBarTex then
		abBarTex:SetHorizTile(false)
		abBarTex:SetVertTile(false)
		abBarTex:SetTexCoord(0, 1, 0, 1)
	end
	frame.absorbBar:SetStatusBarColor(1, 1, 0, 0.4)
	frame.absorbBar:SetMinMaxValues(0, 1)
	frame.absorbBar:SetValue(0)
	frame.absorbBar:SetFrameLevel(frame.healthBar:GetFrameLevel() + 1)
	frame.absorbBar:EnableMouse(false)

	-- ========================================
	-- OVERSHIELD BAR (초과 보호막 오버레이) -- [12.0.1]
	-- 보호막이 부족 체력을 초과할 때 ReverseFill로 표시
	-- [FIX] DandersFrames 패턴: parent를 frame으로 설정
	-- ========================================
	frame.overShieldBar = CreateFrame("StatusBar", nil, frame)
	frame.overShieldBar:SetStatusBarTexture(FLAT)
	-- [FIX] pixel bleeding 방지
	local osBarTex = frame.overShieldBar:GetStatusBarTexture()
	if osBarTex then
		osBarTex:SetHorizTile(false)
		osBarTex:SetVertTile(false)
		osBarTex:SetTexCoord(0, 1, 0, 1)
	end
	frame.overShieldBar:SetStatusBarColor(1, 0.95, 0.3, 0.35)
	frame.overShieldBar:SetAllPoints(frame.healthBar)
	frame.overShieldBar:SetReverseFill(true)
	frame.overShieldBar:SetMinMaxValues(0, 1)
	frame.overShieldBar:SetValue(0)
	frame.overShieldBar:SetFrameLevel(frame.healthBar:GetFrameLevel() + 2)
	frame.overShieldBar:EnableMouse(false)
	frame.overShieldBar:Hide()

	-- OVERSHIELD GLOW (초과 보호막 가장자리 글로우) -- [12.0.1]
	frame.overShieldGlow = frame.healthBar:CreateTexture(nil, "OVERLAY", nil, 7)
	frame.overShieldGlow:SetTexture(FLAT)
	frame.overShieldGlow:SetVertexColor(1, 0.95, 0.3, 0.8)
	frame.overShieldGlow:SetBlendMode("ADD")
	frame.overShieldGlow:SetPoint("TOPRIGHT", frame.healthBar, "TOPRIGHT", 0, 0)
	frame.overShieldGlow:SetPoint("BOTTOMRIGHT", frame.healthBar, "BOTTOMRIGHT", 0, 0)
	frame.overShieldGlow:SetWidth(3)
	frame.overShieldGlow:Hide()

	-- ========================================
	-- HEAL ABSORB BAR (힐 흡수) 	-- [FIX] DandersFrames 패턴: parent를 frame으로 설정
	-- ========================================
	frame.healAbsorbBar = CreateFrame("StatusBar", nil, frame)
	frame.healAbsorbBar:SetStatusBarTexture(FLAT)
	-- [FIX] pixel bleeding 방지
	local haBarTex = frame.healAbsorbBar:GetStatusBarTexture()
	if haBarTex then
		haBarTex:SetHorizTile(false)
		haBarTex:SetVertTile(false)
		haBarTex:SetTexCoord(0, 1, 0, 1)
	end
	frame.healAbsorbBar:SetStatusBarColor(1, 0.1, 0.1, 0.5)
	frame.healAbsorbBar:SetMinMaxValues(0, 1)
	frame.healAbsorbBar:SetValue(0)
	frame.healAbsorbBar:SetReverseFill(true)
	frame.healAbsorbBar:SetFrameLevel(frame.healthBar:GetFrameLevel() + 1)
	frame.healAbsorbBar:EnableMouse(false)

	-- ========================================
	-- CONTENT OVERLAY (텍스트/아이콘을 바 위에 표시)
	-- ========================================
	frame.contentOverlay = CreateFrame("Frame", nil, frame)
	frame.contentOverlay:SetAllPoints()
	frame.contentOverlay:SetFrameLevel(frame:GetFrameLevel() + 25)
	frame.contentOverlay:EnableMouse(false)

	-- ========================================
	-- NAME TEXT
	-- ========================================
	frame.nameText = frame.contentOverlay:CreateFontString(nil, "ARTWORK")
	SafeSetFont(frame.nameText, SL_FONT, 11, "OUTLINE")
	frame.nameText:SetDrawLayer("ARTWORK", 7)
	frame.nameText:SetTextColor(1, 1, 1, 1)

	-- ========================================
	-- HEALTH TEXT
	-- ========================================
	frame.healthText = frame.contentOverlay:CreateFontString(nil, "ARTWORK")
	SafeSetFont(frame.healthText, SL_FONT, 10, "OUTLINE")
	frame.healthText:SetDrawLayer("ARTWORK", 7)
	frame.healthText:SetTextColor(1, 1, 1, 1)

	-- ========================================
	-- STATUS TEXT (Dead, Offline, AFK)
	-- ========================================
	frame.statusText = frame.contentOverlay:CreateFontString(nil, "OVERLAY")
	SafeSetFont(frame.statusText, SL_FONT, 10, "OUTLINE")
	frame.statusText:SetDrawLayer("OVERLAY", 7)
	frame.statusText:SetTextColor(1, 1, 1, 1)
	frame.statusText:SetPoint("CENTER", frame, "CENTER", 0, 0)
	frame.statusText:Hide()

	-- ========================================
	-- BORDER (4면 텍스처)
	-- ========================================
	frame.border = CreateFrame("Frame", nil, frame)
	frame.border:SetAllPoints()
	frame.border:SetFrameLevel(frame:GetFrameLevel() + 10)

	local borderSize = db.border and db.border.size or 1
	local borderColor = db.border and db.border.color or { 0, 0, 0, 1 }

	frame.border.top = frame.border:CreateTexture(nil, "BORDER")
	frame.border.top:SetHeight(borderSize)
	frame.border.top:SetPoint("TOPLEFT", 0, 0)
	frame.border.top:SetPoint("TOPRIGHT", 0, 0)
	frame.border.top:SetTexture(FLAT)
	frame.border.top:SetVertexColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)

	frame.border.bottom = frame.border:CreateTexture(nil, "BORDER")
	frame.border.bottom:SetHeight(borderSize)
	frame.border.bottom:SetPoint("BOTTOMLEFT", 0, 0)
	frame.border.bottom:SetPoint("BOTTOMRIGHT", 0, 0)
	frame.border.bottom:SetTexture(FLAT)
	frame.border.bottom:SetVertexColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)

	frame.border.left = frame.border:CreateTexture(nil, "BORDER")
	frame.border.left:SetWidth(borderSize)
	frame.border.left:SetPoint("TOPLEFT", 0, 0)
	frame.border.left:SetPoint("BOTTOMLEFT", 0, 0)
	frame.border.left:SetTexture(FLAT)
	frame.border.left:SetVertexColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)

	frame.border.right = frame.border:CreateTexture(nil, "BORDER")
	frame.border.right:SetWidth(borderSize)
	frame.border.right:SetPoint("TOPRIGHT", 0, 0)
	frame.border.right:SetPoint("BOTTOMRIGHT", 0, 0)
	frame.border.right:SetTexture(FLAT)
	frame.border.right:SetVertexColor(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1)

	frame.border.SetBorderColor = function(self, r, g, b, a)
		self.top:SetVertexColor(r, g, b, a)
		self.bottom:SetVertexColor(r, g, b, a)
		self.left:SetVertexColor(r, g, b, a)
		self.right:SetVertexColor(r, g, b, a)
	end

	-- ========================================
	-- POWER BAR
	-- ========================================
	frame.powerBar = CreateFrame("StatusBar", nil, frame)
	frame.powerBar:SetStatusBarTexture(FLAT)
	frame.powerBar:SetMinMaxValues(0, 1)
	frame.powerBar:SetValue(1)
	frame.powerBar:SetFrameLevel(frame.healthBar:GetFrameLevel() + 2)
	frame.powerBar:Hide()

	local powerBg = frame.powerBar:CreateTexture(nil, "BACKGROUND")
	powerBg:SetAllPoints()
	powerBg:SetTexture(FLAT)
	powerBg:SetVertexColor(0, 0, 0, 0.8)
	frame.powerBar.bg = powerBg

	-- ========================================
	-- ROLE ICON -- [REFACTOR] 아이콘 세트 적용
	-- ========================================
	local iconSet = C.ICON_SETS[ns.db.iconSet or "default"] or C.ICON_SETS["default"]
	frame.roleIcon = frame.contentOverlay:CreateTexture(nil, "OVERLAY")
	frame.roleIcon:SetSize(14, 14)
	frame.roleIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
	-- [REFACTOR] 개별 텍스처 모드 지원 (role.textures)
	if iconSet.role.texture then
		frame.roleIcon:SetTexture(iconSet.role.texture)
	end
	frame.roleIcon:SetDrawLayer("OVERLAY", 7)
	frame.roleIcon:Hide()

	-- ========================================
	-- LEADER ICON -- [REFACTOR] 아이콘 세트 적용
	-- ========================================
	frame.leaderIcon = frame.contentOverlay:CreateTexture(nil, "OVERLAY")
	frame.leaderIcon:SetSize(12, 12)
	frame.leaderIcon:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 2)
	frame.leaderIcon:SetTexture(iconSet.leader)
	frame.leaderIcon:SetDrawLayer("OVERLAY", 7)
	frame.leaderIcon:Hide()

	-- ========================================
	-- RAID TARGET ICON
	-- ========================================
	frame.raidTargetIcon = frame.contentOverlay:CreateTexture(nil, "OVERLAY")
	frame.raidTargetIcon:SetSize(16, 16)
	frame.raidTargetIcon:SetPoint("TOP", frame, "TOP", 0, 2)
	frame.raidTargetIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	frame.raidTargetIcon:SetDrawLayer("OVERLAY", 7)
	frame.raidTargetIcon:Hide()

	-- ========================================
	-- READY CHECK ICON
	-- ========================================
	frame.readyCheckIcon = frame.contentOverlay:CreateTexture(nil, "OVERLAY")
	frame.readyCheckIcon:SetSize(16, 16)
	frame.readyCheckIcon:SetPoint("CENTER", frame, "CENTER", 0, 0)
	frame.readyCheckIcon:SetDrawLayer("OVERLAY", 7)
	frame.readyCheckIcon:Hide()

	-- ========================================
	-- RESURRECT ICON
	-- ========================================
	frame.resurrectIcon = frame.contentOverlay:CreateTexture(nil, "OVERLAY")
	frame.resurrectIcon:SetSize(16, 16)
	frame.resurrectIcon:SetPoint("CENTER", frame, "CENTER", 0, 0)
	frame.resurrectIcon:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez")
	frame.resurrectIcon:SetDrawLayer("OVERLAY", 7)
	frame.resurrectIcon:Hide()

	-- ========================================
	-- AURA ICONS (버프 + 디버프)
	-- ========================================
	frame.buffIcons = {}
	frame.debuffIcons = {}

	local maxBuffs = 4
	local maxDebuffs = 4
	if frame.isRaidFrame then
		maxBuffs = 3
		maxDebuffs = 3
	end

	for i = 1, maxBuffs do
		frame.buffIcons[i] = self:CreateAuraIcon(frame, i, "BUFF")
	end
	for i = 1, maxDebuffs do
		frame.debuffIcons[i] = self:CreateAuraIcon(frame, i, "DEBUFF")
	end

	-- ========================================
	-- DEBUFF HIGHLIGHT (DandersFrames Dispel.lua 패턴: StatusBar 기반)
	-- ========================================
	frame.debuffHighlight = {}

	-- Border: 4면 StatusBar (Secret color 처리 가능 — DandersFrames 핵심 패턴)
	-- 일반 Texture는 secret value 처리 불가, StatusBar 관리 텍스처는 C++에서 처리
	frame.debuffHighlight.border = CreateFrame("Frame", nil, frame)
	frame.debuffHighlight.border:SetAllPoints()
	frame.debuffHighlight.border:SetFrameLevel((frame.contentOverlay or frame):GetFrameLevel() + 35) -- [FIX] contentOverlay보다 높게 → 이름 위에 표시

	local hlEdge = 2
	local hlBorder = frame.debuffHighlight.border

	-- [DandersFrames] StatusBar borders — SetVertexColor가 secret RGBA 처리 가능
	hlBorder.top = CreateFrame("StatusBar", nil, hlBorder)
	hlBorder.top:SetStatusBarTexture(FLAT)
	hlBorder.top:SetMinMaxValues(0, 1)
	hlBorder.top:SetValue(1)
	hlBorder.top:GetStatusBarTexture():SetBlendMode("BLEND")
	hlBorder.top:SetHeight(hlEdge)
	hlBorder.top:SetPoint("TOPLEFT", 0, 0)
	hlBorder.top:SetPoint("TOPRIGHT", 0, 0)

	hlBorder.bottom = CreateFrame("StatusBar", nil, hlBorder)
	hlBorder.bottom:SetStatusBarTexture(FLAT)
	hlBorder.bottom:SetMinMaxValues(0, 1)
	hlBorder.bottom:SetValue(1)
	hlBorder.bottom:GetStatusBarTexture():SetBlendMode("BLEND")
	hlBorder.bottom:SetHeight(hlEdge)
	hlBorder.bottom:SetPoint("BOTTOMLEFT", 0, 0)
	hlBorder.bottom:SetPoint("BOTTOMRIGHT", 0, 0)

	hlBorder.left = CreateFrame("StatusBar", nil, hlBorder)
	hlBorder.left:SetStatusBarTexture(FLAT)
	hlBorder.left:SetMinMaxValues(0, 1)
	hlBorder.left:SetValue(1)
	hlBorder.left:GetStatusBarTexture():SetBlendMode("BLEND")
	hlBorder.left:SetWidth(hlEdge)
	hlBorder.left:SetPoint("TOPLEFT", 0, 0)
	hlBorder.left:SetPoint("BOTTOMLEFT", 0, 0)

	hlBorder.right = CreateFrame("StatusBar", nil, hlBorder)
	hlBorder.right:SetStatusBarTexture(FLAT)
	hlBorder.right:SetMinMaxValues(0, 1)
	hlBorder.right:SetValue(1)
	hlBorder.right:GetStatusBarTexture():SetBlendMode("BLEND")
	hlBorder.right:SetWidth(hlEdge)
	hlBorder.right:SetPoint("TOPRIGHT", 0, 0)
	hlBorder.right:SetPoint("BOTTOMRIGHT", 0, 0)

	-- [DandersFrames 패턴] 일반 RGB 색상 설정 (non-secret)
	hlBorder.SetColor = function(self, r, g, b, a)
		self.top:GetStatusBarTexture():SetVertexColor(r, g, b, a)
		self.bottom:GetStatusBarTexture():SetVertexColor(r, g, b, a)
		self.left:GetStatusBarTexture():SetVertexColor(r, g, b, a)
		self.right:GetStatusBarTexture():SetVertexColor(r, g, b, a)
	end

	-- [DandersFrames 패턴] Secret color 객체 직접 전달 (C++이 처리)
	hlBorder.SetColorFromSecret = function(self, color)
		if not color or not color.GetRGBA then return end
		self.top:GetStatusBarTexture():SetVertexColor(color:GetRGBA())
		self.bottom:GetStatusBarTexture():SetVertexColor(color:GetRGBA())
		self.left:GetStatusBarTexture():SetVertexColor(color:GetRGBA())
		self.right:GetStatusBarTexture():SetVertexColor(color:GetRGBA())
	end

	hlBorder:SetColor(0, 0, 0, 0)
	hlBorder:Hide()

	-- Overlay: 체력바 위에 반투명 색상 덧씌우기 (ADD 블렌드)
	frame.debuffHighlight.overlay = frame.healthBar:CreateTexture(nil, "ARTWORK", nil, 7)
	frame.debuffHighlight.overlay:SetAllPoints(frame.healthBar)
	frame.debuffHighlight.overlay:SetTexture(FLAT)
	frame.debuffHighlight.overlay:SetBlendMode("ADD")
	frame.debuffHighlight.overlay:SetAlpha(0)

	-- [FIX] 그라디언트 오버레이 (DandersFrames 패턴: 프리베이크 텍스처)
	-- GradientV.tga: 알파 그라데이션이 내장된 텍스처 (상=불투명, 하=투명)
	-- SetTexCoord로 방향 회전 → SetVertexColor만으로 색 적용 (secret-safe)
	local hl = frame.debuffHighlight
	local GRAD_TEX = "Interface\\AddOns\\DDingUI_UF\\Media\\GradientV"

	hl.gradientTop = frame.healthBar:CreateTexture(nil, "ARTWORK", nil, 7)
	hl.gradientTop:SetTexture(GRAD_TEX)
	hl.gradientTop:SetTexCoord(0, 1, 0, 1) -- 기본: 상=불투명, 하=투명
	hl.gradientTop:SetBlendMode("ADD")
	hl.gradientTop:Hide()

	hl.gradientBottom = frame.healthBar:CreateTexture(nil, "ARTWORK", nil, 7)
	hl.gradientBottom:SetTexture(GRAD_TEX)
	hl.gradientBottom:SetTexCoord(0, 1, 1, 0) -- 상하 반전: 하=불투명, 상=투명
	hl.gradientBottom:SetBlendMode("ADD")
	hl.gradientBottom:Hide()

	hl.gradientLeft = frame.healthBar:CreateTexture(nil, "ARTWORK", nil, 7)
	hl.gradientLeft:SetTexture(GRAD_TEX)
	hl.gradientLeft:SetTexCoord(0, 0, 1, 0, 0, 1, 1, 1) -- 90° 회전: 좌=불투명, 우=투명
	hl.gradientLeft:SetBlendMode("ADD")
	hl.gradientLeft:Hide()

	hl.gradientRight = frame.healthBar:CreateTexture(nil, "ARTWORK", nil, 7)
	hl.gradientRight:SetTexture(GRAD_TEX)
	hl.gradientRight:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1) -- -90° 회전: 우=불투명, 좌=투명
	hl.gradientRight:SetBlendMode("ADD")
	hl.gradientRight:Hide()

	-- ========================================
	-- THREAT BORDER (위협 표시) -- [12.0.1]
	-- ========================================
	frame.threatBorder = CreateFrame("Frame", nil, frame)
	frame.threatBorder:SetAllPoints()
	frame.threatBorder:SetFrameLevel(frame:GetFrameLevel() + 12) -- debuffHighlight(+11) 위

	local tb = frame.threatBorder
	tb.top = tb:CreateTexture(nil, "OVERLAY")
	tb.top:SetHeight(2)
	tb.top:SetPoint("TOPLEFT", 0, 0)
	tb.top:SetPoint("TOPRIGHT", 0, 0)
	tb.top:SetTexture(FLAT)

	tb.bottom = tb:CreateTexture(nil, "OVERLAY")
	tb.bottom:SetHeight(2)
	tb.bottom:SetPoint("BOTTOMLEFT", 0, 0)
	tb.bottom:SetPoint("BOTTOMRIGHT", 0, 0)
	tb.bottom:SetTexture(FLAT)

	tb.left = tb:CreateTexture(nil, "OVERLAY")
	tb.left:SetWidth(2)
	tb.left:SetPoint("TOPLEFT", 0, 0)
	tb.left:SetPoint("BOTTOMLEFT", 0, 0)
	tb.left:SetTexture(FLAT)

	tb.right = tb:CreateTexture(nil, "OVERLAY")
	tb.right:SetWidth(2)
	tb.right:SetPoint("TOPRIGHT", 0, 0)
	tb.right:SetPoint("BOTTOMRIGHT", 0, 0)
	tb.right:SetTexture(FLAT)

	tb.SetColor = function(self, r, g, b, a)
		self.top:SetVertexColor(r, g, b, a)
		self.bottom:SetVertexColor(r, g, b, a)
		self.left:SetVertexColor(r, g, b, a)
		self.right:SetVertexColor(r, g, b, a)
	end

	tb:SetColor(0, 0, 0, 0)
	tb:Hide()

	-- ========================================
	-- TARGET/FOCUS HIGHLIGHT BORDER -- [12.0.1]
	-- ========================================
	frame.highlightBorder = CreateFrame("Frame", nil, frame)
	frame.highlightBorder:SetAllPoints()
	frame.highlightBorder:SetFrameLevel(frame:GetFrameLevel() + 13) -- threat(+12) 위

	local hb = frame.highlightBorder
	hb.top = hb:CreateTexture(nil, "OVERLAY")
	hb.top:SetHeight(2)
	hb.top:SetPoint("TOPLEFT", 0, 0)
	hb.top:SetPoint("TOPRIGHT", 0, 0)
	hb.top:SetTexture(FLAT)

	hb.bottom = hb:CreateTexture(nil, "OVERLAY")
	hb.bottom:SetHeight(2)
	hb.bottom:SetPoint("BOTTOMLEFT", 0, 0)
	hb.bottom:SetPoint("BOTTOMRIGHT", 0, 0)
	hb.bottom:SetTexture(FLAT)

	hb.left = hb:CreateTexture(nil, "OVERLAY")
	hb.left:SetWidth(2)
	hb.left:SetPoint("TOPLEFT", 0, 0)
	hb.left:SetPoint("BOTTOMLEFT", 0, 0)
	hb.left:SetTexture(FLAT)

	hb.right = hb:CreateTexture(nil, "OVERLAY")
	hb.right:SetWidth(2)
	hb.right:SetPoint("TOPRIGHT", 0, 0)
	hb.right:SetPoint("BOTTOMRIGHT", 0, 0)
	hb.right:SetTexture(FLAT)

	hb.SetColor = function(self, r, g, b, a)
		self.top:SetVertexColor(r, g, b, a)
		self.bottom:SetVertexColor(r, g, b, a)
		self.left:SetVertexColor(r, g, b, a)
		self.right:SetVertexColor(r, g, b, a)
	end

	hb:SetColor(0, 0, 0, 0)
	hb:Hide()

	-- ========================================
	-- PRIVATE AURA ANCHORS (DandersFrame 패턴) -- [FIX] DB 설정 기반
	-- ========================================
	frame.privateAuraAnchors = {}
	local paDB = (db.widgets or {}).privateAuras or {}
	local paMax = paDB.maxAuras or 2
	local paSizeDB = paDB.size or {}
	local paW = paSizeDB.width or 24
	local paH = paSizeDB.height or 24
	local paSpacingDB = paDB.spacing or {}
	local paHSpacing = paSpacingDB.horizontal or 2

	for i = 1, paMax do
		local anchor = CreateFrame("Frame", nil, frame.contentOverlay or frame)
		anchor:SetSize(paW, paH)
		anchor:SetFrameLevel((frame.contentOverlay or frame):GetFrameLevel() + 50)

		-- 위치는 ApplyLayout에서 설정
		frame.privateAuraAnchors[i] = anchor
	end

	-- ========================================
	-- DEFENSIVE ICONS (생존기/외생기) -- [FIX] 미구현 → 구현
	-- ========================================
	frame.defensiveIcons = {}
	local defDB = (db.widgets or {}).defensives or {}
	local defMax = defDB.maxIcons or 4
	local defScale = defDB.scale or 1.0
	local defSizeDB = defDB.size or {}
	local defW = (defSizeDB.width or 20) * defScale
	local defH = (defSizeDB.height or 20) * defScale

	for i = 1, defMax do
		local btn = CreateFrame("Frame", nil, frame.contentOverlay or frame)
		btn:SetSize(defW, defH)
		btn:SetFrameLevel((frame.contentOverlay or frame):GetFrameLevel() + 42)

		btn.Icon = btn:CreateTexture(nil, "ARTWORK")
		btn.Icon:SetAllPoints()
		btn.Icon:SetTexCoord(0.15, 0.85, 0.15, 0.85)

		-- 테두리
		btn.border = btn:CreateTexture(nil, "BACKGROUND")
		btn.border:SetPoint("TOPLEFT", -1, 1)
		btn.border:SetPoint("BOTTOMRIGHT", 1, -1)
		btn.border:SetColorTexture(0, 0, 0, 0.8)

		-- 쿨다운 — [12.0.1] 네이티브 카운트다운 사용 (일반 버프 아이콘과 동일 패턴)
		btn.Cooldown = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
		btn.Cooldown:SetAllPoints()
		btn.Cooldown:SetDrawEdge(false)
		btn.Cooldown:SetReverse(true)
		btn.Cooldown:SetHideCountdownNumbers(false) -- [12.0.1] 네이티브 카운트다운 표시 (secret-safe, C++)
		btn.Cooldown.noCooldownCount = true -- OmniCC 등 외부 쿨다운 텍스트 차단

		-- Text overlay (쿨다운 위에 텍스트 표시)
		btn.textOverlay = CreateFrame("Frame", nil, btn)
		btn.textOverlay:SetAllPoints()
		btn.textOverlay:SetFrameLevel(btn.Cooldown:GetFrameLevel() + 5)
		btn.textOverlay:EnableMouse(false)

		-- [12.0.1] 네이티브 쿨다운 텍스트 찾기 (일반 버프 아이콘과 동일 DandersFrame 패턴)
		local regions = { btn.Cooldown:GetRegions() }
		for _, region in ipairs(regions) do
			if region and region.GetObjectType and region:GetObjectType() == "FontString" then
				btn.nativeCooldownText = region
				region:ClearAllPoints()
				region:SetPoint("CENTER", btn, "CENTER", 0, 0)
				SafeSetFont(region, SL_FONT, 9, "OUTLINE")
				region:SetTextColor(1, 1, 1, 1)
				break
			end
		end

		-- Stacks 텍스트
		btn.Count = btn.textOverlay:CreateFontString(nil, "OVERLAY")
		SafeSetFont(btn.Count, SL_FONT, 9, "OUTLINE")
		btn.Count:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", 2, -1)
		btn.Count:Hide()

		btn:Hide()
		frame.defensiveIcons[i] = btn
	end

	-- ========================================
	-- HOT INDICATORS (HoT 추적 인디케이터) -- [HOT-TRACKER]
	-- 5가지 표시 유형: bar, gradient, healthColor, outline, text
	-- ========================================
	frame.hotIndicators = {}
	local hotDB = (db.widgets or {}).hotTracker or {}
	local hotMax = 10 -- 모든 전문화 커버 (Holy Paladin 최대 9)
	local hotSizeDB = hotDB.size or {}
	local hotW = hotSizeDB.width or 14
	local hotH = hotSizeDB.height or 14

	for i = 1, hotMax do
		local indicator = CreateFrame("Frame", nil, frame.contentOverlay or frame)
		indicator:SetSize(hotW, hotH)
		indicator:SetFrameLevel((frame.contentOverlay or frame):GetFrameLevel() + 45)

		-- 아이콘 텍스처
		indicator.texture = indicator:CreateTexture(nil, "ARTWORK")
		indicator.texture:SetAllPoints()

		-- [HOT-TRACKER] gradient 오버레이 (남은 시간 % 기반 색상 변화)
		indicator.gradientOverlay = indicator:CreateTexture(nil, "ARTWORK", nil, 1)
		indicator.gradientOverlay:SetAllPoints()
		indicator.gradientOverlay:SetColorTexture(1, 1, 1, 1)
		indicator.gradientOverlay:SetBlendMode("ADD")
		indicator.gradientOverlay:Hide()

		-- 쿨다운 — [12.0.1] swipe 전용 (텍스트 제거됨)
		indicator.cooldown = CreateFrame("Cooldown", nil, indicator, "CooldownFrameTemplate")
		indicator.cooldown:SetAllPoints(indicator.texture)
		indicator.cooldown:SetDrawEdge(false)
		indicator.cooldown:SetDrawSwipe(true)
		indicator.cooldown:SetReverse(true)
		indicator.cooldown:SetHideCountdownNumbers(true) -- [12.0.1] 텍스트 제거
		indicator.cooldown.noCooldownCount = true -- OmniCC 차단

		-- [HOT-TRACKER] bar (StatusBar — 지속시간 막대, 자동 감소)
		indicator.durationBar = CreateFrame("StatusBar", nil, indicator)
		indicator.durationBar:SetStatusBarTexture(FLAT)
		indicator.durationBar:SetStatusBarColor(0.3, 0.85, 0.45, 0.8)
		indicator.durationBar:SetMinMaxValues(0, 1)
		indicator.durationBar:SetValue(1)
		indicator.durationBar:SetSize(hotW, 3)
		indicator.durationBar:SetPoint("BOTTOM", indicator, "TOP", 0, 1)
		indicator.durationBar.bg = indicator.durationBar:CreateTexture(nil, "BACKGROUND")
		indicator.durationBar.bg:SetAllPoints()
		indicator.durationBar.bg:SetColorTexture(0, 0, 0, 0.6)
		indicator.durationBar:Hide()

		-- 테두리
		indicator.border = indicator:CreateTexture(nil, "BACKGROUND")
		indicator.border:SetPoint("TOPLEFT", -1, 1)
		indicator.border:SetPoint("BOTTOMRIGHT", 1, -1)
		indicator.border:SetColorTexture(0, 0, 0, 0.8)

		-- 메타데이터
		indicator.hotName = nil
		indicator.auraInstanceID = nil

		indicator:Hide()
		frame.hotIndicators[i] = indicator
	end

	-- [HOT-TRACKER] 프레임-레벨: outline 테두리 (HoT 활성 시 외곽선 강조)
	frame.hotOutline = CreateFrame("Frame", nil, frame)
	frame.hotOutline:SetAllPoints(frame)
	frame.hotOutline:SetFrameLevel((frame.contentOverlay or frame):GetFrameLevel() + 30) -- [FIX] contentOverlay보다 높게 → 이름 텍스트 위에 표시
	frame.hotOutline.top = frame.hotOutline:CreateTexture(nil, "OVERLAY")
	frame.hotOutline.top:SetColorTexture(0.3, 0.85, 0.45, 1)
	frame.hotOutline.top:SetPoint("TOPLEFT", frame.hotOutline, "TOPLEFT", 0, 0)
	frame.hotOutline.top:SetPoint("TOPRIGHT", frame.hotOutline, "TOPRIGHT", 0, 0)
	frame.hotOutline.top:SetHeight(2)
	frame.hotOutline.bottom = frame.hotOutline:CreateTexture(nil, "OVERLAY")
	frame.hotOutline.bottom:SetColorTexture(0.3, 0.85, 0.45, 1)
	frame.hotOutline.bottom:SetPoint("BOTTOMLEFT", frame.hotOutline, "BOTTOMLEFT", 0, 0)
	frame.hotOutline.bottom:SetPoint("BOTTOMRIGHT", frame.hotOutline, "BOTTOMRIGHT", 0, 0)
	frame.hotOutline.bottom:SetHeight(2)
	frame.hotOutline.left = frame.hotOutline:CreateTexture(nil, "OVERLAY")
	frame.hotOutline.left:SetColorTexture(0.3, 0.85, 0.45, 1)
	frame.hotOutline.left:SetPoint("TOPLEFT", frame.hotOutline, "TOPLEFT", 0, 0)
	frame.hotOutline.left:SetPoint("BOTTOMLEFT", frame.hotOutline, "BOTTOMLEFT", 0, 0)
	frame.hotOutline.left:SetWidth(2)
	frame.hotOutline.right = frame.hotOutline:CreateTexture(nil, "OVERLAY")
	frame.hotOutline.right:SetColorTexture(0.3, 0.85, 0.45, 1)
	frame.hotOutline.right:SetPoint("TOPRIGHT", frame.hotOutline, "TOPRIGHT", 0, 0)
	frame.hotOutline.right:SetPoint("BOTTOMRIGHT", frame.hotOutline, "BOTTOMRIGHT", 0, 0)
	frame.hotOutline.right:SetWidth(2)
	frame.hotOutline:Hide()

	-- [HOT-TRACKER] 프레임-레벨: gradient 오버레이 (지정색→투명)
	-- [FIX] OVERLAY:1 → ARTWORK 레이어(debuff gradient 포함) 위에 배치
	-- 디버프 gradient(ARTWORK:7)와 HOT gradient가 동시에 표시됨
	frame.hotGradient = frame.healthBar:CreateTexture(nil, "OVERLAY", nil, 1)
	frame.hotGradient:SetAllPoints(frame.healthBar)
	frame.hotGradient:SetTexture(FLAT)
	frame.hotGradient:Hide()

	-- [HOT-TRACKER] healthColor 상태
	frame.hotHealthColorActive = false
	frame.hotHealthColorData = nil

	-- ========================================
	-- CLICK SUPPORT + HOVER HIGHLIGHT -- [12.0.1]
	-- ========================================
	if not InCombatLockdown() then
		frame:RegisterForClicks("AnyUp")
		frame:SetAttribute("type1", "target")
		frame:SetAttribute("type2", "togglemenu")
	end

	-- [12.0.1] Hover highlight + Unit Tooltip (HookScript으로 기존 스크립트 보존)
	frame:HookScript("OnEnter", function(self)
		-- [FIX] 유닛 툴팁 표시
		if self.unit and GameTooltip then
			GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
			GameTooltip:SetUnit(self.unit)
			GameTooltip:Show()
		end

		if not self.highlightBorder then return end
		local fdb = GF:GetFrameDB(self)
		local hlDB = (fdb.widgets or {}).highlight or {}
		if hlDB.enabled == false or not hlDB.hover then return end
		-- 타겟/포커스가 이미 표시 중이면 hover 무시
		if self.highlightBorder:IsShown() then return end
		local color = hlDB.hoverColor or { 1, 1, 1, 0.3 }
		local borderSize = hlDB.size or 1
		self.highlightBorder.top:SetHeight(borderSize)
		self.highlightBorder.bottom:SetHeight(borderSize)
		self.highlightBorder.left:SetWidth(borderSize)
		self.highlightBorder.right:SetWidth(borderSize)
		self.highlightBorder:SetColor(color[1], color[2], color[3], color[4] or 0.3)
		self.highlightBorder:Show()
		self._gfHoverActive = true
	end)

	frame:HookScript("OnLeave", function(self)
		-- [FIX] 유닛 툴팁 숨기기
		if GameTooltip then
			GameTooltip:Hide()
		end

		if not self.highlightBorder or not self._gfHoverActive then return end
		self._gfHoverActive = nil
		-- 타겟/포커스 표시가 필요하면 UpdateHighlight 재호출
		if GF.UpdateHighlight then
			GF:UpdateHighlight(self)
		else
			self.highlightBorder:Hide()
		end
	end)

	-- ========================================
	-- CUSTOM TEXT (사용자 정의 텍스트) -- [FIX] 그룹프레임 커스텀텍스트 지원
	-- ========================================
	frame.customTexts = {}
	local ctDB = (db.widgets or {}).customText or {}
	if ctDB.enabled and ctDB.texts then
		for key, textDB in pairs(ctDB.texts) do
			if textDB.enabled and textDB.textFormat and textDB.textFormat ~= "" then
				local fs = frame.contentOverlay:CreateFontString(nil, "OVERLAY")
				local tFont = textDB.font or {}
				SafeSetFont(fs, tFont.style or SL_FONT, tFont.size or 10, tFont.outline or "OUTLINE")
				if tFont.shadow then
					fs:SetShadowColor(0, 0, 0, 1)
					fs:SetShadowOffset(1, -1)
				else
					fs:SetShadowOffset(0, 0)
				end
				fs:SetDrawLayer("OVERLAY", 7)
				local pos = textDB.position or {}
				fs:SetPoint(
					pos.point or "CENTER",
					frame,
					pos.relativePoint or "CENTER",
					pos.offsetX or 0,
					pos.offsetY or 0
				)
				fs:SetJustifyH(tFont.justify or "CENTER")
				-- 색상
				local color = textDB.color
				if color and color.type == "custom" and color.rgb then
					fs:SetTextColor(color.rgb[1] or 1, color.rgb[2] or 1, color.rgb[3] or 1, 1)
				end
				-- 태그 문자열 저장 (UpdateCustomTexts에서 평가)
				fs._tagString = textDB.textFormat
				fs._colorDB = textDB.color
				frame.customTexts[key] = fs
			end
		end
	end

	frame.gfElementsCreated = true
end

-----------------------------------------------
-- CreateAuraIcon (DF 패턴 + StyleLib)
-----------------------------------------------

function GF:CreateAuraIcon(parent, index, auraType)
	local iconParent = parent.contentOverlay or parent
	local icon = CreateFrame("Frame", nil, iconParent)
	icon:SetSize(18, 18)
	icon.unitFrame = parent  -- 유닛프레임 참조 저장

	local baseLevel = parent:GetFrameLevel()
	icon:SetFrameLevel(baseLevel + 40)

	-- Border (BACKGROUND layer → 아이콘 텍스처가 위에 그려짐)
	icon.border = icon:CreateTexture(nil, "BACKGROUND")
	icon.border:SetPoint("TOPLEFT", -1, 1)
	icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
	icon.border:SetColorTexture(1, 1, 1, 1)  -- 흰색 기본 → SetVertexColor로 색상 변경
	icon.border:SetVertexColor(0, 0, 0, 0.8)

	-- Icon texture
	icon.texture = icon:CreateTexture(nil, "ARTWORK")
	icon.texture:SetAllPoints()
	icon.texture:SetTexCoord(0.15, 0.85, 0.15, 0.85)

	-- Cooldown (swipe)
	icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
	icon.cooldown:SetAllPoints(icon.texture)
	icon.cooldown:SetDrawEdge(false)
	icon.cooldown:SetDrawSwipe(true)
	icon.cooldown:SetReverse(true)
	icon.cooldown:SetHideCountdownNumbers(false) -- [FIX] 네이티브 카운트다운 사용 (secret-safe, C++ 레벨)
	icon.cooldown.noCooldownCount = true -- [FIX] OmniCC 등 외부 쿨다운 텍스트 애드온 차단

	-- Text overlay (쿨다운 위)
	icon.textOverlay = CreateFrame("Frame", nil, icon)
	icon.textOverlay:SetAllPoints(icon)
	icon.textOverlay:SetFrameLevel(icon.cooldown:GetFrameLevel() + 5)
	icon.textOverlay:EnableMouse(false)

	-- Stack count
	icon.count = icon.textOverlay:CreateFontString(nil, "OVERLAY")
	icon.count:SetFontObject(GameFontNormalSmall)
	SafeSetFont(icon.count, SL_FONT, 10, "OUTLINE")
	icon.count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
	icon.count:SetTextColor(1, 1, 1, 1)

	-- Duration text (커스텀 FontString은 비활성 — 네이티브 카운트다운 사용)
	icon.duration = icon.textOverlay:CreateFontString(nil, "OVERLAY")
	icon.duration:SetFontObject(GameFontNormalSmall)
	SafeSetFont(icon.duration, SL_FONT, 9, "OUTLINE")
	icon.duration:SetPoint("CENTER", icon, "CENTER", 0, 0)
	icon.duration:SetTextColor(1, 1, 1, 1)
	icon.duration:Hide()

	-- [FIX] 네이티브 쿨다운 텍스트 찾기 (DandersFrame 패턴)
	-- CooldownFrameTemplate의 내장 FontString을 textOverlay로 이동 + 리스타일
	if icon.cooldown then
		local regions = { icon.cooldown:GetRegions() }
		for _, region in ipairs(regions) do
			if region and region.GetObjectType and region:GetObjectType() == "FontString" then
				icon.nativeCooldownText = region
				region:ClearAllPoints()
				region:SetPoint("CENTER", icon, "CENTER", 0, 0)
				SafeSetFont(region, SL_FONT, 9, "OUTLINE")
				region:SetTextColor(1, 1, 1, 1)
				break
			end
		end
	end

	icon.auraType = auraType
	icon.unitFrame = parent
	icon:Hide()

	-- Tooltip
	icon:EnableMouse(true)
	-- [FIX] SecureGroupHeader 자식 초기화 시 taint 방지
	-- SecureStateDriver:Show() 경로에서 호출되면 ADDON_ACTION_BLOCKED 발생
	if not InCombatLockdown() then
		if icon.SetPropagateMouseMotion then
			icon:SetPropagateMouseMotion(true)
		end
		if icon.SetMouseClickEnabled then
			icon:SetMouseClickEnabled(false)
		end
	end

	icon:SetScript("OnEnter", function(self)
		if not self:IsShown() then return end
		if not self.auraInstanceID or not self.unitFrame or not self.unitFrame.unit then return end

		-- [FIX] 옵션에서 툴팁 표시를 껐을 경우 툴팁이 나타나지 않도록 방어 코드 추가
		local db = GF:GetFrameDB(self.unitFrame)
		local widgets = db and db.widgets or {}
		local widgetKey = auraType == "DEBUFF" and "debuffs" or "buffs"
		local auraDB = widgets[widgetKey] or {}
		
		if auraDB.showTooltip == false then return end

		GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
		if auraType == "BUFF" then
			if GameTooltip.SetUnitBuffByAuraInstanceID then
				GameTooltip:SetUnitBuffByAuraInstanceID(self.unitFrame.unit, self.auraInstanceID)
			end
		else
			if GameTooltip.SetUnitDebuffByAuraInstanceID then
				GameTooltip:SetUnitDebuffByAuraInstanceID(self.unitFrame.unit, self.auraInstanceID)
			end
		end
	end)

	icon:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	return icon
end

-----------------------------------------------
-- ApplyLayout — 레이아웃 적용 (설정 변경 시)
-----------------------------------------------

function GF:ApplyLayout(frame)
	if not frame then return end

	local db = self:GetFrameDB(frame)
	local size = db.size or { 120, 36 }
	local widgets = db.widgets or {}

	-- [FIX] 전투 중에도 non-secure 위젯 레이아웃은 적용 가능
	-- frame:SetSize + healthBar/powerBar 앵커만 secure → 전투 종료 후 지연
	if InCombatLockdown() and frame.gfIsHeaderChild then
		-- secure operation 지연 등록
		self:DeferSecureLayout(frame)
	else
		-- 프레임 크기 (secure)
		frame:SetSize(size[1], size[2])

		-- 체력바 위치 (파워바 공간 확보)
		local powerBarDB = widgets.powerBar or {}
		local powerEnabled = powerBarDB.enabled ~= false
		local powerSize = powerBarDB.size or {}
		local powerHeight = powerSize.height or powerSize[2] or 4

		frame.healthBar:ClearAllPoints()
		if powerEnabled then
			frame.healthBar:SetPoint("TOPLEFT", 0, 0)
			frame.healthBar:SetPoint("BOTTOMRIGHT", 0, powerHeight)

			frame.powerBar:ClearAllPoints()
			frame.powerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
			frame.powerBar:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
			frame.powerBar:SetHeight(powerHeight)
			frame.powerBar:Show()
		else
			frame.healthBar:SetPoint("TOPLEFT", 0, 0)
			frame.healthBar:SetPoint("BOTTOMRIGHT", 0, 0)
			frame.powerBar:Hide()
		end
	end

	-- ===== Non-secure operations: 전투 중에도 안전하게 실행 =====

	-- 체력바 텍스처 -- [REFACTOR]
	local mediaTexture = ns.db and ns.db.media and ns.db.media.texture
	if mediaTexture and type(mediaTexture) == "string" and mediaTexture:find("[/\\]") then
		frame.healthBar:SetStatusBarTexture(mediaTexture)
	else
		frame.healthBar:SetStatusBarTexture(FLAT)
	end

	-- ========================================
	-- 이름 텍스트 (위치 + 폰트 + 정렬) -- [REFACTOR]
	-- ========================================
	local nameDB = widgets.nameText or {}
	local namePos = nameDB.position or {}
	local nameFont = nameDB.font or {}
	frame.nameText:ClearAllPoints()
	frame.nameText:SetPoint(
		namePos.point or "LEFT",
		frame,
		namePos.relativePoint or "LEFT",
		namePos.offsetX or 4,
		namePos.offsetY or 0
	)
	SafeSetFont(frame.nameText, SL_FONT, nameFont.size or 12, nameFont.outline or "OUTLINE")
	frame.nameText:SetJustifyH(nameFont.justify or "LEFT")
	if nameFont.shadow then
		frame.nameText:SetShadowColor(0, 0, 0, 1)
		frame.nameText:SetShadowOffset(1, -1)
	else
		frame.nameText:SetShadowOffset(0, 0)
	end
	if nameDB.enabled == false then
		frame.nameText:Hide()
	else
		frame.nameText:Show()
	end

	-- ========================================
	-- 체력 텍스트 (위치 + 폰트 + 정렬) -- [REFACTOR]
	-- ========================================
	local healthDB = widgets.healthText or {}
	local healthPos = healthDB.position or {}
	local healthFont = healthDB.font or {}
	if healthDB.enabled ~= false then
		frame.healthText:ClearAllPoints()
		frame.healthText:SetPoint(
			healthPos.point or "RIGHT",
			frame,
			healthPos.relativePoint or "RIGHT",
			healthPos.offsetX or -3,
			healthPos.offsetY or 0
		)
		SafeSetFont(frame.healthText, SL_FONT, healthFont.size or 11, healthFont.outline or "OUTLINE")
		frame.healthText:SetJustifyH(healthFont.justify or "RIGHT")
		if healthFont.shadow then
			frame.healthText:SetShadowColor(0, 0, 0, 1)
			frame.healthText:SetShadowOffset(1, -1)
		else
			frame.healthText:SetShadowOffset(0, 0)
		end
		frame.healthText:Show()
	else
		frame.healthText:Hide()
	end

	-- 상태 텍스트 (Dead/Offline/AFK) -- [FIX] position/font/color/shadow 전부 적용
	local statusDB = widgets.statusText or {}
	if statusDB.enabled ~= false then
		local statusPos = statusDB.position or {}
		local statusFont = statusDB.font or { size = 11, outline = "OUTLINE" }
		frame.statusText:ClearAllPoints()
		frame.statusText:SetPoint(
			statusPos.point or "CENTER",
			frame,
			statusPos.relativePoint or "CENTER",
			statusPos.offsetX or 0,
			statusPos.offsetY or 0
		)
		SafeSetFont(frame.statusText, SL_FONT, statusFont.size or 10, statusFont.outline or "OUTLINE")
		-- 색상
		local stColor = statusDB.color
		if stColor and stColor.type == "custom" and stColor.rgb then
			frame.statusText:SetTextColor(stColor.rgb[1] or 0.8, stColor.rgb[2] or 0.8, stColor.rgb[3] or 0.8, 1)
		else
			frame.statusText:SetTextColor(0.8, 0.8, 0.8, 1)
		end
		-- 그림자 (statusFont.shadow 사용 - 중복옵션 제거됨)
		if statusFont.shadow then
			frame.statusText:SetShadowColor(0, 0, 0, 1)
			frame.statusText:SetShadowOffset(1, -1)
		else
			frame.statusText:SetShadowOffset(0, 0)
		end
	end

	-- ========================================
	-- 인디케이터 위치/크기 일괄 적용 -- [12.0.1]
	-- ========================================
	local function ApplyGFIndicator(indicator, widgetDB, defW, defH, defPoint, defRelPoint, defOX, defOY)
		if not indicator or not widgetDB then return end
		if widgetDB.enabled == false then return end
		local sz = widgetDB.size or {}
		indicator:SetSize(sz.width or defW, sz.height or defH)
		local pos = widgetDB.position or {}
		indicator:ClearAllPoints()
		indicator:SetPoint(
			pos.point or defPoint,
			frame,
			pos.relativePoint or defRelPoint,
			pos.offsetX or defOX,
			pos.offsetY or defOY
		)
	end

	ApplyGFIndicator(frame.roleIcon, widgets.roleIcon or {}, 14, 14, "TOPLEFT", "TOPLEFT", 2, -2)
	ApplyGFIndicator(frame.leaderIcon, widgets.leaderIcon or {}, 12, 12, "TOPLEFT", "TOPLEFT", -2, 2)
	ApplyGFIndicator(frame.raidTargetIcon, widgets.raidIcon or {}, 16, 16, "TOP", "TOP", 0, 2)
	ApplyGFIndicator(frame.readyCheckIcon, widgets.readyCheckIcon or {}, 16, 16, "CENTER", "CENTER", 0, 0)
	ApplyGFIndicator(frame.resurrectIcon, widgets.resurrectIcon or {}, 16, 16, "CENTER", "CENTER", 0, 0)

	-- 아우라 아이콘 레이아웃
	self:ApplyAuraLayout(frame)

	-- ========================================
	-- PRIVATE AURA ANCHORS 배치 -- [FIX] DB 기반 위치/크기
	-- ========================================
	if frame.privateAuraAnchors then
		local paDB = widgets.privateAuras or {}
		local paScale = paDB.scale or 1.0
		local paSizeDB = paDB.size or {}
		local paW = (paSizeDB.width or 24) * paScale
		local paH = (paSizeDB.height or 24) * paScale
		local paSpacingDB = paDB.spacing or {}
		local paHSpacing = paSpacingDB.horizontal or 2
		local paPos = paDB.position or {}
		local paMax = paDB.maxAuras or 2
		local paPoint = paPos.point or "CENTER"
		local paRelPoint = paPos.relativePoint or "CENTER"
		local paOX = paPos.offsetX or 0
		local paOY = paPos.offsetY or 0

		for i = 1, #frame.privateAuraAnchors do
			local anchor = frame.privateAuraAnchors[i]
			if anchor then
				anchor:SetSize(paW, paH)
				anchor:ClearAllPoints()
				local offset = ((i - 1) - (paMax - 1) / 2) * (paW + paHSpacing)
				anchor:SetPoint(paPoint, frame, paRelPoint, paOX + offset, paOY)
			end
		end
		-- [FIX] 앵커 위치/크기 변경 → C_UnitAuras에 재등록
		if GF.UpdatePrivateAuraAnchors then
			GF:UpdatePrivateAuraAnchors(frame)
		end
	end

	-- ========================================
	-- DEFENSIVE ICONS 배치 -- [12.0.1] CenterDefensiveBuff 기반 (유닛당 최대 1개)
	-- ========================================
	if frame.defensiveIcons then
		local defDB = widgets.defensives or {}
		local defScale = defDB.scale or 1.0
		local defSizeDB = defDB.size or {}
		local defW = (defSizeDB.width or 20) * defScale
		local defH = (defSizeDB.height or 20) * defScale
		local defSpacingDB = defDB.spacing or {}
		local defHSpacing = defSpacingDB.horizontal or 2
		local defVSpacing = defSpacingDB.vertical or 2
		local defPos = defDB.position or {}
		local defPoint = defPos.point or "CENTER"
		local defRelPoint = defPos.relativePoint or "CENTER"
		local defOX = defPos.offsetX or 0
		local defOY = defPos.offsetY or 0
		-- [12.0.1] 앵커 대상: healthBar 사용 (powerBar 유무와 무관하게 체력바 기준 배치)
		local defAnchor = frame.healthBar or frame
		-- [12.0.1] growDirection 지원
		local growDir = defDB.growDirection or "RIGHT"
		local numPerLine = defDB.numPerLine or 4
		local colGrow = defDB.columnGrowDirection or "UP"

		for i = 1, #frame.defensiveIcons do
			local btn = frame.defensiveIcons[i]
			if btn then
				btn:SetSize(defW, defH)
				btn:ClearAllPoints()
				-- 행/열 계산
				local idx = i - 1
				local col = idx % numPerLine
				local row = math.floor(idx / numPerLine)
				-- 방향별 오프셋
				local xOff, yOff = 0, 0
				if growDir == "RIGHT" then
					xOff = col * (defW + defHSpacing)
				elseif growDir == "LEFT" then
					xOff = -(col * (defW + defHSpacing))
				elseif growDir == "DOWN" then
					yOff = -(col * (defH + defVSpacing))
				elseif growDir == "UP" then
					yOff = col * (defH + defVSpacing)
				end
				-- 열 성장 방향
				if row > 0 then
					if colGrow == "UP" then
						yOff = yOff + row * (defH + defVSpacing)
					elseif colGrow == "DOWN" then
						yOff = yOff - row * (defH + defVSpacing)
					elseif colGrow == "RIGHT" then
						xOff = xOff + row * (defW + defHSpacing)
					elseif colGrow == "LEFT" then
						xOff = xOff - row * (defW + defHSpacing)
					end
				end
				btn:SetPoint(defPoint, defAnchor, defRelPoint, defOX + xOff, defOY + yOff)
			end
		end
	end

	-- ========================================
	-- HoT 인디케이터 배치 -- [HOT-TRACKER]
	-- ========================================
	if frame.hotIndicators then
		local hotDB = widgets.hotTracker or {}
		local hotPos = hotDB.position or {}
		local hotSizeDB = hotDB.size or {}
		local hotW = hotSizeDB.width or 14
		local hotH = hotSizeDB.height or 14
		local hotSpacing = hotDB.spacing or 2
		local growDir = hotDB.growDirection or "RIGHT"

		for i = 1, #frame.hotIndicators do
			local ind = frame.hotIndicators[i]
			if ind then
				ind:SetSize(hotW, hotH)
				ind:ClearAllPoints()
				-- [HOT-TRACKER] 중앙 기준 오프셋 계산 + growDirection 분기
				local totalInd = #frame.hotIndicators
				local centerOffset = (i - 1) - (totalInd - 1) / 2
				local xOff, yOff = 0, 0
				if growDir == "RIGHT" then
					xOff = centerOffset * (hotW + hotSpacing)
				elseif growDir == "LEFT" then
					xOff = -centerOffset * (hotW + hotSpacing)
				elseif growDir == "UP" then
					yOff = centerOffset * (hotH + hotSpacing)
				elseif growDir == "DOWN" then
					yOff = -centerOffset * (hotH + hotSpacing)
				end
				ind:SetPoint(
					hotPos.point or "BOTTOM",
					frame,
					hotPos.relativePoint or "BOTTOM",
					(hotPos.offsetX or 0) + xOff,
					(hotPos.offsetY or 2) + yOff
				)
			end
		end
	end

	-- 테두리 갱신 (DandersFrames 패턴: ClearAllPoints + 재앵커)
	local borderDB = db.border or {}
	if borderDB.enabled ~= false then
		local bs = borderDB.size or 1
		local bc = borderDB.color or { 0, 0, 0, 1 }

		-- [FIX] DandersFrames 패턴: 매번 ClearAllPoints + 재앵커
		-- 다른 로직에 의한 앵커 오염 방지 → 테두리 두꺼워짐 해소
		frame.border.top:ClearAllPoints()
		frame.border.top:SetPoint("TOPLEFT", 0, 0)
		frame.border.top:SetPoint("TOPRIGHT", 0, 0)
		frame.border.top:SetHeight(bs)

		frame.border.bottom:ClearAllPoints()
		frame.border.bottom:SetPoint("BOTTOMLEFT", 0, 0)
		frame.border.bottom:SetPoint("BOTTOMRIGHT", 0, 0)
		frame.border.bottom:SetHeight(bs)

		frame.border.left:ClearAllPoints()
		frame.border.left:SetPoint("TOPLEFT", 0, 0)
		frame.border.left:SetPoint("BOTTOMLEFT", 0, 0)
		frame.border.left:SetWidth(bs)

		frame.border.right:ClearAllPoints()
		frame.border.right:SetPoint("TOPRIGHT", 0, 0)
		frame.border.right:SetPoint("BOTTOMRIGHT", 0, 0)
		frame.border.right:SetWidth(bs)

		frame.border:SetBorderColor(bc[1], bc[2], bc[3], bc[4] or 1)
		frame.border:Show()
	else
		frame.border:Hide()
	end

	-- 배경색
	local bgColor = db.background and db.background.color or { 0.08, 0.08, 0.08, 0.85 }
	frame.background:SetVertexColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.85)
end

-----------------------------------------------
-- ApplyAuraLayout — 아우라 아이콘 배치
-----------------------------------------------

function GF:ApplyAuraLayout(frame)
	if not frame then return end
	local db = self:GetFrameDB(frame)
	local widgets = db.widgets or {}

	-- spacing 값 안전 추출 (테이블 {horizontal=N, vertical=N} 또는 숫자)
	local function resolveSpacing(val, fallback)
		if type(val) == "number" then return val, val end
		if type(val) == "table" then
			return val.horizontal or val.xSpacing or val[1] or fallback,
			       val.vertical or val.ySpacing or val[2] or fallback
		end
		return fallback, fallback
	end

	-- [FIX] growDirection 기반 아이콘 배치 헬퍼
	local function LayoutIcons(icons, auraDB, defaultGrow, defaultColGrow, defaultAnchor, defaultRelAnchor, defaultOX, defaultOY)
		if not icons or #icons == 0 then return end

		local sizeDB = auraDB.size or { width = 18, height = 18 }
		local scale = auraDB.scale or 1.0 -- [12.0.1] 확대 비율
		local w = (sizeDB.width or 18) * scale
		local h = (sizeDB.height or 18) * scale
		local hSpacing, vSpacing = resolveSpacing(auraDB.spacing, 2)
		local anchorDB = auraDB.position or {}
		local anchorPoint = anchorDB.point or defaultAnchor
		local relPoint = anchorDB.relativePoint or defaultRelAnchor
		local oX = anchorDB.offsetX or defaultOX
		local oY = anchorDB.offsetY or defaultOY

		local growDir = auraDB.growDirection or defaultGrow
		local colGrowDir = auraDB.columnGrowDirection or defaultColGrow
		local numPerLine = auraDB.numPerLine or #icons
		local isVertical = (growDir == "DOWN" or growDir == "UP")

		-- 방향별 오프셋 계산 -- [FIX] 1차/2차 방향 조합 지원
		local dx, dy -- 1차 방향 오프셋
		local cdx, cdy -- 2차 방향 오프셋 (줄 바꿈)
		if isVertical then
			dx = 0
			dy = (growDir == "DOWN") and -(h + vSpacing) or (h + vSpacing)
			cdx = (colGrowDir == "LEFT") and -(w + hSpacing) or (w + hSpacing)
			cdy = 0
		else
			dx = (growDir == "LEFT") and -(w + hSpacing) or (w + hSpacing)
			dy = 0
			cdx = 0
			cdy = (colGrowDir == "DOWN") and -(h + vSpacing) or (h + vSpacing)
		end

		for i, icon in ipairs(icons) do
			icon:SetSize(w, h)
			icon:ClearAllPoints()
			if i == 1 then
				icon:SetPoint(anchorPoint, frame, relPoint, oX, oY)
			else
				local idx = i - 1 -- 0-based
				local linePos = idx % numPerLine  -- 1차 방향 인덱스
				local lineNum = math.floor(idx / numPerLine) -- 2차 방향 인덱스
				if linePos == 0 then
					-- 줄 바꿈: 첫 아이콘 기준으로 2차 방향 오프셋
					icon:SetPoint(anchorPoint, frame, relPoint, oX + cdx * lineNum, oY + cdy * lineNum)
				else
					-- 같은 줄: 이전 아이콘에 1차 방향으로 연결
					icon:SetPoint(anchorPoint, icons[i - 1], anchorPoint, dx, dy)
				end
			end
		end
	end

	-- [FIX] 아이콘 폰트+위치 업데이트 헬퍼 (DB 설정 → 아이콘 FontString 반영)
	local function UpdateIconFonts(icons, auraDB)
		if not icons or #icons == 0 then return end
		local fontDB = auraDB.font or {}
		local durFont = fontDB.duration or {}
		local stkFont = fontDB.stacks or {}
		local durSize = durFont.size or 9
		local durOutline = durFont.outline or "OUTLINE"
		local durPoint = durFont.point or "CENTER"
		local durRelPoint = durFont.relativePoint or "CENTER"
		local durOX = durFont.offsetX or 0
		local durOY = durFont.offsetY or 0
		local stkSize = stkFont.size or 10
		local stkOutline = stkFont.outline or "OUTLINE"
		local stkPoint = stkFont.point or "BOTTOMRIGHT"
		local stkRelPoint = stkFont.relativePoint or "BOTTOMRIGHT"
		local stkOX = stkFont.offsetX or 0
		local stkOY = stkFont.offsetY or 0

		for _, icon in ipairs(icons) do
			-- 네이티브 쿨다운 텍스트 (duration): 폰트 + 위치
			if icon.nativeCooldownText then
				SafeSetFont(icon.nativeCooldownText, SL_FONT, durSize, durOutline)
				icon.nativeCooldownText:ClearAllPoints()
				icon.nativeCooldownText:SetPoint(durPoint, icon, durRelPoint, durOX, durOY)
			end
			-- 커스텀 duration 텍스트: 폰트 + 위치
			if icon.duration then
				SafeSetFont(icon.duration, SL_FONT, durSize, durOutline)
				icon.duration:ClearAllPoints()
				icon.duration:SetPoint(durPoint, icon, durRelPoint, durOX, durOY)
			end
			-- 스택 텍스트: 폰트 + 위치
			if icon.count then
				SafeSetFont(icon.count, SL_FONT, stkSize, stkOutline)
				icon.count:ClearAllPoints()
				icon.count:SetPoint(stkPoint, icon, stkRelPoint, stkOX, stkOY)
			end
		end
	end

	-- 버프
	local buffsDB = widgets.buffs or {}
	LayoutIcons(frame.buffIcons, buffsDB, "RIGHT", "UP", "BOTTOMLEFT", "BOTTOMLEFT", 2, 2)
	UpdateIconFonts(frame.buffIcons, buffsDB)

	-- 디버프
	local debuffsDB = widgets.debuffs or {}
	LayoutIcons(frame.debuffIcons, debuffsDB, "LEFT", "UP", "BOTTOMRIGHT", "BOTTOMRIGHT", -2, 2)
	UpdateIconFonts(frame.debuffIcons, debuffsDB)

	-- [12.0.1] 생존기 아이콘 폰트 업데이트 (네이티브 카운트다운 + 스택)
	if frame.defensiveIcons then
		local defDB = widgets.defensives or {}
		local defFontDB = defDB.font or {}
		local durFont = defFontDB.duration or {}
		local stkFont = defFontDB.stacks or {}
		for _, btn in ipairs(frame.defensiveIcons) do
			if btn.nativeCooldownText then
				SafeSetFont(btn.nativeCooldownText, SL_FONT, durFont.size or 9, durFont.outline or "OUTLINE")
				btn.nativeCooldownText:ClearAllPoints()
				btn.nativeCooldownText:SetPoint(
					durFont.point or "CENTER", btn,
					durFont.relativePoint or "CENTER",
					durFont.offsetX or 0, durFont.offsetY or 0
				)
				if durFont.rgb then
					btn.nativeCooldownText:SetTextColor(durFont.rgb[1], durFont.rgb[2], durFont.rgb[3], 1)
				end
			end
			if btn.Count then
				SafeSetFont(btn.Count, SL_FONT, stkFont.size or 9, stkFont.outline or "OUTLINE")
				btn.Count:ClearAllPoints()
				btn.Count:SetPoint(
					stkFont.point or "BOTTOMRIGHT", btn,
					stkFont.relativePoint or "BOTTOMRIGHT",
					stkFont.offsetX or 2, stkFont.offsetY or -1
				)
			end
		end
	end
end

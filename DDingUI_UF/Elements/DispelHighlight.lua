--[[
	oUF DispelHighlight Element (Standalone Plugin)
	해제 가능한 디버프가 있을 때 프레임 보더/글로우/그라데이션/아이콘 강조

	[12.1] 댄더스 방식 리팩터:
	- C_CurveUtil.CreateColorCurve + C_UnitAuras.GetAuraDispelTypeColor 사용
	- Secret Value 완전 호환 (auraData.dispelName 직접 읽기 제거)
	- StatusBar 기반 보더/그라데이션 (secret color 네이티브 처리)
	- Bleed(11) / Enrage(9) 디스펠 타입 지원 추가

	4가지 모드:
	- border: StatusBar 기반 보더 색상 변경
	- glow: StyleLib SL 사용 (ProcGlow는 LCG 폴백, 없으면 보더 폴백)
	- gradient: 체력바 위 그라데이션 오버레이
	- icon: 디버프 타입별 아이콘 (per-type curve로 가시성 제어)

	공식 oUF API:
	- oUF:AddElement(name, update, enable, disable) 사용
	- frame:RegisterEvent(event, func, unitless) 사용
]]

local _, ns = ...
local oUF = ns.oUF

-- [STANDALONE] oUF가 없어도 핵심 Update 로직은 로드
-- oUF:AddElement는 oUF가 있을 때만 호출
local hasOUF = (oUF ~= nil)

local C_UnitAuras = C_UnitAuras
local UnitExists = UnitExists
local GetSpecialization = GetSpecialization
local issecretvalue = issecretvalue

local C = ns.Constants

-- ============================================================
-- DISPEL TYPE ENUM VALUES (WoW 12.0+ — wago.tools/db2/SpellDispelType)
-- ============================================================

local Enum_DispelType = {
	None = 0,
	Magic = 1,
	Curse = 2,
	Disease = 3,
	Poison = 4,
	Enrage = 9,
	Bleed = 11,
}

-- 모든 알려진 dispel type enum 값
local ALL_DISPEL_ENUMS = {0, 1, 2, 3, 4, 9, 11}

-- 디스펠 타입 역매핑 (enum → 이름, 폴백용)
local DISPEL_TYPE_NAMES = {
	[0] = "None",
	[1] = "Magic",
	[2] = "Curse",
	[3] = "Disease",
	[4] = "Poison",
	[9] = "Enrage",
	[11] = "Bleed",
}

-- 디스펠 타입별 기본 색상
local DEFAULT_DISPEL_COLORS = {
	Magic   = { 0.20, 0.60, 1.00 },
	Curse   = { 0.60, 0.00, 1.00 },
	Disease = { 0.60, 0.40, 0.00 },
	Poison  = { 0.00, 0.60, 0.00 },
	Enrage  = { 1.00, 0.00, 0.00 },
	Bleed   = { 1.00, 0.00, 0.00 },
}

-- 디스펠 타입별 우선순위 (높을수록 우선)
local dispelPriority = {
	Magic = 4,
	Curse = 3,
	Disease = 2,
	Poison = 1,
	Enrage = 0,
	Bleed = 0,
}

-- 디스펠 타입별 아이콘 atlas (12.0+)
local DISPEL_ICON_ATLAS = {
	Magic   = "RaidFrame-Icon-DebuffMagic",
	Curse   = "RaidFrame-Icon-DebuffCurse",
	Disease = "RaidFrame-Icon-DebuffDisease",
	Poison  = "RaidFrame-Icon-DebuffPoison",
	Bleed   = "RaidFrame-Icon-DebuffBleed",
}

-- 플레이어가 해제 가능한 디스펠 타입 캐시
local canDispel = {}

-- 직업별 해제 가능 디버프 타입 세트
local classDispelTypes = {
	PRIEST = {
		[1] = { Magic = true, Disease = true }, -- Holy
		[2] = { Magic = true, Disease = true }, -- Disc
		[3] = { Disease = true },               -- Shadow
	},
	PALADIN = {
		[1] = { Magic = true, Poison = true, Disease = true }, -- Holy
		[2] = { Poison = true, Disease = true }, -- Prot
		[3] = { Poison = true, Disease = true }, -- Ret
	},
	SHAMAN = {
		[1] = { Curse = true },                 -- Elemental
		[2] = { Curse = true },                 -- Enhancement
		[3] = { Magic = true, Curse = true },   -- Resto
	},
	DRUID = {
		[1] = { Curse = true, Poison = true },  -- Balance
		[2] = { Curse = true, Poison = true },  -- Feral
		[3] = { Curse = true, Poison = true },  -- Guardian
		[4] = { Magic = true, Curse = true, Poison = true }, -- Resto
	},
	MONK = {
		[1] = { Poison = true, Disease = true }, -- BM
		[2] = { Magic = true, Poison = true, Disease = true }, -- MW
		[3] = { Poison = true, Disease = true }, -- WW
	},
	MAGE = {
		[0] = { Curse = true },
	},
	EVOKER = {
		[1] = { Poison = true },                -- Devastation
		[2] = { Magic = true, Poison = true },  -- Preservation
		[3] = { Poison = true },                -- Augmentation
	},
}

local function UpdateCanDispel()
	wipe(canDispel)

	local _, class = UnitClass("player")
	local spec = GetSpecialization and GetSpecialization() or 0

	local classData = classDispelTypes[class]
	if not classData then return end

	local specData = classData[spec] or classData[0]
	if not specData then return end

	for dtype in pairs(specData) do
		canDispel[dtype] = true
	end
end

-- ============================================================
-- COLOR CURVE SYSTEM (댄더스 방식)
-- ============================================================

local borderCurve = nil
local perTypeCurves = {} -- per-type curve 캐시 (아이콘 가시성용)
local bleedEnrageCurve = nil -- [FIX] Bleed/Enrage 전용 커브 캐시

-- 커브 캐시 무효화 (색상 설정 변경 시)
local function InvalidateCurves()
	borderCurve = nil
	wipe(perTypeCurves)
	bleedEnrageCurve = nil
end

-- border/gradient용 통합 커브 생성
-- 모든 dispel type에 대해 해당 색상+alpha 매핑
local function BuildDispelCurve(colors, alpha)
	if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then
		return nil
	end

	local curve = C_CurveUtil.CreateColorCurve()
	curve:SetType(Enum.LuaCurveType.Step)

	-- None (0) = 투명 (디스펠 대상 아님)
	curve:AddPoint(0, CreateColor(0, 0, 0, 0))

	-- 각 dispel type에 색상+alpha 매핑
	for _, enumVal in ipairs(ALL_DISPEL_ENUMS) do
		if enumVal ~= 0 then
			local typeName = DISPEL_TYPE_NAMES[enumVal]
			local c = typeName and colors[typeName]
			if c then
				curve:AddPoint(enumVal, CreateColor(c[1], c[2], c[3], alpha))
			end
		end
	end

	return curve
end

-- [FIX] Bleed(11)/Enrage(9) 전용 커브 (DandersFrames GetBleedIconCurve 패턴)
-- dispelType을 직접 읽지 않고 ColorCurve API로 출혈/격노 검출
local function GetBleedEnrageCurve()
	if bleedEnrageCurve then return bleedEnrageCurve end
	if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then return nil end

	local curve = C_CurveUtil.CreateColorCurve()
	curve:SetType(Enum.LuaCurveType.Step)

	for _, enumVal in ipairs(ALL_DISPEL_ENUMS) do
		if enumVal == 9 or enumVal == 11 then -- Enrage or Bleed
			curve:AddPoint(enumVal, CreateColor(1, 1, 1, 1))
			curve:AddPoint(enumVal + 0.5, CreateColor(1, 1, 1, 0)) -- Step 누출 방지
		else
			curve:AddPoint(enumVal, CreateColor(1, 1, 1, 0))
		end
	end

	bleedEnrageCurve = curve
	return curve
end

-- per-type 아이콘 커브: 특정 타입만 alpha=1, 나머지 alpha=0
local function GetPerTypeCurve(targetEnum)
	if perTypeCurves[targetEnum] then
		return perTypeCurves[targetEnum]
	end

	if not C_CurveUtil or not C_CurveUtil.CreateColorCurve then
		return nil
	end

	local curve = C_CurveUtil.CreateColorCurve()
	curve:SetType(Enum.LuaCurveType.Step)

	for _, enumVal in ipairs(ALL_DISPEL_ENUMS) do
		if enumVal == targetEnum then
			curve:AddPoint(enumVal, CreateColor(1, 1, 1, 1)) -- 보임
			curve:AddPoint(enumVal + 0.5, CreateColor(1, 1, 1, 0)) -- [FIX] 이후 값(알 수 없는 enum)이 1로 평가되는 출혈 버그 방지
		else
			curve:AddPoint(enumVal, CreateColor(1, 1, 1, 0)) -- 안 보임
		end
	end

	perTypeCurves[targetEnum] = curve
	return curve
end

-- ============================================================
-- VISUAL MODES
-- ============================================================

-- border 모드: oUF 보더 색상 변경 (기존 호환)
local function ApplyDispelBorder_Direct(element, r, g, b)
	if element.SetBackdropBorderColor then
		element:SetBackdropBorderColor(r, g, b, 1)
		element:Show()
	end
end

-- glow 모드: StyleLib 사용 (ProcGlow는 LCG 폴백)
local function ApplyDispelGlow(element, r, g, b)
	local SL = _G.DDingUI_StyleLib
	local glowType = element._glowType or "pixel"
	if glowType == "pixel" then
		if SL then
			SL.ShowPixelGlow(element.__owner, {r, g, b, 1}, nil, nil, nil, element._glowThickness or 2)
		end
	elseif glowType == "shine" then
		if SL then
			SL.ShowAutocastGlow(element.__owner, {r, g, b, 1})
		end
	elseif glowType == "proc" then
		-- ProcGlow는 SL에 미구현, LCG 직접 사용
		local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
		if LCG then
			LCG.ProcGlow_Start(element.__owner, {color = {r, g, b, 1}})
		end
	end
	-- glow 실패 시 폴백: 두꺼운 보더
	if not SL and glowType ~= "proc" then
		if element.SetBackdropBorderColor then
			element:SetBackdropBorderColor(r, g, b, 1)
			element:Show()
		end
	end
end

-- gradient 모드: 체력바 위 그라데이션
-- [FIX] SetGradient + CreateColor는 secret value에서 에러 → SetVertexColor로 대체
local function ApplyDispelGradient(element, r, g, b)
	if not element._gradient then
		element._gradient = element.__owner.Health:CreateTexture(nil, "OVERLAY", nil, 2)
		element._gradient:SetAllPoints(element.__owner.Health)
	end
	element._gradient:SetTexture(C.FLAT_TEXTURE)
	element._gradient:SetVertexColor(r, g, b, 1)
	element._gradient:SetAlpha(element._gradientAlpha or 0.4)
	element._gradient:Show()
	element:Hide()
end

-- icon 모드: 디버프 타입별 독립 아이콘 스택 (Danders 방식)
-- 5개의 아이콘에 각 타입별 커브를 바인딩하여 안전하게 필터링
local function ApplyDispelIcon(element, unit, auraInstanceID)
	if not element._icons then
		element._icons = {}
		local function CreateTypeIcon(atlas)
			local tex = element.__owner:CreateTexture(nil, "OVERLAY", nil, 3)
			tex:SetSize(element._iconSize or 14, element._iconSize or 14)
			tex:SetPoint(element._iconPosition or "TOPRIGHT", element.__owner, element._iconPosition or "TOPRIGHT", -2, -2)
			tex:SetAtlas(atlas)
			tex:Hide()
			return tex
		end
		element._icons.Magic   = CreateTypeIcon(DISPEL_ICON_ATLAS["Magic"])
		element._icons.Curse   = CreateTypeIcon(DISPEL_ICON_ATLAS["Curse"])
		element._icons.Disease = CreateTypeIcon(DISPEL_ICON_ATLAS["Disease"])
		element._icons.Poison  = CreateTypeIcon(DISPEL_ICON_ATLAS["Poison"])
		element._icons.Bleed   = CreateTypeIcon("Spell_Holy_DispelMagic") -- Bleed/Enrage fallback atlas or custom
		if DISPEL_ICON_ATLAS["Bleed"] then element._icons.Bleed:SetAtlas(DISPEL_ICON_ATLAS["Bleed"]) end
	end

	-- ColorCurve API가 있는 경우 개별 커브로 색상 적용
	if C_CurveUtil and C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor then
		local function SetupIcon(iconTex, curveID)
			local iconColor = C_UnitAuras.GetAuraDispelTypeColor(unit, auraInstanceID, GetPerTypeCurve(curveID))
			if iconColor then
				-- secret color 객체를 바로 전달
				local r, g, b, a = iconColor:GetRGBA()
				iconTex:SetVertexColor(r, g, b, a)
				iconTex:Show()
			end
		end
		SetupIcon(element._icons.Magic,   1) -- Magic
		SetupIcon(element._icons.Curse,   2) -- Curse
		SetupIcon(element._icons.Disease, 3) -- Disease
		SetupIcon(element._icons.Poison,  4) -- Poison
		
		-- Bleed/Enrage는 수동 검출 루틴에서 별도로 켜주므로 일단 숨김
		element._icons.Bleed:Hide()
	end
	element:Hide()
end

-- 단독 디스펠 아이콘을 직접 RGB 기반으로 켜기 (Bleed/Enrage 등 수동)
local function ApplyDispelIconRGB(element, atlas, r, g, b)
	if not element._icons then ApplyDispelIcon(element, "player", 0) end
	-- 모두 숨김
	for _, icon in pairs(element._icons) do icon:Hide() end
	
	element._icons.Bleed:SetVertexColor(r, g, b, 1.0)
	if atlas then element._icons.Bleed:SetAtlas(atlas) end
	element._icons.Bleed:Show()
	element:Hide()
end

-- 모든 시각 효과 정리
local function ClearDispelVisual(element)
	element:Hide()
	-- 글로우 정리 (SL 우선, ProcGlow는 LCG)
	local SL = _G.DDingUI_StyleLib
	if SL and element.__owner then
		SL.HideAllGlows(element.__owner)
	end
	-- ProcGlow는 SL.HideAllGlows에서 처리 안 될 수 있으므로 LCG도 정리
	local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
	if LCG and element.__owner then
		pcall(LCG.ProcGlow_Stop, element.__owner)
	end
	-- 그라데이션 정리
	if element._gradient then element._gradient:Hide() end
	-- 아이콘 정리
	if element._icon then element._icon:Hide() end
end

-- ============================================================
-- CORE UPDATE (댄더스 방식: ColorCurve 기반)
-- ============================================================

local function Update(self, event, unit)
	if unit and unit ~= self.unit then return end
	unit = unit or self.unit
	if not unit or not UnitExists(unit) then return end

	local element = self.DispelHighlight
	if not element then return end

	if element.PreUpdate then
		element:PreUpdate(unit)
	end

	-- 미리보기 모드인 경우
	if element._preview then
		local pt = element._previewType or "Magic"
		local customColors = element._colors
		local color = (customColors and customColors[pt]) or DEFAULT_DISPEL_COLORS[pt]
		if color then
			ClearDispelVisual(element)
			local mode = element._mode or "border"
			local r, g, b = color[1], color[2], color[3]
			if mode == "border" then ApplyDispelBorder_Direct(element, r, g, b)
			elseif mode == "glow" then ApplyDispelGlow(element, r, g, b)
			elseif mode == "gradient" then ApplyDispelGradient(element, r, g, b)
			elseif mode == "icon" then ApplyDispelIconRGB(element, DISPEL_ICON_ATLAS[pt], r, g, b) end
		end
		if element.PostUpdate then element:PostUpdate(unit) end
		return
	end

	-- ============================================================
	-- 댄더스 패턴 (DandersFrames Pattern) 완전 적용
	-- 1. 블리자드 캐시(playerDispellable) 활용 가능 시 첫 번째 해제 디버프 픽
	-- 2. 발견 시 C_UnitAuras.GetAuraDispelTypeColor로 Color 발급 후 (alpha 검사 없이) 시각 효과에 직접 투입
	-- 3. 미발견 시 1~40 순회하여 출혈(11) / 격노(9)를 수동 검사 (수동으로 색상 삽입)
	-- 4. Color의 Alpha 값을 Lua에서 평가하지 않고 즉시 적용하여 테인트 원천 차단
	-- ============================================================

	local hasColorCurveAPI = C_CurveUtil and C_CurveUtil.CreateColorCurve and C_UnitAuras and C_UnitAuras.GetAuraDispelTypeColor
	
	-- Fast Path: BlizzardAuraCache (ns.AuraCache)
	local dispellableAuraID = nil
	if ns.AuraCache then
		local cache = ns.AuraCache:GetAllPlayerDispellable(unit)
		if cache then
			dispellableAuraID = next(cache) -- 첫 번째 해제 가능한 디버프
		end
	end

	local dc = element._colors or DEFAULT_DISPEL_COLORS

	if dispellableAuraID and hasColorCurveAPI then
		-- 정식 해제 가능한 디버프가 있을 때 (Magic/Curse/Disease/Poison)
		ClearDispelVisual(element)

		-- 통합 border curve 생성
		if not borderCurve then borderCurve = BuildDispelCurve(dc, 1.0) end
		
		local mode = element._mode or "border"
		
		if mode == "border" then
			local curveColor = C_UnitAuras.GetAuraDispelTypeColor(unit, dispellableAuraID, borderCurve)
			if curveColor and element.SetBackdropBorderColor then
				-- C++ 함수로 직접 언래핑 (a 값 파악 불필요, 테인트 방지)
				element:SetBackdropBorderColor(curveColor:GetRGBA())
				element:Show()
			end
		elseif mode == "gradient" then
			local curveColor = C_UnitAuras.GetAuraDispelTypeColor(unit, dispellableAuraID, borderCurve)
			if curveColor then
				if not element._gradient then
					element._gradient = element.__owner.Health:CreateTexture(nil, "OVERLAY", nil, 2)
					element._gradient:SetAllPoints(element.__owner.Health)
				end
				element._gradient:SetTexture(C.FLAT_TEXTURE)
				-- [FIX] secret RGBA → SetVertexColor (C++ 함수) + SetAlpha
				element._gradient:SetVertexColor(curveColor:GetRGBA())
				element._gradient:SetAlpha(element._gradientAlpha or 0.4)
				element._gradient:Show()
				element:Hide()
			end
		elseif mode == "glow" then
			-- glow 모드는 Lua 함수라 API 한계상 color 추출이 필요함, 하지만 forceinsecure 없이
			-- fallback 처리 하거나 insecure 강제를 최소화 (여기선 fallback)
			if element.SetBackdropBorderColor then
				local curveColor = C_UnitAuras.GetAuraDispelTypeColor(unit, dispellableAuraID, borderCurve)
				if curveColor then
					element:SetBackdropBorderColor(curveColor:GetRGBA())
					element:Show()
				end
			end
		elseif mode == "icon" then
			ApplyDispelIcon(element, unit, dispellableAuraID)
		end
		
		if element.PostUpdate then element:PostUpdate(unit) end
		return
	end

	-- Slow Path: 출혈 / 격노 검출 불가 (WoW 11.0 Secret Value 제한)
	-- 블리자드 기본 API(C_UnitAuras.GetAuraDispelTypeColor)에서 alpha 값을 Lua로 검출할 수 없고,
	-- auraData.dispelName 역시 Secret String이라 Lua에서 `== "Bleed"` 비교 시 테인트가 발생함.
	-- 따라서 플레이어 디스펠 불가(Fast Path 미해당)인 출혈/격노를 강제로 하이라이트하는 편법 제거.
	ClearDispelVisual(element)

	if element.PostUpdate then
		element:PostUpdate(unit)
	end
end

local function Path(self, ...)
	return (self.DispelHighlight and self.DispelHighlight.Override or Update)(self, ...)
end

local function ForceUpdate(element)
	return Path(element.__owner, "ForceUpdate", element.__owner.unit)
end

-- 전문화 변경 시 디스펠 타입 재계산 (unitless event)
local function OnSpecChanged(self, event)
	UpdateCanDispel()
	InvalidateCurves() -- 커브 캐시도 무효화
	Path(self, event, self.unit)
end

-----------------------------------------------
-- Preview API
-----------------------------------------------

local function SetPreview(element, dispelType)
	element._preview = (dispelType ~= nil)
	element._previewType = dispelType
	ForceUpdate(element)
end

local function ClearPreview(element)
	element._preview = false
	element._previewType = nil
	ForceUpdate(element)
end

-----------------------------------------------
-- Enable / Disable
-----------------------------------------------

local function Enable(self, unit)
	local element = self.DispelHighlight
	if not element then return end

	element.__owner = self
	element.ForceUpdate = ForceUpdate
	element.SetPreview = SetPreview
	element.ClearPreview = ClearPreview

	-- 디스펠 가능 타입 초기 계산
	UpdateCanDispel()

	-- UNIT_AURA: 유닛별 이벤트
	self:RegisterEvent("UNIT_AURA", Path)

	-- PLAYER_SPECIALIZATION_CHANGED: unitless 이벤트
	self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", OnSpecChanged, true)

	return true
end

local function Disable(self)
	local element = self.DispelHighlight
	if not element then return end

	ClearDispelVisual(element)
	self:UnregisterEvent("UNIT_AURA", Path)
	self:UnregisterEvent("PLAYER_SPECIALIZATION_CHANGED", OnSpecChanged)
end

-- 공식 oUF API: AddElement(name, update, enable, disable)
if hasOUF then
	oUF:AddElement("DispelHighlight", Update, Enable, Disable)
end

-- [STANDALONE] standalone ElementDrivers에서 사용할 수 있도록 노출
ns.DispelHighlightUpdate = function(frame)
	if frame and frame.DispelHighlight then
		Update(frame, "UNIT_AURA", frame.unit)
	end
end

--[[
	ddingUI UnitFrames
	Widgets/Glow.lua - Frame glow effects (4 types)
	[12.0.1] Cell/DandersFrames 수준 글로우 시스템

	지원 타입:
	- pixel:  점선 테두리 깜박임 (LibCustomGlow PixelGlow 스타일)
	- shine:  중앙 확산 빛 + 회전
	- proc:   외곽 두꺼운 펄스 (SpellActivation 스타일)
	- normal: 소프트 테두리 알파 펄스

	API:
	- ns.Glow:Start(frame, glowType, color, opts)
	- ns.Glow:Stop(frame)
	- ns.Glow:SetColor(frame, color)
]]

local _, ns = ...

local Glow = {}
ns.Glow = Glow

-----------------------------------------------
-- Upvalues
-----------------------------------------------

local CreateFrame = CreateFrame
local math_max = math.max
local math_pi = math.pi

-- [12.0.1] Constants는 Core/Constants.lua에서 로드 (TOC 순서상 Widgets가 먼저)
-- 지연 참조로 nil 방지
local FLAT_TEXTURE = [[Interface\Buttons\WHITE8x8]]

-----------------------------------------------
-- Glow Frame Pool
-----------------------------------------------

local glowPool = {}

local function AcquireGlowFrame(parent)
	local glow = tremove(glowPool)
	if not glow then
		glow = CreateFrame("Frame", nil, parent)
	else
		glow:SetParent(parent)
	end
	glow:ClearAllPoints()
	glow:Show()
	return glow
end

local function ReleaseGlowFrame(glow)
	if not glow then return end
	glow:Hide()
	glow:ClearAllPoints()
	glow:SetParent(nil)
	-- 애니메이션 정지 (AnimationGroup fallback)
	if glow._ag then glow._ag:Stop() end
	-- [REFACTOR] OnUpdate 기반 애니메이션 정리
	glow:SetScript("OnUpdate", nil)
	glow:SetScript("OnSizeChanged", nil)
	glow:SetAlpha(1)
	-- 텍스처 숨기기
	for _, tex in ipairs(glow._textures or {}) do
		tex:Hide()
	end
	tinsert(glowPool, glow)
end

-----------------------------------------------
-- Pixel Glow
-- 프레임 테두리에 N개의 짧은 세그먼트 + Alpha 깜박임
-----------------------------------------------

local function CreatePixelGlow(frame, color, opts)
	local lines = (opts and opts.lines) or 9
	local frequency = (opts and opts.frequency) or 0.25
	local length = (opts and opts.length) or 8
	local thickness = (opts and opts.thickness) or 2
	local r, g, b, a = color[1], color[2], color[3], color[4] or 1

	local glow = AcquireGlowFrame(frame)
	glow:SetAllPoints()
	glow:SetFrameLevel(frame:GetFrameLevel() + 3)
	glow._textures = {}

	-- 프레임 둘레 = 2*(W+H), 세그먼트를 균등 배분
	-- 각 세그먼트는 OnUpdate로 위치를 갱신 (프레임 리사이즈 대응)
	local function CreateSegment(i)
		local tex = glow:CreateTexture(nil, "OVERLAY")
		tex:SetTexture(FLAT_TEXTURE)
		tex:SetVertexColor(r, g, b, a)
		tinsert(glow._textures, tex)
		return tex
	end

	local segments = {}
	for i = 1, lines do
		segments[i] = CreateSegment(i)
	end

	-- 위치 계산 함수
	local function LayoutSegments()
		local w, h = glow:GetSize()
		if w <= 0 or h <= 0 then return end

		local perimeter = 2 * (w + h)
		local gap = perimeter / lines

		for i = 1, lines do
			local offset = ((i - 1) * gap) % perimeter
			local tex = segments[i]

			if offset < w then
				-- 상단 변 (왼→오)
				tex:ClearAllPoints()
				tex:SetSize(math.min(length, w - offset), thickness)
				tex:SetPoint("TOPLEFT", glow, "TOPLEFT", offset, 0)
			elseif offset < w + h then
				-- 우측 변 (위→아래)
				local dy = offset - w
				tex:ClearAllPoints()
				tex:SetSize(thickness, math.min(length, h - dy))
				tex:SetPoint("TOPRIGHT", glow, "TOPRIGHT", 0, -dy)
			elseif offset < 2 * w + h then
				-- 하단 변 (오→왼)
				local dx = offset - w - h
				tex:ClearAllPoints()
				tex:SetSize(math.min(length, w - dx), thickness)
				tex:SetPoint("BOTTOMRIGHT", glow, "BOTTOMRIGHT", -dx, 0)
			else
				-- 좌측 변 (아래→위)
				local dy = offset - 2 * w - h
				tex:ClearAllPoints()
				tex:SetSize(thickness, math.min(length, h - dy))
				tex:SetPoint("BOTTOMLEFT", glow, "BOTTOMLEFT", 0, dy)
			end
		end
	end

	LayoutSegments()
	glow:SetScript("OnSizeChanged", LayoutSegments)

	-- [REFACTOR] Alpha 펄스: AnimationGroup → OnUpdate + math.sin (Taint 방지 + 30fps 측)
	local _accum, _timer = 0, 0
	local speed = 1 / frequency -- frequency는 반주기(초)
	glow:SetScript("OnUpdate", function(self, elapsed)
		_accum = _accum + elapsed
		if _accum < 0.033 then return end  -- 30fps
		_timer = _timer + _accum * speed * 6.2832  -- 2π * speed
		_accum = 0
		if _timer > 6.2832 then _timer = _timer - 6.2832 end
		self:SetAlpha(0.2 + 0.8 * (0.5 + 0.5 * math.sin(_timer)))
	end)

	return glow
end

-----------------------------------------------
-- Shine Glow
-- 중앙에서 확산하는 십자형 빛 + 회전
-----------------------------------------------

local function CreateShineGlow(frame, color, opts)
	local frequency = (opts and opts.frequency) or 0.5
	local r, g, b, a = color[1], color[2], color[3], color[4] or 0.6

	local glow = AcquireGlowFrame(frame)
	glow:SetAllPoints()
	glow:SetFrameLevel(frame:GetFrameLevel() + 3)
	glow._textures = {}

	-- 4방향 빛살 (십자)
	local beamSize = math_max(frame:GetWidth(), frame:GetHeight()) * 0.4
	for i = 1, 4 do
		local beam = glow:CreateTexture(nil, "OVERLAY")
		beam:SetTexture(FLAT_TEXTURE)
		beam:SetVertexColor(r, g, b, a)
		beam:SetBlendMode("ADD")
		beam:SetSize(2, beamSize)
		beam:SetPoint("CENTER")
		-- 회전은 OnUpdate로 처리
		tinsert(glow._textures, beam)
	end

	-- 중앙 광점
	local center = glow:CreateTexture(nil, "OVERLAY")
	center:SetTexture(FLAT_TEXTURE)
	center:SetVertexColor(r, g, b, a * 0.5)
	center:SetBlendMode("ADD")
	center:SetSize(6, 6)
	center:SetPoint("CENTER")
	tinsert(glow._textures, center)

	-- [REFACTOR] 스케일+회전+알파 모두 OnUpdate에서 처리 (AnimationGroup 제거)

	-- [REFACTOR] 회전 + 펄스: AnimationGroup → OnUpdate + 30fps 측
	local _accum, _elapsed = 0, 0
	glow:SetScript("OnUpdate", function(self, dt)
		_accum = _accum + dt
		if _accum < 0.033 then return end  -- 30fps
		_elapsed = _elapsed + _accum
		_accum = 0
		local angle = _elapsed * math_pi * 0.5 -- 느린 회전
		for i, beam in ipairs(glow._textures) do
			if i <= 4 then
				local rot = angle + (i - 1) * math_pi * 0.25
				-- WoW 텍스처는 직접 회전 불가 → TexCoord 조작으로 회전 효과
				-- 간단 구현: 위치 오프셋으로 회전 시뮬레이션
				local ox = math.sin(rot) * 2
				local oy = math.cos(rot) * 2
				beam:ClearAllPoints()
				beam:SetPoint("CENTER", ox, oy)
			end
		end
		-- Alpha 펄스
		local alphaT = _elapsed * (1 / frequency) * 6.2832
		self:SetAlpha(0.3 + 0.7 * (0.5 + 0.5 * math.sin(alphaT)))
	end)

	return glow
end

-----------------------------------------------
-- Proc Glow
-- SpellActivation 스타일 외곽 두꺼운 펄스
-----------------------------------------------

local function CreateProcGlow(frame, color, opts)
	local frequency = (opts and opts.frequency) or 0.5
	local thickness = (opts and opts.thickness) or 4
	local r, g, b, a = color[1], color[2], color[3], color[4] or 0.8

	local glow = AcquireGlowFrame(frame)
	glow:SetPoint("TOPLEFT", -thickness, thickness)
	glow:SetPoint("BOTTOMRIGHT", thickness, -thickness)
	glow:SetFrameLevel(math_max(0, frame:GetFrameLevel() + 2))
	glow._textures = {}

	-- 두꺼운 외곽 보더 (4면)
	local edges = {
		{ "TOPLEFT", "TOPRIGHT", 0, 0, nil, thickness },          -- top
		{ "BOTTOMLEFT", "BOTTOMRIGHT", 0, 0, nil, thickness },    -- bottom
		{ "TOPLEFT", "BOTTOMLEFT", 0, 0, thickness, nil },        -- left
		{ "TOPRIGHT", "BOTTOMRIGHT", 0, 0, thickness, nil },      -- right
	}

	for i, e in ipairs(edges) do
		local tex = glow:CreateTexture(nil, "OVERLAY")
		tex:SetTexture(FLAT_TEXTURE)
		tex:SetVertexColor(r, g, b, a)
		tex:SetBlendMode("ADD")

		if i == 1 then -- top
			tex:SetPoint("TOPLEFT")
			tex:SetPoint("TOPRIGHT")
			tex:SetHeight(thickness)
		elseif i == 2 then -- bottom
			tex:SetPoint("BOTTOMLEFT")
			tex:SetPoint("BOTTOMRIGHT")
			tex:SetHeight(thickness)
		elseif i == 3 then -- left
			tex:SetPoint("TOPLEFT")
			tex:SetPoint("BOTTOMLEFT")
			tex:SetWidth(thickness)
		elseif i == 4 then -- right
			tex:SetPoint("TOPRIGHT")
			tex:SetPoint("BOTTOMRIGHT")
			tex:SetWidth(thickness)
		end

		tinsert(glow._textures, tex)
	end

	-- [REFACTOR] Alpha 펄스: AnimationGroup → OnUpdate + math.sin (Taint 방지 + 30fps 측)
	local _accum, _timer = 0, 0
	local speed = 1 / frequency
	glow:SetScript("OnUpdate", function(self, elapsed)
		_accum = _accum + elapsed
		if _accum < 0.033 then return end  -- 30fps
		_timer = _timer + _accum * speed * 6.2832
		_accum = 0
		if _timer > 6.2832 then _timer = _timer - 6.2832 end
		self:SetAlpha(0.1 + 0.9 * (0.5 + 0.5 * math.sin(_timer)))
	end)

	return glow
end

-----------------------------------------------
-- Normal (Button) Glow
-- 소프트 테두리 알파 펄스 (가장 단순)
-----------------------------------------------

local function CreateNormalGlow(frame, color, opts)
	local frequency = (opts and opts.frequency) or 0.8
	local thickness = (opts and opts.thickness) or 3
	local r, g, b, a = color[1], color[2], color[3], color[4] or 0.5

	local glow = AcquireGlowFrame(frame)
	glow:SetPoint("TOPLEFT", -thickness, thickness)
	glow:SetPoint("BOTTOMRIGHT", thickness, -thickness)
	glow:SetFrameLevel(math_max(0, frame:GetFrameLevel() + 2))
	glow._textures = {}

	-- 단일 배경 텍스처 (소프트 글로우)
	local bg = glow:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetTexture(FLAT_TEXTURE)
	bg:SetVertexColor(r, g, b, a * 0.3)
	bg:SetBlendMode("ADD")
	tinsert(glow._textures, bg)

	-- 보더 텍스처 (4면)
	for i = 1, 4 do
		local tex = glow:CreateTexture(nil, "OVERLAY")
		tex:SetTexture(FLAT_TEXTURE)
		tex:SetVertexColor(r, g, b, a)
		tex:SetBlendMode("ADD")

		if i == 1 then
			tex:SetPoint("TOPLEFT")
			tex:SetPoint("TOPRIGHT")
			tex:SetHeight(thickness)
		elseif i == 2 then
			tex:SetPoint("BOTTOMLEFT")
			tex:SetPoint("BOTTOMRIGHT")
			tex:SetHeight(thickness)
		elseif i == 3 then
			tex:SetPoint("TOPLEFT")
			tex:SetPoint("BOTTOMLEFT")
			tex:SetWidth(thickness)
		elseif i == 4 then
			tex:SetPoint("TOPRIGHT")
			tex:SetPoint("BOTTOMRIGHT")
			tex:SetWidth(thickness)
		end

		tinsert(glow._textures, tex)
	end

	-- [REFACTOR] Alpha 펄스: AnimationGroup → OnUpdate + math.sin (Taint 방지 + 30fps 측)
	local _accum, _timer = 0, 0
	local speed = 1 / frequency
	glow:SetScript("OnUpdate", function(self, elapsed)
		_accum = _accum + elapsed
		if _accum < 0.033 then return end  -- 30fps
		_timer = _timer + _accum * speed * 6.2832
		_accum = 0
		if _timer > 6.2832 then _timer = _timer - 6.2832 end
		self:SetAlpha(0.4 + 0.6 * (0.5 + 0.5 * math.sin(_timer)))
	end)

	return glow
end

-----------------------------------------------
-- Public API
-----------------------------------------------

-- 글로우 타입 디스패치 테이블
local glowCreators = {
	pixel  = CreatePixelGlow,
	shine  = CreateShineGlow,
	proc   = CreateProcGlow,
	normal = CreateNormalGlow,
}

-- [ELLESMERE] StyleLib ProceduralGlow 브릿지
local SL_PG = DDingUI_StyleLib and DDingUI_StyleLib.ProceduralGlow or nil

--- 프레임에 글로우 효과 시작
-- @param frame   대상 프레임
-- @param glowType "pixel"|"shine"|"proc"|"normal"|"ants"|"shape"
-- @param color   {r, g, b[, a]}
-- @param opts    { lines, frequency, length, thickness } (타입별 옵션)
function Glow:Start(frame, glowType, color, opts)
	if not frame then return end

	-- 기존 글로우 제거
	self:Stop(frame)

	color = color or { 1, 1, 1, 1 }

	-- [ELLESMERE] ProceduralGlow 타입 처리
	if SL_PG and (glowType == "ants" or glowType == "shape") then
		SL_PG.StartGlow(frame, glowType, color[1], color[2], color[3], opts)
		frame._ddingGlowType = glowType
		frame._ddingGlowPG = true  -- ProceduralGlow 플래그
		return
	end

	local creator = glowCreators[glowType]
	if not creator then
		creator = glowCreators.normal -- fallback
	end

	frame._ddingGlow = creator(frame, color, opts)
	frame._ddingGlowType = glowType
end

--- 프레임의 글로우 효과 중지
function Glow:Stop(frame)
	if not frame then return end

	-- [ELLESMERE] ProceduralGlow 정리
	if frame._ddingGlowPG and SL_PG then
		SL_PG.StopGlow(frame)
		frame._ddingGlowPG = nil
		frame._ddingGlowType = nil
		return
	end

	if not frame._ddingGlow then return end
	ReleaseGlowFrame(frame._ddingGlow)
	frame._ddingGlow = nil
	frame._ddingGlowType = nil
end

--- 글로우 색상 업데이트 (재생성 없이)
function Glow:SetColor(frame, color)
	if not frame then return end
	-- [ELLESMERE] PG 글로우는 재생성 필요
	if frame._ddingGlowPG then
		local glowType = frame._ddingGlowType
		self:Stop(frame)
		self:Start(frame, glowType, color)
		return
	end
	if not frame._ddingGlow then return end
	local glow = frame._ddingGlow
	local r, g, b, a = color[1], color[2], color[3], color[4] or 1
	for _, tex in ipairs(glow._textures or {}) do
		tex:SetVertexColor(r, g, b, a)
	end
end

--- 글로우 활성 여부
function Glow:IsActive(frame)
	return frame and (frame._ddingGlow ~= nil or frame._ddingGlowPG ~= nil)
end

-- [ELLESMERE] Taint-free fade 유틸리티 노출
function Glow:Fade(frame, fromAlpha, toAlpha, duration, opts)
	if SL_PG then
		SL_PG.Fade(frame, fromAlpha, toAlpha, duration, opts)
	else
		-- Fallback: 즉시 설정
		frame:SetAlpha(toAlpha)
	end
end


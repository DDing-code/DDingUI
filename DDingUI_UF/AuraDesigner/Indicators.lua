--[[
	ddingUI UnitFrames
	AuraDesigner/Indicators.lua — Visual indicator renderers
	
	DandersFrames Indicators.lua 패턴 기반.
	Begin/Apply/End 라이프사이클로 프레임당 인디케이터를 관리합니다.
	
	Placed (icon/square/bar): 프레임 위에 자유 배치
	Frame-level (border/healthbar/nametext/healthtext/framealpha): 프레임 속성 변경
]]

local _, ns = ...

local pairs, ipairs, wipe, type = pairs, ipairs, wipe, type
local math_floor = math.floor
local math_abs = math.abs
local math_sin = math.sin
local format = string.format
local CreateFrame = CreateFrame
local GetTime = GetTime

local C_UnitAuras = C_UnitAuras
local UnitExists = UnitExists
local issecretvalue = issecretvalue or function() return false end

-- ============================================================
-- EXPIRING AURA CONSTANTS
-- ============================================================
local EXPIRING_THRESHOLD_PCT = 0.30  -- 30% remaining = expiring
local EXPIRING_THRESHOLD_SEC = 5     -- or 5 seconds remaining
local EXPIRING_PULSE_SPEED = 4       -- pulse frequency (Hz)
local EXPIRING_BORDER_COLOR = { r = 1, g = 0.2, b = 0.2 }
local EXPIRING_MIN_ALPHA = 0.4
local EXPIRING_MAX_ALPHA = 1.0

ns.AuraDesigner = ns.AuraDesigner or {}
local Indicators = {}
ns.AuraDesigner.Indicators = Indicators

-- ============================================================
-- DURATION FORMATTING (must be before OnUpdate handlers)
-- ============================================================

local function FormatDuration(remaining)
	if not remaining or remaining <= 0 then return "" end
	if remaining >= 60 then
		return format("%dm", math_floor(remaining / 60))
	elseif remaining >= 10 then
		return format("%d", math_floor(remaining))
	else
		return format("%.1f", remaining)
	end
end

-- ============================================================
-- OBJECT POOLS
-- ============================================================

local iconPool = {}
local squarePool = {}
local barPool = {}

local function AcquireFromPool(pool, createFn, parent)
	for i = #pool, 1, -1 do
		local obj = pool[i]
		pool[i] = nil
		obj:SetParent(parent)
		obj:ClearAllPoints()
		return obj
	end
	return createFn(parent)
end

local function ReleaseToPool(pool, obj)
	if not obj then return end
	obj:Hide()
	obj:ClearAllPoints()
	pool[#pool + 1] = obj
end

-- ============================================================
-- FRAME STATE
-- ============================================================

local function EnsureADState(frame)
	if not frame._adIndicators then
		frame._adIndicators = {
			icons = {},    -- active icon frames
			squares = {},  -- active square frames
			bars = {},     -- active bar frames
			borderApplied = false,
			healthbarApplied = false,
			nametextApplied = false,
			healthtextApplied = false,
			framealphaApplied = false,
			savedBorderColor = nil,
			savedNameColor = nil,
			savedHealthTextColor = nil,
			savedFrameAlpha = nil,
		}
	end
	return frame._adIndicators
end

-- ============================================================
-- BEGIN FRAME
-- ============================================================

function Indicators:BeginFrame(frame)
	local adState = EnsureADState(frame)

	-- Mark all existing indicators as stale (will be re-activated in Apply*)
	for _, icon in ipairs(adState.icons) do
		icon._adActive = false
	end
	for _, sq in ipairs(adState.squares) do
		sq._adActive = false
	end
	for _, bar in ipairs(adState.bars) do
		bar._adActive = false
	end

	-- Frame-level flags reset
	adState.borderApplied = false
	adState.healthbarApplied = false
	adState.nametextApplied = false
	adState.healthtextApplied = false
	adState.framealphaApplied = false
end

-- ============================================================
-- ICON CREATION
-- ============================================================

local AD_ICON_TEMPLATE = "BackdropTemplate"

local function CreateIconFrame(parent)
	local size = 20
	local f = CreateFrame("Button", nil, parent, AD_ICON_TEMPLATE)
	f:SetSize(size, size)

	-- Icon texture
	local tex = f:CreateTexture(nil, "ARTWORK")
	tex:SetAllPoints()
	tex:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- standard zoom
	f.texture = tex

	-- Cooldown
	local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	cd:SetAllPoints()
	cd:SetDrawSwipe(true)
	cd:SetDrawEdge(false)
	cd:SetReverse(true)
	cd:SetHideCountdownNumbers(false)
	f.cooldown = cd

	-- Border (1px dark)
	f:SetBackdrop({
		bgFile = nil,
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	f:SetBackdropBorderColor(0, 0, 0, 0.8)

	-- Stack text
	local stack = f:CreateFontString(nil, "OVERLAY")
	stack:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
	stack:SetPoint("BOTTOMRIGHT", 2, -1)
	stack:SetJustifyH("RIGHT")
	f.stackText = stack

	-- Duration text
	local dur = f:CreateFontString(nil, "OVERLAY")
	dur:SetFont(STANDARD_TEXT_FONT, 10, "OUTLINE")
	dur:SetPoint("CENTER")
	dur:SetJustifyH("CENTER")
	f.durationText = dur

	-- Expiring state
	f._adExpiring = false
	f._adExpirationTime = nil
	f._adDuration = nil

	-- OnUpdate: duration text + expiring pulse
	f:SetScript("OnUpdate", function(self, elapsed)
		if not self._adExpirationTime or not self._adDuration then return end
		local now = GetTime()
		local remaining = self._adExpirationTime - now
		if remaining <= 0 then
			if self.durationText then self.durationText:SetText("") end
			return
		end

		-- Duration text update
		if self.durationText and self._adShowDuration then
			self.durationText:SetText(FormatDuration(remaining))
			-- Color by time
			if remaining <= 3 then
				self.durationText:SetTextColor(1, 0.2, 0.2)
			elseif remaining <= 5 then
				self.durationText:SetTextColor(1, 0.6, 0.2)
			else
				self.durationText:SetTextColor(1, 1, 1)
			end
		end

		-- Expiring pulse
		local isExpiring = false
		if self._adDuration > 0 then
			local pctRemaining = remaining / self._adDuration
			isExpiring = (pctRemaining <= EXPIRING_THRESHOLD_PCT) or (remaining <= EXPIRING_THRESHOLD_SEC)
		end

		if isExpiring then
			if not self._adExpiring then
				self._adExpiring = true
			end
			-- Pulse alpha
			local pulse = (math_sin(now * EXPIRING_PULSE_SPEED * 2 * math.pi) + 1) / 2
			local alpha = EXPIRING_MIN_ALPHA + pulse * (EXPIRING_MAX_ALPHA - EXPIRING_MIN_ALPHA)
			self:SetAlpha(alpha)
			-- Red border
			if self.SetBackdropBorderColor then
				self:SetBackdropBorderColor(EXPIRING_BORDER_COLOR.r, EXPIRING_BORDER_COLOR.g, EXPIRING_BORDER_COLOR.b, 1)
			end
		else
			if self._adExpiring then
				self._adExpiring = false
				self:SetAlpha(self._adBaseAlpha or 1)
				if self.SetBackdropBorderColor then
					self:SetBackdropBorderColor(0, 0, 0, 0.8)
				end
			end
		end
	end)

	f._adType = "icon"
	return f
end

-- ============================================================
-- SQUARE CREATION
-- ============================================================

local function CreateSquareFrame(parent)
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	f:SetSize(8, 8)

	-- Color fill
	local fill = f:CreateTexture(nil, "ARTWORK")
	fill:SetAllPoints()
	fill:SetColorTexture(1, 1, 1, 1)
	f.fill = fill

	-- Border
	f:SetBackdrop({
		bgFile = nil,
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	f:SetBackdropBorderColor(0, 0, 0, 0.8)

	-- Stack text
	local stack = f:CreateFontString(nil, "OVERLAY")
	stack:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
	stack:SetPoint("CENTER")
	f.stackText = stack

	f._adType = "square"
	return f
end

-- ============================================================
-- BAR CREATION
-- ============================================================

local function CreateBarFrame(parent)
	local f = CreateFrame("StatusBar", nil, parent)
	f:SetSize(60, 4)
	f:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
	f:SetMinMaxValues(0, 1)
	f:SetValue(1)

	-- Background
	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 0.5)
	f.bg = bg

	-- Border frame
	local border = CreateFrame("Frame", nil, f, "BackdropTemplate")
	border:SetPoint("TOPLEFT", -1, 1)
	border:SetPoint("BOTTOMRIGHT", 1, -1)
	border:SetBackdrop({
		bgFile = nil,
		edgeFile = "Interface\\Buttons\\WHITE8x8",
		edgeSize = 1,
	})
	border:SetBackdropBorderColor(0, 0, 0, 1)
	f.borderFrame = border

	-- Duration text
	local dur = f:CreateFontString(nil, "OVERLAY")
	dur:SetFont(STANDARD_TEXT_FONT, 8, "OUTLINE")
	dur:SetPoint("CENTER")
	f.durationText = dur

	-- Expiring state
	f._adExpirationTime = nil
	f._adDuration = nil
	f._adOrigR = nil
	f._adOrigG = nil
	f._adOrigB = nil

	-- OnUpdate: 실시간 바 갱신 + 만료 색상
	f:SetScript("OnUpdate", function(self, elapsed)
		if not self._adExpirationTime or not self._adDuration then return end
		if self._adDuration <= 0 then return end
		local now = GetTime()
		local remaining = self._adExpirationTime - now
		if remaining < 0 then remaining = 0 end

		-- Fill value
		self:SetValue(remaining / self._adDuration)

		-- Duration text
		if self.durationText and self._adShowDuration then
			if remaining > 0 then
				self.durationText:SetText(FormatDuration(remaining))
			else
				self.durationText:SetText("")
			end
		end

		-- Expiring color transition
		local pctRemaining = remaining / self._adDuration
		if pctRemaining <= EXPIRING_THRESHOLD_PCT or remaining <= EXPIRING_THRESHOLD_SEC then
			-- Lerp to red
			local t = 1 - (pctRemaining / EXPIRING_THRESHOLD_PCT)
			if t > 1 then t = 1 end
			if t < 0 then t = 0 end
			local r = (self._adOrigR or 1) + (EXPIRING_BORDER_COLOR.r - (self._adOrigR or 1)) * t
			local g = (self._adOrigG or 1) + (EXPIRING_BORDER_COLOR.g - (self._adOrigG or 1)) * t
			local b = (self._adOrigB or 1) + (EXPIRING_BORDER_COLOR.b - (self._adOrigB or 1)) * t
			self:SetStatusBarColor(r, g, b, 1)
		else
			if self._adOrigR then
				self:SetStatusBarColor(self._adOrigR, self._adOrigG, self._adOrigB, 1)
			end
		end
	end)

	f._adType = "bar"
	return f
end

-- (FormatDuration moved to top of file)

-- ============================================================
-- COMMON HELPERS
-- ============================================================

local function SetupCooldown(cooldown, auraData, unit)
	if not cooldown then return end
	if not auraData then
		cooldown:Clear()
		return
	end

	local instanceID = auraData.auraInstanceID

	-- Secret-safe: use SetCooldownFromExpirationTime (11.1+)
	if cooldown.SetCooldownFromExpirationTime and auraData.expirationTime and auraData.duration then
		cooldown:SetCooldownFromExpirationTime(auraData.expirationTime, auraData.duration)
	elseif auraData.duration and auraData.expirationTime then
		local startTime = auraData.expirationTime - auraData.duration
		if startTime > 0 and auraData.duration > 0 then
			cooldown:SetCooldown(startTime, auraData.duration)
		else
			cooldown:Clear()
		end
	else
		cooldown:Clear()
	end

	-- Expiration visibility (secret-safe)
	if C_UnitAuras.DoesAuraHaveExpirationTime and unit and instanceID then
		local hasExp = C_UnitAuras.DoesAuraHaveExpirationTime(unit, instanceID)
		if cooldown.SetShownFromBoolean then
			cooldown:SetShownFromBoolean(hasExp, true, false)
		elseif not hasExp then
			cooldown:Clear()
		end
	end
end

local function ApplyStacks(stackText, auraData, config)
	if not stackText then return end
	local showStacks = config.showStacks ~= false
	local minStacks = config.stackMinimum or 2
	local stacks = auraData and auraData.stacks or 0

	if showStacks and stacks >= minStacks then
		stackText:SetText(stacks)
		stackText:Show()
	else
		stackText:SetText("")
		stackText:Hide()
	end
end

-- ============================================================
-- APPLY: ICON
-- ============================================================

function Indicators:ApplyIcon(frame, config, auraData, auraName)
	local adState = EnsureADState(frame)

	-- Find existing or acquire new
	local iconFrame = nil
	local iconID = config.id
	for _, existing in ipairs(adState.icons) do
		if existing._adID == iconID then
			iconFrame = existing
			break
		end
	end

	if not iconFrame then
		iconFrame = AcquireFromPool(iconPool, CreateIconFrame, frame)
		iconFrame._adID = iconID
		adState.icons[#adState.icons + 1] = iconFrame
	end

	iconFrame._adActive = true
	iconFrame._adAuraName = auraName

	-- Size
	local size = config.size or 20
	local scale = config.scale or 1.0
	iconFrame:SetSize(size, size)
	iconFrame:SetScale(scale)
	iconFrame:SetAlpha(config.alpha or 1.0)

	-- Position
	local anchor = config.anchor or "TOPLEFT"
	local oX = config.offsetX or 0
	local oY = config.offsetY or 0
	iconFrame:ClearAllPoints()
	iconFrame:SetPoint(anchor, frame, anchor, oX, oY)

	-- Texture
	local AD = ns.AuraDesigner
	local texID = AD.IconTextures and AD.IconTextures[auraName]
	if texID then
		iconFrame.texture:SetTexture(texID)
	elseif auraData and auraData.icon then
		iconFrame.texture:SetTexture(auraData.icon)
	end

	-- Cooldown
	local unit = frame.unit or frame._unit
	SetupCooldown(iconFrame.cooldown, auraData, unit)

	-- Hide swipe if configured
	if config.hideSwipe and iconFrame.cooldown then
		iconFrame.cooldown:SetDrawSwipe(false)
	elseif iconFrame.cooldown then
		iconFrame.cooldown:SetDrawSwipe(true)
	end

	-- Stacks
	ApplyStacks(iconFrame.stackText, auraData, config)

	-- Border
	if config.borderEnabled == false then
		iconFrame:SetBackdropBorderColor(0, 0, 0, 0)
	else
		iconFrame:SetBackdropBorderColor(0, 0, 0, 0.8)
	end

	-- FrameLevel
	local parentLevel = frame:GetFrameLevel()
	iconFrame:SetFrameLevel(parentLevel + (config.frameLevel or 30))

	-- Expiring / OnUpdate state
	iconFrame._adBaseAlpha = config.alpha or 1.0
	iconFrame._adShowDuration = config.showDuration ~= false
	if auraData and auraData.duration and auraData.duration > 0 and auraData.expirationTime then
		iconFrame._adExpirationTime = auraData.expirationTime
		iconFrame._adDuration = auraData.duration
	else
		iconFrame._adExpirationTime = nil
		iconFrame._adDuration = nil
		if iconFrame.durationText then iconFrame.durationText:SetText("") end
	end

	iconFrame:Show()
end

-- ============================================================
-- APPLY: SQUARE
-- ============================================================

function Indicators:ApplySquare(frame, config, auraData, auraName)
	local adState = EnsureADState(frame)

	local sqFrame = nil
	local sqID = config.id
	for _, existing in ipairs(adState.squares) do
		if existing._adID == sqID then
			sqFrame = existing
			break
		end
	end

	if not sqFrame then
		sqFrame = AcquireFromPool(squarePool, CreateSquareFrame, frame)
		sqFrame._adID = sqID
		adState.squares[#adState.squares + 1] = sqFrame
	end

	sqFrame._adActive = true
	sqFrame._adAuraName = auraName

	-- Size
	local size = config.size or 8
	sqFrame:SetSize(size, size)
	sqFrame:SetScale(config.scale or 1.0)
	sqFrame:SetAlpha(config.alpha or 1.0)

	-- Position
	local anchor = config.anchor or "TOPLEFT"
	sqFrame:ClearAllPoints()
	sqFrame:SetPoint(anchor, frame, anchor, config.offsetX or 0, config.offsetY or 0)

	-- Color
	local color = config.color
	if color then
		sqFrame.fill:SetColorTexture(color.r or 1, color.g or 1, color.b or 1, color.a or 1)
	else
		-- Use aura color from TrackableAuras
		local AD = ns.AuraDesigner
		local trackable = AD.TrackableAuras
		local spec = frame.adState and frame.adState.spec
		if spec and trackable and trackable[spec] then
			for _, info in ipairs(trackable[spec]) do
				if info.name == auraName and info.color then
					sqFrame.fill:SetColorTexture(info.color[1], info.color[2], info.color[3], 1)
					break
				end
			end
		end
	end

	-- Border
	if config.showBorder ~= false then
		sqFrame:SetBackdropBorderColor(0, 0, 0, 0.8)
	else
		sqFrame:SetBackdropBorderColor(0, 0, 0, 0)
	end

	-- Stacks
	ApplyStacks(sqFrame.stackText, auraData, config)

	-- FrameLevel
	local parentLevel = frame:GetFrameLevel()
	sqFrame:SetFrameLevel(parentLevel + (config.frameLevel or 30))

	sqFrame:Show()
end

-- ============================================================
-- APPLY: BAR
-- ============================================================

function Indicators:ApplyBar(frame, config, auraData, auraName)
	local adState = EnsureADState(frame)

	local barFrame = nil
	local barID = config.id
	for _, existing in ipairs(adState.bars) do
		if existing._adID == barID then
			barFrame = existing
			break
		end
	end

	if not barFrame then
		barFrame = AcquireFromPool(barPool, CreateBarFrame, frame)
		barFrame._adID = barID
		adState.bars[#adState.bars + 1] = barFrame
	end

	barFrame._adActive = true
	barFrame._adAuraName = auraName

	-- Size
	local width = config.width or 60
	local height = config.height or 4
	if config.matchFrameWidth then
		width = frame:GetWidth()
	end
	if config.matchFrameHeight then
		height = frame:GetHeight()
	end
	barFrame:SetSize(width, height)
	barFrame:SetAlpha(config.alpha or 1.0)

	-- Position
	local anchor = config.anchor or "BOTTOM"
	barFrame:ClearAllPoints()
	barFrame:SetPoint(anchor, frame, anchor, config.offsetX or 0, config.offsetY or 0)

	-- Orientation
	if config.orientation == "VERTICAL" then
		barFrame:SetOrientation("VERTICAL")
	else
		barFrame:SetOrientation("HORIZONTAL")
	end

	-- Colors
	local fc = config.fillColor
	if fc then
		barFrame:SetStatusBarColor(fc.r or 1, fc.g or 1, fc.b or 1, fc.a or 1)
	else
		-- Use aura color
		local AD = ns.AuraDesigner
		local trackable = AD.TrackableAuras
		local spec = frame.adState and frame.adState.spec
		if spec and trackable and trackable[spec] then
			for _, info in ipairs(trackable[spec]) do
				if info.name == auraName and info.color then
					barFrame:SetStatusBarColor(info.color[1], info.color[2], info.color[3], 1)
					break
				end
			end
		end
	end

	local bc = config.bgColor
	if bc and barFrame.bg then
		barFrame.bg:SetColorTexture(bc.r or 0, bc.g or 0, bc.b or 0, bc.a or 0.5)
	end

	-- Fill value + OnUpdate state
	barFrame._adShowDuration = config.showDuration or false
	if auraData and auraData.duration and auraData.duration > 0 and auraData.expirationTime then
		barFrame._adExpirationTime = auraData.expirationTime
		barFrame._adDuration = auraData.duration
		local remaining = auraData.expirationTime - GetTime()
		if remaining < 0 then remaining = 0 end
		barFrame:SetValue(remaining / auraData.duration)
		-- Save original color for expiring lerp
		barFrame._adOrigR, barFrame._adOrigG, barFrame._adOrigB = barFrame:GetStatusBarColor()
	else
		barFrame._adExpirationTime = nil
		barFrame._adDuration = nil
		barFrame:SetValue(1)
	end

	-- Border
	if barFrame.borderFrame then
		if config.showBorder ~= false then
			barFrame.borderFrame:Show()
			local bdc = config.borderColor
			if bdc then
				barFrame.borderFrame:SetBackdropBorderColor(bdc.r or 0, bdc.g or 0, bdc.b or 0, bdc.a or 1)
			end
		else
			barFrame.borderFrame:Hide()
		end
	end

	-- Duration text (initial; OnUpdate handles live updates)
	if barFrame.durationText then
		if barFrame._adShowDuration and barFrame._adDuration and barFrame._adDuration > 0 then
			local rem = (barFrame._adExpirationTime or 0) - GetTime()
			if rem > 0 then
				barFrame.durationText:SetText(FormatDuration(rem))
				barFrame.durationText:Show()
			else
				barFrame.durationText:Hide()
			end
		else
			barFrame.durationText:Hide()
		end
	end

	-- FrameLevel
	local parentLevel = frame:GetFrameLevel()
	barFrame:SetFrameLevel(parentLevel + (config.frameLevel or 30))

	barFrame:Show()
end

-- ============================================================
-- APPLY: BORDER (frame-level)
-- ============================================================

function Indicators:ApplyBorder(frame, config, auraData)
	local adState = EnsureADState(frame)
	if adState.borderApplied then return end
	adState.borderApplied = true

	-- Save original if first time
	if not adState.savedBorderColor and frame.SetBackdropBorderColor then
		local r, g, b, a = frame:GetBackdropBorderColor()
		if r then
			adState.savedBorderColor = { r = r, g = g, b = b, a = a }
		end
	end

	local color = config.color
	if color and frame.SetBackdropBorderColor then
		local r, g, b = color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1
		local thickness = config.thickness or 2
		-- Apply glow-style border via procedural glow or backdrop
		frame:SetBackdropBorderColor(r, g, b, 1)
	end
end

-- ============================================================
-- APPLY: HEALTH BAR COLOR (frame-level)
-- ============================================================

function Indicators:ApplyHealthBar(frame, config, auraData)
	local adState = EnsureADState(frame)
	if adState.healthbarApplied then return end
	adState.healthbarApplied = true

	-- Health bar: frame.Health (oUF) or frame.healthBar (GroupFrames)
	local healthBar = frame.Health or frame.healthBar
	if not healthBar then return end

	local color = config.color
	if not color then return end

	local r, g, b = color.r or color[1] or 1, color.g or color[2] or 1, color.b or color[3] or 1
	local mode = config.mode or "Tint"
	local blend = config.blend or 0.5

	-- Create or show tint overlay
	if not adState.tintOverlay then
		local overlay = CreateFrame("StatusBar", nil, healthBar)
		overlay:SetAllPoints(healthBar)
		overlay:SetFrameLevel(healthBar:GetFrameLevel() + 1)
		overlay:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
		overlay:SetMinMaxValues(0, 1)
		overlay:SetValue(1)
		adState.tintOverlay = overlay
	end

	local overlay = adState.tintOverlay
	if mode == "Replace" then
		overlay:SetStatusBarColor(r, g, b, 1)
	else
		overlay:SetStatusBarColor(r, g, b, blend)
	end
	overlay:Show()
end

-- ============================================================
-- APPLY: NAME TEXT COLOR (frame-level)
-- ============================================================

function Indicators:ApplyNameText(frame, config, auraData)
	local adState = EnsureADState(frame)
	if adState.nametextApplied then return end
	adState.nametextApplied = true

	-- Name text: frame.NameText (DDingUI) or frame.nameText
	local nameText = frame.NameText or frame.nameText
	if not nameText then return end

	-- Save original
	if not adState.savedNameColor then
		local r, g, b, a = nameText:GetTextColor()
		adState.savedNameColor = { r = r, g = g, b = b, a = a }
	end

	local color = config.color
	if color then
		nameText:SetTextColor(color.r or 1, color.g or 1, color.b or 1, 1)
	end
end

-- ============================================================
-- APPLY: HEALTH TEXT COLOR (frame-level)
-- ============================================================

function Indicators:ApplyHealthText(frame, config, auraData)
	local adState = EnsureADState(frame)
	if adState.healthtextApplied then return end
	adState.healthtextApplied = true

	local healthText = frame.HealthText or frame.healthText
	if not healthText then return end

	if not adState.savedHealthTextColor then
		local r, g, b, a = healthText:GetTextColor()
		adState.savedHealthTextColor = { r = r, g = g, b = b, a = a }
	end

	local color = config.color
	if color then
		healthText:SetTextColor(color.r or 1, color.g or 1, color.b or 1, 1)
	end
end

-- ============================================================
-- APPLY: FRAME ALPHA (frame-level)
-- ============================================================

function Indicators:ApplyFrameAlpha(frame, config, auraData)
	local adState = EnsureADState(frame)
	if adState.framealphaApplied then return end
	adState.framealphaApplied = true

	if not adState.savedFrameAlpha then
		adState.savedFrameAlpha = frame:GetAlpha()
	end

	local alpha = config.alpha or 0.5
	frame:SetAlpha(alpha)
end

-- ============================================================
-- END FRAME
-- ============================================================

function Indicators:EndFrame(frame, fState)
	local adState = frame._adIndicators
	if not adState then return end

	-- Hide stale placed indicators
	for i = #adState.icons, 1, -1 do
		local icon = adState.icons[i]
		if not icon._adActive then
			table.remove(adState.icons, i)
			ReleaseToPool(iconPool, icon)
		end
	end
	for i = #adState.squares, 1, -1 do
		local sq = adState.squares[i]
		if not sq._adActive then
			table.remove(adState.squares, i)
			ReleaseToPool(squarePool, sq)
		end
	end
	for i = #adState.bars, 1, -1 do
		local bar = adState.bars[i]
		if not bar._adActive then
			table.remove(adState.bars, i)
			ReleaseToPool(barPool, bar)
		end
	end

	-- Revert frame-level effects that were not applied this frame
	if not adState.borderApplied then
		self:RevertBorder(frame)
	end
	if not adState.healthbarApplied then
		self:RevertHealthBar(frame)
	end
	if not adState.nametextApplied then
		self:RevertNameText(frame)
	end
	if not adState.healthtextApplied then
		self:RevertHealthText(frame)
	end
	if not adState.framealphaApplied then
		self:RevertFrameAlpha(frame)
	end
end

-- ============================================================
-- REVERT HELPERS
-- ============================================================

function Indicators:RevertBorder(frame)
	local adState = frame._adIndicators
	if not adState then return end
	if adState.savedBorderColor and frame.SetBackdropBorderColor then
		local c = adState.savedBorderColor
		frame:SetBackdropBorderColor(c.r, c.g, c.b, c.a)
		adState.savedBorderColor = nil
	end
end

function Indicators:RevertHealthBar(frame)
	local adState = frame._adIndicators
	if not adState then return end
	if adState.tintOverlay then
		adState.tintOverlay:Hide()
	end
end

function Indicators:RevertNameText(frame)
	local adState = frame._adIndicators
	if not adState or not adState.savedNameColor then return end
	local nameText = frame.NameText or frame.nameText
	if nameText then
		local c = adState.savedNameColor
		nameText:SetTextColor(c.r, c.g, c.b, c.a)
	end
	adState.savedNameColor = nil
end

function Indicators:RevertHealthText(frame)
	local adState = frame._adIndicators
	if not adState or not adState.savedHealthTextColor then return end
	local healthText = frame.HealthText or frame.healthText
	if healthText then
		local c = adState.savedHealthTextColor
		healthText:SetTextColor(c.r, c.g, c.b, c.a)
	end
	adState.savedHealthTextColor = nil
end

function Indicators:RevertFrameAlpha(frame)
	local adState = frame._adIndicators
	if not adState then return end
	if adState.savedFrameAlpha then
		frame:SetAlpha(adState.savedFrameAlpha)
		adState.savedFrameAlpha = nil
	end
end

function Indicators:RevertAll(frame)
	local adState = frame._adIndicators
	if not adState then return end

	-- Release all placed indicators
	for i = #adState.icons, 1, -1 do
		ReleaseToPool(iconPool, adState.icons[i])
		adState.icons[i] = nil
	end
	for i = #adState.squares, 1, -1 do
		ReleaseToPool(squarePool, adState.squares[i])
		adState.squares[i] = nil
	end
	for i = #adState.bars, 1, -1 do
		ReleaseToPool(barPool, adState.bars[i])
		adState.bars[i] = nil
	end

	-- Revert frame-level effects
	self:RevertBorder(frame)
	self:RevertHealthBar(frame)
	self:RevertNameText(frame)
	self:RevertHealthText(frame)
	self:RevertFrameAlpha(frame)

	frame._adIndicators = nil
end

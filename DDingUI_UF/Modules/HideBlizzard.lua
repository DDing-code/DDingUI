--[[
	ddingUI UnitFrames
	Modules/HideBlizzard.lua - Hide default Blizzard unit frames
	ElvUI 패턴: hooksecurefunc + SetParent(HiddenFrame) — taint-safe
]]

local _, ns = ...

local HideBlizzard = {}
ns.HideBlizzard = HideBlizzard

local hooksecurefunc = hooksecurefunc
local InCombatLockdown = InCombatLockdown
local pcall = pcall

-----------------------------------------------
-- Taint-Safe Frame Hiding
-----------------------------------------------

local hiddenParent -- lazy init in Apply()

-- [12.0.1] EditMode 관리 프레임용 (PlayerFrame, TargetFrame, FocusFrame 등)
-- SetParent(hiddenParent) → HideBase() taint 유발
-- → SetAlpha(0) + SetScale(0.001)로 시각만 숨김 (이벤트는 해제)
local function HideFrameAlpha(frame)
	if not frame then return end

	-- 이벤트 해제 (업데이트 차단)
	if frame.UnregisterAllEvents then
		frame:UnregisterAllEvents()
	end

	-- 시각만 숨김 (taint-safe)
	frame:SetAlpha(0)
	frame:SetScale(0.001)
	hooksecurefunc(frame, "SetAlpha", function(self, alpha)
		if alpha > 0 then self:SetAlpha(0) end
	end)
	hooksecurefunc(frame, "Show", function(self)
		self:SetAlpha(0)
	end)
end

-- 비-EditMode 프레임용 (Boss 프레임 등) — SetParent 방식
local function HideFrame(frame)
	if not frame then return end

	if frame.UnregisterAllEvents then
		frame:UnregisterAllEvents()
	end

	frame:SetParent(hiddenParent)

	hooksecurefunc(frame, "Show", frame.Hide)
	hooksecurefunc(frame, "SetShown", function(self, shown)
		if shown then self:Hide() end
	end)

	if not InCombatLockdown() then
		pcall(frame.Hide, frame)
	end
end

-- 자식 요소도 비활성화 (ElvUI DisableBlizzard_DisableFrame 패턴)
local function DisableChildren(frame)
	if not frame then return end
	local children = {
		frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar,
		frame.healthBar or frame.healthbar or frame.HealthBar,
		frame.castBar or frame.CastBar,
		frame.debuffFrame or frame.DebuffFrame,
		frame.BuffFrame or frame.AurasFrame,
		frame.totFrame,
		frame.manabar or frame.ManaBar,
		frame.spellbar or frame.SpellBar,
	}
	for _, child in ipairs(children) do
		if child and child.UnregisterAllEvents then
			child:UnregisterAllEvents()
		end
	end
end

-----------------------------------------------
-- Apply
-----------------------------------------------

function HideBlizzard:Apply()
	-- Hidden parent frame
	if not hiddenParent then
		hiddenParent = CreateFrame("Frame", nil, UIParent)
		hiddenParent:SetPoint("BOTTOM")
		hiddenParent:SetSize(1, 1)
		hiddenParent:Hide()
	end
	ns._hiddenParent = hiddenParent

	-- Player Frame (EditMode 관리 → alpha 방식) -- [12.0.1]
	if PlayerFrame then
		HideFrameAlpha(PlayerFrame)
		DisableChildren(PlayerFrame)
	end
	if PlayerFrameAlternateManaBar then
		HideFrameAlpha(PlayerFrameAlternateManaBar)
	end

	-- Target Frame (EditMode 관리 → alpha 방식) -- [12.0.1]
	if TargetFrame then
		HideFrameAlpha(TargetFrame)
		DisableChildren(TargetFrame)
	end
	if ComboPointPlayerFrame then
		HideFrameAlpha(ComboPointPlayerFrame)
	end

	-- Focus Frame (EditMode 관리 → alpha 방식) -- [12.0.1]
	if FocusFrame then
		HideFrameAlpha(FocusFrame)
		DisableChildren(FocusFrame)
	end

	-- Party Frames — SetAlpha 방식 (이벤트 유지, BlizzardAuraCache hook 정상 작동)
	-- [REFACTOR] HideFrame → SetAlpha(0) + SetScale(0.001) (taint-safe, 이벤트 보존)
	if PartyFrame then
		PartyFrame:SetAlpha(0)
		PartyFrame:SetScale(0.001)
		hooksecurefunc(PartyFrame, "SetAlpha", function(self, alpha)
			if alpha > 0 then self:SetAlpha(0) end
		end)
		hooksecurefunc(PartyFrame, "Show", function(self)
			self:SetAlpha(0)
		end)
	end

	-- Compact Raid Frames (DandersFrames 방식: 시각만 숨기고 이벤트 유지)
	-- SetParent(hiddenParent)하면 Blizzard 프레임 관리와 충돌 → "script ran too long"
	-- SetAlpha(0) + SetScale(0.001)로 투명하게 숨기되 이벤트/hook은 그대로 유지
	-- → CompactUnitFrame_UpdateAuras hook이 정상 작동 → 캐시 기반 필터 가능
	if CompactRaidFrameManager then
		CompactRaidFrameManager:SetAlpha(0)
		CompactRaidFrameManager:SetScale(0.001)
		hooksecurefunc(CompactRaidFrameManager, "SetAlpha", function(self, alpha)
			if alpha > 0 then self:SetAlpha(0) end
		end)
		hooksecurefunc(CompactRaidFrameManager, "Show", function(self)
			self:SetAlpha(0)
		end)
	end
	if CompactRaidFrameContainer then
		CompactRaidFrameContainer:SetAlpha(0)
		CompactRaidFrameContainer:SetScale(0.001)
		hooksecurefunc(CompactRaidFrameContainer, "SetAlpha", function(self, alpha)
			if alpha > 0 then self:SetAlpha(0) end
		end)
		hooksecurefunc(CompactRaidFrameContainer, "Show", function(self)
			self:SetAlpha(0)
		end)
	end

	-- Boss Frames
	for i = 1, 8 do
		local bossFrame = _G["Boss" .. i .. "TargetFrame"]
		if bossFrame then
			HideFrame(bossFrame)
		end
	end

	-- Target of Target / Pet / Focus ToT (EditMode 관리 → alpha 방식) -- [12.0.1]
	if TargetFrameToT then HideFrameAlpha(TargetFrameToT) end
	if PetFrame then HideFrameAlpha(PetFrame) end
	if FocusFrameToT then HideFrameAlpha(FocusFrameToT) end

	-- Player Castbar (if we have our own)
	-- [FIX] PlayerCastingBarFrame은 EditMode managed frame
	-- SetParent(hiddenParent)하면 unit=nil 되어 UnitChannelInfo(nil) 크래시 (57x)
	-- UnregisterAllEvents()하면 EditMode가 재등록 시 unit=nil 크래시
	-- → SetParent/이벤트 건드리지 않고 알파만 0으로 (투명하게 숨김)
	if ns.db and ns.db.player and ns.db.player.castbar and ns.db.player.castbar.enabled then
		if PlayerCastingBarFrame then
			PlayerCastingBarFrame:SetAlpha(0)
			PlayerCastingBarFrame:SetScale(0.001)
			hooksecurefunc(PlayerCastingBarFrame, "SetAlpha", function(self, alpha)
				if alpha > 0 then self:SetAlpha(0) end
			end)
			hooksecurefunc(PlayerCastingBarFrame, "Show", function(self)
				self:SetAlpha(0)
			end)
		end
	end

	ns.Debug("Blizzard frames hidden (taint-safe)")
end

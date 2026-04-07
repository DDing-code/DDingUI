--[[
	DDingUI DF Plugin
	Core.lua - Icon Set Override for DandersFrames

	DDingUI_UF의 아이콘 세트를 DandersFrames에 적용합니다.
	역할(탱/힐/딜), 리더, 전투, 휴식 아이콘을 DDingUI 스타일로 교체합니다.
]]

local ADDON_NAME = ...

-- ============================================================
-- ICON SET DEFINITION
-- ============================================================

local MEDIA_PATH = "Interface\\AddOns\\DDingUI_DF_Plugin\\Media\\Icons\\"

local ICON_SET = {
	role = {
		TANK    = MEDIA_PATH .. "tank_sololv",
		HEALER  = MEDIA_PATH .. "healer_sololv",
		DAMAGER = MEDIA_PATH .. "dps_sololv",
	},
	leader  = MEDIA_PATH .. "leader_sololv",
	combat  = MEDIA_PATH .. "combat_sololv",
	resting = MEDIA_PATH .. "rest_sololv",
}

-- ============================================================
-- DB DEFAULTS
-- ============================================================

local DEFAULTS = {
	iconSetEnabled = true,
	minimap = { hide = false },
	flightFade = {
		enabled        = true,
		hideWhileFlying  = true,
		hideWhileMounted = false,
		hideInVehicle    = false,
		hideOutsideInstanceOnly = false,
		fadeDuration     = 0.5,
	},
}

-- ============================================================
-- MINIMAP BUTTON (LibDBIcon)
-- ============================================================

local LOGO_PATH = "Interface\\AddOns\\DDingUI_DF_Plugin\\Media\\logo"

local db -- reference to DDingUI_DF_PluginDB

local function CreateMinimapButton()
	local LDB = LibStub and LibStub("LibDataBroker-1.1", true)
	local LibDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)

	if not LDB or not LibDBIcon then return end

	if not db.minimap then
		db.minimap = { hide = false }
	end

	local dataObj = LDB:NewDataObject(ADDON_NAME, {
		type = "launcher",
		icon = LOGO_PATH,
		label = "DDingUI DF Plugin",
		OnClick = function(_, button)
			if button == "LeftButton" then
				SlashCmdList["DDFP"]("status")
			elseif button == "RightButton" then
				if db.flightFade.enabled then
					SlashCmdList["DDFP"]("fade off")
				else
					SlashCmdList["DDFP"]("fade on")
				end
			end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:SetText("|cffffa300DDingUI|r DF Plugin")
			tooltip:AddLine("|cffffffffLeft-click|r  현재 상태 표시", 0.7, 0.7, 0.7)
			tooltip:AddLine("|cffffffffRight-click|r  비행 페이드 토글", 0.7, 0.7, 0.7)
			tooltip:AddLine(" ")
			local fadeStatus = db.flightFade.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"
			tooltip:AddLine("비행 페이드: " .. fadeStatus, 1, 1, 1)
		end,
	})

	LibDBIcon:Register(ADDON_NAME, dataObj, db.minimap)
end

-- ============================================================
-- INITIALIZATION
-- ============================================================


local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")

initFrame:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
		-- Initialize SavedVariables
		if not DDingUI_DF_PluginDB then
			DDingUI_DF_PluginDB = CopyTable(DEFAULTS)
		else
			-- Merge missing defaults
			for k, v in pairs(DEFAULTS) do
				if DDingUI_DF_PluginDB[k] == nil then
					if type(v) == "table" then
						DDingUI_DF_PluginDB[k] = CopyTable(v)
					else
						DDingUI_DF_PluginDB[k] = v
					end
				end
			end
			if type(DDingUI_DF_PluginDB.flightFade) == "table" then
				for k, v in pairs(DEFAULTS.flightFade) do
					if DDingUI_DF_PluginDB.flightFade[k] == nil then
						DDingUI_DF_PluginDB.flightFade[k] = v
					end
				end
			end
		end
		db = DDingUI_DF_PluginDB

		-- 미니맵 버튼 생성 (ADDON_LOADED에서 — AddonCompartment 정렬 통일)
		CreateMinimapButton()

	elseif event == "PLAYER_LOGIN" then
		self:UnregisterAllEvents()

		-- Ensure DandersFrames is loaded
		if not DandersFrames then
			print("|cffffa300DDingUI DF Plugin:|r DandersFrames not found!")
			return
		end

		local DF = DandersFrames

		-- ========================================
		-- HOOK: GetRoleIconTexture
		-- ========================================
		if db.iconSetEnabled and DF.GetRoleIconTexture then
			local origGetRoleIconTexture = DF.GetRoleIconTexture

			function DF:GetRoleIconTexture(frameDB, role)
				-- DDingUI 아이콘 세트 사용
				local tex = ICON_SET.role[role]
				if tex then
					return tex, 0, 1, 0, 1
				end
				-- Fallback to original
				return origGetRoleIconTexture(self, frameDB, role)
			end
		end

		-- ========================================
		-- HOOK: UpdateLeaderIcon (Bars.lua — 실제 호출 경로)
		-- 리더/부관 아이콘 텍스처 교체
		-- ========================================
		if db.iconSetEnabled and DF.UpdateLeaderIcon then
			local origUpdateLeader = DF.UpdateLeaderIcon

			function DF:UpdateLeaderIcon(frame)
				-- 원래 함수 실행 (보이기/숨기기 로직 유지)
				origUpdateLeader(self, frame)

				-- 아이콘이 보이면 텍스처만 교체
				if frame and frame.leaderIcon and frame.leaderIcon:IsShown() then
					frame.leaderIcon.texture:SetTexture(ICON_SET.leader)
					frame.leaderIcon.texture:SetTexCoord(0, 1, 0, 1)
				end
			end
		end

		-- ========================================
		-- HOOK: UpdateLeaderIconEnhanced (StatusIcons.lua)
		-- ========================================
		if db.iconSetEnabled and DF.UpdateLeaderIconEnhanced then
			local origUpdateLeaderEnhanced = DF.UpdateLeaderIconEnhanced

			function DF:UpdateLeaderIconEnhanced(frame)
				origUpdateLeaderEnhanced(self, frame)

				if frame and frame.leaderIcon and frame.leaderIcon:IsShown() then
					frame.leaderIcon.texture:SetTexture(ICON_SET.leader)
					frame.leaderIcon.texture:SetTexCoord(0, 1, 0, 1)
				end
			end
		end


		-- ========================================
		-- FlightFade 초기화
		-- ========================================
		if db.flightFade and db.flightFade.enabled then
			if DDingUI_DF_FlightFade and DDingUI_DF_FlightFade.Initialize then
				DDingUI_DF_FlightFade:Initialize(db.flightFade)
			end
		end

		print("|cffffa300DDingUI DF Plugin:|r v1.0.0 loaded")
	end
end)

-- ============================================================
-- SLASH COMMANDS
-- ============================================================

SLASH_DDFP1 = "/ddfp"
SlashCmdList["DDFP"] = function(msg)
	local cmd = (msg or ""):lower():trim()

	if cmd == "" or cmd == "help" then
		print("|cffffa300DDingUI DF Plugin|r 명령어:")
		print("  /ddfp icons on|off — 아이콘 세트 토글")
		print("  /ddfp fade on|off — 비행 시 페이드 토글")
		print("  /ddfp fly on|off — 비행 중 숨기기")
		print("  /ddfp mount on|off — 탈것 탑승 시 숨기기")
		print("  /ddfp vehicle on|off — 비히클 탑승 시 숨기기")
		print("  /ddfp instance on|off — 인스턴스 밖에서만 숨기기")
		print("  /ddfp status — 현재 설정 표시")

	elseif cmd == "status" then
		if not db then return end
		print("|cffffa300DDingUI DF Plugin|r 설정:")
		print("  아이콘 세트: " .. (db.iconSetEnabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
		print("  비행 페이드: " .. (db.flightFade.enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
		print("    비행: " .. (db.flightFade.hideWhileFlying and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
		print("    탈것: " .. (db.flightFade.hideWhileMounted and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
		print("    비히클: " .. (db.flightFade.hideInVehicle and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
		print("    인스턴스 밖만: " .. (db.flightFade.hideOutsideInstanceOnly and "|cff00ff00ON|r" or "|cffff0000OFF|r"))

	elseif cmd:match("^icons") then
		local _, toggle = cmd:match("^(%S+)%s+(%S+)")
		if not db then return end
		if toggle == "on" then
			db.iconSetEnabled = true
			print("|cffffa300DDingUI DF Plugin:|r 아이콘 세트 |cff00ff00ON|r (리로드 필요)")
		elseif toggle == "off" then
			db.iconSetEnabled = false
			print("|cffffa300DDingUI DF Plugin:|r 아이콘 세트 |cffff0000OFF|r (리로드 필요)")
		end

	elseif cmd:match("^fade") then
		local _, toggle = cmd:match("^(%S+)%s+(%S+)")
		if not db then return end
		if toggle == "on" then
			db.flightFade.enabled = true
			if DDingUI_DF_FlightFade then
				DDingUI_DF_FlightFade:Initialize(db.flightFade)
			end
			print("|cffffa300DDingUI DF Plugin:|r 비행 페이드 |cff00ff00ON|r")
		elseif toggle == "off" then
			db.flightFade.enabled = false
			if DDingUI_DF_FlightFade then
				DDingUI_DF_FlightFade:ForceShow()
			end
			print("|cffffa300DDingUI DF Plugin:|r 비행 페이드 |cffff0000OFF|r")
		end

	elseif cmd:match("^fly") then
		local _, toggle = cmd:match("^(%S+)%s+(%S+)")
		if not db then return end
		db.flightFade.hideWhileFlying = (toggle == "on")
		print("|cffffa300DDingUI DF Plugin:|r 비행 중 숨기기 " .. (db.flightFade.hideWhileFlying and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
		if DDingUI_DF_FlightFade and db.flightFade.enabled then
			DDingUI_DF_FlightFade:EnsureOnUpdate()
		end

	elseif cmd:match("^mount") then
		local _, toggle = cmd:match("^(%S+)%s+(%S+)")
		if not db then return end
		db.flightFade.hideWhileMounted = (toggle == "on")
		print("|cffffa300DDingUI DF Plugin:|r 탈것 숨기기 " .. (db.flightFade.hideWhileMounted and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
		if DDingUI_DF_FlightFade and db.flightFade.enabled then
			DDingUI_DF_FlightFade:EnsureOnUpdate()
		end

	elseif cmd:match("^vehicle") then
		local _, toggle = cmd:match("^(%S+)%s+(%S+)")
		if not db then return end
		db.flightFade.hideInVehicle = (toggle == "on")
		print("|cffffa300DDingUI DF Plugin:|r 비히클 숨기기 " .. (db.flightFade.hideInVehicle and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
		if DDingUI_DF_FlightFade and db.flightFade.enabled then
			DDingUI_DF_FlightFade:EnsureOnUpdate()
		end

	elseif cmd:match("^instance") then
		local _, toggle = cmd:match("^(%S+)%s+(%S+)")
		if not db then return end
		db.flightFade.hideOutsideInstanceOnly = (toggle == "on")
		print("|cffffa300DDingUI DF Plugin:|r 인스턴스 밖에서만 " .. (db.flightFade.hideOutsideInstanceOnly and "|cff00ff00ON|r" or "|cffff0000OFF|r"))
	end
end

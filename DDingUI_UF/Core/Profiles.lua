--[[
	ddingUI UnitFrames
	Core/Profiles.lua - 프로필 관리 시스템
]]

local _, ns = ...

local Profiles = {}
ns.Profiles = Profiles

-----------------------------------------------
-- Local Variables
-----------------------------------------------

local currentProfile = nil
local playerKey = nil
local pendingSpecSwitch = nil -- [SPEC-SWITCH] forward-declare (Switch에서 참조)

-----------------------------------------------
-- Utility Functions
-----------------------------------------------

local function GetPlayerKey()
	if not playerKey then
		local name = UnitName("player")
		local realm = GetRealmName()
		playerKey = name and realm and (name .. " - " .. realm) or "Unknown"
	end
	return playerKey
end

-- [PERF] 키는 string/number이므로 재귀 불필요 → 호출 횟수 ~50% 절감
local function DeepCopy(source)
	if type(source) ~= "table" then
		return source
	end
	local copy = {}
	for key, value in pairs(source) do
		if type(value) == "table" then
			copy[key] = DeepCopy(value)
		else
			copy[key] = value
		end
	end
	return copy
end

local function DeepMerge(source, target)
	for key, value in pairs(source) do
		if target[key] == nil then
			if type(value) == "table" then
				target[key] = DeepCopy(value)
			else
				target[key] = value
			end
		elseif type(value) == "table" and type(target[key]) == "table" then
			DeepMerge(value, target[key])
		end
	end
end

-----------------------------------------------
-- Profile Database Structure
-----------------------------------------------

-- ddingUI_UFDB structure:
-- {
--     profiles = {
--         ["Default"] = { ... settings ... },
--         ["Healing"] = { ... settings ... },
--         ["DPS"] = { ... settings ... },
--     },
--     profileKeys = {
--         ["PlayerName - RealmName"] = "Default",
--     },
--     global = {
--         minimapAngle = 225,
--     }
-- }

-----------------------------------------------
-- Profile API
-----------------------------------------------

-- Initialize profile system
function Profiles:Initialize()
	-- Ensure database structure exists
	ddingUI_UFDB = ddingUI_UFDB or {}
	ddingUI_UFDB.profiles = ddingUI_UFDB.profiles or {}
	ddingUI_UFDB.profileKeys = ddingUI_UFDB.profileKeys or {}
	ddingUI_UFDB.global = ddingUI_UFDB.global or {}

	-- Ensure Default profile exists
	-- 첫 설치 시 내장 프리셋(ns.builtinPreset) 사용, 없으면 ns.defaults fallback
	if not ddingUI_UFDB.profiles["Default"] then
		if ns.builtinPreset then
			ddingUI_UFDB.profiles["Default"] = DeepCopy(ns.builtinPreset)
		else
			ddingUI_UFDB.profiles["Default"] = DeepCopy(ns.defaults)
		end
	end

	-- Get current player's profile
	local pKey = GetPlayerKey()
	if not ddingUI_UFDB.profileKeys[pKey] then
		ddingUI_UFDB.profileKeys[pKey] = "Default"
	end

	currentProfile = ddingUI_UFDB.profileKeys[pKey]

	-- Set ns.db to point to current profile
	ns.db = ddingUI_UFDB.profiles[currentProfile]

	-- Merge defaults into current profile
	DeepMerge(ns.defaults, ns.db)

	-- [12.0.1] privateAuras 구조 마이그레이션 (iconSize → size, spacing 숫자 → 테이블)
	local PA_UNITS = {"player","target","targettarget","focus","focustarget","pet","party","raid","boss","arena"}
	for _, unitKey in ipairs(PA_UNITS) do
		local pa = ns.db[unitKey] and ns.db[unitKey].widgets and ns.db[unitKey].widgets.privateAuras
		if pa then
			-- iconSize → size.width/height
			if pa.iconSize and not pa.size then
				pa.size = { width = pa.iconSize, height = pa.iconSize }
				pa.iconSize = nil
			end
			-- spacing 숫자 → spacing.horizontal/vertical
			if type(pa.spacing) == "number" then
				local s = pa.spacing
				pa.spacing = { horizontal = s, vertical = s }
			end
		end
	end

	-- [SPEC-SWITCH] 전문화별 프로필 자동 전환 초기화
	self:InitSpecSwitch()

	ns.Debug("Profiles initialized. Current profile:", currentProfile)
end

-- Get list of all profiles
function Profiles:GetList()
	local list = {}
	if ddingUI_UFDB and ddingUI_UFDB.profiles then
		for name in pairs(ddingUI_UFDB.profiles) do
			table.insert(list, name)
		end
	end
	table.sort(list)
	return list
end

-- Get current profile name
function Profiles:GetCurrent()
	return currentProfile or "Default"
end

-- Switch to a different profile
function Profiles:Switch(profileName)
	if not ddingUI_UFDB or not ddingUI_UFDB.profiles then
		return false, "Database not initialized"
	end

	if not ddingUI_UFDB.profiles[profileName] then
		return false, "Profile not found: " .. profileName
	end

	-- [REFACTOR] 편집모드 중 전환 시 안전 종료 (편집 취소 후 전환)
	if ns.Mover and ns.Mover.SafeExitEditMode then
		ns.Mover:SafeExitEditMode()
	end

	local pKey = GetPlayerKey()
	ddingUI_UFDB.profileKeys[pKey] = profileName
	currentProfile = profileName
	ns.db = ddingUI_UFDB.profiles[profileName]

	-- [SPEC-SWITCH] 수동 전환 시 지연된 자동 전환 취소
	pendingSpecSwitch = nil

	-- Merge defaults
	DeepMerge(ns.defaults, ns.db)

	-- [FIX] 마이그레이션: 프로필 전환 시에도 실행
	if ns.Config and ns.Config.RunMigrations then
		ns.Config:RunMigrations()
	end

	-- Trigger update
	if ns.Update and ns.Update.RefreshAll then
		ns.Update:RefreshAll()
	end

	-- [REFACTOR] 프로필 전환 시 oUF 프레임 위치 재적용
	if ns.Mover and ns.Mover.ApplyPositions then
		ns.Mover:ApplyPositions()
	end

	ns.Print("프로필 전환: " .. profileName)
	return true
end

-- Create a new profile
function Profiles:Create(profileName, copyFrom)
	if not ddingUI_UFDB or not ddingUI_UFDB.profiles then
		return false, "Database not initialized"
	end

	if not profileName or profileName == "" then
		return false, "Invalid profile name"
	end

	if ddingUI_UFDB.profiles[profileName] then
		return false, "Profile already exists: " .. profileName
	end

	-- Create new profile
	if copyFrom and ddingUI_UFDB.profiles[copyFrom] then
		-- Copy from existing profile
		ddingUI_UFDB.profiles[profileName] = DeepCopy(ddingUI_UFDB.profiles[copyFrom])
	else
		-- Create from built-in preset (fallback to defaults)
		ddingUI_UFDB.profiles[profileName] = DeepCopy(ns.builtinPreset or ns.defaults)
	end

	ns.Print("프로필 생성: " .. profileName)
	return true
end

-- Delete a profile
function Profiles:Delete(profileName)
	if not ddingUI_UFDB or not ddingUI_UFDB.profiles then
		return false, "Database not initialized"
	end

	-- [REFACTOR] nil 방어: StaticPopup data 전달 누락 대비
	if not profileName or profileName == "" then
		return false, "Invalid profile name"
	end

	if profileName == "Default" then
		return false, "Cannot delete Default profile"
	end

	if not ddingUI_UFDB.profiles[profileName] then
		return false, "Profile not found: " .. profileName
	end

	-- Check if any character is using this profile
	local usedBy = {}
	for charKey, profName in pairs(ddingUI_UFDB.profileKeys) do
		if profName == profileName then
			table.insert(usedBy, charKey)
		end
	end

	-- Switch affected characters to Default
	for _, charKey in ipairs(usedBy) do
		ddingUI_UFDB.profileKeys[charKey] = "Default"
	end

	-- If current character was using deleted profile, switch to Default
	local wasCurrentProfile = (currentProfile == profileName)
	if wasCurrentProfile then
		-- [REFACTOR] 편집모드 중 삭제 시 안전 종료
		if ns.Mover and ns.Mover.SafeExitEditMode then
			ns.Mover:SafeExitEditMode()
		end
		currentProfile = "Default"
		ns.db = ddingUI_UFDB.profiles["Default"]
		DeepMerge(ns.defaults, ns.db)
	end

	-- Delete the profile
	ddingUI_UFDB.profiles[profileName] = nil

	-- [SPEC-SWITCH] 삭제된 프로필을 참조하는 전문화 매핑 정리
	local spDB = ddingUI_UFDB.global and ddingUI_UFDB.global.specProfiles
	if spDB and spDB.mappings then
		for specID, profName in pairs(spDB.mappings) do
			if profName == profileName then
				spDB.mappings[specID] = nil
			end
		end
	end

	-- [REFACTOR] 현재 프로필이 삭제된 경우 프레임 즉시 갱신
	if wasCurrentProfile then
		if ns.Update and ns.Update.RefreshAll then
			ns.Update:RefreshAll()
		end
		if ns.Mover and ns.Mover.ApplyPositions then
			ns.Mover:ApplyPositions()
		end
	end

	ns.Print("프로필 삭제: " .. profileName)
	return true
end

-- Rename a profile
function Profiles:Rename(oldName, newName)
	if not ddingUI_UFDB or not ddingUI_UFDB.profiles then
		return false, "Database not initialized"
	end

	if oldName == "Default" then
		return false, "Cannot rename Default profile"
	end

	if not newName or newName == "" then
		return false, "Invalid new name"
	end

	if not ddingUI_UFDB.profiles[oldName] then
		return false, "Profile not found: " .. oldName
	end

	if ddingUI_UFDB.profiles[newName] then
		return false, "Profile already exists: " .. newName
	end

	-- Copy profile data
	ddingUI_UFDB.profiles[newName] = ddingUI_UFDB.profiles[oldName]
	ddingUI_UFDB.profiles[oldName] = nil

	-- Update all references
	for charKey, profName in pairs(ddingUI_UFDB.profileKeys) do
		if profName == oldName then
			ddingUI_UFDB.profileKeys[charKey] = newName
		end
	end

	-- Update current profile reference
	if currentProfile == oldName then
		currentProfile = newName
	end

	-- [SPEC-SWITCH] 전문화 매핑에서 이름 갱신
	local spDB = ddingUI_UFDB.global and ddingUI_UFDB.global.specProfiles
	if spDB and spDB.mappings then
		for specID, profName in pairs(spDB.mappings) do
			if profName == oldName then
				spDB.mappings[specID] = newName
			end
		end
	end

	ns.Print("프로필 이름 변경: " .. oldName .. " -> " .. newName)
	return true
end

-- Copy current profile to another
function Profiles:CopyTo(targetProfile)
	if not ddingUI_UFDB or not ddingUI_UFDB.profiles then
		return false, "Database not initialized"
	end

	if not ddingUI_UFDB.profiles[targetProfile] then
		return false, "Target profile not found: " .. targetProfile
	end

	ddingUI_UFDB.profiles[targetProfile] = DeepCopy(ns.db)

	ns.Print("프로필 복사: " .. currentProfile .. " -> " .. targetProfile)
	return true
end

-- Reset current profile to defaults
function Profiles:ResetCurrent()
	if not currentProfile then
		return false, "No current profile"
	end

	ddingUI_UFDB.profiles[currentProfile] = DeepCopy(ns.builtinPreset or ns.defaults)
	ns.db = ddingUI_UFDB.profiles[currentProfile]

	-- Merge defaults (프리셋에 없는 신규 설정값 보충)
	DeepMerge(ns.defaults, ns.db)

	-- Trigger update
	if ns.Update and ns.Update.RefreshAll then
		ns.Update:RefreshAll()
	end

	-- [REFACTOR] 프로필 초기화 시 oUF 프레임 위치 재적용
	if ns.Mover and ns.Mover.ApplyPositions then
		ns.Mover:ApplyPositions()
	end

	ns.Print("프로필 초기화: " .. currentProfile)
	return true
end

-----------------------------------------------
-- Import/Export System
-----------------------------------------------

-- Serialize table to string
local function SerializeTable(tbl, indent)
	indent = indent or ""
	local result = "{\n"
	local nextIndent = indent .. "  "

	for key, value in pairs(tbl) do
		local keyStr
		if type(key) == "number" then
			keyStr = "[" .. key .. "]"
		elseif type(key) == "string" then
			if key:match("^[%a_][%w_]*$") then
				keyStr = key
			else
				keyStr = "[\"" .. key:gsub("\"", "\\\"") .. "\"]"
			end
		else
			keyStr = "[" .. tostring(key) .. "]"
		end

		local valueStr
		if type(value) == "table" then
			valueStr = SerializeTable(value, nextIndent)
		elseif type(value) == "string" then
			valueStr = "\"" .. value:gsub("\"", "\\\""):gsub("\n", "\\n") .. "\""
		elseif type(value) == "boolean" then
			valueStr = value and "true" or "false"
		elseif type(value) == "number" then
			valueStr = tostring(value)
		else
			valueStr = "\"" .. tostring(value) .. "\""
		end

		result = result .. nextIndent .. keyStr .. " = " .. valueStr .. ",\n"
	end

	return result .. indent .. "}"
end

-- Compress string for export (simple base64-like encoding)
local function CompressExport(str)
	-- Remove whitespace for compression
	str = str:gsub("%s+", " ")
	-- Use LibDeflate if available, otherwise just return cleaned string
	return str
end

-- Export current profile
function Profiles:Export()
	if not ns.db then
		return nil, "No profile loaded"
	end

	local data = {
		version = ns.VERSION or "1.0.0",
		profile = currentProfile,
		timestamp = date("%Y-%m-%d %H:%M:%S"),
		settings = ns.db,
	}

	local serialized = SerializeTable(data)
	local compressed = CompressExport(serialized)

	-- Create a simple checksum
	local checksum = 0
	for i = 1, #compressed do
		checksum = (checksum + compressed:byte(i)) % 65536
	end

	return "DDINGUI:" .. checksum .. ":" .. compressed
end

-- Parse import string
local function ParseImportString(str)
	-- Validate format
	local prefix, checksum, data = str:match("^DDINGUI:(%d+):(.+)$")
	if not prefix or not data then
		return nil, "Invalid import format"
	end

	-- Verify checksum
	local calculatedSum = 0
	for i = 1, #data do
		calculatedSum = (calculatedSum + data:byte(i)) % 65536
	end

	if tostring(calculatedSum) ~= checksum then
		return nil, "Checksum mismatch - data may be corrupted"
	end

	-- Try to parse the data
	local func, err = loadstring("return " .. data)
	if not func then
		return nil, "Failed to parse import data: " .. (err or "unknown error")
	end

	-- Execute in protected mode
	local success, result = pcall(func)
	if not success then
		return nil, "Failed to load import data: " .. (result or "unknown error")
	end

	return result
end

-- Import profile from string
function Profiles:Import(importString, targetName)
	local data, err = ParseImportString(importString)
	if not data then
		return false, err
	end

	if not data.settings then
		return false, "Import data has no settings"
	end

	-- Use provided name or generate one
	local profileName = targetName
	if not profileName or profileName == "" then
		profileName = data.profile or "Imported"

		-- Ensure unique name
		local baseName = profileName
		local counter = 1
		while ddingUI_UFDB.profiles[profileName] do
			profileName = baseName .. " (" .. counter .. ")"
			counter = counter + 1
		end
	end

	-- Check if target exists
	if ddingUI_UFDB.profiles[profileName] then
		-- Overwrite existing
		ddingUI_UFDB.profiles[profileName] = DeepCopy(data.settings)
	else
		-- Create new
		ddingUI_UFDB.profiles[profileName] = DeepCopy(data.settings)
	end

	-- Merge defaults to ensure all keys exist
	DeepMerge(ns.defaults, ddingUI_UFDB.profiles[profileName])

	-- [FIX] 마이그레이션: 가져온 프로필에도 실행
	local prevDB = ns.db
	ns.db = ddingUI_UFDB.profiles[profileName]
	if ns.Config and ns.Config.RunMigrations then
		ns.Config:RunMigrations()
	end
	ns.db = prevDB

	ns.Print("프로필 가져오기 완료: " .. profileName)
	return true, profileName
end

-----------------------------------------------
-- Global Settings (cross-profile)
-----------------------------------------------

function Profiles:GetGlobal(key)
	if ddingUI_UFDB and ddingUI_UFDB.global then
		return ddingUI_UFDB.global[key]
	end
	return nil
end

function Profiles:SetGlobal(key, value)
	if ddingUI_UFDB then
		ddingUI_UFDB.global = ddingUI_UFDB.global or {}
		ddingUI_UFDB.global[key] = value
	end
end

-----------------------------------------------
-- Character-Profile Assignment
-----------------------------------------------

-- Get which profile a character is using
function Profiles:GetCharacterProfile(charKey)
	if ddingUI_UFDB and ddingUI_UFDB.profileKeys then
		return ddingUI_UFDB.profileKeys[charKey] or "Default"
	end
	return "Default"
end

-- Set which profile a character should use
function Profiles:SetCharacterProfile(charKey, profileName)
	if ddingUI_UFDB then
		ddingUI_UFDB.profileKeys = ddingUI_UFDB.profileKeys or {}
		ddingUI_UFDB.profileKeys[charKey] = profileName
	end
end

-- Get all characters and their profiles
function Profiles:GetCharacterList()
	local list = {}
	if ddingUI_UFDB and ddingUI_UFDB.profileKeys then
		for charKey, profileName in pairs(ddingUI_UFDB.profileKeys) do
			table.insert(list, {
				character = charKey,
				profile = profileName,
			})
		end
	end
	table.sort(list, function(a, b) return a.character < b.character end)
	return list
end

-----------------------------------------------
-- [SPEC-SWITCH] Spec-Based Profile Auto-Switch
-----------------------------------------------

local specSwitchReady = false
-- pendingSpecSwitch: 파일 상단에 선언됨 (Switch()에서 참조하므로)

-- DB 접근 헬퍼: ddingUI_UFDB.global.specProfiles 보장 (lazy init)
function Profiles:GetSpecProfilesDB()
	if not ddingUI_UFDB or not ddingUI_UFDB.global then return nil end
	if not ddingUI_UFDB.global.specProfiles then
		ddingUI_UFDB.global.specProfiles = {
			enabled = false,
			mappings = {},
		}
	end
	return ddingUI_UFDB.global.specProfiles
end

-- 현재 specID 안전 조회
function Profiles:GetCurrentSpecID()
	local specIndex = GetSpecialization and GetSpecialization()
	if not specIndex then return nil end
	local specID = GetSpecializationInfo(specIndex)
	return specID
end

-- 전문화 변경 핸들러
function Profiles:OnSpecChanged()
	if not specSwitchReady then return end

	local spDB = self:GetSpecProfilesDB()
	if not spDB or not spDB.enabled then return end

	local specID = self:GetCurrentSpecID()
	if not specID then return end

	local mappedProfile = spDB.mappings and spDB.mappings[specID]
	if not mappedProfile or mappedProfile == "" then return end

	-- 이미 해당 프로필이면 스킵
	if mappedProfile == self:GetCurrent() then return end

	-- 프로필 존재 확인
	if not ddingUI_UFDB.profiles[mappedProfile] then
		ns.Print("|cffff4444전문화 프로필 전환 실패:|r '"
			.. mappedProfile .. "' 프로필이 존재하지 않습니다.")
		return
	end

	-- 전투 중이면 지연
	if InCombatLockdown() then
		pendingSpecSwitch = mappedProfile
		ns.Print("전투 종료 후 프로필 전환 예정: " .. mappedProfile)
		return
	end

	-- 즉시 전환
	self:Switch(mappedProfile)
	ns.Print("전문화 변경 → 프로필 전환: " .. mappedProfile)
end

-- 전투 종료 시 지연 전환 처리
local function OnCombatEndSpecSwitch()
	if not pendingSpecSwitch then return end

	-- 전투 중 전문화가 다시 바뀌었을 수 있으므로 재확인
	local spDB = Profiles:GetSpecProfilesDB()
	if spDB and spDB.enabled then
		local specID = Profiles:GetCurrentSpecID()
		if specID then
			local currentMapping = spDB.mappings and spDB.mappings[specID]
			if currentMapping and currentMapping ~= "" then
				pendingSpecSwitch = currentMapping
			end
		end
	end

	-- 프로필 존재 확인
	if not ddingUI_UFDB.profiles[pendingSpecSwitch] then
		ns.Print("|cffff4444전문화 프로필 전환 실패:|r '"
			.. pendingSpecSwitch .. "' 프로필이 존재하지 않습니다.")
		pendingSpecSwitch = nil
		return
	end

	Profiles:Switch(pendingSpecSwitch)
	ns.Print("전투 종료 → 프로필 전환: " .. pendingSpecSwitch)
	pendingSpecSwitch = nil
end

-- 이벤트 등록 (Initialize()에서 호출)
function Profiles:InitSpecSwitch()
	-- PLAYER_SPECIALIZATION_CHANGED 등록
	ns.RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", function()
		Profiles:OnSpecChanged()
	end)

	-- PLAYER_REGEN_ENABLED (전투 종료 시 지연 전환)
	ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
		if pendingSpecSwitch then
			OnCombatEndSpecSwitch()
		end
	end)

	-- 로그인 시 첫 1회 체크 (PLAYER_ENTERING_WORLD)
	local initialSpecChecked = false
	ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
		if not initialSpecChecked then
			initialSpecChecked = true
			C_Timer.After(0.5, function()
				Profiles:OnSpecChanged()
			end)
		end
	end)

	specSwitchReady = true
	ns.Debug("Spec-switch initialized")
end

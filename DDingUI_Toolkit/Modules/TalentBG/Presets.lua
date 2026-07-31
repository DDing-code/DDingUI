--[[
    DDingToolKit - TalentBG Presets
    텍스처 프리셋 (SavedVariables에서만 로드)
]]

local addonName, ns = ...

-- 프리셋 관리
ns.TalentBG_Presets = {}

local INTERFACE_ROOT = "Interface\\"
local DEFAULT_FOLDER = "DDingUI_Backgrounds"
local LEGACY_BASE_PATH = "Interface\\AddOns\\DDingUI_Toolkit\\Media\\Backgrounds\\"

local function NormalizeFolderName(folderName)
    folderName = tostring(folderName or "")
    folderName = folderName:gsub("/", "\\")
    folderName = folderName:gsub("^%s+", ""):gsub("%s+$", "")
    folderName = folderName:gsub("^Interface\\+", "")
    folderName = folderName:gsub("^\\+", ""):gsub("\\+$", "")
    folderName = folderName:gsub("\\+", "\\")
    folderName = folderName:gsub("[<>:\"|%?%*]", "")

    if folderName == "" or folderName:find("..", 1, true) then
        return DEFAULT_FOLDER
    end
    return folderName
end

local function NormalizeFileName(fileName)
    fileName = tostring(fileName or "")
    fileName = fileName:gsub("/", "\\")
    fileName = fileName:match("([^\\]+)$") or fileName
    fileName = fileName:gsub("^%s+", ""):gsub("%s+$", "")
    fileName = fileName:gsub("%.[Tt][Gg][Aa]$", "")
    fileName = fileName:gsub("%.[Bb][Ll][Pp]$", "")
    fileName = fileName:gsub("[<>:\"|%?%*]", "")
    return fileName
end

function ns.TalentBG_Presets:GetFolderName()
    local db = ns.db and ns.db.global and ns.db.global.TalentBG
    return NormalizeFolderName(db and db.customFolder)
end

function ns.TalentBG_Presets:SetFolderName(folderName)
    local db = ns.db and ns.db.global and ns.db.global.TalentBG
    if not db then return DEFAULT_FOLDER, false end

    local normalized = NormalizeFolderName(folderName)
    local changed = normalized ~= self:GetFolderName()
    db.customFolder = normalized
    return normalized, changed
end

-- 프리셋 목록 가져오기
function ns.TalentBG_Presets:GetPresets()
    local presets = {}
    local addedPaths = {}  -- 중복 방지

    -- SavedVariables에서 사용자 추가 배경 로드
    if ns.db and ns.db.global and ns.db.global.TalentBG and ns.db.global.TalentBG.customPaths then
        for _, fileName in ipairs(ns.db.global.TalentBG.customPaths) do
            if fileName and fileName ~= "" and not addedPaths[fileName] then
                table.insert(presets, {
                    name = fileName,
                    path = self:GetBasePath() .. fileName,
                    category = "custom",
                })
                addedPaths[fileName] = true
            end
        end
    end

    return presets
end

-- 커스텀 텍스처 추가
function ns.TalentBG_Presets:AddCustomTexture(fileName)
    if not fileName or fileName == "" then
        return false
    end

    fileName = NormalizeFileName(fileName)
    if fileName == "" then return false end

    if not ns.db or not ns.db.global or not ns.db.global.TalentBG then return false end
    if not ns.db.global.TalentBG.customPaths then
        ns.db.global.TalentBG.customPaths = {}
    end

    -- 중복 확인
    for _, path in ipairs(ns.db.global.TalentBG.customPaths) do
        if path:lower() == fileName:lower() then
            return false
        end
    end

    table.insert(ns.db.global.TalentBG.customPaths, fileName)
    return true
end

-- 커스텀 텍스처 제거
function ns.TalentBG_Presets:RemoveCustomTexture(fileName)
    if not ns.db.global.TalentBG.customPaths then
        return false
    end

    for i, path in ipairs(ns.db.global.TalentBG.customPaths) do
        if path:lower() == tostring(fileName):lower() then
            table.remove(ns.db.global.TalentBG.customPaths, i)
            return true
        end
    end

    return false
end

-- 기본 경로 가져오기
function ns.TalentBG_Presets:GetBasePath()
    return INTERFACE_ROOT .. self:GetFolderName() .. "\\"
end

function ns.TalentBG_Presets:GetLegacyBasePath()
    return LEGACY_BASE_PATH
end

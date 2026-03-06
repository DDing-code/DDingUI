--[[
    DDingToolKit - TalentBG Presets
    텍스처 프리셋 (SavedVariables에서만 로드)
]]

local addonName, ns = ...

-- 프리셋 관리
ns.TalentBG_Presets = {}

local basePath = "Interface\\AddOns\\DDingUI_Toolkit\\Media\\Backgrounds\\"

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
                    path = basePath .. fileName,
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

    -- 확장자 제거
    fileName = fileName:gsub("%.tga$", ""):gsub("%.blp$", "")

    if not ns.db or not ns.db.global or not ns.db.global.TalentBG then return false end
    if not ns.db.global.TalentBG.customPaths then
        ns.db.global.TalentBG.customPaths = {}
    end

    -- 중복 확인
    for _, path in ipairs(ns.db.global.TalentBG.customPaths) do
        if path == fileName then
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
        if path == fileName then
            table.remove(ns.db.global.TalentBG.customPaths, i)
            return true
        end
    end

    return false
end

-- 기본 경로 가져오기
function ns.TalentBG_Presets:GetBasePath()
    return basePath
end

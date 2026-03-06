------------------------------------------------------
-- DDingUI_Controller :: Registry
-- Font/Texture registry with LibSharedMedia integration
------------------------------------------------------
local _, Controller = ...
Controller = Controller or {}
_G.DDingUI_Controller = Controller

local LSM = LibStub("LibSharedMedia-3.0")

------------------------------------------------------
-- LSM custom media registration
------------------------------------------------------
-- DDingUI 기본 폰트를 LSM에 등록
LSM:Register("font", "DDingUI 기본 (2002)", [[Fonts\2002.TTF]])
LSM:Register("font", "WoW 기본 (Friz)", [[Fonts\FRIZQT__.TTF]])
LSM:Register("statusbar", "DDingUI Flat", [[Interface\Buttons\WHITE8x8]])

------------------------------------------------------
-- Registry API
------------------------------------------------------

--- 사용 가능한 폰트 목록 반환 (LSM 등록된 전체)
--- @return table { {name, path}, ... } 정렬된 목록
function Controller:GetFontList()
    local fonts = {}
    local hash = LSM:HashTable("font")
    for name, path in pairs(hash) do
        fonts[#fonts + 1] = { name = name, path = path }
    end
    table.sort(fonts, function(a, b) return a.name < b.name end)
    return fonts
end

--- 사용 가능한 상태바 텍스처 목록 반환
--- @return table { {name, path}, ... } 정렬된 목록
function Controller:GetTextureList()
    local textures = {}
    local hash = LSM:HashTable("statusbar")
    for name, path in pairs(hash) do
        textures[#textures + 1] = { name = name, path = path }
    end
    table.sort(textures, function(a, b) return a.name < b.name end)
    return textures
end

--- LSM 이름 → 실제 파일 경로 해석
--- @param mediaType string "font" | "statusbar"
--- @param nameOrPath string  LSM 이름 또는 파일 경로
--- @return string  실제 파일 경로
function Controller:ResolvePath(mediaType, nameOrPath)
    if not nameOrPath then return nil end
    -- 이미 파일 경로이면 그대로 반환
    if nameOrPath:find("[/\\]") then
        return nameOrPath
    end
    -- LSM 이름이면 해석
    return LSM:Fetch(mediaType, nameOrPath) or nameOrPath
end

--- 현재 설정을 StyleLib에 적용
function Controller:ApplyToStyleLib()
    local SL = _G.DDingUI_StyleLib
    if not SL then return end

    local db = self.db
    if not db then return end

    -- 폰트 적용
    local fontPath = self:ResolvePath("font", db.font.primary)
    if fontPath then
        SL.Font.path = fontPath
    end

    local secondaryPath = self:ResolvePath("font", db.font.secondary)
    if secondaryPath then
        SL.Font.default = secondaryPath
    end

    -- 크기 배율 적용
    SL.Font.sizeScale = db.font.sizeScale or 1.0

    -- 텍스처 적용
    local flatPath = self:ResolvePath("statusbar", db.texture.flat)
    if flatPath then
        SL.Textures.flat = flatPath
    end

    -- 콜백 발생 — 모든 등록된 애드온에 변경 통보
    if SL.Fire then
        SL:Fire("MediaChanged", "all")
    end
end

------------------------------------------------------
-- DDingUI_Controller :: Settings
-- Global font/texture settings UI panel
------------------------------------------------------
local Controller = _G.DDingUI_Controller
if not Controller then return end

local SL = _G.DDingUI_StyleLib
if not SL then return end

local C = SL.Colors
local F = SL.Font
local S = SL.Spacing

local ADDON_NAME = "CDM"  -- accent preset key for Controller UI

------------------------------------------------------
-- Helpers
------------------------------------------------------
local function u(tbl) return unpack(tbl) end

--- 폰트 목록을 드롭다운 옵션으로 변환
local function BuildFontOptions()
    local fonts = Controller:GetFontList()
    local options = {}
    for _, f in ipairs(fonts) do
        options[#options + 1] = { text = f.name, value = f.path }
    end
    return options
end

--- 텍스처 목록을 드롭다운 옵션으로 변환
local function BuildTextureOptions()
    local textures = Controller:GetTextureList()
    local options = {}
    for _, t in ipairs(textures) do
        options[#options + 1] = { text = t.name, value = t.path }
    end
    return options
end

--- 현재 폰트 경로에 해당하는 LSM 이름 찾기
local function FindFontName(path)
    if not path then return nil end
    local LSM = LibStub("LibSharedMedia-3.0")
    local hash = LSM:HashTable("font")
    for name, p in pairs(hash) do
        if p == path then return name end
    end
    return path  -- fallback: 경로 그대로 반환
end

--- 현재 텍스처 경로에 해당하는 LSM 이름 찾기
local function FindTextureName(path)
    if not path then return nil end
    local LSM = LibStub("LibSharedMedia-3.0")
    local hash = LSM:HashTable("statusbar")
    for name, p in pairs(hash) do
        if p == path then return name end
    end
    return path
end

------------------------------------------------------
-- Settings Panel
------------------------------------------------------
local panel       -- panel result table
local previewText -- preview FontString
local previewBar  -- preview StatusBar

function Controller:ToggleSettings()
    if panel and panel.frame then
        if panel.frame:IsShown() then
            panel.frame:Hide()
        else
            panel.frame:Show()
        end
        return
    end

    -- StyleLib.CreateSettingsPanel 사용
    panel = SL.CreateSettingsPanel(ADDON_NAME, "DDingUI Controller", "1.0.0", {
        width = 520,
        height = 460,
        minWidth = 420,
        minHeight = 360,
        menuWidth = 140,
    })

    local frame = panel.frame
    local contentChild = panel.contentChild

    -- 트리 메뉴 설정
    local menuData = {
        { text = "폰트",   key = "font" },
        { text = "텍스처", key = "texture" },
    }

    local contentPanels = {}
    local db = self.db

    --------------------------------------------------------
    -- 폰트 설정 패널
    --------------------------------------------------------
    local fontPanel = CreateFrame("Frame", nil, contentChild)
    fontPanel:SetAllPoints()
    fontPanel:Hide()
    contentPanels["font"] = fontPanel

    local yOff = -S.contentPad

    -- 섹션 헤더: 메인 폰트
    local hdr1 = SL.CreateSectionHeader(fontPanel, ADDON_NAME, "메인 폰트 (한글)", { isFirst = true })
    hdr1:SetPoint("TOPLEFT", fontPanel, "TOPLEFT", S.contentPad, yOff)
    hdr1:SetPoint("RIGHT", fontPanel, "RIGHT", -S.contentPad, 0)
    yOff = yOff - hdr1:GetHeight()

    -- 메인 폰트 드롭다운
    local fontOptions = BuildFontOptions()
    local fontDropdown = SL.CreateDropdown(fontPanel, ADDON_NAME, "폰트", fontOptions,
        FindFontName(db.font.primary), {
            width = 200,
            onChange = function(value)
                db.font.primary = value
                Controller:SaveAndApply()
                Controller:UpdatePreview()
            end,
        })
    fontDropdown:SetPoint("TOPLEFT", hdr1, "BOTTOMLEFT", 0, -S.controlGap)
    yOff = yOff - fontDropdown:GetHeight() - S.controlGap

    -- 섹션 헤더: 보조 폰트
    local hdr2 = SL.CreateSectionHeader(fontPanel, ADDON_NAME, "보조 폰트 (영문/숫자)")
    hdr2:SetPoint("TOPLEFT", fontDropdown, "BOTTOMLEFT", 0, -S.sectionGap)
    hdr2:SetPoint("RIGHT", fontPanel, "RIGHT", -S.contentPad, 0)

    -- 보조 폰트 드롭다운
    local secFontDropdown = SL.CreateDropdown(fontPanel, ADDON_NAME, "폰트", fontOptions,
        FindFontName(db.font.secondary), {
            width = 200,
            onChange = function(value)
                db.font.secondary = value
                Controller:SaveAndApply()
                Controller:UpdatePreview()
            end,
        })
    secFontDropdown:SetPoint("TOPLEFT", hdr2, "BOTTOMLEFT", 0, -S.controlGap)

    -- 섹션 헤더: 크기 배율
    local hdr3 = SL.CreateSectionHeader(fontPanel, ADDON_NAME, "글로벌 크기 배율")
    hdr3:SetPoint("TOPLEFT", secFontDropdown, "BOTTOMLEFT", 0, -S.sectionGap)
    hdr3:SetPoint("RIGHT", fontPanel, "RIGHT", -S.contentPad, 0)

    -- 크기 배율 슬라이더
    local scaleSlider = SL.CreateSlider(fontPanel, ADDON_NAME, "배율",
        0.8, 1.5, 0.05, db.font.sizeScale, {
            width = 250,
            onChange = function(value)
                db.font.sizeScale = value
                Controller:SaveAndApply()
                Controller:UpdatePreview()
            end,
        })
    scaleSlider:SetPoint("TOPLEFT", hdr3, "BOTTOMLEFT", 0, -S.controlGap)

    -- 미리보기 영역
    local hdr4 = SL.CreateSectionHeader(fontPanel, ADDON_NAME, "미리보기")
    hdr4:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -S.sectionGap)
    hdr4:SetPoint("RIGHT", fontPanel, "RIGHT", -S.contentPad, 0)

    -- 미리보기 배경
    local previewBG = CreateFrame("Frame", nil, fontPanel, "BackdropTemplate")
    previewBG:SetSize(300, 80)
    previewBG:SetPoint("TOPLEFT", hdr4, "BOTTOMLEFT", 0, -S.controlGap)
    previewBG:SetBackdrop({
        bgFile = [[Interface\Buttons\WHITE8x8]],
        edgeFile = [[Interface\Buttons\WHITE8x8]],
        edgeSize = 1,
    })
    previewBG:SetBackdropColor(u(C.bg.sidebar))
    previewBG:SetBackdropBorderColor(u(C.border.default))

    -- 미리보기 텍스트 (메인 폰트)
    previewText = previewBG:CreateFontString(nil, "OVERLAY")
    previewText:SetPoint("TOPLEFT", 10, -10)
    previewText:SetPoint("RIGHT", -10, 0)
    previewText:SetJustifyH("LEFT")
    previewText:SetText("가나다라마바사 ABCDEFG 1234567890")

    -- 미리보기 텍스트 (보조 폰트)
    local previewText2 = previewBG:CreateFontString(nil, "OVERLAY")
    previewText2:SetPoint("TOPLEFT", previewText, "BOTTOMLEFT", 0, -6)
    previewText2:SetPoint("RIGHT", -10, 0)
    previewText2:SetJustifyH("LEFT")
    previewText2:SetText("Secondary: The quick brown fox")
    Controller._previewText2 = previewText2

    Controller:UpdatePreview()

    -- 기본값 복원 버튼
    local resetBtn = SL.CreateButton(fontPanel, ADDON_NAME, "기본값 복원", function()
        Controller:ResetToDefaults()
        -- 드롭다운/슬라이더 UI 갱신은 ResetToDefaults → RefreshSettingsUI에서 처리
    end, { width = 120, height = 28 })
    resetBtn:SetPoint("TOPLEFT", previewBG, "BOTTOMLEFT", 0, -S.sectionGap)

    --------------------------------------------------------
    -- 텍스처 설정 패널
    --------------------------------------------------------
    local texPanel = CreateFrame("Frame", nil, contentChild)
    texPanel:SetAllPoints()
    texPanel:Hide()
    contentPanels["texture"] = texPanel

    -- 섹션 헤더: 배경 텍스처
    local thdr1 = SL.CreateSectionHeader(texPanel, ADDON_NAME, "배경/단색 텍스처", { isFirst = true })
    thdr1:SetPoint("TOPLEFT", texPanel, "TOPLEFT", S.contentPad, -S.contentPad)
    thdr1:SetPoint("RIGHT", texPanel, "RIGHT", -S.contentPad, 0)

    local texOptions = BuildTextureOptions()
    local flatDropdown = SL.CreateDropdown(texPanel, ADDON_NAME, "텍스처", texOptions,
        FindTextureName(db.texture.flat), {
            width = 200,
            onChange = function(value)
                db.texture.flat = value
                Controller:SaveAndApply()
                Controller:UpdateTexturePreview()
            end,
        })
    flatDropdown:SetPoint("TOPLEFT", thdr1, "BOTTOMLEFT", 0, -S.controlGap)

    -- 섹션 헤더: 상태바 텍스처
    local thdr2 = SL.CreateSectionHeader(texPanel, ADDON_NAME, "상태바 텍스처")
    thdr2:SetPoint("TOPLEFT", flatDropdown, "BOTTOMLEFT", 0, -S.sectionGap)
    thdr2:SetPoint("RIGHT", texPanel, "RIGHT", -S.contentPad, 0)

    local barDropdown = SL.CreateDropdown(texPanel, ADDON_NAME, "텍스처", texOptions,
        FindTextureName(db.texture.statusBar), {
            width = 200,
            onChange = function(value)
                db.texture.statusBar = value
                Controller:SaveAndApply()
                Controller:UpdateTexturePreview()
            end,
        })
    barDropdown:SetPoint("TOPLEFT", thdr2, "BOTTOMLEFT", 0, -S.controlGap)

    -- 텍스처 미리보기
    local thdr3 = SL.CreateSectionHeader(texPanel, ADDON_NAME, "미리보기")
    thdr3:SetPoint("TOPLEFT", barDropdown, "BOTTOMLEFT", 0, -S.sectionGap)
    thdr3:SetPoint("RIGHT", texPanel, "RIGHT", -S.contentPad, 0)

    -- 상태바 미리보기
    previewBar = CreateFrame("StatusBar", nil, texPanel)
    previewBar:SetSize(280, 20)
    previewBar:SetPoint("TOPLEFT", thdr3, "BOTTOMLEFT", 0, -S.controlGap)
    previewBar:SetMinMaxValues(0, 100)
    previewBar:SetValue(72)
    local from = SL.GetAccent(ADDON_NAME)
    previewBar:SetStatusBarColor(from[1], from[2], from[3], 1)
    Controller:UpdateTexturePreview()

    -- 상태바 배경
    local barBG = previewBar:CreateTexture(nil, "BACKGROUND")
    barBG:SetAllPoints()
    barBG:SetColorTexture(u(C.bg.input))
    Controller._previewBarBG = barBG

    -- 텍스처 기본값 복원 버튼
    local texResetBtn = SL.CreateButton(texPanel, ADDON_NAME, "기본값 복원", function()
        db.texture.statusBar = DDingUI_ControllerDefaults.texture.statusBar
        db.texture.flat = DDingUI_ControllerDefaults.texture.flat
        Controller:SaveAndApply()
        Controller:UpdateTexturePreview()
    end, { width = 120, height = 28 })
    texResetBtn:SetPoint("TOPLEFT", previewBar, "BOTTOMLEFT", 0, -S.sectionGap)

    --------------------------------------------------------
    -- 트리 메뉴 연결
    --------------------------------------------------------
    local tree = SL.CreateTreeMenu(panel.treeFrame, ADDON_NAME, menuData, {
        defaultKey = "font",
        onSelect = function(key)
            for k, p in pairs(contentPanels) do
                p:SetShown(k == key)
            end
        end,
    })

    -- 초기 표시
    contentPanels["font"]:Show()

    -- UI 참조 저장 (RefreshSettingsUI용)
    Controller._ui = {
        fontDropdown    = fontDropdown,
        secFontDropdown = secFontDropdown,
        scaleSlider     = scaleSlider,
        flatDropdown    = flatDropdown,
        barDropdown     = barDropdown,
    }

    frame:Show()
end

------------------------------------------------------
-- Preview update
------------------------------------------------------
function Controller:UpdatePreview()
    if not previewText then return end
    local db = self.db
    if not db then return end

    local fontPath = self:ResolvePath("font", db.font.primary) or F.path
    local fontSize = math.floor((F.normal or 13) * (db.font.sizeScale or 1.0) + 0.5)

    pcall(function()
        previewText:SetFont(fontPath, fontSize, "")
        previewText:SetTextColor(u(C.text.normal))
    end)

    -- 보조 폰트 미리보기
    if self._previewText2 then
        local secPath = self:ResolvePath("font", db.font.secondary) or F.default
        pcall(function()
            self._previewText2:SetFont(secPath, fontSize, "")
            self._previewText2:SetTextColor(u(C.text.dim))
        end)
    end
end

function Controller:UpdateTexturePreview()
    if not previewBar then return end
    local db = self.db
    if not db then return end

    local barTexPath = self:ResolvePath("statusbar", db.texture.statusBar) or [[Interface\Buttons\WHITE8x8]]
    pcall(function()
        previewBar:SetStatusBarTexture(barTexPath)
    end)
end

------------------------------------------------------
-- RefreshSettingsUI (기본값 복원 후 UI 동기화)
------------------------------------------------------
function Controller:RefreshSettingsUI()
    local ui = self._ui
    if not ui then return end
    local db = self.db
    if not db then return end

    if ui.fontDropdown and ui.fontDropdown.SetValue then
        ui.fontDropdown:SetValue(db.font.primary)
    end
    if ui.secFontDropdown and ui.secFontDropdown.SetValue then
        ui.secFontDropdown:SetValue(db.font.secondary)
    end
    if ui.scaleSlider and ui.scaleSlider.slider then
        ui.scaleSlider.slider:SetValue(db.font.sizeScale)
    end
    if ui.flatDropdown and ui.flatDropdown.SetValue then
        ui.flatDropdown:SetValue(db.texture.flat)
    end
    if ui.barDropdown and ui.barDropdown.SetValue then
        ui.barDropdown:SetValue(db.texture.statusBar)
    end

    self:UpdatePreview()
    self:UpdateTexturePreview()
end

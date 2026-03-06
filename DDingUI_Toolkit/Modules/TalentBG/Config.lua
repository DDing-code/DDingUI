--[[
    DDingToolKit - TalentBG Config
    StyleLib 기반 TalentBG Settings Panel
    -- [REFACTOR] Phase 5: StyleLib 리팩토링
]]

local addonName, ns = ...
local L = ns.L

-- StyleLib 참조
local Lib = LibStub("DDingUI-StyleLib-1.0")
local C    = Lib.Colors
local F    = Lib.Font
local ADDON_KEY = "MJToolkit"
local SOLID     = "Interface\\Buttons\\WHITE8x8"
local CHAT_PREFIX = (Lib and Lib.GetChatPrefix) and Lib.GetChatPrefix("MJToolkit", "Toolkit") or "|cffffffffDDing|r|cffffa300UI|r |cff33bfe6Toolkit|r: " -- [STYLE]
local CHAT_PREFIX_ERR = "|cFFFF0000" .. ((Lib and Lib.GetChatPrefix) and Lib.GetChatPrefix("MJToolkit", "Toolkit") or "|cffffffffDDing|r|cffffa300UI|r |cff33bfe6Toolkit|r: ") -- [STYLE]

local TalentBG  -- forward ref
local Presets   -- forward ref

local function u(t) return unpack(t) end

------------------------------------------------------
-- TextureGrid (자체 구현)
------------------------------------------------------
local THUMB_W, THUMB_H = 96, 48
local GRID_COLS, GRID_GAP, GRID_PAD = 3, 8, 8

local function CreateThumbnailButton(parent)
    local accentFrom = Lib.GetAccent(ADDON_KEY)  -- returns from color table directly

    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(THUMB_W, THUMB_H)
    btn:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
    btn:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    btn:SetBackdropBorderColor(u(C.border.default))
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 2, -2)
    tex:SetPoint("BOTTOMRIGHT", -2, 2)
    btn.texture = tex

    local sel = btn:CreateTexture(nil, "OVERLAY")
    sel:SetAllPoints()
    sel:SetColorTexture(u(C.bg.selected))
    sel:Hide()
    btn.selectedOverlay = sel

    local chk = btn:CreateTexture(nil, "OVERLAY")
    chk:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    chk:SetSize(24, 24)
    chk:SetPoint("CENTER")
    chk:Hide()
    btn.checkMark = chk

    btn:SetScript("OnEnter", function(self)
        if not self.isSelected then
            self:SetBackdropBorderColor(u(C.border.active))
            self:SetBackdropColor(0.15, 0.15, 0.15, 0.95)
        end
        if self.onHover then self.onHover(self, self.texturePath, self.textureName) end
    end)
    btn:SetScript("OnLeave", function(self)
        if not self.isSelected then
            self:SetBackdropBorderColor(u(C.border.default))
            self:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
        end
        if self.onHoverEnd then self.onHoverEnd(self) end
    end)
    btn:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            if self.onRightClick then self.onRightClick(self, self.texturePath, self.textureName) end
        else
            if self.onClick then self.onClick(self, self.texturePath, self.textureName) end
        end
    end)

    function btn:SetSelected(selected)
        self.isSelected = selected
        if selected then
            self.selectedOverlay:Show()
            self.checkMark:Show()
            self:SetBackdropBorderColor(u(accentFrom))
        else
            self.selectedOverlay:Hide()
            self.checkMark:Hide()
            self:SetBackdropBorderColor(u(C.border.default))
        end
    end

    function btn:SetTextureData(path, name)
        self.texturePath = path
        self.textureName = name
        self.texture:SetTexture(path)
    end

    return btn
end

local function CreateTextureGrid(parent, w, h)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(w, h)
    frame:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
    frame:SetBackdropColor(u(C.bg.sidebar))
    frame:SetBackdropBorderColor(u(C.border.default))

    local scrollFrame = CreateFrame("ScrollFrame", nil, frame)
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -20, 5)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    local gridW = GRID_COLS * (THUMB_W + GRID_GAP) + GRID_PAD * 2
    scrollChild:SetWidth(gridW)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    -- 스크롤바
    local sb = CreateFrame("Slider", nil, frame, "BackdropTemplate")
    sb:SetPoint("TOPRIGHT", -3, -5)
    sb:SetPoint("BOTTOMRIGHT", -3, 5)
    sb:SetWidth(12)
    sb:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
    sb:SetBackdropColor(u(C.bg.input))
    sb:SetBackdropBorderColor(u(C.border.default))
    sb:SetOrientation("VERTICAL")
    sb:SetMinMaxValues(0, 1)
    sb:SetValue(0)
    sb:SetValueStep(20)
    sb:SetObeyStepOnDrag(false)

    local thumb = sb:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(u(Lib.GetAccent(ADDON_KEY)))
    thumb:SetSize(10, 40)
    sb:SetThumbTexture(thumb)

    sb:SetScript("OnValueChanged", function(_, val) scrollFrame:SetVerticalScroll(val) end)
    scrollFrame:SetScript("OnMouseWheel", function(_, delta)
        local cur = sb:GetValue()
        local mn, mx = sb:GetMinMaxValues()
        sb:SetValue(delta > 0 and math.max(mn, cur - 40) or math.min(mx, cur + 40))
    end)
    scrollFrame:EnableMouseWheel(true)

    frame.scrollFrame = scrollFrame
    frame.scrollChild = scrollChild
    frame.scrollbar = sb
    frame.buttons = {}
    frame.selectedButton = nil
    frame.textures = {}

    function frame:LayoutThumbnails()
        local n = #self.textures
        local rows = math.ceil(n / GRID_COLS)
        local cH = rows * (THUMB_H + GRID_GAP) + GRID_PAD * 2
        local sH = self.scrollFrame:GetHeight()
        if sH < 10 then sH = 350 end
        self.scrollChild:SetHeight(math.max(cH, sH))

        for i, btn in ipairs(self.buttons) do
            if i <= n then
                local r = math.floor((i - 1) / GRID_COLS)
                local c = (i - 1) % GRID_COLS
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", self.scrollChild, "TOPLEFT",
                    GRID_PAD + c * (THUMB_W + GRID_GAP),
                    -GRID_PAD - r * (THUMB_H + GRID_GAP))
                btn:Show()
            else
                btn:Hide()
            end
        end

        local maxS = math.max(0, cH - self.scrollFrame:GetHeight())
        self.scrollbar:SetMinMaxValues(0, maxS)
        self.scrollbar:SetValue(0)
        if maxS == 0 then self.scrollbar:Hide() else self.scrollbar:Show() end
    end

    function frame:SetTextures(textures)
        self.textures = textures or {}
        while #self.buttons < #self.textures do
            local btn = CreateThumbnailButton(self.scrollChild)
            btn.onClick    = function(b) self:SelectTexture(b) end
            btn.onRightClick = function(b, p, n) if self.onTextureRightClick then self.onTextureRightClick(p, n) end end
            btn.onHover      = function(b, p, n) if self.onTextureHover then self.onTextureHover(p, n) end end
            btn.onHoverEnd   = function(b) if self.onTextureHoverEnd then self.onTextureHoverEnd() end end
            table.insert(self.buttons, btn)
        end
        for i, td in ipairs(self.textures) do
            self.buttons[i]:SetTextureData(td.path, td.name)
            self.buttons[i]:SetSelected(false)
        end
        self:LayoutThumbnails()
    end

    function frame:SelectTexture(button)
        if self.selectedButton then self.selectedButton:SetSelected(false) end
        self.selectedButton = button
        button:SetSelected(true)
        if self.onTextureSelected then self.onTextureSelected(button.texturePath, button.textureName) end
    end

    function frame:SelectTextureByPath(path)
        for _, btn in ipairs(self.buttons) do
            if btn.texturePath == path then self:SelectTexture(btn); return true end
        end
        return false
    end

    function frame:GetSelectedTexturePath()
        return self.selectedButton and self.selectedButton.texturePath or nil
    end

    frame:SetScript("OnShow", function(self)
        C_Timer.After(0.01, function()
            if self.textures and #self.textures > 0 then self:LayoutThumbnails() end
        end)
    end)

    return frame
end

------------------------------------------------------
-- PreviewPanel (자체 구현)
------------------------------------------------------
local function CreatePreviewPanel(parent, w, h)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(w, h)
    frame:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
    frame:SetBackdropColor(u(C.bg.sidebar))
    frame:SetBackdropBorderColor(u(C.border.default))

    local title = frame:CreateFontString(nil, "OVERLAY")
    title:SetFont(F.path, F.section, "")
    title:SetPoint("TOPLEFT", 10, -10)
    title:SetText(L["TALENTBG_PREVIEW"] or "Preview")
    title:SetTextColor(u(C.text.normal))

    local inner = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    inner:SetPoint("TOPLEFT", 10, -35)
    inner:SetPoint("BOTTOMRIGHT", -10, 35)
    inner:SetBackdrop({ bgFile = SOLID, edgeFile = SOLID, edgeSize = 1 })
    inner:SetBackdropColor(0, 0, 0, 1)
    inner:SetBackdropBorderColor(u(C.border.default))

    local tex = inner:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 2, -2)
    tex:SetPoint("BOTTOMRIGHT", -2, 2)
    frame.texture = tex

    local pathText = frame:CreateFontString(nil, "OVERLAY")
    pathText:SetFont(F.path, F.small, "")
    pathText:SetPoint("BOTTOMLEFT", 10, 10)
    pathText:SetPoint("BOTTOMRIGHT", -10, 10)
    pathText:SetJustifyH("LEFT")
    pathText:SetTextColor(u(C.text.dim))
    pathText:SetText("")
    frame.pathText = pathText

    function frame:UpdateTexture(texturePath)
        if not texturePath or texturePath == "" then
            self.texture:SetTexture(nil)
            self.pathText:SetText(L["TALENTBG_NO_SELECTION"] or "No selection")
            return
        end
        self.texture:SetTexture(texturePath)
        self.pathText:SetText(texturePath)
    end

    return frame
end

------------------------------------------------------
-- TalentBG:CreateConfigPanel (StyleLib 기반)
------------------------------------------------------
local function OnConfigReady()
    TalentBG = ns.TalentBG or (ns.modules and ns.modules["TalentBG"])
    Presets  = ns.TalentBG_Presets
    if not TalentBG then return end

    function TalentBG:CreateConfigPanel(container)
        local cW = container:GetWidth()
        local cH = container:GetHeight()
        -- Config_UI 에서 SetSize 호출하므로 정상값이지만, 안전 fallback
        if cW < 100 then cW = 590 end
        if cH < 100 then cH = 540 end

        -- 왼쪽 패널 (모드 + 그리드)
        local leftW = 350

        -- 모드 드롭다운
        local modeOpts = {
            { text = L["TALENTBG_MODE_SPEC"],   value = "spec" },
            { text = L["TALENTBG_MODE_CLASS"],  value = "class" },
            { text = L["TALENTBG_MODE_GLOBAL"], value = "global" },
        }
        local modeDD = Lib.CreateDropdown(container, ADDON_KEY, L["TALENTBG_SCOPE"] or "Scope", modeOpts,
            self.profileDB and self.profileDB.mode or "spec", {
            width = 200,
            onChange = function(value)
                self:SetMode(value)
                local bg = self:GetCurrentBackground()
                if container.textureGrid then container.textureGrid:SelectTextureByPath(bg) end
                if container.preview then container.preview:UpdateTexture(bg) end
                container.selectedTexture = bg
            end,
        })
        modeDD:SetPoint("TOPLEFT", container, "TOPLEFT", 10, -10)

        -- 텍스처 그리드
        local grid = CreateTextureGrid(container, leftW - 10, cH - 100)
        grid:SetPoint("TOPLEFT", container, "TOPLEFT", 10, -50)
        container.textureGrid = grid

        -- 오른쪽 패널 (프리뷰 + 입력 + 버튼)
        local rightX = leftW + 20
        local rightW = cW - rightX - 10

        -- 프리뷰 (내부 텍스처 2:1 가로 비율)
        local previewInnerW = rightW - 20   -- 좌우 패딩 10씩
        local previewInnerH = math.floor(previewInnerW / 2)  -- 2:1 비율
        local previewH = previewInnerH + 70  -- title(35) + pathText(35)
        local preview = CreatePreviewPanel(container, rightW, previewH)
        preview:SetPoint("TOPLEFT", container, "TOPLEFT", rightX, -10)
        container.preview = preview

        -- 파일명 추가 섹션 (프리뷰 아래 배치)
        local addSectionY = -(10 + previewH + 12)
        local addLabel = container:CreateFontString(nil, "OVERLAY")
        addLabel:SetFont(F.path, F.normal, "")
        addLabel:SetPoint("TOPLEFT", container, "TOPLEFT", rightX, addSectionY)
        addLabel:SetText(L["TALENTBG_ADD_BG"] or "Add Custom Background")
        addLabel:SetTextColor(u(C.text.normal))

        local basePath = Presets and Presets:GetBasePath() or ""
        local baseLabel = container:CreateFontString(nil, "OVERLAY")
        baseLabel:SetFont(F.path, F.small, "")
        baseLabel:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", 0, -4)
        baseLabel:SetText("|cFF888888" .. basePath .. "|r")

        local editBox = Lib.CreateInputField(container, ADDON_KEY, "", {
            width = rightW - 100,
        })
        editBox:SetPoint("TOPLEFT", baseLabel, "BOTTOMLEFT", 0, -8)

        local addBtn = Lib.CreateButton(container, ADDON_KEY, L["ADD"] or "Add", function()
            local eb = editBox.editBox or editBox
            local fn = eb.GetText and eb:GetText() or ""
            if fn == "" then
                print(CHAT_PREFIX_ERR .. (L["TALENTBG_ENTER_FILENAME"] or "Enter filename")) -- [STYLE]
                return
            end
            if Presets and Presets:AddCustomTexture(fn) then
                container:RefreshGrid()
                eb:SetText("")
                print(CHAT_PREFIX .. string.format(L["TALENTBG_BG_ADDED"] or "Added: %s", fn)) -- [STYLE]
            else
                print(CHAT_PREFIX_ERR .. string.format(L["TALENTBG_BG_EXISTS"] or "Already exists: %s", fn)) -- [STYLE]
            end
        end, { width = 80 })
        addBtn:SetPoint("LEFT", editBox, "RIGHT", 8, 0)

        -- 하단 버튼: 적용 + 리셋
        local applyBtn = Lib.CreateButton(container, ADDON_KEY, L["APPLY"] or "Apply", function()
            if InCombatLockdown() then
                print(CHAT_PREFIX_ERR .. (L["TALENTBG_NOT_IN_COMBAT"] or "Not in combat")) -- [STYLE]
                return
            end
            local path = grid:GetSelectedTexturePath()
            if path and path ~= "" then
                self:SetCurrentBackground(path)
                container.selectedTexture = path
                print(CHAT_PREFIX .. string.format(L["TALENTBG_APPLIED"] or "Applied: %s", path)) -- [STYLE]
            else
                print(CHAT_PREFIX_ERR .. (L["TALENTBG_SELECT_TEXTURE"] or "Select a texture first")) -- [STYLE]
            end
        end, { width = 160 })
        applyBtn:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", rightX, 15)

        local resetBtn = Lib.CreateButton(container, ADDON_KEY, L["RESET_TO_DEFAULT"] or "Reset", function()
            if InCombatLockdown() then
                print(CHAT_PREFIX_ERR .. (L["TALENTBG_NOT_IN_COMBAT"] or "Not in combat")) -- [STYLE]
                return
            end
            StaticPopupDialogs["DDINGTOOLKIT_TALENTBG_RESET"] = {
                text = L["TALENTBG_RESET_CONFIRM"] or "Reset TalentBG settings?",
                button1 = YES, button2 = NO,
                OnAccept = function() self:ResetCurrentSettings(); ReloadUI() end,
                timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
            }
            StaticPopup_Show("DDINGTOOLKIT_TALENTBG_RESET")
        end, { width = 160 })
        resetBtn:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -15, 15)

        -- 그리드 콜백
        grid.onTextureSelected = function(path, name)
            preview:UpdateTexture(path)
            container.selectedTexture = path
        end
        grid.onTextureHover = function(path, name)
            preview:UpdateTexture(path)
        end
        grid.onTextureHoverEnd = function()
            local sel = container.selectedTexture or self:GetCurrentBackground()
            preview:UpdateTexture(sel)
        end
        grid.onTextureRightClick = function(path, name)
            local bPath = Presets and Presets:GetBasePath() or ""
            local fileName = path:gsub(bPath, "")
            StaticPopupDialogs["DDINGTOOLKIT_TALENTBG_DELETE"] = {
                text = string.format(L["TALENTBG_DELETE_CONFIRM"] or "Delete %s?", fileName),
                button1 = YES, button2 = NO,
                OnAccept = function()
                    Presets:RemoveCustomTexture(fileName)
                    container:RefreshGrid()
                    print(CHAT_PREFIX .. string.format(L["TALENTBG_BG_DELETED"] or "Deleted: %s", fileName)) -- [STYLE]
                end,
                timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
            }
            StaticPopup_Show("DDINGTOOLKIT_TALENTBG_DELETE")
        end

        -- RefreshGrid
        function container:RefreshGrid()
            if not Presets then return end
            local presets = Presets:GetPresets()
            local list = {}
            for _, p in ipairs(presets) do
                list[#list + 1] = { name = p.name, path = p.path }
            end
            grid:SetTextures(list)

            local bg = TalentBG:GetCurrentBackground()
            grid:SelectTextureByPath(bg)
            preview:UpdateTexture(bg)
            self.selectedTexture = bg
        end

        -- 컨테이너 높이
        container._contentHeight = cH
        container:SetHeight(cH)

        -- 초기 로드
        container:RefreshGrid()
    end
end

-- 모듈 로드 타이밍 보장
if ns.TalentBG then
    OnConfigReady()
else
    C_Timer.After(0, OnConfigReady)
end

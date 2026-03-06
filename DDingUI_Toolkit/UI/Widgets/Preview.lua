--[[
    DDingToolKit - Preview Widget
    실시간 미리보기 패널
]]

local addonName, ns = ...
local UI = ns.UI

-- 미리보기 패널 생성
function UI:CreatePreviewPanel(parent, width, height)
    local frame = self:CreatePanel(parent, width, height)

    -- 제목
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 10, -10)
    title:SetText("미리보기")
    title:SetTextColor(unpack(self.colors.text))
    frame.title = title

    -- 미리보기 영역
    local previewArea = self:CreatePanel(frame, width - 20, height - 80)
    previewArea:SetPoint("TOPLEFT", 10, -40)
    frame.previewArea = previewArea

    -- 텍스처
    local texture = previewArea:CreateTexture(nil, "ARTWORK")
    texture:SetPoint("TOPLEFT", 5, -5)
    texture:SetPoint("BOTTOMRIGHT", -5, 5)
    texture:SetTexCoord(0, 1, 0, 1)
    frame.texture = texture

    -- 경로 텍스트
    local pathText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pathText:SetPoint("BOTTOMLEFT", 10, 10)
    pathText:SetPoint("BOTTOMRIGHT", -10, 10)
    pathText:SetJustifyH("LEFT")
    pathText:SetTextColor(unpack(self.colors.textDim))
    pathText:SetText("")
    frame.pathText = pathText

    frame.currentPath = nil

    -- 텍스처 업데이트
    function frame:UpdateTexture(texturePath)
        if not texturePath or texturePath == "" then
            self.texture:SetTexture(nil)
            self.pathText:SetText("선택된 배경 없음")
            self.currentPath = nil
            return
        end

        self.texture:SetTexture(texturePath)
        self.pathText:SetText(texturePath)
        self.currentPath = texturePath
    end

    -- 현재 텍스처 가져오기
    function frame:GetTexturePath()
        return self.currentPath
    end

    return frame
end

-- 호버 미리보기 (GameTooltip)
function UI:ShowHoverPreview(texturePath, textureName)
    if not texturePath then return end

    GameTooltip:SetOwner(UIParent, "ANCHOR_CURSOR")
    GameTooltip:ClearLines()

    if textureName then
        GameTooltip:AddLine(textureName, 1, 1, 1)
    end

    GameTooltip:AddTexture(texturePath, {
        width = 256,
        height = 128,
    })

    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(texturePath, 0.6, 0.6, 0.6, true)

    GameTooltip:Show()
end

function UI:HideHoverPreview()
    GameTooltip:Hide()
end

--[[
    DDingToolKit - SoundPicker Widget
    소리 선택 위젯
]]

local addonName, ns = ...
local UI = ns.UI

-- 기본 제공 소리 목록
local defaultSounds = {
    { name = "기본 알림", path = "Interface\\AddOns\\DDingUI_Toolkit\\Media\\Sounds\\alert1.ogg" },
    { name = "벨소리", path = "Sound\\Interface\\Bell_01.ogg" },
    { name = "레벨업", path = "Sound\\Interface\\LevelUp.ogg" },
    { name = "퀘스트 완료", path = "Sound\\Interface\\iQuestComplete.ogg" },
    { name = "경매장 알림", path = "Sound\\Interface\\AuctionWindowOpen.ogg" },
    { name = "준비 완료", path = "Sound\\Interface\\ReadyCheck.ogg" },
    { name = "RaidWarning", path = "Sound\\Interface\\RaidWarning.ogg" },
    { name = "PvP 플래그", path = "Sound\\Spells\\PVPFlagTaken.ogg" },
}

-- 소리 선택 위젯 생성
function UI:CreateSoundPicker(parent, width, onSelect)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width or 300, 60)

    -- 라벨
    local label = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT")
    label:SetText("알림 소리")
    label:SetTextColor(unpack(self.colors.text))

    -- 드롭다운
    local dropdown = self:CreateDropdown(container, width - 80, {})
    dropdown:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -5)
    container.dropdown = dropdown

    -- 소리 옵션 설정
    local soundOptions = {}
    for _, sound in ipairs(defaultSounds) do
        table.insert(soundOptions, {
            text = sound.name,
            value = sound.path,
        })
    end
    dropdown:SetOptions(soundOptions)

    -- 테스트 버튼
    local testBtn = self:CreateButton(container, 70, 28, "테스트")
    testBtn:SetPoint("LEFT", dropdown, "RIGHT", 5, 0)
    container.testButton = testBtn

    testBtn:SetScript("OnClick", function()
        local path = dropdown:GetValue()
        if path and path ~= "" then
            PlaySoundFile(path, "Master")
        end
    end)

    -- 값 설정
    function container:SetValue(path)
        self.dropdown:SetValue(path)
        -- 커스텀 경로인 경우
        local found = false
        for _, sound in ipairs(defaultSounds) do
            if sound.path == path then
                found = true
                break
            end
        end
        if not found and path and path ~= "" then
            self.dropdown.text:SetText("커스텀: " .. path:match("([^\\]+)$"))
        end
    end

    -- 값 가져오기
    function container:GetValue()
        return self.dropdown:GetValue()
    end

    -- 선택 콜백
    dropdown.OnValueChanged = function(self, value)
        if onSelect then
            onSelect(value)
        end
    end

    return container
end

-- 채널 선택 드롭다운
function UI:CreateChannelPicker(parent, width, onSelect)
    local channels = {
        { text = "Master", value = "Master" },
        { text = "SFX", value = "SFX" },
        { text = "Music", value = "Music" },
        { text = "Ambience", value = "Ambience" },
        { text = "Dialog", value = "Dialog" },
    }

    local dropdown = self:CreateDropdown(parent, width or 150, channels, onSelect)
    return dropdown
end

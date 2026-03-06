--[[
    DDingToolKit - SharedMedia Registration
    LibSharedMedia-3.0 헬퍼 함수
]]

local addonName, ns = ...

-- LibSharedMedia 참조
local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

-- LibSharedMedia가 있으면 기본 폰트/사운드 등록
if LSM then
    LSM:Register("font", "DDing: 2002", [[Fonts\2002.TTF]])
    LSM:Register("font", "DDing: 2002 Bold", [[Fonts\2002B.TTF]])
    LSM:Register("font", "DDing: Arial Narrow", [[Fonts\ARIALN.TTF]])

    -- [12.0.1] WoW 내장 사운드 등록 (CDM 패턴)
    LSM:Register("sound", "None", [[]])
    LSM:Register("sound", "Alarm Clock Warning 1", [[Sound\Interface\AlarmClockWarning1.ogg]])
    LSM:Register("sound", "Alarm Clock Warning 2", [[Sound\Interface\AlarmClockWarning2.ogg]])
    LSM:Register("sound", "Alarm Clock Warning 3", [[Sound\Interface\AlarmClockWarning3.ogg]])
    LSM:Register("sound", "Bell Low Pitch", [[Sound\Interface\Bell_LowPitch.ogg]])
    LSM:Register("sound", "Bell 01", [[Sound\Interface\Bell_01.ogg]])
    LSM:Register("sound", "Level Up", [[Sound\Interface\LevelUp.ogg]])
    LSM:Register("sound", "Level Up 2", [[Sound\Interface\LevelUp2.ogg]])
    LSM:Register("sound", "Quest Complete", [[Sound\Interface\iQuestComplete.ogg]])
    LSM:Register("sound", "Raid Warning", [[Sound\Interface\RaidWarning.ogg]])
    LSM:Register("sound", "Ready Check", [[Sound\Interface\ReadyCheck.ogg]])
    LSM:Register("sound", "PvP Flag Taken", [[Sound\Spells\PVPFlagTaken.ogg]])
    LSM:Register("sound", "PvP Through Queue", [[Sound\Interface\PVPThroughQueue.ogg]])
    LSM:Register("sound", "Map Ping", [[Sound\Interface\MapPing.ogg]])
    LSM:Register("sound", "Tell Message", [[Sound\Interface\iTellMessage.ogg]])
    LSM:Register("sound", "Auction Open", [[Sound\Interface\AuctionWindowOpen.ogg]])
    LSM:Register("sound", "Auction Close", [[Sound\Interface\AuctionWindowClose.ogg]])
    LSM:Register("sound", "Countdown Go", [[Sound\Interface\UI_BattlegroundCountdown_Go.ogg]])
    LSM:Register("sound", "Countdown Timer", [[Sound\Interface\UI_BattlegroundCountdown_Timer.ogg]])
    LSM:Register("sound", "Power Aura Short", [[Sound\Spells\SimonGame_Visual_GameStart.ogg]])

    -- 네임스페이스에 LSM 참조 저장
    ns.LSM = LSM
end

-------------------------------------------------
-- 커스텀 사운드 유틸리티 (CDM 패턴) -- [12.0.1]
-------------------------------------------------

--- 사운드 파일 경로 유효성 검증
--- @param path string 사운드 파일 경로
--- @return boolean
function ns:IsValidSoundPath(path)
    if not path or path == "" then return false end
    local ext = path:lower():match("%.(%w+)$")
    return ext == "mp3" or ext == "ogg" or ext == "wav"
end

--- 중앙 사운드 재생 함수 (customPath 우선 → LSM fallback)
--- @param soundFile string LSM 사운드 경로 (드롭다운에서 선택한 값)
--- @param channel string 재생 채널 (Master/SFX/Music/Ambience/Dialog)
--- @param customPath string|nil 커스텀 사운드 파일 경로
function ns:PlaySound(soundFile, channel, customPath)
    channel = channel or "Master"

    -- 커스텀 경로 우선 -- [12.0.1]
    if customPath and customPath ~= "" then
        if self:IsValidSoundPath(customPath) then
            PlaySoundFile(customPath, channel)
        end
        return
    end

    -- LSM 사운드 파일 경로 fallback
    if soundFile and soundFile ~= "" then
        PlaySoundFile(soundFile, channel)
    end
end

-------------------------------------------------
-- 드롭다운용 헬퍼 함수들 (LSM 없어도 작동)
-------------------------------------------------

-- 기본 폰트 목록 (Fallback)
local defaultFonts = {
    { text = "Arial Narrow", value = [[Fonts\ARIALN.TTF]] },
    { text = "Friz Quadrata TT", value = [[Fonts\FRIZQT__.TTF]] },
    { text = "Morpheus", value = [[Fonts\MORPHEUS.TTF]] },
    { text = "Skurri", value = [[Fonts\SKURRI.TTF]] },
    { text = "2002", value = [[Fonts\2002.TTF]] },
    { text = "2002 Bold", value = [[Fonts\2002B.TTF]] },
}

-- 기본 사운드 목록 (Fallback)
local defaultSounds = {
    { text = "준비 완료", value = "sound/interface/levelup2.ogg" },
    { text = "벨소리", value = "sound/interface/bell_lowpitch.ogg" },
    { text = "레벨업", value = "sound/interface/levelup.ogg" },
    { text = "퀘스트 완료", value = "sound/interface/iquestcomplete.ogg" },
    { text = "RaidWarning", value = "sound/interface/raidwarning.ogg" },
    { text = "경고음", value = "sound/interface/alarmclockwarning2.ogg" },
}

-- 사운드 옵션 가져오기
function ns:GetSoundOptions(includeDefault, defaultText, defaultValue)
    local options = {}

    -- 기본 옵션 추가
    if includeDefault then
        table.insert(options, { text = defaultText or "없음", value = defaultValue or "" })
    end

    local initialCount = #options

    -- LibSharedMedia 사용
    if LSM then
        local soundList = LSM:List("sound")
        if soundList and #soundList > 0 then
            for _, name in ipairs(soundList) do
                local path = LSM:Fetch("sound", name)
                if path then
                    table.insert(options, { text = name, value = path })
                end
            end
        end
    end

    -- LSM이 없거나 빈 목록일 경우 Fallback 사용
    if #options == initialCount then
        for _, sound in ipairs(defaultSounds) do
            table.insert(options, sound)
        end
    end

    return options
end

-- 폰트 옵션 가져오기
function ns:GetFontOptions()
    local options = {}

    -- LibSharedMedia 사용
    if LSM then
        local fontList = LSM:List("font")
        if fontList and #fontList > 0 then
            for _, name in ipairs(fontList) do
                local path = LSM:Fetch("font", name)
                if path then
                    table.insert(options, { text = name, value = path })
                end
            end
        end
    end

    -- LSM이 없거나 빈 목록일 경우 Fallback 사용
    if #options == 0 then
        for _, font in ipairs(defaultFonts) do
            table.insert(options, { text = font.text, value = font.value })
        end
    end

    return options
end

-- 배경 옵션 가져오기
function ns:GetBackgroundOptions(includeNone)
    local options = {}

    if includeNone then
        table.insert(options, { text = "없음", value = "" })
    end

    local initialCount = #options

    -- LibSharedMedia 사용
    if LSM then
        local bgList = LSM:List("background")
        if bgList and #bgList > 0 then
            for _, name in ipairs(bgList) do
                local path = LSM:Fetch("background", name)
                if path then
                    table.insert(options, { text = name, value = path })
                end
            end
        end
    end

    return options
end

-- 상태바 텍스처 옵션 가져오기
function ns:GetStatusBarOptions()
    local options = {}

    if LSM then
        local barList = LSM:List("statusbar")
        if barList and #barList > 0 then
            for _, name in ipairs(barList) do
                local path = LSM:Fetch("statusbar", name)
                if path then
                    table.insert(options, { text = name, value = path })
                end
            end
        end
    end

    -- LSM이 없거나 빈 목록일 경우 Fallback 사용
    if #options == 0 then
        table.insert(options, { text = "Blizzard", value = [[Interface\TargetingFrame\UI-StatusBar]] })
    end

    return options
end

-- 테두리 옵션 가져오기
function ns:GetBorderOptions(includeNone)
    local options = {}

    if includeNone then
        table.insert(options, { text = "없음", value = "" })
    end

    local initialCount = #options

    if LSM then
        local borderList = LSM:List("border")
        if borderList and #borderList > 0 then
            for _, name in ipairs(borderList) do
                local path = LSM:Fetch("border", name)
                if path then
                    table.insert(options, { text = name, value = path })
                end
            end
        end
    end

    -- LSM이 없거나 빈 목록일 경우 Fallback 사용
    if #options == initialCount then
        table.insert(options, { text = "Blizzard Tooltip", value = [[Interface\Tooltips\UI-Tooltip-Border]] })
    end

    return options
end

-- 미디어 경로로 이름 찾기
function ns:GetMediaName(mediatype, path)
    if not LSM then return nil end

    local list = LSM:HashTable(mediatype)
    if list then
        for name, mediaPath in pairs(list) do
            if mediaPath == path then
                return name
            end
        end
    end
    return nil
end

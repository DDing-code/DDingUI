--[[
    DDingToolKit - KeystoneTracker Module
    파티원 쐐기돌 정보 추적 및 공유
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local L = ns.L
local SL = _G.DDingUI_StyleLib -- [12.0.1]
local SL_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF" -- [12.0.1]
local CHAT_PREFIX = (SL and SL.GetChatPrefix) and SL.GetChatPrefix("MJToolkit", "Toolkit") or "|cffffffffDDing|r|cffffa300UI|r |cff33bfe6Toolkit|r: " -- [STYLE]

local KeystoneTracker = {}
ns.KeystoneTracker = KeystoneTracker

-- 던전 정보 (TWW 시즌)
local DUNGEON_INFO = {
    -- TWW 시즌 1 던전들
    [501] = { name = "어둠불꽃 지하도시", abbr = "어둠불꽃", icon = 5779461 },
    [502] = { name = "돌무덤", abbr = "돌무덤", icon = 5779460 },
    [503] = { name = "도시의 결", abbr = "도시결", icon = 5779459 },
    [504] = { name = "여명의 유도관", abbr = "여명", icon = 5779458 },
    [505] = { name = "아라카라, 네루브아르의 도시", abbr = "아라카라", icon = 5779457 },
    [506] = { name = "보석궁전 폐허", abbr = "보석궁전", icon = 5779456 },
    [507] = { name = "희망의 불꽃", abbr = "희망불꽃", icon = 5779455 },
    [508] = { name = "잿빛 운명의 금고", abbr = "잿빛금고", icon = 5779454 },
    -- 기본 던전 추가
    [399] = { name = "루비 생명웅덩이", abbr = "루비", icon = 4511173 },
    [400] = { name = "노크후드 침공군", abbr = "노크", icon = 4511175 },
    [401] = { name = "하늘기병 아카데미", abbr = "하아", icon = 4511177 },
    [402] = { name = "알겟아르 아카데미", abbr = "알겟", icon = 4511179 },
}

-- 애드온 메시지 프리픽스
local ADDON_PREFIX = "DDingKeystone"

-- 파티원 키스톤 데이터
local partyKeystones = {}
local myKeystone = nil

-- 로컬 변수
local mainFrame = nil
local updateTicker = nil
local isEnabled = false

-- 초기화
function KeystoneTracker:OnInitialize()
    if ns.db and ns.db.profile then
        self.db = ns.db.profile.KeystoneTracker
    end
    -- 애드온 메시지 등록
    C_ChatInfo.RegisterAddonMessagePrefix(ADDON_PREFIX)
end

-- 활성화
function KeystoneTracker:OnEnable()
    if not self.db then
        if ns.db and ns.db.profile and ns.db.profile.KeystoneTracker then
            self.db = ns.db.profile.KeystoneTracker
        else
            self.db = {
                locked = false,
                showInParty = true,
                showInRaid = false,
                scale = 1.0,
                font = SL_FONT, -- [12.0.1]
                fontSize = 12,
                position = {
                    point = "TOPLEFT",
                    relativePoint = "TOPLEFT",
                    x = 50,
                    y = -200,
                },
            }
        end
    end

    isEnabled = true
    self:CreateMainFrame()
    self:ScanMyKeystone()
    self:StartUpdate()

    print(CHAT_PREFIX .. L["KEYSTONETRACKER_ENABLED"]) -- [STYLE]
end

-- 비활성화
function KeystoneTracker:OnDisable()
    isEnabled = false
    if mainFrame then
        mainFrame:Hide()
    end
    if updateTicker then
        updateTicker:Cancel()
        updateTicker = nil
    end
end

-- 내 쐐기돌 스캔
function KeystoneTracker:ScanMyKeystone()
    myKeystone = nil

    -- C_MythicPlus API로 직접 체크
    if C_MythicPlus and C_MythicPlus.GetOwnedKeystoneChallengeMapID then
        local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
        local level = C_MythicPlus.GetOwnedKeystoneLevel()

        if mapID and level and mapID > 0 and level > 0 then
            myKeystone = {
                mapID = mapID,
                level = level,
                name = UnitName("player"),
                class = select(2, UnitClass("player")),
            }
        end
    end
end

-- 메인 프레임 생성
function KeystoneTracker:CreateMainFrame()
    if mainFrame then return end

    if not self.db then
        self.db = {
            position = { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 50, y = -200 },
            scale = 1.0,
            font = SL_FONT, -- [12.0.1]
            fontSize = 12,
        }
    end

    local pos = self.db.position or { point = "TOPLEFT", relativePoint = "TOPLEFT", x = 50, y = -200 }
    local frame = CreateFrame("Frame", "DDingToolKit_KeystoneTrackerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(280, 200)
    frame:SetPoint(pos.point or "TOPLEFT", UIParent, pos.relativePoint or "TOPLEFT", pos.x or 50, pos.y or -200)
    frame:SetFrameStrata("HIGH")

    -- 배경
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.85)
    frame:SetBackdropBorderColor(0.6, 0.4, 0.1, 1)

    -- 드래그 가능
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        if not KeystoneTracker.db or not KeystoneTracker.db.locked then
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if KeystoneTracker.db and KeystoneTracker.db.position then
            local point, _, relativePoint, x, y = self:GetPoint()
            KeystoneTracker.db.position.point = point
            KeystoneTracker.db.position.relativePoint = relativePoint
            KeystoneTracker.db.position.x = x
            KeystoneTracker.db.position.y = y
        end
    end)

    -- 타이틀
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -10)
    title:SetText("|cFFFFD100" .. L["KEYSTONETRACKER_PARTY_KEYS"] .. "|r")
    frame.title = title

    -- 닫기 버튼
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)

    -- 컨텐츠 영역
    frame.content = CreateFrame("Frame", nil, frame)
    frame.content:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -35)
    frame.content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)

    -- 파티원 행 프레임들
    frame.rows = {}
    for i = 1, 5 do
        local row = self:CreatePlayerRow(frame.content, i)
        row:SetPoint("TOPLEFT", frame.content, "TOPLEFT", 0, -((i-1) * 30))
        row:Hide()
        frame.rows[i] = row
    end

    mainFrame = frame
    mainFrame:Hide()  -- 기본은 숨김

    -- 크기 적용
    if self.db and self.db.scale then
        mainFrame:SetScale(self.db.scale)
    end
end

-- 파티원 행 생성
function KeystoneTracker:CreatePlayerRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(260, 26)

    local font = (self.db and self.db.font) or SL_FONT -- [12.0.1]
    local fontSize = (self.db and self.db.fontSize) or 12

    -- 직업 아이콘
    row.classIcon = row:CreateTexture(nil, "ARTWORK")
    row.classIcon:SetSize(22, 22)
    row.classIcon:SetPoint("LEFT", row, "LEFT", 0, 0)
    row.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")

    -- 플레이어 이름
    row.nameText = row:CreateFontString(nil, "OVERLAY")
    row.nameText:SetFont(font, fontSize, "OUTLINE")
    row.nameText:SetPoint("LEFT", row.classIcon, "RIGHT", 5, 0)
    row.nameText:SetWidth(90)
    row.nameText:SetJustifyH("LEFT")

    -- 던전 아이콘
    row.dungeonIcon = row:CreateTexture(nil, "ARTWORK")
    row.dungeonIcon:SetSize(22, 22)
    row.dungeonIcon:SetPoint("LEFT", row.nameText, "RIGHT", 5, 0)

    -- 던전 이름 + 레벨
    row.keystoneText = row:CreateFontString(nil, "OVERLAY")
    row.keystoneText:SetFont(font, fontSize, "OUTLINE")
    row.keystoneText:SetPoint("LEFT", row.dungeonIcon, "RIGHT", 5, 0)
    row.keystoneText:SetWidth(110)
    row.keystoneText:SetJustifyH("LEFT")

    return row
end

-- 업데이트 시작
function KeystoneTracker:StartUpdate()
    if updateTicker then
        updateTicker:Cancel()
    end

    updateTicker = C_Timer.NewTicker(2.0, function()
        if isEnabled and mainFrame and mainFrame:IsShown() then
            KeystoneTracker:Update()
        end
    end)

    -- 초기 브로드캐스트
    C_Timer.After(3, function()
        if isEnabled then
            self:BroadcastKeystone()
            self:RequestKeystones()
        end
    end)
end

-- 키스톤 브로드캐스트
function KeystoneTracker:BroadcastKeystone()
    if not IsInGroup() then return end

    self:ScanMyKeystone()

    if myKeystone then
        local msg = string.format("%d:%d:%s", myKeystone.mapID, myKeystone.level, myKeystone.class)

        local channel = "PARTY"
        if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
            channel = "INSTANCE_CHAT"
        elseif IsInRaid() then
            channel = "RAID"
        end

        C_ChatInfo.SendAddonMessage(ADDON_PREFIX, msg, channel)
    end
end

-- 키스톤 요청
function KeystoneTracker:RequestKeystones()
    if not IsInGroup() then return end

    local channel = "PARTY"
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then
        channel = "INSTANCE_CHAT"
    elseif IsInRaid() then
        channel = "RAID"
    end

    C_ChatInfo.SendAddonMessage(ADDON_PREFIX, "REQUEST", channel)
end

-- 전체 업데이트
function KeystoneTracker:Update()
    if not mainFrame then return end

    -- 내 쐐기돌 업데이트
    self:ScanMyKeystone()

    -- UI 업데이트
    self:UpdateDisplay()
end

-- 디스플레이 업데이트
function KeystoneTracker:UpdateDisplay()
    if not mainFrame or not mainFrame.rows then return end

    -- 모든 행 숨기기
    for _, row in ipairs(mainFrame.rows) do
        row:Hide()
    end

    local index = 1

    -- 본인 먼저 표시
    if myKeystone then
        self:UpdateRow(mainFrame.rows[index], myKeystone)
        mainFrame.rows[index]:Show()
        index = index + 1
    else
        -- 쐐기돌 없음 표시
        local row = mainFrame.rows[index]
        local _, class = UnitClass("player")
        if CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class] then
            row.classIcon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[class]))
        end
        local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if classColor then
            row.nameText:SetText(string.format("|c%s%s|r", classColor.colorStr, UnitName("player")))
        else
            row.nameText:SetText(UnitName("player"))
        end
        row.dungeonIcon:SetTexture(134414)
        row.keystoneText:SetText("|cFF888888" .. L["KEYSTONETRACKER_NO_KEY"] .. "|r")
        row:Show()
        index = index + 1
    end

    -- 파티원 표시
    if IsInGroup() then
        local inRaid = IsInRaid()
        local prefix = inRaid and "raid" or "party"
        local maxMembers = inRaid and GetNumGroupMembers() or GetNumGroupMembers() - 1

        for i = 1, maxMembers do
            if index > 5 then break end

            local unit = prefix .. i
            if UnitExists(unit) and not UnitIsUnit(unit, "player") then
                local name = UnitName(unit)
                local _, class = UnitClass(unit)
                local row = mainFrame.rows[index]

                -- 직업 아이콘
                if CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class] then
                    row.classIcon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[class]))
                end

                -- 이름 (직업 색상)
                local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
                if classColor then
                    row.nameText:SetText(string.format("|c%s%s|r", classColor.colorStr, name))
                else
                    row.nameText:SetText(name)
                end

                -- 파티원 키스톤 정보
                if partyKeystones[name] then
                    self:UpdateRowKeystone(row, partyKeystones[name])
                else
                    row.dungeonIcon:SetTexture(134414)
                    row.keystoneText:SetText("|cFF888888" .. L["KEYSTONETRACKER_NO_INFO"] .. "|r")
                end

                row:Show()
                index = index + 1
            end
        end
    end

    -- 프레임 높이 조정
    local height = 45 + ((index - 1) * 30)
    mainFrame:SetHeight(math.max(height, 100))
end

-- 행 업데이트
function KeystoneTracker:UpdateRow(row, data)
    if not row or not data then return end

    -- 직업 아이콘
    if CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[data.class] then
        row.classIcon:SetTexCoord(unpack(CLASS_ICON_TCOORDS[data.class]))
    end

    -- 이름 (직업 색상)
    local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[data.class]
    if classColor then
        row.nameText:SetText(string.format("|c%s%s|r", classColor.colorStr, data.name))
    else
        row.nameText:SetText(data.name)
    end

    self:UpdateRowKeystone(row, data)
end

-- 행 키스톤 정보 업데이트
function KeystoneTracker:UpdateRowKeystone(row, data)
    -- 던전 정보
    local dungeonInfo = DUNGEON_INFO[data.mapID]
    if dungeonInfo then
        row.dungeonIcon:SetTexture(dungeonInfo.icon)

        -- 레벨에 따른 색상
        local levelColor
        if data.level >= 15 then
            levelColor = "|cFFFF8000"  -- 주황
        elseif data.level >= 10 then
            levelColor = "|cFFA335EE"  -- 보라
        elseif data.level >= 7 then
            levelColor = "|cFF0070DD"  -- 파랑
        else
            levelColor = "|cFF1EFF00"  -- 녹색
        end

        row.keystoneText:SetText(string.format("%s%s +%d|r", levelColor, dungeonInfo.abbr, data.level))
    else
        row.dungeonIcon:SetTexture(134414)  -- 기본 열쇠 아이콘
        row.keystoneText:SetText(string.format("|cFFFFFFFF+%d|r", data.level))
    end
end

-- 메시지 수신 처리
function KeystoneTracker:OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= ADDON_PREFIX then return end

    -- 본인 메시지 무시
    local playerName = UnitName("player")
    local senderName = strsplit("-", sender)
    if senderName == playerName then return end

    if message == "REQUEST" then
        -- 요청에 응답
        self:BroadcastKeystone()
    else
        -- 키스톤 정보 파싱
        local mapID, level, class = strsplit(":", message)
        mapID = tonumber(mapID)
        level = tonumber(level)

        if mapID and level and class then
            partyKeystones[senderName] = {
                mapID = mapID,
                level = level,
                class = class,
                name = senderName,
            }
        end
    end
end

-- 쐐기돌 표시 토글
function KeystoneTracker:Toggle()
    if not mainFrame then
        self:CreateMainFrame()
    end

    if not mainFrame then return end

    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        self:ScanMyKeystone()
        self:UpdateDisplay()
        self:RequestKeystones()
        mainFrame:Show()
    end
end

-- 메인 프레임 반환
function KeystoneTracker:GetMainFrame()
    return mainFrame
end

-- 이벤트 프레임
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_ADDON")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        KeystoneTracker:OnAddonMessage(prefix, message, channel, sender)
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(2, function()
            if isEnabled then
                KeystoneTracker:ScanMyKeystone()
            end
        end)
    elseif event == "GROUP_ROSTER_UPDATE" then
        if isEnabled then
            partyKeystones = {}  -- 파티 변경시 초기화
            C_Timer.After(1, function()
                KeystoneTracker:RequestKeystones()
            end)
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        if isEnabled then
            KeystoneTracker:ScanMyKeystone()
        end
    end
end)

-- 모듈 등록
DDingToolKit:RegisterModule("KeystoneTracker", KeystoneTracker)

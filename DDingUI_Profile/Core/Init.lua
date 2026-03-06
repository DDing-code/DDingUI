local AddOnName, Engine = ...

local DUI = LibStub("AceAddon-3.0"):NewAddon(AddOnName, "AceConsole-3.0", "AceHook-3.0")

Engine[1] = DUI
Engine[2] = {}
_G[AddOnName] = Engine

DUI.title = "|cffffffffDDing|r|cffffa300UI|r"
DUI.name = "DDingUI"
DUI.version = C_AddOns.GetAddOnMetadata(AddOnName, "Version")
DUI.profileName = "DDingUI"

-- Modules
DUI.Data = DUI:NewModule("Data")
DUI.Setup = DUI:NewModule("Setup", "AceHook-3.0")
DUI.Installer = DUI:NewModule("Installer")

-- 직업별 한국어 이름 매핑
DUI.classNames = {
    ["WARRIOR"]     = "전사",
    ["PALADIN"]     = "성기사",
    ["HUNTER"]      = "사냥꾼",
    ["ROGUE"]       = "도적",
    ["PRIEST"]      = "사제",
    ["DEATHKNIGHT"] = "죽음의기사",
    ["SHAMAN"]      = "주술사",
    ["MAGE"]        = "마법사",
    ["WARLOCK"]     = "흑마법사",
    ["MONK"]        = "수도사",
    ["DRUID"]       = "드루이드",
    ["DEMONHUNTER"] = "악마사냥꾼",
    ["EVOKER"]      = "기원사",
}

-- 전문화별 정보 매핑 (specID 기준)
-- { [specID] = { class, specName, classColor } }
DUI.specInfo = {
    -- 전사
    [71]   = { class = "WARRIOR",     specName = "무기",   classColor = "C69B6D" },
    [72]   = { class = "WARRIOR",     specName = "분노",   classColor = "C69B6D" },
    [73]   = { class = "WARRIOR",     specName = "방어",   classColor = "C69B6D" },
    -- 성기사
    [65]   = { class = "PALADIN",     specName = "신성",   classColor = "F48CBA" },
    [66]   = { class = "PALADIN",     specName = "보호",   classColor = "F48CBA" },
    [70]   = { class = "PALADIN",     specName = "징벌",   classColor = "F48CBA" },
    -- 사냥꾼
    [253]  = { class = "HUNTER",      specName = "야수",   classColor = "AAD372" },
    [254]  = { class = "HUNTER",      specName = "사격",   classColor = "AAD372" },
    [255]  = { class = "HUNTER",      specName = "생존",   classColor = "AAD372" },
    -- 도적
    [259]  = { class = "ROGUE",       specName = "암살",   classColor = "FFF468" },
    [260]  = { class = "ROGUE",       specName = "무법",   classColor = "FFF468" },
    [261]  = { class = "ROGUE",       specName = "잠행",   classColor = "FFF468" },
    -- 사제
    [256]  = { class = "PRIEST",      specName = "수양",   classColor = "FFFFFF" },
    [257]  = { class = "PRIEST",      specName = "신성",   classColor = "FFFFFF" },
    [258]  = { class = "PRIEST",      specName = "암흑",   classColor = "FFFFFF" },
    -- 죽음의기사
    [250]  = { class = "DEATHKNIGHT", specName = "혈기",   classColor = "C41E3A" },
    [251]  = { class = "DEATHKNIGHT", specName = "냉기",   classColor = "C41E3A" },
    [252]  = { class = "DEATHKNIGHT", specName = "부정",   classColor = "C41E3A" },
    -- 주술사
    [262]  = { class = "SHAMAN",      specName = "정기",   classColor = "0070DD" },
    [263]  = { class = "SHAMAN",      specName = "고양",   classColor = "0070DD" },
    [264]  = { class = "SHAMAN",      specName = "복원",   classColor = "0070DD" },
    -- 마법사
    [62]   = { class = "MAGE",        specName = "비전",   classColor = "3FC7EB" },
    [63]   = { class = "MAGE",        specName = "화염",   classColor = "3FC7EB" },
    [64]   = { class = "MAGE",        specName = "냉기",   classColor = "3FC7EB" },
    -- 흑마법사
    [265]  = { class = "WARLOCK",     specName = "고통",   classColor = "8788EE" },
    [266]  = { class = "WARLOCK",     specName = "악마",   classColor = "8788EE" },
    [267]  = { class = "WARLOCK",     specName = "파괴",   classColor = "8788EE" },
    -- 수도사
    [268]  = { class = "MONK",        specName = "양조",   classColor = "00FF98" },
    [270]  = { class = "MONK",        specName = "운무",   classColor = "00FF98" },
    [269]  = { class = "MONK",        specName = "풍운",   classColor = "00FF98" },
    -- 드루이드
    [102]  = { class = "DRUID",       specName = "조화",   classColor = "FF7C0A" },
    [103]  = { class = "DRUID",       specName = "야성",   classColor = "FF7C0A" },
    [104]  = { class = "DRUID",       specName = "수호",   classColor = "FF7C0A" },
    [105]  = { class = "DRUID",       specName = "복원",   classColor = "FF7C0A" },
    -- 악마사냥꾼
    [577]  = { class = "DEMONHUNTER", specName = "파멸",   classColor = "A330C9" },
    [581]  = { class = "DEMONHUNTER", specName = "복수",   classColor = "A330C9" },
    -- 기원사
    [1467] = { class = "EVOKER",      specName = "황폐",   classColor = "33937F" },
    [1468] = { class = "EVOKER",      specName = "보존",   classColor = "33937F" },
    [1473] = { class = "EVOKER",      specName = "증강",   classColor = "33937F" },
}

function DUI:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("DDingUIProfileDB", {
        global = {
            profiles = {},
            version = nil,
        },
        char = {
            loaded = false,
        },
    })

    self:RegisterChatCommand("ddp", "HandleCommand")
    self:RegisterChatCommand("ddingprofile", "HandleCommand")
end

function DUI:OnEnable()
    self:Initialize()
end

function DUI:Initialize()
    if not self.db.char.loaded then
        C_Timer.After(6, function()
            self:ShowInstallPrompt()
        end)
    end
end

function DUI:HandleCommand(input)
    input = strtrim(input):lower()

    if input == "install" or input == "" then
        self:ShowInstaller()
    elseif input == "load" then
        self:LoadProfiles()
    elseif input == "reset" then
        self.db.char.loaded = false
        self:Print("프로필 설치 상태가 초기화되었습니다. /reload 후 다시 설치할 수 있습니다.")
    else
        self:Print("사용법: /ddp [install|load|reset]")
    end
end

function DUI:ShowInstallPrompt()
    local I = self:GetModule("Installer")
    if not I.installer then return end

    -- ElvUI 런타임 감지: 있으면 PluginInstaller, 없으면 독자 UI
    if ElvUI then
        local E = unpack(ElvUI)
        E:GetModule("PluginInstaller"):Queue(I.installer)
    else
        I:ShowStandalone(I.installer)
    end
end

function DUI:ShowInstaller()
    local I = self:GetModule("Installer")
    if not I.installer then return end

    if ElvUI then
        local E = unpack(ElvUI)
        E:GetModule("PluginInstaller"):Queue(I.installer)
    else
        I:ShowStandalone(I.installer)
    end
end

-- Addon Compartment (미니맵 버튼)
function DDingUIProfile_OnAddonCompartmentClick()
    DUI:ShowInstaller()
end

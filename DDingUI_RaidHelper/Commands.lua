local _, ns = ...

local Commands = {}
ns.Commands = Commands

local function Trim(value)
    return (value or ""):match("^%s*(.-)%s*$")
end

function Commands:ShowHelp()
    ns:Print("/drh preview - 견본 전투 미리보기 켜기/끄기")
    ns:Print("/drh edit - 위치 편집 모드 켜기/끄기")
    ns:Print("/drh stop - 미리보기 또는 전투 타임라인 종료")
    ns:Print("/drh reset - 프레임 위치 초기화")
    ns:Print("/drh lock - 프레임 이동 잠금 전환")
    ns:Print("/drh tooltip - 마커 툴팁 표시 전환 (전투 중 변경은 종료 후 적용)")
    ns:Print("/drh profile - 현재 보스의 상위 전문화 2차 스탯과 특성 코드")
    ns:Print("/drh options - RaidHelper 독립 설정 창 열기")
end

function Commands:Handle(message)
    local command = string.lower(Trim(message))

    if command == "demo" or command == "test" or command == "preview" then
        ns.TimelineUI:TogglePreviewMode()
    elseif command == "stop" then
        if ns.TimelineUI:IsPreviewMode() then
            ns.TimelineUI:SetPreviewMode(false)
        else
            ns.Engine:StopEncounter(false)
        end
    elseif command == "reset" then
        ns.TimelineUI:ResetPosition()
        ns:Print("프레임 위치를 초기화했습니다.")
    elseif command == "edit" or command == "move" or command == "unlock" then
        ns.TimelineUI:ToggleEditMode()
    elseif command == "lock" then
        ns.db.locked = not ns.db.locked
        ns:Print(ns.db.locked and "프레임 이동을 잠갔습니다." or "프레임 이동 잠금을 해제했습니다.")
    elseif command == "tooltip" or command == "tooltips" then
        local current = ns.Options:GetRequestedTooltipSetting()
        ns.Options:SetTooltipsEnabled(not current)
    elseif command == "profile" or command == "talent" or command == "talents" or command == "build" then
        ns.HealerProfileUI:Toggle()
    elseif command == "options" or command == "option" or command == "config" then
        ns.Options:Open()
    elseif command == "show" then
        if not ns.Engine:IsRunning() then
            ns.TimelineUI:SetPreviewMode(true)
        else
            ns.TimelineUI.frame:Show()
        end
    elseif command == "hide" then
        ns.TimelineUI.frame:Hide()
    else
        self:ShowHelp()
    end
end

function Commands:Initialize()
    if self.initialized then return end
    SLASH_DDINGUIRAIDHELPER1 = "/drh"
    SLASH_DDINGUIRAIDHELPER2 = "/ddingraid"
    SlashCmdList.DDINGUIRAIDHELPER = function(message)
        Commands:Handle(message)
    end
    self.initialized = true
end

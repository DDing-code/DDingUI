-- DDingUI_Essential: BlizzardSkins Module -- [ESSENTIAL]
-- ElvUI 로컬 코드 분석 기반 재구현
-- Phase 1: GameMenu, StaticPopup, Tooltip, DropDown, ReadyCheck, LFDRole, GhostFrame
-- Phase 2: CharacterFrame, SpellBook, WorldMap, QuestLog (OnDemand)

local _, ns = ...

local BlizzardSkins = {}

------------------------------------------------------------------------
-- StyleLib 참조 -- [ESSENTIAL]
------------------------------------------------------------------------
local SL      = _G.DDingUI_StyleLib
local FLAT    = (SL and SL.Textures and SL.Textures.flat) or "Interface\\Buttons\\WHITE8x8"
local SL_FONT = (SL and SL.Font and SL.Font.path) or "Fonts\\2002.TTF"

-- 악센트 캐시 (Enable 시 갱신) -- [ESSENTIAL]
local accentFrom, accentTo

------------------------------------------------------------------------
-- 공통 유틸리티 -- [ESSENTIAL]
------------------------------------------------------------------------

--- 타이틀 악센트 그라디언트 라인 (프레임 상단 2px) -- [ESSENTIAL-DESIGN]
local function CreateAccentLine(parent, height)
    if not parent then return end
    height = height or 2

    local line = parent:CreateTexture(nil, "OVERLAY", nil, 7)
    line:SetTexture(FLAT)
    line:SetHeight(height)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)

    -- 클래스 컬러 사용 
    local classFileName = select(2, UnitClass("player"))
    local color = RAID_CLASS_COLORS[classFileName] or {r = 1, g = 1, b = 1}
    
    line:SetVertexColor(color.r, color.g, color.b, 1)

    return line
end

------------------------------------------------------------------------
-- 1. GameMenuFrame 스     킨 (ElvUI Misc.lua L60-95) -- [ESSENTIAL]
------------------------------------------------------------------------
local function SkinGameMenu()
    local gmf = _G.GameMenuFrame
    if not gmf or gmf._ddeSkinned then return end
    gmf._ddeSkinned = true

    ns.StripTextures(gmf)
    ns.CreateBackdrop(gmf)
    CreateAccentLine(gmf)

    -- 헤더 -- [ESSENTIAL]
    local header = gmf.Header
    if header then
        ns.StripTextures(header)
        header:ClearAllPoints()
        header:SetPoint("TOP", gmf, "TOP", 0, 7)
    end

    -- 버튼: buttonPool 동적 감지 (ElvUI InitButtons 패턴) -- [ESSENTIAL]
    hooksecurefunc(gmf, "InitButtons", function(menu)
        if not menu.buttonPool then return end

        for button in menu.buttonPool:EnumerateActive() do
            if not button._ddeSkinned then
                ns.HandleButton(button, true)
            end
        end
    end)

    -- 이미 존재하는 버튼도 스킨 -- [ESSENTIAL]
    if gmf.buttonPool then
        for button in gmf.buttonPool:EnumerateActive() do
            if not button._ddeSkinned then
                ns.HandleButton(button, true)
            end
        end
    end
end

------------------------------------------------------------------------
-- 2. StaticPopup 스킨 (BFI + ElvUI 통합 패턴) -- [ESSENTIAL]
------------------------------------------------------------------------
local function SkinStaticPopup(popup)
    if not popup or popup._ddeSkinned then return end
    popup._ddeSkinned = true

    -- ★ BFI: SetParent(UIParent) — 다른 프레임에 종속 방지 -- [ESSENTIAL]
    popup:SetParent(UIParent)

    ns.StripTextures(popup)
    ns.CreateBackdrop(popup)
    CreateAccentLine(popup)

    -- ★ 버튼: ButtonContainer 패턴 (12.x) + 레거시 패턴 -- [ESSENTIAL]
    local pname = popup:GetName()

    -- 12.x 새 패턴: ButtonContainer.Button1~4
    if popup.ButtonContainer then
        for i = 1, 4 do
            local btn = popup.ButtonContainer["Button"..i]
            if btn then ns.HandleButton(btn) end
        end
    end

    -- 레거시 패턴: popup.button1~4 / StaticPopup1Button1~4
    for i = 1, 4 do
        local btn = popup["button"..i] or (pname and _G[pname.."Button"..i])
        if btn and not btn._ddeSkinned then ns.HandleButton(btn) end
    end

    -- ExtraButton -- [ESSENTIAL]
    if popup.ExtraButton then ns.HandleButton(popup.ExtraButton) end

    -- CloseButton -- [ESSENTIAL]
    local closeBtn = popup.CloseButton or (pname and _G[pname.."CloseButton"])
    if closeBtn then ns.HandleCloseButton(closeBtn) end

    -- EditBox -- [ESSENTIAL]
    local editBox = popup.editBox or popup.EditBox or (pname and _G[pname.."EditBox"])
    if editBox then ns.HandleEditBox(editBox) end

    -- Dropdown (BFI 패턴) -- [ESSENTIAL]
    if popup.Dropdown then
        ns.StripTextures(popup.Dropdown)
        ns.CreateBackdrop(popup.Dropdown, {0.12, 0.12, 0.12, 0.9}, {0.2, 0.2, 0.2, 0.8})
    end

    -- MoneyInputFrame (gold/silver/copper) -- [ESSENTIAL]
    local moneyFrame = popup.moneyInputFrame or popup.MoneyInputFrame or (pname and _G[pname.."MoneyInputFrame"])
    if moneyFrame then
        if moneyFrame.gold then ns.HandleEditBox(moneyFrame.gold) end
        if moneyFrame.silver then ns.HandleEditBox(moneyFrame.silver) end
        if moneyFrame.copper then ns.HandleEditBox(moneyFrame.copper) end
    end

    -- ItemFrame -- [ESSENTIAL]
    local itemFrame = popup.ItemFrame or (pname and _G[pname.."ItemFrame"])
    if itemFrame then
        local nameFrame = itemFrame.NameFrame or (pname and _G[pname.."ItemFrameNameFrame"])
        if nameFrame then ns.StripTextures(nameFrame) end

        local icon = itemFrame.IconTexture or itemFrame.icon
        if icon then
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        ns.StripTextures(itemFrame)
        ns.CreateBorder(itemFrame, {0, 0, 0, 1})

        -- NormalTexture 제거 + 후킹 -- [ESSENTIAL]
        local normTex = itemFrame.GetNormalTexture and itemFrame:GetNormalTexture()
        if normTex then
            normTex:SetTexture(nil)
            hooksecurefunc(normTex, "SetTexture", function(self, tex)
                if tex and tex ~= "" then self:SetTexture(nil) end
            end)
        end
    end

    -- 텍스트 폰트 -- [ESSENTIAL]
    local text = popup.text or (pname and _G[pname.."Text"])
    if text and text.SetFont then
        ns.SetFont(text, (SL and SL.Font and SL.Font.normal) or 13, "")
    end
end

local function SkinStaticPopups()
    local maxPopups = _G.STATICPOPUP_NUMDIALOGS or 4
    for i = 1, maxPopups do
        local popup = _G["StaticPopup"..i]
        if popup then
            SkinStaticPopup(popup)
        end
    end
end

------------------------------------------------------------------------
-- 3. Tooltip 스킨 (ElvUI Tooltip.lua 패턴) -- [ESSENTIAL]
------------------------------------------------------------------------
local function ApplyTooltipStyle(tooltip)
    if not tooltip then return end
    if tooltip.SetBackdrop then
        tooltip:SetBackdrop({
            bgFile   = FLAT,
            edgeFile = FLAT,
            edgeSize = 1,
        })
        local r, g, b, a = ns.GetColor("bg.main")
        tooltip:SetBackdropColor(r, g, b, 0.95)
        tooltip:SetBackdropBorderColor(0, 0, 0, 1)
    end
    -- NineSlice 숨기기 -- [ESSENTIAL]
    if tooltip.NineSlice then
        tooltip.NineSlice:SetAlpha(0)
    end
end

local function SkinTooltips()
    -- 18개 툴팁 스킨 (ElvUI Tooltip.lua L11-34) -- [ESSENTIAL]
    local tooltips = {
        _G.GameTooltip,
        _G.ShoppingTooltip1,
        _G.ShoppingTooltip2,
        _G.ItemRefTooltip,
        _G.ItemRefShoppingTooltip1,
        _G.ItemRefShoppingTooltip2,
        _G.EmbeddedItemTooltip,
        _G.FriendsTooltip,
        _G.QuickKeybindTooltip,
        _G.GameSmallHeaderTooltip,
    }

    -- 안전하게 추가 (nil 체크) -- [ESSENTIAL]
    if _G.QuestScrollFrame then
        if _G.QuestScrollFrame.StoryTooltip then
            tooltips[#tooltips + 1] = _G.QuestScrollFrame.StoryTooltip
        end
        if _G.QuestScrollFrame.CampaignTooltip then
            tooltips[#tooltips + 1] = _G.QuestScrollFrame.CampaignTooltip
        end
    end
    if _G.LibDBIconTooltip then
        tooltips[#tooltips + 1] = _G.LibDBIconTooltip
    end
    if _G.SettingsTooltip then
        tooltips[#tooltips + 1] = _G.SettingsTooltip
    end

    for _, tt in ipairs(tooltips) do
        ApplyTooltipStyle(tt)
    end

    -- ★ 핵심: SharedTooltip_SetBackdropStyle 후킹 (ElvUI L69) -- [ESSENTIAL]
    -- 블리자드가 OnShow에서 스타일 리셋할 때마다 자동 재적용
    if _G.SharedTooltip_SetBackdropStyle then
        hooksecurefunc("SharedTooltip_SetBackdropStyle", function(tooltip)
            ApplyTooltipStyle(tooltip)
        end)
    end

    -- GameTooltip StatusBar 스킨 -- [ESSENTIAL]
    local statusBar = _G.GameTooltipStatusBar
    if statusBar then
        statusBar:SetStatusBarTexture(FLAT)
        if not statusBar._ddeBG then
            local bg = statusBar:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetTexture(FLAT)
            bg:SetVertexColor(0.05, 0.05, 0.05, 0.80)
            statusBar._ddeBG = bg
        end
        statusBar:SetHeight(3)
    end

    -- CloseButton (ItemRefTooltip) -- [ESSENTIAL]
    if _G.ItemRefTooltip and _G.ItemRefTooltip.CloseButton then
        ns.HandleCloseButton(_G.ItemRefTooltip.CloseButton)
    end
end

------------------------------------------------------------------------
-- 4. DropDown 스킨 -- [ESSENTIAL]
------------------------------------------------------------------------
local function SkinDropDown(level)
    level = level or 1
    local listFrame = _G["DropDownList"..level]
    if not listFrame then return end

    -- Backdrop -- [ESSENTIAL]
    local backdrop = listFrame.Backdrop or _G[listFrame:GetName().."Backdrop"]
    if backdrop then
        if backdrop.NineSlice then
            ns.StripTextures(backdrop.NineSlice)
        end
        ns.StripTextures(backdrop)
        ns.CreateBackdrop(backdrop)
    end

    -- MenuBackdrop -- [ESSENTIAL]
    local menuBackdrop = _G[listFrame:GetName().."MenuBackdrop"]
    if menuBackdrop then
        if menuBackdrop.NineSlice then
            ns.StripTextures(menuBackdrop.NineSlice)
        end
        ns.StripTextures(menuBackdrop)
        ns.CreateBackdrop(menuBackdrop)
    end
end

local function SkinDropDowns()
    -- 기존 레벨 스킨 -- [ESSENTIAL]
    for i = 1, (_G.UIDROPDOWNMENU_MAXLEVELS or 3) do
        SkinDropDown(i)
    end

    -- 새 레벨 생성 시 자동 스킨 -- [ESSENTIAL]
    if _G.UIDropDownMenu_CreateFrames then
        hooksecurefunc("UIDropDownMenu_CreateFrames", function(level)
            SkinDropDown(level)
        end)
    end

    -- 12.x Menu.GetManager 패턴 -- [ESSENTIAL]
    if _G.Menu and _G.Menu.GetManager then
        local manager = _G.Menu.GetManager()
        if manager then
            local function SkinContextMenu(mgr, ownerRegion, menuDescription)
                local menu = mgr:GetOpenMenu()
                if menu and not menu._ddeSkinned then
                    ns.StripTextures(menu)
                    ns.CreateBackdrop(menu)
                    menu._ddeSkinned = true
                end
                -- SubMenu 콜백 -- [ESSENTIAL]
                if menuDescription and menuDescription.AddMenuAcquiredCallback then
                    menuDescription:AddMenuAcquiredCallback(function(subMenu)
                        if subMenu and not subMenu._ddeSkinned then
                            ns.StripTextures(subMenu)
                            ns.CreateBackdrop(subMenu)
                            subMenu._ddeSkinned = true
                        end
                    end)
                end
            end
            hooksecurefunc(manager, "OpenMenu", SkinContextMenu)
            hooksecurefunc(manager, "OpenContextMenu", SkinContextMenu)
        end
    end
end

------------------------------------------------------------------------
-- 5. ReadyCheck / LFDRoleCheck / GhostFrame -- [ESSENTIAL]
------------------------------------------------------------------------
local function SkinReadyCheck()
    local rc = _G.ReadyCheckFrame
    if not rc or rc._ddeSkinned then return end
    rc._ddeSkinned = true

    ns.StripTextures(rc)
    ns.CreateBackdrop(rc)
    CreateAccentLine(rc)

    -- ReadyCheckPortrait 제거 (ElvUI: Kill) -- [ESSENTIAL]
    local portrait = _G.ReadyCheckPortrait
    if portrait then portrait:SetAlpha(0); portrait:Hide() end

    -- 버튼 -- [ESSENTIAL]
    local yesBtn = _G.ReadyCheckFrameYesButton
    local noBtn = _G.ReadyCheckFrameNoButton
    if yesBtn then
        ns.HandleButton(yesBtn)
        yesBtn:SetParent(rc)
        yesBtn:ClearAllPoints()
        yesBtn:SetPoint("TOPRIGHT", rc, "CENTER", -3, -5)
    end
    if noBtn then
        ns.HandleButton(noBtn)
        noBtn:SetParent(rc)
        noBtn:ClearAllPoints()
        noBtn:SetPoint("TOPLEFT", rc, "CENTER", 3, -5)
    end

    -- 텍스트 재배치 (ElvUI Misc.lua L44-46) -- [ESSENTIAL]
    local text = _G.ReadyCheckFrameText
    if text then
        text:ClearAllPoints()
        text:SetPoint("TOP", 0, -30)
        text:SetWidth(300)
    end
end

local function SkinLFDRoleCheck()
    local popup = _G.LFDRoleCheckPopup
    if not popup or popup._ddeSkinned then return end
    popup._ddeSkinned = true

    ns.StripTextures(popup)
    ns.CreateBackdrop(popup)
    CreateAccentLine(popup)

    -- Accept / Decline 버튼 -- [ESSENTIAL]
    if _G.LFDRoleCheckPopupAcceptButton then
        ns.HandleButton(_G.LFDRoleCheckPopupAcceptButton)
    end
    if _G.LFDRoleCheckPopupDeclineButton then
        ns.HandleButton(_G.LFDRoleCheckPopupDeclineButton)
    end
end

local function SkinGhostFrame()
    local gf = _G.GhostFrame
    if not gf or gf._ddeSkinned then return end
    gf._ddeSkinned = true

    ns.StripTextures(gf)
    -- GhostFrame 알파 -- [ESSENTIAL]
    if _G.GhostFrameMiddle then _G.GhostFrameMiddle:SetAlpha(0) end
    if _G.GhostFrameRight then _G.GhostFrameRight:SetAlpha(0) end
    if _G.GhostFrameLeft then _G.GhostFrameLeft:SetAlpha(0) end

    -- ContentsFrame 스킨 -- [ESSENTIAL]
    local contentsFrame = _G.GhostFrameContentsFrame
    if contentsFrame then
        ns.CreateBackdrop(contentsFrame)
    end

    -- 아이콘 TexCoord -- [ESSENTIAL]
    local icon = _G.GhostFrameContentsFrameIcon
    if icon then
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

------------------------------------------------------------------------
-- 6. Phase 2: OnDemand 스킨 -- [ESSENTIAL]
------------------------------------------------------------------------
ns.onDemandSkins = ns.onDemandSkins or {}
local onDemandSkins = ns.onDemandSkins

-- 외부 스킨 파일에서 사용할 수 있도록 노출 -- [ESSENTIAL]
ns.SkinAccentLine = CreateAccentLine

--- CharacterFrame: BFI급 Deep Skinning -- [ESSENTIAL]
onDemandSkins["Blizzard_CharacterUI"] = function()
    local cf = _G.CharacterFrame
    if not cf or cf._ddeSkinned then return end
    ns.HandleFrame(cf)
    CreateAccentLine(cf)

    -- ★ 탭 (HandleTab 사용 — PanelTemplates_UpdateTabs 후킹 자동 적용) -- [ESSENTIAL]
    local i = 1
    while _G["CharacterFrameTab"..i] do
        local tab = _G["CharacterFrameTab"..i]
        ns.HandleTab(tab)
        i = i + 1
    end

    -- Insets -- [ESSENTIAL]
    if _G.CharacterFrameInset then ns.StripTextures(_G.CharacterFrameInset) end
    if _G.CharacterFrameInsetRight then ns.StripTextures(_G.CharacterFrameInsetRight) end

    -- ★ PaperDollFrame 배경 제거 -- [ESSENTIAL]
    local pdf = _G.PaperDollFrame
    if pdf then ns.StripTextures(pdf) end

    -- ★ 장비 슬롯 16개 Deep Skinning (BFI StyleSlots 패턴) -- [ESSENTIAL]
    local pdif = _G.PaperDollItemsFrame
    if pdif then
        local allSlots = {}
        if pdif.EquipmentSlots then
            for _, s in ipairs(pdif.EquipmentSlots) do allSlots[#allSlots+1] = s end
        end
        if pdif.WeaponSlots then
            for _, s in ipairs(pdif.WeaponSlots) do allSlots[#allSlots+1] = s end
        end

        for _, slot in next, allSlots do
            ns.HandleItemButton(slot)

            -- 장비 해제 텍스처 복원 -- [ESSENTIAL]
            if slot.ignoreTexture then
                slot.ignoreTexture:SetTexture("Interface/PaperDollInfoFrame/UI-GearManager-LeaveItem-Transparent")
            end
        end
    end

    -- ★ 모델씬 배경 정리 (BFI StyleCharacterModelScene 패턴) -- [ESSENTIAL]
    local modelScene = _G.CharacterModelScene
    if modelScene then
        -- PaperDollInnerBorder* 제거 -- [ESSENTIAL]
        local positions = {
            "Top", "TopLeft", "TopRight", "Left", "Right",
            "Bottom", "Bottom2", "BottomLeft", "BottomRight", "BotLeft", "BotRight",
        }
        for _, pos in next, positions do
            local tex = _G["PaperDollInnerBorder"..pos]
            if tex then tex:SetAlpha(0) end
            tex = _G["CharacterModelFrameBackground"..pos]
            if tex then tex:SetAlpha(0) end
        end

        -- 오버레이 다크 배경 -- [ESSENTIAL]
        local overlay = _G.CharacterModelFrameBackgroundOverlay
        if overlay then
            overlay:SetColorTexture(0.06, 0.06, 0.06, 0.8)
        end
    end

    -- ★ 사이드바 탭 (스탯/타이틀/장비 관리자) -- [ESSENTIAL]
    local sidebarTabs = _G.PaperDollSidebarTabs
    if sidebarTabs then
        ns.StripTextures(sidebarTabs)
        if sidebarTabs.DecorLeft then sidebarTabs.DecorLeft:SetAlpha(0) end
        if sidebarTabs.DecorRight then sidebarTabs.DecorRight:SetAlpha(0) end

        -- 각 사이드바 탭 -- [ESSENTIAL]
        for i = 1, 3 do
            local tab = sidebarTabs["Tab"..i] or _G["PaperDollSidebarTab"..i]
            if tab then
                ns.StripTextures(tab)
                tab:SetHighlightTexture("")
            end
        end
    end

    -- ★ 스탯 패널 — StripTextures 하지 않음! 카테고리 접기/펼치기 깨짐 방지 -- [ESSENTIAL]
    -- 폰트만 교체 (배경은 부모 프레임에서 상속)
    local statsPane = _G.CharacterStatsPane
    if statsPane then
        local categories = { statsPane.EnhancementsCategory, statsPane.ItemLevelCategory }
        for _, cat in ipairs(categories) do
            if cat and cat.Title then
                ns.SetFont(cat.Title, (SL and SL.Font and SL.Font.normal) or 12, "")
            end
        end
    end

    -- ★ 평판 프레임 -- [ESSENTIAL]
    local repFrame = _G.ReputationFrame
    if repFrame then
        ns.StripTextures(repFrame)

        -- 평판 바 후킹: 동적 업데이트 -- [ESSENTIAL]
        if repFrame.UpdateRow then
            hooksecurefunc(repFrame, "UpdateRow", function(self, row)
                if row and not row._ddeSkinned then
                    row._ddeSkinned = true
                    if row.Background then row.Background:SetAlpha(0) end
                    local bar = row.ReputationBar
                    if bar then
                        ns.HandleStatusBar(bar)
                    end
                end
            end)
        end
    end

    -- ★ 통화(토큰) 프레임 -- [ESSENTIAL]
    local tokenFrame = _G.TokenFrame
    if tokenFrame then
        ns.StripTextures(tokenFrame)
        if tokenFrame.Inset then ns.StripTextures(tokenFrame.Inset) end
        -- 스크롤바 -- [ESSENTIAL]
        if tokenFrame.ScrollBar then ns.HandleScrollBar(tokenFrame.ScrollBar) end
    end

    -- 통화 팝업 -- [ESSENTIAL]
    local tokenPopup = _G.TokenFramePopup
    if tokenPopup then
        ns.HandleFrame(tokenPopup)
        if tokenPopup.CloseButton then ns.HandleCloseButton(tokenPopup.CloseButton) end
    end

    -- ★ CurrencyTransferLog -- [ESSENTIAL]
    local ctl = _G.CurrencyTransferLog
    if ctl then
        ns.HandleFrame(ctl)
    end

    -- ★ EquipmentFlyout 동적 후킹 -- [ESSENTIAL]
    if _G.EquipmentFlyoutFrame then
        local flyout = _G.EquipmentFlyoutFrame
        ns.StripTextures(flyout)
        ns.CreateBackdrop(flyout, {0.08, 0.08, 0.08, 0.95}, {0.2, 0.2, 0.2, 0.8})

        if _G.EquipmentFlyoutFrameHighlight then
            _G.EquipmentFlyoutFrameHighlight:SetAlpha(0)
        end
        if _G.EquipmentFlyoutFrameButtons then
            _G.EquipmentFlyoutFrameButtons:DisableDrawLayer("ARTWORK")
            if _G.EquipmentFlyoutFrameButtons.bg1 then
                _G.EquipmentFlyoutFrameButtons.bg1:SetAlpha(0)
            end
        end

        -- 플라이아웃 아이템 버튼 동적 후킹 -- [ESSENTIAL]
        if EquipmentFlyout_UpdateItems then
            hooksecurefunc("EquipmentFlyout_UpdateItems", function()
                if flyout.buttons then
                    for _, btn in next, flyout.buttons do
                        if not btn._ddeSkinned then
                            ns.HandleItemButton(btn)
                        end
                    end
                end
            end)
        end
    end
end

--- SpellBook / PlayerSpells
onDemandSkins["Blizzard_PlayerSpells"] = function()
    local sbf = _G.PlayerSpellsFrame or _G.SpellBookFrame
    if not sbf or sbf._ddeSkinned then return end
    ns.HandleFrame(sbf)
    CreateAccentLine(sbf)
end

--- WorldMap
onDemandSkins["Blizzard_WorldMap"] = function()
    local wmf = _G.WorldMapFrame
    if not wmf or wmf._ddeSkinned then return end
    wmf._ddeSkinned = true

    -- BorderFrame만 스킨 (맵 캔버스 건드리지 않음) -- [ESSENTIAL]
    local borderFrame = wmf.BorderFrame
    if borderFrame then
        ns.StripTextures(borderFrame)

        -- 타이틀바 -- [ESSENTIAL]
        local titleBg = borderFrame:CreateTexture(nil, "BACKGROUND")
        titleBg:SetTexture(FLAT)
        titleBg:SetVertexColor(ns.GetColor("bg.main"))
        titleBg:SetHeight(28)
        titleBg:SetPoint("TOPLEFT", 0, 0)
        titleBg:SetPoint("TOPRIGHT", 0, 0)

        CreateAccentLine(borderFrame)

        local closeBtn = borderFrame.CloseButton
        if closeBtn then ns.HandleCloseButton(closeBtn) end
    end
end

--- QuestLog
onDemandSkins["Blizzard_QuestLog"] = function()
    local qmf = _G.QuestMapFrame
    if not qmf or qmf._ddeSkinned then return end
    qmf._ddeSkinned = true

    if qmf.DetailsFrame then
        ns.StripTextures(qmf.DetailsFrame)
        -- 퀘스트 버튼들 -- [ESSENTIAL]
        local df = qmf.DetailsFrame
        if df.CompleteQuestFrame and df.CompleteQuestFrame.CompleteButton then
            ns.HandleButton(df.CompleteQuestFrame.CompleteButton)
        end
        if df.AbandonButton then ns.HandleButton(df.AbandonButton) end
        if df.TrackButton then ns.HandleButton(df.TrackButton) end
        if df.ShareButton then ns.HandleButton(df.ShareButton) end
    end
end

------------------------------------------------------------------------
-- OnDemand 등록 -- [ESSENTIAL]
------------------------------------------------------------------------
local function RegisterOnDemandSkins()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:SetScript("OnEvent", function(_, event, addonName)
        if event == "ADDON_LOADED" and onDemandSkins[addonName] then
            C_Timer.After(0.1, function()
                local ok, err = pcall(onDemandSkins[addonName])
                if not ok then
                    print("|cffff0000DDingUI Essential Skin error ("..addonName.."): "..tostring(err).."|r")
                end
            end)
        end
    end)
end

------------------------------------------------------------------------
-- Enable / Disable -- [ESSENTIAL]
------------------------------------------------------------------------
function BlizzardSkins:Enable()
    if self._deSkinned then return end

    -- StyleLib 재확인 -- [ESSENTIAL]
    SL = _G.DDingUI_StyleLib
    FLAT = (SL and SL.Textures and SL.Textures.flat) or FLAT
    SL_FONT = (SL and SL.Font and SL.Font.path) or SL_FONT

    -- 악센트 캐시 -- [ESSENTIAL]
    if SL and SL.GetAccent then
        accentFrom, accentTo = SL.GetAccent("Essential")
    end

    local db = ns.db and ns.db.skins or {}

    -- Phase 1: 기본 프레임 스킨 -- [ESSENTIAL]
    if db.gameMenu ~= false then
        local ok, err = pcall(SkinGameMenu)
        if not ok then print("|cffff0000Skins(GameMenu): "..tostring(err).."|r") end
    end

    if db.staticPopup ~= false then
        local ok, err = pcall(SkinStaticPopups)
        if not ok then print("|cffff0000Skins(StaticPopup): "..tostring(err).."|r") end
    end

    if db.tooltip ~= false then
        local ok, err = pcall(SkinTooltips)
        if not ok then print("|cffff0000Skins(Tooltip): "..tostring(err).."|r") end
    end

    if db.dropdown ~= false then
        local ok, err = pcall(SkinDropDowns)
        if not ok then print("|cffff0000Skins(DropDown): "..tostring(err).."|r") end
    end

    if db.readyCheck ~= false then
        if _G.ReadyCheckFrame then
            local ok, err = pcall(SkinReadyCheck)
            if not ok then print("|cffff0000Skins(ReadyCheck): "..tostring(err).."|r") end
        end
    end

    if db.lfgPopup ~= false then
        if _G.LFDRoleCheckPopup then
            local ok, err = pcall(SkinLFDRoleCheck)
            if not ok then print("|cffff0000Skins(LFDRole): "..tostring(err).."|r") end
        end
    end

    if db.ghostFrame ~= false then
        if _G.GhostFrame then
            local ok, err = pcall(SkinGhostFrame)
            if not ok then print("|cffff0000Skins(GhostFrame): "..tostring(err).."|r") end
        end
    end

    -- Phase 1.5: Alerts (즉시 훅) -- [ESSENTIAL]
    pcall(function()
        -- 알림 프레임 공용 스킨 함수 -- [ESSENTIAL]
        local function SkinAlertFrame(frame)
            if not frame or frame._ddeSkinned then return end
            frame._ddeSkinned = true
            frame:SetAlpha(1)
            hooksecurefunc(frame, "SetAlpha", function(self, alpha)
                if alpha ~= 1 then self:SetAlpha(1) end
            end)
            -- 배경/효과 제거 -- [ESSENTIAL]
            if frame.Background then frame.Background:SetTexture(nil) end
            if frame.glow then frame.glow:SetAlpha(0) end
            if frame.shine then frame.shine:SetAlpha(0) end
            if frame.BGAtlas then frame.BGAtlas:SetAlpha(0) end
            -- 백드롭 -- [ESSENTIAL]
            ns.CreateBackdrop(frame, {0.08, 0.08, 0.08, 0.9}, {0.2, 0.2, 0.2, 0.8})
            -- 아이콘 -- [ESSENTIAL]
            local icon = frame.Icon or (frame.lootItem and frame.lootItem.Icon)
            if icon then
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                if icon.Overlay then icon.Overlay:SetAlpha(0) end
            end
        end

        -- 주요 알림 시스템 훅 -- [ESSENTIAL]
        local alertSystems = {
            "AchievementAlertSystem", "CriteriaAlertSystem",
            "DungeonCompletionAlertSystem", "GuildChallengeAlertSystem",
            "ScenarioAlertSystem", "WorldQuestCompleteAlertSystem",
            "LegendaryItemAlertSystem", "LootAlertSystem", "LootUpgradeAlertSystem",
            "MoneyWonAlertSystem", "HonorAwardedAlertSystem",
            "DigsiteCompleteAlertSystem", "NewRecipeLearnedAlertSystem",
            "EntitlementDeliveredAlertSystem", "RafRewardDeliveredAlertSystem",
            "GarrisonFollowerAlertSystem", "GarrisonMissionAlertSystem",
            "GarrisonTalentAlertSystem", "GarrisonBuildingAlertSystem",
            "MonthlyActivityAlertSystem", "InvasionAlertSystem",
        }
        for _, sysName in ipairs(alertSystems) do
            local sys = _G[sysName]
            if sys and sys.setUpFunction then
                hooksecurefunc(sys, "setUpFunction", SkinAlertFrame)
            end
        end
    end)

    -- Phase 1.5: MirrorTimers (숨 참기 등) -- [ESSENTIAL]
    pcall(function()
        if _G.MirrorTimerContainer and _G.MirrorTimerContainer.SetupTimer then
            hooksecurefunc(_G.MirrorTimerContainer, "SetupTimer", function(container, timer)
                local bar = container:GetAvailableTimer(timer)
                if bar and not bar._ddeSkinned then
                    bar._ddeSkinned = true
                    ns.StripTextures(bar)
                    ns.CreateBackdrop(bar, {0.08, 0.08, 0.08, 0.85}, {0.2, 0.2, 0.2, 0.8})
                end
            end)
        end
    end)

    -- Phase 1.5: BattleNet (토스트/신고/초대) -- [ESSENTIAL]
    pcall(function()
        local bnetFrames = { _G.BNToastFrame, _G.TimeAlertFrame }
        for _, f in ipairs(bnetFrames) do
            if f and not f._ddeSkinned then
                f._ddeSkinned = true
                ns.StripTextures(f)
                ns.CreateBackdrop(f)
            end
        end
        -- 신고 프레임 -- [ESSENTIAL]
        local rf = _G.ReportFrame
        if rf and not rf._ddeSkinned then
            rf._ddeSkinned = true
            ns.StripTextures(rf)
            ns.CreateBackdrop(rf)
            if rf.CloseButton then ns.HandleCloseButton(rf.CloseButton) end
            if rf.ReportButton then ns.HandleButton(rf.ReportButton) end
            if rf.Comment then ns.HandleEditBox(rf.Comment) end
        end
        -- 배틀태그 초대 -- [ESSENTIAL]
        local btif = _G.BattleTagInviteFrame
        if btif and not btif._ddeSkinned then
            btif._ddeSkinned = true
            ns.StripTextures(btif)
            ns.CreateBackdrop(btif)
            for _, child in ipairs({btif:GetChildren()}) do
                if child:IsObjectType("Button") then
                    ns.HandleButton(child)
                end
            end
        end
    end)

    -- Phase 2: OnDemand -- [ESSENTIAL]
    if db.phase2 ~= false then
        -- 이미 로드된 애드온 스킨 -- [ESSENTIAL]
        for addonName, skinFunc in pairs(onDemandSkins) do
            if C_AddOns.IsAddOnLoaded(addonName) then
                local ok, err = pcall(skinFunc)
                if not ok then print("|cffff0000Skins("..addonName.."): "..tostring(err).."|r") end
            end
        end
        RegisterOnDemandSkins()
    end

    self._deSkinned = true
end

function BlizzardSkins:Disable()
    -- 훅은 해제 불가 → ReloadUI 필요 -- [ESSENTIAL]
end

------------------------------------------------------------------------
-- 모듈 등록 -- [ESSENTIAL]
------------------------------------------------------------------------
ns:RegisterModule("skins", BlizzardSkins)

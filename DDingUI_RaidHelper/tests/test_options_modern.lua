local addonName = "DDingUI_RaidHelper"

local function Noop() end

local methods = {}

function methods:SetSize(width, height)
    self.width = width
    self.height = height
end

function methods:SetWidth(width) self.width = width end
function methods:SetHeight(height) self.height = height end
function methods:GetWidth() return self.width or 640 end
function methods:GetHeight() return self.height or 500 end
function methods:GetFrameLevel() return rawget(self, "frameLevel") or 1 end
function methods:GetScale() return 1 end
function methods:GetEffectiveScale() return 1 end
function methods:GetName() return rawget(self, "name") end
function methods:SetPoint() end
function methods:ClearAllPoints() end
function methods:SetAllPoints() end
function methods:SetBackdrop() end
function methods:SetBackdropColor() end
function methods:SetBackdropBorderColor() end
function methods:SetColorTexture() end
function methods:SetTexture(value) self.texture = value end
function methods:SetTexCoord() end
function methods:SetText(value) self.text = tostring(value or "") end
function methods:GetText() return self.text or "" end
function methods:SetTextColor() end
function methods:SetFont() end
function methods:SetJustifyH() end
function methods:SetJustifyV() end
function methods:SetWordWrap() end
function methods:SetAlpha(value) self.alpha = value end
function methods:SetEnabled(value) self.enabled = value end
function methods:EnableMouse() end
function methods:EnableMouseWheel() end
function methods:RegisterForClicks() end
function methods:RegisterForDrag() end
function methods:SetMovable() end
function methods:SetResizable() end
function methods:SetResizeBounds() end
function methods:SetClampedToScreen() end
function methods:SetFrameStrata() end
function methods:SetFrameLevel(value) self.frameLevel = value end
function methods:StartMoving() end
function methods:StartSizing() end
function methods:StopMovingOrSizing() end
function methods:SetScript(event, handler) self.scripts[event] = handler end
function methods:HookScript(event, handler) self.scripts[event] = handler end
function methods:Show() self.shown = true end
function methods:Hide() self.shown = false end
function methods:SetShown(value) self.shown = value == true end
function methods:IsShown() return self.shown == true end
function methods:SetScrollChild(child) self.scrollChild = child end
function methods:GetScrollChild() return self.scrollChild end
function methods:SetVerticalScroll(value) self.verticalScroll = value end
function methods:GetVerticalScroll() return self.verticalScroll or 0 end
function methods:SetChecked(value) self.checked = value == true end
function methods:GetChecked() return self.checked == true end
function methods:SetDisabledState(value) self.disabled = value == true end

local function NewObject(name)
    local object = {
        name = name,
        shown = true,
        scripts = {},
        width = 640,
        height = 500,
    }
    object.CreateFontString = function() return NewObject() end
    object.CreateTexture = function() return NewObject() end
    return setmetatable(object, {
        __index = function(_, key)
            return methods[key] or Noop
        end,
    })
end

UIParent = NewObject("UIParent")
UISpecialFrames = {}
CreateFrame = function(_, name) return NewObject(name) end
InCombatLockdown = function() return false end
GameTooltip = { Hide = Noop }
C_Timer = { After = function(_, callback) callback() end }
C_AddOns = { GetAddOnMetadata = function() return "0.1.0" end }
C_Spell = {
    GetSpellName = function(spellID) return "Spell " .. tostring(spellID) end,
    GetSpellTexture = function(spellID) return spellID end,
}

local colors = {
    bg = {
        main = { 0.1, 0.1, 0.1, 0.95 },
        sidebar = { 0.08, 0.08, 0.08, 0.95 },
        input = { 0.06, 0.06, 0.06, 0.8 },
        widget = { 0.06, 0.06, 0.06, 0.8 },
        hover = { 0.2, 0.2, 0.2, 0.6 },
        selected = { 0.18, 0.18, 0.22, 0.8 },
        titlebar = { 0.12, 0.12, 0.12, 0.98 },
    },
    text = {
        normal = { 0.85, 0.85, 0.85, 1 },
        highlight = { 1, 1, 1, 1 },
        disabled = { 0.5, 0.5, 0.5, 1 },
        dim = { 0.6, 0.6, 0.6, 1 },
    },
    border = {
        default = { 0.25, 0.25, 0.25, 0.5 },
        active = { 0.4, 0.4, 0.4, 0.7 },
        separator = { 0.2, 0.2, 0.2, 0.4 },
    },
    status = {
        success = { 0.3, 0.8, 0.3, 1 },
        warning = { 0.9, 0.75, 0.2, 1 },
        error = { 0.9, 0.25, 0.25, 1 },
    },
}

local function CreateSearchBox()
    local search = NewObject()
    search.editBox = NewObject()
    function search:SetOnTextChanged(callback) self.callback = callback end
    function search:SetText(text)
        self.text = text or ""
        if self.callback then self.callback(self.text) end
    end
    function search:GetText() return self.text or "" end
    return search
end

local createdButtonTexts = {}
local createdButtons = {}
local motionCalls = { indicators = {}, rowHover = 0, stagger = {}, applied = {}, cancelled = {} }
-- [STYLE] StyleLib 1.3 rounded API calls (시안 7).
local roundCalls = { frames = {}, textures = {}, rings = 0, watermark = nil, titleBarOnRounded = nil }

local function CreateButton(_, _, text, callback)
    local button = NewObject()
    button.callback = callback
    button.label = NewObject()
    button.label:SetText(text)
    createdButtonTexts[#createdButtonTexts + 1] = text
    createdButtons[text] = button
    return button
end

local function CreateSlider(_, _, _, _, _, _, initial, options)
    local container = NewObject()
    local slider = NewObject()
    slider.value = initial
    function slider:SetValue(value)
        self.value = value
        if options.onChange then options.onChange(value) end
    end
    function slider:GetValue() return self.value end
    container.slider = slider
    return container
end

-- RaidHelper only reads its private embedded StyleLib global.
DDingUI_RaidHelperStyleLib = {
    Colors = colors,
    Font = { path = "font", title = 14, normal = 13, small = 11 },
    GetFont = function() return "font" end,
    GetAccent = function()
        return { 0.84, 0.36, 1, 1 }, { 0.45, 0.16, 0.68, 1 }
    end,
    CreateTitleBar = function(parent, _, _, _, opts)
        roundCalls.titleBarOnRounded = rawget(parent, "_ddslRounded") ~= nil
        local titleBar = NewObject()
        titleBar.titleText = NewObject()
        titleBar.verText = NewObject()
        titleBar.closeBtn = NewObject()
        titleBar.CreateTexture = function() return NewObject() end
        titleBar.titleText.SetFont = function() error("title font must stay on the shared title bar") end
        titleBar.verText.SetPoint = function() error("version position must stay on the shared title bar") end
        if opts and opts.scale then
            titleBar.scaleConfig = opts.scale
            titleBar.scaleControl = NewObject()
        end
        if opts and opts.editMode then
            local em = opts.editMode
            local editButton = NewObject()
            editButton.label = NewObject()
            editButton.click = em.onClick
            function editButton:Refresh()
                self.label:SetText(em.isActive() and "편집 중" or "편집 모드")
            end
            editButton:Refresh()
            titleBar.editButton = editButton
        end
        return titleBar
    end,
    CreateIndicator = function(parent, width, height, color, opts)
        local indicator = NewObject()
        indicator.parent = parent
        indicator.args = { width = width, height = height, color = color, opts = opts }
        function indicator:MoveTo(row, animate)
            self.row = row
            self.animated = animate
            self.shown = true
        end
        function indicator:HideIndicator()
            self.row = nil
            self.shown = false
        end
        motionCalls.indicators[#motionCalls.indicators + 1] = indicator
        return indicator
    end,
    RowHover = function(row, opts)
        assert(opts.bg == row.background and opts.hover and opts.normal and opts.isActive)
        motionCalls.rowHover = motionCalls.rowHover + 1
    end,
    StaggerIn = function(regions, opts)
        motionCalls.stagger[#motionCalls.stagger + 1] = { regions = regions, opts = opts }
    end,
    CancelAppliedFeedback = function(label)
        motionCalls.cancelled[#motionCalls.cancelled + 1] = label
    end,
    AppliedFeedback = function(button, label, opts)
        motionCalls.applied[#motionCalls.applied + 1] = { button = button, label = label, text = opts and opts.text }
    end,
    Rounded = true,
    Radius = { window = 14, card = 10, row = 8, control = 6, check = 4, track = 2 },
    MakeRounded = function(frame, radius, bg, border)
        assert(type(bg) == "table" and type(border) == "table")
        frame._ddslRounded = { radius = radius }
        roundCalls.frames[#roundCalls.frames + 1] = frame
    end,
    RoundTexture = function(texture, radius)
        texture._ddslRoundTex = radius
        roundCalls.textures[#roundCalls.textures + 1] = texture
        return texture
    end,
    CreateStatusRing = function(parent, size)
        roundCalls.rings = roundCalls.rings + 1
        local ring = NewObject()
        ring.ringSize = size
        return ring
    end,
    AddWatermark = function(parent, key, opts)
        roundCalls.watermark = { parent = parent, key = key, opts = opts }
        return NewObject()
    end,
    CreateSearchBox = CreateSearchBox,
    CreateButton = CreateButton,
    CreateSlider = CreateSlider,
    EnableRightClickMouselook = Noop,
}

local ns = {
    addonName = addonName,
    db = {
        optionsScale = 1.2,
        showTooltips = false,
        showUpcomingCooldowns = true,
        timelineScale = 1,
        timelineWidth = 680,
        timelineHeight = 210,
        backgroundAlpha = 1,
        cooldownVisibility = {},
    },
    Print = Noop,
    Registry = {
        GetByKey = function() return { name = "Demo" } end,
        GetDataSummary = function()
            return {
                modelCount = 11,
                heroicCount = 9,
                mythicCount = 2,
                latestGeneratedAt = "2026-08-24T10:15:06+00:00",
            }
        end,
    },
    Engine = {
        playerSpecID = 257,
        RefreshPlayerSpecialization = function(self) return self.playerSpecID end,
        GetHealerProfile = function() return nil end,
        GetModel = function() return nil end,
    },
    HealerProfileUI = {
        GetSummary = function() return "현재 전문화의 수집 데이터가 없습니다." end,
    },
    TimelineUI = {
        previewMode = false,
        IsPreviewMode = function(self) return self.previewMode == true end,
        TogglePreviewMode = function(self)
            self.previewMode = not self.previewMode
            return true
        end,
        ResetPosition = Noop,
    },
}

assert(loadfile("Data/CooldownCatalog.lua"))(addonName, ns)
assert(loadfile("Options.lua"))(addonName, ns)
assert(loadfile("UI/OptionsWindow.lua"))(addonName, ns)
ns.Options:Initialize()

assert(ns.Options.initialized)
assert(ns.Options.modernWorkspace)
assert(ns.Options.independentWindow)
assert(ns.Options.activePage == "timeline")
assert(ns.Options.pages.timeline:IsShown())
assert(not ns.Options.pages.cooldowns:IsShown())
assert(ns.Options.pages.preview == nil)
assert(ns.Options.panel.editButton == nil)
assert(ns.Options.panel.moduleFrame ~= nil)
assert(ns.Options.panel.contentHeader ~= nil)
assert(ns.Options.upcomingCooldownCheckbox:GetChecked())
-- [STYLE] "곧 사용" voice countdown: switch + 미리 듣기, applies at once (also in combat).
assert(ns.Options.countdownVoiceCheckbox and ns.Options.voicePreviewButton)
assert(ns.Options.countdownVoiceCheckbox:GetChecked())
assert(ns.Options:SetCountdownVoiceEnabled(false) and ns.db.countdownVoice == false)
assert(not ns.Options.countdownVoiceCheckbox:GetChecked())
assert(ns.Options:SetCountdownVoiceEnabled(true) and ns.db.countdownVoice == true)
assert(ns.Options.countdownVoiceCheckbox:GetChecked())
assert(#ns.Options.cooldownCheckboxes[257] >= 10)
assert(ns.Options.panel.workspace.primaryRows[1].icon.texture:find("RaidTimeline.tga", 1, true))
assert(ns.Options.panel.workspace.primaryRows[2].icon.texture:find("HealerPlan.tga", 1, true))
assert(ns.Options.panel.workspace.primaryRows[3].icon.texture:find("LogData.tga", 1, true))

local previewButtonCount = 0
for _, text in ipairs(createdButtonTexts) do
    if text == "미리보기" then previewButtonCount = previewButtonCount + 1 end
    assert(text ~= "미리보기 시작")
    assert(text ~= "편집 모드")
    assert(text ~= "표시 중지")
end
assert(previewButtonCount == 1)
assert(ns.Options.previewButton.label:GetText() == "미리보기")
ns.Options.previewButton.callback()
assert(ns.TimelineUI:IsPreviewMode())
assert(ns.Options.previewButton.label:GetText() == "미리보기 종료")
ns.Options.previewButton.callback()
assert(not ns.TimelineUI:IsPreviewMode())
assert(ns.Options.previewButton.label:GetText() == "미리보기")

-- C12: shared title-bar edit button toggles preview and follows its state.
local titleEdit = ns.Options.panel.titleBar.editButton
assert(titleEdit and titleEdit.label:GetText() == "편집 모드")
titleEdit.click()
assert(ns.TimelineUI:IsPreviewMode() and titleEdit.label:GetText() == "편집 중")
assert(ns.Options.previewButton.label:GetText() == "미리보기 종료")
titleEdit.click()
assert(not ns.TimelineUI:IsPreviewMode() and titleEdit.label:GetText() == "편집 모드")

ns.Options:SelectPage("cooldowns")
assert(ns.Options.activePage == "cooldowns")
assert(ns.Options.pages.cooldowns:IsShown())
assert(ns.Options.cooldownSpecFrames[257]:IsShown())
ns.Engine.playerSpecID = 251
ns.Options:RefreshCooldownControls()
assert(ns.Options.cooldownSpecFrames[251]:IsShown())
assert(#ns.Options.cooldownCheckboxes[251] == #ns.CooldownCatalog:GetSpec(251).spells)
ns.Engine.playerSpecID = 257
ns.Options:RefreshCooldownControls()

ns.Options:SelectPage("data")
assert(ns.Options.activePage == "data")
assert(ns.Options.pages.data:IsShown())

-- [STYLE] StyleLib 1.2 "정밀 다듬기" wiring.
local titleBar = ns.Options.panel.titleBar
assert(titleBar.scaleConfig and titleBar.scaleConfig.target == ns.Options.frame)
assert(math.abs(titleBar.scaleConfig.get() - 1.2) < 1e-9)
titleBar.scaleConfig.set(0.9)
assert(math.abs(ns.db.optionsScale - 0.9) < 1e-9)
titleBar.scaleConfig.set(9)
assert(ns.db.optionsScale == 1.5)
ns.db.optionsScale = "bad"
assert(ns.Options:GetOptionsScale() == 1.0)

local workspace = ns.Options.panel.workspace
assert(#motionCalls.indicators == 2)
assert(motionCalls.rowHover >= 4)
assert(workspace.primaryIndicator.row == workspace.primaryRows[3])
assert(workspace.moduleIndicator.row.pageKey == "data")
for _, row in ipairs(workspace.primaryRows) do assert(rawget(row, "activeBar") == nil) end
for _, row in ipairs(workspace.moduleRows) do assert(rawget(row, "activeBar") == nil) end

ns.Options:SelectPage("timeline")
assert(workspace.primaryIndicator.row == workspace.primaryRows[1])
assert(workspace.moduleIndicator.row.pageKey == "timeline")
ns.Options.panel.moduleSearch:SetText("zzzz")
assert(rawget(workspace.moduleIndicator, "row") == nil and not workspace.moduleIndicator:IsShown())
ns.Options.panel.moduleSearch:SetText("")
assert(workspace.moduleIndicator.row.pageKey == "timeline")

local staggerBefore = #motionCalls.stagger
ns.Options.frame:Hide()
ns.Options:SelectPage("data")
assert(#motionCalls.stagger == staggerBefore)
ns.Options.frame:Show()
ns.Options:SelectPage("profile")
local stagger = motionCalls.stagger[#motionCalls.stagger]
assert(#motionCalls.stagger == staggerBefore + 1)
assert(stagger.regions == ns.Options.pages.profile.rows and #stagger.regions == 3)
assert(stagger.opts.step == 0.03 and stagger.opts.offset == 4)
ns.Options:SelectPage("profile")
assert(#motionCalls.stagger == staggerBefore + 1)
for _, page in pairs(ns.Options.pages) do assert(#page.rows >= 2) end

createdButtons["주요만"].callback()
assert(motionCalls.applied[#motionCalls.applied].text == "적용됨")
assert(motionCalls.applied[#motionCalls.applied].label == createdButtons["주요만"].label)
-- presets are exclusive: the other four preset labels are restored immediately
assert(#motionCalls.cancelled == 4)
for _, label in ipairs(motionCalls.cancelled) do assert(label ~= createdButtons["주요만"].label) end
createdButtons["위치 초기화"].callback()
assert(motionCalls.applied[#motionCalls.applied].text == "초기화됨")

-- [STYLE] 시안 7: rounded window, three rounded cards, pill indicators, rings, watermark.
local panel = ns.Options.panel
assert(roundCalls.titleBarOnRounded == true, "window must be rounded before the title bar")
assert(ns.Options.frame._ddslRounded.radius == 14)
for _, card in ipairs({ panel.treeFrame, panel.moduleFrame, panel.detailCard }) do
    assert(card and card._ddslRounded and card._ddslRounded.radius == 10)
end
assert(rawget(panel.contentHeader, "_ddslRounded") == nil and rawget(panel.contentFrame, "_ddslRounded") == nil)
assert(workspace.primaryIndicator.parent == panel.treeFrame)
assert(workspace.moduleIndicator.parent == panel.moduleFrame)
for _, indicator in ipairs({ workspace.primaryIndicator, workspace.moduleIndicator }) do
    local args = indicator.args
    assert(args.opts.radius == 8 and args.opts.x == 4)
    assert(math.abs(args.color[4] - 0.18) < 1e-9)
end
assert(workspace.primaryIndicator.args.width == 174 and workspace.moduleIndicator.args.width == 224)
for _, row in ipairs(workspace.primaryRows) do
    assert(row.background._ddslRoundTex == 8)
    assert(rawget(row, "divider") == nil)
end
for _, row in ipairs(workspace.moduleRows) do assert(row.background._ddslRoundTex == 8) end
assert(roundCalls.rings == #workspace.moduleRows and roundCalls.rings >= 2)
assert(roundCalls.watermark and roundCalls.watermark.key == "RaidHelper")
assert(ns.Options.previewButton ~= nil and ns.Options.tooltipCheckbox._ddslRounded.radius == 6)

print("RaidHelper modern three-column options window test OK")

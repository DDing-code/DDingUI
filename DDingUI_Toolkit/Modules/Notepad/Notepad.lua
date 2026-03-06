--[[
    DDingToolKit - Notepad Module
    메모장 기능 (파티 모집용 메모 관리)
    DDingToolKit UI 테마 적용
]]

local addonName, ns = ...
local DDingToolKit = ns.DDingToolKit
local UI = ns.UI

-- 모듈 생성
local Notepad = {}
Notepad.name = "Notepad"
Notepad.enabled = false

-- 프레임 참조
local mainFrame, createFrame, detailFrame
local memoList, emptyMessage
local nameBox, titleBox, contentBox
local detailNameEdit, detailTitleEdit, detailContentEdit
local editingMemoIndex = nil
local selectedMemoIndex = nil

-- 로컬 함수 선언
local RefreshMemoList, ShowMemoDetail, UpdateRowHighlights

------------------------------------------------
-- 멀티라인 에디트 박스 생성 (UI 시스템에 없음)
------------------------------------------------
local function CreateMultiLineEditBox(parent, width, height)
    local container = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    container:SetSize(width or 200, height or 100)
    container:SetBackdrop(UI.backdrop)
    container:SetBackdropColor(unpack(UI.colors.panel))
    container:SetBackdropBorderColor(unpack(UI.colors.border))
    container:EnableMouse(true)

    -- 스크롤 프레임
    local scrollFrame = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 6, -6)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 6)
    scrollFrame:EnableMouse(true)

    -- 스크롤바 스타일링
    local scrollBar = scrollFrame.ScrollBar
    if scrollBar then
        scrollBar:ClearAllPoints()
        scrollBar:SetPoint("TOPRIGHT", container, "TOPRIGHT", -4, -18)
        scrollBar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -4, 18)
    end

    -- 에디트 박스
    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetWidth(width - 35)
    editBox:SetHeight(height - 12)  -- 최소 높이 설정
    editBox:SetFontObject("ChatFontNormal")
    editBox:SetTextColor(unpack(UI.colors.text))
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetJustifyH("LEFT")
    editBox:SetJustifyV("TOP")
    editBox:EnableMouse(true)
    editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    scrollFrame:SetScrollChild(editBox)
    container.editBox = editBox
    container.scrollFrame = scrollFrame

    -- 컨테이너 클릭 시 에디트박스 포커스
    container:SetScript("OnMouseDown", function()
        editBox:SetFocus()
    end)

    -- 스크롤프레임 클릭 시 에디트박스 포커스
    scrollFrame:SetScript("OnMouseDown", function()
        editBox:SetFocus()
    end)

    container:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.borderHover))
    end)

    container:SetScript("OnLeave", function(self)
        if not self.editBox:HasFocus() then
            self:SetBackdropBorderColor(unpack(UI.colors.border))
        end
    end)

    editBox:SetScript("OnEditFocusGained", function()
        container:SetBackdropBorderColor(unpack(UI.colors.borderFocus))
    end)

    editBox:SetScript("OnEditFocusLost", function()
        container:SetBackdropBorderColor(unpack(UI.colors.border))
    end)

    function container:SetText(text)
        self.editBox:SetText(text or "")
    end

    function container:GetText()
        return self.editBox:GetText()
    end

    function container:ClearFocus()
        self.editBox:ClearFocus()
    end

    return container
end

------------------------------------------------
-- [1] 메모 목록 메인 창
------------------------------------------------
local function CreateMainFrame()
    if mainFrame then return mainFrame end

    mainFrame = UI:CreateMainFrame(UIParent, 400, 500, "DDingToolKit_NotepadMainFrame")
    mainFrame:SetFrameLevel(20)

    -- 타이틀바
    local titleBar = UI:CreateTitleBar(mainFrame, "Memo List")
    mainFrame.titleBar = titleBar

    -- 컨텐츠 영역
    local content = UI:CreatePanel(mainFrame, 380, 400)
    content:SetPoint("TOP", titleBar, "BOTTOM", 0, -10)
    content:SetPoint("LEFT", 10, 0)
    content:SetPoint("RIGHT", -10, 0)
    content:SetPoint("BOTTOM", 60, 0)

    -- 메모 리스트 컨테이너
    memoList = CreateFrame("Frame", nil, content)
    memoList:SetPoint("TOPLEFT", 10, -10)
    memoList:SetPoint("BOTTOMRIGHT", -10, 10)

    -- 빈 메시지
    emptyMessage = memoList:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyMessage:SetText("저장된 메모가 없습니다.")
    emptyMessage:SetPoint("CENTER", memoList, "CENTER")
    emptyMessage:SetTextColor(unpack(UI.colors.textDim))
    emptyMessage:Show()

    -- 생성 버튼
    local createBtn = UI:CreateButton(mainFrame, 100, 32, "새 메모")
    createBtn:SetPoint("BOTTOM", mainFrame, "BOTTOM", 0, 15)
    createBtn:SetScript("OnClick", function()
        editingMemoIndex = nil
        nameBox:SetText("")
        titleBox:SetText("")
        contentBox:SetText("")
        createFrame:Show()
    end)

    -- ESC로 닫기
    tinsert(UISpecialFrames, "DDingToolKit_NotepadMainFrame")

    return mainFrame
end

------------------------------------------------
-- [2] 메모 생성/수정 창
------------------------------------------------
local function CreateCreateFrame()
    if createFrame then return createFrame end

    createFrame = UI:CreateMainFrame(UIParent, 420, 420, "DDingToolKit_NotepadCreateFrame")
    createFrame:SetFrameLevel(25)

    -- 타이틀바
    local titleBar = UI:CreateTitleBar(createFrame, "메모 작성")
    createFrame.titleBar = titleBar

    -- 컨텐츠 영역
    local content = UI:CreatePanel(createFrame, 400, 340)
    content:SetPoint("TOP", titleBar, "BOTTOM", 0, -10)
    content:SetPoint("LEFT", 10, 0)
    content:SetPoint("RIGHT", -10, 0)

    local yOffset = -15

    -- 메모 이름
    local nameLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetText("메모 이름")
    nameLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 15, yOffset)
    nameLabel:SetTextColor(unpack(UI.colors.text))
    yOffset = yOffset - 20

    nameBox = UI:CreateEditBox(content, 370, 28)
    nameBox:SetPoint("TOPLEFT", content, "TOPLEFT", 15, yOffset)
    yOffset = yOffset - 45

    -- 파티 이름
    local titleLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLabel:SetText("파티 이름")
    titleLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 15, yOffset)
    titleLabel:SetTextColor(unpack(UI.colors.text))
    yOffset = yOffset - 20

    titleBox = UI:CreateEditBox(content, 370, 28)
    titleBox:SetPoint("TOPLEFT", content, "TOPLEFT", 15, yOffset)
    yOffset = yOffset - 45

    -- 세부 정보
    local contentLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    contentLabel:SetText("세부 정보")
    contentLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 15, yOffset)
    contentLabel:SetTextColor(unpack(UI.colors.text))
    yOffset = yOffset - 20

    contentBox = CreateMultiLineEditBox(content, 370, 150)
    contentBox:SetPoint("TOPLEFT", content, "TOPLEFT", 15, yOffset)

    -- 버튼 영역
    local cancelBtn = UI:CreateButton(createFrame, 80, 32, "취소")
    cancelBtn:SetPoint("BOTTOMLEFT", createFrame, "BOTTOMLEFT", 15, 15)
    cancelBtn:SetScript("OnClick", function()
        createFrame:Hide()
    end)

    local saveBtn = UI:CreateButton(createFrame, 80, 32, "저장")
    saveBtn:SetPoint("BOTTOMRIGHT", createFrame, "BOTTOMRIGHT", -15, 15)
    saveBtn:SetScript("OnClick", function()
        local note = {
            name = nameBox:GetText(),
            title = titleBox:GetText(),
            content = contentBox:GetText(),
        }
        local savedNotes = Notepad.db.savedNotes
        if editingMemoIndex then
            savedNotes[editingMemoIndex] = note
            editingMemoIndex = nil
        else
            table.insert(savedNotes, note)
        end
        createFrame:Hide()
        RefreshMemoList()
    end)

    -- ESC로 닫기
    tinsert(UISpecialFrames, "DDingToolKit_NotepadCreateFrame")

    return createFrame
end

------------------------------------------------
-- [3] 상세보기 창
------------------------------------------------
local function CreateDetailFrame()
    if detailFrame then return detailFrame end

    detailFrame = UI:CreateMainFrame(UIParent, 320, 520, "DDingToolKit_NotepadDetailFrame")
    detailFrame:SetFrameLevel(25)
    detailFrame:ClearAllPoints()
    detailFrame:SetPoint("LEFT", mainFrame, "RIGHT", 10, 0)

    -- 타이틀바
    local titleBar = UI:CreateTitleBar(detailFrame, "메모 상세보기")
    detailFrame.titleBar = titleBar

    -- 컨텐츠 영역
    local content = UI:CreatePanel(detailFrame, 300, 420)
    content:SetPoint("TOP", titleBar, "BOTTOM", 0, -10)
    content:SetPoint("LEFT", 10, 0)
    content:SetPoint("RIGHT", -10, 0)

    local yOffset = -15

    -- 메모 이름
    local nameLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameLabel:SetText("메모 이름")
    nameLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 15, yOffset)
    nameLabel:SetTextColor(unpack(UI.colors.text))
    yOffset = yOffset - 20

    detailNameEdit = UI:CreateEditBox(content, 270, 28)
    detailNameEdit:SetPoint("TOPLEFT", content, "TOPLEFT", 15, yOffset)
    yOffset = yOffset - 45

    -- 파티 이름
    local titleLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleLabel:SetText("파티 이름")
    titleLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 15, yOffset)
    titleLabel:SetTextColor(unpack(UI.colors.text))
    yOffset = yOffset - 20

    detailTitleEdit = UI:CreateEditBox(content, 270, 28)
    detailTitleEdit:SetPoint("TOPLEFT", content, "TOPLEFT", 15, yOffset)
    yOffset = yOffset - 45

    -- 세부 정보
    local contentLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    contentLabel:SetText("세부 정보")
    contentLabel:SetPoint("TOPLEFT", content, "TOPLEFT", 15, yOffset)
    contentLabel:SetTextColor(unpack(UI.colors.text))
    yOffset = yOffset - 20

    detailContentEdit = CreateMultiLineEditBox(content, 270, 220)
    detailContentEdit:SetPoint("TOPLEFT", content, "TOPLEFT", 15, yOffset)

    -- 버튼 영역
    local closeBtn = UI:CreateButton(detailFrame, 80, 32, "닫기")
    closeBtn:SetPoint("BOTTOMLEFT", detailFrame, "BOTTOMLEFT", 15, 15)
    closeBtn:SetScript("OnClick", function() detailFrame:Hide() end)

    local editBtn = UI:CreateButton(detailFrame, 80, 32, "수정")
    editBtn:SetPoint("BOTTOM", detailFrame, "BOTTOM", 0, 15)
    editBtn:SetScript("OnClick", function()
        if selectedMemoIndex then
            local note = {
                name = detailNameEdit:GetText(),
                title = detailTitleEdit:GetText(),
                content = detailContentEdit:GetText(),
            }
            Notepad.db.savedNotes[selectedMemoIndex] = note
            RefreshMemoList()
        end
    end)

    local deleteBtn = UI:CreateButton(detailFrame, 80, 32, "삭제")
    deleteBtn:SetPoint("BOTTOMRIGHT", detailFrame, "BOTTOMRIGHT", -15, 15)
    -- 삭제 버튼은 빨간색 강조
    deleteBtn:SetBackdropColor(0.5, 0.1, 0.1, 0.95)
    deleteBtn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.borderHover))
        self:SetBackdropColor(0.6, 0.15, 0.15, 0.95)
    end)
    deleteBtn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.border))
        self:SetBackdropColor(0.5, 0.1, 0.1, 0.95)
    end)
    deleteBtn:SetScript("OnClick", function()
        if selectedMemoIndex then
            StaticPopup_Show("DDINGTOOLKIT_NOTEPAD_DELETE",
                Notepad.db.savedNotes[selectedMemoIndex].name,
                nil, selectedMemoIndex
            )
        end
    end)

    -- ESC로 닫기
    tinsert(UISpecialFrames, "DDingToolKit_NotepadDetailFrame")

    return detailFrame
end

------------------------------------------------
-- [4] 유틸리티 함수들
------------------------------------------------
UpdateRowHighlights = function()
    if not memoList or not memoList.rows then return end
    for i, row in ipairs(memoList.rows) do
        if i == selectedMemoIndex then
            row:SetBackdropColor(unpack(UI.colors.selected))
            row:SetBackdropBorderColor(unpack(UI.colors.accent))
        else
            row:SetBackdropColor(unpack(UI.colors.panel))
            row:SetBackdropBorderColor(unpack(UI.colors.border))
        end
    end
end

RefreshMemoList = function()
    if not Notepad.enabled or not Notepad.db then return end
    local savedNotes = Notepad.db.savedNotes

    if memoList.rows then
        for _, oldRow in ipairs(memoList.rows) do
            oldRow:Hide()
        end
    end
    memoList.rows = {}

    if #savedNotes == 0 then
        emptyMessage:Show()
    else
        emptyMessage:Hide()
    end

    for i, note in ipairs(savedNotes) do
        local row = CreateFrame("Frame", nil, memoList, "BackdropTemplate")
        row:SetSize(360, 36)
        row:SetBackdrop(UI.backdrop)
        row:SetBackdropColor(unpack(UI.colors.panel))
        row:SetBackdropBorderColor(unpack(UI.colors.border))
        row:EnableMouse(true)
        row:SetPoint("TOP", memoList, "TOP", 0, -((i - 1) * 40))

        -- 호버 효과
        row:SetScript("OnEnter", function(self)
            if i ~= selectedMemoIndex then
                self:SetBackdropBorderColor(unpack(UI.colors.borderHover))
            end
        end)

        row:SetScript("OnLeave", function(self)
            if i ~= selectedMemoIndex then
                self:SetBackdropBorderColor(unpack(UI.colors.border))
            end
        end)

        row:SetScript("OnMouseDown", function()
            selectedMemoIndex = i
            UpdateRowHighlights()
            ShowMemoDetail(note, i)
        end)

        -- 메모 이름
        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.nameText:SetPoint("LEFT", row, "LEFT", 15, 0)
        row.nameText:SetText(note.name or "")
        row.nameText:SetTextColor(unpack(UI.colors.text))
        row.nameText:SetWidth(340)
        row.nameText:SetJustifyH("LEFT")
        row:Show()

        memoList.rows[i] = row
    end

    UpdateRowHighlights()
end

ShowMemoDetail = function(note, index)
    if note then
        selectedMemoIndex = index
        detailNameEdit:SetText(note.name or "")
        detailTitleEdit:SetText(note.title or "")
        detailContentEdit:SetText(note.content or "")
        detailFrame:ClearAllPoints()
        detailFrame:SetPoint("LEFT", mainFrame, "RIGHT", 10, 0)
        detailFrame:Show()
    end
end

------------------------------------------------
-- [5] PVEFrame 연동
------------------------------------------------
local pveToggleButton = nil

local function CreatePVEToggleButton()
    if not Notepad.enabled then return end
    if not Notepad.db.showPVEButton then return end
    if not PVEFrame then return end
    if pveToggleButton then return end

    -- DDingToolKit 스타일 버튼
    pveToggleButton = CreateFrame("Button", "DDingToolKit_NotepadPVEButton", PVEFrame, "BackdropTemplate")
    pveToggleButton:SetSize(80, 24)
    pveToggleButton:SetBackdrop(UI.backdrop)
    pveToggleButton:SetBackdropColor(unpack(UI.colors.panel))
    pveToggleButton:SetBackdropBorderColor(unpack(UI.colors.border))
    pveToggleButton:SetPoint("TOPRIGHT", PVEFrame, "TOPRIGHT", -80, -5)
    pveToggleButton:SetFrameStrata("DIALOG")
    pveToggleButton:SetFrameLevel(PVEFrame:GetFrameLevel() + 10)

    pveToggleButton.text = pveToggleButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pveToggleButton.text:SetPoint("CENTER")
    pveToggleButton.text:SetText("메모장")
    pveToggleButton.text:SetTextColor(unpack(UI.colors.text))

    pveToggleButton:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.borderHover))
        self:SetBackdropColor(unpack(UI.colors.panelLight))
    end)

    pveToggleButton:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(UI.colors.border))
        self:SetBackdropColor(unpack(UI.colors.panel))
    end)

    pveToggleButton:SetScript("OnClick", function()
        Notepad:ToggleMainFrame()
    end)

    PVEFrame:HookScript("OnHide", function()
        if mainFrame and mainFrame:IsShown() then mainFrame:Hide() end
        if createFrame and createFrame:IsShown() then createFrame:Hide() end
        if detailFrame and detailFrame:IsShown() then detailFrame:Hide() end
    end)
end

local function UpdatePVEButton()
    if pveToggleButton then
        if Notepad.db.showPVEButton then
            pveToggleButton:Show()
        else
            pveToggleButton:Hide()
        end
    end
end

------------------------------------------------
-- [6] 삭제 확인 팝업
------------------------------------------------
StaticPopupDialogs["DDINGTOOLKIT_NOTEPAD_DELETE"] = {
    text = "정말로 '%s' 메모를 삭제하시겠습니까?",
    button1 = "예",
    button2 = "아니오",
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    OnAccept = function(self, idx)
        table.remove(Notepad.db.savedNotes, idx)
        if selectedMemoIndex == idx then
            selectedMemoIndex = nil
        end
        if detailFrame then
            detailFrame:Hide()
        end
        RefreshMemoList()
    end,
}

------------------------------------------------
-- [7] 모듈 인터페이스
------------------------------------------------
function Notepad:OnInitialize()
    self.db = ns.db.profile.Notepad
end

function Notepad:OnEnable()
    self.enabled = true

    -- 프레임 생성
    CreateMainFrame()
    CreateCreateFrame()
    CreateDetailFrame()

    -- PVEFrame 버튼 생성 (지연 로딩)
    C_Timer.After(2, CreatePVEToggleButton)
end

function Notepad:OnDisable()
    self.enabled = false
    if mainFrame then mainFrame:Hide() end
    if createFrame then createFrame:Hide() end
    if detailFrame then detailFrame:Hide() end
end

function Notepad:ToggleMainFrame()
    if not mainFrame then return end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
        RefreshMemoList()
    end
end

function Notepad:ShowMainFrame()
    if not mainFrame then return end
    mainFrame:Show()
    RefreshMemoList()
end

function Notepad:HideMainFrame()
    if mainFrame then mainFrame:Hide() end
    if createFrame then createFrame:Hide() end
    if detailFrame then detailFrame:Hide() end
end

function Notepad:UpdateSettings()
    UpdatePVEButton()
end

-- 모듈 등록
DDingToolKit:RegisterModule("Notepad", Notepad)

------------------------------------------------------
-- DDingUI_StyleLib :: DragSorter
-- 드래그로 순서 변경 (inspired by AbstractFramework)
-- 버프 트래커, 아이콘 그룹 등에서 사용
------------------------------------------------------
local MAJOR = "DDingUI-StyleLib-1.0"
local Lib = LibStub:GetLibrary(MAJOR)
if not Lib then return end

local CreateFrame = CreateFrame
local GetCursorPosition = GetCursorPosition

---------------------------------------------------------------------
-- DragSorter
---------------------------------------------------------------------
local DragSorter = {}
DragSorter.__index = DragSorter

--- 드래그 정렬 시스템 생성
--- @param config table
---   config.parent     Frame    컨테이너 프레임
---   config.items      table    정렬할 아이템 프레임 배열
---   config.direction  string   "VERTICAL"|"HORIZONTAL" (기본 "VERTICAL")
---   config.spacing    number   아이템 간격 (기본 2)
---   config.onReorder  function(newOrder) 순서 변경 콜백
---   config.dragHandle string|nil  "LEFT"|"RIGHT"|nil (nil이면 전체 영역이 핸들)
--- @return table sorter
function Lib.CreateDragSorter(config)
    assert(config.parent, "DragSorter: parent is required")
    assert(config.items, "DragSorter: items is required")
    assert(config.onReorder, "DragSorter: onReorder is required")

    local sorter = setmetatable({}, DragSorter)
    sorter.parent = config.parent
    sorter.items = config.items
    sorter.direction = config.direction or "VERTICAL"
    sorter.spacing = config.spacing or 2
    sorter.onReorder = config.onReorder
    sorter.enabled = true

    -- placeholder (드래그 중 삽입 위치 표시)
    sorter.placeholder = CreateFrame("Frame", nil, config.parent)
    sorter.placeholder:SetHeight(2)
    sorter.placeholder:Hide()
    local phTex = sorter.placeholder:CreateTexture(nil, "OVERLAY")
    phTex:SetAllPoints()
    phTex:SetColorTexture(Lib.GetColor("accent"))
    sorter.placeholder._tex = phTex

    -- 드래그할 아이템 복사본 (ghost)
    sorter.ghost = CreateFrame("Frame", nil, UIParent)
    sorter.ghost:SetFrameStrata("TOOLTIP")
    sorter.ghost:SetAlpha(0.7)
    sorter.ghost:Hide()

    -- 각 아이템에 드래그 등록
    sorter:_RegisterItems()

    return sorter
end

function DragSorter:SetEnabled(enabled)
    self.enabled = enabled
end

function DragSorter:SetItems(items)
    self.items = items
    self:_RegisterItems()
end

function DragSorter:_RegisterItems()
    for i, item in ipairs(self.items) do
        item._sortIndex = i
        item:EnableMouse(true)

        -- 기존 스크립트 보존
        if not item._slDragRegistered then
            item._slDragRegistered = true

            item:RegisterForDrag("LeftButton")
            item:SetScript("OnDragStart", function(self_item)
                if not self.enabled then return end
                self:_StartDrag(self_item)
            end)
            item:SetScript("OnDragStop", function(self_item)
                if not self.enabled then return end
                self:_StopDrag(self_item)
            end)
        end
    end
end

function DragSorter:_StartDrag(item)
    self.dragging = item
    self.dragStartIndex = item._sortIndex

    -- Ghost 설정
    self.ghost:SetSize(item:GetWidth(), item:GetHeight())
    self.ghost:ClearAllPoints()
    self.ghost:Show()

    -- 원본 투명하게
    item:SetAlpha(0.3)

    -- OnUpdate로 ghost 위치 추적 + 삽입 위치 계산
    self.parent:SetScript("OnUpdate", function()
        if not self.dragging then return end

        local x, y = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        self.ghost:ClearAllPoints()
        self.ghost:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)

        self:_UpdatePlaceholder(x / scale, y / scale)
    end)
end

function DragSorter:_StopDrag(item)
    if not self.dragging then return end

    local oldIndex = self.dragStartIndex
    local newIndex = self.dropIndex or oldIndex

    -- 정리
    self.dragging:SetAlpha(1)
    self.dragging = nil
    self.ghost:Hide()
    self.placeholder:Hide()
    self.parent:SetScript("OnUpdate", nil)

    -- 순서 변경 적용
    if oldIndex ~= newIndex then
        local moved = tremove(self.items, oldIndex)
        tinsert(self.items, newIndex, moved)

        -- 인덱스 재설정
        for i, it in ipairs(self.items) do
            it._sortIndex = i
        end

        -- 콜백
        local order = {}
        for i, it in ipairs(self.items) do
            order[i] = it._sortIndex
        end
        self.onReorder(self.items, oldIndex, newIndex)
    end
end

function DragSorter:_UpdatePlaceholder(cursorX, cursorY)
    local isVertical = (self.direction == "VERTICAL")
    local bestIndex = 1
    local bestDist = math.huge

    for i, item in ipairs(self.items) do
        if item ~= self.dragging then
            local cx, cy = item:GetCenter()
            local dist
            if isVertical then
                dist = math.abs(cursorY - cy)
            else
                dist = math.abs(cursorX - cx)
            end
            if dist < bestDist then
                bestDist = dist
                -- 위/왼쪽이면 이 아이템 앞에, 아래/오른쪽이면 뒤에
                if isVertical then
                    bestIndex = (cursorY > cy) and i or (i + 1)
                else
                    bestIndex = (cursorX < cx) and i or (i + 1)
                end
            end
        end
    end

    self.dropIndex = math.min(bestIndex, #self.items)

    -- placeholder 표시
    local refItem = self.items[math.min(self.dropIndex, #self.items)]
    if refItem and refItem ~= self.dragging then
        self.placeholder:ClearAllPoints()
        if isVertical then
            self.placeholder:SetPoint("BOTTOMLEFT", refItem, "TOPLEFT", 0, 1)
            self.placeholder:SetPoint("BOTTOMRIGHT", refItem, "TOPRIGHT", 0, 1)
            self.placeholder:SetHeight(2)
        else
            self.placeholder:SetPoint("TOPRIGHT", refItem, "TOPLEFT", -1, 0)
            self.placeholder:SetPoint("BOTTOMRIGHT", refItem, "BOTTOMLEFT", -1, 0)
            self.placeholder:SetWidth(2)
        end
        self.placeholder:Show()
    end
end

--- 레이아웃 재적용
function DragSorter:Relayout()
    local isVertical = (self.direction == "VERTICAL")
    for i, item in ipairs(self.items) do
        item:ClearAllPoints()
        if i == 1 then
            item:SetPoint("TOPLEFT", self.parent, "TOPLEFT", 0, 0)
            if isVertical then
                item:SetPoint("RIGHT", self.parent, "RIGHT", 0, 0)
            end
        else
            if isVertical then
                item:SetPoint("TOPLEFT", self.items[i - 1], "BOTTOMLEFT", 0, -self.spacing)
                item:SetPoint("RIGHT", self.parent, "RIGHT", 0, 0)
            else
                item:SetPoint("TOPLEFT", self.items[i - 1], "TOPRIGHT", self.spacing, 0)
            end
        end
    end
end

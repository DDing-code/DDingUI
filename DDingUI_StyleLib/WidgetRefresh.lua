------------------------------------------------------
-- DDingUI_StyleLib :: WidgetRefresh
-- In-place widget refresh system (EllesmereUI pattern)
-- Prevents flicker by updating values without destroying/recreating widgets
------------------------------------------------------
local MAJOR = "DDingUI-StyleLib-1.0"
local Lib = LibStub:GetLibrary(MAJOR)
if not Lib then return end

-- ============================================
-- WidgetRefresh Module
-- ============================================
local WR = {}
Lib.WidgetRefresh = WR

-- Per-panel refresh registries
-- key = panel identifier string, value = array of refresh functions
local _panelRegistries = {}

-- Global accent elements (for theme changes)
local _accentElements = {}

------------------------------------------------------
-- Widget Refresh Registration
------------------------------------------------------

--- Create a new refresh context for a panel.
--- @param panelId string  Unique identifier for the panel (e.g. "CDM_BuffTracker", "UF_Options")
--- @return table  context object with :Register() and :RefreshAll() methods
function WR.CreateContext(panelId)
    local ctx = {
        id = panelId,
        _refreshList = {},
        _scrollPositions = {},
    }

    --- Register a widget's refresh callback.
    --- The callback should update the widget's visual state without destroying it.
    --- @param fn function  refresh callback: fn() → updates widget in-place
    --- @param key string|nil  optional unique key for targeted refresh
    function ctx:Register(fn, key)
        local entry = { fn = fn, key = key }
        self._refreshList[#self._refreshList + 1] = entry
        if key then
            self._refreshList[key] = entry
        end
    end

    --- Refresh all registered widgets in this context.
    --- Preserves scroll positions automatically.
    function ctx:RefreshAll()
        for i, entry in ipairs(self._refreshList) do
            local ok, err = pcall(entry.fn)
            if not ok then
                -- Silent fail for individual widget errors
                -- print("|cffff4444[WR]|r Refresh error:", err)
            end
        end
    end

    --- Refresh a single widget by key.
    --- @param key string  the key used during registration
    function ctx:RefreshByKey(key)
        local entry = self._refreshList[key]
        if entry and entry.fn then
            pcall(entry.fn)
        end
    end

    --- Save scroll position for a scroll frame.
    --- @param scrollFrame Frame  the scroll frame to save
    --- @param id string  unique id for this scroll frame
    function ctx:SaveScroll(scrollFrame, id)
        if scrollFrame and scrollFrame.GetVerticalScroll then
            self._scrollPositions[id] = scrollFrame:GetVerticalScroll()
        end
    end

    --- Restore scroll position for a scroll frame.
    --- @param scrollFrame Frame  the scroll frame to restore
    --- @param id string  unique id for this scroll frame
    function ctx:RestoreScroll(scrollFrame, id)
        local pos = self._scrollPositions[id]
        if pos and scrollFrame and scrollFrame.SetVerticalScroll then
            C_Timer.After(0.01, function()
                scrollFrame:SetVerticalScroll(pos)
            end)
        end
    end

    --- Clear all registrations (when panel is destroyed)
    function ctx:Clear()
        wipe(self._refreshList)
        wipe(self._scrollPositions)
    end

    --- Get count of registered widgets
    function ctx:Count()
        return #self._refreshList
    end

    _panelRegistries[panelId] = ctx
    return ctx
end

--- Get an existing context by panel ID.
--- @param panelId string
--- @return table|nil  context or nil
function WR.GetContext(panelId)
    return _panelRegistries[panelId]
end

--- Destroy a context (when panel is permanently closed)
--- @param panelId string
function WR.DestroyContext(panelId)
    if _panelRegistries[panelId] then
        _panelRegistries[panelId]:Clear()
        _panelRegistries[panelId] = nil
    end
end

------------------------------------------------------
-- Accent Element Registry (for theme changes)
------------------------------------------------------

--- Register an element that should update when accent color changes.
--- @param elementType string  "solid" | "vertex" | "text" | "callback"
--- @param obj table|function  the texture/fontstring/callback
--- @param alpha number|nil  optional alpha override
function WR.RegAccent(elementType, obj, alpha)
    _accentElements[#_accentElements + 1] = {
        type = elementType,
        obj = obj,
        a = alpha,
    }
end

--- Update all registered accent elements with new accent color.
--- Called when theme/accent changes.
--- @param r number  red 0-1
--- @param g number  green 0-1
--- @param b number  blue 0-1
function WR.UpdateAccent(r, g, b)
    for _, entry in ipairs(_accentElements) do
        if entry.type == "solid" and entry.obj and entry.obj.SetColorTexture then
            entry.obj:SetColorTexture(r, g, b, entry.a or 1)
            -- Re-disable pixel snap after color change
            if entry.obj.SetSnapToPixelGrid then
                entry.obj:SetSnapToPixelGrid(false)
                entry.obj:SetTexelSnappingBias(0)
            end
        elseif entry.type == "vertex" and entry.obj and entry.obj.SetVertexColor then
            entry.obj:SetVertexColor(r, g, b, entry.a or 1)
        elseif entry.type == "text" and entry.obj and entry.obj.SetTextColor then
            entry.obj:SetTextColor(r, g, b, entry.a or 1)
        elseif entry.type == "callback" and type(entry.obj) == "function" then
            pcall(entry.obj, r, g, b)
        end
    end
end

--- Clear all accent registrations
function WR.ClearAccent()
    wipe(_accentElements)
end

------------------------------------------------------
-- SoftRefresh helper — update value without rebuild
------------------------------------------------------

--- Create a soft-refresh wrapper for a getter/setter pair.
--- Returns a function that, when called, updates the widget visual
--- to match the current db value.
--- @param widget table  the WoW frame/fontstring
--- @param widgetType string  "slider" | "toggle" | "dropdown" | "input" | "color"
--- @param getter function  fn() → current value
--- @param accent table  {r,g,b,a}  accent color for fills
--- @return function  refresh callback
function WR.MakeSoftRefresh(widget, widgetType, getter, accent)
    if widgetType == "slider" then
        return function()
            local v = getter()
            if widget._currentVal ~= v then
                widget._currentVal = v
                if widget.UpdateVisual then widget:UpdateVisual(v) end
                if widget._valueText then
                    widget._valueText:SetText(tostring(v))
                end
                -- Update fill color with current accent
                if widget._fill and accent then
                    widget._fill:SetColorTexture(accent[1], accent[2], accent[3], 0.75)
                end
            end
        end
    elseif widgetType == "toggle" then
        return function()
            local v = getter()
            if widget._isOn ~= v then
                widget._isOn = v
                if widget.UpdateVisual then widget:UpdateVisual(v) end
            end
        end
    elseif widgetType == "dropdown" then
        return function()
            local v = getter()
            if widget._selectedValue ~= v then
                widget._selectedValue = v
                if widget.UpdateLabel then widget:UpdateLabel(v) end
            end
        end
    elseif widgetType == "input" then
        return function()
            local v = getter()
            if widget:GetText() ~= tostring(v) then
                widget:SetText(tostring(v))
            end
        end
    elseif widgetType == "color" then
        return function()
            local r, g, b, a = getter()
            if widget._swatch then
                widget._swatch:SetColorTexture(r, g, b, a or 1)
            end
        end
    end
    return function() end  -- no-op fallback
end

local _, ns = ...
local Preview = {}
ns.Addon.GUI.DashboardPreview = Preview

local function Pack(...)
    return { n = select("#", ...), ... }
end

local function Secret(value)
    return issecretvalue and issecretvalue(value)
end

-- Read-only boundary: never inspect forbidden frames or calculate with secret returns.
local function Values(object, method, allowSecret, ...)
    if Secret(object) or object == nil then return nil end
    local args = Pack(...)
    local ok, values = pcall(function()
        if object.IsForbidden and object:IsForbidden() then return nil end
        local fn = object[method]
        if type(fn) ~= "function" then return nil end
        return Pack(fn(object, unpack(args, 1, args.n)))
    end)
    if not ok or not values then return nil end
    if not allowSecret then
        for index = 1, values.n do
            if Secret(values[index]) then return nil end
        end
    end
    return values
end

local function ReadMethod(object, method, arg)
    if object.IsForbidden and object:IsForbidden() then return nil end
    local fn = object[method]
    if type(fn) == "function" then
        if arg == nil then return fn(object) end
        return fn(object, arg)
    end
end

function Preview.Read(object, method, arg)
    if Secret(object) or object == nil then return nil end
    local ok, a, b, c, d, e, f, g, h = pcall(ReadMethod, object, method, arg)
    if ok and not (Secret(a) or Secret(b) or Secret(c) or Secret(d)
        or Secret(e) or Secret(f) or Secret(g) or Secret(h)) then
        return a, b, c, d, e, f, g, h
    end
end

local Read = Preview.Read

function Preview.Rect(object)
    local left, bottom, width, height = Read(object, "GetRect")
    if type(left) ~= "number" or type(bottom) ~= "number"
        or type(width) ~= "number" or type(height) ~= "number"
        or width <= 0 or height <= 0 then return nil end
    local scale = (Read(object, "GetEffectiveScale") or 1) / (Read(UIParent, "GetEffectiveScale") or 1)
    return { left = left * scale, bottom = bottom * scale, width = width * scale, height = height * scale }
end

-- Opt in only for AllowedWhenTainted display setters; never inspect their secret arguments.
local function Copy(source, target, getter, setter, allowSecret)
    local values = Values(source, getter, allowSecret)
    if values and values.n > 0 and (Secret(values[1]) or values[1] ~= nil) then
        return pcall(target[setter], target, unpack(values, 1, values.n))
    end
    return false
end

local function Acquire(host, kind, index)
    host._previewPool = host._previewPool or {}
    local pool = host._previewPool[kind]
    if not pool then pool = {}; host._previewPool[kind] = pool end
    if not pool[index] then
        local cell = CreateFrame((kind == "Cooldown" or kind == "StatusBar") and kind or "Frame", nil, host)
        cell:EnableMouse(false)
        if kind == "Texture" then
            cell.visual = cell:CreateTexture(nil, "ARTWORK")
        elseif kind == "FontString" then
            cell.visual = cell:CreateFontString(nil, "OVERLAY")
        end
        if cell.visual then cell.visual:SetAllPoints(cell) end
        pool[index] = cell
    end
    return pool[index]
end

function Preview.Clear(host)
    for _, pool in pairs(host._previewPool or {}) do
        for _, cell in ipairs(pool) do cell:Hide() end
    end
end

-- [REFACTOR] Apply a non-secret display property only when it differs from the target's current
-- value. Re-setting the same texture / fill style / layer makes WoW rebuild the region, which shows
-- as a flicker when it happens every copy.
local function Sync(source, target, getter, setter)
    local want = Values(source, getter)
    if not want or want.n == 0 or want[1] == nil then return false end
    local have = Values(target, getter)
    if have and have.n == want.n then
        local same = true
        for index = 1, want.n do
            if have[index] ~= want[index] then same = false; break end
        end
        if same then return true end
    end
    return pcall(target[setter], target, unpack(want, 1, want.n))
end

-- [REFACTOR] Anchor a copy region only when its placement really changes.
local function Place(region, relativeTo, x, y, width, height)
    if region._ddX == x and region._ddY == y and region._ddW == width and region._ddH == height
        and region._ddRel == relativeTo then
        return
    end
    region:ClearAllPoints()
    region:SetPoint("BOTTOMLEFT", relativeTo, "BOTTOMLEFT", x, y)
    region:SetSize(width, height)
    region._ddX, region._ddY, region._ddW, region._ddH, region._ddRel = x, y, width, height, relativeTo
end

function Preview.Paint(host, sources, bounds, scale, color)
    local used, seen = {}, {}
    host._liveBounds, host._liveScale = bounds, scale -- [REFACTOR] per-frame SyncLive geometry
    local partial, painted = false, 0
    local baseLevel = host:GetFrameLevel() + 1
    local rootLevel = sources[1] and Read(sources[1], "GetFrameLevel") or 0

    -- Fills one pooled cell from its source. Returns true when the cell should be shown.
    -- [REFACTOR] The cell is never hidden first and nothing is reset: a cell that was already
    -- showing keeps its texture until a property really differs (no blank / default frame).
    local function Fill(cell, source, kind, level, rect)
        Place(cell, host, (rect.left - bounds.left) * scale, (rect.bottom - bounds.bottom) * scale,
            rect.width * scale, rect.height * scale)
        local frameLevel = baseLevel + math.max(0, math.min(16, level - rootLevel))
        if cell:GetFrameLevel() ~= frameLevel then cell:SetFrameLevel(frameLevel) end
        -- [REFACTOR] remember the source so SyncLive can follow values every frame;
        -- textures on a StatusBar (e.g. the cast spark) move with the fill, so track their rect too.
        cell._liveSource = source
        cell._trackRect = kind == "Texture" and Read(Read(source, "GetParent"), "GetObjectType") == "StatusBar" or nil
        if not Copy(source, cell, "GetEffectiveAlpha", "SetAlpha", true)
            and not Copy(source, cell, "GetAlpha", "SetAlpha", true) then
            partial = true; return
        end
        local visual = cell.visual
        if kind == "Texture" then
            local texture, atlas = Read(source, "GetTexture"), Read(source, "GetAtlas")
            if atlas and atlas ~= "" then
                if visual._ddAtlas ~= atlas then
                    visual:SetAtlas(atlas)
                    visual._ddAtlas, visual._ddTexture = atlas, nil
                end
            elseif texture then
                if visual._ddTexture ~= texture then
                    visual:SetTexture(texture)
                    visual._ddTexture, visual._ddAtlas = texture, nil
                end
            else partial = true; return end
            -- Unlike IsDesaturated, the numeric getter permits forwarding protected CDM desaturation.
            if not Copy(source, visual, "GetTexCoord", "SetTexCoord", true)
                or not Copy(source, visual, "GetVertexColor", "SetVertexColor", true)
                or not Copy(source, visual, "GetDesaturation", "SetDesaturation", true) then
                partial = true; return
            end
            Sync(source, visual, "GetBlendMode", "SetBlendMode")
            Sync(source, visual, "GetDrawLayer", "SetDrawLayer")
            -- Masks are re-attached only when the set of mask textures changes.
            local masks = Read(source, "GetNumMaskTextures") or 0
            local found, keys = {}, {}
            for index = 1, masks do
                local maskSource = Read(source, "GetMaskTexture", index)
                local maskRect = Preview.Rect(maskSource)
                local maskTexture = Read(maskSource, "GetTexture")
                if maskRect and maskTexture then
                    found[#found + 1] = { source = maskSource, rect = maskRect, texture = maskTexture }
                    keys[#keys + 1] = tostring(maskTexture)
                else partial = true end
            end
            local maskKey = table.concat(keys, "|")
            cell.masks = cell.masks or {}
            if cell._ddMaskKey ~= maskKey then
                for _, mask in ipairs(cell.activeMasks or {}) do visual:RemoveMaskTexture(mask) end
                cell.activeMasks = {}
                for index, data in ipairs(found) do
                    local mask = cell.masks[index] or cell:CreateMaskTexture()
                    cell.masks[index] = mask
                    mask:SetTexture(data.texture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                    visual:AddMaskTexture(mask)
                    cell.activeMasks[index] = mask
                end
                cell._ddMaskKey = maskKey
            end
            for index, data in ipairs(found) do
                local mask = cell.masks[index]
                Place(mask, cell, (data.rect.left - rect.left) * scale, (data.rect.bottom - rect.bottom) * scale,
                    data.rect.width * scale, data.rect.height * scale)
                Copy(data.source, mask, "GetTexCoord", "SetTexCoord", true)
            end
        elseif kind == "StatusBar" then
            local fill = Read(source, "GetStatusBarTexture")
            local texture = Read(fill, "GetTexture")
            if not texture then partial = true; return end
            if cell._ddTexture ~= texture then
                cell:SetStatusBarTexture(texture)
                cell._ddTexture = texture
            end
            Sync(source, cell, "GetOrientation", "SetOrientation")
            Sync(source, cell, "GetReverseFill", "SetReverseFill")
            Sync(source, cell, "GetFillStyle", "SetFillStyle")
            Sync(source, cell, "GetRotatesTexture", "SetRotatesTexture")
            local sl = _G.DDingUI_StyleLib
            local okGradient, gradient = pcall(function() return source._ddingBarGradientActive end)
            gradient = okGradient and not Secret(gradient) and gradient == true
            -- only drop an old gradient when the source no longer uses one (no white/gradient toggling)
            if not gradient and cell._ddingBarGradientActive and sl and sl.ApplyBarColor then
                sl.ApplyBarColor(cell, { 1, 1, 1, 1 })
            end
            -- These native setters accept secret values. Never branch on or calculate them.
            local okState, copied = pcall(function()
                if source.IsForbidden and source:IsForbidden() then return false end
                cell:SetMinMaxValues(source:GetMinMaxValues())
                if source.GetInterpolatedValue then cell:SetValue(source:GetInterpolatedValue())
                else cell:SetValue(source:GetValue()) end
                if not gradient then cell:SetStatusBarColor(source:GetStatusBarColor()) end
                if source.GetStatusBarDesaturation and cell.SetStatusBarDesaturation then
                    cell:SetStatusBarDesaturation(source:GetStatusBarDesaturation())
                end
                return true
            end)
            if not okState or not copied then partial = true; return end
            if gradient then
                if not color or not sl or not sl.ApplyBarColor then partial = true; return end
                sl.ApplyBarColor(cell, color)
            end
        elseif kind == "FontString" then
            local font, size, flags = Read(source, "GetFont")
            local text = Read(source, "GetText")
            if text == "" then return end
            if not font or not size then partial = true; return end
            local fontScale = (Read(source, "GetEffectiveScale") or 1) / (Read(UIParent, "GetEffectiveScale") or 1)
            local fontSize = math.max(1, size * fontScale * scale)
            if visual._ddFont ~= font or visual._ddFontSize ~= fontSize or visual._ddFontFlags ~= flags then
                if not visual:SetFont(font, fontSize, flags) then partial = true; return end
                visual._ddFont, visual._ddFontSize, visual._ddFontFlags = font, fontSize, flags
            end
            if not Copy(source, visual, "GetText", "SetText", true)
                or not Copy(source, visual, "GetTextColor", "SetTextColor", true) then
                partial = true; return
            end
            Sync(source, visual, "GetJustifyH", "SetJustifyH")
            Sync(source, visual, "GetJustifyV", "SetJustifyV")
            Sync(source, visual, "GetDrawLayer", "SetDrawLayer")
            -- [REFACTOR] A text the game shows in full (IsTruncated false, e.g. a single-anchored
            -- cast name / time) must not get an ellipsis from scaled glyph widths in the copy:
            -- anchor it on its justified side without a width. Truncated or unknown texts keep the
            -- source box so the copy truncates like the game.
            local anchor = "FIT"
            if Read(source, "IsTruncated") == false then
                local justify = Read(source, "GetJustifyH")
                anchor = (justify == "LEFT" or justify == "RIGHT") and justify or "CENTER"
            end
            if visual._ddAnchor ~= anchor then
                visual:ClearAllPoints()
                if anchor == "FIT" then
                    visual:SetAllPoints(cell)
                else
                    visual:SetPoint(anchor, cell, anchor, 0, 0)
                    if visual.SetWordWrap then visual:SetWordWrap(false) end
                end
                visual._ddAnchor = anchor
            end
        elseif kind == "Cooldown" then
            local start, duration = Read(source, "GetCooldownTimes")
            if not start or not duration then partial = true; return end
            if duration <= 0 then return end
            -- No completion effects or duplicate countdown text in a sampled preview.
            cell:SetDrawBling(false)
            cell:SetHideCountdownNumbers(true)
            if not Copy(source, cell, "GetDrawSwipe", "SetDrawSwipe")
                or not Copy(source, cell, "GetDrawEdge", "SetDrawEdge")
                or not Copy(source, cell, "GetReverse", "SetReverse") then
                partial = true; return
            end
            Copy(source, cell, "GetRotation", "SetRotation")
            local ok, ringTexture = pcall(function() return source._ddingRingSwipeTexture end)
            local engine = ns.Addon.TrackedAuraContainer
            local viewers = ns.Addon.IconViewers
            local data = viewers and viewers._cdData and viewers._cdData[source]
            local swipeColor = data and data.previewSwipeColor
            if ok and not Secret(ringTexture) and engine then
                if type(ringTexture) == "string" and engine.ConfigureRingCooldown then
                    engine:ConfigureRingCooldown(cell, host, ringTexture)
                    swipeColor = color
                elseif engine.ClearRingCooldownMask then
                    engine:ClearRingCooldownMask(cell)
                end
            end
            if not swipeColor then partial = true; return end
            cell:SetSwipeColor(swipeColor[1], swipeColor[2], swipeColor[3], swipeColor[4] or 1)
            if cell._start ~= start or cell._duration ~= duration then
                cell:SetCooldown(start / 1000, duration / 1000)
                cell._start, cell._duration = start, duration
            end
        end
        return true
    end

    local function Draw(source, kind, level)
        local rect = Preview.Rect(source)
        if not rect then
            if Read(source, "GetWidth") ~= 0 and Read(source, "GetHeight") ~= 0 then partial = true end
            return
        end
        used[kind] = (used[kind] or 0) + 1
        local cell = Acquire(host, kind, used[kind])
        if Fill(cell, source, kind, level, rect) then
            if not cell:IsShown() then cell:Show() end
            painted = painted + 1
        elseif cell:IsShown() then
            cell:Hide()
        end
    end

    local function Visit(frame, depth)
        if seen[frame] then return end
        seen[frame] = true
        local visible = Read(frame, "IsVisible")
        if visible ~= true then partial = partial or visible == nil; return end
        -- ponytail: bounded visual traversal; add a dedicated adapter for deeper custom renderers.
        if depth > 6 then partial = true; return end
        local level = Read(frame, "GetFrameLevel") or rootLevel
        local kind = Read(frame, "GetObjectType")
        local fill
        if kind == "Cooldown" then Draw(frame, kind, level)
        elseif kind == "StatusBar" then
            -- The engine-owned fill is not guaranteed to occur in GetRegions().
            fill = Read(frame, "GetStatusBarTexture")
            Draw(frame, kind, level)
        end
        local regions = Values(frame, "GetRegions")
        if not regions then partial = true end
        for index = 1, regions and regions.n or 0 do
            local region = regions[index]
            local kind = Read(region, "GetObjectType")
            if region ~= fill and (kind == "Texture" or kind == "FontString") then
                local shown = Read(region, "IsVisible")
                if shown == true then Draw(region, kind, level)
                elseif shown == nil then partial = true end
            end
        end
        local children = Values(frame, "GetChildren")
        if not children then partial = true end
        for index = 1, children and children.n or 0 do Visit(children[index], depth + 1) end
    end

    for _, source in ipairs(sources) do Visit(source, 0) end
    for kind, pool in pairs(host._previewPool or {}) do
        for index = (used[kind] or 0) + 1, #pool do pool[index]:Hide() end
    end
    return painted, partial
end

-- [REFACTOR] Union rectangle (UIParent units) of the readable frames, or nil.
function Preview.UnionRect(frames)
    local left, right, bottom, top
    for _, frame in ipairs(frames or {}) do
        local rect = Preview.Rect(frame)
        if rect then
            left = left and math.min(left, rect.left) or rect.left
            right = right and math.max(right, rect.left + rect.width) or rect.left + rect.width
            bottom = bottom and math.min(bottom, rect.bottom) or rect.bottom
            top = top and math.max(top, rect.bottom + rect.height) or rect.bottom + rect.height
        end
    end
    if left then return { left = left, bottom = bottom, width = right - left, height = top - bottom } end
end

--- [REFACTOR] Copy runtime frames into host at their real on-screen size, centred, and shrink
-- only when they do not fit. Returns painted, partial, sizeRatio (1 = actual size) or nil ratio
-- when nothing readable was found.
function Preview.PaintFit(host, sources, color, padding)
    local bounds = Preview.UnionRect(sources)
    local hostW, hostH = Read(host, "GetWidth") or 0, Read(host, "GetHeight") or 0
    if not bounds or hostW <= 1 or hostH <= 1 then
        Preview.Clear(host)
        return 0, bounds == nil and #(sources or {}) > 0, nil
    end
    padding = padding or 8
    local uiScale = Read(UIParent, "GetEffectiveScale") or 1
    local hostScale = Read(host, "GetEffectiveScale") or 1
    local trueScale = hostScale > 0 and uiScale / hostScale or 1
    local fit = math.min(1,
        math.max(1, hostW - padding * 2) / math.max(1, bounds.width * trueScale),
        math.max(1, hostH - padding * 2) / math.max(1, bounds.height * trueScale))
    local scale = trueScale * math.max(0.05, fit)
    local view = {
        left = bounds.left - (hostW / scale - bounds.width) / 2,
        bottom = bounds.bottom - (hostH / scale - bounds.height) / 2,
    }
    local painted, partial = Preview.Paint(host, sources, view, scale, color)
    return painted, partial, fit
end

-- ============================================================
-- [REFACTOR] Live layout session.
-- While a dashboard or section preview is open (out of combat), every CDM element is really put on
-- screen through the runtime's own preview paths, so the previews only ever copy real frames:
--   * custom aura trackers: runtime preview mode (ResourceBars:EnablePreviewMode)
--   * cast bar: runtime test cast looping in place (CastBars:ShowTestCastBar(true))
--   * inactive buffs / custom icons: DDingUI:SetLayoutPreviewForced (same path as edit mode)
-- Modes that were already on are left untouched on exit. Entering combat ends the session at once
-- (and shows "display limited"); it comes back after combat if a preview is still open.
-- Nothing is written to SavedVariables.
-- ============================================================
local Session = { owners = {}, active = false }
local TEST_CAST_TICK = 0.2
Preview.LiveSession = Session

local function Addon() return ns.Addon end

function Session:IsActive()
    return self.active
end

function Session:KeepTestCast()
    if not self.active or InCombatLockdown() then return end
    local addon = Addon()
    local cfg = addon.db and addon.db.profile and addon.db.profile.castBar
    if not cfg or cfg.enabled == false or not addon.ShowTestCastBar then return end
    local bar = addon.castBar
    local testing = addon.IsTestCastActive and addon:IsTestCastActive()
    -- a real cast in progress wins; the preview then copies it
    if bar and not testing and Read(bar, "IsShown") == true then return end
    -- [REFACTOR] the runtime loops its own test cast in place (ShowTestCastBar(true)): no hide,
    -- no relayout and no texture re-apply at the 15 s mark. This only (re)starts it when none runs,
    -- e.g. after a real cast ended.
    if not testing then
        addon:ShowTestCastBar(true)
        self.testCastOwned = true
    end
end

local function StartSession(self)
    if self.active or InCombatLockdown() then return self.active end
    local addon = Addon()
    self.active = true
    self.combatBlocked = nil
    if addon.IsBuffTrackerPreviewEnabled and not addon:IsBuffTrackerPreviewEnabled() and addon.EnableBuffTrackerPreview then
        addon:EnableBuffTrackerPreview()
        self.trackerPreviewOwned = true
    end
    if addon.SetLayoutPreviewForced and not addon._layoutPreviewForced then
        addon:SetLayoutPreviewForced(true)
        self.forcedOwned = true
    end
    self:KeepTestCast()
    self.ticker = C_Timer.NewTicker(TEST_CAST_TICK, function() Session:KeepTestCast() end)
    return true
end

local function StopSession(self)
    if not self.active then return end
    self.active = false
    if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    local addon = Addon()
    if self.testCastOwned and addon.StopTestCastBar then addon:StopTestCastBar() end
    if self.trackerPreviewOwned and addon.DisableBuffTrackerPreview then addon:DisableBuffTrackerPreview() end
    if self.forcedOwned and addon.SetLayoutPreviewForced then addon:SetLayoutPreviewForced(false) end
    self.testCastOwned, self.trackerPreviewOwned, self.forcedOwned = nil, nil, nil
end

--- A preview surface opens: turn the live layout on (no-op in combat; it starts after combat).
function Session:Begin(owner)
    if owner then self.owners[owner] = true end
    if InCombatLockdown() then
        self.combatBlocked = true
        return false
    end
    return StartSession(self)
end

--- A preview surface closes: restore once the last one is gone.
function Session:End(owner)
    if owner then self.owners[owner] = nil else wipe(self.owners) end
    if next(self.owners) then return end
    self.combatBlocked = nil
    StopSession(self)
end

local sessionEvents = CreateFrame("Frame")
sessionEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
sessionEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
sessionEvents:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if Session.active or next(Session.owners) then
            StopSession(Session)
            Session.combatBlocked = true
        end
    elseif next(Session.owners) then
        StartSession(Session)
    else
        Session.combatBlocked = nil
    end
end)

--- [REFACTOR] Light per-frame follow of an already painted copy: StatusBar min/max/value, texts
-- and the rect of StatusBar-attached textures (spark). No traversal, no new cells; call it from an
-- OnUpdate that only runs while the preview is shown. Secret values go straight to the setters.
-- Static helpers (no per-frame closures or tables). Secret values are only forwarded.
local function SyncBar(cell, source)
    if source.IsForbidden and source:IsForbidden() then return false end
    cell:SetMinMaxValues(source:GetMinMaxValues())
    if source.GetInterpolatedValue then cell:SetValue(source:GetInterpolatedValue())
    else cell:SetValue(source:GetValue()) end
    return true
end

local function SyncText(visual, source)
    if source.IsForbidden and source:IsForbidden() then return false end
    visual:SetText(source:GetText())
    return true
end

function Preview.SyncLive(host)
    local pool = host and host._previewPool
    if not pool then return 0 end
    local synced = 0
    for _, cell in ipairs(pool.StatusBar or {}) do
        local source = cell._liveSource
        if source and cell:IsShown() then
            local ok, done = pcall(SyncBar, cell, source)
            if ok and done then synced = synced + 1 end
        end
    end
    for _, cell in ipairs(pool.FontString or {}) do
        local source = cell._liveSource
        if source and cell:IsShown() then
            local ok, done = pcall(SyncText, cell.visual, source)
            if ok and done then synced = synced + 1 end
        end
    end
    local bounds, scale = host._liveBounds, host._liveScale
    if bounds and scale then
        for _, cell in ipairs(pool.Texture or {}) do
            local source = cell._liveSource
            if source and cell._trackRect and cell:IsShown() then
                local rect = Preview.Rect(source)
                if rect then
                    Place(cell, host, (rect.left - bounds.left) * scale, (rect.bottom - bounds.bottom) * scale,
                        rect.width * scale, rect.height * scale)
                    synced = synced + 1
                end
            end
        end
    end
    return synced
end

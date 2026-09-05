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
local function Values(object, method, ...)
    if Secret(object) or object == nil then return nil end
    local args = Pack(...)
    local ok, values = pcall(function()
        if object.IsForbidden and object:IsForbidden() then return nil end
        local fn = object[method]
        if type(fn) ~= "function" then return nil end
        return Pack(fn(object, unpack(args, 1, args.n)))
    end)
    if not ok or not values then return nil end
    for index = 1, values.n do
        if Secret(values[index]) then return nil end
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

local function Copy(source, target, getter, setter)
    local values = Values(source, getter)
    if values and values.n > 0 and values[1] ~= nil then
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

function Preview.Paint(host, sources, bounds, scale, color)
    local used, seen = {}, {}
    local partial, painted = false, 0
    local baseLevel = host:GetFrameLevel() + 1
    local rootLevel = sources[1] and Read(sources[1], "GetFrameLevel") or 0

    local function Draw(source, kind, level)
        local rect = Preview.Rect(source)
        if not rect then
            if Read(source, "GetWidth") ~= 0 and Read(source, "GetHeight") ~= 0 then partial = true end
            return
        end
        used[kind] = (used[kind] or 0) + 1
        local cell = Acquire(host, kind, used[kind])
        cell:Hide()
        cell:ClearAllPoints()
        cell:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT",
            (rect.left - bounds.left) * scale, (rect.bottom - bounds.bottom) * scale)
        cell:SetSize(rect.width * scale, rect.height * scale)
        cell:SetFrameLevel(baseLevel + math.max(0, math.min(16, level - rootLevel)))
        local alpha = Read(source, "GetEffectiveAlpha") or Read(source, "GetAlpha")
        if alpha == nil then partial = true; return end
        cell:SetAlpha(alpha)
        local visual = cell.visual
        if kind == "Texture" then
            local texture, atlas = Read(source, "GetTexture"), Read(source, "GetAtlas")
            if atlas and atlas ~= "" then visual:SetAtlas(atlas)
            elseif texture then visual:SetTexture(texture)
            else partial = true; return end
            if not Copy(source, visual, "GetTexCoord", "SetTexCoord")
                or not Copy(source, visual, "GetVertexColor", "SetVertexColor")
                or not Copy(source, visual, "IsDesaturated", "SetDesaturated") then
                partial = true; return
            end
            Copy(source, visual, "GetBlendMode", "SetBlendMode")
            Copy(source, visual, "GetDrawLayer", "SetDrawLayer")
            local masks = Read(source, "GetNumMaskTextures") or 0
            cell.masks = cell.masks or {}
            for _, mask in ipairs(cell.activeMasks or {}) do visual:RemoveMaskTexture(mask) end
            cell.activeMasks = {}
            for index = 1, masks do
                local maskSource = Read(source, "GetMaskTexture", index)
                local maskRect = Preview.Rect(maskSource)
                local maskTexture = Read(maskSource, "GetTexture")
                if maskRect and maskTexture then
                    local mask = cell.masks[index] or cell:CreateMaskTexture()
                    cell.masks[index] = mask
                    mask:SetTexture(maskTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
                    mask:ClearAllPoints()
                    mask:SetPoint("BOTTOMLEFT", cell, "BOTTOMLEFT",
                        (maskRect.left - rect.left) * scale, (maskRect.bottom - rect.bottom) * scale)
                    mask:SetSize(maskRect.width * scale, maskRect.height * scale)
                    Copy(maskSource, mask, "GetTexCoord", "SetTexCoord")
                    visual:AddMaskTexture(mask)
                    cell.activeMasks[#cell.activeMasks + 1] = mask
                else partial = true end
            end
        elseif kind == "StatusBar" then
            local fill = Read(source, "GetStatusBarTexture")
            local texture = Read(fill, "GetTexture")
            if not texture then partial = true; return end
            cell:SetStatusBarTexture(texture)
            Copy(source, cell, "GetOrientation", "SetOrientation")
            Copy(source, cell, "GetReverseFill", "SetReverseFill")
            Copy(source, cell, "GetFillStyle", "SetFillStyle")
            Copy(source, cell, "GetRotatesTexture", "SetRotatesTexture")
            local sl = _G.DDingUI_StyleLib
            if cell._ddingBarGradientActive and sl and sl.ApplyBarColor then
                sl.ApplyBarColor(cell, { 1, 1, 1, 1 })
            end
            -- These native setters accept secret values. Never branch on or calculate them.
            local okState, copied = pcall(function()
                if source.IsForbidden and source:IsForbidden() then return false end
                cell:SetMinMaxValues(source:GetMinMaxValues())
                if source.GetInterpolatedValue then cell:SetValue(source:GetInterpolatedValue())
                else cell:SetValue(source:GetValue()) end
                cell:SetStatusBarColor(source:GetStatusBarColor())
                if source.GetStatusBarDesaturation and cell.SetStatusBarDesaturation then
                    cell:SetStatusBarDesaturation(source:GetStatusBarDesaturation())
                end
                return true
            end)
            if not okState or not copied then partial = true; return end
            local ok, gradient = pcall(function() return source._ddingBarGradientActive end)
            if ok and not Secret(gradient) and gradient == true then
                if not color or not sl or not sl.ApplyBarColor then partial = true; return end
                sl.ApplyBarColor(cell, color)
            end
        elseif kind == "FontString" then
            local font, size, flags = Read(source, "GetFont")
            local text = Read(source, "GetText")
            if text == "" then return end
            if not font or not size or text == nil then partial = true; return end
            local fontScale = (Read(source, "GetEffectiveScale") or 1) / (Read(UIParent, "GetEffectiveScale") or 1)
            if not visual:SetFont(font, math.max(1, size * fontScale * scale), flags) then
                partial = true; return
            end
            visual:SetText(text)
            if not Copy(source, visual, "GetTextColor", "SetTextColor") then partial = true; return end
            Copy(source, visual, "GetJustifyH", "SetJustifyH")
            Copy(source, visual, "GetJustifyV", "SetJustifyV")
            Copy(source, visual, "GetDrawLayer", "SetDrawLayer")
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
        cell:Show()
        painted = painted + 1
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

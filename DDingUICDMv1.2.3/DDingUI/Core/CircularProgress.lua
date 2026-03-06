-- ============================================================
-- DDingUI Circular Progress Texture
-- Based on WeakAuras CircularProgressTexture implementation
-- Credit: WeakAuras team, CommanderSirow, Semlar
-- ============================================================

local ADDON_NAME, ns = ...
local DDingUI = ns.Addon
DDingUI.CircularProgress = DDingUI.CircularProgress or {}

local CircularProgress = DDingUI.CircularProgress

-- ============================================================
-- TEXTURE COORDS - Handles geometry calculations for circular progress
-- ============================================================

local floor = math.floor
local cos = math.cos
local sin = math.sin
local tan = math.tan
local rad = math.rad

-- WoW vertex constants
local UPPER_LEFT_VERTEX = 1
local LOWER_LEFT_VERTEX = 2
local UPPER_RIGHT_VERTEX = 3
local LOWER_RIGHT_VERTEX = 4

local defaultTexCoord = {
    ULx = 0, ULy = 0,
    LLx = 0, LLy = 1,
    URx = 1, URy = 0,
    LRx = 1, LRy = 1,
}

-- Exact angles for 45-degree increments (optimization)
local exactAngles = {
    {0.5, 0},  -- 0°
    {1, 0},    -- 45°
    {1, 0.5},  -- 90°
    {1, 1},    -- 135°
    {0.5, 1},  -- 180°
    {0, 1},    -- 225°
    {0, 0.5},  -- 270°
    {0, 0}     -- 315°
}

-- Convert angle (degrees) to texture coordinates
local function angleToCoord(angle)
    angle = angle % 360

    if (angle % 45 == 0) then
        local index = floor(angle / 45) + 1
        return exactAngles[index][1], exactAngles[index][2]
    end

    -- Convert to radians for tan calculation
    local angleRad = rad(angle)

    if (angle < 45) then
        return 0.5 + tan(angleRad) / 2, 0
    elseif (angle < 135) then
        return 1, 0.5 + tan(rad(angle - 90)) / 2
    elseif (angle < 225) then
        return 0.5 - tan(angleRad) / 2, 1
    elseif (angle < 315) then
        return 0, 0.5 - tan(rad(angle - 90)) / 2
    elseif (angle < 360) then
        return 0.5 + tan(angleRad) / 2, 0
    end
end

-- Corner order for angle calculations
local pointOrder = { "LL", "UL", "UR", "LR", "LL", "UL", "UR", "LR", "LL", "UL", "UR", "LR" }

-- Transform point with rotation, mirroring, and scaling
local function TransformPoint(x, y, scalex, scaley, texRotation, mirror_h, mirror_v)
    -- Translate to center
    x = x - 0.5
    y = y - 0.5

    -- Shrink by 1/sqrt(2) to fit rotated texture
    x = x * 1.4142
    y = y * 1.4142

    -- Scale
    x = x / scalex
    y = y / scaley

    -- Mirror
    if mirror_h then x = -x end
    if mirror_v then y = -y end

    -- Rotate
    local cos_rotation = cos(texRotation)
    local sin_rotation = sin(texRotation)
    x, y = cos_rotation * x - sin_rotation * y, sin_rotation * x + cos_rotation * y

    -- Translate back
    x = x + 0.5
    y = y + 0.5

    return x, y
end

-- ============================================================
-- TEXTURE COORDS CLASS
-- ============================================================

local TextureCoordsFuncs = {
    MoveCorner = function(self, width, height, corner, x, y)
        local rx = defaultTexCoord[corner .. "x"] - x
        local ry = defaultTexCoord[corner .. "y"] - y
        self[corner .. "vx"] = -rx * width
        self[corner .. "vy"] = ry * height
        self[corner .. "x"] = x
        self[corner .. "y"] = y
    end,

    Hide = function(self)
        self.texture:Hide()
    end,

    Show = function(self)
        self:Apply()
        self.texture:Show()
    end,

    SetFull = function(self)
        self.ULx, self.ULy = 0, 0
        self.LLx, self.LLy = 0, 1
        self.URx, self.URy = 1, 0
        self.LRx, self.LRy = 1, 1
        self.ULvx, self.ULvy = 0, 0
        self.LLvx, self.LLvy = 0, 0
        self.URvx, self.URvy = 0, 0
        self.LRvx, self.LRvy = 0, 0
    end,

    Apply = function(self)
        self.texture:SetVertexOffset(UPPER_RIGHT_VERTEX, self.URvx, self.URvy)
        self.texture:SetVertexOffset(UPPER_LEFT_VERTEX, self.ULvx, self.ULvy)
        self.texture:SetVertexOffset(LOWER_RIGHT_VERTEX, self.LRvx, self.LRvy)
        self.texture:SetVertexOffset(LOWER_LEFT_VERTEX, self.LLvx, self.LLvy)
        self.texture:SetTexCoord(self.ULx, self.ULy, self.LLx, self.LLy, self.URx, self.URy, self.LRx, self.LRy)
    end,

    SetAngle = function(self, width, height, angle1, angle2)
        local index = floor((angle1 + 45) / 90)

        local middleCorner = pointOrder[index + 1]
        local startCorner = pointOrder[index + 2]
        local endCorner1 = pointOrder[index + 3]
        local endCorner2 = pointOrder[index + 4]

        self:MoveCorner(width, height, middleCorner, 0.5, 0.5)
        self:MoveCorner(width, height, startCorner, angleToCoord(angle1))

        local edge1 = floor((angle1 - 45) / 90)
        local edge2 = floor((angle2 - 45) / 90)

        if (edge1 == edge2) then
            self:MoveCorner(width, height, endCorner1, angleToCoord(angle2))
        else
            self:MoveCorner(width, height, endCorner1, defaultTexCoord[endCorner1 .. "x"], defaultTexCoord[endCorner1 .. "y"])
        end

        self:MoveCorner(width, height, endCorner2, angleToCoord(angle2))
    end,

    Transform = function(self, scalex, scaley, texRotation, mirror_h, mirror_v)
        self.ULx, self.ULy = TransformPoint(self.ULx, self.ULy, scalex, scaley, texRotation, mirror_h, mirror_v)
        self.LLx, self.LLy = TransformPoint(self.LLx, self.LLy, scalex, scaley, texRotation, mirror_h, mirror_v)
        self.URx, self.URy = TransformPoint(self.URx, self.URy, scalex, scaley, texRotation, mirror_h, mirror_v)
        self.LRx, self.LRy = TransformPoint(self.LRx, self.LRy, scalex, scaley, texRotation, mirror_h, mirror_v)
    end
}

local function CreateTextureCoords(texture)
    local coord = {
        ULx = 0, ULy = 0,
        LLx = 0, LLy = 1,
        URx = 1, URy = 0,
        LRx = 1, LRy = 1,
        ULvx = 0, ULvy = 0,
        LLvx = 0, LLvy = 0,
        URvx = 0, URvy = 0,
        LRvx = 0, LRvy = 0,
        texture = texture
    }

    for k, f in pairs(TextureCoordsFuncs) do
        coord[k] = f
    end

    return coord
end

-- ============================================================
-- CIRCULAR PROGRESS TEXTURE CLASS
-- ============================================================

local CircularTextureFuncs = {
    SetTextureOrAtlas = function(self, texture)
        for i = 1, 3 do
            if type(texture) == "string" and not texture:find("\\") and not texture:find("/") then
                -- Atlas
                self.textures[i]:SetAtlas(texture)
            else
                -- File path or texture ID
                self.textures[i]:SetTexture(texture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            end
        end
    end,

    SetDesaturated = function(self, desaturate)
        for i = 1, 3 do
            self.textures[i]:SetDesaturated(desaturate)
        end
    end,

    SetBlendMode = function(self, blendMode)
        for i = 1, 3 do
            self.textures[i]:SetBlendMode(blendMode)
        end
    end,

    SetAuraRotation = function(self, radians)
        for i = 1, 3 do
            self.textures[i]:SetRotation(radians)
        end
    end,

    Show = function(self)
        self.visible = true
        for i = 1, 3 do
            self.textures[i]:Show()
        end
    end,

    Hide = function(self)
        self.visible = false
        for i = 1, 3 do
            self.textures[i]:Hide()
        end
    end,

    SetColor = function(self, r, g, b, a)
        for i = 1, 3 do
            self.textures[i]:SetVertexColor(r, g, b, a)
        end
    end,

    SetCropX = function(self, crop_x)
        self.crop_x = crop_x
        self:UpdateTextures()
    end,

    SetCropY = function(self, crop_y)
        self.crop_y = crop_y
        self:UpdateTextures()
    end,

    SetTexRotation = function(self, texRotation)
        self.texRotation = texRotation
        self:UpdateTextures()
    end,

    SetMirror = function(self, mirror)
        self.mirror = mirror
        self:UpdateTextures()
    end,

    SetWidth = function(self, width)
        self.width = width
    end,

    SetHeight = function(self, height)
        self.height = height
    end,

    SetScale = function(self, scalex, scaley)
        self.scalex, self.scaley = scalex, scaley
    end,

    UpdateTextures = function(self)
        if not self.visible then return end

        local crop_x = self.crop_x or 1
        local crop_y = self.crop_y or 1
        local texRotation = self.texRotation or 0
        local mirror_h = self.mirror or false
        local mirror_v = false

        local width = self.width * (self.scalex or 1) + 2 * self.offset
        local height = self.height * (self.scaley or 1) + 2 * self.offset

        if width == 0 or height == 0 then return end

        local angle1 = self.angle1
        local angle2 = self.angle2

        if angle1 == nil or angle2 == nil then return end

        -- Full circle case
        if (angle2 - angle1 >= 360) then
            self.coords[1]:SetFull()
            self.coords[1]:Transform(crop_x, crop_y, texRotation, mirror_h, mirror_v)
            self.coords[1]:Show()
            self.coords[2]:Hide()
            self.coords[3]:Hide()
            return
        end

        -- Empty case
        if (angle1 == angle2) then
            self.coords[1]:Hide()
            self.coords[2]:Hide()
            self.coords[3]:Hide()
            return
        end

        local index1 = floor((angle1 + 45) / 90)
        local index2 = floor((angle2 + 45) / 90)

        if (index1 + 1 >= index2) then
            -- Single segment
            self.coords[1]:SetAngle(width, height, angle1, angle2)
            self.coords[1]:Transform(crop_x, crop_y, texRotation, mirror_h, mirror_v)
            self.coords[1]:Show()
            self.coords[2]:Hide()
            self.coords[3]:Hide()
        elseif (index1 + 3 >= index2) then
            -- Two segments
            local firstEndAngle = (index1 + 1) * 90 + 45
            self.coords[1]:SetAngle(width, height, angle1, firstEndAngle)
            self.coords[1]:Transform(crop_x, crop_y, texRotation, mirror_h, mirror_v)
            self.coords[1]:Show()

            self.coords[2]:SetAngle(width, height, firstEndAngle, angle2)
            self.coords[2]:Transform(crop_x, crop_y, texRotation, mirror_h, mirror_v)
            self.coords[2]:Show()

            self.coords[3]:Hide()
        else
            -- Three segments
            local firstEndAngle = (index1 + 1) * 90 + 45
            local secondEndAngle = firstEndAngle + 180

            self.coords[1]:SetAngle(width, height, angle1, firstEndAngle)
            self.coords[1]:Transform(crop_x, crop_y, texRotation, mirror_h, mirror_v)
            self.coords[1]:Show()

            self.coords[2]:SetAngle(width, height, firstEndAngle, secondEndAngle)
            self.coords[2]:Transform(crop_x, crop_y, texRotation, mirror_h, mirror_v)
            self.coords[2]:Show()

            self.coords[3]:SetAngle(width, height, secondEndAngle, angle2)
            self.coords[3]:Transform(crop_x, crop_y, texRotation, mirror_h, mirror_v)
            self.coords[3]:Show()
        end
    end,

    -- Main progress setter: startAngle and endAngle in degrees
    SetProgress = function(self, angle1, angle2)
        self.angle1 = angle1
        self.angle2 = angle2
        self:UpdateTextures()
    end,

    -- Convenience: Set progress as 0-1 value (clockwise from top)
    SetValue = function(self, progress, startAngle, endAngle)
        startAngle = startAngle or 0
        endAngle = endAngle or 360
        progress = math.max(0, math.min(1, progress or 0))

        local pAngle = (endAngle - startAngle) * progress + startAngle
        self:SetProgress(startAngle, pAngle)
    end,

    -- Convenience: Set progress as 0-1 value (counter-clockwise)
    SetValueReverse = function(self, progress, startAngle, endAngle)
        startAngle = startAngle or 0
        endAngle = endAngle or 360
        progress = math.max(0, math.min(1, progress or 0))
        progress = 1 - progress

        local pAngle = (endAngle - startAngle) * progress + startAngle
        self:SetProgress(pAngle, endAngle)
    end,
}

-- ============================================================
-- PUBLIC API
-- ============================================================

-- Create a circular progress texture on a parent frame
function CircularProgress:Create(parent, layer, drawLayer)
    layer = layer or "ARTWORK"
    drawLayer = drawLayer or 1

    local circularTexture = {
        textures = {},
        coords = {},
        offset = 0,
        visible = true,
        width = 32,
        height = 32,
        scalex = 1,
        scaley = 1,
        crop_x = 1.41,  -- Default for ring (sqrt(2))
        crop_y = 1.41,
        texRotation = 0,
        mirror = false,
        angle1 = 0,
        angle2 = 360,
    }

    -- Create 3 textures for the circular progress
    for i = 1, 3 do
        local texture = parent:CreateTexture(nil, layer)
        texture:SetSnapToPixelGrid(false)
        texture:SetTexelSnappingBias(0)
        texture:SetDrawLayer(layer, drawLayer)
        texture:SetAllPoints(parent)
        circularTexture.textures[i] = texture
        circularTexture.coords[i] = CreateTextureCoords(texture)
    end

    -- Add methods
    for funcName, func in pairs(CircularTextureFuncs) do
        circularTexture[funcName] = func
    end

    circularTexture.parentFrame = parent

    return circularTexture
end

-- Modify an existing circular progress texture
function CircularProgress:Modify(circularTexture, options)
    options = options or {}

    if options.texture then
        circularTexture:SetTextureOrAtlas(options.texture)
    end
    if options.desaturated ~= nil then
        circularTexture:SetDesaturated(options.desaturated)
    end
    if options.blendMode then
        circularTexture:SetBlendMode(options.blendMode)
    end
    if options.auraRotation then
        circularTexture:SetAuraRotation(options.auraRotation)
    end

    circularTexture.crop_x = options.crop_x or circularTexture.crop_x
    circularTexture.crop_y = options.crop_y or circularTexture.crop_y
    circularTexture.mirror = options.mirror or circularTexture.mirror
    circularTexture.texRotation = options.texRotation or circularTexture.texRotation
    circularTexture.width = options.width or circularTexture.width
    circularTexture.height = options.height or circularTexture.height
    circularTexture.offset = options.offset or circularTexture.offset

    local offset = circularTexture.offset
    local frame = circularTexture.parentFrame

    if offset > 0 then
        for i = 1, 3 do
            circularTexture.textures[i]:ClearAllPoints()
            circularTexture.textures[i]:SetPoint("TOPRIGHT", frame, offset, offset)
            circularTexture.textures[i]:SetPoint("BOTTOMRIGHT", frame, offset, -offset)
            circularTexture.textures[i]:SetPoint("BOTTOMLEFT", frame, -offset, -offset)
            circularTexture.textures[i]:SetPoint("TOPLEFT", frame, -offset, offset)
        end
    else
        for i = 1, 3 do
            circularTexture.textures[i]:ClearAllPoints()
            circularTexture.textures[i]:SetAllPoints(frame)
        end
    end

    circularTexture:UpdateTextures()
end

-- ============================================================
-- CONVENIENCE: Create a complete ring progress widget
-- ============================================================

function CircularProgress:CreateRingWidget(parent, size, options)
    options = options or {}

    -- Create container frame
    local widget = CreateFrame("Frame", nil, parent)
    widget:SetSize(size, size)

    -- Background ring (always full)
    widget.background = self:Create(widget, "BACKGROUND", 0)
    self:Modify(widget.background, {
        texture = options.texture or "Interface\\AddOns\\DDingUI\\Media\\Textures\\Ring_20px.tga",
        width = size,
        height = size,
        crop_x = options.crop_x or 1.41,
        crop_y = options.crop_y or 1.41,
        blendMode = "BLEND",
    })
    widget.background:SetColor(
        options.bgColor and options.bgColor[1] or 0.15,
        options.bgColor and options.bgColor[2] or 0.15,
        options.bgColor and options.bgColor[3] or 0.15,
        options.bgColor and options.bgColor[4] or 0.8
    )
    widget.background:SetProgress(0, 360)
    widget.background:Show()

    -- Foreground ring (progress)
    widget.foreground = self:Create(widget, "ARTWORK", 1)
    self:Modify(widget.foreground, {
        texture = options.texture or "Interface\\AddOns\\DDingUI\\Media\\Textures\\Ring_20px.tga",
        width = size,
        height = size,
        crop_x = options.crop_x or 1.41,
        crop_y = options.crop_y or 1.41,
        blendMode = "BLEND",
    })
    widget.foreground:SetColor(
        options.fgColor and options.fgColor[1] or 1,
        options.fgColor and options.fgColor[2] or 0.8,
        options.fgColor and options.fgColor[3] or 0,
        options.fgColor and options.fgColor[4] or 1
    )
    widget.foreground:SetProgress(0, 360)
    widget.foreground:Show()

    -- Widget methods
    widget.SetProgress = function(self, progress)
        -- progress: 0-1, clockwise from top
        self.foreground:SetValue(progress, 0, 360)
    end

    widget.SetProgressReverse = function(self, progress)
        -- progress: 0-1, counter-clockwise (fills up as progress increases)
        self.foreground:SetValueReverse(progress, 0, 360)
    end

    widget.SetForegroundColor = function(self, r, g, b, a)
        self.foreground:SetColor(r, g, b, a or 1)
    end

    widget.SetBackgroundColor = function(self, r, g, b, a)
        self.background:SetColor(r, g, b, a or 1)
    end

    widget.SetTexture = function(self, texture)
        self.foreground:SetTextureOrAtlas(texture)
        self.background:SetTextureOrAtlas(texture)
    end

    widget.SetSize = function(self, w, h)
        h = h or w
        self:SetWidth(w)
        self:SetHeight(h)
        self.foreground.width = w
        self.foreground.height = h
        self.background.width = w
        self.background.height = h
        self.foreground:UpdateTextures()
        self.background:UpdateTextures()
    end

    return widget
end

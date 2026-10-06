local _, FX = ...

local function SetFrameIndex(frame, index)
    local preset = frame.preset
    local capacity = preset.columns * preset.rows
    local page = math.floor(index / capacity) + 1
    local texture = frame.textures[page]
    local cell = index % capacity
    local col, row = cell % preset.columns, math.floor(cell / preset.columns)
    texture:SetTexCoord(col / preset.columns, (col + 1) / preset.columns,
        row / preset.rows, (row + 1) / preset.rows)
    if page ~= frame.page then
        if frame.texture then frame.texture:Hide() end
        texture:Show()
        frame.texture, frame.page = texture, page
    end
    frame.frameIndex = index
end

local function Update(frame, elapsed)
    frame.elapsed = frame.elapsed + elapsed * frame.speed
    local index = math.floor(frame.elapsed * frame.preset.fps)
    if index >= frame.preset.frames then
        if not frame.loop then frame:Stop(); return end
        frame.elapsed = frame.elapsed % (frame.preset.frames / frame.preset.fps)
        index = math.floor(frame.elapsed * frame.preset.fps)
    end
    if frame.frameIndex ~= index then SetFrameIndex(frame, index) end
end

function FX:CreatePlayer(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:EnableMouse(false)
    frame.textures = {}
    function frame:Stop()
        self:SetScript("OnUpdate", nil)
        self.playing = false
        self:Hide()
    end
    function frame:Play(preset, speed, loop)
        self:Stop()
        if not preset then return false end
        self.preset, self.speed, self.loop = preset, speed or 1, loop
        local pages = math.ceil(preset.frames / (preset.columns * preset.rows))
        for page, texture in ipairs(self.textures) do
            texture:Hide()
            if page > pages then texture:SetTexture(nil) end
        end
        -- Bind every page before starting; swapping a large TGA mid-play can show a blank frame.
        for page = 1, pages do
            local texture = self.textures[page]
            if not texture then
                texture = self:CreateTexture(nil, "ARTWORK")
                texture:SetAllPoints()
                texture:SetBlendMode("BLEND")
                texture:SetBlockingLoadsRequested(true)
                self.textures[page] = texture
            end
            texture:Hide()
            local path = page == 1 and preset.path or preset.path:sub(1, -5) .. "_" .. page .. ".tga"
            if texture:SetTexture(path, "CLAMP", "CLAMP", "NEAREST") == false then return false end
        end
        self.elapsed, self.frameIndex, self.page = 0, nil, nil
        SetFrameIndex(self, 0)
        self.playing = true
        self:Show()
        self:SetScript("OnUpdate", Update)
        return true
    end
    frame:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        self.playing = false
    end)
    frame:Hide()
    return frame
end

function FX:FireRule(rule, skipSound)
    if not skipSound then self:PlaySound(rule.sound) end
    local preset = self.presets[rule.preset]
    if not preset then return end
    local player = self.active[rule]
    if not player then
        player = table.remove(self.playerPool or {}) or self:CreatePlayer(UIParent)
        player:SetFrameStrata("HIGH")
        self.active[rule] = player
    end
    player:ClearAllPoints()
    player:SetPoint("CENTER", UIParent, "CENTER", rule.x, rule.y)
    player:SetSize(self:EffectSize(rule))
    player:SetAlpha((rule.opacity or 100) / 100)
    player:Play(preset, rule.speed, false)
end

function FX:StopLive()
    if self.testing then self:StopTest() end
    self.playerPool = self.playerPool or {}
    for rule, player in pairs(self.active) do
        player:Stop()
        self.playerPool[#self.playerPool+1] = player
        self.active[rule] = nil
    end
end

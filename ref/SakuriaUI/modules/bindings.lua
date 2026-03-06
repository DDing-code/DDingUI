SakuriaUI_Bindings = SakuriaUI_Bindings or {}

function SakuriaUI_Bindings.Enable()
    local HOTKEY_FONT_SIZE = 12
    local MACRO_FONT_SIZE  = 12

    local MAX_HOTKEY_CHARS = 3
    local MAX_MACRO_CHARS  = 5

    local HOTKEY_COLOR = { r = 1, g = 1, b = 1 }
    local MACRO_COLOR  = { r = 1, g = 1, b = 1 }

    local prefixes = {
        "ActionButton",
        "MultiBarBottomLeftButton",
        "MultiBarBottomRightButton",
        "MultiBarRightButton",
        "MultiBarLeftButton",
        "MultiBar5Button",
        "MultiBar6Button",
    }

    local function CleanText(s)
        if not s or s == "" then
            return s
        end

        return s
            :gsub("|A.-|a", "")
            :gsub("|T.-|t", "")
            :gsub("|c%x%x%x%x%x%x%x%x", "")
            :gsub("|r", "")
    end

    local function UTF8Truncate(s, maxChars)
        if not s then
            return s
        end
        if maxChars <= 0 then
            return ""
        end

        local i, len, bytes = 1, 0, #s
        while i <= bytes do
            len = len + 1
            if len > maxChars then
                return s:sub(1, i - 1)
            end

            local c = s:byte(i)
            if c < 0x80 then
                i = i + 1
            elseif c < 0xE0 then
                i = i + 2
            elseif c < 0xF0 then
                i = i + 3
            else
                i = i + 4
            end
        end

        return s
    end

    local function ShortenKeybind(text)
        if not text then
            return ""
        end

        text = text
            :gsub("SHIFT%-", "S")
            :gsub("CTRL%-", "C")
            :gsub("ALT%-", "A")
            :gsub("NUMPAD", "N")
            :gsub("Mouse Wheel Up", "MU")
            :gsub("Mouse Wheel Down", "MD")
            :gsub("MOUSEWHEELUP", "MU")
            :gsub("MOUSEWHEELDOWN", "MD")
            :gsub("Mouse Button (%d+)", "M%1")
            :gsub("MOUSEBUTTON(%d+)", "M%1")
            :gsub("BUTTON(%d+)", "M%1")
            :gsub("Middle Mouse", "M3")
            :gsub("Right Mouse", "M2")
            :gsub("Left Mouse", "M1")
            :gsub("PLUS", "+")
            :gsub("MINUS", "-")
            :gsub("MULTIPLY", "*")
            :gsub("DIVIDE", "/")
            :gsub("[%-]", "")

        if #text > MAX_HOTKEY_CHARS then
            text = text:sub(1, MAX_HOTKEY_CHARS)
        end

        return text
    end

    local function ShortenMacro(text)
        if not text then
            return ""
        end

        text = CleanText(text)
        if text == "" then
            return text
        end

        local i, len, bytes = 1, 0, #text
        while i <= bytes and len <= MAX_MACRO_CHARS do
            len = len + 1

            local c = text:byte(i)
            if c < 0x80 then
                i = i + 1
            elseif c < 0xE0 then
                i = i + 2
            elseif c < 0xF0 then
                i = i + 3
            else
                i = i + 4
            end
        end

        if len <= MAX_MACRO_CHARS then
            return text
        end

        return UTF8Truncate(text, MAX_MACRO_CHARS)
    end

    local function EnforceMacroShorteningOnFS(fs)
        if not fs or fs._Sakuria_Enforced then
            return
        end
        fs._Sakuria_Enforced = true

        hooksecurefunc(fs, "SetText", function(self, newText)
            if self._saku_lock then
                return
            end

            local truncated = ShortenMacro(newText or "")
            if truncated ~= (newText or "") then
                self._saku_lock = true
                self:SetText(truncated)
                self._saku_lock = false
            end

            self:SetMaxLines(1)
            self:SetWordWrap(false)
        end)

        hooksecurefunc(fs, "SetFormattedText", function(self, fmt, ...)
            if self._saku_lock then
                return
            end

            local candidate = string.format(fmt or "", ...)
            local truncated = ShortenMacro(candidate or "")
            if truncated ~= candidate then
                self._saku_lock = true
                self:SetText(truncated)
                self._saku_lock = false
            end

            self:SetMaxLines(1)
            self:SetWordWrap(false)
        end)
    end

    local function EnforceTextColor(fs, r, g, b)
        if not fs or fs._Sakuria_ColorEnforced then
            return
        end
        fs._Sakuria_ColorEnforced = true

        local function Apply(self)
            if self._saku_color_lock then
                return
            end
            self._saku_color_lock = true
            self:SetTextColor(r, g, b)
            self._saku_color_lock = false
        end

        hooksecurefunc(fs, "SetTextColor", function(self, nr, ng, nb)
            if self._saku_color_lock then
                return
            end
            if nr ~= r or ng ~= g or nb ~= b then
                Apply(self)
            end
        end)

        hooksecurefunc(fs, "SetVertexColor", function(self, nr, ng, nb)
            if self._saku_color_lock then
                return
            end
            if nr ~= r or ng ~= g or nb ~= b then
                Apply(self)
            end
        end)

        Apply(fs)
    end
	
    local function ApplyOutline(fs, size)
        if not fs then
            return
        end
        local font = fs:GetFont()
        if font then
            fs:SetFont(font, size, "OUTLINE")
        end
    end

    local function StyleAndShortenForButton(btn)
        if not btn then
            return
        end

        local hk = btn.HotKey
        if hk then
            local orig = hk:GetText()
            if orig and orig ~= "" then
                local shortHK = ShortenKeybind(orig)
                if shortHK ~= orig then
                    hk:SetText(shortHK)
                end
            end

            ApplyOutline(hk, HOTKEY_FONT_SIZE)

            hk:SetWidth(64)
            hk:SetJustifyH("RIGHT")
            hk:SetMaxLines(1)
            hk:SetWordWrap(false)

            hk:SetTextColor(HOTKEY_COLOR.r, HOTKEY_COLOR.g, HOTKEY_COLOR.b)
            EnforceTextColor(hk, HOTKEY_COLOR.r, HOTKEY_COLOR.g, HOTKEY_COLOR.b)
        end

        local nameFS = btn.Name
        if nameFS then
            EnforceMacroShorteningOnFS(nameFS)

            local txt = nameFS:GetText()
            if txt and txt ~= "" then
                local short = ShortenMacro(txt)
                if short ~= txt then
                    nameFS:SetText(short)
                end
            end

            ApplyOutline(nameFS, MACRO_FONT_SIZE)

            nameFS:SetWidth(80)
            nameFS:SetJustifyH("CENTER")
            nameFS:SetMaxLines(1)
            nameFS:SetWordWrap(false)

            nameFS:SetTextColor(MACRO_COLOR.r, MACRO_COLOR.g, MACRO_COLOR.b)
            EnforceTextColor(nameFS, MACRO_COLOR.r, MACRO_COLOR.g, MACRO_COLOR.b)
        end
    end

    local function SweepAllButtons()
        for _, prefix in ipairs(prefixes) do
            for i = 1, 12 do
                local btn = _G[prefix .. i]
                if btn then
                    StyleAndShortenForButton(btn)
                end
            end
        end
    end

    C_Timer.After(0.2, SweepAllButtons)

    if ActionBarActionButtonMixin and not SakuriaUI_Bindings._hookRetail then
        hooksecurefunc(ActionBarActionButtonMixin, "UpdateAction", function(self)
            StyleAndShortenForButton(self)
        end)
        SakuriaUI_Bindings._hookRetail = true
    end

    if not SakuriaUI_Bindings._hookClassic then
        if type(ActionButton_Update) == "function" then
            hooksecurefunc("ActionButton_Update", function(btn)
                StyleAndShortenForButton(btn)
            end)
        end

        if type(ActionButton_UpdateAction) == "function" then
            hooksecurefunc("ActionButton_UpdateAction", function(btn)
                StyleAndShortenForButton(btn)
            end)
        end

        SakuriaUI_Bindings._hookClassic = true
    end

    if not SakuriaUI_Bindings._frame then
        local f = CreateFrame("Frame")
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        f:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
        f:RegisterEvent("UPDATE_BINDINGS")
        f:RegisterEvent("CVAR_UPDATE")
        f:RegisterEvent("UPDATE_MACROS")
        f:RegisterEvent("SPELLS_CHANGED")
        f:RegisterEvent("PLAYER_REGEN_ENABLED")

        f:SetScript("OnEvent", function(_, event, arg1)
            if event == "CVAR_UPDATE" and arg1 ~= "SHOW_MACRO_NAMES" then
                return
            end

            if InCombatLockdown() then
                SakuriaUI_Bindings._needsRefresh = true
                return
            end

            SweepAllButtons()
        end)

        SakuriaUI_Bindings._frame = f
    end

    hooksecurefunc(SakuriaUI_Bindings, "Enable", function()
        if SakuriaUI_Bindings._needsRefresh and not InCombatLockdown() then
            SakuriaUI_Bindings._needsRefresh = false
            SweepAllButtons()
        end
    end)
end

function SakuriaUI_Bindings.Disable()
    if InCombatLockdown() then
        SakuriaUI_Bindings._needsRefresh = true
        return
    end

    if ActionBarActionButtonMixin then
        local disablePrefixes = {
            "ActionButton",
            "MultiBarBottomLeftButton",
            "MultiBarBottomRightButton",
            "MultiBarRightButton",
            "MultiBarLeftButton",
            "MultiBar5Button",
            "MultiBar6Button",
        }

        for _, prefix in ipairs(disablePrefixes) do
            for i = 1, 12 do
                local btn = _G[prefix .. i]
                if btn and btn.UpdateAction then
                    btn:UpdateAction()
                end
            end
        end
    end
end
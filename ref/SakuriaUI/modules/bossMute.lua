-- Mutes Boss Sounds during encounters & enables them again as soon as the fight ends
-- Good for focusing on warning sounds etc. without being distracted by spell sounds

SakuriaUI_BossMute = {}
local mod = SakuriaUI_BossMute

local f = CreateFrame("Frame")

local cvarMap = {
  disableSfx = "Sound_EnableSFX",
  disableMusic = "Sound_EnableMusic",
  disableAmbience = "Sound_EnableAmbience",
  disableErrorSpeech = "Sound_EnableErrorSpeech",
}

local stored = nil
local active = 0

local function GetCVarSafe(name)
  local ok, val = pcall(GetCVar, name)
  return ok and val or nil
end

local function SetCVarSafe(name, value)
  pcall(SetCVar, name, value)
end

local function GetSettings()
  SakuriaUI_DB = SakuriaUI_DB or {}
  SakuriaUI_DB.bossMuteSettings = SakuriaUI_DB.bossMuteSettings or {}
  local s = SakuriaUI_DB.bossMuteSettings

  if s.disableSfx == nil then s.disableSfx = true end
  if s.disableMusic == nil then s.disableMusic = false end
  if s.disableAmbience == nil then s.disableAmbience = false end
  if s.disableErrorSpeech == nil then s.disableErrorSpeech = false end

  return s
end

local function ApplyMute()
  local s = GetSettings()

  if not stored then
    stored = {}
    for _, cvar in pairs(cvarMap) do
      stored[cvar] = GetCVarSafe(cvar)
    end
  end

  for opt, cvar in pairs(cvarMap) do
    if s[opt] then
      SetCVarSafe(cvar, "0")
    end
  end
end

local function Restore()
  if not stored then return end
  for cvar, value in pairs(stored) do
    if value ~= nil then
      SetCVarSafe(cvar, value)
    end
  end
  stored = nil
end

local function OnEvent(_, event, ...)
  if event == "ENCOUNTER_START" then
    active = active + 1
    if active == 1 then ApplyMute() end

  elseif event == "ENCOUNTER_END" then
    if active > 0 then active = active - 1 end
    if active == 0 then Restore() end

  elseif event == "PLAYER_ENTERING_WORLD" then
    if IsEncounterInProgress and IsEncounterInProgress() then
      if active == 0 then
        active = 1
        ApplyMute()
      end
    else
      if active ~= 0 then
        active = 0
        Restore()
      end
    end
  end
end

function mod.Enable()
  f:SetScript("OnEvent", OnEvent)
  f:RegisterEvent("ENCOUNTER_START")
  f:RegisterEvent("ENCOUNTER_END")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")

  if IsEncounterInProgress and IsEncounterInProgress() then
    active = 1
    ApplyMute()
  end
end

function mod.Disable()
  f:UnregisterEvent("ENCOUNTER_START")
  f:UnregisterEvent("ENCOUNTER_END")
  f:UnregisterEvent("PLAYER_ENTERING_WORLD")
  f:SetScript("OnEvent", nil)

  active = 0
  Restore()
end
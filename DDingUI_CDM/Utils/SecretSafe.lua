-- ============================================================
-- DDingUI SecretSafe — WoW 12.0 SecretValue 안전 유틸리티
-- ============================================================
local AddonName, ns = ...
local DDingUI = LibStub("AceAddon-3.0"):GetAddon("DDingUI")

DDingUI.SecretSafe = {}
local SS = DDingUI.SecretSafe

function SS.IsSafeNumber(v) return type(v) == "number" and not issecretvalue(v) end
function SS.SafeNumberOr(v, fb) return SS.IsSafeNumber(v) and v or (fb or 0) end
function SS.SafeEquals(v, expected) return (type(v) ~= "number" or not issecretvalue(v)) and v == expected end

-- CooldownCurves (WoW 12.0 비밀값 안전 쿨다운 상태 감지)
SS.Curves = {}
if C_CurveUtil and C_CurveUtil.CreateCurve then
    SS.Curves.Binary = C_CurveUtil.CreateCurve()
    SS.Curves.Binary:AddPoint(0.0, 0)
    SS.Curves.Binary:AddPoint(0.001, 1)
    SS.Curves.Binary:AddPoint(1.0, 1)

    SS.Curves.Desaturation = C_CurveUtil.CreateCurve()
    SS.Curves.Desaturation:AddPoint(0.0, 0)
    SS.Curves.Desaturation:AddPoint(0.01, 1)
    SS.Curves.Desaturation:AddPoint(1.0, 1)
end

function SS.IsCooldownActive(spellID)
    if not spellID or not (C_Spell and C_Spell.GetSpellCooldownDuration) then return nil end
    local durObj = C_Spell.GetSpellCooldownDuration(spellID)
    if not durObj or not durObj.EvaluateRemainingDuration or not SS.Curves.Binary then return nil end
    local result = durObj:EvaluateRemainingDuration(SS.Curves.Binary, 0)
    return result and type(result) == "number" and result > 0.5
end

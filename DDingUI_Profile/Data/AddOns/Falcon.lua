local DUI = unpack(DDingUI_Profile)
local D = DUI:GetModule("Data")

------------------------------------------------------------------------
-- Falcon (Skyriding Falcon) 프로필 데이터
-- SavedVariables (FalconAddOnDB.Settings.FalconGlobalSettings) 테이블 직접 복사
------------------------------------------------------------------------
D.falcon = {
    ["Styles"] = {
        ["Clean"] = {
            ["SpeedHeight"] = 7,
            ["SwapPositions"] = false,
            ["Padding"] = 0,
            ["ChargeHeight"] = 7,
            ["Width"] = 63,
        },
    },
    ["General"] = {
        ["ApplySpeedBarColorsToChargeBar"] = false,
    },
    ["scale"] = 1,
    ["secondWindMode"] = 1,
    ["StatusBarColors"] = {
        ["SecondWind"] = {
            ["a"] = 1,
            ["b"] = 0.65,
            ["g"] = 0.45,
            ["r"] = 0,
        },
        ["Charge"] = {
            ["a"] = 1,
            ["r"] = 0,
            ["g"] = 0.67,
            ["b"] = 0.98,
        },
        ["GroundSkimming"] = {
            ["a"] = 1,
            ["b"] = 0.25,
            ["g"] = 0.77,
            ["r"] = 0.88,
        },
        ["Thrill"] = {
            ["a"] = 1,
            ["r"] = 0.549,
            ["g"] = 0.8118,
            ["b"] = 0.3882,
        },
        ["LowSpeed"] = {
            ["a"] = 1,
            ["b"] = 0.39,
            ["g"] = 0.32,
            ["r"] = 0.86,
        },
    },
    ["FontSettings"] = {
        ["Flags"] = "",
        ["Name"] = "ARIALN",
        ["Position"] = {
            ["Justify"] = "RIGHT",
        },
        ["Size"] = 14,
        ["Hide"] = true,
    },
    ["hideWhenGroundedAndFull"] = true,
    ["CurrentTexture"] = {
        ["Name"] = "Melli",
        ["Texture"] = "Interface\\Addons\\SharedMedia\\statusbar\\Melli",
    },
    ["BuffSettings"] = {
        ["Anchor"] = "Right",
        ["Visibility"] = 1,
        ["Size"] = 28,
    },
    ["FrameColors"] = {
        ["ShadowColor"] = {
            ["a"] = 0,
            ["b"] = 0,
            ["g"] = 0,
            ["r"] = 0,
        },
        ["BackgroundColor"] = {
            ["a"] = 1,
            ["b"] = 0.2000000178813934,
            ["g"] = 0.2000000178813934,
            ["r"] = 0.2000000178813934,
        },
        ["InsideGlowColor"] = {
            ["a"] = 0,
            ["r"] = 1,
            ["g"] = 1,
            ["b"] = 1,
        },
        ["BorderColor"] = {
            ["a"] = 1,
            ["r"] = 0,
            ["g"] = 0,
            ["b"] = 0,
        },
    },
    ["DefaultTexture"] = {
        ["Name"] = "Falcon Smooth",
        ["Texture"] = "Interface\\AddOns\\Falcon\\Media\\Statusbar\\FalconSmooth.tga",
    },
    ["Version"] = 2,
    ["Position"] = {
        ["y"] = -102.666748046875,
        ["x"] = -0.444488525390625,
        ["point"] = "CENTER",
        ["scale"] = 1,
    },
    ["whirlingSurgeMode"] = 0,
    ["BarBehaviourFlags"] = 0,
    ["mutedSoundsBitfield"] = 0,
    ["CurrentStyle"] = "Clean",
}

------------------------------------------------------
-- DDingUI_Controller :: Defaults
-- Default settings for global font/texture management
------------------------------------------------------
DDingUI_ControllerDefaults = {
    font = {
        primary   = "Fonts\\2002.TTF",       -- 메인 폰트 (한글)
        secondary = "Fonts\\FRIZQT__.TTF",    -- 보조 폰트 (영문/숫자)
        sizeScale = 1.0,                      -- 글로벌 크기 배율 (0.8~1.5)
    },
    texture = {
        statusBar = [[Interface\Buttons\WHITE8x8]],  -- 상태바 텍스처
        flat      = [[Interface\Buttons\WHITE8x8]],   -- 배경/단색 텍스처
    },
}

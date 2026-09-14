from PIL import Image, ImageChops, ImageOps

from test_calm_alert_visual import ROOT, calm_runtime


def mask_runtime(locale="koKR"):
    lua = calm_runtime(locale)
    lua.execute('''
        local methods = getmetatable(UIParent).__index
        function methods:SetVertexColor(...) self.vertexColor={...} end
        function methods:SetBlendMode(mode) self.blendMode=mode end
        function methods:SetShadowOffset() end
        function methods:SetShadowColor() end
        function methods:RegisterUnitEvent() end
    ''')
    lua.execute((ROOT / "Modules/BloodlustTimer/BloodlustTimer.lua").read_text(encoding="utf-8-sig"),
                "DDingUI_Toolkit", lua.globals().ns)
    return lua


def test_mask_textures_and_color_motion():
    masks = []
    for name in ("Mask", "MaskAccent"):
        path = ROOT / "Media/BloodlustSystem" / (name + ".tga")
        header = path.read_bytes()[:18]
        assert header[2] == 2 and header[16] == 32 and header[17] & 15 == 8
        image = Image.open(path)
        assert image.mode == "RGBA" and image.size == (256, 256)
        assert image.convert("RGB").getextrema() == ((255, 255),) * 3
        alpha = image.getchannel("A")
        assert alpha.getextrema() == (0, 255)
        assert alpha.tobytes() == ImageOps.mirror(alpha).tobytes()
        assert alpha.crop((0, 0, 256, 12)).getextrema() == (0, 0)
        assert 500 < sum(value > 0 for value in alpha.getdata()) < 30000
        masks.append(alpha)
    assert ImageChops.multiply(*masks).getextrema()[1] < 64, "Only antialiased edges may overlap"

    for locale in ("koKR", "enUS"):
        lua = mask_runtime(locale)
        lua.execute('''
            local module = ns.BloodlustTimer
            module:PlayStartMotion(true, false)
            local frame, db = module.startMotionFrame, module.db
            assert(frame.systemCrest.texture:match("Mask%.tga$"))
            assert(frame.systemCrestCore.texture:match("MaskAccent%.tga$"))
            assert(frame.systemCrest.blendMode == "BLEND" and frame.systemCrestCore.blendMode == "BLEND")
            assert(frame.systemCrestGlow.blendMode == "ADD")
            db.startMotionSystemCrestColor = {0.1, 0.8, 0.2, 0.7}
            db.startMotionSystemCrestCoreColor = {0.3, 0.4, 1, 0.6}
            local allocated = #regions
            for _, width in ipairs({360,620,900}) do
                for _, height in ipairs({90,130,220}) do
                    db.startMotionWidth, db.startMotionHeight, db.startMotionFontSize = width,height,72
                    module:ApplyStartMotionSettings()
                    assert(frame.systemTitle.fontSize == math.min(72, height * 0.32))
                    assert(frame.systemTitle.width == width - 190)
                    for _, progress in ipairs({0,0.1,0.3,0.5,0.7,0.9,1}) do
                        module:RenderStartMotion(progress)
                        assert(not frame.art.shown and frame.systemArt.shown)
                        assert(frame.systemCrest.x == frame.systemCrestCore.x)
                        assert(frame.systemCrest.y == frame.systemCrestCore.y)
                        assert(frame.systemCrest.width == frame.systemCrestCore.width)
                        local ringSize = math.min(height * 0.94, width * 0.22)
                        assert(frame.systemOuterRing.width == ringSize)
                        assert(frame.systemOuterRing.y == height * 0.03)
                        assert(frame.systemCrest.width == ringSize * 0.54)
                        assert(frame.systemPanelLeft.y == 0 and frame.systemPanelRight.y == 0)
                        assert(frame.systemPanelLeft.height == height * 0.68)
                        local reveal = ns.CalmAlertStyle.SmoothStep((progress - 0.30) / 0.22)
                        assert(frame.systemTitle.y == -height * 0.015 + (1 - reveal) * 4)
                        if frame.systemTitle.color[4] > 0 then
                            local top = frame.systemTitle.y + frame.systemTitle.height * frame.systemTitle.scale / 2
                            local bottom = frame.systemTitle.y - frame.systemTitle.height * frame.systemTitle.scale / 2
                            assert(top < frame.systemTopLeft.y, "Title exceeds top rail")
                            assert(bottom > frame.systemStatusNodes[2].y + frame.systemStatusNodes[2].height / 2, "Title overlaps bottom node")
                        end
                    end
                end
            end
            assert(#regions == allocated, "Rendering must reuse frames/textures")
            db.startMotionWidth, db.startMotionHeight, db.startMotionFontSize = 620,130,38
            module:ApplyStartMotionSettings()
            module:RenderStartMotion(0.6)
            assert(frame.systemTitle.fontSize == 38)
            assert(math.abs(frame.systemOuterRing.width - 122.2) < 0.001)
            assert(math.abs(frame.systemTitle.y + 1.95) < 0.001)
            local mask, accent = frame.systemCrest, frame.systemCrestCore
            assert(mask.vertexColor[1] == 0.1 and mask.vertexColor[2] == 0.8 and mask.vertexColor[3] == 0.2)
            assert(accent.vertexColor[1] == 0.3 and accent.vertexColor[2] == 0.4 and accent.vertexColor[3] == 1)
            assert(mask.alpha <= 0.7 and accent.alpha <= 0.6)
            db.startMotionSystemCrestColor[4], db.startMotionSystemCrestCoreColor[4] = 0,0
            module:RenderStartMotion(0.6)
            assert(mask.alpha == 0 and accent.alpha == 0 and frame.systemCrestGlow.alpha == 0)
            module:UpdateStartMotion(10)
            assert(not frame.shown)
            db.startMotionStyle = "RITUAL"
            module:PlayStartMotion(true, false)
            module:RenderStartMotion(0.6)
            assert(frame.art.shown and not frame.systemArt.shown)
            module:StopStartMotion()
        ''')


def test_mask_migration_preserves_custom_colors():
    for custom in (False, True):
        lua = mask_runtime()
        lua.globals().custom = custom
        lua.execute('''
            local db = ns.db.profile.BloodlustTimer
            db.startMotionStyleVersion = 4
            db.startMotionSystemCrestColor = custom and {0.2,0.4,0.6,0.8} or {1,0.82,0.62,1}
            db.startMotionSystemCrestCoreColor = custom and {0.7,0.6,0.3,0.5} or {0.9,0.025,0.075,1}
            ns.BloodlustTimer:PlayStartMotion(true, false)
            assert(db.startMotionStyleVersion == 5)
            if custom then
                assert(db.startMotionSystemCrestColor[1] == 0.2 and db.startMotionSystemCrestColor[4] == 0.8)
                assert(db.startMotionSystemCrestCoreColor[1] == 0.7 and db.startMotionSystemCrestCoreColor[4] == 0.5)
            else
                assert(db.startMotionSystemCrestColor[1] == 241/255)
                assert(db.startMotionSystemCrestCoreColor[1] == 219/255)
            end
            ns.BloodlustTimer:StopStartMotion()
        ''')

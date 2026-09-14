from PIL import Image

from test_calm_alert_visual import ROOT, calm_runtime


def mail_runtime(locale="koKR"):
    lua = calm_runtime(locale)
    lua.execute('''
        now, sounds, flashes, timers = 100, 0, 0, {}
        faction, newMail, combat = "Alliance", false, false
        function GetTime() return now end
        function UnitFactionGroup() return faction end
        function HasNewMail() return newMail end
        function InCombatLockdown() return combat end
        function IsInInstance() return false end
        function FlashClientIcon() flashes=flashes+1 end
        function print() end
        function ns:RequestSound() sounds=sounds+1 end
        function ns:CancelManagedSoundsBySource() end
        C_Timer={After=function(delay,callback) timers[#timers+1]={due=now+delay,callback=callback} end}
        function advance(dt)
            now=now+dt
            local pending=timers; timers={}
            for _,timer in ipairs(pending) do
                if timer.due<=now then timer.callback() else timers[#timers+1]=timer end
            end
        end
        local methods=getmetatable(UIParent).__index
        function methods:SetTexCoord(...) self.uv={...} end
        function methods:SetVertexColor(...) self.vertexColor={...} end
        function methods:GetFont() return self.font,self.fontSize,self.fontFlags end
        function methods:SetAtlas(atlas) self.atlas=atlas end
        function methods:SetShadowColor() end
        function methods:SetShadowOffset() end
        function methods:UnregisterAllEvents() end
        local makeFont=methods.CreateFontString
        function methods:CreateFontString(name,layer,template)
            local fs=makeFont(self,name,layer)
            if template then fs:SetFont("GameFont",16,"") end
            return fs
        end
        function methods:CreateAnimationGroup()
            local ag={playing=false,scripts={},generation=0}
            function ag:CreateAnimation()
                return {SetFromAlpha=function() end,SetToAlpha=function() end,
                    SetDuration=function(_,duration) ag.duration=duration end}
            end
            function ag:SetScript(name,callback) self.scripts[name]=callback end
            function ag:SetLooping(loop) self.loop=loop end
            function ag:IsPlaying() return self.playing end
            function ag:Stop() self.playing=false; self.generation=self.generation+1 end
            function ag:Play()
                self:Stop(); self.playing=true
                local generation=self.generation
                if not self.loop then C_Timer.After(self.duration,function()
                    if generation~=self.generation then return end
                    self.playing=false
                    if self.scripts.OnFinished then self.scripts.OnFinished() end
                end) end
            end
            return ag
        end
    ''')
    for file in ("Modules/MailAlert/MailAlert.lua", "Modules/MailAlert/AlertFrame.lua"):
        lua.execute((ROOT / file).read_text(encoding="utf-8-sig"), "DDingUI_Toolkit", lua.globals().ns)
    return lua


def test_mail_design_selection_motion_and_preview():
    for locale in ("koKR", "enUS"):
        lua = mail_runtime(locale)
        lua.execute('''
            local mail=ns.MailAlert
            local db=ns.db.profile.MailAlert
            assert(db.alertStyle=="FACTION" and db.sealMotion)
            mail:OnInitialize(); mail:OnEnable()
            assert(mail.alertFrame==mail.factionFrame and not mail.sealVisual)
            db.alertStyle=nil -- Existing profiles without the new key retain the original.
            mail:TriggerAlert(false)
            local original=mail.alertFrame
            assert(original.width==475 and original.height==64 and original.pulse:IsPlaying())
            assert(original.factionBg.atlas=="Objective-Header-CampaignAlliance")
            assert(original.text.text==ns.L.MAILALERT_NEW_MAIL_TEXT)
            assert(sounds==1 and flashes==1)
            local oldTimers=timers; timers={}
            db.alertStyle="SEAL"
            mail:ApplySettings()
            local visual,frame=mail.sealVisual,mail.alertFrame
            assert(not original:IsShown() and not original.pulse:IsPlaying())
            assert(frame==visual.frame and frame.width==560 and frame.height==166)
            assert(sounds==1 and flashes==1, "Switching designs must not replay sounds/flashes")
            for _,timer in ipairs(oldTimers) do timer.callback() end
            assert(frame:IsShown(), "Old hide timers must not close the new design")
            assert(frame.mailSeal.texture:match("MailAlertIcons%.tga$"))
            assert(frame.mailIcon.uv[1]==0.5 and frame.mailSeal.uv[2]==0.5)
            assert(frame.title.fontSize==29 and frame.subtitle.fontSize==14)
            local allocated=#regions
            for _,duration in ipairs({1,5,15}) do
                db.alertDuration=duration
                mail:ShowAlert(false)
                visual:OnUpdate(.1)
                local earlyWidth=frame.topLeft.width
                visual:OnUpdate(duration*.5-.1)
                assert(frame.topLeft.width>earlyWidth)
                visual:OnUpdate(duration*.5)
                assert(not frame:IsShown() and not visual.state and #regions==allocated)
            end
            db.alertDuration=5
            mail:ShowAlert(false); visual:OnUpdate(1.2)
            assert(math.abs(frame.topLeft.width-226)<.01)
            assert(frame.title.y==-6.5 and frame.subtitle.y==-45.5 and frame.mailSeal.y==51)
            assert(frame.title.y+frame.title.fontSize/2<frame.mailIcon.y-13)
            assert(frame.subtitle.y+7<frame.title.y-frame.title.fontSize/2)
            assert(frame.subtitle.y-7>frame.bottomLeft.y)
            assert(frame.haloLeft.x==0 and frame.haloLeft.width==560*.52)
            assert(frame.haloLeft.width/2==frame.panelRight.x-frame.panelRight.width/2)
            mail:HideAlert(false); visual:OnUpdate(.2)
            assert(frame:IsShown() and frame.art.alpha>0 and frame.title.color[4]>0)
            visual:OnUpdate(.3); assert(not frame:IsShown())

            db.sealMotion=false
            for _,position in ipairs({"TOP","CENTER","BOTTOM"}) do
                db.alertPosition=position
                for _,scale in ipairs({.5,1,2}) do
                    db.alertScale=scale
                    mail:EnterEditPreview()
                    assert(frame:IsShown() and not visual.state and frame.art.alpha==1)
                    assert(frame.point==position and frame.scale==scale)
                    assert(frame.title.text==ns.L.MAILALERT_SEAL_TITLE)
                    assert(frame.subtitle.text==ns.L.MAILALERT_SEAL_SUBTITLE)
                    visual:OnUpdate(20)
                    assert(frame:IsShown() and frame.title.y==-6.5)
                end
            end
            db.sealMotion=true; mail:RefreshEditPreview()
            assert(visual.state.looping)
            visual:OnUpdate(12); assert(frame:IsShown())
            db.alertStyle="FACTION"; faction="Horde"
            mail:RefreshEditPreview()
            assert(not frame:IsShown() and not visual.state and original:IsShown())
            assert(original.factionBg.atlas=="Objective-Header-CampaignHorde")
            assert(original.text.text==ns.L.MAILALERT_TEST_TEXT)
            advance(30); assert(original:IsShown(), "Persistent original preview must not time out")
            mail:ExitEditPreview(); assert(not original:IsShown())
            db.alertStyle="SEAL"; mail:EnterEditPreview(); mail:OnDisable()
            assert(not frame:IsShown() and not original:IsShown() and not visual.state)
            advance(30); assert(not original:IsShown())

            db.alertStyle="FACTION"; db.alertAnimation="pulse"
            mail:ShowAlert(false)
            oldTimers=timers; timers={}
            mail:ShowAlert(false)
            for _,timer in ipairs(oldTimers) do timer.callback() end
            assert(original:IsShown() and original.pulse:IsPlaying(), "Repeated alerts invalidate old callbacks")
            db.alertAnimation="fade"; mail:ApplySettings(); assert(original.fadeIn:IsPlaying())
            db.alertAnimation="none"; mail:ApplySettings(); assert(not original.fadeIn:IsPlaying() and not original.pulse:IsPlaying())
            db.screenAlertEnabled=false; mail:ApplySettings(); assert(not original:IsShown())
            assert(db.alertAnimation=="none" and db.alertPosition=="BOTTOM" and db.alertScale==2)
            assert(sounds==1 and flashes==1)
        ''')
        lua.execute('C_AddOns={GetAddOnMetadata=function() return nil end}; ns.modules={MailAlert=ns.MailAlert}')
        lua.execute((ROOT / "Config_Data.lua").read_text(encoding="utf-8-sig"), "DDingUI_Toolkit", lua.globals().ns)
        lua.execute('''
            ns:InitConfigTree()
            local fields={}
            for _,setting in ipairs(ns.ConfigTree.panels.mailalert.settings) do
                if setting.key then fields[setting.key]=setting end
            end
            local style=fields["profile.MailAlert.alertStyle"]
            local motion=fields["profile.MailAlert.sealMotion"]
            local original=fields["profile.MailAlert.alertAnimation"]
            assert(style.refreshPanel and #style.options==2)
            assert(style.options[1].value=="FACTION" and style.options[2].value=="SEAL")
            assert(style.options[1].text==ns.L.MAILALERT_DESIGN_FACTION)
            ns:SetDBValue(style.key,"FACTION")
            assert(original.visible() and not motion.visible())
            ns.MailAlert:EnterEditPreview()
            ns:SetDBValue(style.key,"SEAL"); style.onChange("SEAL")
            assert(motion.visible() and not original.visible())
            assert(ns.MailAlert.sealVisual.frame:IsShown() and not ns.MailAlert.factionFrame:IsShown())
            ns:SetDBValue(motion.key,false); motion.onChange(false)
            assert(not ns.MailAlert.sealVisual.state)
            ns.MailAlert:ExitEditPreview()
            assert(not ns.MailAlert.alertFrame:IsShown())
        ''')

    image = Image.open(ROOT / "Media/MailAlertIcons.tga")
    assert image.mode == "RGBA" and image.size == (256, 128)
    assert image.convert("RGB").getextrema() == ((255, 255),) * 3
    alpha = image.getchannel("A")
    for left in (0, 128):
        tile = alpha.crop((left, 0, left + 128, 128))
        assert tile.getbbox() is not None
        assert tile.crop((0, 0, 128, 2)).getextrema() == (0, 0)
        assert tile.crop((0, 126, 128, 128)).getextrema() == (0, 0)
        assert tile.crop((0, 0, 2, 128)).getextrema() == (0, 0)
        assert tile.crop((126, 0, 128, 128)).getextrema() == (0, 0)
    config = (ROOT / "Config_Data.lua").read_text(encoding="utf-8-sig")
    assert 'key = "profile.MailAlert.alertStyle"' in config
    assert 'visible = ShowMailSealOptions' in config

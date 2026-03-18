import sys
import re

file_path = r'C:\Users\D2JK\바탕화면\cd\DDingUI_Super\DDingUI\Modules\ResourceBars\BuffTrackerBar.lua'
with open(file_path, 'r', encoding='utf-8') as f:
    content = f.read()

# For UpdateSingleTrackedBuffBar
def patch_bar_ring(content, fn_name, frame_var):
    pattern = r'(function ResourceBars:' + fn_name + r'\(.*?\).*?)(?=function ResourceBars:UpdateSingleTrackedBuff|$)'
    m = re.search(pattern, content, re.DOTALL)
    if not m: return content
    
    old_func = m.group(1)
    
    insert_glow = f"""
    -- [Phase 3] Alert Glow Override for {fn_name}
    if {frame_var}._alertGlowOverride then
        local glowSettings = {{
            color = {frame_var}._alertColorOverride or {{1, 0.9, 0.5, 1}},
            lines = 8,
            frequency = 0.25,
            thickness = 2,
            xOffset = 0,
            yOffset = 0,
        }}
        ApplyIconAnimation({frame_var}, "pixel", glowSettings)
    else
        StopAllAnimations({frame_var})
    end
    """
    
    # Inject right before the very end of the function or before bar:Show()
    # It usually ends with `end` of the function.
    if f'{frame_var}:Show()' in old_func:
        new_func = old_func.replace(f'{frame_var}:Show()', f'{frame_var}:Show()\n{insert_glow}')
    else:
        # Fallback: find last `end`
        parts = old_func.rsplit('end', 1)
        new_func = parts[0] + insert_glow + 'end' + parts[1]
        
    return content.replace(old_func, new_func)

content = patch_bar_ring(content, 'UpdateSingleTrackedBuffBar', 'bar')
content = patch_bar_ring(content, 'UpdateSingleTrackedBuffRing', 'bar') # Ring reuses bar frame

# For Icon and Text, they already have shouldGlow logic.
# Let's replace the 'shouldGlow = hasData or ...' with logic that also checks _alertGlowOverride

def patch_icon_text(content, fn_name, frame_var, anim_func="ApplyIconAnimation"):
    pattern = r'local shouldGlow\s*(.*?end).*?if shouldGlow then\s*'+anim_func+r'\(.*?glowSettings\)\s*else\s*StopAllAnimations\([^)]*\)\s*end'
    
    def replacer(m):
        old_block = m.group(0)
        # We rewrite the shouldGlow block to consider _alertGlowOverride
        return f"""local shouldGlow = false
    if {frame_var}._alertGlowOverride then
        shouldGlow = true
        glowSettings.color = {frame_var}._alertColorOverride or glowSettings.color
        iconAnimation = "pixel"
    else
        {m.group(1)}
    end

    if shouldGlow then
        {anim_func}({frame_var}, iconAnimation, glowSettings)
    else
        StopAllAnimations({frame_var})
    end"""
    
    # We must restrict search to the specific function to avoid bad replacements, but the regex above might be unique enough.
    # Actually, icon uses iconAnimation, text uses textAnimation.
    
    # For icon:
    if fn_name == 'UpdateSingleTrackedBuffIcon':
        ptn = r'local shouldGlow\s*if glowWhenInactive then.*?end\s*if shouldGlow then\s*ApplyIconAnimation\([^)]*\)\s*else\s*StopAllAnimations\([^)]*\)\s*end'
        
        replacement = f"""local shouldGlow = false
    if {frame_var}._alertGlowOverride then
        shouldGlow = true
        glowSettings.color = {frame_var}._alertColorOverride or glowSettings.color
        iconAnimation = "pixel"
    else
        if glowWhenInactive then
            shouldGlow = not hasData or (isInPreviewMode or isInMoverMode)
        else
            shouldGlow = hasData or ((isInPreviewMode or isInMoverMode) and not hasData)
        end
    end

    if shouldGlow then
        ApplyIconAnimation({frame_var}, iconAnimation, glowSettings)
    else
        StopAllAnimations({frame_var})
    end"""
        # We need to find this block inside UpdateSingleTrackedBuffIcon
        func_match = re.search(r'(function ResourceBars:'+fn_name+r'\(.*?\).*?)(?=function ResourceBars:UpdateSingleTrackedBuff|$)', content, re.DOTALL)
        if func_match:
            old_func = func_match.group(1)
            new_func = re.sub(ptn, replacement, old_func, flags=re.DOTALL)
            content = content.replace(old_func, new_func)
            
    # For text:
    if fn_name == 'UpdateSingleTrackedBuffText':
        ptn = r'local shouldGlow\s*if glowWhenInactive then.*?end\s*if shouldGlow then\s*ApplyTextAnimation\([^)]*\)\s*else\s*StopTextAnimations\([^)]*\)\s*end'
        
        replacement = f"""local shouldGlow = false
    if {frame_var}._alertGlowOverride then
        shouldGlow = true
        glowSettings.color = {frame_var}._alertColorOverride or glowSettings.color
        textAnimation = "pixel"
    else
        if glowWhenInactive then
            shouldGlow = not hasData or (isInPreviewMode or isInMoverMode)
        else
            shouldGlow = hasData or ((isInPreviewMode or isInMoverMode) and not hasData)
        end
    end

    if shouldGlow then
        ApplyTextAnimation({frame_var}, textAnimation, glowSettings)
    else
        StopTextAnimations({frame_var})
    end"""
        func_match = re.search(r'(function ResourceBars:'+fn_name+r'\(.*?\).*?)(?=function ResourceBars:UpdateSingleTrackedBuff|$)', content, re.DOTALL)
        if func_match:
            old_func = func_match.group(1)
            new_func = re.sub(ptn, replacement, old_func, flags=re.DOTALL)
            content = content.replace(old_func, new_func)

    return content

content = patch_icon_text(content, 'UpdateSingleTrackedBuffIcon', 'icon', 'ApplyIconAnimation')
content = patch_icon_text(content, 'UpdateSingleTrackedBuffText', 'textFrame', 'ApplyTextAnimation')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Applied Glow overrides successfully!")

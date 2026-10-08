# 미나즈키 v2 — 움직임과 타격감

사용자 피드백: 움직임과 타격감이 약함. 내장 image_gen으로 분출·반동·횡방향 흐름·배수를 새로 제작.
기존 작은 시작 원화 2개 + 새 준비 9개 + 분출 9개 + 후속 흐름 9개 + 배수 6개 = 35개 그림.
원화별 노출 길이를 달리해 24 FPS/88프레임/3.667초로 패킹. 1.75초에 분출 시작,1.875초 최대 높이. 3.64초 클린 음성 유지.
네 원본 시트는 실제1254×1254 RGBA. 3×3 시트에서 네이티브 픽셀을 정수 이동만으로 맞췄다. 확대·회전·모핑·보간 없음. 512px 셀 안 최대 약430px 실제 그림. 불균등 행/열 경계는 측정값으로 자르고, 배수 마지막 행 아래의 alpha2~6 잡점 9개를 셀 밖에 제외했다.
실제 TGA 디코딩 결과로 만든 `artifacts/DDingUI_FX/minazuki/Minazuki-preview-v2.webp`와 소리 포함 `.mp4`에서 확인 가능.

## 페이지 1
Use case: stylized-concept.
Asset type: a production sprite atlas for a punchier Minazuki Bankai liquid effect in an action RPG.
Input image 1 is the original anime reference for viscous crimson liquid, not an edit target. Input image 2 is the old VFX and is a COLOR/MATERIAL reference only. The user rejects its weak motion and impact. It rises like a quiet, symmetrical crown; replace that choreography.
Create exactly NINE consecutive animation cels in a strict 3-column by 3-row square grid, reading left-to-right, top-to-bottom. Real transparent RGBA. No background or painted checkerboard, no captions, labels or grid.
One continuous effect only, three-quarter elevated front viewpoint, camera locked. Dark burgundy thick liquid with vivid wet crimson edges, clean hand-drawn anime/action-RPG shading; NO metallic chrome, bright neon ring, fire, lightning, pink plasma or sparks. No characters, swords, wounds, gore or text.
All nine cels share the same coordinates and perspective: puddle bottom at 88% cell height, horizontal center 50%; full pool spans x5%..95%, shallow ellipse y69%..88%. Maximum plume extends to y7%. Negative center x37%..63% y20%..65% stays open for the game character. Show the same actual scale in every cell, margin 4% at cell borders. No whole-effect translation or resizing. Crisp substantial liquid ribbons, directional surface flow and tapered trajectories. The full pool is NOT an ornamental circular hoop: it has a filled translucent dark crimson body, broken asymmetric edges, visible forward-moving shallow liquid sheets and broad flow lines.
This atlas is phase 1 of 4, ANTICIPATION, frames 1 through 9. Intended screen time ~1.75 sec before the word Minazuki begins. Draw:
1: a small dark liquid trace on the ground;
2: trace spreads outward with a low forward ripple;
3: a wider shallow asymmetric puddle, wake curls right;
4: almost full footprint, thin back-left stream curls inward;
5: full pool, a low right stream counters inward;
6: dark fluid converges toward the center-rear, an S-shaped current visibly tightens;
7: two slim streams bend inward, low and under pressure;
8: surface dips in the middle, perimeter wave pulls inward, tense compressed posture;
9: sharp squat compression, two wet narrow fins angled inward, all mass poised to burst vertically next.
Keep the entire anticipation low, below y55%; do NOT erupt yet. Adjacent cels vary because liquid flows, not static copies. Use most of each cell's width once the pool forms. Draw large native details. Everything remains isolated, without any neighboring sprite overlap.

## 페이지 2
Use case: stylized-concept.
Asset type: a production sprite atlas for a punchier Minazuki Bankai liquid effect in an action RPG.
Input image 1 is the original anime reference for viscous crimson liquid, not an edit target. Input image 2 is phase 1 of this new animation: preserve its dark crimson material, fixed camera and low pool's scale. Continue its motion with much stronger acceleration and recoil.
Create exactly NINE consecutive animation cels in a strict 3-column by 3-row square grid, reading left-to-right, top-to-bottom. Real transparent RGBA. No background or painted checkerboard, no captions, labels or grid.
One continuous effect only, three-quarter elevated front viewpoint, camera locked. Dark burgundy thick liquid with vivid wet crimson edges, clean hand-drawn anime/action-RPG shading; NO metallic chrome, bright neon ring, fire, lightning, pink plasma or sparks. No characters, swords, wounds, gore or text.
All nine cels share the same coordinates and perspective: puddle bottom at 88% cell height, horizontal center 50%; full pool spans x14%..86%, shallow ellipse y69%..88%. Maximum plume extends to y12%. Negative center x37%..63% y20%..65% stays open for the game character. Show the same actual scale in every cell, margin AT LEAST 10% at every cell border. Nothing may touch cell boundaries; leave obvious transparent gutters. No whole-effect translation or resizing. Crisp substantial liquid ribbons, directional surface flow and tapered trajectories. The full pool is NOT an ornamental circular hoop: it has a filled translucent dark crimson body, broken asymmetric edges, visible forward-moving shallow liquid sheets and broad flow lines.
This atlas is phase 2 of 4, THE IMPACT, frames 10 through 18, screen time about 0.5 seconds. Do not merely raise a symmetrical crown. This is a physically forceful sudden liquid eruption with stretched animation silhouettes, followed by visible recoil:
1: low compressed mass like the final frame of input2, a broad bulge at rear left;
2: first narrow diagonal jet lashes upward right from the left rear, pool's front edge kicks outward;
3: the main mass suddenly SHOOTS into a tall asymmetrical fan of several heavy crimson liquid ribbons, low forward sheet surges toward the viewer;
4: MAXIMUM EXTENSION, tall broad rear curtains and two long tapered lateral whips, the low forward wave reaches maximum span. Show powerful straight flow lines;
5: upper ribbons OVERSHOOT and fold outward, falling large droplets trace the motion;
6: the left fan curls downward, the right jet swings through, counterflow twists across the rear;
7: stream lands heavily in the pool, low horizontal splash flares at the sides;
8: the counter-wave surges back, narrow back curtains still moving, fluid hangs in broad arcs;
9: force settles into broad moving rear curtains and a low deep pool, central empty vertical corridor remains open.
The motion must have different anticipation, stretched burst, overshoot and recoil silhouettes; no nine near-identical crowns. NO human figure or weapons. Exactly nine fully isolated cels, not a storyboard poster.

## 페이지 3
Use case: stylized-concept.
Asset type: a production sprite atlas for a punchier Minazuki Bankai liquid effect in an action RPG.
Input image 1 is the original anime reference for viscous crimson liquid, not an edit target. Input image 2 is phase 1 of this new animation: preserve its dark crimson material, fixed camera and low pool's scale. Continue its motion with much stronger acceleration and recoil.
Create exactly NINE consecutive animation cels in a strict 3-column by 3-row square grid, reading left-to-right, top-to-bottom. Real transparent RGBA. No background or painted checkerboard, no captions, labels or grid.
One continuous effect only, three-quarter elevated front viewpoint, camera locked. Dark burgundy thick liquid with vivid wet crimson edges, clean hand-drawn anime/action-RPG shading; NO metallic chrome, bright neon ring, fire, lightning, pink plasma or sparks. No characters, swords, wounds, gore or text.
All nine cels share the same coordinates and perspective: puddle bottom at 88% cell height, horizontal center 50%; full pool spans x14%..86%, shallow ellipse y69%..88%. Maximum plume extends to y12%. Negative center x37%..63% y20%..65% stays open for the game character. Show the same actual scale in every cell, margin AT LEAST 10% at every cell border. Nothing may touch cell boundaries; leave obvious transparent gutters. No whole-effect translation or resizing. Crisp substantial liquid ribbons, directional surface flow and tapered trajectories. The full pool is NOT an ornamental circular hoop: it has a filled translucent dark crimson body, broken asymmetric edges, visible forward-moving shallow liquid sheets and broad flow lines.
This atlas is phase 3 of 4, DRIVEN FLOW AND SECONDARY WHIP, frames 19 through 27, screen time about 0.875 seconds after the initial eruption. Full pool with moving rear crimson curtains. Draw a clear sweeping action instead of a static crown:
1: tall irregular rear liquid curtain, left folds toward right;
2: a wide dark ribbon sweeps clockwise across the BACK ARC only, leaving the central vertical opening clear;
3: ribbon lengthens and leans to the right, broad shallow pool flow streaks point outward;
4: the moving ribbon whips over at the right edge;
5: upper right stream folds forward and downward, a few heavy detached droplets trail it;
6: it strikes the right pool edge, sending a thin broad shallow splash outward;
7: a counterwave passes along the front edge toward the left;
8: tall back curtains shorten as mass pours downward;
9: curtains still visibly streaming at about half their maximum height, ready to drain.
Material dark burgundy, restrained wet crimson highlights. Fixed footprint and camera, substantial asymmetrical silhouettes with clear directional force. No ornamental hoop, no symmetric horns, no fire. Exactly nine isolated cels; generous transparent gutters. End with low flowing mass about half-height.

## 페이지 4
Use case: stylized-concept.
Asset type: a production sprite atlas for a punchier Minazuki Bankai liquid effect in an action RPG.
Input image 1 is the original anime reference for viscous crimson liquid, not an edit target. Input image 2 is phase 1 of this new animation: preserve its dark crimson material, fixed camera and low pool's scale. Continue its motion with much stronger acceleration and recoil.
Create exactly NINE consecutive animation cels in a strict 3-column by 3-row square grid, reading left-to-right, top-to-bottom. Real transparent RGBA. No background or painted checkerboard, no captions, labels or grid.
One continuous effect only, three-quarter elevated front viewpoint, camera locked. Dark burgundy thick liquid with vivid wet crimson edges, clean hand-drawn anime/action-RPG shading; NO metallic chrome, bright neon ring, fire, lightning, pink plasma or sparks. No characters, swords, wounds, gore or text.
All nine cels share the same coordinates and perspective: puddle bottom at 88% cell height, horizontal center 50%; full pool spans x14%..86%, shallow ellipse y69%..88%. Maximum plume extends to y12%. Negative center x37%..63% y20%..65% stays open for the game character. Show the same actual scale in every cell, margin AT LEAST 10% at every cell border. Nothing may touch cell boundaries; leave obvious transparent gutters. No whole-effect translation or resizing. Crisp substantial liquid ribbons, directional surface flow and tapered trajectories. The full pool is NOT an ornamental circular hoop: it has a filled translucent dark crimson body, broken asymmetric edges, visible forward-moving shallow liquid sheets and broad flow lines.
This atlas is phase 4 of 4, HEAVY DRAIN AND DISPERSAL, frames 28 through 36, screen time about 0.54 seconds. Start at half-height flowing rear curtains, then release:
1: half-height rear liquid sheets begin collapsing downward with strong vertical streaks;
2: one broader sheet lands in the ground pool, sends a low forward wave;
3: the second sheet lands, a fast shallow splash flows left and right;
4: only a low wide ripple and falling droplets remain;
5: the pool quickly tears into long thin streams flowing away from center;
6: sparse low liquid ribbons, large central ground opening;
7: only several receding droplets and two short trailing puddle streaks;
8: a handful of tiny fading dark-red droplets;
9: almost entirely transparent, a single tiny low red trace.
Everything keeps the SAME ground location and same per-cell scale, do not shrink the whole drawing. The disappearance happens by fluid motion and breakup. Never fill empty space with smoke, fog, sparks, magical symbols. Exactly nine isolated cels, even when almost empty.

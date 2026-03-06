# ElvUI Unitframe Database Structure

이 문서는 ElvUI의 SavedVariables에서 추출한 완전한 유닛프레임 구조입니다.
DDingUI Profile 임포터를 만들 때 참조용입니다.

## 1. Global Unitframe Settings (unitframe 테이블 직속)

```lua
unitframe = {
  targetOnMouseDown = boolean,
  fontSize = number,
  statusbar = string,  -- 텍스처 이름 (예: "Melli")
  smoothbars = boolean,

  debuffHighlight = {
    overlayAlpha = number,
    filterDispellable = boolean,
    showNonDispellable = boolean,
  },

  colors = {
    castColor = { r = number, g = number, b = number },
    auraBarBuff = { r = number, g = number, b = number },
    health = { r = number, g = number, b = number },
  },

  units = {
    -- 개별 유닛 설정들 (아래 참조)
    player = { ... },
    target = { ... },
    raid1 = { ... },
    raid2 = { ... },
    raid3 = { ... },
    party = { ... },
    boss = { ... },
    arena = { ... },
    focus = { ... },
    pet = { ... },
    targettarget = { ... },
    tank = { ... },
    assist = { ... },
  }
}
```

## 2. Player Unit 전체 구조

```lua
player = {
  -- 기본 크기
  width = number,
  height = number,

  -- 체력바
  health = {
    position = string,  -- "BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT", "CENTER" 등
    text_format = string,  -- "[health:current]", "[perhp]%" 등
    attachTextTo = string,  -- "InfoPanel", "Health", "Frame"
    xOffset = number,
    yOffset = number,
  },

  -- 자원바 (마나/분노/기력 등)
  power = {
    enable = boolean,
    text_format = string,
    attachTextTo = string,
    position = string,
    height = number,
    offset = number,
    xOffset = number,
    yOffset = number,
    detachFromFrame = boolean,  -- 분리된 자원바
    detachedWidth = number,
    width = string,  -- "spaced" 등
    hideonnpc = boolean,
  },

  -- 직업 자원바 (콤보포인트, 룬, 신성한 힘 등)
  classbar = {
    enable = boolean,
    detachFromFrame = boolean,
    height = number,
  },

  -- 캐스트바
  castbar = {
    enable = boolean,
    height = number,
    width = number,
    insideInfoPanel = boolean,
    icon = boolean,
    iconAttached = boolean,
  },

  -- 버프
  buffs = {
    enable = boolean,
    attachTo = string,  -- "FRAME", "BUFFS", "HEALTH" 등
    perrow = number,  -- 한 줄당 버프 개수
    numrows = number,  -- 줄 수
    sizeOverride = number,  -- 아이콘 크기 (픽셀)
    yOffset = number,
    xOffset = number,
    growthX = string,  -- "RIGHT", "LEFT"
    growthY = string,  -- "DOWN", "UP"
    spacing = number,  -- 아이콘 간격
    countPosition = string,  -- "TOP", "BOTTOM"
    countYOffset = number,
    countXOffset = number,
    countFont = string,
    countFontSize = number,
    priority = string,  -- "Blacklist,Personal,Boss,nonPersonal" 등
    strataAndLevel = {
      useCustomStrata = boolean,
      frameStrata = string,  -- "BACKGROUND", "LOW", "MEDIUM", "HIGH"
    },
    keepSizeRatio = boolean,
    height = number,
  },

  -- 디버프
  debuffs = {
    enable = boolean,
    attachTo = string,
    perrow = number,
    numrows = number,
    sizeOverride = number,
    yOffset = number,
    xOffset = number,
    growthX = string,
    anchorPoint = string,
    countPosition = string,
    countYOffset = number,
    countFont = string,
    priority = string,
  },

  -- 정보 패널
  infoPanel = {
    enable = boolean,
    height = number,
  },

  -- 치유 예측
  healPrediction = {
    enable = boolean,
    absorbStyle = string,  -- "NORMAL", "WRAPPED", "OVERFLOW"
  },

  -- 오라바
  aurabar = {
    enable = boolean,
  },

  -- 이름 텍스트
  name = {
    text_format = string,
    position = string,
    attachTextTo = string,
    xOffset = number,
    yOffset = number,
  },

  -- 초상화
  portrait = {
    enable = boolean,
    overlay = boolean,
    width = number,
    camDistanceScale = number,
  },

  -- 공격대 아이콘
  raidicon = {
    enable = boolean,
    attachTo = string,  -- "CENTER", "LEFT", "RIGHT", "TOPRIGHT"
    size = number,
    xOffset = number,
    yOffset = number,
  },

  -- 역할 아이콘 (탱/힐/딜)
  roleIcon = {
    enable = boolean,
    attachTo = string,
    size = number,
    xOffset = number,
    yOffset = number,
    damager = boolean,  -- 딜러 아이콘 표시 여부
  },

  -- 공격대 역할 아이콘 (리더/도우미)
  raidRoleIcons = {
    position = string,
    xOffset = number,
    yOffset = number,
  },

  -- 위협 수준 표시
  threatStyle = string,  -- "NONE", "GLOW", "BORDERS"
  threatPrimary = boolean,

  -- 색상 강제 적용
  colorOverride = string,  -- "FORCE_ON", "FORCE_OFF"

  -- 마우스오버 효과
  disableMouseoverGlow = boolean,
  disableTargetGlow = boolean,

  -- 커스텀 텍스트 (사용자 정의 텍스트 여러 개 가능)
  customTexts = {
    ["텍스트 이름"] = {
      attachTextTo = string,  -- "Health", "Frame", "Power"
      enable = boolean,
      text_format = string,  -- "[name]", "[health:current]", "[perhp]%" 등
      xOffset = number,
      yOffset = number,
      font = string,
      size = number,
      fontOutline = string,  -- "OUTLINE", "THICKOUTLINE", "MONOCHROME"
      justifyH = string,  -- "LEFT", "RIGHT", "CENTER"
    },
  },

  -- 프레임 방향
  orientation = string,  -- "LEFT", "MIDDLE", "RIGHT"
}
```

## 3. Target Unit

Target은 player와 거의 동일하지만 추가 옵션:

```lua
target = {
  -- player의 모든 필드 +
  orientation = string,  -- "LEFT", "MIDDLE", "RIGHT"

  auras = {
    enable = boolean,
  },
}
```

## 4. Raid Frames (raid1, raid2, raid3)

```lua
raid1 = {
  -- 활성화
  enable = boolean,

  -- 기본 크기
  width = number,
  height = number,

  -- 그룹 설정
  numGroups = number,  -- 보여줄 그룹 수 (1~8)
  growthDirection = string,  -- "LEFT_DOWN", "LEFT_UP", "RIGHT_DOWN", "RIGHT_UP"
  horizontalSpacing = number,  -- 가로 간격
  verticalSpacing = number,  -- 세로 간격
  sortDir = string,  -- "DESC", "ASC"
  groupBy = string,  -- "ROLE", "CLASS", "GROUP", "MTMA"

  -- 이름
  name = {
    text_format = string,
    position = string,
    attachTextTo = string,  -- "InfoPanel", "Health"
    xOffset = number,
    yOffset = number,
  },

  -- 체력
  health = {
    text_format = string,
    position = string,
    xOffset = number,
    yOffset = number,
  },

  -- 자원
  power = {
    enable = boolean,
    height = number,
    text_format = string,
    position = string,
  },

  -- 버프
  buffs = {
    enable = boolean,
    growthX = string,  -- "LEFT", "RIGHT"
    growthY = string,  -- "UP", "DOWN"
    xOffset = number,
    yOffset = number,
    anchorPoint = string,  -- "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"
    perrow = number,
    numrows = number,
    sizeOverride = number,
    countPosition = string,
    countYOffset = number,
    countXOffset = number,
    countFont = string,
    countFontSize = number,
    priority = string,
  },

  -- 디버프
  debuffs = {
    enable = boolean,
    growthX = string,
    xOffset = number,
    yOffset = number,
    anchorPoint = string,
    clickThrough = boolean,
    sizeOverride = number,
    countPosition = string,
    countYOffset = number,
    countXOffset = number,
    countFont = string,
    countFontSize = number,
    priority = string,
  },

  -- 공격대 디버프 (rdebuffs)
  rdebuffs = {
    enable = boolean,
    size = number,
    xOffset = number,
    yOffset = number,
    font = string,
    fontSize = number,
    stack = {
      color = { r = number, g = number, b = number },
      position = string,  -- "TOP", "BOTTOM", "LEFT", "RIGHT"
      xOffset = number,
      yOffset = number,
    },
  },

  -- 역할 아이콘
  roleIcon = {
    enable = boolean,
    attachTo = string,
    size = number,
    xOffset = number,
    yOffset = number,
    damager = boolean,
  },

  -- 공격대 아이콘
  raidicon = {
    enable = boolean,
    attachTo = string,
    size = number,
    xOffset = number,
    yOffset = number,
  },

  -- 부활 아이콘
  resurrectIcon = {
    enable = boolean,
    attachTo = string,
    size = number,
    xOffset = number,
    yOffset = number,
  },

  -- 정보 패널
  infoPanel = {
    enable = boolean,
    height = number,
  },

  -- 직업바
  classbar = {
    enable = boolean,
  },

  -- 기타
  threatStyle = string,
  disableTargetGlow = boolean,
  disableMouseoverGlow = boolean,
}
```

## 5. Party Unit

```lua
party = {
  -- raid와 유사하지만 추가:

  enable = boolean,
  width = number,
  height = number,

  -- 간격
  horizontalSpacing = number,
  verticalSpacing = number,

  -- 성장 방향
  growthDirection = string,  -- "RIGHT_DOWN", "RIGHT_UP", "LEFT_DOWN", "LEFT_UP"

  -- 그룹화
  groupBy = string,  -- "ROLE", "CLASS"

  -- 방향
  orientation = string,  -- "MIDDLE", "LEFT", "RIGHT"

  -- 펫 그룹
  petsGroup = {
    enable = boolean,
    xOffset = number,
    yOffset = number,
    disableMouseoverGlow = boolean,
  },

  -- 대상 그룹
  targetsGroup = {
    enable = boolean,
    xOffset = number,
    yOffset = number,
    disableMouseoverGlow = boolean,
  },

  -- 버프 표시기
  buffIndicator = {
    enable = boolean,
    size = number,
  },

  -- 준비 확인 아이콘
  readycheckIcon = {
    enable = boolean,
    size = number,
    xOffset = number,
    yOffset = number,
  },

  -- 나머지는 raid와 동일
  health = { ... },
  power = { ... },
  buffs = { ... },
  debuffs = { ... },
  rdebuffs = { ... },
  roleIcon = { ... },
  raidicon = { ... },
  raidRoleIcons = { ... },
  name = { ... },
  infoPanel = { ... },
  classbar = { ... },
  threatStyle = string,
  threatPrimary = boolean,
  disableMouseoverGlow = boolean,
  disableTargetGlow = boolean,
}
```

## 6. Boss Unit

```lua
boss = {
  enable = boolean,
  width = number,
  height = number,

  -- 성장 방향
  growthDirection = string,  -- "UP", "DOWN"
  spacing = number,  -- 보스 프레임 간 간격

  -- 이름
  name = {
    text_format = string,
    position = string,
    xOffset = number,
    yOffset = number,
  },

  -- 체력
  health = {
    text_format = string,
    position = string,
    xOffset = number,
    yOffset = number,
  },

  -- 자원
  power = {
    enable = boolean,
    text_format = string,
    position = string,
    height = number,
    xOffset = number,
  },

  -- 캐스트바
  castbar = {
    enable = boolean,
    height = number,
    width = number,
  },

  -- 버프
  buffs = {
    enable = boolean,
    sizeOverride = number,
    maxDuration = number,  -- 최대 지속시간 (초)
    xOffset = number,
    yOffset = number,
    anchorPoint = string,
    perrow = number,
    countPosition = string,
    countYOffset = number,
    countXOffset = number,
    countFont = string,
    priority = string,
  },

  -- 디버프
  debuffs = {
    enable = boolean,
    sizeOverride = number,
    maxDuration = number,
    xOffset = number,
    yOffset = number,
    anchorPoint = string,
    perrow = number,
    countPosition = string,
    countYOffset = number,
    countFont = string,
  },

  -- 정보 패널
  infoPanel = {
    enable = boolean,
    height = number,
  },

  -- 커스텀 텍스트
  customTexts = {
    ["이름"] = {
      attachTextTo = string,
      enable = boolean,
      text_format = string,
      xOffset = number,
      yOffset = number,
      font = string,
      size = number,
      fontOutline = string,
      justifyH = string,
    },
  },

  disableMouseoverGlow = boolean,
  disableTargetGlow = boolean,
}
```

## 7. Arena Unit

```lua
arena = {
  enable = boolean,
  width = number,
  height = number,

  -- 성장
  growthDirection = string,  -- "UP", "DOWN"
  spacing = number,

  -- 이름
  name = {
    text_format = string,  -- "[name:veryshort]", "[name:short]" 등
    position = string,
    xOffset = number,
    yOffset = number,
  },

  -- 체력
  health = {
    text_format = string,
    xOffset = number,
    yOffset = number,
  },

  -- 자원
  power = {
    enable = boolean,
    text_format = string,
    height = number,
    xOffset = number,
  },

  -- 디버프
  debuffs = {
    enable = boolean,
    sizeOverride = number,
    maxDuration = number,  -- 0 = 모든 디버프 표시
    xOffset = number,
    yOffset = number,
    anchorPoint = string,
    perrow = number,
  },

  -- 초상화
  portrait = {
    enable = boolean,
    width = number,
    camDistanceScale = number,
  },

  -- 정보 패널
  infoPanel = {
    enable = boolean,
    height = number,
  },

  disableMouseoverGlow = boolean,
  disableTargetGlow = boolean,
}
```

## 8. Focus Unit

```lua
focus = {
  enable = boolean,
  width = number,
  height = number,

  -- 이름
  name = {
    text_format = string,
    position = string,
    xOffset = number,
    yOffset = number,
  },

  -- 자원
  power = {
    enable = boolean,
    height = number,
  },

  -- 캐스트바
  castbar = {
    enable = boolean,
    height = number,
    width = number,
  },

  -- 디버프
  debuffs = {
    enable = boolean,
    anchorPoint = string,
  },

  -- 공격대 아이콘
  raidicon = {
    enable = boolean,
  },

  -- 치유 예측
  healPrediction = {
    enable = boolean,
  },

  colorOverride = string,
  threatStyle = string,
  disableTargetGlow = boolean,
}
```

## 9. Pet Unit

```lua
pet = {
  enable = boolean,
  width = number,
  height = number,

  -- 이름
  name = {
    text_format = string,  -- "[name:short:translit]" 등
    xOffset = number,
    yOffset = number,
  },

  -- 자원
  power = {
    enable = boolean,
    height = number,
  },

  -- 캐스트바
  castbar = {
    enable = boolean,
    height = number,
    width = number,
    iconSize = number,
  },

  -- 버프
  buffs = {
    enable = boolean,
    sizeOverride = number,
    priority = string,
  },

  -- 디버프
  debuffs = {
    enable = boolean,
    sizeOverride = number,
    xOffset = number,
    yOffset = number,
    anchorPoint = string,
    perrow = number,
    priority = string,
  },

  -- 정보 패널
  infoPanel = {
    enable = boolean,
    height = number,
  },

  -- 치유 예측
  healPrediction = {
    enable = boolean,
  },

  threatStyle = string,
  disableTargetGlow = boolean,
}
```

## 10. TargetTarget Unit

```lua
targettarget = {
  enable = boolean,
  width = number,
  height = number,

  -- 이름
  name = {
    text_format = string,
    position = string,
    xOffset = number,
    yOffset = number,
  },

  -- 자원
  power = {
    enable = boolean,
    height = number,
  },

  -- 디버프
  debuffs = {
    enable = boolean,
  },

  -- 공격대 아이콘
  raidicon = {
    enable = boolean,
    attachTo = string,
    xOffset = number,
    yOffset = number,
  },

  threatStyle = string,
  colorOverride = string,
  disableMouseoverGlow = boolean,
}
```

## 11. Tank / Assist Units

```lua
tank = {
  enable = boolean,
  -- 기본적으로 raid와 유사한 구조
}

assist = {
  enable = boolean,
  -- 기본적으로 raid와 유사한 구조
}
```

## 주요 Text Format 태그들

ElvUI에서 사용하는 태그 예시:

### 이름 관련
- `[name]` - 유닛 이름
- `[name:short]` - 짧은 이름 (15자)
- `[name:medium]` - 중간 이름 (10자)
- `[name:veryshort]` - 매우 짧은 이름 (5자)
- `[name:translit]` - 음역된 이름

### 체력 관련
- `[health:current]` - 현재 체력 (숫자)
- `[health:current:shortvalue]` - 현재 체력 (K, M 축약)
- `[health:max]` - 최대 체력
- `[health:deficit]` - 부족한 체력
- `[perhp]` - 체력 퍼센트 (숫자만)
- `[absorbs]` - 피해 흡수량

### 자원 관련
- `[power:current]` - 현재 자원
- `[power:current:shortvalue]` - 현재 자원 (축약)
- `[power:max]` - 최대 자원
- `[power:deficit]` - 부족한 자원
- `[perpp]` - 자원 퍼센트
- `[powercolor]` - 자원 색상 태그

### 기타
- `[classificaion]` - 분류 (정예, 희귀 등)
- `[level]` - 레벨
- `[threat]` - 위협 수준
- `[guild]` - 길드명
- `[race]` - 종족
- `[class]` - 직업

## Priority 문자열

버프/디버프 우선순위 (쉼표로 구분):

- `Blacklist` - 블랙리스트 (숨김)
- `Personal` - 내가 시전한 것
- `Boss` - 보스가 시전한 것
- `CastByNPC` - NPC가 시전한 것
- `TurtleBuffs` - 방어 버프 (생존기)
- `RaidDebuffs` - 공격대 디버프
- `Whitelist` - 화이트리스트
- `nonPersonal` - 다른 사람이 시전한 것

예: `"Blacklist,Personal,Boss,nonPersonal"`

## GrowthDirection 옵션

- `LEFT_DOWN` - 왼쪽으로, 아래로
- `LEFT_UP` - 왼쪽으로, 위로
- `RIGHT_DOWN` - 오른쪽으로, 아래로
- `RIGHT_UP` - 오른쪽으로, 위로
- `UP` - 위로
- `DOWN` - 아래로

## 사용 예시

DDingUI_Profile의 ImportAddon.lua에서 이 구조를 참조하여:

```lua
-- ElvUI → DDingUI_UF 매핑 예시
local function ConvertElvUIUnit(elvUnit)
  return {
    width = elvUnit.width,
    height = elvUnit.height,
    health = {
      text = elvUnit.health.text_format,
      position = elvUnit.health.position,
    },
    power = {
      enable = elvUnit.power.enable,
      height = elvUnit.power.height,
    },
    -- ... 나머지 필드들
  }
end
```

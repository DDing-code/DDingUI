local _, ns = ...

local spikes = {
    { t = 12,  amplitude = 38000000, width = 0.9, label = "균열 파동",       icon = 136048, phase = 1, affectedPlayers = 20 },
    { t = 28,  amplitude = 24000000, width = 1.5, label = "불안정한 폭발",   icon = 135826, phase = 1, affectedPlayers = 10 },
    { t = 46,  amplitude = 52000000, width = 1.0, label = "암흑 붕괴",       icon = 136197, phase = 2, affectedPlayers = 20 },
    { t = 62,  amplitude = 30000000, width = 1.2, label = "공명 충격",       icon = 136116, phase = 2, affectedPlayers = 14 },
    { t = 78,  amplitude = 61000000, width = 0.8, label = "파멸의 메아리",   icon = 136214, phase = 2, affectedPlayers = 20 },
    { t = 94,  amplitude = 46000000, width = 1.1, label = "별의 분출",       icon = 135753, phase = 3, affectedPlayers = 20 },
    { t = 111, amplitude = 34000000, width = 1.4, label = "연쇄 파열",       icon = 136205, phase = 3, affectedPlayers = 12 },
    { t = 126, amplitude = 68000000, width = 0.9, label = "최후의 붕괴",     icon = 136201, phase = 3, affectedPlayers = 20 },
}

local interval = 0.5
local duration = 135
local values = {}
local maximum = 1

for index = 0, math.floor(duration / interval) do
    local t = index * interval
    local value = 2800000 + 900000 * (0.5 + 0.5 * math.sin(t * 0.43))
    for _, spike in ipairs(spikes) do
        local delta = t - spike.t
        value = value + spike.amplitude * math.exp(-(delta * delta) / (2 * spike.width * spike.width))
    end
    value = math.floor(value + 0.5)
    values[#values + 1] = value
    maximum = math.max(maximum, value)
end

local mechanics = {}
for index, spike in ipairs(spikes) do
    mechanics[index] = {
        id = "demo_mechanic_" .. index,
        t = spike.t,
        label = spike.label,
        icon = spike.icon,
        phase = spike.phase,
        avgDamage = math.floor(spike.amplitude),
        affectedPlayers = spike.affectedPlayers,
        severity = spike.amplitude / 68000000,
    }
end

ns.Registry:Register("demo", {
    encounterID = 0,
    difficultyID = 0,
    name = "RaidHelper 실시간 미리보기",
    duration = duration,
    dataStatus = "demo",
    sampleCount = 10,
    generatedAt = "preview",
    phases = {
        { index = 1, stage = 1, t = 0,  label = "P1" },
        { index = 2, stage = 2, t = 44, label = "P2" },
        { index = 3, stage = 3, t = 88, label = "P3" },
    },
    damage = {
        interval = interval,
        values = values,
        max = maximum,
        metric = "raidDamageTaken",
    },
    mechanics = mechanics,
    cooldowns = {
        { id = "demo_cd_1", t = 10.0,  spellID = 64843,  label = "천상의 찬가", usage = 0.74, spread = 2.1, phase = 1 },
        { id = "demo_cd_2", t = 26.5,  spellID = 98008,  label = "정신의 고리 토템", usage = 0.68, spread = 1.8, phase = 1 },
        { id = "demo_cd_3", t = 44.5,  spellID = 31821,  label = "오라 숙련", usage = 0.81, spread = 2.4, phase = 2 },
        { id = "demo_cd_4", t = 60.5,  spellID = 115310, label = "재활", usage = 0.62, spread = 2.7, phase = 2 },
        { id = "demo_cd_5", t = 76.5,  spellID = 740,    label = "평온", usage = 0.77, spread = 2.0, phase = 2 },
        { id = "demo_cd_6", t = 92.0,  spellID = 62618,  label = "신의 권능: 방벽", usage = 0.71, spread = 2.5, phase = 3 },
        { id = "demo_cd_7", t = 109.0, spellID = 64843,  label = "천상의 찬가", usage = 0.58, spread = 3.1, phase = 3 },
        { id = "demo_cd_8", t = 124.0, spellID = 98008,  label = "정신의 고리 토템", usage = 0.84, spread = 1.6, phase = 3 },
    },
})

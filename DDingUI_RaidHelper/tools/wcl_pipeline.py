"""Pure aggregation helpers for DDingUI RaidHelper's Warcraft Logs data pack."""

from __future__ import annotations

import bisect
import math
import statistics
from collections import Counter, defaultdict
from datetime import datetime, timezone
from functools import lru_cache
from typing import Any, Iterable


INTERVAL_MS = 500
MECHANIC_HIT_WINDOW_MS = 1200
MECHANIC_ALIGNMENT_TOLERANCE_MS = 4000
COOLDOWN_ALIGNMENT_TOLERANCE_MS = 12000
BOSS_CAST_LOOKBACK_MS = 12000
VALIDATION_MECHANIC_MATCH_TOLERANCE_MS = 8000
VALIDATION_DAMAGE_PEAK_MATCH_TOLERANCE_MS = 5000
VALIDATION_MAX_MECHANIC_MEDIAN_ERROR_SECONDS = 3.0
VALIDATION_MAX_MECHANIC_P90_ERROR_SECONDS = 7.0
VALIDATION_MAX_DAMAGE_PEAK_MEDIAN_ERROR_SECONDS = 4.0
VALIDATION_MIN_PHASE_COVERAGE = 0.80
VALIDATION_MIN_MECHANIC_COVERAGE = 0.35
VALIDATION_MIN_DAMAGE_PEAK_COVERAGE = 0.30
VALIDATION_MIN_DAMAGE_CURVE_SIMILARITY = 0.60

WCL_TO_WOW_DIFFICULTY = {
    1: 17,  # LFR
    3: 14,  # Normal
    4: 15,  # Heroic
    5: 16,  # Mythic
}

HEALER_SPECS: tuple[dict[str, Any], ...] = (
    {"spec_id": 65, "class_name": "Paladin", "spec_name": "Holy"},
    {"spec_id": 105, "class_name": "Druid", "spec_name": "Restoration"},
    {"spec_id": 256, "class_name": "Priest", "spec_name": "Discipline"},
    {"spec_id": 257, "class_name": "Priest", "spec_name": "Holy"},
    {"spec_id": 264, "class_name": "Shaman", "spec_name": "Restoration"},
    {"spec_id": 270, "class_name": "Monk", "spec_name": "Mistweaver"},
    {"spec_id": 1468, "class_name": "Evoker", "spec_name": "Preservation"},
)

DPS_SPECS: tuple[dict[str, Any], ...] = (
    {"spec_id": 251, "class_name": "DeathKnight", "spec_name": "Frost"},
    {"spec_id": 252, "class_name": "DeathKnight", "spec_name": "Unholy"},
    {"spec_id": 577, "class_name": "DemonHunter", "spec_name": "Havoc"},
    {"spec_id": 1480, "class_name": "DemonHunter", "spec_name": "Devourer"},
    {"spec_id": 102, "class_name": "Druid", "spec_name": "Balance"},
    {"spec_id": 103, "class_name": "Druid", "spec_name": "Feral"},
    {"spec_id": 1467, "class_name": "Evoker", "spec_name": "Devastation"},
    {"spec_id": 1473, "class_name": "Evoker", "spec_name": "Augmentation"},
    {"spec_id": 253, "class_name": "Hunter", "spec_name": "BeastMastery"},
    {"spec_id": 254, "class_name": "Hunter", "spec_name": "Marksmanship"},
    {"spec_id": 255, "class_name": "Hunter", "spec_name": "Survival"},
    {"spec_id": 62, "class_name": "Mage", "spec_name": "Arcane"},
    {"spec_id": 63, "class_name": "Mage", "spec_name": "Fire"},
    {"spec_id": 64, "class_name": "Mage", "spec_name": "Frost"},
    {"spec_id": 269, "class_name": "Monk", "spec_name": "Windwalker"},
    {"spec_id": 70, "class_name": "Paladin", "spec_name": "Retribution"},
    {"spec_id": 258, "class_name": "Priest", "spec_name": "Shadow"},
    {"spec_id": 259, "class_name": "Rogue", "spec_name": "Assassination"},
    {"spec_id": 260, "class_name": "Rogue", "spec_name": "Outlaw"},
    {"spec_id": 261, "class_name": "Rogue", "spec_name": "Subtlety"},
    {"spec_id": 262, "class_name": "Shaman", "spec_name": "Elemental"},
    {"spec_id": 263, "class_name": "Shaman", "spec_name": "Enhancement"},
    {"spec_id": 265, "class_name": "Warlock", "spec_name": "Affliction"},
    {"spec_id": 266, "class_name": "Warlock", "spec_name": "Demonology"},
    {"spec_id": 267, "class_name": "Warlock", "spec_name": "Destruction"},
    {"spec_id": 71, "class_name": "Warrior", "spec_name": "Arms"},
    {"spec_id": 72, "class_name": "Warrior", "spec_name": "Fury"},
)

# Spell IDs are checked against public WCL casts; absent talents yield no marker.
# Labels are fallbacks because the report ability table supplies the actual name.
DPS_COOLDOWNS_BY_SPEC: dict[int, dict[int, dict[str, Any]]] = {
    251: {51271: {"label": "Pillar of Frost", "category": "major", "default_shown": True}, 47568: {"label": "Empower Rune Weapon", "category": "semi", "default_shown": True}},
    252: {42650: {"label": "Army of the Dead", "category": "major", "default_shown": True}, 63560: {"label": "Dark Transformation", "category": "semi", "default_shown": True}},
    577: {191427: {"label": "Metamorphosis", "category": "major", "default_shown": True}, 198013: {"label": "Eye Beam", "category": "semi", "default_shown": True}},
    1480: {1226019: {"label": "Reap", "category": "major", "default_shown": True}, 1221150: {"label": "Collapsing Star", "category": "semi", "default_shown": False}},
    102: {102560: {"label": "Incarnation: Chosen of Elune", "category": "major", "default_shown": True}, 205636: {"label": "Force of Nature", "category": "semi", "default_shown": True}},
    103: {106951: {"label": "Berserk", "category": "major", "default_shown": True}, 391528: {"label": "Convoke the Spirits", "category": "semi", "default_shown": True}},
    1467: {375087: {"label": "Dragonrage", "category": "major", "default_shown": True}, 357210: {"label": "Deep Breath", "category": "semi", "default_shown": True}},
    1473: {403631: {"label": "Breath of Eons", "category": "major", "default_shown": True}, 395152: {"label": "Ebon Might", "category": "semi", "default_shown": True}},
    253: {19574: {"label": "Bestial Wrath", "category": "major", "default_shown": True}},
    254: {288613: {"label": "Trueshot", "category": "major", "default_shown": True}, 260243: {"label": "Volley", "category": "semi", "default_shown": True}},
    255: {1253859: {"label": "Takedown", "category": "major", "default_shown": True}, 1264949: {"label": "Moonlight Chakram", "category": "semi", "default_shown": True}},
    62: {365350: {"label": "Arcane Surge", "category": "major", "default_shown": True}, 321507: {"label": "Touch of the Magi", "category": "semi", "default_shown": True}},
    63: {190319: {"label": "Combustion", "category": "major", "default_shown": True}, 153561: {"label": "Meteor", "category": "semi", "default_shown": True}},
    64: {84714: {"label": "Frozen Orb", "category": "semi", "default_shown": True}},
    269: {123904: {"label": "Invoke Xuen", "category": "major", "default_shown": True}},
    70: {31884: {"label": "Avenging Wrath", "category": "major", "default_shown": True}, 255937: {"label": "Wake of Ashes", "category": "semi", "default_shown": True}},
    258: {228260: {"label": "Void Eruption", "category": "major", "default_shown": True}, 10060: {"label": "Power Infusion", "category": "semi", "default_shown": True}},
    259: {360194: {"label": "Deathmark", "category": "major", "default_shown": True}, 385627: {"label": "Kingsbane", "category": "semi", "default_shown": True}},
    260: {13750: {"label": "Adrenaline Rush", "category": "major", "default_shown": True}, 51690: {"label": "Killing Spree", "category": "semi", "default_shown": True}},
    261: {185313: {"label": "Shadow Dance", "category": "major", "default_shown": True}, 280719: {"label": "Secret Technique", "category": "semi", "default_shown": True}},
    262: {114050: {"label": "Ascendance", "category": "major", "default_shown": True}, 191634: {"label": "Stormkeeper", "category": "semi", "default_shown": True}},
    263: {114051: {"label": "Ascendance", "category": "major", "default_shown": True}},
    265: {205180: {"label": "Summon Darkglare", "category": "major", "default_shown": True}},
    266: {265187: {"label": "Summon Demonic Tyrant", "category": "major", "default_shown": True}},
    267: {1122: {"label": "Summon Infernal", "category": "major", "default_shown": True}},
    71: {107574: {"label": "Avatar", "category": "major", "default_shown": True}},
    72: {1719: {"label": "Recklessness", "category": "major", "default_shown": True}, 385059: {"label": "Odyn's Fury", "category": "semi", "default_shown": True}},
}

# Additional 12.1 skills are taken from the curated specialization/class KB.
# Talent alternatives stay selectable; the WCL cast filter creates timeline
# markers only for spells actually used by the sampled players.
DPS_EXTRA_COOLDOWNS_BY_SPEC: dict[int, dict[int, tuple[str, str]]] = {
    251: {279302: ("Frostwyrm's Fury", "major"), 1249658: ("Breath of Sindragosa", "major"), 48707: ("Anti-Magic Shell", "personal"), 51052: ("Anti-Magic Zone", "external")},
    252: {1233448: ("Dark Transformation", "major"), 1247378: ("Putrefy", "semi"), 48707: ("Anti-Magic Shell", "personal"), 51052: ("Anti-Magic Zone", "external")},
    577: {258860: ("Essence Break", "semi"), 370965: ("The Hunt", "semi"), 212800: ("Blur", "personal"), 196718: ("Darkness", "external")},
    1480: {1245412: ("Voidblade", "semi"), 1234195: ("Void Nova", "semi"), 1241937: ("Soul Immolation", "major"), 1246167: ("The Hunt", "semi"), 212800: ("Blur", "personal"), 196718: ("Darkness", "external")},
    102: {202770: ("Fury of Elune", "semi"), 194223: ("Celestial Alignment", "major"), 22812: ("Barkskin", "personal"), 106898: ("Stampeding Roar", "personal")},
    103: {274837: ("Feral Frenzy", "semi"), 102543: ("Incarnation: Avatar of Ashamane", "major"), 22812: ("Barkskin", "personal"), 106898: ("Stampeding Roar", "personal")},
    1467: {359073: ("Eternity Surge", "semi"), 370553: ("Tip the Scales", "semi"), 363916: ("Obsidian Scales", "personal"), 374227: ("Zephyr", "external")},
    1473: {396286: ("Upheaval", "semi"), 404977: ("Time Skip", "semi"), 363916: ("Obsidian Scales", "personal"), 374227: ("Zephyr", "external")},
    253: {264735: ("Survival of the Fittest", "personal"), 186265: ("Aspect of the Turtle", "personal"), 109304: ("Exhilaration", "personal"), 34477: ("Misdirection", "external")},
    254: {212431: ("Explosive Shot", "semi"), 264735: ("Survival of the Fittest", "personal"), 186265: ("Aspect of the Turtle", "personal")},
    255: {1261193: ("Boomstick", "semi"), 186289: ("Aspect of the Eagle", "semi"), 264735: ("Survival of the Fittest", "personal"), 186265: ("Aspect of the Turtle", "personal")},
    62: {12051: ("Evocation", "semi"), 205025: ("Presence of Mind", "semi"), 45438: ("Ice Block", "personal"), 342245: ("Alter Time", "personal")},
    63: {45438: ("Ice Block", "personal"), 342245: ("Alter Time", "personal"), 55342: ("Mirror Image", "personal")},
    64: {205021: ("Ray of Frost", "semi"), 45438: ("Ice Block", "personal"), 342245: ("Alter Time", "personal"), 235219: ("Cold Snap", "personal")},
    269: {392983: ("Strike of the Windlord", "semi"), 1249625: ("Zenith", "major"), 1217413: ("Slicing Winds", "semi"), 443028: ("Celestial Conduit", "major"), 115203: ("Fortifying Brew", "personal")},
    70: {343527: ("Execution Sentence", "semi"), 403876: ("Divine Protection", "personal"), 642: ("Divine Shield", "personal"), 6940: ("Blessing of Sacrifice", "external")},
    258: {263165: ("Void Torrent", "semi"), 47585: ("Dispersion", "personal"), 19236: ("Desperate Prayer", "personal")},
    259: {31224: ("Cloak of Shadows", "personal"), 5277: ("Evasion", "personal"), 381623: ("Thistle Tea", "semi")},
    260: {315508: ("Roll the Bones", "semi"), 271877: ("Blade Rush", "semi"), 381989: ("Keep It Rolling", "semi"), 31224: ("Cloak of Shadows", "personal"), 5277: ("Evasion", "personal")},
    261: {121471: ("Shadow Blades", "major"), 426591: ("Goremaw", "semi"), 31224: ("Cloak of Shadows", "personal"), 5277: ("Evasion", "personal")},
    262: {198067: ("Fire Elemental", "major"), 192249: ("Storm Elemental", "major"), 108271: ("Astral Shift", "personal"), 192077: ("Wind Rush Totem", "personal")},
    263: {197214: ("Sundering", "semi"), 384352: ("Doom Winds", "semi"), 108271: ("Astral Shift", "personal"), 192077: ("Wind Rush Totem", "personal")},
    265: {1257052: ("Dark Harvest", "major"), 104773: ("Unending Resolve", "personal"), 108416: ("Dark Pact", "personal"), 48020: ("Demonic Circle: Teleport", "personal")},
    266: {1276672: ("Summon Doomguard", "major"), 1276452: ("Grimoire: Imp Lord", "major"), 1276467: ("Grimoire: Fel Ravager", "major"), 104773: ("Unending Resolve", "personal"), 108416: ("Dark Pact", "personal")},
    267: {152108: ("Cataclysm", "semi"), 80240: ("Havoc", "semi"), 104773: ("Unending Resolve", "personal"), 108416: ("Dark Pact", "personal")},
    71: {167105: ("Colossus Smash", "semi"), 227847: ("Bladestorm", "semi"), 97462: ("Rallying Cry", "external"), 118038: ("Die by the Sword", "personal")},
    72: {228920: ("Ravager", "semi"), 227847: ("Bladestorm", "semi"), 97462: ("Rallying Cry", "external"), 184364: ("Enraged Regeneration", "personal")},
}
for _spec_id, _spells in DPS_EXTRA_COOLDOWNS_BY_SPEC.items():
    DPS_COOLDOWNS_BY_SPEC[_spec_id].update({
        spell_id: {
            "label": label, "category": category,
            "default_shown": category in {"major", "semi"},
        }
        for spell_id, (label, category) in _spells.items()
    })

# Lorrgs-style healer spell selection, extended with the existing RaidHelper
# planning cooldowns. The WCL ability table supplies localized/current names;
# these labels are safe fallbacks. Semi cooldowns are collected as first-class
# data so spells such as Holy Priest Halo are not silently discarded.
HEALER_COOLDOWNS_BY_SPEC: dict[int, dict[int, dict[str, Any]]] = {
    65: {
        31821: {"label": "Aura Mastery", "category": "major", "default_shown": True},
        31884: {"label": "Avenging Wrath", "category": "major", "default_shown": True},
        375576: {"label": "Divine Toll", "category": "semi", "default_shown": True},
        200025: {"label": "Beacon of Virtue", "category": "semi", "default_shown": True},
        6940: {"label": "Blessing of Sacrifice", "category": "external", "default_shown": False},
        1022: {"label": "Blessing of Protection", "category": "external", "default_shown": False},
        498: {"label": "Divine Protection", "category": "personal", "default_shown": False},
        642: {"label": "Divine Shield", "category": "personal", "default_shown": False},
    },
    105: {
        740: {"label": "Tranquility", "category": "major", "default_shown": True},
        33891: {"label": "Incarnation: Tree of Life", "category": "major", "default_shown": True},
        197721: {"label": "Flourish", "category": "major", "default_shown": True},
        391528: {"label": "Convoke the Spirits", "category": "semi", "default_shown": True},
        102342: {"label": "Ironbark", "category": "external", "default_shown": False},
        5487: {"label": "Bear Form", "category": "personal", "default_shown": False},
        22812: {"label": "Barkskin", "category": "personal", "default_shown": False},
        106898: {"label": "Stampeding Roar", "category": "personal", "default_shown": False},
    },
    256: {
        62618: {"label": "Power Word: Barrier", "category": "major", "default_shown": True},
        421453: {"label": "Ultimate Penitence", "category": "major", "default_shown": True},
        472433: {"label": "Voidwraith", "category": "major", "default_shown": True},
        246287: {"label": "Evangelism", "category": "semi", "default_shown": True},
        194509: {"label": "Power Word: Radiance", "category": "semi", "default_shown": True},
        33206: {"label": "Pain Suppression", "category": "external", "default_shown": False},
        586: {"label": "Fade", "category": "personal", "default_shown": False},
        19236: {"label": "Desperate Prayer", "category": "personal", "default_shown": False},
        73325: {"label": "Leap of Faith", "category": "personal", "default_shown": False},
    },
    257: {
        64843: {"label": "Divine Hymn", "category": "major", "default_shown": True},
        64901: {"label": "Symbol of Hope", "category": "major", "default_shown": True},
        265202: {"label": "Holy Word: Salvation", "category": "major", "default_shown": True},
        120517: {"label": "Halo", "category": "semi", "default_shown": True},
        200183: {"label": "Apotheosis", "category": "semi", "default_shown": True},
        47788: {"label": "Guardian Spirit", "category": "external", "default_shown": False},
        586: {"label": "Fade", "category": "personal", "default_shown": False},
        19236: {"label": "Desperate Prayer", "category": "personal", "default_shown": False},
        73325: {"label": "Leap of Faith", "category": "personal", "default_shown": False},
        27827: {"label": "Spirit of Redemption", "category": "personal", "default_shown": False},
    },
    264: {
        98008: {"label": "Spirit Link Totem", "category": "major", "default_shown": True},
        108280: {"label": "Healing Tide Totem", "category": "major", "default_shown": True},
        114052: {"label": "Ascendance", "category": "major", "default_shown": True},
        378270: {"label": "Totemic Recall", "category": "semi", "default_shown": True},
        79206: {"label": "Spiritwalker's Grace", "category": "personal", "default_shown": False},
        108271: {"label": "Astral Shift", "category": "personal", "default_shown": False},
        192077: {"label": "Wind Rush Totem", "category": "personal", "default_shown": False},
        381755: {"label": "Earthliving Weapon", "category": "personal", "default_shown": False},
    },
    270: {
        115310: {"label": "Revival", "category": "major", "default_shown": True},
        388615: {"label": "Restoral", "category": "major", "default_shown": True},
        322118: {"label": "Invoke Yu'lon", "category": "major", "default_shown": True},
        325197: {"label": "Invoke Chi-Ji", "category": "major", "default_shown": True},
        443028: {"label": "Celestial Conduit", "category": "major", "default_shown": True},
        116680: {"label": "Thunder Focus Tea", "category": "semi", "default_shown": True},
        116849: {"label": "Life Cocoon", "category": "external", "default_shown": False},
        115203: {"label": "Fortifying Brew", "category": "personal", "default_shown": False},
        322109: {"label": "Touch of Death", "category": "personal", "default_shown": False},
    },
    1468: {
        359816: {"label": "Dream Flight", "category": "major", "default_shown": True},
        363534: {"label": "Rewind", "category": "major", "default_shown": True},
        370537: {"label": "Stasis", "category": "major", "default_shown": True},
        370564: {"label": "Emerald Communion", "category": "major", "default_shown": True},
        355936: {"label": "Dream Breath", "category": "semi", "default_shown": True},
        370553: {"label": "Tip the Scales", "category": "semi", "default_shown": True},
        374227: {"label": "Zephyr", "category": "semi", "default_shown": True},
        357170: {"label": "Time Dilation", "category": "external", "default_shown": False},
        406789: {"label": "Stretch Time", "category": "external", "default_shown": False},
        406732: {"label": "Spatial Paradox", "category": "external", "default_shown": False},
        363916: {"label": "Obsidian Scales", "category": "personal", "default_shown": False},
        370665: {"label": "Rescue", "category": "personal", "default_shown": False},
        374968: {"label": "Time Spiral", "category": "personal", "default_shown": False},
    },
}

SPELL_COOLDOWN_CANDIDATES: dict[int, list[dict[str, Any]]] = defaultdict(list)
for _spec_id, _spells in (HEALER_COOLDOWNS_BY_SPEC | DPS_COOLDOWNS_BY_SPEC).items():
    for _spell_id, _entry in _spells.items():
        SPELL_COOLDOWN_CANDIDATES[_spell_id].append({"spec_id": _spec_id, **_entry})

# Compatibility view for callers that only need unambiguous spell IDs.
HEALER_COOLDOWNS: dict[int, dict[str, Any]] = {
    spell_id: entries[0]
    for spell_id, entries in SPELL_COOLDOWN_CANDIDATES.items()
    if len(entries) == 1
}


def _number(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _phase_segments(fight: dict[str, Any]) -> list[dict[str, Any]]:
    start = int(_number(fight.get("startTime")))
    end = int(_number(fight.get("endTime")))
    if end <= start:
        raise ValueError("fight endTime must be greater than startTime")

    transitions = []
    for transition in fight.get("phaseTransitions") or []:
        phase_id = int(_number(transition.get("id"), 1))
        transition_start = int(_number(transition.get("startTime"), start))
        if start <= transition_start < end:
            transitions.append((transition_start, max(1, phase_id)))
    transitions.sort()

    if not transitions or transitions[0][0] > start:
        transitions.insert(0, (start, 1))

    # WCL can occasionally repeat an identical transition in imported reports.
    unique: list[tuple[int, int]] = []
    for item in transitions:
        if unique and unique[-1] == item:
            continue
        unique.append(item)

    occurrences: Counter[int] = Counter()
    segments: list[dict[str, Any]] = []
    for index, (segment_start, phase_id) in enumerate(unique):
        segment_end = unique[index + 1][0] if index + 1 < len(unique) else end
        if segment_end <= segment_start:
            continue
        occurrences[phase_id] += 1
        occurrence = occurrences[phase_id]
        segments.append(
            {
                "key": f"{phase_id}:{occurrence}",
                "phase_id": phase_id,
                "occurrence": occurrence,
                "start_ms": segment_start,
                "end_ms": segment_end,
                "duration_ms": segment_end - segment_start,
            }
        )
    return segments


def _segment_for_timestamp(
    segments: list[dict[str, Any]], starts: list[int], timestamp: int
) -> dict[str, Any] | None:
    index = bisect.bisect_right(starts, timestamp) - 1
    if index < 0 or index >= len(segments):
        return None
    segment = segments[index]
    if timestamp >= segment["end_ms"]:
        return None
    return segment


def _ability_index(master_data: dict[str, Any]) -> dict[int, dict[str, Any]]:
    result: dict[int, dict[str, Any]] = {}
    for ability in master_data.get("abilities") or []:
        spell_id = int(_number(ability.get("gameID")))
        if spell_id > 0:
            result[spell_id] = ability
    return result


def _icon_path(icon: Any) -> int | str | None:
    if not icon:
        return None
    # WCL serves web jpg names; WoW needs a numeric FileDataID or an extensionless path.
    value = str(icon).removesuffix(".jpg")
    if value.isdigit():
        return int(value)
    if value.startswith("Interface\\"):
        return value
    return "Interface\\Icons\\" + value


def build_sample(
    fight: dict[str, Any],
    master_data: dict[str, Any],
    damage_events: Iterable[dict[str, Any]],
    cast_events: Iterable[dict[str, Any]],
    *,
    interval_ms: int = INTERVAL_MS,
    expected_spec_id: int | None = None,
    hostile_cast_events: Iterable[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Convert one WCL kill into phase-relative damage/mechanic/cooldown data."""

    segments = _phase_segments(fight)
    starts = [segment["start_ms"] for segment in segments]
    friendly_players = {int(value) for value in fight.get("friendlyPlayers") or []}
    abilities = _ability_index(master_data)
    ordered_casts = sorted(cast_events, key=lambda item: _number(item.get("timestamp")))
    ordered_hostile_casts = sorted(
        hostile_cast_events if hostile_cast_events is not None else ordered_casts,
        key=lambda item: _number(item.get("timestamp")),
    )
    actor_types = {
        int(_number(actor.get("id"), -1)): str(actor.get("type") or "")
        for actor in master_data.get("actors") or []
    }

    phase_damage: dict[str, dict[int, float]] = defaultdict(lambda: defaultdict(float))
    mechanic_events: dict[tuple[str, int], list[dict[str, Any]]] = defaultdict(list)

    ordered_damage = sorted(
        (event for event in damage_events if event.get("type") == "damage"),
        key=lambda event: _number(event.get("timestamp")),
    )
    for event in ordered_damage:
        timestamp = int(_number(event.get("timestamp")))
        target_id = int(_number(event.get("targetID"), -999999))
        if friendly_players and target_id not in friendly_players:
            continue
        segment = _segment_for_timestamp(segments, starts, timestamp)
        if not segment:
            continue

        # Amount plus absorbed is the post-mitigation healing/absorb load. Using
        # amount alone would make well-timed shields erase the predicted spike.
        amount = max(0.0, _number(event.get("amount"))) + max(
            0.0, _number(event.get("absorbed"))
        )
        if amount <= 0:
            continue

        relative_ms = timestamp - segment["start_ms"]
        bin_index = max(0, int(relative_ms // interval_ms))
        phase_damage[segment["key"]][bin_index] += amount

        spell_id = int(_number(event.get("abilityGameID")))
        if spell_id > 0:
            mechanic_events[(segment["key"], spell_id)].append(
                {
                    "timestamp": timestamp,
                    "relative_ms": relative_ms,
                    "target_id": target_id,
                    "source_id": int(_number(event.get("sourceID"), -999999)),
                    "amount": amount,
                }
            )

    hostile_casts: list[dict[str, Any]] = []
    for event in ordered_hostile_casts:
        if event.get("type") not in {"cast", "begincast"} or event.get("fake"):
            continue
        source_id = int(_number(event.get("sourceID"), -999999))
        # WCL's Enemies cast stream can contain synthetic Environment casts
        # (sourceID -1) carrying friendly mitigation spell IDs. Treating those
        # as boss casts produced anchors such as Anti-Magic Zone and caused the
        # live BigWigs clock to drift away from the generated cooldown plan.
        if source_id <= 0 or source_id in friendly_players:
            continue
        if actor_types.get(source_id) in {"Player", "Pet"}:
            continue
        timestamp = int(_number(event.get("timestamp")))
        segment = _segment_for_timestamp(segments, starts, timestamp)
        spell_id = int(_number(event.get("abilityGameID")))
        if not segment or spell_id <= 0:
            continue
        hostile_casts.append(
            {
                "phase_key": segment["key"],
                "timestamp": timestamp,
                "source_id": source_id,
                "spell_id": spell_id,
                "type": event.get("type"),
                "relative_ms": timestamp - segment["start_ms"],
            }
        )

    mechanics: list[dict[str, Any]] = []
    for (phase_key, spell_id), events in mechanic_events.items():
        clusters: list[dict[str, Any]] = []
        for event in events:
            if (
                not clusters
                or event["timestamp"] - clusters[-1]["start_timestamp"]
                > MECHANIC_HIT_WINDOW_MS
            ):
                clusters.append(
                    {
                        "start_timestamp": event["timestamp"],
                        "last_timestamp": event["timestamp"],
                        "timestamps": [],
                        "damage": 0.0,
                        "targets": set(),
                        "sources": Counter(),
                    }
                )
            cluster = clusters[-1]
            cluster["last_timestamp"] = event["timestamp"]
            cluster["timestamps"].append(event["timestamp"])
            cluster["damage"] += event["amount"]
            cluster["targets"].add(event["target_id"])
            cluster["sources"][event["source_id"]] += 1

        ability = abilities.get(spell_id, {})
        for occurrence, cluster in enumerate(clusters, start=1):
            hit_timestamp = int(round(statistics.median(cluster["timestamps"])))
            source_id = cluster["sources"].most_common(1)[0][0]
            cast_candidates = [
                cast
                for cast in hostile_casts
                if cast["phase_key"] == phase_key
                and cast["source_id"] == source_id
                and 0 <= hit_timestamp - cast["timestamp"] <= BOSS_CAST_LOOKBACK_MS
            ]
            anchor_spell_id = None
            anchor_relative_ms = None
            if cast_candidates:
                same_spell = [
                    cast for cast in cast_candidates if cast["spell_id"] == spell_id
                ]
                eligible = same_spell
                if not eligible and len(cluster["targets"]) >= 3:
                    eligible = [
                        cast
                        for cast in cast_candidates
                        if hit_timestamp - cast["timestamp"] <= 6000
                    ]
                if eligible:
                    best_cast = min(
                        eligible,
                        key=lambda cast: (
                            cast["type"] != "cast",
                            hit_timestamp - cast["timestamp"],
                        ),
                    )
                    anchor_spell_id = best_cast["spell_id"]
                    anchor_relative_ms = best_cast["relative_ms"]
            mechanics.append(
                {
                    "phase_key": phase_key,
                    "spell_id": spell_id,
                    "occurrence": occurrence,
                    "relative_ms": hit_timestamp
                    - next(segment["start_ms"] for segment in segments if segment["key"] == phase_key),
                    "damage": cluster["damage"],
                    "affected_players": len(cluster["targets"]),
                    "label": ability.get("name") or f"Spell {spell_id}",
                    "icon": _icon_path(ability.get("icon")),
                    "anchor_spell_id": anchor_spell_id,
                    "anchor_relative_ms": anchor_relative_ms,
                    "anchor_delay_ms": hit_timestamp - best_cast["timestamp"]
                    if anchor_spell_id is not None
                    else None,
                }
            )

    cooldown_casts: list[dict[str, Any]] = []
    seen_cooldowns: dict[tuple[int, int], int] = {}
    for event in ordered_casts:
        if event.get("type") != "cast" or event.get("fake"):
            continue
        spell_id = int(_number(event.get("abilityGameID")))
        if expected_spec_id is not None:
            spec_entry = (HEALER_COOLDOWNS_BY_SPEC.get(expected_spec_id)
                          or DPS_COOLDOWNS_BY_SPEC.get(expected_spec_id, {})).get(spell_id)
            cooldown = {"spec_id": expected_spec_id, **spec_entry} if spec_entry else None
        else:
            candidates = SPELL_COOLDOWN_CANDIDATES.get(spell_id) or []
            cooldown = candidates[0] if len(candidates) == 1 else None
        if not cooldown:
            continue
        source_id = int(_number(event.get("sourceID"), -999999))
        if friendly_players and source_id not in friendly_players:
            continue
        timestamp = int(_number(event.get("timestamp")))
        duplicate_key = (source_id, spell_id)
        if timestamp - seen_cooldowns.get(duplicate_key, -1000000) < 1000:
            continue
        seen_cooldowns[duplicate_key] = timestamp
        segment = _segment_for_timestamp(segments, starts, timestamp)
        if not segment:
            continue
        ability = abilities.get(spell_id, {})
        cooldown_casts.append(
            {
                "phase_key": segment["key"],
                "spell_id": spell_id,
                "spec_id": cooldown["spec_id"],
                "relative_ms": timestamp - segment["start_ms"],
                "label": cooldown["label"],
                "icon": _icon_path(ability.get("icon")),
                "category": cooldown["category"],
                "default_shown": cooldown["default_shown"],
            }
        )

    cooldown_ordinals: Counter[tuple[str, int]] = Counter()
    for cooldown in sorted(cooldown_casts, key=lambda item: item["relative_ms"]):
        key = (cooldown["phase_key"], cooldown["spell_id"])
        cooldown_ordinals[key] += 1
        cooldown["occurrence"] = cooldown_ordinals[key]

    size = max(1, int(_number(fight.get("size"), len(friendly_players) or 20)))
    return {
        "fight_id": int(_number(fight.get("id"))),
        "size": size,
        "duration_ms": int(_number(fight.get("endTime"))) - int(_number(fight.get("startTime"))),
        "segments": segments,
        "phase_damage": {key: dict(values) for key, values in phase_damage.items()},
        "mechanics": mechanics,
        "cooldowns": cooldown_casts,
        # Internal alignment input only; source identity is deliberately not
        # retained. apply_healer_profiles uses these casts to warp top-HPS
        # cooldowns onto the same mechanic clock as the damage model.
        "boss_casts": [
            {
                "phase_key": cast["phase_key"],
                "spell_id": cast["spell_id"],
                "relative_ms": cast["relative_ms"],
                "type": cast["type"],
                "label": (abilities.get(cast["spell_id"]) or {}).get("name")
                or f"Spell {cast['spell_id']}",
                "icon": _icon_path((abilities.get(cast["spell_id"]) or {}).get("icon")),
            }
            for cast in hostile_casts
        ],
    }


def build_healer_sample(
    fight: dict[str, Any],
    master_data: dict[str, Any],
    cast_events: Iterable[dict[str, Any]],
    combatant_events: Iterable[dict[str, Any]],
    ranking: dict[str, Any],
    *,
    expected_spec_id: int,
    hostile_cast_events: Iterable[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Build one ranked character sample without retaining character identity."""

    ranking_name = str(ranking.get("name") or "")
    ranking_class = str(ranking.get("class") or "")
    actor_ids = {
        int(_number(actor.get("id"), -1))
        for actor in master_data.get("actors") or []
        if actor.get("type") == "Player"
        and str(actor.get("name") or "") == ranking_name
        and (not ranking_class or str(actor.get("subType") or "") == ranking_class)
    }
    actor_ids.discard(-1)
    if not actor_ids:
        raise ValueError("ranked character was not found in report actors")

    matching_combatants = [
        event
        for event in combatant_events
        if int(_number(event.get("sourceID"), -1)) in actor_ids
        and int(_number(event.get("specID"), -1)) == expected_spec_id
    ]
    if not matching_combatants:
        raise ValueError("ranked character combatant info was not found")

    combatant = matching_combatants[0]
    source_id = int(_number(combatant.get("sourceID"), -1))
    filtered_casts = [
        event
        for event in cast_events
        if int(_number(event.get("sourceID"), -2)) == source_id
    ]
    sample = build_sample(
        fight,
        master_data,
        [],
        filtered_casts,
        expected_spec_id=expected_spec_id,
        hostile_cast_events=hostile_cast_events,
    )

    talents = []
    for talent in combatant.get("talentTree") or []:
        talent_id = int(_number(talent.get("id")))
        points = int(_number(talent.get("rank")))
        if talent_id <= 0 or points <= 0:
            continue
        item = {"talentID": talent_id, "points": points}
        node_id = int(_number(talent.get("nodeID")))
        if node_id > 0:
            item["nodeID"] = node_id
        talents.append(item)
    if not talents:
        for talent in ranking.get("talents") or []:
            talent_id = int(_number(talent.get("talentID")))
            points = int(_number(talent.get("points")))
            if talent_id > 0 and points > 0:
                talents.append({"talentID": talent_id, "points": points})
    talents.sort(key=lambda item: (item.get("nodeID", 0), item["talentID"], item["points"]))

    secondary_stats = {}
    for output_key, source_key in (
        ("criticalStrike", "critSpell"),
        ("haste", "hasteSpell"),
        ("mastery", "mastery"),
        ("versatility", "versatilityDamageDone" if expected_spec_id in DPS_COOLDOWNS_BY_SPEC else "versatilityHealingDone"),
    ):
        raw_value = combatant.get(source_key)
        if isinstance(raw_value, (int, float)) and raw_value >= 0:
            secondary_stats[output_key] = int(round(float(raw_value)))

    item_levels = [
        float(item["itemLevel"])
        for item in combatant.get("gear") or []
        if isinstance(item, dict) and _number(item.get("itemLevel")) > 0
    ]
    item_level = statistics.fmean(item_levels) if item_levels else _number(ranking.get("bracketData"), 0.0)

    sample["profile"] = {
        "specID": expected_spec_id,
        "className": ranking_class,
        "specName": str(ranking.get("spec") or ""),
        "itemLevel": item_level,
        "secondaryStats": secondary_stats,
        "talents": talents,
    }
    return sample


def _reference_phases(samples: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], dict[str, int]]:
    sequences = Counter(tuple(segment["key"] for segment in sample["segments"]) for sample in samples)
    sequence = max(sequences, key=lambda value: (sequences[value], len(value)))
    phases: list[dict[str, Any]] = []
    starts: dict[str, int] = {}
    cursor = 0
    for index, key in enumerate(sequence, start=1):
        matching = [
            segment
            for sample in samples
            for segment in sample["segments"]
            if segment["key"] == key
        ]
        if not matching:
            continue
        duration_ms = max(INTERVAL_MS, int(statistics.median(item["duration_ms"] for item in matching)))
        duration_ms = int(math.ceil(duration_ms / INTERVAL_MS) * INTERVAL_MS)
        phase_id, occurrence = (int(part) for part in key.split(":"))
        starts[key] = cursor
        label = f"P{phase_id}" if occurrence == 1 else f"P{phase_id}.{occurrence}"
        phases.append(
            {
                "index": index,
                "stage": phase_id,
                "t": cursor / 1000.0,
                "label": label,
                "key": key,
                "duration_ms": duration_ms,
            }
        )
        cursor += duration_ms
    return phases, starts


def _population_spread(values: list[float]) -> float:
    return statistics.pstdev(values) if len(values) > 1 else 0.0


def _cluster_records_by_time(
    records: list[tuple[Any, ...]], tolerance_ms: int
) -> list[list[tuple[Any, ...]]]:
    """Match repeated events by time while allowing a sample to skip an occurrence.

    Ordinal matching (first cast with first cast, second with second) shifts every
    later event when one log omits a cast. Temporal clusters keep later casts and
    mechanics attached to the closest real occurrence instead.
    """

    clusters: list[dict[str, Any]] = []
    for item in sorted(records, key=lambda value: int(_number(value[-1].get("relative_ms")))):
        sample_id = item[0]
        timestamp = int(_number(item[-1].get("relative_ms")))
        best_cluster = None
        best_distance = None
        for cluster in clusters:
            if sample_id in cluster["sample_ids"]:
                continue
            center = statistics.median(cluster["times"])
            distance = abs(timestamp - center)
            if distance <= tolerance_ms and (
                best_distance is None or distance < best_distance
            ):
                best_cluster = cluster
                best_distance = distance
        if best_cluster is None:
            best_cluster = {"sample_ids": set(), "times": [], "records": []}
            clusters.append(best_cluster)
        best_cluster["sample_ids"].add(sample_id)
        best_cluster["times"].append(timestamp)
        best_cluster["records"].append(item)

    clusters.sort(key=lambda cluster: statistics.median(cluster["times"]))
    return [cluster["records"] for cluster in clusters]


def aggregate_samples(
    samples: list[dict[str, Any]],
    *,
    encounter_id: int,
    encounter_name: str,
    wcl_difficulty_id: int,
    zone_id: int,
    zone_name: str,
    interval_ms: int = INTERVAL_MS,
    mechanic_usage_floor: float = 0.25,
    cooldown_usage_floor: float = 0.10,
    max_mechanics: int = 72,
    max_sync_anchors: int = 600,
) -> dict[str, Any]:
    if not samples:
        raise ValueError("at least one fight sample is required")
    if wcl_difficulty_id not in WCL_TO_WOW_DIFFICULTY:
        raise ValueError(f"unsupported WCL raid difficulty: {wcl_difficulty_id}")

    phases, phase_starts = _reference_phases(samples)
    phase_by_key = {phase["key"]: phase for phase in phases}
    reference_size = max(1, int(round(statistics.median(sample["size"] for sample in samples))))

    mechanic_groups: dict[
        tuple[str, int], list[tuple[int, dict[str, Any], dict[str, Any]]]
    ] = defaultdict(list)
    for sample_index, sample in enumerate(samples):
        for mechanic in sample["mechanics"]:
            if mechanic["phase_key"] in phase_starts:
                mechanic_groups[(mechanic["phase_key"], mechanic["spell_id"])].append(
                    (sample_index, sample, mechanic)
                )

    aligned_mechanic_groups: list[
        tuple[str, int, int, list[tuple[int, dict[str, Any], dict[str, Any]]]]
    ] = []
    for (phase_key, spell_id), records in mechanic_groups.items():
        clusters = _cluster_records_by_time(records, MECHANIC_ALIGNMENT_TOLERANCE_MS)
        for occurrence, cluster_records in enumerate(clusters, start=1):
            aligned_mechanic_groups.append(
                (phase_key, spell_id, occurrence, cluster_records)
            )

    mechanic_candidates: list[dict[str, Any]] = []
    minimum_targets = max(3.0, reference_size * 0.20)
    for phase_key, spell_id, occurrence, records in aligned_mechanic_groups:
        sample_ids = {sample_index for sample_index, _, _ in records}
        usage = len(sample_ids) / len(samples)
        if usage < mechanic_usage_floor:
            continue
        relative_times = [record["relative_ms"] / 1000.0 for _, _, record in records]
        scaled_damage = [
            record["damage"] * reference_size / max(1, sample["size"])
            for _, sample, record in records
        ]
        scaled_targets = [
            record["affected_players"] * reference_size / max(1, sample["size"])
            for _, sample, record in records
        ]
        avg_damage = statistics.fmean(scaled_damage)
        affected_players = statistics.fmean(scaled_targets)
        anchor_spell_ids = [
            int(_number(record.get("anchor_spell_id")))
            for _, _, record in records
            if int(_number(record.get("anchor_spell_id"))) > 0
        ]
        anchor_spell_id = None
        anchor_relative_times: list[float] = []
        anchor_delays: list[float] = []
        if anchor_spell_ids:
            candidate_spell_id, candidate_count = Counter(anchor_spell_ids).most_common(1)[0]
            matching_anchor_records = [
                record
                for _, _, record in records
                if int(_number(record.get("anchor_spell_id"))) == candidate_spell_id
                and _number(record.get("anchor_relative_ms"), -1) >= 0
            ]
            anchor_relative_times = [
                _number(record.get("anchor_relative_ms")) / 1000.0
                for record in matching_anchor_records
            ]
            anchor_delays = [
                _number(record.get("anchor_delay_ms")) / 1000.0
                for record in matching_anchor_records
                if _number(record.get("anchor_delay_ms"), -1) >= 0
            ]
            anchor_confidence = candidate_count / max(1, len(records))
            delay_spread = _population_spread(anchor_delays)
            # Cross-spell mappings are needed for mechanics whose cast and
            # damage aura use different IDs, but only keep them when the
            # relationship repeats tightly across logs. A loose nearest-cast
            # guess is worse than leaving the mechanic unsynchronised.
            same_spell = candidate_spell_id == spell_id
            stable_cross_spell = (
                len(anchor_delays) >= 2
                and anchor_confidence >= 0.60
                and delay_spread <= 0.85
            )
            if anchor_relative_times and (same_spell or stable_cross_spell):
                anchor_spell_id = candidate_spell_id
        mechanic_candidates.append(
            {
                "id": f"wcl_{encounter_id}_{wcl_difficulty_id}_{phase_key}_{spell_id}_{occurrence}",
                "t": phase_starts[phase_key] / 1000.0 + statistics.median(relative_times),
                "phase": phase_by_key[phase_key]["index"],
                "spellID": spell_id,
                "anchorKey": spell_id,
                "label": records[0][2]["label"],
                "icon": records[0][2].get("icon"),
                "avgDamage": int(round(avg_damage)),
                "affectedPlayers": round(affected_players, 1),
                "usage": round(usage, 3),
                "spread": round(_population_spread(relative_times), 2),
                "_passes_targets": affected_players >= minimum_targets,
                "bigWigsKey": anchor_spell_id,
                "syncT": (
                    phase_starts[phase_key] / 1000.0
                    + statistics.median(anchor_relative_times)
                    if anchor_spell_id is not None
                    else None
                ),
                "syncSpread": (
                    _population_spread(anchor_relative_times)
                    if anchor_spell_id is not None
                    else None
                ),
            }
        )

    # Low-damage or single-target abilities may still be the exact key emitted
    # by a BigWigs bar. Keep their aggregate hit times in the hidden sync index
    # even when they do not deserve a visible mechanic marker.
    damage_sync_anchors: list[dict[str, Any]] = []
    for item in mechanic_candidates:
        if item["usage"] < mechanic_usage_floor:
            continue
        anchor = {
            "id": str(item["id"]) + "_damage_sync",
            "t": round(float(item["t"]), 2),
            "syncT": round(float(item["t"]), 2),
            "phase": item["phase"],
            "spellID": item["spellID"],
            "bigWigsKey": item["spellID"],
            "label": item["label"],
            "usage": item["usage"],
            "spread": item["spread"],
            "syncOnly": True,
        }
        if item.get("icon"):
            anchor["icon"] = item["icon"]
        damage_sync_anchors.append(anchor)

    damage_cutoff = 0.0
    if mechanic_candidates:
        ordered_damage = sorted(item["avgDamage"] for item in mechanic_candidates)
        damage_cutoff = ordered_damage[int((len(ordered_damage) - 1) * 0.70)]
    mechanic_candidates = [
        item
        for item in mechanic_candidates
        if item.pop("_passes_targets") or item["avgDamage"] >= damage_cutoff
    ]
    mechanic_candidates.sort(key=lambda item: (item["avgDamage"], item["usage"]), reverse=True)
    mechanics = mechanic_candidates[:max_mechanics]
    maximum_mechanic_damage = max((item["avgDamage"] for item in mechanics), default=1)
    for mechanic in mechanics:
        mechanic["severity"] = round(mechanic["avgDamage"] / maximum_mechanic_damage, 3)
        mechanic["t"] = round(mechanic["t"], 2)
        if mechanic.get("syncT") is not None:
            mechanic["syncT"] = round(mechanic["syncT"], 2)
            mechanic["syncSpread"] = round(mechanic.get("syncSpread") or 0.0, 2)
        if mechanic.get("icon") is None:
            mechanic.pop("icon", None)
        if mechanic.get("bigWigsKey") is None:
            mechanic.pop("bigWigsKey", None)
            mechanic.pop("syncT", None)
            mechanic.pop("syncSpread", None)
    mechanics.sort(key=lambda item: item["t"])

    # Build a separate boss-cast schedule for runtime synchronization. Damage
    # auras often use a different spell ID (or have no cast at all), so limiting
    # BigWigs matching to the visible damage markers leaves long sections of a
    # fight unable to follow Blizzard's live encounter timeline.
    sync_anchor_groups: dict[
        tuple[str, int], list[tuple[int, dict[str, Any]]]
    ] = defaultdict(list)
    for sample_index, sample in enumerate(samples):
        successful_by_key: dict[tuple[str, int], list[dict[str, Any]]] = defaultdict(list)
        fallback_by_key: dict[tuple[str, int], list[dict[str, Any]]] = defaultdict(list)
        for cast in sample.get("boss_casts") or []:
            phase_key = str(cast.get("phase_key") or "")
            spell_id = int(_number(cast.get("spell_id")))
            if phase_key not in phase_starts or spell_id <= 0:
                continue
            key = (phase_key, spell_id)
            fallback_by_key[key].append(cast)
            if cast.get("type") == "cast":
                successful_by_key[key].append(cast)
        for key, fallback_records in fallback_by_key.items():
            for cast in successful_by_key.get(key) or fallback_records:
                sync_anchor_groups[key].append((sample_index, cast))

    sync_anchor_candidates: list[dict[str, Any]] = list(damage_sync_anchors)
    minimum_anchor_records = min(2, len(samples))
    for (phase_key, spell_id), records in sync_anchor_groups.items():
        clusters = _cluster_records_by_time(records, 1750)
        for occurrence, cluster_records in enumerate(clusters, start=1):
            sample_ids = {sample_index for sample_index, _ in cluster_records}
            usage = len(sample_ids) / len(samples)
            if usage < 0.50 or len(sample_ids) < minimum_anchor_records:
                continue
            relative_times = [
                _number(record.get("relative_ms")) / 1000.0
                for _, record in cluster_records
            ]
            first_record = cluster_records[0][1]
            item = {
                "id": f"wcl_sync_{encounter_id}_{wcl_difficulty_id}_{phase_key}_{spell_id}_{occurrence}",
                "t": round(
                    phase_starts[phase_key] / 1000.0 + statistics.median(relative_times),
                    2,
                ),
                "syncT": round(
                    phase_starts[phase_key] / 1000.0 + statistics.median(relative_times),
                    2,
                ),
                "phase": phase_by_key[phase_key]["index"],
                "spellID": spell_id,
                "bigWigsKey": spell_id,
                "label": first_record.get("label") or f"Spell {spell_id}",
                "usage": round(usage, 3),
                "spread": round(_population_spread(relative_times), 2),
                "syncOnly": True,
            }
            if first_record.get("icon"):
                item["icon"] = first_record["icon"]
            sync_anchor_candidates.append(item)

    # A few periodic aura IDs can produce hundreds of very stable records and
    # previously pushed real BigWigs keys out of the global cap. Deduplicate
    # near-identical anchors, reserve chronological coverage per spell, and
    # only then apply the encounter-wide limit.
    anchors_by_spell: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for item in sorted(sync_anchor_candidates, key=lambda value: value["t"]):
        spell_id = int(_number(item.get("spellID")))
        existing = anchors_by_spell[spell_id]
        if existing and item["t"] - existing[-1]["t"] < 0.35:
            current_score = (item["usage"], -item["spread"])
            existing_score = (existing[-1]["usage"], -existing[-1]["spread"])
            if current_score > existing_score:
                existing[-1] = item
            continue
        existing.append(item)

    covered_by_spell: dict[int, list[dict[str, Any]]] = {}
    per_spell_limit = 24
    for spell_id, records in anchors_by_spell.items():
        if len(records) <= per_spell_limit:
            covered_by_spell[spell_id] = records
            continue
        indexes = {
            int(round(index * (len(records) - 1) / (per_spell_limit - 1)))
            for index in range(per_spell_limit)
        }
        covered_by_spell[spell_id] = [records[index] for index in sorted(indexes)]

    ordered_spell_ids = sorted(
        covered_by_spell,
        key=lambda spell_id: (
            -max(item["usage"] for item in covered_by_spell[spell_id]),
            min(item["spread"] for item in covered_by_spell[spell_id]),
            spell_id,
        ),
    )
    selected_anchors: list[dict[str, Any]] = []
    depth = 0
    while len(selected_anchors) < max_sync_anchors:
        added = False
        for spell_id in ordered_spell_ids:
            records = covered_by_spell[spell_id]
            if depth < len(records):
                selected_anchors.append(records[depth])
                added = True
                if len(selected_anchors) >= max_sync_anchors:
                    break
        if not added:
            break
        depth += 1
    sync_anchors = sorted(selected_anchors, key=lambda item: item["t"])

    cooldown_groups: dict[
        tuple[str, int, int], list[tuple[int, dict[str, Any]]]
    ] = defaultdict(list)
    for sample_index, sample in enumerate(samples):
        for cooldown in sample["cooldowns"]:
            if cooldown["phase_key"] not in phase_starts:
                continue
            key = (
                cooldown["phase_key"],
                cooldown["spec_id"],
                cooldown["spell_id"],
            )
            cooldown_groups[key].append((sample_index, cooldown))

    cooldowns_by_spec: dict[int, list[dict[str, Any]]] = defaultdict(list)
    all_cooldowns: list[dict[str, Any]] = []
    minimum_cooldown_records = min(2, len(samples))
    for (phase_key, spec_id, spell_id), records in cooldown_groups.items():
        aligned_clusters = _cluster_records_by_time(
            records, COOLDOWN_ALIGNMENT_TOLERANCE_MS
        )
        for occurrence, cluster_records in enumerate(aligned_clusters, start=1):
            sample_ids = {sample_index for sample_index, _ in cluster_records}
            usage = len(sample_ids) / len(samples)
            # A single cast is too noisy for a top-10 average unless only one
            # public kill exists for the encounter.
            if usage < cooldown_usage_floor or len(sample_ids) < minimum_cooldown_records:
                continue
            relative_times = [
                record["relative_ms"] / 1000.0 for _, record in cluster_records
            ]
            first_record = cluster_records[0][1]
            item = {
                "id": f"wcl_cd_{encounter_id}_{wcl_difficulty_id}_{phase_key}_{spell_id}_{occurrence}",
                "t": round(
                    phase_starts[phase_key] / 1000.0
                    + statistics.median(relative_times),
                    2,
                ),
                "phase": phase_by_key[phase_key]["index"],
                "spellID": spell_id,
                "label": first_record["label"],
                "category": first_record.get("category", "major"),
                "defaultShown": first_record.get("default_shown", True),
                "usage": round(usage, 3),
                "spread": round(_population_spread(relative_times), 2),
            }
            if first_record.get("icon"):
                item["icon"] = first_record["icon"]
            cooldowns_by_spec[spec_id].append(item)
            all_cooldowns.append(dict(item))

    for cooldowns in cooldowns_by_spec.values():
        cooldowns.sort(key=lambda item: item["t"])
    all_cooldowns.sort(key=lambda item: item["t"])

    public_phases = [
        {key: value for key, value in phase.items() if key not in {"key", "duration_ms"}}
        for phase in phases
    ]
    duration_seconds = sum(phase["duration_ms"] for phase in phases) / 1000.0
    model = {
        "schemaVersion": 2,
        "encounterID": encounter_id,
        "difficultyID": WCL_TO_WOW_DIFFICULTY[wcl_difficulty_id],
        "wclDifficultyID": wcl_difficulty_id,
        "zoneID": zone_id,
        "zoneName": zone_name,
        "name": encounter_name,
        "duration": round(duration_seconds, 1),
        "groupSize": reference_size,
        "dataStatus": "wcl",
        "sampleCount": len(samples),
        "generatedAt": datetime.now(timezone.utc).replace(microsecond=0).isoformat(),
        "sourceMetric": "top-speed-kills",
        "timingAlignment": "phase-cast-anchored-v2",
        "phases": public_phases,
        "damage": {
            "interval": interval_ms / 1000.0,
            "values": [],
            "max": 1,
            "metric": "raidDamageAfterMitigationIncludingAbsorbs",
        },
        "mechanics": mechanics,
        "syncAnchors": sync_anchors,
        "cooldowns": all_cooldowns,
        "cooldownsBySpec": dict(cooldowns_by_spec),
    }

    # Damage, healer casts and holdouts must all use the same source clock.
    damage_values: list[int] = []
    for phase in phases:
        curves = []
        for sample in samples:
            segment = next((item for item in sample["segments"] if item["key"] == phase["key"]), None)
            if segment is None:
                continue
            mapper, _ = _phase_time_mapper(
                model, sample, phase["key"], phase_starts[phase["key"]],
                phase["duration_ms"], phase["index"],
            )
            curve = _mapped_damage_curve(
                sample, phase["key"], mapper, phase["duration_ms"], interval_ms, reference_size,
            )
            curves.append((curve, mapper(0), mapper(segment["duration_ms"])))
        for bin_index in range(int(math.ceil(phase["duration_ms"] / interval_ms))):
            time = (bin_index + 0.5) * interval_ms
            values = [curve[bin_index] for curve, start, end in curves if start <= time < end]
            damage_values.append(int(round(statistics.fmean(values))) if values else 0)
    model["damage"]["values"] = damage_values
    model["damage"]["max"] = max(damage_values, default=1)
    return model


def _dedupe_times(values: Iterable[float], tolerance_ms: float = 650.0) -> list[float]:
    result: list[float] = []
    for value in sorted(float(item) for item in values):
        if not result or value - result[-1] > tolerance_ms:
            result.append(value)
        else:
            result[-1] = (result[-1] + value) / 2.0
    return result


def _phase_time_mapper(
    model: dict[str, Any],
    sample: dict[str, Any],
    phase_key: str,
    phase_start_ms: float,
    model_duration_ms: float,
    phase_index: int,
):
    """Map one healer log phase onto the base model's mechanic clock.

    Top-HPS rankings are collected from different kills than the damage model.
    Their raw seconds-from-phase-start are therefore not directly comparable.
    Match nearby occurrences in elapsed seconds, never by kill-duration ratio.
    Interpolate only between observed cast anchors; beyond them preserve seconds.
    A longer kill is not evidence that every spell's cooldown ran faster.
    """

    segment = next(
        (item for item in sample.get("segments") or [] if item.get("key") == phase_key),
        None,
    )
    sample_duration_ms = max(
        float(INTERVAL_MS),
        _number((segment or {}).get("duration_ms"), model_duration_ms),
    )
    model_duration_ms = max(float(INTERVAL_MS), float(model_duration_ms))

    model_by_spell: dict[int, list[float]] = defaultdict(list)
    alignment_events = [
        *(model.get("syncAnchors") or []),
        *(model.get("mechanics") or []),
    ]
    for mechanic in alignment_events:
        if int(_number(mechanic.get("phase"))) != phase_index:
            continue
        spell_id = int(_number(mechanic.get("bigWigsKey")))
        sync_time = _number(mechanic.get("syncT"), -1)
        if spell_id <= 0 or sync_time < 0:
            continue
        relative_ms = sync_time * 1000.0 - phase_start_ms
        if 0 <= relative_ms <= model_duration_ms:
            model_by_spell[spell_id].append(relative_ms)
    model_by_spell = {
        spell_id: _dedupe_times(times)
        for spell_id, times in model_by_spell.items()
    }

    sample_by_spell_all: dict[int, list[tuple[float, str]]] = defaultdict(list)
    for cast in sample.get("boss_casts") or []:
        if str(cast.get("phase_key")) != phase_key:
            continue
        spell_id = int(_number(cast.get("spell_id")))
        relative_ms = _number(cast.get("relative_ms"), -1)
        if spell_id > 0 and 0 <= relative_ms <= sample_duration_ms:
            sample_by_spell_all[spell_id].append((relative_ms, str(cast.get("type") or "")))

    sample_by_spell: dict[int, list[float]] = {}
    for spell_id, records in sample_by_spell_all.items():
        successful = [time for time, event_type in records if event_type == "cast"]
        sample_by_spell[spell_id] = _dedupe_times(successful or [time for time, _ in records])

    pairs: list[tuple[float, float]] = [(0.0, 0.0)]
    for spell_id, model_times in model_by_spell.items():
        sample_times = sample_by_spell.get(spell_id) or []
        if not sample_times:
            continue
        unused = set(range(len(sample_times)))
        for model_time in model_times:
            best_index = min(
                unused,
                key=lambda index: abs(sample_times[index] - model_time),
                default=None,
            )
            if best_index is None:
                break
            sample_time = sample_times[best_index]
            if abs(sample_time - model_time) > 2 * VALIDATION_MECHANIC_MATCH_TOLERANCE_MS:
                continue
            unused.remove(best_index)
            pairs.append((sample_time, model_time))

    # Piecewise interpolation requires a monotonic path. When noisy/add casts
    # cross, retain the anchors that preserve chronological order.
    ordered_pairs = sorted(pairs)
    monotonic: list[tuple[float, float]] = []
    for source_time, target_time in ordered_pairs:
        if monotonic and source_time - monotonic[-1][0] < 250:
            if target_time > monotonic[-1][1]:
                monotonic[-1] = (source_time, target_time)
            continue
        if monotonic and target_time <= monotonic[-1][1]:
            continue
        monotonic.append((source_time, target_time))
    source_points = [point[0] for point in monotonic]

    def map_time(relative_ms: float) -> float:
        relative_ms = float(relative_ms)
        right = bisect.bisect_right(source_points, relative_ms)
        if right <= 0:
            return relative_ms + monotonic[0][1] - monotonic[0][0]
        if right >= len(monotonic):
            return relative_ms + monotonic[-1][1] - monotonic[-1][0]
        left_source, left_target = monotonic[right - 1]
        right_source, right_target = monotonic[right]
        span = max(1.0, right_source - left_source)
        ratio = (relative_ms - left_source) / span
        return left_target + (right_target - left_target) * ratio

    return map_time, max(0, len(monotonic) - 1)


def _percentile(values: list[float], fraction: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(float(value) for value in values)
    if len(ordered) == 1:
        return ordered[0]
    position = max(0.0, min(1.0, fraction)) * (len(ordered) - 1)
    lower = int(math.floor(position))
    upper = int(math.ceil(position))
    if lower == upper:
        return ordered[lower]
    weight = position - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def _model_phase_layout(model: dict[str, Any]) -> list[dict[str, Any]]:
    phases = model.get("phases") or []
    duration_ms = max(float(INTERVAL_MS), _number(model.get("duration")) * 1000.0)
    occurrences: Counter[int] = Counter()
    layout: list[dict[str, Any]] = []
    for phase_index, phase in enumerate(phases):
        stage = int(_number(phase.get("stage"), phase.get("index", 1)))
        occurrences[stage] += 1
        start_ms = _number(phase.get("t")) * 1000.0
        end_ms = (
            _number(phases[phase_index + 1].get("t")) * 1000.0
            if phase_index + 1 < len(phases)
            else duration_ms
        )
        layout.append(
            {
                "key": f"{stage}:{occurrences[stage]}",
                "index": int(_number(phase.get("index"), phase_index + 1)),
                "start_ms": start_ms,
                "duration_ms": max(float(INTERVAL_MS), end_ms - start_ms),
            }
        )
    return layout


def _pair_event_times(
    expected_times: list[float],
    actual_times: list[float],
    tolerance_ms: float,
) -> list[float]:
    candidates = sorted(
        (
            (abs(expected - actual), expected_index, actual_index)
            for expected_index, expected in enumerate(expected_times)
            for actual_index, actual in enumerate(actual_times)
            if abs(expected - actual) <= tolerance_ms
        ),
        key=lambda item: item[0],
    )
    used_expected: set[int] = set()
    used_actual: set[int] = set()
    residuals: list[float] = []
    for residual, expected_index, actual_index in candidates:
        if expected_index in used_expected or actual_index in used_actual:
            continue
        used_expected.add(expected_index)
        used_actual.add(actual_index)
        residuals.append(float(residual))
    return residuals


def _smooth_curve(values: list[float], radius: int = 2) -> list[float]:
    if not values:
        return []
    prefix = [0.0]
    for value in values:
        prefix.append(prefix[-1] + max(0.0, float(value)))
    result = []
    for index in range(len(values)):
        start = max(0, index - radius)
        end = min(len(values), index + radius + 1)
        result.append((prefix[end] - prefix[start]) / max(1, end - start))
    return result


def _peak_indexes(
    values: list[float],
    *,
    maximum: int = 5,
    minimum_separation: int = 8,
) -> list[int]:
    if not values or max(values, default=0.0) <= 0:
        return []
    threshold = max(values) * 0.30
    candidates = [
        index
        for index, value in enumerate(values)
        if value >= threshold
        and (index == 0 or value >= values[index - 1])
        and (index + 1 == len(values) or value >= values[index + 1])
    ]
    selected: list[int] = []
    for index in sorted(candidates, key=lambda item: values[item], reverse=True):
        if any(abs(index - existing) < minimum_separation for existing in selected):
            continue
        selected.append(index)
        if len(selected) >= maximum:
            break
    return sorted(selected)


def _mapped_damage_curve(
    sample: dict[str, Any],
    phase_key: str,
    mapper,
    target_duration_ms: float,
    interval_ms: int,
    reference_size: int,
) -> list[float]:
    bin_count = max(1, int(math.ceil(target_duration_ms / interval_ms)))
    values = [0.0] * bin_count
    source_values = sample.get("phase_damage", {}).get(phase_key, {})
    scale = reference_size / max(1, int(_number(sample.get("size"), reference_size)))
    for source_bin, raw_value in source_values.items():
        source_time = (int(source_bin) + 0.5) * interval_ms
        target_time = mapper(source_time)
        if not 0 <= target_time < target_duration_ms:
            continue
        target_bin = min(bin_count - 1, max(0, int(target_time // interval_ms)))
        values[target_bin] += max(0.0, _number(raw_value)) * scale
    return values


def validate_model_accuracy(
    model: dict[str, Any],
    training_samples: list[dict[str, Any]],
    validation_samples: list[dict[str, Any]] | None = None,
    healer_samples_by_spec: dict[int, list[dict[str, Any]]] | None = None,
    healer_validation_samples_by_spec: dict[int, list[dict[str, Any]]] | None = None,
    dps_samples_by_spec: dict[int, list[dict[str, Any]]] | None = None,
    dps_validation_samples_by_spec: dict[int, list[dict[str, Any]]] | None = None,
) -> dict[str, Any]:
    """Validate one generated model against source-log timing evidence.

    Ranked kills used to build the average remain the training set. When public
    logs are available beyond that set, independent holdouts verify that phase,
    mechanic, and damage-peak timing generalises instead of merely reproducing
    the same ten inputs. Only aggregate diagnostics are exported; report and
    character identities never leave the collector.
    """

    validation_samples = list(validation_samples or [])
    evaluation_samples = validation_samples or list(training_samples)
    layout = _model_phase_layout(model)
    layout_by_key = {phase["key"]: phase for phase in layout}
    phase_key_by_index = {phase["index"]: phase["key"] for phase in layout}
    model_phase_keys = [phase["key"] for phase in layout]
    interval_ms = max(
        1,
        int(round(_number((model.get("damage") or {}).get("interval"), 0.5) * 1000.0)),
    )
    reference_size = max(1, int(_number(model.get("groupSize"), 20)))

    matched_phase_slots = 0
    total_phase_slots = len(evaluation_samples) * len(model_phase_keys)
    exact_phase_sequences = 0
    phase_mappers_by_sample: list[dict[str, Any]] = []
    alignment_anchor_counts: list[int] = []
    for sample in evaluation_samples:
        sample_keys = [str(segment.get("key")) for segment in sample.get("segments") or []]
        if sample_keys == model_phase_keys:
            exact_phase_sequences += 1
        sample_key_set = set(sample_keys)
        matched_phase_slots += min(len(sample_keys), len(model_phase_keys))
        mappers: dict[str, Any] = {}
        for phase in layout:
            if phase["key"] not in sample_key_set:
                continue
            mapper, anchor_count = _phase_time_mapper(
                model,
                sample,
                phase["key"],
                phase["start_ms"],
                phase["duration_ms"],
                phase["index"],
            )
            mappers[phase["key"]] = mapper
            alignment_anchor_counts.append(anchor_count)
        phase_mappers_by_sample.append(mappers)

    mechanic_groups: dict[tuple[str, int], list[float]] = defaultdict(list)
    for mechanic in model.get("mechanics") or []:
        if _number(mechanic.get("usage"), 1.0) < 0.50:
            continue
        phase_key = phase_key_by_index.get(int(_number(mechanic.get("phase"))))
        spell_id = int(_number(mechanic.get("spellID")))
        if not phase_key or spell_id <= 0:
            continue
        phase = layout_by_key[phase_key]
        mechanic_groups[(phase_key, spell_id)].append(
            _number(mechanic.get("t")) * 1000.0 - phase["start_ms"]
        )

    mechanic_expected = 0
    mechanic_residuals_ms: list[float] = []
    for sample, phase_mappers in zip(evaluation_samples, phase_mappers_by_sample):
        sample_groups: dict[tuple[str, int], list[float]] = defaultdict(list)
        for mechanic in sample.get("mechanics") or []:
            phase_key = str(mechanic.get("phase_key") or "")
            mapper = phase_mappers.get(phase_key)
            spell_id = int(_number(mechanic.get("spell_id")))
            if mapper is None or spell_id <= 0:
                continue
            sample_groups[(phase_key, spell_id)].append(
                mapper(_number(mechanic.get("relative_ms")))
            )
        for key, expected_times in mechanic_groups.items():
            if key[0] not in phase_mappers:
                continue
            mechanic_expected += len(expected_times)
            mechanic_residuals_ms.extend(
                _pair_event_times(
                    expected_times,
                    sample_groups.get(key) or [],
                    VALIDATION_MECHANIC_MATCH_TOLERANCE_MS,
                )
            )

    flat_model_damage = [float(value) for value in (model.get("damage") or {}).get("values") or []]
    model_damage_by_phase: dict[str, list[float]] = {}
    damage_cursor = 0
    for phase in layout:
        bin_count = max(1, int(math.ceil(phase["duration_ms"] / interval_ms)))
        values = flat_model_damage[damage_cursor : damage_cursor + bin_count]
        if len(values) < bin_count:
            values.extend([0.0] * (bin_count - len(values)))
        model_damage_by_phase[phase["key"]] = values
        damage_cursor += bin_count

    damage_peak_expected = 0
    damage_peak_residuals_ms: list[float] = []
    damage_curve_similarities: list[float] = []
    peak_tolerance_bins = max(
        1, int(round(VALIDATION_DAMAGE_PEAK_MATCH_TOLERANCE_MS / interval_ms))
    )
    minimum_peak_separation = max(2, int(round(4000 / interval_ms)))
    for sample, phase_mappers in zip(evaluation_samples, phase_mappers_by_sample):
        for phase_key, mapper in phase_mappers.items():
            phase = layout_by_key[phase_key]
            model_curve = _smooth_curve(model_damage_by_phase.get(phase_key) or [])
            sample_curve = _smooth_curve(
                _mapped_damage_curve(
                    sample,
                    phase_key,
                    mapper,
                    phase["duration_ms"],
                    interval_ms,
                    reference_size,
                )
            )
            if not model_curve or not sample_curve or max(model_curve) <= 0 or max(sample_curve) <= 0:
                continue
            model_norm = math.sqrt(sum(value * value for value in model_curve))
            sample_norm = math.sqrt(sum(value * value for value in sample_curve))
            if model_norm > 0 and sample_norm > 0:
                damage_curve_similarities.append(
                    sum(left * right for left, right in zip(model_curve, sample_curve))
                    / (model_norm * sample_norm)
                )
            model_peaks = _peak_indexes(
                model_curve, minimum_separation=minimum_peak_separation
            )
            sample_peaks = _peak_indexes(
                sample_curve, minimum_separation=minimum_peak_separation
            )
            damage_peak_expected += len(model_peaks)
            damage_peak_residuals_ms.extend(
                residual * interval_ms
                for residual in _pair_event_times(
                    [float(index) for index in model_peaks],
                    [float(index) for index in sample_peaks],
                    peak_tolerance_bins,
                )
            )

    def anchored_samples(*sources: dict[int, list[dict[str, Any]]]) -> tuple[int, int, list[int]]:
        sample_count = 0
        anchored_count = 0
        matches: list[int] = []
        for source in sources:
            for samples in source.values():
                for sample in samples:
                    sample_count += 1
                    sample_keys = {str(segment.get("key")) for segment in sample.get("segments") or []}
                    anchor_total = 0
                    for phase in layout:
                        if phase["key"] not in sample_keys:
                            continue
                        _, anchor_count = _phase_time_mapper(
                            model, sample, phase["key"], phase["start_ms"],
                            phase["duration_ms"], phase["index"],
                        )
                        anchor_total += anchor_count
                    matches.append(anchor_total)
                    if anchor_total > 0:
                        anchored_count += 1
        return sample_count, anchored_count, matches

    healer_sample_count, healer_anchored_sample_count, healer_anchor_matches = anchored_samples(
        healer_samples_by_spec or {}, healer_validation_samples_by_spec or {}
    )
    dps_sample_count, dps_anchored_sample_count, dps_anchor_matches = anchored_samples(
        dps_samples_by_spec or {}, dps_validation_samples_by_spec or {}
    )

    phase_coverage = matched_phase_slots / max(1, total_phase_slots)
    exact_phase_coverage = exact_phase_sequences / max(1, len(evaluation_samples))
    mechanic_coverage = len(mechanic_residuals_ms) / max(1, mechanic_expected)
    mechanic_median_error = statistics.median(mechanic_residuals_ms) / 1000.0 if mechanic_residuals_ms else 0.0
    mechanic_p90_error = _percentile(mechanic_residuals_ms, 0.90) / 1000.0
    damage_peak_coverage = len(damage_peak_residuals_ms) / max(1, damage_peak_expected)
    damage_peak_median_error = (
        statistics.median(damage_peak_residuals_ms) / 1000.0
        if damage_peak_residuals_ms
        else 0.0
    )
    damage_curve_similarity = (
        statistics.median(damage_curve_similarities)
        if damage_curve_similarities
        else 0.0
    )
    healer_anchor_coverage = healer_anchored_sample_count / max(1, healer_sample_count)

    failures: list[str] = []
    if not layout:
        failures.append("missing phase layout")
    if phase_coverage < VALIDATION_MIN_PHASE_COVERAGE:
        failures.append(f"phase coverage {phase_coverage:.2f} is below {VALIDATION_MIN_PHASE_COVERAGE:.2f}")
    if mechanic_expected >= 4:
        if mechanic_coverage < VALIDATION_MIN_MECHANIC_COVERAGE:
            failures.append(
                f"mechanic match coverage {mechanic_coverage:.2f} is below "
                f"{VALIDATION_MIN_MECHANIC_COVERAGE:.2f}"
            )
        if mechanic_median_error > VALIDATION_MAX_MECHANIC_MEDIAN_ERROR_SECONDS:
            failures.append(
                f"mechanic median error {mechanic_median_error:.2f}s exceeds "
                f"{VALIDATION_MAX_MECHANIC_MEDIAN_ERROR_SECONDS:.2f}s"
            )
        if mechanic_p90_error > VALIDATION_MAX_MECHANIC_P90_ERROR_SECONDS:
            failures.append(
                f"mechanic p90 error {mechanic_p90_error:.2f}s exceeds "
                f"{VALIDATION_MAX_MECHANIC_P90_ERROR_SECONDS:.2f}s"
            )
    if damage_peak_expected >= 4:
        # A broad damage event can appear as one plateau in a holdout and as
        # several adjacent local maxima in the ten-log mean. In that case the
        # discrete peak count is low even though the full curve is correctly
        # aligned, so only reject low peak coverage when curve similarity also
        # confirms a real timing mismatch.
        if (
            damage_peak_coverage < VALIDATION_MIN_DAMAGE_PEAK_COVERAGE
            and damage_curve_similarity < VALIDATION_MIN_DAMAGE_CURVE_SIMILARITY
        ):
            failures.append(
                f"damage peak coverage {damage_peak_coverage:.2f} is below "
                f"{VALIDATION_MIN_DAMAGE_PEAK_COVERAGE:.2f} and curve similarity "
                f"{damage_curve_similarity:.2f} is below "
                f"{VALIDATION_MIN_DAMAGE_CURVE_SIMILARITY:.2f}"
            )
        if damage_peak_median_error > VALIDATION_MAX_DAMAGE_PEAK_MEDIAN_ERROR_SECONDS:
            failures.append(
                f"damage peak median error {damage_peak_median_error:.2f}s exceeds "
                f"{VALIDATION_MAX_DAMAGE_PEAK_MEDIAN_ERROR_SECONDS:.2f}s"
            )
    sync_anchor_count = len(model.get("syncAnchors") or [])
    if sync_anchor_count >= 4 and healer_sample_count >= 4 and healer_anchor_coverage < 0.20:
        failures.append(
            f"healer anchor coverage {healer_anchor_coverage:.2f} is below 0.20"
        )
    dps_anchor_coverage = dps_anchored_sample_count / max(1, dps_sample_count)
    if sync_anchor_count >= 4 and dps_sample_count >= 4 and dps_anchor_coverage < 0.20:
        failures.append(f"DPS anchor coverage {dps_anchor_coverage:.2f} is below 0.20")

    independent_holdout_count = len(validation_samples)
    enough_independent_evidence = (
        independent_holdout_count > 0
        and mechanic_expected >= 4
        and damage_peak_expected >= 4
    )
    missing_healer_specs = [
        int(spec["spec_id"]) for spec in HEALER_SPECS
        if healer_samples_by_spec is not None
        and not healer_samples_by_spec.get(int(spec["spec_id"]))
    ]
    if missing_healer_specs:
        enough_independent_evidence = False
    status = "failed" if failures else ("passed" if enough_independent_evidence else "limited")
    report: dict[str, Any] = {
        "status": status,
        "method": "ranked-kill-holdout-v1",
        "trainingSampleCount": len(training_samples),
        "holdoutSampleCount": independent_holdout_count,
        "evaluatedSampleCount": len(evaluation_samples),
        "phaseCoverage": round(phase_coverage, 3),
        "exactPhaseSequenceCoverage": round(exact_phase_coverage, 3),
        "alignmentAnchorMedian": round(statistics.median(alignment_anchor_counts), 1)
        if alignment_anchor_counts
        else 0,
        "mechanicComparisons": len(mechanic_residuals_ms),
        "mechanicExpected": mechanic_expected,
        "mechanicMatchCoverage": round(mechanic_coverage, 3),
        "mechanicMedianError": round(mechanic_median_error, 2),
        "mechanicP90Error": round(mechanic_p90_error, 2),
        "damagePeakComparisons": len(damage_peak_residuals_ms),
        "damagePeakExpected": damage_peak_expected,
        "damagePeakMatchCoverage": round(damage_peak_coverage, 3),
        "damagePeakMedianError": round(damage_peak_median_error, 2),
        "damageCurveSimilarity": round(damage_curve_similarity, 3),
        "syncAnchorCount": sync_anchor_count,
        "healerSampleCount": healer_sample_count,
        "missingHealerSpecs": missing_healer_specs,
        "healerAnchoredSampleCoverage": round(healer_anchor_coverage, 3),
        "healerAnchorMedian": round(statistics.median(healer_anchor_matches), 1)
        if healer_anchor_matches
        else 0,
        "dpsSampleCount": dps_sample_count,
        "dpsAnchoredSampleCoverage": round(dps_anchor_coverage, 3),
        "dpsAnchorMedian": round(statistics.median(dps_anchor_matches), 1)
        if dps_anchor_matches else 0,
    }
    if failures:
        report["failures"] = failures
    model["validation"] = report
    return report


def _optimize_cooldown_schedule(
    model: dict[str, Any],
    candidates: list[dict[str, Any]],
    casts_by_spell: dict[int, dict[int, list[float]]],
    sample_count: int,
) -> list[dict[str, Any]]:
    damage = model.get("damage") or {}
    interval = max(0.1, _number(damage.get("interval"), INTERVAL_MS / 1000.0))
    damage_values = [max(0.0, _number(value)) for value in damage.get("values") or []]
    radius = max(1, int(round((COOLDOWN_ALIGNMENT_TOLERANCE_MS / 2000.0) / interval)))
    grouped: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for candidate in candidates:
        grouped[int(_number(candidate.get("spellID")))].append(candidate)

    selected: list[dict[str, Any]] = []
    for spell_id, spell_candidates in grouped.items():
        cast_times = casts_by_spell.get(spell_id) or {}
        use_counts = Counter(
            len(cast_times.get(sample_index) or [])
            for sample_index in range(sample_count)
        )
        typical_uses = max(
            1, max(use_counts, key=lambda count: (use_counts[count], count))
        )
        ordered = sorted(spell_candidates, key=lambda item: item["t"])
        repeat_gaps = [
            right - left
            for times in cast_times.values()
            for left, right in zip(sorted(times), sorted(times)[1:])
            if right > left
        ]
        # Observed raw intervals include talents/CD reductions; never infer a
        # shorter cooldown from a compressed reference phase. Allow bin jitter.
        minimum_gap = max(0.0, min(repeat_gaps) - INTERVAL_MS / 1000.0) if repeat_gaps else 0.0
        times = [float(item["t"]) for item in ordered]
        usage_weights = []
        damage_weights = []
        for item in ordered:
            center = int(round(float(item["t"]) / interval))
            load = sum(damage_values[max(0, center - radius) : center + radius + 1])
            usage_weights.append(_number(item.get("usage")))
            damage_weights.append(
                max(1.0, load) / (1.0 + _number(item.get("spread")) / 12.0)
            )

        @lru_cache(maxsize=None)
        def choose(index: int, remaining: int) -> tuple[int, float, float, tuple[int, ...]]:
            if index >= len(ordered) or remaining <= 0:
                return 0, 0.0, 0.0, ()
            skipped = choose(index + 1, remaining)
            next_index = bisect.bisect_left(
                times, times[index] + minimum_gap, index + 1
            )
            count, usage, damage_score, indexes = choose(next_index, remaining - 1)
            taken = (
                count + 1,
                usage + usage_weights[index],
                damage_score + damage_weights[index],
                (index, *indexes),
            )
            return taken if taken[:3] > skipped[:3] else skipped

        selected.extend(ordered[index] for index in choose(0, typical_uses)[3])
    return sorted(selected, key=lambda item: item["t"])


def apply_healer_profiles(
    model: dict[str, Any],
    samples_by_spec: dict[int, list[dict[str, Any]]],
    *,
    cooldown_usage_floor: float = 0.10,
    max_talent_builds: int = 3,
    ranking_metric: str = "hps",
) -> dict[str, Any]:
    """Attach ranked cooldown, talent, and stat aggregates to an encounter model."""

    phase_occurrences: Counter[int] = Counter()
    phase_starts: dict[str, int] = {}
    phase_by_key: dict[str, dict[str, Any]] = {}
    ordered_phase_keys: list[str] = []
    for phase in model.get("phases") or []:
        stage = int(_number(phase.get("stage"), phase.get("index", 1)))
        phase_occurrences[stage] += 1
        key = f"{stage}:{phase_occurrences[stage]}"
        phase_starts[key] = int(round(_number(phase.get("t")) * 1000.0))
        phase_by_key[key] = phase
        ordered_phase_keys.append(key)

    phase_durations: dict[str, float] = {}
    model_duration_ms = _number(model.get("duration")) * 1000.0
    for index, key in enumerate(ordered_phase_keys):
        start_ms = phase_starts[key]
        end_ms = (
            phase_starts[ordered_phase_keys[index + 1]]
            if index + 1 < len(ordered_phase_keys)
            else model_duration_ms
        )
        phase_durations[key] = max(float(INTERVAL_MS), end_ms - start_ms)

    encounter_id = int(_number(model.get("encounterID")))
    difficulty_id = int(_number(model.get("wclDifficultyID")))
    profiles: dict[int, dict[str, Any]] = {}
    cooldowns_by_spec: dict[int, list[dict[str, Any]]] = {}

    for spec_id, samples in sorted(samples_by_spec.items()):
        if not samples:
            continue

        cooldown_groups: dict[
            tuple[str, int], list[tuple[int, dict[str, Any]]]
        ] = defaultdict(list)
        raw_casts_by_spell: dict[int, dict[int, list[float]]] = defaultdict(
            lambda: defaultdict(list)
        )
        for sample_index, sample in enumerate(samples):
            source_starts = {}
            source_cursor = 0.0
            for segment in sample.get("segments") or []:
                source_starts[segment["key"]] = source_cursor
                source_cursor += _number(segment.get("duration_ms"))
            phase_mappers = {
                phase_key: _phase_time_mapper(
                    model,
                    sample,
                    phase_key,
                    phase_starts[phase_key],
                    phase_durations[phase_key],
                    int(_number(phase_by_key[phase_key].get("index"))),
                )[0]
                for phase_key in ordered_phase_keys
            }
            for cooldown in sample.get("cooldowns") or []:
                if cooldown.get("phase_key") not in phase_starts:
                    continue
                if int(_number(cooldown.get("spec_id"))) != spec_id:
                    continue
                key = (
                    str(cooldown["phase_key"]),
                    int(_number(cooldown.get("spell_id"))),
                )
                aligned_cooldown = dict(cooldown)
                aligned_cooldown["relative_ms"] = phase_mappers[str(cooldown["phase_key"])](
                    _number(cooldown.get("relative_ms"))
                )
                if not 0 <= aligned_cooldown["relative_ms"] < phase_durations[key[0]]:
                    continue
                cooldown_groups[key].append((sample_index, aligned_cooldown))
                raw_casts_by_spell[key[1]][sample_index].append(
                    (
                        source_starts[str(cooldown["phase_key"])]
                        + _number(cooldown.get("relative_ms"))
                    )
                    / 1000.0
                )

        minimum_records = min(2, len(samples))
        spec_cooldowns: list[dict[str, Any]] = []
        for (phase_key, spell_id), records in cooldown_groups.items():
            aligned_clusters = _cluster_records_by_time(
                records, COOLDOWN_ALIGNMENT_TOLERANCE_MS
            )
            for occurrence, cluster_records in enumerate(aligned_clusters, start=1):
                sample_ids = {sample_index for sample_index, _ in cluster_records}
                usage = len(sample_ids) / len(samples)
                if usage < cooldown_usage_floor or len(sample_ids) < minimum_records:
                    continue
                relative_times = [
                    record["relative_ms"] / 1000.0 for _, record in cluster_records
                ]
                first_record = cluster_records[0][1]
                item = {
                    "id": f"wcl_cd_{encounter_id}_{difficulty_id}_{phase_key}_{spell_id}_{occurrence}",
                    "t": round(
                        phase_starts[phase_key] / 1000.0
                        + statistics.median(relative_times),
                        2,
                    ),
                    "phase": phase_by_key[phase_key]["index"],
                    "specID": spec_id,
                    "spellID": spell_id,
                    "label": first_record["label"],
                    "category": first_record.get("category", "major"),
                    "defaultShown": first_record.get("default_shown", True),
                    "usage": round(usage, 3),
                    "spread": round(_population_spread(relative_times), 2),
                }
                if first_record.get("icon"):
                    item["icon"] = first_record["icon"]
                spec_cooldowns.append(item)
        spec_cooldowns = _optimize_cooldown_schedule(
            model, spec_cooldowns, raw_casts_by_spell, len(samples)
        )

        profiles_data = [sample.get("profile") or {} for sample in samples]
        first_profile = next((profile for profile in profiles_data if profile), {})
        secondary_stats: dict[str, int] = {}
        for stat_key in ("criticalStrike", "haste", "mastery", "versatility"):
            values = [
                float(profile["secondaryStats"][stat_key])
                for profile in profiles_data
                if isinstance(profile.get("secondaryStats", {}).get(stat_key), (int, float))
            ]
            if values:
                secondary_stats[stat_key] = int(round(statistics.fmean(values)))

        item_levels = [
            float(profile["itemLevel"])
            for profile in profiles_data
            if _number(profile.get("itemLevel")) > 0
        ]

        signatures: Counter[tuple[tuple[int, int, int], ...]] = Counter()
        talent_records: dict[int, list[tuple[int, int]]] = defaultdict(list)
        for profile in profiles_data:
            signature_items = []
            seen_talents = set()
            for talent in profile.get("talents") or []:
                talent_id = int(_number(talent.get("talentID")))
                points = int(_number(talent.get("points")))
                node_id = int(_number(talent.get("nodeID")))
                if talent_id <= 0 or points <= 0:
                    continue
                signature_items.append((talent_id, points, node_id))
                if talent_id not in seen_talents:
                    talent_records[talent_id].append((points, node_id))
                    seen_talents.add(talent_id)
            if signature_items:
                signatures[tuple(sorted(signature_items))] += 1

        talent_builds = []
        for signature, count in signatures.most_common(max_talent_builds):
            talents = []
            for talent_id, points, node_id in signature:
                talent = {"talentID": talent_id, "points": points}
                if node_id > 0:
                    talent["nodeID"] = node_id
                talents.append(talent)
            talent_builds.append(
                {
                    "sampleCount": count,
                    "usage": round(count / len(samples), 3),
                    "talents": talents,
                }
            )

        talent_usage = []
        for talent_id, records in talent_records.items():
            points = [record[0] for record in records]
            node_ids = [record[1] for record in records if record[1] > 0]
            item = {
                "talentID": talent_id,
                "usage": round(len(records) / len(samples), 3),
                "averagePoints": round(statistics.fmean(points), 2),
            }
            if node_ids:
                item["nodeID"] = Counter(node_ids).most_common(1)[0][0]
            talent_usage.append(item)
        talent_usage.sort(key=lambda item: (-item["usage"], item["talentID"]))

        profile = {
            "specID": spec_id,
            "className": first_profile.get("className") or "",
            "specName": first_profile.get("specName") or "",
            "rankingMetric": ranking_metric,
            "sampleCount": len(samples),
            "statSampleCount": sum(1 for profile in profiles_data if profile.get("secondaryStats")),
            "secondaryStatsUnit": "rating",
            "secondaryStats": secondary_stats,
            "talentBuilds": talent_builds,
            "talentUsage": talent_usage,
        }
        if item_levels:
            profile["averageItemLevel"] = round(statistics.fmean(item_levels), 1)

        profiles[spec_id] = profile
        cooldowns_by_spec[spec_id] = spec_cooldowns

    if profiles:
        if ranking_metric == "hps":
            model["healerRankingMetric"] = "hps"
            model["cooldownsBySpec"] = cooldowns_by_spec
        else:
            model.setdefault("cooldownsBySpec", {}).update(cooldowns_by_spec)
        model["cooldownTimingAlignment"] = "phase-cast-anchored-v2"
        model["healerProfilesBySpec" if ranking_metric == "hps" else "dpsProfilesBySpec"] = profiles
        # cooldownsBySpec is the canonical generated timeline. Keeping copies
        # in both the profile and the legacy flat list roughly triples the Lua
        # pack size now that semi cooldowns are included.
        model["cooldowns"] = []
    return model


def apply_dps_profiles(
    model: dict[str, Any], samples_by_spec: dict[int, list[dict[str, Any]]]
) -> dict[str, Any]:
    return apply_healer_profiles(model, samples_by_spec, ranking_metric="dps")


def _quote_lua(value: str) -> str:
    return (
        '"'
        + value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\r", "\\r")
        .replace("\n", "\\n")
        .replace("\t", "\\t")
        + '"'
    )


def _lua_key(key: Any) -> str:
    if isinstance(key, int):
        return f"[{key}]"
    text = str(key)
    if text.isidentifier() and text.isascii():
        return text
    return f"[{_quote_lua(text)}]"


def to_lua(value: Any, indent: int = 0) -> str:
    """Serialize JSON-like data into deterministic, WoW-compatible Lua source."""

    prefix = "    " * indent
    child_prefix = "    " * (indent + 1)
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, str):
        return _quote_lua(value)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ValueError("non-finite numbers cannot be serialized to Lua")
        return str(int(value)) if value.is_integer() else f"{value:.3f}".rstrip("0").rstrip(".")
    if isinstance(value, (list, tuple)):
        if not value:
            return "{}"
        if all(isinstance(item, (int, float)) and not isinstance(item, bool) for item in value):
            rows = []
            for start in range(0, len(value), 12):
                rows.append(child_prefix + ", ".join(to_lua(item) for item in value[start : start + 12]))
            return "{\n" + ",\n".join(rows) + "\n" + prefix + "}"
        rows = [child_prefix + to_lua(item, indent + 1) for item in value]
        return "{\n" + ",\n".join(rows) + "\n" + prefix + "}"
    if isinstance(value, dict):
        if not value:
            return "{}"
        rows = []
        for key in sorted(value, key=lambda item: (isinstance(item, str), str(item))):
            rows.append(
                child_prefix + _lua_key(key) + " = " + to_lua(value[key], indent + 1)
            )
        return "{\n" + ",\n".join(rows) + "\n" + prefix + "}"
    raise TypeError(f"unsupported Lua value: {type(value).__name__}")


def render_data_pack(models: Iterable[dict[str, Any]]) -> str:
    ordered = sorted(models, key=lambda model: (model["zoneID"], model["encounterID"], model["difficultyID"]))
    lines = [
        "local _, ns = ...",
        "",
        "-- Generated by tools/update_wcl.py. Do not edit by hand.",
    ]
    for model in ordered:
        key = f"wcl:{model['encounterID']}:{model['difficultyID']}"
        lines.extend(
            [
                "",
                f"ns.Registry:Register({_quote_lua(key)}, {to_lua(model)})",
            ]
        )
    lines.append("")
    return "\n".join(lines)

from __future__ import annotations

import sys
import unittest
from pathlib import Path


TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))

from wcl_pipeline import (  # noqa: E402
    DPS_COOLDOWNS_BY_SPEC,
    DPS_SPECS,
    _icon_path,
    _mapped_damage_curve,
    _optimize_cooldown_schedule,
    _phase_time_mapper,
    aggregate_samples,
    apply_dps_profiles,
    apply_healer_profiles,
    build_healer_sample,
    build_sample,
    render_data_pack,
    validate_model_accuracy,
)


class WCLPipelineTests(unittest.TestCase):
    def test_wcl_icon_filenames_are_exported_as_wow_textures(self):
        for file_id in (8026697, 8026696, 8026698):
            self.assertEqual(_icon_path(f"{file_id}.jpg"), file_id)
            self.assertEqual(_icon_path(str(file_id)), file_id)
        self.assertEqual(_icon_path("spell_nature_tranquility.jpg"),
                         r"Interface\Icons\spell_nature_tranquility")
        self.assertEqual(_icon_path(r"Interface\Icons\spell_nature_tranquility"),
                         r"Interface\Icons\spell_nature_tranquility")
        self.assertIsNone(_icon_path(None))

    def test_dps_rankings_generate_profile_and_timeline_without_identity(self):
        self.assertEqual(len(DPS_SPECS), 27)
        self.assertEqual({spec["spec_id"] for spec in DPS_SPECS}, set(DPS_COOLDOWNS_BY_SPEC))
        fight = {
            "id": 11, "startTime": 1000, "endTime": 11000, "size": 20,
            "friendlyPlayers": [7],
            "phaseTransitions": [{"id": 1, "startTime": 1000}, {"id": 2, "startTime": 6000}],
        }
        sample = build_healer_sample(
            fight,
            {"actors": [{"id": 7, "name": "PrivateDps", "type": "Player", "subType": "DeathKnight"}],
             "abilities": [{"gameID": 51271, "name": "Fremdsprachiger Name", "icon": "spell_deathknight_pillaroffrost"}]},
            [{"timestamp": 2000, "type": "cast", "sourceID": 7, "abilityGameID": 51271}],
            [{"sourceID": 7, "specID": 251, "critSpell": 1111, "hasteSpell": 888,
              "mastery": 999, "versatilityDamageDone": 444,
              "talentTree": [{"id": 123, "rank": 1, "nodeID": 456}]}],
            {"name": "PrivateDps", "class": "DeathKnight", "spec": "Frost",
             "report": {"code": "PrivateReport"}},
            expected_spec_id=251,
        )
        model = aggregate_samples(
            [self._sample(fight_id=1, start=1000, phase_two=6000, end=11000)],
            encounter_id=3470, encounter_name="Boss", wcl_difficulty_id=4,
            zone_id=53, zone_name="Raid",
        )
        apply_dps_profiles(model, {251: [sample]})
        profile = model["dpsProfilesBySpec"][251]
        self.assertEqual(profile["rankingMetric"], "dps")
        self.assertEqual(profile["secondaryStats"]["versatility"], 444)
        self.assertEqual(model["cooldownsBySpec"][251][0]["spellID"], 51271)
        self.assertEqual(model["cooldownsBySpec"][251][0]["label"], "Pillar of Frost")
        self.assertEqual(len(model["cooldownsBySpec"][251]), 1)
        lua = render_data_pack([model])
        self.assertNotIn("PrivateDps", lua)
        self.assertNotIn("PrivateReport", lua)

    def test_phase_clock_does_not_scale_with_kill_duration(self):
        model = {
            "syncAnchors": [
                {"phase": 1, "bigWigsKey": 123, "syncT": time}
                for time in (30, 90, 150)
            ]
        }
        sample = {
            "segments": [{"key": "1:1", "duration_ms": 360000}],
            "boss_casts": [
                {"phase_key": "1:1", "spell_id": 123, "relative_ms": time * 1000, "type": "cast"}
                for time in (30, 90, 150, 210, 270, 330)
            ],
        }
        for anchors in (model, {}):
            mapper, _ = _phase_time_mapper(anchors, sample, "1:1", 0, 180000, 1)
            self.assertEqual(mapper(120000), 120000)
            self.assertEqual(mapper(240000), 240000)

    def test_damage_after_reference_end_is_not_piled_into_last_bin(self):
        sample = {"size": 20, "phase_damage": {"1:1": {0: 10, 100: 9000}}}
        curve = _mapped_damage_curve(sample, "1:1", lambda time: time, 1000, 500, 20)
        self.assertEqual(curve, [10, 0])

    def test_cooldown_spacing_is_checked_even_with_few_candidates(self):
        candidates = [
            {"spellID": 740, "t": time, "usage": usage}
            for time, usage in ((60, 0.4), (120, 0.8))
        ]
        casts = {740: {0: [0, 120], 1: [60, 180]}}
        selected = _optimize_cooldown_schedule({}, candidates, casts, 2)
        self.assertEqual([item["t"] for item in selected], [120])

    def _sample(self, *, fight_id: int, start: int, phase_two: int, end: int):
        fight = {
            "id": fight_id,
            "startTime": start,
            "endTime": end,
            "size": 20,
            "friendlyPlayers": list(range(1, 21)),
            "phaseTransitions": [
                {"id": 1, "startTime": start},
                {"id": 2, "startTime": phase_two},
            ],
        }
        master_data = {
            "abilities": [
                {"gameID": 999001, "name": "Raid Blast", "icon": "spell_shadow_shadowbolt"},
                {"gameID": 740, "name": "Tranquility", "icon": "spell_nature_tranquility"},
            ]
        }
        blast_time = phase_two + 1000
        damage = [
            {
                "timestamp": blast_time + target,
                "type": "damage",
                "targetID": target,
                "abilityGameID": 999001,
                "amount": 1000,
                "absorbed": 250,
            }
            for target in range(1, 6)
        ]
        casts = [
            {
                "timestamp": phase_two + 500,
                "type": "cast",
                "sourceID": 1,
                "abilityGameID": 740,
            }
        ]
        return build_sample(fight, master_data, damage, casts)

    def test_phase_relative_alignment_and_cooldowns(self):
        samples = [
            self._sample(fight_id=1, start=1000, phase_two=6000, end=11000),
            self._sample(fight_id=2, start=2000, phase_two=8000, end=14000),
        ]
        model = aggregate_samples(
            samples,
            encounter_id=3470,
            encounter_name="Example Boss",
            wcl_difficulty_id=5,
            zone_id=53,
            zone_name="Example Raid",
        )

        self.assertEqual(model["difficultyID"], 16)
        self.assertEqual(model["sampleCount"], 2)
        self.assertEqual(model["phases"][1]["t"], 5.5)
        self.assertEqual(len(model["mechanics"]), 1)
        self.assertAlmostEqual(model["mechanics"][0]["t"], 6.5, places=1)
        self.assertEqual(model["mechanics"][0]["avgDamage"], 6250)
        self.assertEqual(model["cooldownsBySpec"][105][0]["spellID"], 740)
        self.assertAlmostEqual(model["cooldownsBySpec"][105][0]["t"], 6.0, places=1)
        self.assertGreater(model["damage"]["max"], 0)

        lua = render_data_pack([model])
        self.assertIn('ns.Registry:Register("wcl:3470:16"', lua)
        self.assertIn("cooldownsBySpec", lua)
        self.assertNotIn("client_secret", lua.lower())

    def test_single_cooldown_cast_is_filtered_from_top_ten_style_sample(self):
        samples = [
            self._sample(fight_id=1, start=1000, phase_two=6000, end=11000),
            self._sample(fight_id=2, start=2000, phase_two=8000, end=14000),
            self._sample(fight_id=3, start=3000, phase_two=9000, end=15000),
        ]
        samples[1]["cooldowns"] = []
        samples[2]["cooldowns"] = []

        model = aggregate_samples(
            samples,
            encounter_id=3470,
            encounter_name="Example Boss",
            wcl_difficulty_id=5,
            zone_id=53,
            zone_name="Example Raid",
        )

        self.assertEqual(model["cooldowns"], [])
        self.assertEqual(model["cooldownsBySpec"], {})

    def test_skipped_cooldown_cast_does_not_shift_later_occurrences(self):
        def sample(fight_id, cast_seconds):
            fight = {
                "id": fight_id,
                "startTime": 0,
                "endTime": 120000,
                "size": 20,
                "friendlyPlayers": list(range(1, 21)),
                "phaseTransitions": [{"id": 1, "startTime": 0}],
            }
            master_data = {
                "abilities": [
                    {"gameID": 740, "name": "Tranquility", "icon": "spell_nature_tranquility"}
                ]
            }
            casts = [
                {
                    "timestamp": seconds * 1000,
                    "type": "cast",
                    "sourceID": 1,
                    "abilityGameID": 740,
                }
                for seconds in cast_seconds
            ]
            return build_sample(fight, master_data, [], casts)

        model = aggregate_samples(
            [sample(1, (10, 70)), sample(2, (70,)), sample(3, (11, 71))],
            encounter_id=3470,
            encounter_name="Example Boss",
            wcl_difficulty_id=4,
            zone_id=53,
            zone_name="Example Raid",
        )

        cooldowns = model["cooldownsBySpec"][105]
        self.assertEqual(len(cooldowns), 2)
        self.assertAlmostEqual(cooldowns[0]["t"], 10.5, places=1)
        self.assertAlmostEqual(cooldowns[0]["usage"], 2 / 3, places=3)
        self.assertAlmostEqual(cooldowns[1]["t"], 70.0, places=1)
        self.assertEqual(cooldowns[1]["usage"], 1.0)

    def test_holy_priest_halo_is_collected_as_a_semi_cooldown(self):
        fight = {
            "id": 1,
            "startTime": 0,
            "endTime": 30000,
            "size": 20,
            "friendlyPlayers": list(range(1, 21)),
            "phaseTransitions": [{"id": 1, "startTime": 0}],
        }
        master_data = {
            "abilities": [
                {"gameID": 120517, "name": "Halo", "icon": "ability_priest_halo"}
            ]
        }
        sample = build_sample(
            fight,
            master_data,
            [],
            [{"timestamp": 9000, "type": "cast", "sourceID": 1, "abilityGameID": 120517}],
            expected_spec_id=257,
        )

        self.assertEqual(len(sample["cooldowns"]), 1)
        self.assertEqual(sample["cooldowns"][0]["spell_id"], 120517)
        self.assertEqual(sample["cooldowns"][0]["category"], "semi")
        self.assertTrue(sample["cooldowns"][0]["default_shown"])

    def test_boss_cast_spell_is_exported_as_bigwigs_alignment_key(self):
        fight = {
            "id": 1,
            "startTime": 0,
            "endTime": 30000,
            "size": 20,
            "friendlyPlayers": list(range(1, 21)),
            "phaseTransitions": [{"id": 1, "startTime": 0}],
        }
        master_data = {
            "actors": [
                {"id": -1, "name": "Environment", "type": "NPC", "subType": "Boss"},
                {"id": 100, "name": "Example Boss", "type": "NPC", "subType": "Boss"},
            ],
            "abilities": [
                {"gameID": 888001, "name": "Boss Cast", "icon": "spell_fire_fire"},
                {"gameID": 999001, "name": "Raid Blast", "icon": "spell_shadow_shadowbolt"},
            ]
        }
        damage = [
            {
                "timestamp": 10000 + target,
                "type": "damage",
                "sourceID": 100,
                "targetID": target,
                "abilityGameID": 999001,
                "amount": 1000,
            }
            for target in range(1, 6)
        ]
        casts = [
            {
                "timestamp": 9500,
                "type": "cast",
                "sourceID": -1,
                "abilityGameID": 145629,
            },
            {
                "timestamp": 9000,
                "type": "cast",
                "sourceID": 100,
                "abilityGameID": 888001,
            }
        ]
        samples = [build_sample(fight, master_data, damage, casts) for _ in range(2)]
        model = aggregate_samples(
            samples,
            encounter_id=3470,
            encounter_name="Example Boss",
            wcl_difficulty_id=4,
            zone_id=53,
            zone_name="Example Raid",
        )

        self.assertEqual(model["mechanics"][0]["bigWigsKey"], 888001)
        self.assertAlmostEqual(model["mechanics"][0]["syncT"], 9.0, places=1)
        self.assertEqual(model["timingAlignment"], "phase-cast-anchored-v2")

    def test_top_healer_cooldown_is_warped_to_the_model_mechanic_clock(self):
        model = {
            "duration": 100.0,
            "encounterID": 3470,
            "wclDifficultyID": 4,
            "phases": [{"index": 1, "stage": 1, "t": 0.0, "label": "P1"}],
            "mechanics": [
                {
                    "phase": 1,
                    "t": 50.0,
                    "syncT": 45.0,
                    "bigWigsKey": 888001,
                }
            ],
        }

        healer_samples = []
        for fight_id in (1, 2):
            fight = {
                "id": fight_id,
                "startTime": 0,
                "endTime": 120000,
                "size": 20,
                "friendlyPlayers": [7],
                "phaseTransitions": [{"id": 1, "startTime": 0}],
            }
            master_data = {
                "actors": [
                    {"id": 7, "name": "PrivateHealer", "type": "Player", "subType": "Druid"},
                    {"id": 100, "name": "Example Boss", "type": "NPC", "subType": "Boss"},
                ],
                "abilities": [
                    {"gameID": 740, "name": "Tranquility", "icon": "spell_nature_tranquility"},
                    {"gameID": 888001, "name": "Boss Cast", "icon": "spell_fire_fire"},
                ],
            }
            healer_samples.append(
                build_healer_sample(
                    fight,
                    master_data,
                    [{"timestamp": 62000, "type": "cast", "sourceID": 7, "abilityGameID": 740}],
                    [{"sourceID": 7, "specID": 105}],
                    {"name": "PrivateHealer", "class": "Druid", "spec": "Restoration"},
                    expected_spec_id=105,
                    hostile_cast_events=[
                        {
                            "timestamp": 60000,
                            "type": "cast",
                            "sourceID": 100,
                            "abilityGameID": 888001,
                        }
                    ],
                )
            )

        apply_healer_profiles(model, {105: healer_samples})

        cooldown = model["cooldownsBySpec"][105][0]
        self.assertAlmostEqual(cooldown["t"], 47.0, places=1)
        self.assertEqual(model["cooldownTimingAlignment"], "phase-cast-anchored-v2")

    def test_split_single_use_cooldown_uses_the_most_common_time_cluster(self):
        damage = [0] * 180
        damage[60] = 10
        damage[120] = 100
        model = {
            "duration": 180.0,
            "encounterID": 3470,
            "wclDifficultyID": 4,
            "phases": [{"index": 1, "stage": 1, "t": 0.0, "label": "P1"}],
            "mechanics": [],
            "damage": {"interval": 1.0, "values": damage},
        }
        samples = []
        for index in range(10):
            samples.append(
                {
                    "segments": [{"key": "1:1", "duration_ms": 180000}],
                    "boss_casts": [],
                    "cooldowns": [
                        {
                            "phase_key": "1:1",
                            "spell_id": 740,
                            "spec_id": 105,
                            "relative_ms": 60000 if index < 6 else 120000,
                            "label": "Tranquility",
                            "category": "major",
                            "default_shown": True,
                        }
                    ],
                    "profile": {"specID": 105},
                }
            )

        apply_healer_profiles(model, {105: samples})

        cooldowns = model["cooldownsBySpec"][105]
        self.assertEqual(len(cooldowns), 1)
        self.assertEqual(cooldowns[0]["t"], 60.0)

    def test_healer_profiles_include_stats_talents_and_no_identity(self):
        base_samples = [
            self._sample(fight_id=1, start=1000, phase_two=6000, end=11000),
            self._sample(fight_id=2, start=2000, phase_two=8000, end=14000),
        ]
        model = aggregate_samples(
            base_samples,
            encounter_id=3470,
            encounter_name="Example Boss",
            wcl_difficulty_id=4,
            zone_id=53,
            zone_name="Example Raid",
        )

        healer_samples = []
        for index, (crit, haste, mastery, versatility) in enumerate(
            ((1000, 600, 1200, 200), (1200, 800, 1400, 300)),
            start=1,
        ):
            start = index * 1000
            phase_two = start + 5000 + ((index - 1) * 1000)
            fight = {
                "id": index + 10,
                "startTime": start,
                "endTime": phase_two + 5000,
                "size": 20,
                "friendlyPlayers": list(range(1, 21)),
                "phaseTransitions": [
                    {"id": 1, "startTime": start},
                    {"id": 2, "startTime": phase_two},
                ],
            }
            master_data = {
                "actors": [
                    {"id": 7, "name": f"PrivateHealer{index}", "type": "Player", "subType": "Druid"}
                ],
                "abilities": [
                    {"gameID": 740, "name": "Tranquility", "icon": "spell_nature_tranquility"}
                ],
            }
            casts = [
                {
                    "timestamp": phase_two + 500,
                    "type": "cast",
                    "sourceID": 7,
                    "abilityGameID": 740,
                }
            ]
            combatants = [
                {
                    "sourceID": 7,
                    "specID": 105,
                    "critSpell": crit,
                    "hasteSpell": haste,
                    "mastery": mastery,
                    "versatilityHealingDone": versatility,
                    "gear": [
                        {"itemLevel": 310 + index},
                        {"itemLevel": 312 + index},
                    ],
                    "talentTree": [
                        {"id": 100001, "rank": 1, "nodeID": 200001},
                        {"id": 100002 + index, "rank": 1, "nodeID": 200002},
                    ],
                }
            ]
            ranking = {
                "name": f"PrivateHealer{index}",
                "class": "Druid",
                "spec": "Restoration",
                "bracketData": 310 + index,
                "report": {"code": f"PrivateReport{index}", "fightID": index + 10},
            }
            healer_samples.append(
                build_healer_sample(
                    fight,
                    master_data,
                    casts,
                    combatants,
                    ranking,
                    expected_spec_id=105,
                )
            )

        apply_healer_profiles(model, {105: healer_samples})
        profile = model["healerProfilesBySpec"][105]
        self.assertEqual(profile["sampleCount"], 2)
        self.assertEqual(profile["statSampleCount"], 2)
        self.assertEqual(profile["secondaryStats"]["criticalStrike"], 1100)
        self.assertEqual(profile["secondaryStats"]["haste"], 700)
        self.assertEqual(profile["secondaryStats"]["mastery"], 1300)
        self.assertEqual(profile["secondaryStats"]["versatility"], 250)
        self.assertEqual(profile["averageItemLevel"], 312.5)
        self.assertEqual(len(profile["talentBuilds"]), 2)
        self.assertEqual(model["cooldownsBySpec"][105][0]["spellID"], 740)
        self.assertNotIn("cooldowns", profile)
        self.assertEqual(model["cooldowns"], [])

        lua = render_data_pack([model])
        self.assertIn("healerProfilesBySpec", lua)
        self.assertIn("secondaryStats", lua)
        self.assertIn("talentBuilds", lua)
        self.assertNotIn("PrivateHealer", lua)
        self.assertNotIn("PrivateReport", lua)

    def test_source_log_validation_compares_independent_timing(self):
        training_samples = [
            self._sample(fight_id=1, start=1000, phase_two=6000, end=11000),
            self._sample(fight_id=2, start=2000, phase_two=8000, end=14000),
        ]
        holdout = self._sample(fight_id=3, start=3000, phase_two=9500, end=15500)
        model = aggregate_samples(
            training_samples,
            encounter_id=3470,
            encounter_name="Example Boss",
            wcl_difficulty_id=4,
            zone_id=53,
            zone_name="Example Raid",
        )

        report = validate_model_accuracy(model, training_samples, [holdout])

        self.assertEqual(report["holdoutSampleCount"], 1)
        self.assertEqual(report["phaseCoverage"], 1.0)
        self.assertEqual(report["mechanicComparisons"], 1)
        self.assertLess(report["mechanicMedianError"], 0.5)
        self.assertIn(report["status"], {"passed", "limited"})
        self.assertEqual(model["validation"], report)

    def test_source_log_validation_rejects_incompatible_phase_data(self):
        training_samples = [
            self._sample(fight_id=1, start=1000, phase_two=6000, end=11000),
            self._sample(fight_id=2, start=2000, phase_two=8000, end=14000),
        ]
        model = aggregate_samples(
            training_samples,
            encounter_id=3470,
            encounter_name="Example Boss",
            wcl_difficulty_id=4,
            zone_id=53,
            zone_name="Example Raid",
        )
        incompatible = dict(training_samples[0])
        incompatible["segments"] = [
            {
                "key": "9:1",
                "phase_id": 9,
                "occurrence": 1,
                "start_ms": 1000,
                "end_ms": 11000,
                "duration_ms": 10000,
            }
        ]

        report = validate_model_accuracy(model, training_samples, [incompatible])

        self.assertEqual(report["status"], "failed")
        self.assertTrue(any("phase coverage" in failure for failure in report["failures"]))

    def test_source_log_validation_rejects_unanchored_dps_samples(self):
        sample = self._sample(fight_id=1, start=1000, phase_two=6000, end=11000)
        model = aggregate_samples(
            [sample], encounter_id=3470, encounter_name="Example Boss",
            wcl_difficulty_id=4, zone_id=53, zone_name="Example Raid",
        )
        model["syncAnchors"] = [
            {"phase": 1, "bigWigsKey": 900000 + index, "syncT": index}
            for index in range(1, 5)
        ]

        report = validate_model_accuracy(
            model, [sample], dps_samples_by_spec={251: [sample] * 4}
        )

        self.assertEqual(report["dpsSampleCount"], 4)
        self.assertEqual(report["dpsAnchoredSampleCoverage"], 0.0)
        self.assertEqual(report["status"], "failed")
        self.assertTrue(any("DPS anchor coverage" in failure for failure in report["failures"]))

    def test_source_log_validation_allows_complete_branching_phase_layout(self):
        training_samples = [
            self._sample(fight_id=1, start=1000, phase_two=6000, end=11000),
            self._sample(fight_id=2, start=2000, phase_two=8000, end=14000),
        ]
        model = aggregate_samples(
            training_samples,
            encounter_id=3470,
            encounter_name="Example Boss",
            wcl_difficulty_id=4,
            zone_id=53,
            zone_name="Example Raid",
        )
        branched = dict(training_samples[0])
        branched["segments"] = [dict(segment) for segment in branched["segments"]]
        branched["segments"][1]["key"] = "3:1"

        report = validate_model_accuracy(model, training_samples, [branched])

        self.assertEqual(report["phaseCoverage"], 1.0)
        self.assertFalse(any("phase coverage" in failure for failure in report.get("failures", [])))


if __name__ == "__main__":
    unittest.main()

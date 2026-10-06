from __future__ import annotations

import io
import os
import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest import mock


TOOLS_DIR = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS_DIR))
import update_wcl

from update_wcl import (  # noqa: E402
    HEALER_SPECS,
    WCLAuthenticationExpired,
    WCLClient,
    WCLFailure,
    _filter_incomplete_phase_samples,
    _incomplete_dps_profile_specs,
    _validate_generated_models,
)


class _Response:
    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self) -> bytes:
        return b'{"ok":true}'


class WCLClientRequestTests(unittest.TestCase):
    def test_backfill_keeps_ten_training_kills_and_independent_holdouts(self) -> None:
        rankings = [{"report": {"code": "test", "fightID": rank}} for rank in range(1, 21)]
        client = mock.Mock()
        client.zone.return_value = {"id": 53, "name": "Test", "encounters": [{"id": 3470, "name": "Boss"}]}
        client.top_rankings.side_effect = [rankings[:15], rankings]
        client.top_healer_rankings.return_value = []
        client.top_character_rankings.return_value = []

        def build_sample(_client, ranking):
            rank = ranking["report"]["fightID"]
            if rank == 16:
                raise WCLFailure("unavailable")
            return {"rank": rank, "segments": [{}] * (1 if rank <= 5 else 3)}

        args = update_wcl.build_parser().parse_args(["update", "--zone", "53"])
        with mock.patch.object(update_wcl, "WCLClient", return_value=client), mock.patch.object(
            update_wcl, "_build_ranked_sample", side_effect=build_sample
        ) as build, mock.patch.object(update_wcl, "aggregate_samples", return_value={}), mock.patch.object(
            update_wcl, "apply_healer_profiles"
        ), mock.patch.object(update_wcl, "validate_model_accuracy") as validate, mock.patch.object(
            update_wcl, "_validate_generated_models"
        ), mock.patch.object(update_wcl, "render_data_pack", return_value="test"), mock.patch.object(
            update_wcl, "_atomic_write"
        ), mock.patch("sys.stdout", new=io.StringIO()), mock.patch("sys.stderr", new=io.StringIO()):
            validate.return_value = dict(status="passed", phaseCoverage=1, mechanicMedianError=0,
                mechanicMatchCoverage=1, damagePeakMedianError=0, damagePeakMatchCoverage=1,
                damageCurveSimilarity=1, healerAnchoredSampleCoverage=1,
                dpsAnchoredSampleCoverage=1)
            self.assertEqual(update_wcl.update(args), 0)
        self.assertEqual([item["rank"] for item in validate.call_args.args[1]], list(range(6, 16)))
        self.assertEqual([item["rank"] for item in validate.call_args.args[2]], [17, 18])
        self.assertEqual(build.call_count, 18, "do not download duplicate or unneeded backfill reports")

    def test_incomplete_phase_metadata_is_backfilled_before_selection(self) -> None:
        complete = lambda rank: {
            "rank": rank,
            "segments": [{"key": key} for key in ("1:1", "2:1", "3:1")],
        }
        incomplete = {"rank": 2, "segments": [{"key": "1:1"}]}

        filtered, reference = _filter_incomplete_phase_samples(
            [complete(1), incomplete, complete(3)]
        )

        self.assertEqual(reference, 3)
        self.assertEqual([sample["rank"] for sample in filtered], [1, 3])

        variable_order = {"rank": 4, "segments": [{"key": str(index)} for index in range(3)]}
        self.assertEqual(
            len(_filter_incomplete_phase_samples([complete(1), variable_order])[0]),
            2,
        )

    def test_429_is_deferred_and_retried_instead_of_skipped(self) -> None:
        rate_limit_error = urllib.error.HTTPError(
            "https://example.invalid",
            429,
            "Too Many Requests",
            {"Retry-After": "2"},
            io.BytesIO(),
        )
        with tempfile.TemporaryDirectory() as directory, mock.patch.dict(
            os.environ,
            {"WCL_CLIENT_ID": "test-id", "WCL_CLIENT_SECRET": "test-secret"},
        ):
            client = WCLClient(Path(directory))
            with mock.patch.object(client, "_wait_for_request_slot"), mock.patch.object(
                client, "_defer_requests"
            ) as defer, mock.patch(
                "urllib.request.urlopen", side_effect=[rate_limit_error, _Response()]
            ):
                result = client._request_json(
                    "https://example.invalid",
                    body=b"{}",
                    headers={"Content-Type": "application/json"},
                )

        self.assertEqual(result, {"ok": True})
        defer.assert_called_once_with(2.0)

    def test_generated_model_validation_rejects_private_source_fields(self) -> None:
        model = {
            "schemaVersion": 2,
            "sampleCount": 10,
            "damage": {"values": [1, 2]},
            "healerProfilesBySpec": {
                int(spec["spec_id"]): {"sampleCount": 10} for spec in HEALER_SPECS
            },
            "validation": {"status": "passed"},
        }
        _validate_generated_models([model])

        model["healerProfilesBySpec"][105]["reportCode"] = "must-not-leak"
        with self.assertRaises(WCLFailure):
            _validate_generated_models([model])

    def test_partial_secondary_stats_require_explicit_dps_limitation(self) -> None:
        model = {
            "schemaVersion": 2,
            "sampleCount": 10,
            "damage": {"values": [1, 2]},
            "healerProfilesBySpec": {
                int(spec["spec_id"]): {"sampleCount": 10} for spec in HEALER_SPECS
            },
            "dpsProfilesBySpec": {
                1473: {
                    "sampleCount": 10,
                    "secondaryStats": {"criticalStrike": 912, "haste": 510, "mastery": 3533},
                    "talentBuilds": [{"talents": [{"talentID": 1}]}],
                },
            },
            "validation": {
                "status": "passed",
                "dpsCoverageStatus": "limited",
                "incompleteDpsProfileSpecs": [],
            },
        }
        self.assertEqual(_incomplete_dps_profile_specs(model), [1473])
        with self.assertRaisesRegex(WCLFailure, "inaccurate incomplete DPS profile metadata"):
            _validate_generated_models([model])
        model["validation"]["incompleteDpsProfileSpecs"] = [1473]
        _validate_generated_models([model])

    def test_generated_model_validation_allows_partial_limited_healer_coverage(self) -> None:
        model = {
            "schemaVersion": 2,
            "difficultyID": 16,
            "sampleCount": 4,
            "damage": {"values": [1, 2]},
            "healerProfilesBySpec": {105: {"sampleCount": 3}},
            "validation": {"status": "limited"},
        }
        _validate_generated_models([model])

        model["difficultyID"] = 15
        with self.assertRaisesRegex(WCLFailure, "outside Mythic difficulty"):
            _validate_generated_models([model])

        model["difficultyID"] = 16
        model["validation"]["status"] = "passed"
        with self.assertRaisesRegex(WCLFailure, "without all healer specializations"):
            _validate_generated_models([model])

    def test_generated_model_validation_rejects_failed_accuracy_gate(self) -> None:
        model = {
            "schemaVersion": 2,
            "sampleCount": 10,
            "damage": {"values": [1, 2]},
            "validation": {
                "status": "failed",
                "failures": ["mechanic timing drifted"],
            },
        }

        with self.assertRaisesRegex(WCLFailure, "mechanic timing drifted"):
            _validate_generated_models([model])

    def test_graphql_refreshes_an_expired_access_token_once(self) -> None:
        with tempfile.TemporaryDirectory() as directory, mock.patch.dict(
            os.environ,
            {"WCL_CLIENT_ID": "test-id", "WCL_CLIENT_SECRET": "test-secret"},
        ):
            client = WCLClient(Path(directory))
            client._access_token = "expired"
            with mock.patch.object(
                client,
                "_request_json",
                side_effect=[
                    WCLAuthenticationExpired("expired"),
                    {"data": {"ok": True}},
                ],
            ), mock.patch.object(client, "access_token", side_effect=["expired", "fresh"]):
                result = client.graphql("query Test { ok }")

        self.assertEqual(result, {"ok": True})


if __name__ == "__main__":
    unittest.main()

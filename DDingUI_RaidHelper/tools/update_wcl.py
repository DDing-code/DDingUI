#!/usr/bin/env python3
"""Download public Warcraft Logs kills and generate RaidHelper's Lua data pack."""

from __future__ import annotations

import argparse
import base64
import concurrent.futures
import gzip
import hashlib
import json
import os
import sys
import threading
import time
import urllib.error
import urllib.request
from collections import Counter
from pathlib import Path
from typing import Any

from wcl_pipeline import (
    DPS_SPECS,
    HEALER_SPECS,
    VALIDATION_MIN_PHASE_COVERAGE,
    aggregate_samples,
    apply_dps_profiles,
    apply_healer_profiles,
    build_healer_sample,
    build_sample,
    render_data_pack,
    validate_model_accuracy,
)


TOKEN_URL = "https://www.warcraftlogs.com/oauth/token"
GRAPHQL_URL = "https://www.warcraftlogs.com/api/v2/client"
USER_AGENT = "DDingUI-RaidHelper/0.1 (+public Warcraft Logs data pack generator)"
CACHE_VERSION = 1
RANKED_KILL_BACKFILL = 3
HEALER_RANKING_BACKFILL = 3
DEFAULT_VALIDATION_LIMIT = 2
REQUEST_START_INTERVAL = 0.15
MAX_RATE_LIMIT_WAIT = 3700

ADDON_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ADDON_ROOT / "Data" / "Generated.lua"
DEFAULT_CACHE = Path(__file__).resolve().parent / ".cache" / "wcl"


ZONE_QUERY = """
query RaidHelperZone($zoneID: Int!) {
  worldData {
    zone(id: $zoneID) {
      id
      name
      frozen
      difficulties { id name sizes }
      encounters { id journalID name }
    }
  }
}
"""

EXPANSIONS_QUERY = """
query RaidHelperExpansions {
  worldData {
    expansions {
      id
      name
      zones {
        id
        name
        frozen
        difficulties { id name sizes }
        encounters { id journalID name }
      }
    }
  }
}
"""

RANKINGS_QUERY = """
query RaidHelperRankings($encounterID: Int!, $difficulty: Int!, $page: Int!) {
  worldData {
    encounter(id: $encounterID) {
      id
      name
      fightRankings(difficulty: $difficulty, page: $page, metric: speed)
    }
  }
}
"""

CHARACTER_RANKINGS_QUERY = """
query RaidHelperHealerRankings(
  $encounterID: Int!,
  $difficulty: Int!,
  $page: Int!,
  $className: String!,
  $specName: String!,
  $metric: CharacterRankingMetricType!
) {
  worldData {
    encounter(id: $encounterID) {
      id
      name
      characterRankings(
        difficulty: $difficulty,
        page: $page,
        metric: $metric,
        className: $className,
        specName: $specName
      )
    }
  }
}
"""

METADATA_QUERY = """
query RaidHelperFightMetadata($code: String!, $fightIDs: [Int]) {
  reportData {
    report(code: $code) {
      fights(fightIDs: $fightIDs, translate: false) {
        id
        name
        encounterID
        difficulty
        kill
        startTime
        endTime
        size
        friendlyPlayers
        phaseTransitions { id startTime }
      }
      masterData(translate: false) {
        actors { id name type subType }
        abilities { gameID name icon }
      }
    }
  }
}
"""

EVENTS_QUERY = """
query RaidHelperFightEvents(
  $code: String!,
  $fightIDs: [Int],
  $dataType: EventDataType!,
  $hostilityType: HostilityType,
  $startTime: Float!,
  $endTime: Float!
) {
  reportData {
    report(code: $code) {
      events(
        fightIDs: $fightIDs,
        dataType: $dataType,
        hostilityType: $hostilityType,
        startTime: $startTime,
        endTime: $endTime,
        limit: 10000,
        translate: false,
        useActorIDs: true
      ) {
        data
        nextPageTimestamp
      }
    }
  }
}
"""


class WCLFailure(RuntimeError):
    pass


class WCLAuthenticationExpired(WCLFailure):
    pass


def _read_user_environment(name: str) -> str | None:
    value = os.environ.get(name)
    if value:
        return value.strip()
    if os.name != "nt":
        return None
    try:
        import winreg

        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment") as key:
            value, _ = winreg.QueryValueEx(key, name)
            return str(value).strip() or None
    except (FileNotFoundError, OSError):
        return None


def _json_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


class WCLClient:
    def __init__(self, cache_dir: Path, refresh: bool = False) -> None:
        self.client_id = _read_user_environment("WCL_CLIENT_ID")
        self.client_secret = _read_user_environment("WCL_CLIENT_SECRET")
        if not self.client_id or not self.client_secret:
            raise WCLFailure(
                "WCL_CLIENT_ID and WCL_CLIENT_SECRET are required. Run tools/configure_wcl.ps1 first."
            )
        self.cache_dir = cache_dir
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.refresh = refresh
        self._access_token: str | None = None
        self._cache_lock_guard = threading.Lock()
        self._cache_locks: dict[Path, threading.Lock] = {}
        self._written_cache_paths: set[Path] = set()
        self._request_gate = threading.Lock()
        self._next_request_at = 0.0
        self._rate_limited_until = 0.0

    def _wait_for_request_slot(self) -> None:
        """Space concurrent requests and honor a shared 429 cooldown."""
        while True:
            with self._request_gate:
                now = time.monotonic()
                target = max(self._next_request_at, self._rate_limited_until)
                if target <= now:
                    self._next_request_at = now + REQUEST_START_INTERVAL
                    return
                delay = target - now
            time.sleep(min(delay, 5.0))

    def _defer_requests(self, delay: float) -> None:
        delay = max(1.0, min(float(delay), MAX_RATE_LIMIT_WAIT))
        with self._request_gate:
            until = time.monotonic() + delay
            if until <= self._rate_limited_until:
                return
            self._rate_limited_until = until
        print(
            f"  Warcraft Logs rate limit reached; pausing requests for {int(delay + 0.5)}s",
            flush=True,
        )

    def _request_json(
        self,
        url: str,
        *,
        body: bytes,
        headers: dict[str, str],
        attempts: int = 5,
    ) -> dict[str, Any]:
        request = urllib.request.Request(url, data=body, headers=headers, method="POST")
        transient_attempt = 0
        rate_limit_attempt = 0
        rate_limit_started: float | None = None
        while True:
            self._wait_for_request_slot()
            try:
                with urllib.request.urlopen(request, timeout=90) as response:
                    return json.loads(response.read().decode("utf-8"))
            except urllib.error.HTTPError as error:
                if error.code == 401:
                    raise WCLAuthenticationExpired(
                        "Warcraft Logs access token was rejected"
                    ) from None
                if error.code == 429:
                    now = time.monotonic()
                    rate_limit_started = rate_limit_started or now
                    retry_after = error.headers.get("Retry-After", "")
                    try:
                        delay = float(retry_after)
                    except (TypeError, ValueError):
                        delay = 0.0
                    if delay <= 0:
                        delay = min(300.0, 15.0 * (2 ** min(rate_limit_attempt, 5)))
                    if now - rate_limit_started + delay > MAX_RATE_LIMIT_WAIT:
                        raise WCLFailure(
                            "Warcraft Logs hourly rate limit did not reset within the safe wait window"
                        ) from None
                    rate_limit_attempt += 1
                    self._defer_requests(delay)
                    continue
                if 500 <= error.code < 600 and transient_attempt + 1 < attempts:
                    delay = min(30, 2 ** transient_attempt)
                    transient_attempt += 1
                    time.sleep(delay)
                    continue
                raise WCLFailure(f"Warcraft Logs HTTP request failed with status {error.code}") from None
            except urllib.error.URLError as error:
                if transient_attempt + 1 < attempts:
                    delay = min(30, 2 ** transient_attempt)
                    transient_attempt += 1
                    time.sleep(delay)
                    continue
                raise WCLFailure(f"Warcraft Logs connection failed: {error.reason}") from None

    def access_token(self) -> str:
        if self._access_token:
            return self._access_token
        credentials = base64.b64encode(
            f"{self.client_id}:{self.client_secret}".encode("ascii")
        ).decode("ascii")
        result = self._request_json(
            TOKEN_URL,
            body=b"grant_type=client_credentials",
            headers={
                "Authorization": "Basic " + credentials,
                "Content-Type": "application/x-www-form-urlencoded",
                "User-Agent": USER_AGENT,
            },
        )
        token = result.get("access_token")
        if not token:
            raise WCLFailure("Warcraft Logs authentication returned no access token")
        self._access_token = str(token)
        return self._access_token

    def graphql(self, query: str, variables: dict[str, Any] | None = None) -> dict[str, Any]:
        result = None
        for auth_attempt in range(2):
            try:
                result = self._request_json(
                    GRAPHQL_URL,
                    body=_json_bytes({"query": query, "variables": variables or {}}),
                    headers={
                        "Authorization": "Bearer " + self.access_token(),
                        "Content-Type": "application/json",
                        "User-Agent": USER_AGENT,
                    },
                )
                break
            except WCLAuthenticationExpired:
                if auth_attempt > 0:
                    raise
                self._access_token = None
        if result is None:
            raise WCLFailure("Warcraft Logs returned no response")
        errors = result.get("errors") or []
        if errors:
            messages = "; ".join(str(error.get("message", "GraphQL error")) for error in errors)
            raise WCLFailure(messages)
        data = result.get("data")
        if not isinstance(data, dict):
            raise WCLFailure("Warcraft Logs returned no GraphQL data")
        return data

    def _cache_path(self, category: str, report_code: str, fight_id: int) -> Path:
        digest = hashlib.sha256(
            f"{CACHE_VERSION}:{report_code}:{fight_id}:{category}".encode("utf-8")
        ).hexdigest()[:24]
        return self.cache_dir / f"{category}_{digest}.json.gz"

    def _load_cache(self, path: Path) -> Any | None:
        if (self.refresh and path not in self._written_cache_paths) or not path.exists():
            return None
        try:
            with gzip.open(path, "rt", encoding="utf-8") as handle:
                return json.load(handle)
        except (OSError, json.JSONDecodeError):
            return None

    def _save_cache(self, path: Path, value: Any) -> None:
        temporary = path.with_suffix(path.suffix + ".tmp")
        with gzip.open(temporary, "wt", encoding="utf-8", compresslevel=6) as handle:
            json.dump(value, handle, ensure_ascii=False, separators=(",", ":"))
        temporary.replace(path)
        self._written_cache_paths.add(path)

    def _cache_lock(self, path: Path) -> threading.Lock:
        with self._cache_lock_guard:
            lock = self._cache_locks.get(path)
            if lock is None:
                lock = threading.Lock()
                self._cache_locks[path] = lock
            return lock

    def zone(self, zone_id: int) -> dict[str, Any]:
        data = self.graphql(ZONE_QUERY, {"zoneID": zone_id})
        zone = (data.get("worldData") or {}).get("zone")
        if not zone:
            raise WCLFailure(f"Warcraft Logs zone {zone_id} was not found")
        return zone

    def latest_live_raid_zone(self) -> dict[str, Any]:
        data = self.graphql(EXPANSIONS_QUERY)
        expansions = (data.get("worldData") or {}).get("expansions") or []
        if not expansions:
            raise WCLFailure("Warcraft Logs returned no expansions")
        newest = max(expansions, key=lambda expansion: int(expansion.get("id", -1)))
        candidates = []
        blocked_words = ("ptr", "beta", "dummy", "complete raid", "complete raids")
        for zone in newest.get("zones") or []:
            name = str(zone.get("name", "")).lower()
            difficulty_ids = {int(item.get("id", -1)) for item in zone.get("difficulties") or []}
            if zone.get("frozen") or any(word in name for word in blocked_words):
                continue
            if not ({3, 4, 5} & difficulty_ids) or len(zone.get("encounters") or []) < 2:
                continue
            candidates.append(zone)
        if not candidates:
            raise WCLFailure(f"No live raid zone found for {newest.get('name', 'latest expansion')}")
        return max(candidates, key=lambda zone: int(zone.get("id", -1)))

    def top_rankings(self, encounter_id: int, difficulty: int, limit: int) -> list[dict[str, Any]]:
        rankings: list[dict[str, Any]] = []
        seen: set[tuple[str, int]] = set()
        page = 1
        while len(rankings) < limit:
            data = self.graphql(
                RANKINGS_QUERY,
                {"encounterID": encounter_id, "difficulty": difficulty, "page": page},
            )
            encounter = (data.get("worldData") or {}).get("encounter") or {}
            page_data = encounter.get("fightRankings") or {}
            for ranking in page_data.get("rankings") or []:
                report = ranking.get("report") or {}
                code = report.get("code")
                fight_id = report.get("fightID")
                if not code or fight_id is None:
                    continue
                identity = (str(code), int(fight_id))
                if identity in seen:
                    continue
                seen.add(identity)
                rankings.append(ranking)
                if len(rankings) >= limit:
                    break
            if not page_data.get("hasMorePages") or not page_data.get("rankings"):
                break
            page += 1
        return rankings

    def top_healer_rankings(
        self,
        encounter_id: int,
        difficulty: int,
        class_name: str,
        spec_name: str,
        limit: int,
    ) -> list[dict[str, Any]]:
        return self.top_character_rankings(
            encounter_id, difficulty, class_name, spec_name, limit, "hps"
        )

    def top_character_rankings(
        self,
        encounter_id: int,
        difficulty: int,
        class_name: str,
        spec_name: str,
        limit: int,
        metric: str,
    ) -> list[dict[str, Any]]:
        rankings: list[dict[str, Any]] = []
        seen: set[tuple[str, str, str, str]] = set()
        page = 1
        while len(rankings) < limit:
            data = self.graphql(
                CHARACTER_RANKINGS_QUERY,
                {
                    "encounterID": encounter_id,
                    "difficulty": difficulty,
                    "page": page,
                    "className": class_name,
                    "specName": spec_name,
                    "metric": metric,
                },
            )
            encounter = (data.get("worldData") or {}).get("encounter") or {}
            page_data = encounter.get("characterRankings") or {}
            page_rankings = page_data.get("rankings") or []
            for ranking in page_rankings:
                report = ranking.get("report") or {}
                server = ranking.get("server") or {}
                if not report.get("code") or report.get("fightID") is None:
                    continue
                identity = (
                    str(ranking.get("name") or ""),
                    str(server.get("id") or server.get("name") or ""),
                    str(server.get("region") or ""),
                    f"{ranking.get('class') or class_name}:{ranking.get('spec') or spec_name}",
                )
                if not identity[0] or identity in seen:
                    continue
                seen.add(identity)
                rankings.append(ranking)
                if len(rankings) >= limit:
                    break
            if not page_data.get("hasMorePages") or not page_rankings:
                break
            page += 1
        return rankings

    def fight_metadata(self, report_code: str, fight_id: int) -> dict[str, Any]:
        cache_path = self._cache_path("metadata", report_code, fight_id)
        with self._cache_lock(cache_path):
            cached = self._load_cache(cache_path)
            if cached is not None:
                return cached
            data = self.graphql(METADATA_QUERY, {"code": report_code, "fightIDs": [fight_id]})
            report = (data.get("reportData") or {}).get("report")
            if not report:
                raise WCLFailure("ranked report is not publicly accessible")
            fights = report.get("fights") or []
            if not fights:
                raise WCLFailure("ranked report no longer contains the selected fight")
            result = {"fight": fights[0], "masterData": report.get("masterData") or {}}
            self._save_cache(cache_path, result)
            return result

    def fight_events(
        self,
        report_code: str,
        fight_id: int,
        data_type: str,
        start_time: float,
        end_time: float,
        hostility_type: str | None = None,
    ) -> list[dict[str, Any]]:
        cache_category = data_type.lower()
        if hostility_type:
            cache_category += "_" + hostility_type.lower()
        cache_path = self._cache_path(cache_category, report_code, fight_id)
        with self._cache_lock(cache_path):
            cached = self._load_cache(cache_path)
            if cached is not None:
                return cached

            events: list[dict[str, Any]] = []
            cursor = float(start_time)
            while cursor < end_time:
                data = self.graphql(
                    EVENTS_QUERY,
                    {
                        "code": report_code,
                        "fightIDs": [fight_id],
                        "dataType": data_type,
                        "hostilityType": hostility_type,
                        "startTime": cursor,
                        "endTime": float(end_time),
                    },
                )
                report = (data.get("reportData") or {}).get("report")
                if not report:
                    raise WCLFailure("ranked report events are not publicly accessible")
                page = report.get("events") or {}
                events.extend(page.get("data") or [])
                next_cursor = page.get("nextPageTimestamp")
                if next_cursor is None:
                    break
                next_cursor = float(next_cursor)
                if next_cursor <= cursor:
                    raise WCLFailure("event pagination did not advance")
                cursor = next_cursor
            self._save_cache(cache_path, events)
            return events


def _atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(content, encoding="utf-8", newline="\n")
    temporary.replace(path)


def _select_encounters(zone: dict[str, Any], encounter_ids: list[int] | None) -> list[dict[str, Any]]:
    encounters = zone.get("encounters") or []
    if not encounter_ids:
        return encounters
    requested = set(encounter_ids)
    selected = [encounter for encounter in encounters if int(encounter.get("id", -1)) in requested]
    missing = requested - {int(encounter["id"]) for encounter in selected}
    if missing:
        raise WCLFailure("encounters not found in zone: " + ", ".join(str(value) for value in sorted(missing)))
    return selected


def _filter_incomplete_phase_samples(
    samples: list[dict[str, Any]],
    reference_phase_count: int | None = None,
) -> tuple[list[dict[str, Any]], int]:
    if not samples:
        return [], reference_phase_count or 0
    phase_counts = Counter(
        len(sample.get("segments") or []) for sample in samples
    )
    reference_phase_count = reference_phase_count or max(
        phase_counts, key=lambda count: (phase_counts[count], count)
    )
    return [
        sample
        for sample in samples
        if len(sample.get("segments") or []) / reference_phase_count
        >= VALIDATION_MIN_PHASE_COVERAGE
    ], reference_phase_count


def _incomplete_dps_profile_specs(model: dict[str, Any]) -> list[int]:
    profiles = model.get("dpsProfilesBySpec") or {}
    incomplete = []
    for spec in DPS_SPECS:
        spec_id = int(spec["spec_id"])
        profile = profiles.get(spec_id)
        if not profile:
            continue
        stats = profile.get("secondaryStats") or {}
        builds = profile.get("talentBuilds") or []
        has_all_stats = all(
            isinstance(stats.get(key), (int, float)) and stats[key] >= 0
            for key in ("criticalStrike", "haste", "mastery", "versatility")
        )
        if not has_all_stats or not any(build.get("talents") for build in builds):
            incomplete.append(spec_id)
    return incomplete


def _validate_generated_models(models: list[dict[str, Any]]) -> None:
    private_fields = {"characterName", "playerName", "report", "reportCode", "server"}
    healer_spec_ids = {int(spec["spec_id"]) for spec in HEALER_SPECS}
    dps_spec_ids = {int(spec["spec_id"]) for spec in DPS_SPECS}

    def validate_private_fields(value: Any, path: str) -> None:
        if isinstance(value, dict):
            for key, child in value.items():
                if key in private_fields:
                    raise WCLFailure(f"private source field leaked into data pack: {path}.{key}")
                validate_private_fields(child, f"{path}.{key}")
        elif isinstance(value, list):
            for index, child in enumerate(value):
                validate_private_fields(child, f"{path}[{index}]")

    if not models:
        raise WCLFailure("no data models were generated")
    for model_index, model in enumerate(models, start=1):
        if model.get("schemaVersion") != 2:
            raise WCLFailure(f"model {model_index} has an unsupported schema version")
        sample_count = model.get("sampleCount")
        if not isinstance(sample_count, int) or not 1 <= sample_count <= 10:
            raise WCLFailure(f"model {model_index} has an invalid ranked-kill sample count")
        damage_values = (model.get("damage") or {}).get("values") or []
        if not damage_values:
            raise WCLFailure(f"model {model_index} has no damage timeline")
        validation = model.get("validation") or {}
        validation_status = validation.get("status")
        if validation_status not in {"passed", "limited"}:
            failures = validation.get("failures") or ["missing validation result"]
            raise WCLFailure(
                f"model {model_index} failed source-log validation: "
                + "; ".join(str(item) for item in failures)
            )
        if validation_status == "limited" and model.get("difficultyID") != 16:
            raise WCLFailure(f"model {model_index} has limited validation outside Mythic difficulty")
        profiles_by_spec = model.get("healerProfilesBySpec") or {}
        generated_spec_ids = {int(spec_id) for spec_id in profiles_by_spec}
        if not generated_spec_ids or not generated_spec_ids.issubset(healer_spec_ids):
            raise WCLFailure(f"model {model_index} has invalid healer specialization coverage")
        if validation_status == "passed" and generated_spec_ids != healer_spec_ids:
            missing = ", ".join(str(value) for value in sorted(healer_spec_ids - generated_spec_ids))
            raise WCLFailure(
                f"model {model_index} passed validation without all healer specializations: {missing}"
            )
        for spec_id, profile in profiles_by_spec.items():
            profile_count = profile.get("sampleCount")
            if not isinstance(profile_count, int) or not 1 <= profile_count <= 10:
                raise WCLFailure(
                    f"model {model_index} healer spec {spec_id} has an invalid sample count"
                )
        dps_profiles = model.get("dpsProfilesBySpec") or {}
        generated_dps_ids = {int(spec_id) for spec_id in dps_profiles}
        if not generated_dps_ids.issubset(dps_spec_ids):
            raise WCLFailure(f"model {model_index} has invalid DPS specialization coverage")
        if validation.get("dpsCoverageStatus") == "complete" and generated_dps_ids != dps_spec_ids:
            raise WCLFailure(f"model {model_index} claims complete DPS coverage with missing specs")
        incomplete_dps_specs = _incomplete_dps_profile_specs(model)
        if set(validation.get("incompleteDpsProfileSpecs") or []) != set(incomplete_dps_specs):
            raise WCLFailure(f"model {model_index} has inaccurate incomplete DPS profile metadata")
        if validation.get("dpsCoverageStatus") == "complete":
            if incomplete_dps_specs:
                raise WCLFailure(f"model {model_index} claims complete DPS coverage with incomplete profiles")
            if any(not (model.get("cooldownsBySpec") or {}).get(spec_id) for spec_id in dps_spec_ids):
                raise WCLFailure(f"model {model_index} claims complete DPS coverage without cooldown markers")
        for spec_id, profile in dps_profiles.items():
            if not isinstance(profile.get("sampleCount"), int) or not 1 <= profile["sampleCount"] <= 10:
                raise WCLFailure(f"model {model_index} DPS spec {spec_id} has an invalid sample count")
        validate_private_fields(model, f"model[{model_index}]")


def _build_ranked_sample(client: WCLClient, ranking: dict[str, Any]) -> dict[str, Any] | None:
    report = ranking.get("report") or {}
    metadata = client.fight_metadata(str(report["code"]), int(report["fightID"]))
    fight = metadata["fight"]
    if not fight.get("kill"):
        return None

    damage_events = client.fight_events(
        str(report["code"]),
        int(report["fightID"]),
        "DamageTaken",
        float(fight["startTime"]),
        float(fight["endTime"]),
    )
    cast_events = client.fight_events(
        str(report["code"]),
        int(report["fightID"]),
        "Casts",
        float(fight["startTime"]),
        float(fight["endTime"]),
    )
    enemy_cast_events = client.fight_events(
        str(report["code"]),
        int(report["fightID"]),
        "Casts",
        float(fight["startTime"]),
        float(fight["endTime"]),
        hostility_type="Enemies",
    )
    return build_sample(
        fight,
        metadata["masterData"],
        damage_events,
        cast_events,
        hostile_cast_events=enemy_cast_events,
    )


def _build_healer_ranked_sample(
    client: WCLClient,
    ranking: dict[str, Any],
    expected_spec_id: int,
) -> dict[str, Any] | None:
    report = ranking.get("report") or {}
    metadata = client.fight_metadata(str(report["code"]), int(report["fightID"]))
    fight = metadata["fight"]
    if not fight.get("kill"):
        return None

    cast_events = client.fight_events(
        str(report["code"]),
        int(report["fightID"]),
        "Casts",
        float(fight["startTime"]),
        float(fight["endTime"]),
    )
    enemy_cast_events = client.fight_events(
        str(report["code"]),
        int(report["fightID"]),
        "Casts",
        float(fight["startTime"]),
        float(fight["endTime"]),
        hostility_type="Enemies",
    )
    combatant_events = client.fight_events(
        str(report["code"]),
        int(report["fightID"]),
        "CombatantInfo",
        float(fight["startTime"]),
        float(fight["endTime"]),
    )
    return build_healer_sample(
        fight,
        metadata["masterData"],
        cast_events,
        combatant_events,
        ranking,
        expected_spec_id=expected_spec_id,
        hostile_cast_events=enemy_cast_events,
    )


def update(args: argparse.Namespace) -> int:
    client = WCLClient(args.cache_dir, refresh=args.refresh)
    client.access_token()
    zone = client.zone(args.zone) if args.zone else client.latest_live_raid_zone()
    encounters = _select_encounters(zone, args.encounter)
    if not encounters:
        raise WCLFailure("selected zone has no encounters")

    print(f"Zone: {zone['name']} ({len(encounters)} encounters)")
    models = []
    for difficulty in args.difficulty:
        for encounter_index, encounter in enumerate(encounters, start=1):
            encounter_id = int(encounter["id"])
            ranking_target = min(
                100,
                args.limit + args.validation_limit + RANKED_KILL_BACKFILL,
            )
            rankings = client.top_rankings(encounter_id, difficulty, ranking_target)
            print(
                f"[{difficulty}] {encounter_index}/{len(encounters)} {encounter['name']}: "
                f"top {args.limit} target, {len(rankings)} candidates "
                f"({args.validation_limit} holdout target)"
            )
            indexed_samples: list[tuple[int, dict[str, Any]]] = []
            completed = 0
            with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as executor:
                pending = {
                    executor.submit(_build_ranked_sample, client, ranking): ranking_index
                    for ranking_index, ranking in enumerate(rankings, start=1)
                }
                for future in concurrent.futures.as_completed(pending):
                    ranking_index = pending[future]
                    try:
                        sample = future.result()
                        if sample is not None:
                            indexed_samples.append((ranking_index, sample))
                    except (KeyError, TypeError, ValueError, WCLFailure) as error:
                        print(f"  skipped ranked kill {ranking_index}: {error}", file=sys.stderr)
                    completed += 1
                    if completed == len(rankings) or completed % 10 == 0:
                        print(
                            f"  processed {completed}/{len(rankings)}; usable {len(indexed_samples)}",
                            flush=True,
                        )

            ordered_samples = [
                sample for _, sample in sorted(indexed_samples, key=lambda item: item[0])
            ]
            ordered_samples, reference_phase_count = _filter_incomplete_phase_samples(
                ordered_samples
            )
            required_samples = args.limit + args.validation_limit
            if len(ordered_samples) < required_samples and len(rankings) == ranking_target and ranking_target < 100:
                print("  backfilling usable kills/holdouts from the next ranks (up to 100)", flush=True)
                seen = {
                    (item["report"]["code"], item["report"]["fightID"])
                    for item in rankings
                }
                raw_samples = [sample for _, sample in sorted(indexed_samples)]
                phase_reference = reference_phase_count or None
                for ranking in client.top_rankings(encounter_id, difficulty, 100):
                    report = ranking["report"]
                    if (report["code"], report["fightID"]) in seen:
                        continue
                    try:
                        sample = _build_ranked_sample(client, ranking)
                        if sample is not None:
                            raw_samples.append(sample)
                            ordered_samples, reference_phase_count = _filter_incomplete_phase_samples(
                                raw_samples, phase_reference
                            )
                    except (KeyError, TypeError, ValueError, WCLFailure) as error:
                        print(f"  skipped backfill kill: {error}", file=sys.stderr)
                    if len(ordered_samples) >= required_samples:
                        break
            samples = ordered_samples[: args.limit]
            validation_samples = ordered_samples[
                args.limit : args.limit + args.validation_limit
            ]
            if not samples:
                print(f"  no usable public kills; data model omitted", file=sys.stderr)
                continue
            print(
                f"  selected {len(samples)} ranked kills + "
                f"{len(validation_samples)} independent holdouts",
                flush=True,
            )
            model = aggregate_samples(
                samples,
                encounter_id=encounter_id,
                encounter_name=str(encounter["name"]),
                wcl_difficulty_id=difficulty,
                zone_id=int(zone["id"]),
                zone_name=str(zone["name"]),
            )

            ranked_specs = [("healer", spec) for spec in HEALER_SPECS]
            ranked_specs += [("dps", spec) for spec in DPS_SPECS]
            rankings_by_spec: dict[int, list[dict[str, Any]]] = {}
            for role, spec in ranked_specs:
                spec_id = int(spec["spec_id"])
                limit = args.healer_limit if role == "healer" else args.dps_limit
                ranking_limit = min(100, limit + args.validation_limit + HEALER_RANKING_BACKFILL)
                if role == "healer":
                    spec_rankings = client.top_healer_rankings(
                        encounter_id, difficulty, str(spec["class_name"]),
                        str(spec["spec_name"]), ranking_limit,
                    )
                else:
                    spec_rankings = client.top_character_rankings(
                        encounter_id, difficulty, str(spec["class_name"]),
                        str(spec["spec_name"]), ranking_limit, "dps",
                    )
                rankings_by_spec[spec_id] = spec_rankings
                print(
                    f"  [{role}] {spec['class_name']} {spec['spec_name']}: "
                    f"top {limit} target, {len(spec_rankings)} candidates",
                    flush=True,
                )

            indexed_samples_by_spec: dict[int, list[tuple[int, dict[str, Any]]]] = {
                int(spec["spec_id"]): [] for _, spec in ranked_specs
            }
            ranked_tasks = [
                (spec_id, ranking_index, ranking)
                for spec_id, spec_rankings in rankings_by_spec.items()
                for ranking_index, ranking in enumerate(spec_rankings, start=1)
            ]
            ranked_completed = 0
            with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as executor:
                pending = {
                    executor.submit(
                        _build_healer_ranked_sample,
                        client,
                        ranking,
                        spec_id,
                    ): (spec_id, ranking_index)
                    for spec_id, ranking_index, ranking in ranked_tasks
                }
                for future in concurrent.futures.as_completed(pending):
                    spec_id, ranking_index = pending[future]
                    try:
                        ranked_sample = future.result()
                        if ranked_sample is not None:
                            indexed_samples_by_spec[spec_id].append((ranking_index, ranked_sample))
                    except (KeyError, TypeError, ValueError, WCLFailure) as error:
                        print(
                            f"  skipped spec {spec_id} rank {ranking_index}: {error}",
                            file=sys.stderr,
                        )
                    ranked_completed += 1
                    if ranked_completed == len(ranked_tasks) or ranked_completed % 10 == 0:
                        usable = sum(len(items) for items in indexed_samples_by_spec.values())
                        print(
                            f"  processed characters {ranked_completed}/{len(ranked_tasks)}; "
                            f"usable {usable}",
                            flush=True,
                        )

            healer_samples_by_spec: dict[int, list[dict[str, Any]]] = {}
            healer_validation_samples_by_spec: dict[int, list[dict[str, Any]]] = {}
            dps_samples_by_spec: dict[int, list[dict[str, Any]]] = {}
            dps_validation_samples_by_spec: dict[int, list[dict[str, Any]]] = {}
            for role, spec in ranked_specs:
                spec_id = int(spec["spec_id"])
                limit = args.healer_limit if role == "healer" else args.dps_limit
                ordered_samples, _ = _filter_incomplete_phase_samples(
                    [
                        sample
                        for _, sample in sorted(
                            indexed_samples_by_spec[spec_id], key=lambda item: item[0]
                        )
                    ],
                    reference_phase_count,
                )
                samples_by_spec = healer_samples_by_spec if role == "healer" else dps_samples_by_spec
                holdouts_by_spec = healer_validation_samples_by_spec if role == "healer" else dps_validation_samples_by_spec
                samples_by_spec[spec_id] = ordered_samples[:limit]
                holdouts_by_spec[spec_id] = ordered_samples[limit : limit + args.validation_limit]
                print(
                    f"  [{role} usable] {spec['class_name']} "
                    f"{spec['spec_name']}: {len(samples_by_spec[spec_id])} + "
                    f"{len(holdouts_by_spec[spec_id])} holdout",
                    flush=True,
                )
            apply_healer_profiles(model, healer_samples_by_spec)
            apply_dps_profiles(model, dps_samples_by_spec)
            validation = validate_model_accuracy(
                model,
                samples,
                validation_samples,
                healer_samples_by_spec,
                healer_validation_samples_by_spec,
                dps_samples_by_spec,
                dps_validation_samples_by_spec,
            )
            validation["missingDpsSpecs"] = [
                int(spec["spec_id"]) for spec in DPS_SPECS
                if not dps_samples_by_spec[int(spec["spec_id"])]
            ]
            validation["limitedDpsSpecs"] = [
                int(spec["spec_id"]) for spec in DPS_SPECS
                if 0 < len(dps_samples_by_spec[int(spec["spec_id"])]) < args.dps_limit
            ]
            validation["missingDpsCooldownSpecs"] = [
                int(spec["spec_id"]) for spec in DPS_SPECS
                if dps_samples_by_spec[int(spec["spec_id"])]
                and not (model.get("cooldownsBySpec") or {}).get(int(spec["spec_id"]))
            ]
            validation["incompleteDpsProfileSpecs"] = _incomplete_dps_profile_specs(model)
            validation["dpsCoverageStatus"] = (
                "limited" if any(validation[key] for key in (
                    "missingDpsSpecs", "limitedDpsSpecs", "missingDpsCooldownSpecs",
                    "incompleteDpsProfileSpecs",
                ))
                else "complete"
            )
            print(
                f"  [validation] {validation['status']}: "
                f"phases {validation['phaseCoverage']:.0%}, "
                f"mechanics {validation['mechanicMedianError']:.2f}s median "
                f"({validation['mechanicMatchCoverage']:.0%}), "
                f"damage peaks {validation['damagePeakMedianError']:.2f}s median "
                f"({validation['damagePeakMatchCoverage']:.0%}, "
                f"curve {validation['damageCurveSimilarity']:.2f}), "
                f"healer anchors {validation['healerAnchoredSampleCoverage']:.0%}, "
                f"DPS anchors {validation['dpsAnchoredSampleCoverage']:.0%}",
                flush=True,
            )
            if validation["status"] == "failed":
                raise WCLFailure(
                    f"{encounter['name']} difficulty {difficulty} failed source-log validation: "
                    + "; ".join(validation.get("failures") or [])
                )
            models.append(model)

    _validate_generated_models(models)
    _atomic_write(args.output, render_data_pack(models))
    print(f"Wrote {len(models)} data models to {args.output}")
    return 0


def list_zone(args: argparse.Namespace) -> int:
    client = WCLClient(args.cache_dir, refresh=args.refresh)
    zone = client.zone(args.zone) if args.zone else client.latest_live_raid_zone()
    print(f"{zone['id']}  {zone['name']}")
    for difficulty in zone.get("difficulties") or []:
        print(f"  difficulty {difficulty['id']}: {difficulty['name']}")
    for encounter in zone.get("encounters") or []:
        print(f"  encounter {encounter['id']}: {encounter['name']}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-dir", type=Path, default=DEFAULT_CACHE)
    parser.add_argument("--refresh", action="store_true", help="ignore cached report payloads")
    subparsers = parser.add_subparsers(dest="command", required=True)

    list_parser = subparsers.add_parser("list", help="show the selected or latest live raid")
    list_parser.add_argument("--zone", type=int, help="Warcraft Logs zone ID")
    list_parser.set_defaults(handler=list_zone)

    update_parser = subparsers.add_parser("update", help="build a Lua pack from top ranked kills")
    update_parser.add_argument("--zone", type=int, help="Warcraft Logs zone ID; defaults to latest live raid")
    update_parser.add_argument("--encounter", type=int, action="append", help="limit to an encounter ID")
    update_parser.add_argument(
        "--difficulty",
        type=int,
        nargs="+",
        default=[5],
        choices=(1, 3, 4, 5),
        help="WCL raid difficulties: 1 LFR, 3 Normal, 4 Heroic, 5 Mythic",
    )
    update_parser.add_argument("--limit", type=int, default=10, choices=range(1, 101), metavar="1-100")
    update_parser.add_argument(
        "--validation-limit",
        type=int,
        default=DEFAULT_VALIDATION_LIMIT,
        choices=range(0, 11),
        metavar="0-10",
        help=(
            "independent ranked kills reserved for phase/mechanic/damage timing "
            f"validation (default: {DEFAULT_VALIDATION_LIMIT})"
        ),
    )
    update_parser.add_argument(
        "--healer-limit",
        type=int,
        default=10,
        choices=range(1, 101),
        metavar="1-100",
        help="top HPS characters collected separately for each healer specialization (default: 10)",
    )
    update_parser.add_argument(
        "--dps-limit", type=int, default=10, choices=range(1, 101), metavar="1-100",
        help="top DPS characters collected separately for each damage specialization (default: 10)",
    )
    update_parser.add_argument(
        "--workers",
        type=int,
        default=4,
        choices=range(1, 9),
        metavar="1-8",
        help="concurrent public report downloads per encounter (default: 4)",
    )
    update_parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    update_parser.set_defaults(handler=update)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return int(args.handler(args))
    except WCLFailure as error:
        print(f"error: {error}", file=sys.stderr)
        return 2
    except KeyboardInterrupt:
        print("cancelled", file=sys.stderr)
        return 130


if __name__ == "__main__":
    raise SystemExit(main())

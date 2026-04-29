#!/usr/bin/env python3
"""Zigbee2MQTT OTA Firmware Update Automation.

Connects to MQTT, discovers devices with available OTA updates, and applies
them sequentially with configurable delays to avoid overloading the mesh.

Self-managing skip behavior
---------------------------
Z2M's "OTA success" only proves it transferred the firmware bytes — some
devices (notoriously Inovelli VZM31-SN on the 2.x -> 3.04 jump) accept the
bytes, ACK the OTA, but never actually switch over: their `update.installed_version`
on the device state topic stays unchanged. Re-flashing them weekly is
pointless and ties the mesh up for hours.

This script verifies every "successful" OTA against the device's *real*
`update.installed_version`. If it didn't advance, the device is recorded as
STUCK in /state/skip.json (persistent volume) keyed on the firmware target
Z2M was trying to push. On subsequent runs:

  * If Z2M still offers the same `latest_version` -> skip (no human action).
  * If Z2M offers a *different* `latest_version` (upstream shipped a fix)
    -> automatically retry. If it works, drop from skip.

This means zero manual intervention: the system self-heals when the upstream
firmware index advances, and stays quiet otherwise.
"""

import json
import logging
import os
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

import paho.mqtt.client as mqtt

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("zigbee2mqtt-ota")

# ---------------------------------------------------------------------------
# Configuration from environment
# ---------------------------------------------------------------------------
MQTT_HOST = os.environ.get("MQTT_HOST", "emqx-listeners.database.svc.cluster.local")
MQTT_PORT = int(os.environ.get("MQTT_PORT", "1883"))
MQTT_USER = os.environ.get("MQTT_USER", "")
MQTT_PASS = os.environ.get("MQTT_PASS", "")
Z2M_TOPIC = os.environ.get("Z2M_TOPIC", "zigbee2mqtt")

# Seconds to wait between finishing one device update and starting the next.
DELAY_BETWEEN_UPDATES = int(os.environ.get("DELAY_BETWEEN_UPDATES", "180"))

# Seconds to wait for a single device OTA to finish before giving up.
UPDATE_TIMEOUT = int(os.environ.get("UPDATE_TIMEOUT", "3600"))

# Seconds to wait after requesting all OTA checks before processing results.
CHECK_WAIT = int(os.environ.get("CHECK_WAIT", "30"))

# If "true", only check and report — do not apply updates.
DRY_RUN = os.environ.get("DRY_RUN", "false").lower() == "true"

# Hard model skip — applied BEFORE the OTA check is even sent. Use only when
# you want to take a model entirely out of rotation. Empty by default; the
# self-managing skip list (below) is the preferred mechanism.
SKIP_MODELS = {
    m.strip() for m in os.environ.get("SKIP_MODELS", "").split(",") if m.strip()
}

# One-shot bootstrap: on the very first run (no skip.json yet), automatically
# pre-mark every device of these models that currently advertises an
# `update_available` as STUCK on its currently-offered firmware. This avoids
# a 10-hour cold-start where the script rediscovers known-broken OTAs the
# hard way. Once skip.json exists, this var is ignored. Empty disables.
BASELINE_SKIP_MODELS = {
    m.strip() for m in os.environ.get("BASELINE_SKIP_MODELS", "").split(",") if m.strip()
}

# Seconds to observe MQTT for in-progress OTA activity before starting.
OTA_OBSERVE_WINDOW = int(os.environ.get("OTA_OBSERVE_WINDOW", "15"))

# After Z2M reports OTA success, wait this many seconds for the device to
# republish its state with the new installed_version, then verify.
VERIFY_DELAY = int(os.environ.get("VERIFY_DELAY", "30"))

# Where the persistent skip database lives. Must be writable.
STATE_FILE = Path(os.environ.get("STATE_FILE", "/state/skip.json"))


@dataclass
class State:
    """Mutable state shared across MQTT callbacks."""

    devices: list = field(default_factory=list)
    devices_received: bool = False
    devices_with_updates: list = field(default_factory=list)
    check_responses: int = 0
    check_expected: int = 0
    current_update_done: bool = False
    current_update_failed: bool = False
    current_update_progress: int = 0
    current_update_device: str = ""
    current_update_seen_updating: bool = False
    ota_in_progress: bool = False
    ota_in_progress_device: str = ""
    # Per-IEEE latest device-state payload (the authoritative source of
    # update.installed_version / update.latest_version / update.state).
    device_state_by_ieee: dict = field(default_factory=dict)
    # Persistent skip database, loaded from STATE_FILE.
    skip: dict = field(default_factory=dict)
    skip_dirty: bool = False


state = State()


# ---------------------------------------------------------------------------
# Skip-list persistence
# ---------------------------------------------------------------------------
def load_skip() -> None:
    if not STATE_FILE.exists():
        log.info("No persistent skip file at %s (first run).", STATE_FILE)
        return
    try:
        state.skip = json.loads(STATE_FILE.read_text())
        log.info("Loaded persistent skip list (%d entries) from %s",
                 len(state.skip), STATE_FILE)
    except (OSError, json.JSONDecodeError) as exc:
        log.error("Failed to read %s (%s) — starting with empty skip list.", STATE_FILE, exc)
        state.skip = {}


def save_skip() -> None:
    if not state.skip_dirty:
        return
    try:
        STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
        tmp = STATE_FILE.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(state.skip, indent=2, sort_keys=True))
        tmp.replace(STATE_FILE)
        log.info("Persisted skip list (%d entries) to %s", len(state.skip), STATE_FILE)
    except OSError as exc:
        log.error("Failed to persist skip list to %s: %s", STATE_FILE, exc)


def mark_stuck(ieee: str, friendly_name: str, model: str,
               installed: int, wanted: int, source: str) -> None:
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    entry = state.skip.get(ieee, {})
    entry.update({
        "friendly_name": friendly_name,
        "model": model,
        "stuck_at_installed": installed,
        "wanted_latest": wanted,
        "latest_source": source,
        "last_attempt_at": now,
        "attempts": int(entry.get("attempts", 0)) + 1,
    })
    entry.setdefault("first_marked_at", now)
    state.skip[ieee] = entry
    state.skip_dirty = True


def clear_stuck(ieee: str) -> None:
    if ieee in state.skip:
        log.info("STUCK -> CLEAR: device %s succeeded; removing from skip list.",
                 state.skip[ieee].get("friendly_name", ieee))
        del state.skip[ieee]
        state.skip_dirty = True


# ---------------------------------------------------------------------------
# MQTT helpers
# ---------------------------------------------------------------------------
def publish_json(client: mqtt.Client, topic: str, payload: dict) -> None:
    client.publish(topic, json.dumps(payload))


def on_connect(client: mqtt.Client, _userdata, _flags, rc, _props=None) -> None:
    if rc != 0:
        log.error("MQTT connection failed: rc=%d", rc)
        sys.exit(1)
    log.info("Connected to MQTT broker at %s:%d", MQTT_HOST, MQTT_PORT)
    client.subscribe(f"{Z2M_TOPIC}/bridge/response/#")
    client.subscribe(f"{Z2M_TOPIC}/bridge/devices")
    # Subscribe to all device messages — gives us update.installed_version /
    # update.latest_version per device, plus in-progress OTA detection.
    client.subscribe(f"{Z2M_TOPIC}/+")


def _ieee_for_friendly(name: str) -> str:
    for d in state.devices:
        if d.get("friendly_name") == name:
            return d.get("ieee_address", "")
    return ""


def on_message(client: mqtt.Client, _userdata, msg: mqtt.MQTTMessage) -> None:
    topic = msg.topic
    try:
        payload = json.loads(msg.payload)
    except json.JSONDecodeError:
        return

    # Device list
    if topic == f"{Z2M_TOPIC}/bridge/devices":
        state.devices = payload
        state.devices_received = True
        return

    # Device state messages: track update lifecycle and the authoritative
    # installed_version / latest_version per device. Z2M publishes these on
    # {Z2M_TOPIC}/{friendly_name} (NOT under /bridge/).
    if (
        not topic.startswith(f"{Z2M_TOPIC}/bridge/")
        and isinstance(payload, dict)
    ):
        device_name = topic.rsplit("/", 1)[-1]
        update_block = payload.get("update")

        if isinstance(update_block, dict):
            # Cache full update block under IEEE for verification later.
            ieee = _ieee_for_friendly(device_name)
            if ieee:
                state.device_state_by_ieee[ieee] = {
                    "friendly_name": device_name,
                    "update": dict(update_block),
                    "received_at": time.time(),
                }

            update_state = update_block.get("state")
            progress = update_block.get("progress")
            remaining = update_block.get("remaining")

            # Pre-flight: detect any device currently being updated.
            if update_state == "updating" and not state.current_update_device:
                state.ota_in_progress = True
                state.ota_in_progress_device = device_name

            # Active update tracking for the device we're currently updating.
            if state.current_update_device and device_name == state.current_update_device:
                if update_state == "updating":
                    state.current_update_seen_updating = True
                    if isinstance(progress, (int, float)):
                        pct = int(progress)
                        if pct > state.current_update_progress:
                            state.current_update_progress = pct
                            remaining_str = (
                                f", ~{int(remaining)}s remaining"
                                if isinstance(remaining, (int, float))
                                else ""
                            )
                            log.info("  Progress: %d%%%s", pct, remaining_str)
                elif update_state in ("idle", "available") and state.current_update_seen_updating:
                    log.info("  Update complete (state=%s)", update_state)
                    state.current_update_done = True
        return

    # OTA check response
    if topic == f"{Z2M_TOPIC}/bridge/response/device/ota_update/check":
        _handle_check_response(payload)
        return

    # OTA update response
    if topic == f"{Z2M_TOPIC}/bridge/response/device/ota_update/update":
        _handle_update_response(payload)
        return


def _handle_check_response(payload: dict) -> None:
    state.check_responses += 1
    data = payload.get("data", {})
    status = payload.get("status", "")
    device_name = data.get("id", "unknown")

    if status == "ok" and data.get("update_available"):
        log.info("  OTA available: %s", device_name)
        state.devices_with_updates.append(device_name)
    elif status == "ok":
        log.debug("  No update: %s", device_name)
    else:
        log.debug("  Check skipped/failed for %s: %s", device_name, payload.get("error", ""))


def _handle_update_response(payload: dict) -> None:
    """Z2M sends this once at the end of an OTA. Use as success/failure signal;
    actual verification of installed_version happens later in apply_update()."""
    data = payload.get("data", {})
    status = payload.get("status", "")
    device_name = data.get("id", "")

    if status == "ok":
        from_ver = data.get("from", {}).get("software_build_id") or data.get("from")
        to_ver = data.get("to", {}).get("software_build_id") or data.get("to")
        log.info("  Z2M reports update finished for %s (%s -> %s)",
                 device_name, from_ver, to_ver)
        state.current_update_done = True
    else:
        log.error("  Update failed for %s: %s", device_name, payload.get("error", "unknown error"))
        state.current_update_done = True
        state.current_update_failed = True


# ---------------------------------------------------------------------------
# Main workflow
# ---------------------------------------------------------------------------
def check_no_ota_in_progress(client: mqtt.Client) -> bool:
    """Observe MQTT for OTA activity from any source for OTA_OBSERVE_WINDOW."""
    log.info("Observing MQTT for %ds to detect in-progress OTA updates...", OTA_OBSERVE_WINDOW)
    state.ota_in_progress = False
    state.ota_in_progress_device = ""

    publish_json(client, f"{Z2M_TOPIC}/bridge/request/device/list", {})

    deadline = time.time() + OTA_OBSERVE_WINDOW
    while time.time() < deadline:
        if state.ota_in_progress:
            log.warning(
                "Detected in-progress OTA update on device: %s. Aborting to avoid conflicts.",
                state.ota_in_progress_device,
            )
            return False
        time.sleep(1)

    if state.devices_received:
        for device in state.devices:
            definition = device.get("definition") or {}
            ota_state = definition.get("ota", {})
            if isinstance(ota_state, dict) and ota_state.get("state") == "updating":
                log.warning(
                    "Device %s reports OTA state 'updating'. Aborting to avoid conflicts.",
                    device.get("friendly_name", device.get("ieee_address")),
                )
                return False

    log.info("No in-progress OTA updates detected. Safe to proceed.")
    return True


def _request_check(client: mqtt.Client, name: str) -> None:
    publish_json(client, f"{Z2M_TOPIC}/bridge/request/device/ota_update/check", {"id": name})


def get_updatable_devices(client: mqtt.Client) -> list[str]:
    """Discover devices and check which ones have OTA updates available.

    Filters out:
      * SKIP_MODELS (hard, model-name based)
      * Devices in the persistent skip list whose Z2M-offered latest_version
        still matches what we recorded as stuck (no upstream change -> retry
        would be futile).
    """
    log.info("Requesting device list...")
    publish_json(client, f"{Z2M_TOPIC}/bridge/request/device/list", {})

    deadline = time.time() + 30
    while not state.devices_received and time.time() < deadline:
        time.sleep(0.5)

    if not state.devices_received:
        log.error("Timed out waiting for device list")
        sys.exit(1)

    eligible = [
        d for d in state.devices
        if d.get("type") in ("EndDevice", "Router")
        and not d.get("disabled", False)
        and d.get("interview_completed", False)
    ]

    if SKIP_MODELS:
        skipped = [
            d.get("friendly_name", d.get("ieee_address"))
            for d in eligible
            if (d.get("definition") or {}).get("model") in SKIP_MODELS
        ]
        eligible = [
            d for d in eligible
            if (d.get("definition") or {}).get("model") not in SKIP_MODELS
        ]
        if skipped:
            log.info("Hard-skipping %d device(s) via SKIP_MODELS=%s: %s",
                     len(skipped), ",".join(sorted(SKIP_MODELS)), ", ".join(skipped))

    # Allow the device-state cache to populate so we know each device's
    # update.latest_version before we filter against the skip list.
    log.info("Letting device-state cache populate (%ds)...", OTA_OBSERVE_WINDOW)
    time.sleep(OTA_OBSERVE_WINDOW)

    persistently_skipped = []
    persistently_retried = []
    eligible_after_persistent = []
    for d in eligible:
        ieee = d.get("ieee_address", "")
        name = d.get("friendly_name", ieee)
        entry = state.skip.get(ieee)
        if not entry:
            eligible_after_persistent.append(d)
            continue
        cached = state.device_state_by_ieee.get(ieee, {}).get("update", {})
        offered = cached.get("latest_version")
        wanted = entry.get("wanted_latest")
        if offered is not None and wanted is not None and offered != wanted:
            log.info(
                "STUCK -> RETRY: %s — Z2M now offers latest_version %s (was stuck on %s).",
                name, offered, wanted,
            )
            persistently_retried.append(name)
            eligible_after_persistent.append(d)
        else:
            persistently_skipped.append(name)
    eligible = eligible_after_persistent

    if persistently_skipped:
        log.info(
            "Persistently skipping %d known-stuck device(s) (no new firmware offered): %s",
            len(persistently_skipped), ", ".join(sorted(persistently_skipped)),
        )

    log.info("Found %d eligible devices (out of %d total)", len(eligible), len(state.devices))

    state.check_expected = len(eligible)
    state.check_responses = 0

    log.info("Checking OTA availability for %d devices...", len(eligible))
    for device in eligible:
        name = device.get("friendly_name", device.get("ieee_address"))
        _request_check(client, name)
        time.sleep(0.5)

    log.info("Waiting for OTA check responses (timeout: %ds)...", CHECK_WAIT)
    deadline = time.time() + CHECK_WAIT
    while state.check_responses < state.check_expected and time.time() < deadline:
        time.sleep(1)

    log.info(
        "Received %d/%d check responses. %d devices have updates available.",
        state.check_responses, state.check_expected, len(state.devices_with_updates),
    )

    # One-shot bootstrap: if skip.json doesn't exist yet AND BASELINE_SKIP_MODELS
    # is set, pre-mark every offered device matching those models as STUCK on
    # whatever Z2M is currently offering. Avoids a 10-hour cold-start.
    if (
        BASELINE_SKIP_MODELS
        and not STATE_FILE.exists()
        and state.devices_with_updates
    ):
        baselined = []
        remaining = []
        by_name = {d.get("friendly_name"): d for d in state.devices}
        for name in state.devices_with_updates:
            d = by_name.get(name) or {}
            model = (d.get("definition") or {}).get("model")
            if model in BASELINE_SKIP_MODELS:
                ieee = d.get("ieee_address", "")
                cached = state.device_state_by_ieee.get(ieee, {}).get("update", {})
                installed = cached.get("installed_version", 0)
                wanted = cached.get("latest_version", 0)
                source = cached.get("latest_source", "")
                mark_stuck(ieee, name, model, installed, wanted, source)
                baselined.append(name)
            else:
                remaining.append(name)
        if baselined:
            log.warning(
                "BASELINE: pre-marking %d device(s) of model(s) %s as STUCK on first run "
                "(will auto-retry when upstream firmware index advances): %s",
                len(baselined), ",".join(sorted(BASELINE_SKIP_MODELS)),
                ", ".join(baselined),
            )
            state.devices_with_updates = remaining
            save_skip()

    return state.devices_with_updates


def apply_update(client: mqtt.Client, device_name: str) -> bool:
    """Apply an OTA update to a single device, then verify installed_version
    actually advanced. Returns True only if the device really updated."""
    log.info("Starting OTA update for: %s", device_name)
    state.current_update_done = False
    state.current_update_failed = False
    state.current_update_progress = 0
    state.current_update_device = device_name
    state.current_update_seen_updating = False

    ieee = _ieee_for_friendly(device_name)
    pre = state.device_state_by_ieee.get(ieee, {}).get("update", {})
    installed_before = pre.get("installed_version")
    target_version = pre.get("latest_version")
    target_source = pre.get("latest_source", "")
    model = ""
    for d in state.devices:
        if d.get("friendly_name") == device_name:
            model = (d.get("definition") or {}).get("model", "")
            break

    publish_json(
        client,
        f"{Z2M_TOPIC}/bridge/request/device/ota_update/update",
        {"id": device_name},
    )

    deadline = time.time() + UPDATE_TIMEOUT
    while not state.current_update_done and time.time() < deadline:
        time.sleep(5)

    state.current_update_device = ""

    if not state.current_update_done:
        log.error("Timed out waiting for OTA update on %s", device_name)
        return False

    if state.current_update_failed:
        return False

    # Z2M says success — now verify the device actually advanced. Re-check
    # via Z2M and wait for the device to republish its state.
    if not ieee or installed_before is None or target_version is None:
        log.warning("  Cannot verify %s — missing IEEE / installed_version / latest_version.",
                    device_name)
        return True

    log.info("  Verifying installed_version advanced (waiting up to %ds)...", VERIFY_DELAY)
    _request_check(client, device_name)
    deadline = time.time() + VERIFY_DELAY
    installed_after = installed_before
    while time.time() < deadline:
        cur = state.device_state_by_ieee.get(ieee, {}).get("update", {})
        installed_after = cur.get("installed_version", installed_before)
        if installed_after != installed_before and installed_after is not None:
            break
        time.sleep(2)

    if installed_after == installed_before:
        log.error(
            "  STUCK: %s — Z2M reports OTA success but installed_version is still %s "
            "(wanted %s). Marking as stuck; will not retry until Z2M offers a different "
            "firmware. Likely cause: device firmware does not honor this OTA path.",
            device_name, installed_before, target_version,
        )
        mark_stuck(ieee, device_name, model, installed_before, target_version, target_source)
        return False

    log.info("  VERIFIED: %s installed_version %s -> %s",
             device_name, installed_before, installed_after)
    clear_stuck(ieee)
    return True


def main() -> None:
    log.info("=== Zigbee2MQTT OTA Update Automation ===")
    log.info("Broker: %s:%d | Topic: %s | Delay: %ds | Timeout: %ds | Dry run: %s",
             MQTT_HOST, MQTT_PORT, Z2M_TOPIC, DELAY_BETWEEN_UPDATES, UPDATE_TIMEOUT, DRY_RUN)
    log.info("State file: %s | Verify delay: %ds | Baseline skip models: %s",
             STATE_FILE, VERIFY_DELAY, ",".join(sorted(BASELINE_SKIP_MODELS)) or "(none)")

    load_skip()

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    if MQTT_USER:
        client.username_pw_set(MQTT_USER, MQTT_PASS)

    client.on_connect = on_connect
    client.on_message = on_message

    client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
    client.loop_start()

    time.sleep(2)

    try:
        if not check_no_ota_in_progress(client):
            log.error("Exiting due to in-progress OTA update.")
            sys.exit(1)

        devices = get_updatable_devices(client)

        if not devices:
            log.info("No devices need OTA updates. Done!")
            return

        log.info("Devices with available updates: %s", ", ".join(devices))

        if DRY_RUN:
            log.info("[DRY RUN] Would update %d devices. Exiting.", len(devices))
            return

        succeeded = 0
        failed = 0
        stuck = 0

        for i, device_name in enumerate(devices, 1):
            log.info("--- Updating device %d/%d: %s ---", i, len(devices), device_name)
            ieee = _ieee_for_friendly(device_name)
            was_in_skip = ieee in state.skip

            if apply_update(client, device_name):
                succeeded += 1
                log.info("Successfully updated: %s", device_name)
            else:
                # Distinguish "stuck" (we just marked it) from generic failure.
                if ieee and ieee in state.skip and not was_in_skip:
                    stuck += 1
                    log.warning("Marked STUCK: %s (continuing with next device)", device_name)
                else:
                    failed += 1
                    log.warning("Failed to update: %s (continuing with next device)", device_name)

            if i < len(devices):
                log.info("Waiting %ds before next update...", DELAY_BETWEEN_UPDATES)
                time.sleep(DELAY_BETWEEN_UPDATES)

        log.info("=== OTA Update Summary ===")
        log.info("Total: %d | Succeeded: %d | Stuck (newly): %d | Failed: %d | Persistent skip list size: %d",
                 len(devices), succeeded, stuck, failed, len(state.skip))

        if state.skip:
            log.info("Currently STUCK devices (will auto-retry when Z2M offers a different firmware):")
            for ieee, e in sorted(state.skip.items(), key=lambda kv: kv[1].get("friendly_name", "")):
                log.info("  - %s [%s] stuck at installed_version=%s wanted=%s attempts=%s",
                         e.get("friendly_name", ieee), e.get("model", "?"),
                         e.get("stuck_at_installed"), e.get("wanted_latest"),
                         e.get("attempts"))

        save_skip()

        if failed > 0:
            sys.exit(1)

    finally:
        save_skip()
        client.loop_stop()
        client.disconnect()


if __name__ == "__main__":
    main()

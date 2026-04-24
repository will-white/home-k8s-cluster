#!/usr/bin/env python3
"""Zigbee2MQTT OTA Firmware Update Automation.

Connects to MQTT, discovers devices with available OTA updates,
and applies them sequentially with configurable delays to avoid
overloading the Zigbee mesh network.
"""

import json
import logging
import os
import sys
import time
from dataclasses import dataclass, field

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


# Seconds to observe MQTT for in-progress OTA activity before starting.
OTA_OBSERVE_WINDOW = int(os.environ.get("OTA_OBSERVE_WINDOW", "15"))


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
    ota_in_progress: bool = False
    ota_in_progress_device: str = ""


state = State()


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
    # Subscribe to all device messages to detect in-progress OTA from any source
    client.subscribe(f"{Z2M_TOPIC}/+")


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

    # Detect in-progress OTA from any source (manual UI, other automation, etc.)
    # Device state messages with "update" containing progress indicate an active OTA.
    if (
        not topic.startswith(f"{Z2M_TOPIC}/bridge/")
        and isinstance(payload, dict)
        and isinstance(payload.get("update"), dict)
    ):
        update_state = payload["update"].get("state")
        if update_state == "updating":
            device_name = topic.rsplit("/", 1)[-1]
            state.ota_in_progress = True
            state.ota_in_progress_device = device_name
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
        # Many devices don't support OTA — this is expected.
        log.debug("  Check skipped/failed for %s: %s", device_name, payload.get("error", ""))


def _handle_update_response(payload: dict) -> None:
    data = payload.get("data", {})
    status = payload.get("status", "")

    if status == "ok":
        progress = data.get("progress", 0)
        remaining = data.get("remaining")
        state.current_update_progress = progress
        if progress >= 100 or data.get("status") == "idle":
            log.info("  Update complete (progress=%d%%)", progress)
            state.current_update_done = True
        else:
            remaining_str = f", ~{remaining}s remaining" if remaining else ""
            log.info("  Progress: %d%%%s", progress, remaining_str)
    else:
        log.error("  Update failed: %s", payload.get("error", "unknown error"))
        state.current_update_done = True
        state.current_update_failed = True


# ---------------------------------------------------------------------------
# Main workflow
# ---------------------------------------------------------------------------
def check_no_ota_in_progress(client: mqtt.Client) -> bool:
    """Observe MQTT traffic to detect if an OTA update is already running.

    Listens for device state messages with update.state == "updating" during
    the observation window. Returns True if it's safe to proceed.
    """
    log.info("Observing MQTT for %ds to detect in-progress OTA updates...", OTA_OBSERVE_WINDOW)
    state.ota_in_progress = False
    state.ota_in_progress_device = ""

    # Also do an explicit check: request the device list and look for update state
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

    # Also check the device list for any device with update.state == "updating"
    if state.devices_received:
        for device in state.devices:
            definition = device.get("definition") or {}
            ota_state = definition.get("ota", {})
            # Check if the device-level state reports updating
            if isinstance(ota_state, dict) and ota_state.get("state") == "updating":
                log.warning(
                    "Device %s reports OTA state 'updating'. Aborting to avoid conflicts.",
                    device.get("friendly_name", device.get("ieee_address")),
                )
                return False

    log.info("No in-progress OTA updates detected. Safe to proceed.")
    return True


def get_updatable_devices(client: mqtt.Client) -> list[str]:
    """Discover devices and check which ones have OTA updates available."""
    # Request device list
    log.info("Requesting device list...")
    publish_json(client, f"{Z2M_TOPIC}/bridge/request/device/list", {})

    deadline = time.time() + 30
    while not state.devices_received and time.time() < deadline:
        time.sleep(0.5)

    if not state.devices_received:
        log.error("Timed out waiting for device list")
        sys.exit(1)

    # Filter to end-devices and routers (skip coordinator)
    eligible = [
        d for d in state.devices
        if d.get("type") in ("EndDevice", "Router")
        and not d.get("disabled", False)
        and d.get("interview_completed", False)
    ]
    log.info("Found %d eligible devices (out of %d total)", len(eligible), len(state.devices))

    # Check OTA for each device
    state.check_expected = len(eligible)
    state.check_responses = 0

    log.info("Checking OTA availability for %d devices...", len(eligible))
    for device in eligible:
        name = device.get("friendly_name", device.get("ieee_address"))
        publish_json(
            client,
            f"{Z2M_TOPIC}/bridge/request/device/ota_update/check",
            {"id": name},
        )
        # Small delay to avoid flooding
        time.sleep(0.5)

    # Wait for all check responses (or timeout)
    log.info("Waiting for OTA check responses (timeout: %ds)...", CHECK_WAIT)
    deadline = time.time() + CHECK_WAIT
    while state.check_responses < state.check_expected and time.time() < deadline:
        time.sleep(1)

    log.info(
        "Received %d/%d check responses. %d devices have updates available.",
        state.check_responses,
        state.check_expected,
        len(state.devices_with_updates),
    )
    return state.devices_with_updates


def apply_update(client: mqtt.Client, device_name: str) -> bool:
    """Apply an OTA update to a single device and wait for completion."""
    log.info("Starting OTA update for: %s", device_name)
    state.current_update_done = False
    state.current_update_failed = False
    state.current_update_progress = 0

    publish_json(
        client,
        f"{Z2M_TOPIC}/bridge/request/device/ota_update/update",
        {"id": device_name},
    )

    deadline = time.time() + UPDATE_TIMEOUT
    while not state.current_update_done and time.time() < deadline:
        time.sleep(5)

    if not state.current_update_done:
        log.error("Timed out waiting for OTA update on %s", device_name)
        return False

    return not state.current_update_failed


def main() -> None:
    log.info("=== Zigbee2MQTT OTA Update Automation ===")
    log.info("Broker: %s:%d | Topic: %s | Delay: %ds | Timeout: %ds | Dry run: %s",
             MQTT_HOST, MQTT_PORT, Z2M_TOPIC, DELAY_BETWEEN_UPDATES, UPDATE_TIMEOUT, DRY_RUN)

    client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    if MQTT_USER:
        client.username_pw_set(MQTT_USER, MQTT_PASS)

    client.on_connect = on_connect
    client.on_message = on_message

    client.connect(MQTT_HOST, MQTT_PORT, keepalive=60)
    client.loop_start()

    # Wait for connection
    time.sleep(2)

    try:
        # Pre-flight: ensure no OTA update is already in progress
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

        for i, device_name in enumerate(devices, 1):
            log.info("--- Updating device %d/%d: %s ---", i, len(devices), device_name)

            if apply_update(client, device_name):
                succeeded += 1
                log.info("Successfully updated: %s", device_name)
            else:
                failed += 1
                log.warning("Failed to update: %s (continuing with next device)", device_name)

            # Delay between updates to let the mesh settle
            if i < len(devices):
                log.info("Waiting %ds before next update...", DELAY_BETWEEN_UPDATES)
                time.sleep(DELAY_BETWEEN_UPDATES)

        log.info("=== OTA Update Summary ===")
        log.info("Total: %d | Succeeded: %d | Failed: %d", len(devices), succeeded, failed)

        if failed > 0:
            sys.exit(1)

    finally:
        client.loop_stop()
        client.disconnect()


if __name__ == "__main__":
    main()

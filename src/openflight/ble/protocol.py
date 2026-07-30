"""Versioned OpenFlight shot payload and BLE framing helpers."""

from __future__ import annotations

import json
import math
import struct
import uuid
from typing import Iterable, Mapping

SERVICE_UUID = "B6F633F2-E6E3-45AE-84B4-968ECCA2D9C7"
SHOT_CHARACTERISTIC_UUID = "2B28F67E-9011-41D2-98ED-562B47D7A5E4"

SCHEMA_VERSION = 1
FRAME_VERSION = 1
FRAME_SIZE = 20
_HEADER = struct.Struct(">BHBB")
HEADER_SIZE = _HEADER.size
FRAGMENT_PAYLOAD_SIZE = FRAME_SIZE - HEADER_SIZE
MAX_FRAGMENT_COUNT = 255
MAX_MESSAGE_SIZE = FRAGMENT_PAYLOAD_SIZE * MAX_FRAGMENT_COUNT

_OPTIONAL_SHOT_FIELDS = (
    "club_speed_mph",
    "smash_factor",
    "launch_angle_vertical",
    "launch_angle_horizontal",
    "spin_rpm",
    "club_path_deg",
    "spin_axis_deg",
)


def build_shot_event(shot_data: Mapping, *, event_id: str | None = None) -> dict:
    """Build the stable, display-focused V1 payload from ``shot_to_dict`` output."""
    event = {
        "schema_version": SCHEMA_VERSION,
        "event_id": event_id or str(uuid.uuid4()),
        "timestamp": shot_data["timestamp"],
        "club": shot_data["club"],
        "ball_speed_mph": shot_data["ball_speed_mph"],
        "estimated_carry_yards": shot_data["estimated_carry_yards"],
    }
    event.update({field: shot_data.get(field) for field in _OPTIONAL_SHOT_FIELDS})
    return event


def encode_shot_event(shot_data: Mapping, *, event_id: str | None = None) -> bytes:
    """Encode a shot event as deterministic, compact UTF-8 JSON."""
    event = build_shot_event(shot_data, event_id=event_id)
    return json.dumps(
        event,
        allow_nan=False,
        ensure_ascii=True,
        separators=(",", ":"),
        sort_keys=True,
    ).encode("utf-8")


def fragment_payload(payload: bytes, *, sequence: int) -> list[bytes]:
    """Split a message into conservative 20-byte BLE notification frames."""
    if not payload:
        raise ValueError("BLE payload must not be empty")
    if not 0 <= sequence <= 0xFFFF:
        raise ValueError("BLE sequence must fit in an unsigned 16-bit integer")

    fragment_count = math.ceil(len(payload) / FRAGMENT_PAYLOAD_SIZE)
    if fragment_count > MAX_FRAGMENT_COUNT:
        raise ValueError(
            f"BLE payload is {len(payload)} bytes; maximum is {MAX_MESSAGE_SIZE} bytes"
        )

    frames = []
    for index in range(fragment_count):
        start = index * FRAGMENT_PAYLOAD_SIZE
        chunk = payload[start : start + FRAGMENT_PAYLOAD_SIZE]
        frames.append(_HEADER.pack(FRAME_VERSION, sequence, index, fragment_count) + chunk)
    return frames


def parse_fragment(frame: bytes) -> tuple[int, int, int, bytes]:
    """Return ``(sequence, index, count, payload)`` after validating one frame."""
    if len(frame) < HEADER_SIZE or len(frame) > FRAME_SIZE:
        raise ValueError("BLE frame has an invalid size")
    version, sequence, index, fragment_count = _HEADER.unpack(frame[:HEADER_SIZE])
    if version != FRAME_VERSION:
        raise ValueError(f"unsupported BLE frame version: {version}")
    if fragment_count == 0 or index >= fragment_count:
        raise ValueError("BLE frame has invalid fragment metadata")
    return sequence, index, fragment_count, frame[HEADER_SIZE:]


def reassemble_fragments(frames: Iterable[bytes]) -> bytes:
    """Reassemble a complete message; duplicate fragments are harmless."""
    sequence = None
    fragment_count = None
    fragments: dict[int, bytes] = {}

    for frame in frames:
        frame_sequence, index, frame_count, payload = parse_fragment(frame)
        if sequence is None:
            sequence = frame_sequence
            fragment_count = frame_count
        elif frame_sequence != sequence or frame_count != fragment_count:
            raise ValueError("BLE frames belong to different messages")
        fragments[index] = payload

    if fragment_count is None or len(fragments) != fragment_count:
        raise ValueError("BLE message is incomplete")
    return b"".join(fragments[index] for index in range(fragment_count))

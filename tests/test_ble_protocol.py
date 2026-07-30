"""Tests for the public OpenFlight BLE shot contract."""

import json
from pathlib import Path

import pytest

from openflight.ble.protocol import (
    FRAGMENT_PAYLOAD_SIZE,
    FRAME_SIZE,
    MAX_MESSAGE_SIZE,
    build_shot_event,
    encode_shot_event,
    fragment_payload,
    parse_fragment,
    reassemble_fragments,
)

FIXTURE_PATH = Path(__file__).parents[1] / "ios" / "OpenFlightTests" / "Fixtures" / "shot_v1.json"


def _shot_data():
    return {
        "timestamp": "2026-07-29T19:42:10.123456",
        "club": "driver",
        "ball_speed_mph": 151.4,
        "club_speed_mph": 103.2,
        "smash_factor": 1.47,
        "estimated_carry_yards": 264,
        "launch_angle_vertical": 12.6,
        "launch_angle_horizontal": -1.3,
        "spin_rpm": 2380,
        "club_path_deg": 2.1,
        "spin_axis_deg": -3.4,
        "spin_candidates": [{"rpm": 2380}],
    }


def test_build_shot_event_is_stable_and_display_focused():
    expected = json.loads(FIXTURE_PATH.read_text(encoding="utf-8"))
    event = build_shot_event(_shot_data(), event_id=expected["event_id"])

    assert event == expected
    assert "spin_candidates" not in event


def test_missing_measurements_are_explicit_nulls():
    shot = _shot_data()
    for key in (
        "club_speed_mph",
        "smash_factor",
        "launch_angle_vertical",
        "launch_angle_horizontal",
        "spin_rpm",
        "club_path_deg",
        "spin_axis_deg",
    ):
        shot.pop(key)

    event = json.loads(encode_shot_event(shot, event_id="shot-null"))

    assert event["club_speed_mph"] is None
    assert event["launch_angle_vertical"] is None
    assert event["spin_rpm"] is None
    assert event["spin_axis_deg"] is None


def test_encoding_is_compact_and_deterministic():
    encoded = encode_shot_event(_shot_data(), event_id="shot-1")

    assert b" " not in encoded
    assert encoded == encode_shot_event(_shot_data(), event_id="shot-1")


def test_non_finite_numbers_are_rejected():
    shot = _shot_data()
    shot["ball_speed_mph"] = float("nan")

    with pytest.raises(ValueError, match="Out of range float values"):
        encode_shot_event(shot)


@pytest.mark.parametrize(
    ("payload_size", "expected_frames"),
    [
        (1, 1),
        (FRAGMENT_PAYLOAD_SIZE, 1),
        (FRAGMENT_PAYLOAD_SIZE + 1, 2),
        (FRAGMENT_PAYLOAD_SIZE * 3, 3),
    ],
)
def test_fragment_boundaries(payload_size, expected_frames):
    frames = fragment_payload(b"x" * payload_size, sequence=42)

    assert len(frames) == expected_frames
    assert all(len(frame) <= FRAME_SIZE for frame in frames)
    assert reassemble_fragments(reversed(frames)) == b"x" * payload_size


def test_duplicate_fragment_is_harmless():
    frames = fragment_payload(b"a complete payload", sequence=7)

    assert reassemble_fragments([frames[0], frames[0], *frames[1:]]) == b"a complete payload"


def test_incomplete_message_is_rejected():
    frames = fragment_payload(b"x" * (FRAGMENT_PAYLOAD_SIZE + 1), sequence=8)

    with pytest.raises(ValueError, match="incomplete"):
        reassemble_fragments(frames[:-1])


def test_mixed_sequences_are_rejected():
    first = fragment_payload(b"first message that has chunks", sequence=1)
    second = fragment_payload(b"second message", sequence=2)

    with pytest.raises(ValueError, match="different messages"):
        reassemble_fragments([first[0], second[0]])


def test_invalid_frame_metadata_is_rejected():
    frame = bytearray(fragment_payload(b"payload", sequence=3)[0])
    frame[4] = 0

    with pytest.raises(ValueError, match="metadata"):
        parse_fragment(bytes(frame))


def test_oversized_payload_is_rejected():
    with pytest.raises(ValueError, match="maximum"):
        fragment_payload(b"x" * (MAX_MESSAGE_SIZE + 1), sequence=0)

"""Tests for BLE delivery isolation, buffering, and fragmentation."""

import asyncio
import json
import logging

from openflight.ble.protocol import SHOT_CHARACTERISTIC_UUID, reassemble_fragments
from openflight.ble.publisher import BleShotPublisher


def _shot_data(ball_speed=150.0):
    return {
        "timestamp": "2026-07-29T19:42:10",
        "club": "driver",
        "ball_speed_mph": ball_speed,
        "club_speed_mph": None,
        "smash_factor": None,
        "estimated_carry_yards": 250,
        "launch_angle_vertical": None,
        "launch_angle_horizontal": None,
        "spin_rpm": None,
        "club_path_deg": None,
        "spin_axis_deg": None,
    }


class _Characteristic:
    value = bytearray()


class _Server:
    def __init__(self):
        self.characteristic = _Characteristic()
        self.notifications = []

    def get_characteristic(self, uuid):
        assert uuid == SHOT_CHARACTERISTIC_UUID
        return self.characteristic

    def update_value(self, _service_uuid, _characteristic_uuid):
        self.notifications.append(bytes(self.characteristic.value))
        return True


def test_disconnected_publish_retains_only_latest_payload():
    publisher = BleShotPublisher()

    assert publisher.publish(_shot_data(140.0))
    assert publisher.publish(_shot_data(151.0))

    latest = json.loads(publisher._latest_payload)  # pylint: disable=protected-access
    assert latest["ball_speed_mph"] == 151.0


def test_invalid_shot_does_not_raise_into_caller():
    publisher = BleShotPublisher()

    assert publisher.publish({}) is False


def test_delivery_uses_bounded_frames_and_round_trips():
    async def run():
        publisher = BleShotPublisher(fragment_interval_s=0)
        server = _Server()
        publisher._server = server  # pylint: disable=protected-access
        publisher._subscribed = True  # pylint: disable=protected-access

        payload = b'{"schema_version":1,"event_id":"shot-1","ball_speed_mph":150.0}'
        await publisher._send_payload(payload)  # pylint: disable=protected-access

        assert reassemble_fragments(server.notifications) == payload
        assert max(map(len, server.notifications)) <= 20

    asyncio.run(run())


def test_queue_overflow_drops_oldest_unsent_payload():
    async def run():
        publisher = BleShotPublisher(queue_size=2)
        publisher._queue = asyncio.Queue(maxsize=2)  # pylint: disable=protected-access
        publisher._subscribed = True  # pylint: disable=protected-access

        publisher._enqueue_payload(b"first")  # pylint: disable=protected-access
        publisher._enqueue_payload(b"second")  # pylint: disable=protected-access
        publisher._enqueue_payload(b"third")  # pylint: disable=protected-access

        assert publisher._queue.qsize() == 2  # pylint: disable=protected-access
        assert publisher._queue.get_nowait() == b"second"  # pylint: disable=protected-access
        assert publisher._queue.get_nowait() == b"third"  # pylint: disable=protected-access

    asyncio.run(run())


def test_unsubscribe_clears_backlog_but_keeps_latest_payload():
    async def run():
        publisher = BleShotPublisher(queue_size=2)
        publisher._queue = asyncio.Queue(maxsize=2)  # pylint: disable=protected-access
        publisher._subscribed = True  # pylint: disable=protected-access
        publisher.publish(_shot_data())
        publisher._enqueue_payload(b"queued")  # pylint: disable=protected-access

        publisher._on_unsubscribe(None, None)  # pylint: disable=protected-access

        assert not publisher.subscribed
        assert publisher._queue.empty()  # pylint: disable=protected-access
        assert publisher._latest_payload is not None  # pylint: disable=protected-access

    asyncio.run(run())


def test_background_startup_failure_is_isolated(caplog):
    class FailingPublisher(BleShotPublisher):
        async def _run(self):
            raise RuntimeError("no BlueZ adapter")

    publisher = FailingPublisher()
    with caplog.at_level(logging.WARNING):
        publisher.start()
        publisher._thread.join(timeout=2)  # pylint: disable=protected-access

    assert not publisher._thread.is_alive()  # pylint: disable=protected-access
    assert "shot recording will continue without BLE" in caplog.text

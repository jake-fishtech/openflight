"""Tests for swing speed training mode."""

from datetime import datetime

from openflight.ops243 import Direction, SpeedReading
from openflight.swing_speed import SwingSpeedEvent, SwingSpeedMonitor


def test_build_event_uses_peak_outbound_speed_and_magnitude():
    """A completed swing window should report peak speed and peak magnitude."""
    monitor = SwingSpeedMonitor(trigger_threshold_mph=30)
    readings = [
        SpeedReading(
            speed=44.0,
            direction=Direction.OUTBOUND,
            magnitude=12,
            timestamp=100.00,
        ),
        SpeedReading(
            speed=88.4,
            direction=Direction.OUTBOUND,
            magnitude=36,
            timestamp=100.08,
        ),
        SpeedReading(
            speed=73.2,
            direction=Direction.OUTBOUND,
            magnitude=24,
            timestamp=100.13,
        ),
    ]

    event = monitor._build_event(  # pylint: disable=protected-access
        readings=readings,
        trigger_speed=44.0,
        swing_start=100.00,
        swing_end=100.13,
    )

    assert event.peak_speed_mph == 88.4
    assert event.trigger_speed_mph == 44.0
    assert round(event.duration_ms) == 130
    assert event.reading_count == 3
    assert event.peak_magnitude == 36
    assert event.mode == "swing-speed"


def test_session_stats_for_swing_speed_events():
    """Swing speed sessions should summarize rep count, best, average, and last."""
    monitor = SwingSpeedMonitor()
    monitor._events = [  # pylint: disable=protected-access
        SwingSpeedEvent(
            peak_speed_mph=95.0,
            timestamp=datetime.now(),
            duration_ms=320,
            reading_count=5,
            trigger_speed_mph=35.0,
        ),
        SwingSpeedEvent(
            peak_speed_mph=101.4,
            timestamp=datetime.now(),
            duration_ms=340,
            reading_count=7,
            trigger_speed_mph=37.0,
        ),
        SwingSpeedEvent(
            peak_speed_mph=99.2,
            timestamp=datetime.now(),
            duration_ms=300,
            reading_count=6,
            trigger_speed_mph=34.0,
        ),
    ]

    assert monitor.get_session_stats() == {
        "swing_count": 3,
        "best_speed_mph": 101.4,
        "avg_speed_mph": 98.5,
        "last_speed_mph": 99.2,
    }


def test_min_readings_default_rejects_single_spike():
    """The default gate should reject one-off hand-motion or noise spikes."""
    monitor = SwingSpeedMonitor()

    assert monitor.min_readings == 3
    assert monitor.max_speed_mph == 130.0
    assert monitor.single_reading_peak_mph == 60.0
    assert monitor.num_reports == 8
    assert monitor.end_quiet_ms == 1000.0
    assert monitor.rejected_cooldown_ms == 100.0


def test_connect_applies_threshold_to_radar_filter(monkeypatch):
    """Swing mode should not stream low-speed background readings from the OPS."""
    calls = []

    class FakeRadar:
        def __init__(self, port=None):
            self.port = port

        def connect(self):
            calls.append(("connect", None))

        def configure_for_swing_speed_training(self, min_speed_mph=None, num_reports=None):
            calls.append(("configure_for_swing_speed_training", (min_speed_mph, num_reports)))

    monkeypatch.setattr("openflight.swing_speed.OPS243Radar", FakeRadar)

    monitor = SwingSpeedMonitor(port="COM4", trigger_threshold_mph=45.0)

    assert monitor.connect() is True
    # Training owns its own radar setup; it must not route through the launch
    # monitor's configure_for_speed_trigger() (which hands off to the rolling
    # buffer), and the threshold/report count go in as arguments.
    assert calls == [
        ("connect", None),
        ("configure_for_swing_speed_training", (45.0, 8)),
    ]


def test_disconnect_restores_rolling_buffer_mode(monkeypatch):
    """Leaving swing speed mode should put the OPS back into launch-monitor mode."""
    calls = []

    class FakeRadar:
        def __init__(self, port=None):
            self.port = port

        def restore_rolling_buffer_mode(self):
            calls.append("restore_rolling_buffer_mode")

        def disconnect(self):
            calls.append("disconnect")

    monkeypatch.setattr("openflight.swing_speed.OPS243Radar", FakeRadar)

    monitor = SwingSpeedMonitor(port="COM4")
    monitor.disconnect()

    assert calls == ["restore_rolling_buffer_mode", "disconnect"]


def test_select_swing_reading_uses_fastest_outbound_candidate():
    """Swing speed should prefer the fastest outbound return, not the strongest one."""
    monitor = SwingSpeedMonitor(trigger_threshold_mph=45.0)
    readings = [
        SpeedReading(
            speed=56.0,
            direction=Direction.OUTBOUND,
            magnitude=1200.0,
        ),
        SpeedReading(
            speed=103.0,
            direction=Direction.OUTBOUND,
            magnitude=180.0,
        ),
        SpeedReading(
            speed=120.0,
            direction=Direction.INBOUND,
            magnitude=900.0,
        ),
    ]

    selected = monitor._select_swing_reading(readings)  # pylint: disable=protected-access

    assert selected is readings[1]


def test_select_swing_reading_rejects_speeds_above_configured_max():
    """Impossible high candidates from OPS multi-report mode should be ignored."""
    monitor = SwingSpeedMonitor(trigger_threshold_mph=70.0, max_speed_mph=125.0)
    readings = [
        SpeedReading(
            speed=143.4,
            direction=Direction.OUTBOUND,
            magnitude=90.0,
        ),
        SpeedReading(
            speed=104.1,
            direction=Direction.OUTBOUND,
            magnitude=220.0,
        ),
    ]

    selected = monitor._select_swing_reading(readings)  # pylint: disable=protected-access

    assert selected is readings[1]

"""Tests for transport-independent phone control commands."""

from openflight import server as server_module
from openflight.launch_monitor import ClubType


class _Monitor:
    def __init__(self):
        self.clubs = []

    def set_club(self, club):
        self.clubs.append(club)


def test_apply_club_selection_updates_monitor_and_broadcasts(monkeypatch):
    monitor = _Monitor()
    emitted = []
    monkeypatch.setattr(server_module, "monitor", monitor)
    monkeypatch.setattr(
        server_module.socketio, "emit", lambda event, data: emitted.append((event, data))
    )

    response, status = server_module.apply_club_selection({"club": "7-iron"})

    assert status == 200
    assert response == {"status": "applied", "club": "7-iron"}
    assert monitor.clubs == [ClubType.IRON_7]
    assert emitted == [("club_changed", {"club": "7-iron"})]


def test_apply_club_selection_rejects_unknown_club(monkeypatch):
    monitor = _Monitor()
    monkeypatch.setattr(server_module, "monitor", monitor)

    response, status = server_module.apply_club_selection({"club": "putter"})

    assert status == 400
    assert "Unknown club" in response["error"]
    assert monitor.clubs == []


def test_wifi_club_endpoint_uses_shared_selection_logic(monkeypatch):
    monitor = _Monitor()
    monkeypatch.setattr(server_module, "monitor", monitor)

    response = server_module.app.test_client().post(
        "/api/club",
        json={"club": "pw"},
    )

    assert response.status_code == 200
    assert response.get_json() == {"status": "applied", "club": "pw"}
    assert monitor.clubs == [ClubType.PW]


def test_control_dispatch_routes_club_command(monkeypatch):
    monitor = _Monitor()
    monkeypatch.setattr(server_module, "monitor", monitor)

    response, status = server_module.dispatch_phone_control_command("set_club", {"club": "3-wood"})

    assert status == 200
    assert response["club"] == "3-wood"
    assert monitor.clubs == [ClubType.WOOD_3]

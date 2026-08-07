"""Fan out completed shots to HTTP clients as Server-Sent Events.

This is the Wi-Fi sibling of the BLE publisher: same versioned payload, same
bounded-queue delivery policy, same isolation from shot recording. It exists so
a phone can receive shots over the network on hardware where BLE advertising is
unavailable, and so the payload contract can be exercised with nothing but
``curl``.
"""

from __future__ import annotations

import logging
import queue
import threading
from typing import Iterator, Mapping

# The wire payload is the same versioned V1 shot event the BLE transport sends,
# so both transports are validated against one contract and one test fixture.
from .ble.protocol import encode_club_event, encode_shot_event

logger = logging.getLogger(__name__)

SSE_MIMETYPE = "text/event-stream"
DEFAULT_HEARTBEAT_INTERVAL_S = 15.0
DEFAULT_MAX_SUBSCRIBERS = 8

# An SSE comment. Clients ignore it, but it keeps idle connections from being
# reaped and lets the server notice a vanished client between shots.
HEARTBEAT_FRAME = ": ping\n\n"


class ShotStreamFull(RuntimeError):
    """Raised when the broker already serves the maximum number of clients."""


class StreamEvent(bytes):
    """Encoded JSON carrying its SSE name while remaining bytes-compatible."""

    name: str

    def __new__(cls, name: str, payload: bytes):
        event = super().__new__(cls, payload)
        event.name = name
        return event


def format_event(event: StreamEvent | bytes) -> str:
    """Frame one encoded event for the SSE wire protocol.

    ``encode_shot_event`` emits compact single-line JSON, so the payload never
    needs to be split across multiple ``data:`` lines.
    """
    name = event.name if isinstance(event, StreamEvent) else "shot"
    return f"event: {name}\ndata: {event.decode('utf-8')}\n\n"


class ShotStreamBroker:
    """Deliver encoded shot events to every connected SSE subscriber."""

    def __init__(
        self,
        *,
        queue_size: int = 8,
        heartbeat_interval_s: float = DEFAULT_HEARTBEAT_INTERVAL_S,
        max_subscribers: int = DEFAULT_MAX_SUBSCRIBERS,
    ):
        if queue_size < 1:
            raise ValueError("Shot stream queue size must be at least one")
        if heartbeat_interval_s <= 0:
            raise ValueError("Shot stream heartbeat interval must be positive")
        if max_subscribers < 1:
            raise ValueError("Shot stream must allow at least one subscriber")

        self.queue_size = queue_size
        self.heartbeat_interval_s = heartbeat_interval_s
        self.max_subscribers = max_subscribers

        self._lock = threading.Lock()
        self._subscribers: list[queue.Queue[StreamEvent]] = []
        self._latest_payload: bytes | None = None

    @property
    def subscriber_count(self) -> int:
        """How many clients are currently streaming."""
        with self._lock:
            return len(self._subscribers)

    def publish(self, shot_data: Mapping) -> bool:
        """Encode a shot and hand it to every subscriber; never raises upward."""
        try:
            payload = encode_shot_event(shot_data)
        except (KeyError, TypeError, ValueError):
            logger.warning("[STREAM] Failed to encode shot payload", exc_info=True)
            return False

        with self._lock:
            self._latest_payload = payload
            subscribers = list(self._subscribers)
        event = StreamEvent("shot", payload)
        for subscriber in subscribers:
            self._offer(subscriber, event)
        return True

    def publish_club(self, club: str) -> bool:
        """Broadcast an authoritative club change to every Wi-Fi subscriber."""
        try:
            event = StreamEvent("club_changed", encode_club_event(club))
        except (TypeError, ValueError):
            logger.warning("[STREAM] Failed to encode club payload", exc_info=True)
            return False

        with self._lock:
            subscribers = list(self._subscribers)
        for subscriber in subscribers:
            self._offer(subscriber, event)
        return True

    def subscribe(self) -> queue.Queue[StreamEvent]:
        """Register a subscriber, seeded with the latest shot for replay."""
        with self._lock:
            if len(self._subscribers) >= self.max_subscribers:
                raise ShotStreamFull(f"Shot stream already has {self.max_subscribers} clients")
            subscriber: queue.Queue[StreamEvent] = queue.Queue(maxsize=self.queue_size)
            if self._latest_payload is not None:
                subscriber.put_nowait(StreamEvent("shot", self._latest_payload))
            self._subscribers.append(subscriber)
            count = len(self._subscribers)
        logger.info("[STREAM] Client subscribed (%d streaming)", count)
        return subscriber

    def unsubscribe(self, subscriber: queue.Queue[StreamEvent]) -> None:
        """Drop a subscriber. Unsubscribing twice is not an error."""
        with self._lock:
            if subscriber not in self._subscribers:
                return
            self._subscribers.remove(subscriber)
            count = len(self._subscribers)
        logger.info("[STREAM] Client unsubscribed (%d streaming)", count)

    def frames(self, subscriber: queue.Queue[StreamEvent]) -> Iterator[str]:
        """Yield SSE frames for an already-registered subscriber.

        Registration is deliberately not folded in here: a generator body does
        not run until first iteration, so a caller that needs to reject a client
        before sending response headers has to call ``subscribe`` itself.
        """
        try:
            # Open with a heartbeat so the WSGI server flushes response headers
            # at once. Without it a client learns nothing -- not even that it
            # connected -- until the first shot or heartbeat, because headers
            # are not written until the first chunk of the body.
            yield HEARTBEAT_FRAME
            while True:
                try:
                    event = subscriber.get(timeout=self.heartbeat_interval_s)
                except queue.Empty:
                    yield HEARTBEAT_FRAME
                    continue
                yield format_event(event)
        finally:
            self.unsubscribe(subscriber)

    def _offer(self, subscriber: queue.Queue[StreamEvent], event: StreamEvent) -> None:
        """Queue an event, dropping the oldest unsent event when full."""
        try:
            subscriber.put_nowait(event)
            return
        except queue.Full:
            pass

        try:
            subscriber.get_nowait()
            logger.warning("[STREAM] Delivery queue full; dropped oldest unsent shot")
        except queue.Empty:
            pass

        try:
            subscriber.put_nowait(event)
        except queue.Full:
            logger.warning("[STREAM] Delivery queue still full; dropped shot")

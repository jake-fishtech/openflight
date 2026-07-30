"""Non-blocking BLE GATT publisher backed by Bless/BlueZ."""

from __future__ import annotations

import asyncio
import logging
import threading
from typing import Mapping

from .protocol import SERVICE_UUID, SHOT_CHARACTERISTIC_UUID, encode_shot_event, fragment_payload

logger = logging.getLogger(__name__)


class BleShotPublisher:
    """Publish completed shots without coupling the radar thread to Bluetooth."""

    def __init__(
        self,
        *,
        name: str = "OpenFlight",
        queue_size: int = 8,
        fragment_interval_s: float = 0.01,
    ):
        if queue_size < 1:
            raise ValueError("BLE queue size must be at least one")
        self.name = name
        self.queue_size = queue_size
        self.fragment_interval_s = fragment_interval_s

        self._state_lock = threading.Lock()
        self._thread: threading.Thread | None = None
        self._loop: asyncio.AbstractEventLoop | None = None
        self._queue: asyncio.Queue[bytes] | None = None
        self._stop_event: asyncio.Event | None = None
        self._stop_requested = threading.Event()
        self._server = None
        self._latest_payload: bytes | None = None
        self._subscribed = False
        self._sequence = 0

    @property
    def subscribed(self) -> bool:
        """Whether at least one central is subscribed to shot notifications."""
        with self._state_lock:
            return self._subscribed

    def start(self) -> None:
        """Start advertising in a daemon thread; startup failures remain isolated."""
        with self._state_lock:
            if self._thread and self._thread.is_alive():
                return
            self._stop_requested.clear()
            self._thread = threading.Thread(
                target=self._run_thread,
                name="openflight-ble",
                daemon=True,
            )
            self._thread.start()

    def stop(self) -> None:
        """Stop advertising and join the BLE thread."""
        self._stop_requested.set()
        with self._state_lock:
            loop = self._loop
            stop_event = self._stop_event
            thread = self._thread
        if loop and stop_event:
            loop.call_soon_threadsafe(stop_event.set)
        if thread and thread is not threading.current_thread():
            thread.join(timeout=5.0)
            if thread.is_alive():
                logger.warning("[BLE] Publisher thread did not stop within 5 seconds")

    def publish(self, shot_data: Mapping) -> bool:
        """Store the latest shot and enqueue it when a central is subscribed."""
        try:
            payload = encode_shot_event(shot_data)
        except (KeyError, TypeError, ValueError):
            logger.warning("[BLE] Failed to encode shot payload", exc_info=True)
            return False

        with self._state_lock:
            self._latest_payload = payload
            loop = self._loop
            subscribed = self._subscribed
        if loop and subscribed:
            loop.call_soon_threadsafe(self._enqueue_payload, payload)
        return True

    def _run_thread(self) -> None:
        try:
            asyncio.run(self._run())
        except Exception:  # pylint: disable=broad-exception-caught
            logger.warning(
                "[BLE] Bluetooth unavailable; shot recording will continue without BLE",
                exc_info=True,
            )
        finally:
            with self._state_lock:
                self._loop = None
                self._queue = None
                self._stop_event = None
                self._server = None
                self._subscribed = False

    async def _run(self) -> None:
        # Bless is an optional dependency and must not affect non-BLE installs.
        from bless import (  # pylint: disable=import-error,import-outside-toplevel
            BlessServer,
            GATTAttributePermissions,
            GATTCharacteristicProperties,
        )

        loop = asyncio.get_running_loop()
        queue: asyncio.Queue[bytes] = asyncio.Queue(maxsize=self.queue_size)
        stop_event = asyncio.Event()
        server = BlessServer(
            name=self.name,
            loop=loop,
            on_subscribe=self._on_subscribe,
            on_unsubscribe=self._on_unsubscribe,
        )
        await server.add_new_service(SERVICE_UUID)
        await server.add_new_characteristic(
            SERVICE_UUID,
            SHOT_CHARACTERISTIC_UUID,
            GATTCharacteristicProperties.notify,
            bytearray(),
            GATTAttributePermissions.readable,
        )

        with self._state_lock:
            self._loop = loop
            self._queue = queue
            self._stop_event = stop_event
            self._server = server

        await server.start()
        logger.info("[BLE] Advertising %s", self.name)
        if self._stop_requested.is_set():
            stop_event.set()

        worker = asyncio.create_task(self._delivery_worker())
        try:
            await stop_event.wait()
        finally:
            worker.cancel()
            await asyncio.gather(worker, return_exceptions=True)
            await server.stop()
            logger.info("[BLE] Advertising stopped")

    def _on_subscribe(self, _characteristic, _session) -> None:
        with self._state_lock:
            self._subscribed = True
            latest_payload = self._latest_payload
        logger.info("[BLE] iOS client subscribed")
        if latest_payload is not None:
            self._enqueue_payload(latest_payload)

    def _on_unsubscribe(self, _characteristic, _session) -> None:
        with self._state_lock:
            self._subscribed = False
        self._clear_queue()
        logger.info("[BLE] iOS client unsubscribed")

    def _enqueue_payload(self, payload: bytes) -> None:
        with self._state_lock:
            queue = self._queue
            subscribed = self._subscribed
        if queue is None or not subscribed:
            return
        if queue.full():
            try:
                queue.get_nowait()
                queue.task_done()
                logger.warning("[BLE] Delivery queue full; dropped oldest unsent shot")
            except asyncio.QueueEmpty:
                pass
        queue.put_nowait(payload)

    def _clear_queue(self) -> None:
        with self._state_lock:
            queue = self._queue
        if queue is None:
            return
        while True:
            try:
                queue.get_nowait()
                queue.task_done()
            except asyncio.QueueEmpty:
                return

    async def _delivery_worker(self) -> None:
        with self._state_lock:
            queue = self._queue
        if queue is None:
            return
        while True:
            payload = await queue.get()
            try:
                await self._send_payload(payload)
            except Exception:  # pylint: disable=broad-exception-caught
                logger.warning("[BLE] Failed to notify shot payload", exc_info=True)
            finally:
                queue.task_done()

    async def _send_payload(self, payload: bytes) -> None:
        with self._state_lock:
            server = self._server
            subscribed = self._subscribed
            sequence = self._sequence
            self._sequence = (self._sequence + 1) & 0xFFFF
        if server is None or not subscribed:
            return

        characteristic = server.get_characteristic(SHOT_CHARACTERISTIC_UUID)
        if characteristic is None:
            raise RuntimeError("BLE shot characteristic is unavailable")

        for frame in fragment_payload(payload, sequence=sequence):
            with self._state_lock:
                if not self._subscribed:
                    return
            characteristic.value = bytearray(frame)
            if not server.update_value(SERVICE_UUID, SHOT_CHARACTERISTIC_UUID):
                raise RuntimeError("BLE notification update failed")
            await asyncio.sleep(self.fragment_interval_s)

"""Non-blocking BLE GATT publisher backed by Bless/BlueZ."""

from __future__ import annotations

import asyncio
import json
import logging
import threading
from collections.abc import Callable
from typing import Any, Mapping

from .protocol import (
    CONTROL_CHARACTERISTIC_UUID,
    SCHEMA_VERSION,
    SERVICE_UUID,
    SHOT_CHARACTERISTIC_UUID,
    FragmentReassembler,
    encode_club_event,
    encode_shot_event,
    fragment_payload,
)

logger = logging.getLogger(__name__)


class BleShotPublisher:
    """Publish completed shots without coupling the radar thread to Bluetooth."""

    def __init__(
        self,
        *,
        name: str = "OpenFlight",
        queue_size: int = 8,
        fragment_interval_s: float = 0.01,
        command_handler: Callable[[str, Mapping], tuple[dict, int]] | None = None,
    ):
        if queue_size < 1:
            raise ValueError("BLE queue size must be at least one")
        self.name = name
        self.queue_size = queue_size
        self.fragment_interval_s = fragment_interval_s
        self.command_handler = command_handler

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
        self._control_sequence = 0
        self._control_reassembler = FragmentReassembler()
        self._control_send_lock: asyncio.Lock | None = None

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

    def publish_club(self, club: str) -> bool:
        """Notify connected centrals that the authoritative club changed."""
        try:
            payload = encode_club_event(club)
        except (TypeError, ValueError):
            logger.warning("[BLE] Failed to encode club payload", exc_info=True)
            return False

        with self._state_lock:
            loop = self._loop
            subscribed = self._subscribed
        if loop and subscribed:
            asyncio.run_coroutine_threadsafe(self._send_control_response(payload), loop)
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
                self._control_send_lock = None

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
        await server.add_new_characteristic(
            SERVICE_UUID,
            CONTROL_CHARACTERISTIC_UUID,
            GATTCharacteristicProperties.write | GATTCharacteristicProperties.notify,
            bytearray(),
            GATTAttributePermissions.readable | GATTAttributePermissions.writeable,
        )
        server.write_request_func = self._on_write_request
        self._install_bluez_subscription_hooks(server)

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

    def _install_bluez_subscription_hooks(self, server) -> None:
        """Wire callbacks that Bless 0.3.0 leaves disconnected on BlueZ.

        Bless's Linux backend accepts ``on_subscribe`` and ``on_unsubscribe``
        constructor keywords but replaces the underlying BlueZ ``StartNotify``
        and ``StopNotify`` handlers with no-ops. Hook the application object
        after asynchronous server setup so delivery state follows the iOS
        notification subscription.
        """
        app = getattr(server, "app", None)
        if app is None:
            return
        app.StartNotify = lambda session: self._on_subscribe(None, session)
        app.StopNotify = lambda session: self._on_unsubscribe(None, session)

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

    def _on_write_request(self, characteristic, value, **_kwargs) -> None:
        """Receive one framed phone control command from the writable GATT value."""
        if str(getattr(characteristic, "uuid", "")).lower() != CONTROL_CHARACTERISTIC_UUID.lower():
            return
        characteristic.value = bytearray(value)
        try:
            payload = self._control_reassembler.append(bytes(value))
        except ValueError:
            logger.warning("[BLE] Rejected malformed control frame", exc_info=True)
            self._control_reassembler.reset()
            return
        if payload is None:
            return

        with self._state_lock:
            loop = self._loop
        if loop is None:
            return
        asyncio.run_coroutine_threadsafe(self._process_control_payload(payload), loop)

    async def _process_control_payload(self, payload: bytes) -> None:
        request_id = "unknown"
        try:
            command = json.loads(payload)
            if not isinstance(command, dict):
                raise ValueError("Control command must be a JSON object")
            request_id = command.get("request_id")
            command_type = command.get("type")
            command_payload = command.get("payload")
            if command.get("schema_version") != SCHEMA_VERSION:
                raise ValueError("Unsupported control schema version")
            if not isinstance(request_id, str) or not request_id:
                raise ValueError("Control command requires a request_id")
            if not isinstance(command_type, str) or not command_type:
                raise ValueError("Control command requires a type")
            if not isinstance(command_payload, dict):
                raise ValueError("Control command payload must be an object")
            if self.command_handler is None:
                raise ValueError("Phone controls are not configured on this OpenFlight server")

            result, status = await asyncio.to_thread(
                self.command_handler,
                command_type,
                command_payload,
            )
            if status < 200 or status >= 300:
                error = result.get("error", f"Control command failed with status {status}")
                response = self._control_response(request_id, error=str(error))
            else:
                response = self._control_response(request_id, result=result)
        except (UnicodeDecodeError, json.JSONDecodeError, TypeError, ValueError) as error:
            response = self._control_response(str(request_id or "unknown"), error=str(error))
        except Exception:  # pylint: disable=broad-exception-caught
            logger.exception("[BLE] Phone control command failed")
            response = self._control_response(
                str(request_id or "unknown"),
                error="OpenFlight could not apply the phone command",
            )

        encoded = json.dumps(
            response,
            allow_nan=False,
            ensure_ascii=True,
            separators=(",", ":"),
            sort_keys=True,
        ).encode("utf-8")
        await self._send_control_response(encoded)

    @staticmethod
    def _control_response(
        request_id: str,
        *,
        result: Mapping[str, Any] | None = None,
        error: str | None = None,
    ) -> dict:
        response = {
            "schema_version": SCHEMA_VERSION,
            "request_id": request_id,
            "ok": error is None,
        }
        if error is None:
            response["result"] = dict(result or {})
        else:
            response["error"] = error
        return response

    async def _send_control_response(self, payload: bytes) -> None:
        if self._control_send_lock is None:
            self._control_send_lock = asyncio.Lock()
        async with self._control_send_lock:
            await self._send_control_payload(payload)

    async def _send_control_payload(self, payload: bytes) -> None:
        """Send one complete control message without interleaving fragments."""
        with self._state_lock:
            server = self._server
            subscribed = self._subscribed
            sequence = self._control_sequence
            self._control_sequence = (self._control_sequence + 1) & 0xFFFF
        if server is None or not subscribed:
            return

        characteristic = server.get_characteristic(CONTROL_CHARACTERISTIC_UUID)
        if characteristic is None:
            raise RuntimeError("BLE control characteristic is unavailable")
        for frame in fragment_payload(payload, sequence=sequence):
            characteristic.value = bytearray(frame)
            if not server.update_value(SERVICE_UUID, CONTROL_CHARACTERISTIC_UUID):
                raise RuntimeError("BLE control notification update failed")
            await asyncio.sleep(self.fragment_interval_s)

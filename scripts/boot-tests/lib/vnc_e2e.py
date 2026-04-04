#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import socket
import struct
import sys
import time
from collections import Counter
from dataclasses import dataclass
from typing import Callable


def fail(message: str) -> None:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


KEYSYM_ALT_L = 0xFFE9
KEYSYM_BACKSPACE = 0xFF08
KEYSYM_ENTER = 0xFF0D
KEYSYM_UP = 0xFF52
KEYSYM_DOWN = 0xFF54
KEYSYM_F3 = 0xFFC0
KEYSYM_F4 = 0xFFC1
KEYSYM_F5 = 0xFFC2
KEYSYM_F6 = 0xFFC3
KEYSYM_F7 = 0xFFC4
KEYSYM_F8 = 0xFFC5
KEYSYM_F9 = 0xFFC6
KEYSYM_F10 = 0xFFC7
KEYSYM_F1 = 0xFFBE
KEYSYM_F2 = 0xFFBF
KEYSYM_F11 = 0xFFC8
KEYSYM_F12 = 0xFFC9

QCODE_KEYS = {
    "alt": "alt",
    "backspace": "backspace",
    "arrowdown": "down",
    "arrowup": "up",
    "down": "down",
    "enter": "ret",
    "f1": "f1",
    "f2": "f2",
    "f3": "f3",
    "f4": "f4",
    "f5": "f5",
    "f6": "f6",
    "f7": "f7",
    "f8": "f8",
    "f9": "f9",
    "f10": "f10",
    "f11": "f11",
    "f12": "f12",
    "up": "up",
    "spc": "spc",
}


def normalize_keysym(value: int | str) -> int:
    if isinstance(value, int):
        return value
    if len(value) == 1 and value.isascii():
        return ord(value)
    mapping = {
        "ArrowDown": KEYSYM_DOWN,
        "ArrowUp": KEYSYM_UP,
        "Backspace": KEYSYM_BACKSPACE,
        "Enter": KEYSYM_ENTER,
        "F1": KEYSYM_F1,
        "F2": KEYSYM_F2,
        "F3": KEYSYM_F3,
        "F4": KEYSYM_F4,
        "F5": KEYSYM_F5,
        "F6": KEYSYM_F6,
        "F7": KEYSYM_F7,
        "F8": KEYSYM_F8,
        "F9": KEYSYM_F9,
        "F10": KEYSYM_F10,
        "F11": KEYSYM_F11,
        "F12": KEYSYM_F12,
    }
    if value in mapping:
        return mapping[value]
    fail(f"unsupported VNC keysym: {value!r}")


def normalize_qcode_key(key_name: str) -> str:
    lower = key_name.lower()
    if lower in QCODE_KEYS:
        return QCODE_KEYS[lower]
    if len(key_name) == 1 and (key_name.isalpha() or key_name.isdigit()):
        return key_name.lower()
    if key_name in (" ",):
        return "spc"
    fail(f"unsupported QMP key name: {key_name!r}")


class VNCClient:
    def __init__(self, socket_path: str, timeout_secs: float) -> None:
        self.socket_path = socket_path
        self.timeout_secs = timeout_secs
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(timeout_secs)
        self.sock.connect(socket_path)

        self.width = 0
        self.height = 0
        self.bits_per_pixel = 0
        self.bytes_per_pixel = 0
        self.big_endian_flag = 0
        self.red_max = 0
        self.green_max = 0
        self.blue_max = 0
        self.red_shift = 0
        self.green_shift = 0
        self.blue_shift = 0
        self.framebuffer = b""
        self._handshake()

    def _read_exact(self, size: int) -> bytes:
        chunks = bytearray()
        while len(chunks) < size:
            chunk = self.sock.recv(size - len(chunks))
            if not chunk:
                fail("VNC socket closed unexpectedly")
            chunks.extend(chunk)
        return bytes(chunks)

    def _read_u8(self) -> int:
        return self._read_exact(1)[0]

    def _read_u16(self) -> int:
        return struct.unpack(">H", self._read_exact(2))[0]

    def _read_i32(self) -> int:
        return struct.unpack(">i", self._read_exact(4))[0]

    def _handshake(self) -> None:
        version = self._read_exact(12)
        if not version.startswith(b"RFB "):
            fail(f"unexpected VNC version banner: {version!r}")
        self.sock.sendall(version)

        security_count = self._read_u8()
        if security_count == 0:
            reason_size = struct.unpack(">I", self._read_exact(4))[0]
            reason = self._read_exact(reason_size).decode("utf-8", "replace")
            fail(f"VNC refused security negotiation: {reason}")
        security_types = self._read_exact(security_count)
        if 1 not in security_types:
            fail(f"VNC does not offer no-auth: {list(security_types)}")
        self.sock.sendall(b"\x01")

        result = struct.unpack(">I", self._read_exact(4))[0]
        if result != 0:
            fail(f"VNC security setup failed ({result})")

        # Signal shared desktop mode, per VNC client-init protocol.
        self.sock.sendall(b"\x01")

        self.width, self.height = self._read_u16(), self._read_u16()

        pixel_format = self._read_exact(16)
        (
            self.bits_per_pixel,
            _depth,
            self.big_endian_flag,
            _true_color,
            self.red_max,
            self.green_max,
            self.blue_max,
            self.red_shift,
            self.green_shift,
            self.blue_shift,
            _,
        ) = struct.unpack(">BBBBHHHBBB3s", pixel_format)
        self.bytes_per_pixel = self.bits_per_pixel // 8
        if self.bytes_per_pixel <= 0:
            fail(f"unsupported pixel depth: {self.bits_per_pixel}")

        name_length = struct.unpack(">I", self._read_exact(4))[0]
        self._read_exact(name_length)
        self.framebuffer = b"\x00" * (self.width * self.height * self.bytes_per_pixel)

    def close(self) -> None:
        try:
            self.sock.close()
        except OSError:
            pass

    def request_frame(self) -> None:
        self.sock.sendall(
            struct.pack(
                ">BBHHHH",
                3,
                0,
                0,
                0,
                self.width,
                self.height,
            )
        )

    def _read_server_frame(self) -> None:
        while True:
            msg_type = self._read_u8()
            if msg_type == 0:
                self._read_exact(1)
                rects = struct.unpack(">H", self._read_exact(2))[0]
                if rects == 0:
                    continue
                framebuffer = bytearray(self.framebuffer)
                for _ in range(rects):
                    x = struct.unpack(">H", self._read_exact(2))[0]
                    y = struct.unpack(">H", self._read_exact(2))[0]
                    w = struct.unpack(">H", self._read_exact(2))[0]
                    h = struct.unpack(">H", self._read_exact(2))[0]
                    encoding = self._read_i32()
                    if encoding != 0:
                        payload_len = (w * h * self.bytes_per_pixel)
                        self._read_exact(payload_len)
                        continue
                    payload = self._read_exact(w * h * self.bytes_per_pixel)
                    for row in range(h):
                        dst_y = y + row
                        if dst_y >= self.height:
                            break
                        copy_w = min(w, self.width - x)
                        if copy_w <= 0:
                            continue
                        src = row * w * self.bytes_per_pixel
                        dst = (dst_y * self.width + x) * self.bytes_per_pixel
                        end = src + copy_w * self.bytes_per_pixel
                        framebuffer[dst : dst + copy_w * self.bytes_per_pixel] = payload[src:end]
                self.framebuffer = bytes(framebuffer)
                return
            if msg_type == 2:
                continue
            if msg_type == 1:
                self._read_exact(1)
                first_color = self._read_u16()
                color_count = self._read_u16()
                self._read_exact(color_count * 6)
                continue
            if msg_type == 3:
                self._read_exact(3)
                text_len = struct.unpack(">I", self._read_exact(4))[0]
                self._read_exact(text_len)
                continue
            if msg_type == 4:
                continue
            fail(f"unsupported VNC server message: {msg_type}")

    def capture(self) -> bytes:
        self.request_frame()
        self._read_server_frame()
        return self.framebuffer

    def key_event(self, keysym: int | str, down: bool) -> None:
        keysym = normalize_keysym(keysym)
        self.sock.sendall(struct.pack(">BBHI", 4, 1 if down else 0, 0, keysym))

    def tap(self, keysym: int | str, delay_secs: float = 0.05) -> None:
        self.key_event(keysym, True)
        time.sleep(delay_secs)
        self.key_event(keysym, False)


class QMPClient:
    def __init__(self, path: str, timeout_secs: float) -> None:
        self.path = path
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(timeout_secs)
        self.sock.connect(path)
        self.file = self.sock.makefile("rwb", buffering=0)
        self._handshake()

    def _read_message(self) -> dict:
        while True:
            line = self.file.readline()
            if not line:
                fail("QMP socket closed unexpectedly")
            payload = json.loads(line.decode("utf-8"))
            if "event" in payload:
                continue
            return payload

    def _handshake(self) -> None:
        greeting = self._read_message()
        if "QMP" not in greeting:
            fail(f"unexpected QMP greeting: {greeting!r}")
        self.execute("qmp_capabilities")

    def close(self) -> None:
        try:
            self.file.close()
        except OSError:
            pass
        try:
            self.sock.close()
        except OSError:
            pass

    def execute(self, command: str, arguments: dict | None = None) -> dict:
        request = {"execute": command}
        if arguments is not None:
            request["arguments"] = arguments
        self.file.write(json.dumps(request).encode("utf-8") + b"\n")
        response = self._read_message()
        if "error" in response:
            fail(f"QMP command failed ({command}): {response['error']}")
        return response

    def ensure_running(self) -> None:
        status = self.execute("query-status").get("return", {})
        if isinstance(status, dict) and status.get("status") == "paused":
            self.execute("cont")
            time.sleep(0.05)

    def key_event(self, key_name: str, down: bool) -> None:
        key = normalize_qcode_key(key_name)
        self.execute(
            "input-send-event",
            {
                "events": [
                    {
                        "type": "key",
                        "data": {
                            "down": down,
                            "key": {
                                "type": "qcode",
                                "data": key,
                            },
                        },
                    }
                ],
            },
        )


class InputBackend:
    def tap(self, key: str) -> None:
        raise NotImplementedError

    def type_text(self, text: str) -> None:
        raise NotImplementedError

    def chord(self, keys: list[str]) -> None:
        raise NotImplementedError

    def alt_a_prefix(self) -> None:
        raise NotImplementedError


class QmpInput(InputBackend):
    def __init__(self, qmp: QMPClient) -> None:
        self.qmp = qmp

    def _send(self, key_name: str, down: bool) -> None:
        self.qmp.ensure_running()
        self.qmp.key_event(key_name, down)

    def _tap(self, key_name: str, delay_secs: float = 0.05) -> None:
        self._send(key_name, True)
        time.sleep(delay_secs)
        self._send(key_name, False)
        time.sleep(0.12)

    def tap(self, key: str) -> None:
        self._tap(key)

    def type_text(self, text: str) -> None:
        for c in text:
            self._tap(c)

    def chord(self, keys: list[str]) -> None:
        for key in keys:
            self._send(key, True)
        time.sleep(0.08)
        for key in reversed(keys):
            self._send(key, False)
        time.sleep(0.12)

    def alt_a_prefix(self) -> None:
        self.chord(["Alt", "a"])


def _pixel_color(client: VNCClient, pixel: bytes) -> tuple[int, int, int]:
    raw = int.from_bytes(pixel, "big" if client.big_endian_flag else "little")
    red = (raw >> client.red_shift) & client.red_max
    green = (raw >> client.green_shift) & client.green_max
    blue = (raw >> client.blue_shift) & client.blue_max
    if client.red_max:
        red = int(red * 255 / client.red_max)
    if client.green_max:
        green = int(green * 255 / client.green_max)
    if client.blue_max:
        blue = int(blue * 255 / client.blue_max)
    return red, green, blue


def cell_metrics(width: int, height: int) -> tuple[int, int]:
    return max(1, width // 80), max(1, height // 25)


def crop(
    framebuffer: bytes,
    width: int,
    height: int,
    bpp: int,
    x: int,
    y: int,
    w: int,
    h: int,
) -> bytes:
    rows: list[bytes] = []
    for row in range(y, y + h):
        if row >= height:
            break
        row_start = (row * width + x) * bpp
        row_end = row_start + (w * bpp)
        if x < 0 or x >= width or row_start < 0 or row_end < 0:
            continue
        row_end = min(row_end, (row + 1) * width * bpp)
        if row_start >= row_end:
            continue
        rows.append(framebuffer[row_start:row_end])
    return b"".join(rows)


def top_left_text_region(client: VNCClient, frame: bytes) -> bytes:
    cell_w, cell_h = cell_metrics(client.width, client.height)
    return crop(
        frame,
        client.width,
        client.height,
        client.bytes_per_pixel,
        0,
        0,
        12 * cell_w,
        2 * cell_h,
    )


def top_left_body_region(client: VNCClient, frame: bytes) -> bytes:
    cell_w, cell_h = cell_metrics(client.width, client.height)
    return crop(
        frame,
        client.width,
        client.height,
        client.bytes_per_pixel,
        cell_w,
        0,
        11 * cell_w,
        2 * cell_h,
    )


def top_left_cell_region(client: VNCClient, frame: bytes) -> bytes:
    cell_w, cell_h = cell_metrics(client.width, client.height)
    return crop(
        frame,
        client.width,
        client.height,
        client.bytes_per_pixel,
        0,
        0,
        cell_w,
        cell_h,
    )


def compact_origin_region(client: VNCClient, frame: bytes) -> bytes:
    cell_w, cell_h = cell_metrics(client.width, client.height)
    return crop(
        frame,
        client.width,
        client.height,
        client.bytes_per_pixel,
        20 * cell_w,
        7 * cell_h,
        3 * cell_w,
        cell_h,
    )


def top_right_label_region(client: VNCClient, frame: bytes) -> bytes:
    cell_w, cell_h = cell_metrics(client.width, client.height)
    return crop(
        frame,
        client.width,
        client.height,
        client.bytes_per_pixel,
        client.width - (14 * cell_w),
        0,
        14 * cell_w,
        cell_h,
    )


def boot_text_region(client: VNCClient, frame: bytes) -> bytes:
    cell_w, cell_h = cell_metrics(client.width, client.height)
    return crop(
        frame,
        client.width,
        client.height,
        client.bytes_per_pixel,
        0,
        0,
        1 * cell_w,
        cell_h,
    )


RegionFn = Callable[[VNCClient, bytes], bytes]

REGIONS: dict[str, RegionFn] = {
    "top_left_text": top_left_text_region,
    "top_left_body": top_left_body_region,
    "top_left_cell": top_left_cell_region,
    "compact_origin": compact_origin_region,
    "top_right_label": top_right_label_region,
    "boot_text": boot_text_region,
}


@dataclass
class CaptureSample:
    payload: bytes
    background: bytes
    hash: str


def _region_hash(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def _dominant_pixel(payload: bytes, bpp: int) -> bytes:
    if not payload:
        return b"\x00" * bpp
    counter = Counter(payload[i : i + bpp] for i in range(0, len(payload), bpp))
    return counter.most_common(1)[0][0]


def _has_foreground(payload: bytes, background: bytes, bpp: int) -> bool:
    for i in range(0, len(payload), bpp):
        if payload[i : i + bpp] != background:
            return True
    return False


def _unique_foreground_pixels(payload: bytes, background: bytes, bpp: int) -> list[bytes]:
    return [
        payload[i : i + bpp]
        for i in range(0, len(payload), bpp)
        if payload[i : i + bpp] != background
    ]


def _color_distance(a: tuple[int, int, int], b: tuple[int, int, int]) -> int:
    return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])


def _is_visible_text_color(
    pixel_rgb: tuple[int, int, int],
    background_rgb: tuple[int, int, int],
) -> bool:
    distance = _color_distance(pixel_rgb, background_rgb)
    if distance <= 80:
        return False
    luminance = int(0.299 * pixel_rgb[0] + 0.587 * pixel_rgb[1] + 0.114 * pixel_rgb[2])
    bg_luminance = int(
        0.299 * background_rgb[0] + 0.587 * background_rgb[1] + 0.114 * background_rgb[2]
    )
    return abs(luminance - bg_luminance) >= 28


def _wait_for_visible_frame(client: VNCClient, timeout_secs: float) -> bytes:
    deadline = time.time() + timeout_secs
    last = b""
    while time.time() < deadline:
        frame = client.capture()
        background = frame[: client.bytes_per_pixel]
        if _has_foreground(frame, background, client.bytes_per_pixel):
            return frame
        last = frame
        time.sleep(0.1)
    return last


def _capture_until_change(
    client: VNCClient,
    region: str,
    before: CaptureSample,
    timeout_secs: float,
    poll_interval_secs: float = 0.08,
) -> CaptureSample:
    end = time.time() + timeout_secs
    while time.time() < end:
        candidate = capture_region(
            client,
            region=region,
            wait_boot=False,
            timeout_secs=1.0,
        )
        if candidate.hash != before.hash:
            return candidate
        time.sleep(poll_interval_secs)
    fail("timeout waiting for region change")


def _capture_until_match(
    client: VNCClient,
    region: str,
    target: CaptureSample,
    timeout_secs: float,
    poll_interval_secs: float = 0.08,
) -> CaptureSample:
    end = time.time() + timeout_secs
    while time.time() < end:
        candidate = capture_region(
            client,
            region=region,
            wait_boot=False,
            timeout_secs=1.0,
        )
        if candidate.hash == target.hash:
            return candidate
        time.sleep(poll_interval_secs)
    fail("timeout waiting for region match")


def _capture_until_foreground(
    client: VNCClient,
    region: str,
    timeout_secs: float,
    poll_interval_secs: float,
) -> CaptureSample | None:
    end = time.time() + timeout_secs
    while time.time() < end:
        candidate = capture_region(
            client,
            region=region,
            wait_boot=False,
            timeout_secs=1.0,
        )
        if _has_foreground(candidate.payload, candidate.background, len(candidate.background)):
            return candidate
        time.sleep(poll_interval_secs)
    return None


def _capture_until_blank(
    client: VNCClient,
    region: str,
    timeout_secs: float,
    poll_interval_secs: float,
) -> CaptureSample | None:
    end = time.time() + timeout_secs
    while time.time() < end:
        candidate = capture_region(
            client,
            region=region,
            wait_boot=False,
            timeout_secs=1.0,
        )
        if not _has_foreground(candidate.payload, candidate.background, len(candidate.background)):
            return candidate
        time.sleep(poll_interval_secs)
    return None


def _capture_until_stable(
    client: VNCClient,
    region: str,
    timeout_secs: float,
    poll_interval_secs: float,
    required_stable: int,
    wait_boot: bool,
    message: str,
    hold_secs: float = 0.0,
) -> CaptureSample:
    if required_stable < 1:
        required_stable = 1

    hold_deadline: float | None = None
    end = time.time() + timeout_secs
    first = capture_region(
        client=client,
        region=region,
        wait_boot=wait_boot,
        timeout_secs=1.0,
    )
    stable_count = 1
    last = first

    while time.time() < end:
        candidate = capture_region(
            client=client,
            region=region,
            wait_boot=False,
            timeout_secs=1.0,
        )
        if candidate.hash == last.hash:
            stable_count += 1
        else:
            last = candidate
            stable_count = 1
            hold_deadline = None

        if stable_count >= required_stable and hold_deadline is None:
            hold_deadline = time.time() + hold_secs
        if hold_deadline is not None and time.time() >= hold_deadline:
            return last
        time.sleep(poll_interval_secs)

    fail(message)


def capture_region(
    client: VNCClient,
    *,
    region: str,
    wait_boot: bool,
    timeout_secs: float,
) -> CaptureSample:
    frame = _wait_for_visible_frame(client, timeout_secs) if wait_boot else client.capture()
    region_fn = REGIONS.get(region)
    if region_fn is None:
        fail(f"unknown region: {region}")
    payload = region_fn(client, frame)
    # Use the full frame to choose background so small UI regions don't self-select
    # the text color when foreground/background frequencies are similar.
    background = _dominant_pixel(frame, client.bytes_per_pixel)
    return CaptureSample(payload=payload, background=background, hash=_region_hash(payload))


def assert_eq(samples: dict[str, CaptureSample], left: str, right: str, message: str) -> None:
    if samples[left].hash != samples[right].hash:
        fail(message)


def assert_ne(samples: dict[str, CaptureSample], left: str, right: str, message: str) -> None:
    if samples[left].hash == samples[right].hash:
        fail(message)


def assert_foreground(samples: dict[str, CaptureSample], sample_key: str, message: str) -> None:
    sample = samples[sample_key]
    if not _has_foreground(sample.payload, sample.background, len(sample.background)):
        fail(message)


def assert_blank(samples: dict[str, CaptureSample], sample_key: str, message: str) -> None:
    sample = samples[sample_key]
    if _has_foreground(sample.payload, sample.background, len(sample.background)):
        fail(message)


def assert_green_text(client: VNCClient, samples: dict[str, CaptureSample], sample_key: str, message: str) -> None:
    sample = samples[sample_key]
    fg_pixels = _unique_foreground_pixels(sample.payload, sample.background, len(sample.background))
    if not fg_pixels:
        fail(message)
    background_rgb = _pixel_color(client, sample.background)
    has_visible = False
    for px in fg_pixels:
        if _is_visible_text_color(_pixel_color(client, px), background_rgb):
            has_visible = True
            break
    if not has_visible:
        fail(message)


def _execute_steps(
    steps: list[dict],
    client: VNCClient,
    input_backend: InputBackend,
) -> None:
    samples: dict[str, CaptureSample] = {}
    for step in steps:
        op = step["op"]
        if op == "capture_wait_change":
            before = samples[step["from"]]
            samples[step["name"]] = _capture_until_change(
                client=client,
                region=step["region"],
                before=before,
                timeout_secs=float(step.get("timeout_secs", 2.5)),
            )
            continue

        if op == "capture_wait_match":
            target = samples[step["target"]]
            samples[step["name"]] = _capture_until_match(
                client=client,
                region=step["region"],
                target=target,
                timeout_secs=float(step.get("timeout_secs", 3.0)),
            )
            continue

        if op == "capture_wait_foreground":
            sample = _capture_until_foreground(
                client=client,
                region=step["region"],
                timeout_secs=float(step.get("timeout_secs", 2.5)),
                poll_interval_secs=0.08,
            )
            if sample is None:
                fail(step.get("message", f"timeout waiting for foreground in {step['name']}"))
            samples[step["name"]] = sample
            continue

        if op == "capture_wait_blank":
            sample = _capture_until_blank(
                client=client,
                region=step["region"],
                timeout_secs=float(step.get("timeout_secs", 2.5)),
                poll_interval_secs=0.08,
            )
            if sample is None:
                fail(step.get("message", f"timeout waiting for blank region in {step['name']}"))
            samples[step["name"]] = sample
            continue

        if op == "capture_wait_stable":
            samples[step["name"]] = _capture_until_stable(
                client=client,
                region=step["region"],
                timeout_secs=float(step.get("timeout_secs", 3.0)),
                poll_interval_secs=float(step.get("sample_interval_secs", 0.08)),
                required_stable=int(step.get("required_stable", 2)),
                hold_secs=float(step.get("hold_secs", 0.3)),
                wait_boot=bool(step.get("wait_boot", False)),
                message=step.get("message", "timeout waiting for region to become stable"),
            )
            continue

        if op == "sleep":
            time.sleep(float(step["duration_secs"]))
            continue

        if op == "capture":
            samples[step["name"]] = capture_region(
                client,
                region=step["region"],
                wait_boot=bool(step.get("wait_boot", False)),
                timeout_secs=float(step.get("timeout_secs", 8.0)),
            )
            continue

        if op == "capture_after":
            time.sleep(float(step.get("after", 0.0)))
            samples[step["name"]] = capture_region(
                client,
                region=step["region"],
                wait_boot=False,
                timeout_secs=float(step.get("timeout_secs", 8.0)),
            )
            continue

        if op == "tap":
            input_backend.tap(step["key"])
            time.sleep(float(step.get("after", 0.0)))
            continue

        if op == "type_text":
            input_backend.type_text(step["text"])
            time.sleep(float(step.get("after", 0.0)))
            continue

        if op == "chord":
            input_backend.chord(step["keys"])
            time.sleep(float(step.get("after", 0.0)))
            continue

        if op == "alt_a_prefix":
            input_backend.alt_a_prefix()
            time.sleep(float(step.get("after", 0.0)))
            continue

        if op == "assert_eq":
            assert_eq(samples, step["left"], step["right"], step["message"])
            continue

        if op == "assert_ne":
            assert_ne(samples, step["left"], step["right"], step["message"])
            continue

        if op == "assert_foreground":
            assert_foreground(samples, step["sample"], step["message"])
            continue

        if op == "assert_blank":
            assert_blank(samples, step["sample"], step["message"])
            continue

        if op == "assert_green_text":
            assert_green_text(client, samples, step["sample"], step["message"])
            continue

        fail(f"unknown scenario op: {op}")


TERMINAL_LABEL_NAMES = (
    "alpha",
    "beta",
    "gamma",
    "delta",
    "epsilon",
    "zeta",
    "eta",
    "theta",
    "iota",
    "kappa",
    "lambda",
    "mu",
)


def _label_sample_name(index: int) -> str:
    return f"label_{TERMINAL_LABEL_NAMES[index]}"


def _create_terminal_label_steps(target_count: int) -> list[dict]:
    steps: list[dict] = [
        {
            "op": "capture_wait_foreground",
            "name": _label_sample_name(0),
            "region": "top_right_label",
            "timeout_secs": 3.0,
            "message": "alpha terminal label did not appear",
        }
    ]

    for index in range(1, target_count):
        steps.extend(
            [
                {"op": "tap", "key": "F11", "after": 0.45},
                {
                    "op": "capture_wait_change",
                    "from": _label_sample_name(index - 1),
                    "name": _label_sample_name(index),
                    "region": "top_right_label",
                    "message": f"F11 bootstrap to {TERMINAL_LABEL_NAMES[index]} failed",
                    "timeout_secs": 3.0,
                },
            ]
        )

    return steps


def _selection_matrix_steps(keys: list[str], target_count: int, use_chord: bool) -> list[dict]:
    steps = _create_terminal_label_steps(target_count)

    for index, key in enumerate(keys):
        steps.append(
            {
                "op": "chord" if use_chord else "tap",
                "keys": ["Alt", key] if use_chord else None,
                "key": None if use_chord else key,
                "after": 0.45,
            }
        )
        steps.extend(
            [
                {
                    "op": "capture_wait_match",
                    "target": _label_sample_name(index),
                    "name": f"selected_{key.lower()}",
                    "region": "top_right_label",
                    "message": f"{key} did not select terminal {index}",
                    "timeout_secs": 3.0,
                },
                {
                    "op": "assert_eq",
                    "left": _label_sample_name(index),
                    "right": f"selected_{key.lower()}",
                    "message": f"{key} did not select terminal {index}",
                },
            ]
        )

    return steps


def _write_lines_steps(lines: list[str], text_after_secs: float = 0.05, enter_after_secs: float = 0.18) -> list[dict]:
    steps: list[dict] = []
    for line in lines:
        steps.extend(
            [
                {"op": "type_text", "text": line, "after": text_after_secs},
                {"op": "tap", "key": "Enter", "after": enter_after_secs},
            ]
        )
    return steps


def _line_block(prefix: str, count: int) -> list[str]:
    return [f"{prefix}{index:02d}" for index in range(count)]


def _fresh_terminal_blank_steps(sample_name: str) -> list[dict]:
    return [
        {
            "op": "capture_wait_foreground",
            "name": f"{sample_name}_alpha_label",
            "region": "top_right_label",
            "timeout_secs": 3.0,
            "message": "alpha terminal label did not appear before creating a fresh terminal",
        },
        {"op": "tap", "key": "F11", "after": 0.45},
        {
            "op": "capture_wait_blank",
            "name": sample_name,
            "region": "top_left_body",
            "message": "fresh terminal did not render blank",
            "timeout_secs": 3.0,
        },
    ]


SCENARIOS: dict[str, list[dict]] = {
    "f11-creates-terminal-and-label-becomes-beta": [
        {"op": "capture", "name": "label_alpha", "region": "top_right_label", "wait_boot": True},
        {"op": "tap", "key": "F11", "after": 0.5},
        {
            "op": "capture_wait_change",
            "from": "label_alpha",
            "name": "label_beta",
            "region": "top_right_label",
            "message": "F11 did not change the terminal label",
            "timeout_secs": 2.5,
        },
        {"op": "assert_ne", "left": "label_alpha", "right": "label_beta", "message": "F11 did not change the terminal label"},
    ],
    "f12-destroys-current-terminal-and-label-returns-alpha": [
        {"op": "capture_wait_foreground", "name": "label_alpha", "region": "top_right_label", "timeout_secs": 3.0, "message": "alpha terminal label did not appear"},
        {"op": "tap", "key": "F11", "after": 0.5},
        {
            "op": "capture_wait_change",
            "from": "label_alpha",
            "name": "label_beta",
            "region": "top_right_label",
            "message": "F11 bootstrap for F12 case did not create beta",
            "timeout_secs": 3.0,
        },
        {"op": "assert_ne", "left": "label_alpha", "right": "label_beta", "message": "F11 bootstrap for F12 case did not create beta"},
        {"op": "tap", "key": "F12", "after": 0.5},
        {
            "op": "capture_wait_match",
            "target": "label_alpha",
            "name": "label_restored",
            "region": "top_right_label",
            "message": "F12 did not restore alpha label",
            "timeout_secs": 5.0,
        },
        {"op": "assert_eq", "left": "label_alpha", "right": "label_restored", "message": "F12 did not restore alpha label"},
    ],
    "terminal-switching-preserves-screen-contents": [
        {"op": "capture", "name": "alpha_before", "region": "top_left_text", "wait_boot": True},
        {"op": "type_text", "text": "c", "after": 0.35},
        {
            "op": "capture_wait_change",
            "from": "alpha_before",
            "name": "alpha_after_c",
            "region": "top_left_text",
            "message": "alpha text did not change after typing",
            "timeout_secs": 2.0,
        },
        {"op": "assert_ne", "left": "alpha_before", "right": "alpha_after_c", "message": "alpha text did not change after typing"},
        {"op": "tap", "key": "F11", "after": 0.45},
        {"op": "type_text", "text": "b", "after": 0.35},
        {
            "op": "capture_wait_change",
            "from": "alpha_after_c",
            "name": "beta_text",
            "region": "top_left_text",
            "message": "beta text matched alpha after terminal switch",
            "timeout_secs": 2.0,
        },
        {"op": "assert_ne", "left": "alpha_after_c", "right": "beta_text", "message": "beta text matched alpha after terminal switch"},
        {"op": "tap", "key": "F1", "after": 0.45},
        {
            "op": "capture_wait_match",
            "target": "alpha_after_c",
            "name": "alpha_restored",
            "region": "top_left_text",
            "message": "switching to F1 did not restore alpha",
            "timeout_secs": 2.0,
        },
        {"op": "assert_eq", "left": "alpha_after_c", "right": "alpha_restored", "message": "switching to F1 did not restore alpha"},
        {"op": "tap", "key": "F2", "after": 0.45},
        {
            "op": "capture_wait_match",
            "target": "beta_text",
            "name": "beta_restored",
            "region": "top_left_text",
            "message": "switching to F2 did not restore beta",
            "timeout_secs": 2.0,
        },
        {"op": "assert_eq", "left": "beta_text", "right": "beta_restored", "message": "switching to F2 did not restore beta"},
    ],
    "alt-a-c-creates-terminal-and-label-becomes-beta": [
        {"op": "capture_wait_foreground", "name": "label_alpha", "region": "top_right_label", "timeout_secs": 3.0, "message": "alpha terminal label did not appear"},
        {"op": "alt_a_prefix", "after": 0.15},
        {"op": "tap", "key": "c", "after": 0.55},
        {
            "op": "capture_wait_change",
            "from": "label_alpha",
            "name": "label_created",
            "region": "top_right_label",
            "message": "Alt+A C did not change terminal label",
            "timeout_secs": 2.0,
        },
        {"op": "assert_ne", "left": "label_alpha", "right": "label_created", "message": "Alt+A C did not change terminal label"},
    ],
    "alt-a-x-destroys-terminal-and-label-returns-alpha": [
        {"op": "capture_wait_foreground", "name": "label_alpha", "region": "top_right_label", "timeout_secs": 3.0, "message": "alpha terminal label did not appear"},
        {"op": "tap", "key": "F11", "after": 0.4},
        {
            "op": "capture_wait_change",
            "from": "label_alpha",
            "name": "label_beta",
            "region": "top_right_label",
            "message": "F11 bootstrap for Alt+A X case failed",
            "timeout_secs": 3.0,
        },
        {"op": "assert_ne", "left": "label_alpha", "right": "label_beta", "message": "F11 bootstrap for Alt+A X case failed"},
        {"op": "alt_a_prefix", "after": 0.15},
        {"op": "tap", "key": "x", "after": 0.55},
        {
            "op": "capture_wait_match",
            "target": "label_alpha",
            "name": "label_restored",
            "region": "top_right_label",
            "message": "Alt+A X did not restore alpha label",
            "timeout_secs": 5.0,
        },
        {"op": "assert_eq", "left": "label_alpha", "right": "label_restored", "message": "Alt+A X did not restore alpha label"},
    ],
    "alt-a-digit-selects-target-terminal": [
        {"op": "capture_wait_foreground", "name": "label_alpha", "region": "top_right_label", "timeout_secs": 3.0, "message": "alpha terminal label did not appear"},
        {"op": "tap", "key": "F11", "after": 0.45},
        {"op": "capture_wait_change", "from": "label_alpha", "name": "label_beta", "region": "top_right_label", "message": "F11 bootstrap to beta failed", "timeout_secs": 3.0},
        {"op": "tap", "key": "F11", "after": 0.45},
        {"op": "capture_wait_change", "from": "label_beta", "name": "label_gamma", "region": "top_right_label", "message": "second F11 bootstrap to gamma failed", "timeout_secs": 3.0},
        {"op": "capture", "name": "gamma_seed", "region": "top_left_text", "wait_boot": True},
        {"op": "type_text", "text": "g", "after": 0.35},
        {
            "op": "capture_wait_change",
            "from": "gamma_seed",
            "name": "gamma_text",
            "region": "top_left_text",
            "message": "gamma terminal did not update after typing",
            "timeout_secs": 2.5,
        },
        {"op": "assert_ne", "left": "gamma_seed", "right": "gamma_text", "message": "gamma terminal did not update after typing"},
        {"op": "alt_a_prefix", "after": 0.15},
        {"op": "tap", "key": "0", "after": 0.45},
        {
            "op": "capture_wait_change",
            "from": "gamma_text",
            "name": "alpha_text",
            "region": "top_left_text",
            "message": "Alt+A 0 did not switch away from gamma",
            "timeout_secs": 3.0,
        },
        {"op": "assert_ne", "left": "alpha_text", "right": "gamma_text", "message": "Alt+A 0 did not switch away from gamma"},
        {"op": "alt_a_prefix", "after": 0.15},
        {"op": "tap", "key": "2", "after": 0.45},
        {
            "op": "capture_wait_match",
            "target": "gamma_text",
            "name": "gamma_restored",
            "region": "top_left_text",
            "message": "Alt+A 2 did not restore gamma",
            "timeout_secs": 4.0,
        },
        {"op": "assert_eq", "left": "gamma_text", "right": "gamma_restored", "message": "Alt+A 2 did not restore gamma"},
    ],
    "compact-geometry-centers-42-in-physical-vga": [
        {"op": "capture", "name": "compact_boot", "region": "top_left_cell", "wait_boot": True},
        {
            "op": "capture_wait_foreground",
            "name": "compact_text",
            "region": "compact_origin",
            "message": "compact boot text did not appear at centered origin",
            "timeout_secs": 3.0,
        },
        {"op": "assert_ne", "left": "compact_boot", "right": "compact_text", "message": "compact boot text did not appear at centered origin"},
    ],
    "compact-geometry-keeps-terminal-label-in-physical-top-right": [
        {"op": "capture_wait_foreground", "name": "compact_boot_label", "region": "top_right_label", "timeout_secs": 3.0, "message": "compact mode hid terminal label in physical top-right"},
    ],
    "compact-create-terminal-keeps-output-centered": [
        {"op": "capture_wait_stable", "name": "physical_margin_blank", "region": "top_left_cell", "wait_boot": True, "timeout_secs": 3.0, "sample_interval_secs": 0.12, "hold_secs": 0.2, "message": "compact physical top-left margin did not stabilize before terminal creation"},
        {"op": "tap", "key": "F11", "after": 0.45},
        {"op": "type_text", "text": "b", "after": 0.25},
        {
            "op": "capture_wait_foreground",
            "name": "compact_center_text",
            "region": "compact_origin",
            "message": "compact terminal text did not appear in the centered viewport",
            "timeout_secs": 3.0,
        },
        {"op": "capture", "name": "physical_margin_after_create", "region": "top_left_cell", "wait_boot": False},
        {"op": "assert_eq", "left": "physical_margin_blank", "right": "physical_margin_after_create", "message": "compact terminal creation leaked visible output into the physical top-left margin"},
    ],
    "compact-switching-restores-centered-terminal-contents": [
        {"op": "capture_wait_stable", "name": "physical_margin_blank", "region": "top_left_cell", "wait_boot": True, "timeout_secs": 3.0, "sample_interval_secs": 0.12, "hold_secs": 0.2, "message": "compact physical top-left margin did not stabilize before terminal switching"},
        {"op": "type_text", "text": "a", "after": 0.25},
        {"op": "capture_wait_foreground", "name": "alpha_center_text", "region": "compact_origin", "message": "alpha text did not appear in the compact centered viewport", "timeout_secs": 3.0},
        {"op": "tap", "key": "F11", "after": 0.45},
        {"op": "type_text", "text": "b", "after": 0.25},
        {"op": "capture_wait_change", "from": "alpha_center_text", "name": "beta_center_text", "region": "compact_origin", "message": "beta text did not change the compact centered viewport", "timeout_secs": 3.0},
        {"op": "tap", "key": "F1", "after": 0.45},
        {"op": "capture_wait_match", "target": "alpha_center_text", "name": "alpha_center_restored", "region": "compact_origin", "message": "compact switch to alpha did not restore centered contents", "timeout_secs": 4.0},
        {"op": "assert_eq", "left": "alpha_center_text", "right": "alpha_center_restored", "message": "compact switch to alpha did not restore centered contents"},
        {"op": "tap", "key": "F2", "after": 0.45},
        {"op": "capture_wait_match", "target": "beta_center_text", "name": "beta_center_restored", "region": "compact_origin", "message": "compact switch to beta did not restore centered contents", "timeout_secs": 4.0},
        {"op": "assert_eq", "left": "beta_center_text", "right": "beta_center_restored", "message": "compact switch to beta did not restore centered contents"},
        {"op": "capture", "name": "physical_margin_after_switch", "region": "top_left_cell", "wait_boot": False},
        {"op": "assert_eq", "left": "physical_margin_blank", "right": "physical_margin_after_switch", "message": "compact terminal switching leaked visible output into the physical top-left margin"},
    ],
    "compact-destroy-restores-previous-terminal": [
        {"op": "capture_wait_stable", "name": "physical_margin_blank", "region": "top_left_cell", "wait_boot": True, "timeout_secs": 3.0, "sample_interval_secs": 0.12, "hold_secs": 0.2, "message": "compact physical top-left margin did not stabilize before terminal destroy"},
        {"op": "type_text", "text": "a", "after": 0.25},
        {"op": "capture_wait_foreground", "name": "alpha_center_text", "region": "compact_origin", "message": "alpha text did not appear in compact mode", "timeout_secs": 3.0},
        {"op": "capture_wait_foreground", "name": "alpha_label", "region": "top_right_label", "timeout_secs": 3.0, "message": "alpha label did not appear in compact mode"},
        {"op": "tap", "key": "F11", "after": 0.45},
        {"op": "type_text", "text": "b", "after": 0.25},
        {"op": "capture_wait_change", "from": "alpha_center_text", "name": "beta_center_text", "region": "compact_origin", "message": "beta text did not change the compact viewport", "timeout_secs": 3.0},
        {"op": "capture_wait_change", "from": "alpha_label", "name": "beta_label", "region": "top_right_label", "message": "beta label did not appear in compact mode", "timeout_secs": 3.0},
        {"op": "tap", "key": "F12", "after": 0.45},
        {"op": "capture_wait_match", "target": "alpha_center_text", "name": "alpha_center_restored", "region": "compact_origin", "message": "compact destroy did not restore alpha contents", "timeout_secs": 4.0},
        {"op": "assert_eq", "left": "alpha_center_text", "right": "alpha_center_restored", "message": "compact destroy did not restore alpha contents"},
        {"op": "capture_wait_match", "target": "alpha_label", "name": "alpha_label_restored", "region": "top_right_label", "message": "compact destroy did not restore alpha label", "timeout_secs": 4.0},
        {"op": "assert_eq", "left": "alpha_label", "right": "alpha_label_restored", "message": "compact destroy did not restore alpha label"},
        {"op": "capture", "name": "physical_margin_after_destroy", "region": "top_left_cell", "wait_boot": False},
        {"op": "assert_eq", "left": "physical_margin_blank", "right": "physical_margin_after_destroy", "message": "compact destroy leaked visible output into the physical top-left margin"},
    ],
    "compact-scroll-keeps-output-inside-centered-viewport": [
        {"op": "capture_wait_stable", "name": "physical_margin_blank", "region": "top_left_cell", "wait_boot": True, "timeout_secs": 3.0, "sample_interval_secs": 0.12, "hold_secs": 0.2, "message": "compact physical top-left margin did not stabilize before scroll"},
        *_write_lines_steps(_line_block("cmp", 16), text_after_secs=0.04, enter_after_secs=0.12),
        {"op": "capture_wait_foreground", "name": "compact_scrolled_text", "region": "compact_origin", "message": "compact scroll did not leave visible text inside the centered viewport", "timeout_secs": 4.0},
        {"op": "capture", "name": "physical_margin_after_scroll", "region": "top_left_cell", "wait_boot": False},
        {"op": "assert_eq", "left": "physical_margin_blank", "right": "physical_margin_after_scroll", "message": "compact scroll leaked visible output into the physical top-left margin"},
    ],
    "vga-buffer-starts-with-42": [
        {"op": "capture", "name": "boot", "region": "boot_text", "wait_boot": True},
        {"op": "assert_foreground", "sample": "boot", "message": "boot text did not render"},
    ],
    "vga-buffer-uses-default-attribute": [
        {"op": "capture", "name": "boot", "region": "boot_text", "wait_boot": True},
        {"op": "assert_green_text", "sample": "boot", "message": "boot text was not green dominant"},
    ],
    "vga-buffer-stable-across-snapshots": [
        {
            "op": "capture_wait_stable",
            "name": "snapshot_1",
            "region": "boot_text",
            "message": "boot region did not stabilize after boot",
            "required_stable": 2,
            "sample_interval_secs": 0.15,
            "hold_secs": 0.3,
            "timeout_secs": 4.0,
            "wait_boot": True,
        },
        {
            "op": "capture_wait_match",
            "target": "snapshot_1",
            "name": "snapshot_2",
            "region": "boot_text",
            "message": "boot region changed between snapshots",
            "timeout_secs": 3.0,
        },
        {"op": "assert_eq", "left": "snapshot_1", "right": "snapshot_2", "message": "boot region changed between snapshots"},
    ],
}

SCENARIOS["bare-function-key-selection-matrix"] = _selection_matrix_steps(
    [f"F{index}" for index in range(1, 11)],
    10,
    False,
)
SCENARIOS["alt-function-key-selection-matrix"] = _selection_matrix_steps(
    [f"F{index}" for index in range(1, 13)],
    12,
    True,
)
SCENARIOS["destroying-last-terminal-keeps-alpha-active"] = [
    {"op": "capture_wait_foreground", "name": "label_alpha", "region": "top_right_label", "timeout_secs": 3.0, "message": "alpha terminal label did not appear"},
    {"op": "tap", "key": "F12", "after": 0.35},
    {
        "op": "capture_wait_match",
        "target": "label_alpha",
        "name": "label_after_destroy",
        "region": "top_right_label",
        "message": "destroying the last terminal changed the active label",
        "timeout_secs": 2.0,
    },
    {"op": "assert_eq", "left": "label_alpha", "right": "label_after_destroy", "message": "destroying the last terminal changed the active label"},
]
SCENARIOS["terminal-create-capacity-limit-is-a-no-op"] = [
    *_create_terminal_label_steps(12),
    {"op": "tap", "key": "F11", "after": 0.35},
    {
        "op": "capture_wait_match",
        "target": "label_mu",
        "name": "label_after_capacity",
        "region": "top_right_label",
        "message": "creating beyond terminal capacity changed the active label",
        "timeout_secs": 3.0,
    },
    {"op": "assert_eq", "left": "label_mu", "right": "label_after_capacity", "message": "creating beyond terminal capacity changed the active label"},
]
SCENARIOS["switching-to-an-untouched-terminal-shows-a-blank-screen"] = [
    {"op": "capture_wait_foreground", "name": "alpha_label", "region": "top_right_label", "timeout_secs": 3.0, "message": "alpha terminal label did not appear"},
    {"op": "type_text", "text": "d", "after": 0.35},
    {
        "op": "capture_wait_change",
        "from": "alpha_label",
        "name": "dirty_alpha",
        "region": "top_left_text",
        "message": "alpha terminal did not become visibly dirty",
        "timeout_secs": 2.5,
    },
    {"op": "tap", "key": "F11", "after": 0.45},
    {
        "op": "capture_wait_blank",
        "name": "untouched_beta",
        "region": "top_left_body",
        "message": "untouched terminal did not render blank after switching",
        "timeout_secs": 3.0,
    },
]
SCENARIOS["switching-back-from-an-untouched-terminal-restores-the-dirty-terminal"] = [
    {"op": "capture_wait_foreground", "name": "alpha_label", "region": "top_right_label", "timeout_secs": 3.0, "message": "alpha terminal label did not appear"},
    {"op": "type_text", "text": "d", "after": 0.35},
    {
        "op": "capture_wait_change",
        "from": "alpha_label",
        "name": "dirty_alpha",
        "region": "top_left_text",
        "message": "alpha terminal did not become visibly dirty",
        "timeout_secs": 2.5,
    },
    {"op": "tap", "key": "F11", "after": 0.45},
    {
        "op": "capture_wait_blank",
        "name": "untouched_beta",
        "region": "top_left_body",
        "message": "untouched terminal did not render blank after switching",
        "timeout_secs": 3.0,
    },
    {"op": "tap", "key": "F1", "after": 0.45},
    {
        "op": "capture_wait_match",
        "target": "dirty_alpha",
        "name": "restored_alpha",
        "region": "top_left_text",
        "message": "switching back from an untouched terminal did not restore the dirty terminal",
        "timeout_secs": 3.0,
    },
    {"op": "assert_eq", "left": "dirty_alpha", "right": "restored_alpha", "message": "switching back from an untouched terminal did not restore the dirty terminal"},
]
SCENARIOS["destroying-from-a-high-slot-focuses-a-valid-survivor"] = [
    *_create_terminal_label_steps(12),
    {"op": "tap", "key": "F12", "after": 0.35},
    {
        "op": "capture_wait_match",
        "target": "label_lambda",
        "name": "label_survivor",
        "region": "top_right_label",
        "message": "destroying the highest active slot did not focus a surviving terminal",
        "timeout_secs": 3.0,
    },
    {"op": "assert_eq", "left": "label_lambda", "right": "label_survivor", "message": "destroying the highest active slot did not focus a surviving terminal"},
]
SCENARIOS["arrow-up-restores-an-older-viewport-snapshot"] = [
    {"op": "capture_wait_foreground", "name": "alpha_label", "region": "top_right_label", "timeout_secs": 3.0, "message": "alpha terminal label did not appear"},
    *_write_lines_steps(_line_block("old", 26)),
    {"op": "capture", "name": "older_view", "region": "top_left_text", "wait_boot": False},
    *_write_lines_steps(["tail"]),
    {
        "op": "capture_wait_change",
        "from": "older_view",
        "name": "live_tail",
        "region": "top_left_text",
        "message": "live tail did not change after one more line of output",
        "timeout_secs": 3.0,
    },
    {"op": "tap", "key": "ArrowUp", "after": 0.35},
    {
        "op": "capture_wait_match",
        "target": "older_view",
        "name": "restored_old_view",
        "region": "top_left_text",
        "message": "ArrowUp did not restore an older viewport snapshot",
        "timeout_secs": 4.0,
    },
    {"op": "assert_eq", "left": "older_view", "right": "restored_old_view", "message": "ArrowUp did not restore an older viewport snapshot"},
]
SCENARIOS["arrow-down-returns-to-the-live-tail-viewport"] = [
    {"op": "capture_wait_foreground", "name": "alpha_label", "region": "top_right_label", "timeout_secs": 3.0, "message": "alpha terminal label did not appear"},
    *_write_lines_steps(_line_block("old", 26)),
    {"op": "capture", "name": "older_view", "region": "top_left_text", "wait_boot": False},
    *_write_lines_steps(["tail"]),
    {
        "op": "capture_wait_change",
        "from": "older_view",
        "name": "live_tail",
        "region": "top_left_text",
        "message": "live tail did not change after one more line of output",
        "timeout_secs": 3.0,
    },
    {"op": "tap", "key": "ArrowUp", "after": 0.35},
    {"op": "capture_wait_change", "from": "live_tail", "name": "older_again", "region": "top_left_text", "message": "ArrowUp did not move the viewport away from the live tail", "timeout_secs": 3.0},
    {"op": "tap", "key": "ArrowDown", "after": 0.35},
    {
        "op": "capture_wait_match",
        "target": "live_tail",
        "name": "restored_tail",
        "region": "top_left_text",
        "message": "ArrowDown did not return to the live tail viewport",
        "timeout_secs": 4.0,
    },
    {"op": "assert_eq", "left": "live_tail", "right": "restored_tail", "message": "ArrowDown did not return to the live tail viewport"},
]
SCENARIOS["multi-line-output-scrolls-visibly-after-repeated-newlines"] = [
    {"op": "capture_wait_foreground", "name": "alpha_label", "region": "top_right_label", "timeout_secs": 3.0, "message": "alpha terminal label did not appear"},
    {"op": "capture", "name": "before_scroll", "region": "top_left_text", "wait_boot": True},
    *_write_lines_steps(_line_block("scr", 30), text_after_secs=0.04, enter_after_secs=0.12),
    {
        "op": "capture_wait_change",
        "from": "before_scroll",
        "name": "after_scroll",
        "region": "top_left_text",
        "message": "repeated newlines did not visibly scroll the screen",
        "timeout_secs": 5.0,
    },
    {"op": "assert_ne", "left": "before_scroll", "right": "after_scroll", "message": "repeated newlines did not visibly scroll the screen"},
]
SCENARIOS["backspace-blanks-the-last-visible-character-cell"] = [
    *_fresh_terminal_blank_steps("beta_blank"),
    {"op": "type_text", "text": "x", "after": 0.25},
    {"op": "capture_wait_change", "from": "beta_blank", "name": "beta_dirty", "region": "top_left_body", "message": "typing a visible character did not change the terminal", "timeout_secs": 2.5},
    {"op": "tap", "key": "Backspace", "after": 0.35},
    {
        "op": "capture_wait_match",
        "target": "beta_blank",
        "name": "beta_restored_blank",
        "region": "top_left_body",
        "message": "Backspace did not blank the last visible character cell",
        "timeout_secs": 3.0,
    },
    {"op": "assert_eq", "left": "beta_blank", "right": "beta_restored_blank", "message": "Backspace did not blank the last visible character cell"},
]
SCENARIOS["newline-moves-visible-output-to-the-next-row"] = [
    *_fresh_terminal_blank_steps("beta_blank"),
    {"op": "type_text", "text": "ab", "after": 0.25},
    {"op": "capture", "name": "before_newline", "region": "top_left_body", "wait_boot": False},
    {"op": "tap", "key": "Enter", "after": 0.25},
    {"op": "type_text", "text": "c", "after": 0.25},
    {
        "op": "capture_wait_change",
        "from": "before_newline",
        "name": "after_newline",
        "region": "top_left_body",
        "message": "newline did not move visible output to the next row",
        "timeout_secs": 3.0,
    },
    {"op": "assert_ne", "left": "before_newline", "right": "after_newline", "message": "newline did not move visible output to the next row"},
]
SCENARIOS["end-of-line-wrap-continues-on-the-next-row"] = [
    *_fresh_terminal_blank_steps("beta_blank"),
    {"op": "type_text", "text": "a" * 80, "after": 0.35},
    {"op": "capture", "name": "before_wrap", "region": "top_left_text", "wait_boot": False},
    {"op": "type_text", "text": "b", "after": 0.35},
    {
        "op": "capture_wait_change",
        "from": "before_wrap",
        "name": "after_wrap",
        "region": "top_left_text",
        "message": "end-of-line wrap did not continue on the next row",
        "timeout_secs": 3.0,
    },
    {"op": "assert_ne", "left": "before_wrap", "right": "after_wrap", "message": "end-of-line wrap did not continue on the next row"},
]
SCENARIOS["switching-back-to-a-scrolled-terminal-restores-its-viewport"] = [
    {"op": "capture_wait_foreground", "name": "alpha_label", "region": "top_right_label", "timeout_secs": 3.0, "message": "alpha terminal label did not appear"},
    *_write_lines_steps(_line_block("scr", 26)),
    {"op": "capture", "name": "scrolled_alpha", "region": "top_left_text", "wait_boot": False},
    {"op": "tap", "key": "F11", "after": 0.45},
    {
        "op": "capture_wait_blank",
        "name": "untouched_beta",
        "region": "top_left_body",
        "message": "untouched terminal did not render blank after switching away from a scrolled terminal",
        "timeout_secs": 3.0,
    },
    {"op": "tap", "key": "F1", "after": 0.45},
    {
        "op": "capture_wait_match",
        "target": "scrolled_alpha",
        "name": "restored_scrolled_alpha",
        "region": "top_left_text",
        "message": "switching back to a scrolled terminal did not restore its viewport",
        "timeout_secs": 4.0,
    },
    {"op": "assert_eq", "left": "scrolled_alpha", "right": "restored_scrolled_alpha", "message": "switching back to a scrolled terminal did not restore its viewport"},
]


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--socket", required=True)
    parser.add_argument("--qmp-socket")
    parser.add_argument("--case", required=True, choices=sorted(SCENARIOS.keys()))
    parser.add_argument("--timeout-secs", type=float, default=10.0)
    parser.add_argument(
        "--input-backend",
        choices=("qmp-events",),
        default="qmp-events",
    )
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    if not os.path.exists(args.socket):
        fail(f"missing VNC socket: {args.socket}")

    client = VNCClient(args.socket, args.timeout_secs)
    qmp = None
    input_backend: InputBackend
    try:
        if args.input_backend == "qmp-events":
            if not args.qmp_socket:
                fail("--qmp-socket is required for qmp-events input backend")
            if not os.path.exists(args.qmp_socket):
                fail(f"missing QMP socket: {args.qmp_socket}")
            qmp = QMPClient(args.qmp_socket, args.timeout_secs)
            input_backend = QmpInput(qmp)
        else:
            fail(f"unsupported input backend: {args.input_backend}")

        _execute_steps(SCENARIOS[args.case], client, input_backend)
    finally:
        if qmp is not None:
            qmp.close()
        client.close()


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Generate the extension icons with no third-party dependencies."""

import math
import os
import struct
import zlib

SIZES = (16, 32, 48, 64, 128, 256, 512)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "icons")

TOP = (42, 120, 214)    # palette blue 450
BOTTOM = (24, 79, 149)  # palette blue 600


def rounded_rect(x, y, n, radius):
    cx = min(max(x, radius), n - radius)
    cy = min(max(y, radius), n - radius)
    return (x - cx) ** 2 + (y - cy) ** 2 <= radius ** 2


def segment_distance(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    length_sq = vx * vx + vy * vy
    t = 0.0 if length_sq == 0 else (wx * vx + wy * vy) / length_sq
    t = max(0.0, min(1.0, t))
    return math.hypot(px - (ax + t * vx), py - (ay + t * vy))


def sample(x, y, n):
    if not rounded_rect(x, y, n, 0.235 * n):
        return (0, 0, 0, 0)

    mixed = (x + y) / (2 * n)
    red = round(TOP[0] + (BOTTOM[0] - TOP[0]) * mixed)
    green = round(TOP[1] + (BOTTOM[1] - TOP[1]) * mixed)
    blue = round(TOP[2] + (BOTTOM[2] - TOP[2]) * mixed)

    cx, cy = 0.5 * n, 0.505 * n
    dx, dy = x - cx, y - cy
    distance = math.hypot(dx, dy)

    ring = 0.232 * n <= distance <= 0.300 * n
    long_hand = segment_distance(x, y, cx, cy, cx, cy - 0.195 * n) <= 0.040 * n
    short_hand = segment_distance(
        x, y, cx, cy, cx + 0.145 * n, cy + 0.084 * n
    ) <= 0.040 * n
    center_dot = distance <= 0.052 * n

    if ring or long_hand or short_hand or center_dot:
        return (255, 255, 255, 255)
    return (red, green, blue, 255)


def render(size):
    scale = 4 if size <= 128 else 2
    n = size * scale
    high = [[sample(x + 0.5, y + 0.5, n) for x in range(n)] for y in range(n)]

    rows = []
    for out_y in range(size):
        row = bytearray()
        for out_x in range(size):
            red = green = blue = alpha = 0
            for sy in range(scale):
                source_row = high[out_y * scale + sy]
                for sx in range(scale):
                    pr, pg, pb, pa = source_row[out_x * scale + sx]
                    red += pr * pa
                    green += pg * pa
                    blue += pb * pa
                    alpha += pa
            count = scale * scale
            if alpha == 0:
                row += bytes((0, 0, 0, 0))
            else:
                row += bytes((
                    round(red / alpha),
                    round(green / alpha),
                    round(blue / alpha),
                    round(alpha / count),
                ))
        rows.append(row)
    return rows


def png_bytes(size, rows):
    raw = b"".join(b"\x00" + bytes(row) for row in rows)

    def chunk(tag, data):
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for size in SIZES:
        path = os.path.join(OUT_DIR, f"icon{size}.png")
        with open(path, "wb") as handle:
            handle.write(png_bytes(size, render(size)))
        print(f"wrote {path}")


if __name__ == "__main__":
    main()

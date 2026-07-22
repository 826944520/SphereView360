#!/usr/bin/env python3
"""Generate an equirectangular 360 test video with clear directional markers.

Output: equirectangular MP4, 1920x960 (2:1), 5 seconds, 30 fps.
The video shows colored markers at cardinal directions so you can verify
the 360 viewer is orienting correctly.

Usage:
    pip3 install numpy opencv-python
    python3 script/generate_360_test_video.py

Requirements: numpy, opencv-python
"""

import numpy as np
import cv2
import imageio
import os

# ── Config ──────────────────────────────────────────────────────────────
WIDTH = 1920          # equirectangular width (360° of longitude)
HEIGHT = 960          # equirectangular height (180° of latitude → -90° to +90°)
FPS = 30
DURATION_SEC = 5
TOTAL_FRAMES = FPS * DURATION_SEC
OUTPUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "test_360_video.mp4")

# ── Helpers ─────────────────────────────────────────────────────────────
def latlon_to_xy(lat_deg, lon_deg):
    """Convert latitude/longitude to equirectangular pixel coordinates."""
    x = int((lon_deg / 360.0 + 0.5) * WIDTH) % WIDTH
    y = int((0.5 - lat_deg / 180.0) * HEIGHT)
    y = max(0, min(HEIGHT - 1, y))
    return x, y


def draw_text_marker(frame, text, lat, lon, color, scale=1.5, thickness=3):
    """Draw bold text at a given lat/lon position."""
    x, y = latlon_to_xy(lat, lon)
    font = cv2.FONT_HERSHEY_SIMPLEX
    (tw, th), _ = cv2.getTextSize(text, font, scale, thickness)
    cv2.putText(frame, text, (x - tw // 2, y + th // 2), font, scale,
                (0, 0, 0), thickness + 2, cv2.LINE_AA)
    cv2.putText(frame, text, (x - tw // 2, y + th // 2), font, scale,
                color, thickness, cv2.LINE_AA)


def draw_cross(frame, x, y, size, color, thickness=2):
    """Draw a crosshair at pixel position."""
    cv2.line(frame, (x - size, y), (x + size, y), (0, 0, 0), thickness + 2)
    cv2.line(frame, (x, y - size), (x, y + size), (0, 0, 0), thickness + 2)
    cv2.line(frame, (x - size, y), (x + size, y), color, thickness)
    cv2.line(frame, (x, y - size), (x, y + size), color, thickness)


def make_frame(t: float) -> np.ndarray:
    """Create one equirectangular frame at time t (seconds)."""
    # Dark gray background
    frame = np.full((HEIGHT, WIDTH, 3), (30, 30, 40), dtype=np.uint8)

    # ── Longitude grid lines every 30° ──────────────────────────────────
    for lon in range(0, 360, 30):
        x = int((lon / 360.0) * WIDTH)
        cv2.line(frame, (x, 0), (x, HEIGHT), (50, 50, 55), 1)

    # ── Latitude grid lines every 30° ───────────────────────────────────
    for lat in range(-60, 90, 30):
        y = int((0.5 - lat / 180.0) * HEIGHT)
        cv2.line(frame, (0, y), (WIDTH, y), (50, 50, 55), 1)

    # ── Horizon line (equator) ──────────────────────────────────────────
    y_horizon = HEIGHT // 2
    cv2.line(frame, (0, y_horizon), (WIDTH, y_horizon), (60, 60, 80), 2)

    # ── Prime meridian ──────────────────────────────────────────────────
    x_center = WIDTH // 2
    cv2.line(frame, (x_center, 0), (x_center, HEIGHT), (60, 60, 80), 2)

    # ── Cardinal direction markers ──────────────────────────────────────
    markers = [
        #  (label,      lat,  lon,       color BGR)
        ("↑ NORTH",    80,   0,         (80, 80, 255)),     # red
        ("↓ SOUTH",   -80,   0,         (255, 200, 80)),    # cyan-ish
        ("→ EAST",      0,   90,        (80, 255, 80)),     # green
        ("← WEST",      0,  -90,        (255, 200, 80)),    # yellow-ish
        ("● CENTER",    0,   0,         (255, 255, 255)),   # white
        ("▲ UP ",      45,   0,         (255, 80, 180)),    # purple
        ("▼ DOWN",    -45,   0,         (180, 255, 80)),    # lime
        ("NE",         45,   45,        (80, 180, 255)),    # orange
        ("NW",         45,  -45,        (80, 180, 255)),    # orange
        ("SE",        -45,   45,        (255, 130, 80)),    # sky blue
        ("SW",        -45,  -45,        (255, 130, 80)),    # sky blue
    ]

    for label, lat, lon, color in markers:
        # Apply a slow pulse animation
        pulse = 0.7 + 0.3 * np.sin(t * 3.0 + hash(label) % 100 * 0.1)
        pulsed_color = tuple(int(c * pulse) for c in color)
        draw_text_marker(frame, label, lat, lon, pulsed_color, scale=1.3, thickness=3)

    # ── Moving ball (orbits around equator) ─────────────────────────────
    ball_lon = (t * 72) % 360  # full orbit every 5 seconds
    bx, by = latlon_to_xy(0, ball_lon)
    ball_radius = 12
    cv2.circle(frame, (bx, by), ball_radius, (0, 0, 0), 3)
    cv2.circle(frame, (bx, by), ball_radius, (0, 220, 255), -1)

    # ── Top/bottom cap markers ──────────────────────────────────────────
    cv2.circle(frame, (WIDTH // 2, 10), 6, (255, 255, 255), -1)
    cv2.circle(frame, (WIDTH // 2, HEIGHT - 10), 6, (255, 255, 255), -1)
    draw_text_marker(frame, "TOP", 89.5, 0, (200, 200, 200), scale=0.7, thickness=1)
    draw_text_marker(frame, "BOT", -89.5, 0, (200, 200, 200), scale=0.7, thickness=1)

    # ── Horizontal compass labels at bottom ─────────────────────────────
    for lon_deg in range(-180, 180, 30):
        x, y = latlon_to_xy(0, lon_deg)
        label = f"{lon_deg}°"
        cv2.putText(frame, label, (x - 15, y + 20), cv2.FONT_HERSHEY_SIMPLEX,
                    0.4, (100, 100, 110), 1, cv2.LINE_AA)

    # ── Center crosshair ────────────────────────────────────────────────
    draw_cross(frame, x_center, y_horizon, 20, (200, 200, 200), thickness=2)

    # ── Timestamp ───────────────────────────────────────────────────────
    timestamp = f"t = {t:.1f}s"
    cv2.putText(frame, timestamp, (20, HEIGHT - 20), cv2.FONT_HERSHEY_SIMPLEX,
                0.8, (150, 150, 150), 1, cv2.LINE_AA)

    # ── Top info bar ────────────────────────────────────────────────────
    info = "EQUIRECTANGULAR 360  |  EAST → green  |  NORTH ↑ red  |  CENTER ● white  |  🔴 = orbiting ball"
    cv2.putText(frame, info, (20, 30), cv2.FONT_HERSHEY_SIMPLEX,
                0.55, (120, 120, 130), 1, cv2.LINE_AA)

    return frame


# ── Generate video ──────────────────────────────────────────────────────
def main():
    output_path = os.path.normpath(OUTPUT)
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    print(f"Generating {TOTAL_FRAMES} frames → {output_path}")
    writer = imageio.get_writer(
        output_path,
        fps=FPS,
        format="FFMPEG",
        codec="mpeg4",
        pixelformat="yuv420p",
        output_params=[
            "-qscale:v", "3",
            "-movflags", "+faststart",
        ],
        macro_block_size=1,
    )

    with writer:
        for i in range(TOTAL_FRAMES):
            t = i / FPS
            frame_bgr = make_frame(t)
            frame_rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
            writer.append_data(frame_rgb)

            if (i + 1) % 30 == 0:
                print(f"  frame {i + 1}/{TOTAL_FRAMES} ({t:.1f}s)")

    print(f"\nDone: {output_path}")
    print(f"Size: {os.path.getsize(output_path) / 1024 / 1024:.1f} MB")
    print("\nTest with:")
    print(f"  python3 -m http.server 8080 --directory {os.path.dirname(output_path)}")
    print(f"  Then open URL: http://localhost:8080/test_360_video.mp4")


if __name__ == "__main__":
    main()

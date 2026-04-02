#!/usr/bin/env python3
"""
vision_cli.py – Command-line interface for ChemMaster 4000 panel detection.

Usage examples
--------------
# Detect from an image file, write debug overlay to ./debug/
python vision_cli.py --mode detect --input file --image path/to/screenshot.png --debug-dir ./debug

# Detect from a live screenshot of the primary monitor
python vision_cli.py --mode detect --input screenshot --debug-dir ./debug

Output: JSON to stdout, e.g.
{
  "ok": true,
  "timing_ms": 42.1,
  "frame": {"w": 1920, "h": 1080},
  "panel": {"found": true, "confidence": 0.87, "rect": {"x":..., "y":..., "w":..., "h":..., "cx":..., "cy":...}},
  "anchors": {
    "transfer_button": {"found": true, "confidence": 0.95, "rect": {...}}
  },
  "orange_title_confidence": 0.72,
  "debug": {"overlay": "debug/frame_overlay.png", "panel_crop": "debug/frame_panel_crop.png"}
}
"""

import argparse
import json
import sys
from pathlib import Path

import cv2
import numpy as np


def _capture_screenshot() -> np.ndarray:
    """Capture the primary monitor and return a BGR numpy array."""
    try:
        import mss
        import mss.tools

        with mss.mss() as sct:
            monitor = sct.monitors[1]  # 1 = primary monitor
            sct_img = sct.grab(monitor)
            # mss returns BGRA; drop alpha and return BGR
            frame = np.array(sct_img, dtype=np.uint8)
            return frame[:, :, :3]  # BGR
    except Exception as exc:
        _fatal(f"Screenshot capture failed: {exc}")


def _load_image(path: str) -> np.ndarray:
    p = Path(path)
    if not p.is_file():
        _fatal(f"Image file not found: {path}")
    img = cv2.imread(str(p))
    if img is None:
        _fatal(f"cv2.imread could not read image: {path}")
    return img


def _fatal(msg: str) -> None:
    out = {"ok": False, "error": msg}
    print(json.dumps(out))
    sys.exit(1)


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        description="ChemMaster 4000 vision helper – Phase 1 detection",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument(
        "--mode",
        choices=["detect"],
        default="detect",
        help="Operation mode (default: detect)",
    )
    p.add_argument(
        "--input",
        choices=["screenshot", "file"],
        default="file",
        help="Image source: 'screenshot' (live capture) or 'file' (--image path)",
    )
    p.add_argument(
        "--image",
        default=None,
        metavar="PATH",
        help="Path to image file when --input=file",
    )
    p.add_argument(
        "--debug-dir",
        default=None,
        metavar="DIR",
        help="Directory for debug overlay and panel-crop images",
    )
    return p


def main() -> None:
    parser = _build_parser()
    args = parser.parse_args()

    if args.mode == "detect":
        _run_detect(args)
    else:
        _fatal(f"Unknown mode: {args.mode}")


def _run_detect(args: argparse.Namespace) -> None:
    # --- Import here so the CLI remains importable even if OpenCV missing ---
    try:
        from detector import detect  # noqa: PLC0415
    except ImportError:
        try:
            from vision.detector import detect  # noqa: PLC0415
        except ImportError as exc:
            _fatal(f"Cannot import detector module: {exc}")

    # --- Load image ---
    if args.input == "screenshot":
        frame = _capture_screenshot()
        image_name = "screenshot"
    else:
        if not args.image:
            _fatal("--input=file requires --image PATH")
        frame = _load_image(args.image)
        image_name = Path(args.image).stem

    # --- Run detection ---
    debug_dir = Path(args.debug_dir) if args.debug_dir else None
    result = detect(frame, debug_dir=debug_dir, image_name=image_name)

    # --- Output JSON ---
    print(json.dumps(result.to_dict(), indent=2))


if __name__ == "__main__":
    main()

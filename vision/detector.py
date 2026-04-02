"""
detector.py – Deterministic ChemMaster 4000 panel detector.

Strategy
--------
1. HSV-threshold the frame for the bright-green Transfer button.
2. Filter green contours by aspect ratio, minimum area, and solidity.
3. Use the best green candidate as an anchor; expand search ROI upward/leftward
   to find the dark panel bounding rectangle.
4. Optionally validate with an orange title-bar cluster near the panel top-left.
5. Return a structured result dict; draw a debug overlay when requested.
"""

import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional, Tuple

import cv2
import numpy as np

# ---------------------------------------------------------------------------
# Colour ranges (HSV, uint8)
# ---------------------------------------------------------------------------

# Bright green Transfer button:  ~H 40-95, high S, high V
GREEN_HSV_LO = np.array([40, 90, 90], dtype=np.uint8)
GREEN_HSV_HI = np.array([95, 255, 255], dtype=np.uint8)

# Orange/gold title text:  ~H 10-28, high S, high V
ORANGE_HSV_LO = np.array([8, 120, 150], dtype=np.uint8)
ORANGE_HSV_HI = np.array([30, 255, 255], dtype=np.uint8)

# Dark panel background:  low V (dark), low S
DARK_HSV_LO = np.array([0, 0, 0], dtype=np.uint8)
DARK_HSV_HI = np.array([180, 60, 70], dtype=np.uint8)

# ---------------------------------------------------------------------------
# Geometry helpers
# ---------------------------------------------------------------------------

Rect = Tuple[int, int, int, int]  # x, y, w, h


def rect_center(r: Rect) -> Tuple[int, int]:
    x, y, w, h = r
    return x + w // 2, y + h // 2


def expand_rect(r: Rect, dx: int, dy: int, frame_w: int, frame_h: int) -> Rect:
    x, y, w, h = r
    x2 = min(x + w + dx, frame_w)
    y2 = min(y + h + dy, frame_h)
    x = max(x - dx, 0)
    y = max(y - dy, 0)
    return x, y, x2 - x, y2 - y


def rect_overlap_fraction(a: Rect, b: Rect) -> float:
    """Fraction of area of *a* that overlaps with *b*."""
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    ix = max(0, min(ax + aw, bx + bw) - max(ax, bx))
    iy = max(0, min(ay + ah, by + bh) - max(ay, by))
    inter = ix * iy
    area_a = aw * ah
    return inter / area_a if area_a > 0 else 0.0


# ---------------------------------------------------------------------------
# Green button detection
# ---------------------------------------------------------------------------

# Minimum pixel area for the Transfer button contour
_MIN_BTN_AREA = 200
# Maximum reasonable button area as fraction of frame
_MAX_BTN_AREA_FRAC = 0.05
# Aspect ratio range (w/h) for the Transfer button
_BTN_ASPECT_LO = 1.0
_BTN_ASPECT_HI = 8.0
# Minimum solidity (area / convex hull area)
_MIN_SOLIDITY = 0.6


def _find_green_button_candidates(hsv: np.ndarray) -> list:
    """
    Return a list of (score, rect) tuples sorted best-first for green Transfer
    button candidates found in *hsv*.
    """
    mask = cv2.inRange(hsv, GREEN_HSV_LO, GREEN_HSV_HI)
    # Light morphological close to fill small gaps
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3))
    mask = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, kernel, iterations=2)

    frame_area = hsv.shape[0] * hsv.shape[1]
    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    candidates = []
    for cnt in contours:
        area = cv2.contourArea(cnt)
        if area < _MIN_BTN_AREA:
            continue
        if area > _MAX_BTN_AREA_FRAC * frame_area:
            continue

        x, y, w, h = cv2.boundingRect(cnt)
        if h == 0:
            continue
        aspect = w / h
        if not (_BTN_ASPECT_LO <= aspect <= _BTN_ASPECT_HI):
            continue

        hull = cv2.convexHull(cnt)
        hull_area = cv2.contourArea(hull)
        solidity = area / hull_area if hull_area > 0 else 0.0
        if solidity < _MIN_SOLIDITY:
            continue

        # Score: larger area is better; penalise extreme aspect ratios
        score = area * solidity / (1 + abs(aspect - 2.5))
        candidates.append((score, (x, y, w, h)))

    candidates.sort(key=lambda t: t[0], reverse=True)
    return candidates


# ---------------------------------------------------------------------------
# Panel detection
# ---------------------------------------------------------------------------

# How far to expand around the Transfer button when looking for the panel
_PANEL_EXPAND_X = 600
_PANEL_EXPAND_Y = 500

# Minimum dark-panel contour area as fraction of expanded ROI
_MIN_PANEL_AREA_FRAC = 0.05

# How much of the frame height the panel is expected to use at most
_MAX_PANEL_HEIGHT_FRAC = 0.95


def _find_panel_rect(
    frame_bgr: np.ndarray,
    hsv: np.ndarray,
    btn_rect: Rect,
) -> Optional[Tuple[Rect, float]]:
    """
    Given the Transfer button rect, expand an ROI and find the dark panel.
    Returns (rect, confidence) or None.
    """
    fh, fw = frame_bgr.shape[:2]

    roi_rect = expand_rect(btn_rect, _PANEL_EXPAND_X, _PANEL_EXPAND_Y, fw, fh)
    rx, ry, rw, rh = roi_rect

    roi_hsv = hsv[ry : ry + rh, rx : rx + rw]
    dark_mask = cv2.inRange(roi_hsv, DARK_HSV_LO, DARK_HSV_HI)

    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (5, 5))
    dark_mask = cv2.morphologyEx(dark_mask, cv2.MORPH_CLOSE, kernel, iterations=3)

    contours, _ = cv2.findContours(dark_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

    roi_area = rw * rh
    best: Optional[Tuple[float, Rect]] = None

    for cnt in contours:
        area = cv2.contourArea(cnt)
        if area < _MIN_PANEL_AREA_FRAC * roi_area:
            continue
        cx, cy, cw, ch = cv2.boundingRect(cnt)
        # Convert back to full-frame coords
        abs_rect: Rect = (rx + cx, ry + cy, cw, ch)
        abs_x, abs_y, abs_w, abs_h = abs_rect
        if abs_h > _MAX_PANEL_HEIGHT_FRAC * fh:
            continue
        # Prefer the contour that fully contains the Transfer button
        overlap = rect_overlap_fraction(btn_rect, abs_rect)
        score = area * (1 + overlap)
        if best is None or score > best[0]:
            best = (score, abs_rect)

    if best is None:
        return None

    panel_rect = best[1]
    # Confidence: fraction of Transfer button inside panel
    conf = min(1.0, rect_overlap_fraction(btn_rect, panel_rect) + 0.5)
    return panel_rect, conf


# ---------------------------------------------------------------------------
# Orange title validation
# ---------------------------------------------------------------------------

def _orange_title_confidence(hsv: np.ndarray, panel_rect: Rect) -> float:
    """
    Look for orange pixels in the upper-left area of the panel.
    Returns a value in [0, 1].
    """
    px, py, pw, ph = panel_rect
    # Top 20 % of panel, left 70 %
    title_h = max(1, int(ph * 0.20))
    title_w = max(1, int(pw * 0.70))
    fh, fw = hsv.shape[:2]
    y1 = py
    y2 = min(py + title_h, fh)
    x1 = px
    x2 = min(px + title_w, fw)
    roi = hsv[y1:y2, x1:x2]
    if roi.size == 0:
        return 0.0
    orange_mask = cv2.inRange(roi, ORANGE_HSV_LO, ORANGE_HSV_HI)
    orange_pixels = cv2.countNonZero(orange_mask)
    title_area = (y2 - y1) * (x2 - x1)
    return min(1.0, orange_pixels / max(1, title_area * 0.02))


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

@dataclass
class DetectionResult:
    ok: bool
    timing_ms: float
    frame_w: int
    frame_h: int
    panel_found: bool = False
    panel_confidence: float = 0.0
    panel_rect: Optional[Rect] = None
    transfer_found: bool = False
    transfer_confidence: float = 0.0
    transfer_rect: Optional[Rect] = None
    orange_title_confidence: float = 0.0
    debug_overlay_path: Optional[str] = None
    debug_panel_crop_path: Optional[str] = None
    error: Optional[str] = None

    def to_dict(self) -> dict:
        d: dict = {
            "ok": self.ok,
            "timing_ms": round(self.timing_ms, 2),
            "frame": {"w": self.frame_w, "h": self.frame_h},
            "panel": {
                "found": self.panel_found,
                "confidence": round(self.panel_confidence, 3),
                "rect": _rect_to_dict(self.panel_rect),
            },
            "anchors": {
                "transfer_button": {
                    "found": self.transfer_found,
                    "confidence": round(self.transfer_confidence, 3),
                    "rect": _rect_to_dict(self.transfer_rect),
                }
            },
            "orange_title_confidence": round(self.orange_title_confidence, 3),
            "debug": {
                "overlay": self.debug_overlay_path,
                "panel_crop": self.debug_panel_crop_path,
            },
        }
        if self.error:
            d["error"] = self.error
        return d


def _rect_to_dict(r: Optional[Rect]) -> Optional[dict]:
    if r is None:
        return None
    x, y, w, h = r
    cx, cy = rect_center(r)
    return {"x": x, "y": y, "w": w, "h": h, "cx": cx, "cy": cy}


def detect(
    frame_bgr: np.ndarray,
    debug_dir: Optional[Path] = None,
    image_name: str = "frame",
) -> DetectionResult:
    """
    Run the full ChemMaster panel detection pipeline on *frame_bgr*.

    Parameters
    ----------
    frame_bgr:
        BGR image as a numpy array (e.g. from cv2.imread or mss).
    debug_dir:
        If provided, write overlay and panel-crop images here.
    image_name:
        Base name used for debug output files.

    Returns
    -------
    DetectionResult
    """
    t0 = time.perf_counter()
    fh, fw = frame_bgr.shape[:2]

    result = DetectionResult(ok=False, timing_ms=0.0, frame_w=fw, frame_h=fh)

    try:
        hsv = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2HSV)

        # --- Step 1: find Transfer button ---
        candidates = _find_green_button_candidates(hsv)
        if not candidates:
            result.timing_ms = (time.perf_counter() - t0) * 1000
            result.ok = True
            return result

        btn_score, btn_rect = candidates[0]
        result.transfer_found = True
        result.transfer_rect = btn_rect
        # Confidence: combine aspect-ratio fit and solidity quality.
        # Re-derive per-candidate quality without area dependence.
        bx, by, bw, bh = btn_rect
        b_aspect = bw / max(1, bh)
        # How close to the ideal Transfer-button aspect ratio (~3:1)
        aspect_quality = max(0.0, 1.0 - abs(b_aspect - 3.0) / 5.0)
        # Solidity was already >= _MIN_SOLIDITY; re-estimate from score relation
        # The score formula is: area * solidity / (1 + abs(aspect - 2.5))
        # We just use aspect_quality as a proxy for confidence
        result.transfer_confidence = min(1.0, 0.5 + aspect_quality * 0.5)

        # --- Step 2: find panel ---
        panel_result = _find_panel_rect(frame_bgr, hsv, btn_rect)
        if panel_result is not None:
            result.panel_rect, result.panel_confidence = panel_result
            result.panel_found = True

            # --- Step 3: orange title validation ---
            result.orange_title_confidence = _orange_title_confidence(
                hsv, result.panel_rect
            )
            # Boost panel confidence when title is confirmed
            result.panel_confidence = min(
                1.0,
                result.panel_confidence + result.orange_title_confidence * 0.3,
            )

        # --- Debug output ---
        if debug_dir is not None:
            debug_dir = Path(debug_dir)
            debug_dir.mkdir(parents=True, exist_ok=True)

            overlay = frame_bgr.copy()
            if result.panel_found and result.panel_rect:
                px, py, pw, ph = result.panel_rect
                cv2.rectangle(overlay, (px, py), (px + pw, py + ph), (0, 200, 255), 3)

            if result.transfer_found and result.transfer_rect:
                bx, by, bw, bh = result.transfer_rect
                cv2.rectangle(overlay, (bx, by), (bx + bw, by + bh), (0, 255, 0), 2)
                cx, cy = rect_center(result.transfer_rect)
                cv2.drawMarker(overlay, (cx, cy), (0, 255, 0), cv2.MARKER_CROSS, 20, 2)

            overlay_path = debug_dir / f"{image_name}_overlay.png"
            cv2.imwrite(str(overlay_path), overlay)
            result.debug_overlay_path = str(overlay_path)

            if result.panel_found and result.panel_rect:
                px, py, pw, ph = result.panel_rect
                crop = frame_bgr[py : py + ph, px : px + pw]
                crop_path = debug_dir / f"{image_name}_panel_crop.png"
                cv2.imwrite(str(crop_path), crop)
                result.debug_panel_crop_path = str(crop_path)

        result.ok = True

    except Exception as exc:
        result.ok = False
        result.error = str(exc)

    result.timing_ms = (time.perf_counter() - t0) * 1000
    return result

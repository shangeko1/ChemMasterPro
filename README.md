# ChemMasterPro
Take the clicking out of Chemistry, I will develop arthritis and it won't be to this >:/

---

## Computer Vision – Phase 1 Setup

ChemMasterPro now includes a Python-based vision helper that can locate the
**ChemMaster 4000** panel and the green **Transfer** button in screenshots or
in a live game window using deterministic colour-and-contour detection
(no machine-learning required).

### Prerequisites

| Requirement | Version |
|-------------|---------|
| Python      | 3.9+    |
| AutoHotkey  | v2.0    |

### Installation

```bash
# From the repo root:
pip install -r vision/requirements.txt
```

### Running detection on a saved image (offline testing)

```bash
python vision/vision_cli.py \
    --mode detect \
    --input file \
    --image "path/to/screenshot.png" \
    --debug-dir "./debug"
```

Example with one of the bundled test images:

```bash
python vision/vision_cli.py --mode detect --input file \
    --image "test_images/test12 Just ChemMaster.png" \
    --debug-dir "./debug"
```

**Expected stdout** (formatted for readability):

```json
{
  "ok": true,
  "timing_ms": 45.2,
  "frame": { "w": 1920, "h": 1080 },
  "panel": {
    "found": true,
    "confidence": 0.87,
    "rect": { "x": 842, "y": 133, "w": 348, "h": 620, "cx": 1016, "cy": 443 }
  },
  "anchors": {
    "transfer_button": {
      "found": true,
      "confidence": 0.95,
      "rect": { "x": 855, "y": 145, "w": 84, "h": 24, "cx": 897, "cy": 157 }
    }
  },
  "orange_title_confidence": 0.73,
  "debug": {
    "overlay":     "debug/test12 Just ChemMaster_overlay.png",
    "panel_crop":  "debug/test12 Just ChemMaster_panel_crop.png"
  }
}
```

The `debug/` directory will contain:
- `*_overlay.png` – original frame with coloured rectangles drawn:
  - **Cyan** rectangle → detected panel bounds
  - **Green** rectangle + cross-hair → Transfer button
- `*_panel_crop.png` – cropped panel region

### Running detection from a live game screenshot

```bash
python vision/vision_cli.py --mode detect --input screenshot --debug-dir ./debug
```

### CLI reference

| Argument | Values | Default | Description |
|----------|--------|---------|-------------|
| `--mode` | `detect` | `detect` | Operation mode |
| `--input` | `screenshot` \| `file` | `file` | Image source |
| `--image` | path | — | Required when `--input file` |
| `--debug-dir` | path | — | Write overlay/crop images here |

### AHK integration

Include `VisionHelper.ahk` in your AutoHotkey script:

```ahk
#Include "VisionHelper.ahk"

; Enable vision-assisted clicking
g_VisionEnabled := true

; Detect from a saved image file
result := VisionDetectFile("C:\screenshots\chemmaster.png", "C:\debug")
if result.ok && result.panel.found
    MsgBox("Panel at: " result.panel.rect.cx ", " result.panel.rect.cy)

; Detect from live screen capture
result := VisionDetectScreen("C:\debug")
if result.anchors.transfer_button.found {
    cx := result.anchors.transfer_button.rect.cx
    cy := result.anchors.transfer_button.rect.cy
    MouseMove(cx, cy)
    Click()
}

; One-shot: detect and click Transfer (only acts when g_VisionEnabled = true)
VisionClickTransfer()
```

#### How the AHK ↔ Python bridge works

1. AHK calls `RunWait` to launch `python vision_cli.py …`, redirecting stdout
   to a temporary JSON file.
2. AHK reads and parses the JSON file using a built-in `ScriptControl`
   JScript parser (no third-party AHK library needed).
3. The result is a nested AHK object with the same structure as the JSON.

The `g_VisionEnabled` global flag (default `false`) guards all
vision-assisted click actions, so no existing hotkey behaviour changes until
you opt in.

### Detection strategy (Phase 1)

1. **Green Transfer button** – HSV thresholding `H 40–95, S 90–255, V 90–255`;
   contours filtered by minimum area, aspect ratio `1–8`, and solidity ≥ 0.6.
2. **Dark panel bounds** – expand an ROI around the Transfer button anchor;
   threshold for dark pixels `V < 70`; find largest dark contour that encloses
   the button.
3. **Orange title validation** – scan the top-20 % / left-70 % of the panel
   for orange pixels `H 8–30`; increases panel confidence when confirmed.
4. **JSON output** – includes `ok`, `timing_ms`, frame size, panel rect,
   Transfer button rect, per-field confidence scores, and debug file paths.

### Test images

Place test images in `test_images/` (not committed – add your own):

| File | Scene |
|------|-------|
| `test9.png`  | Full screen with ChemMaster panel visible |
| `test10.png` | Full screen with ChemMaster panel visible |
| `test11.png` | Full screen with ChemMaster panel visible |
| `test12 Just ChemMaster.png` | Panel only (close-up) |

Run the offline workflow:

```bash
for img in test_images/test9.png test_images/test10.png \
            test_images/test11.png "test_images/test12 Just ChemMaster.png"; do
    echo "--- $img ---"
    python vision/vision_cli.py --mode detect --input file \
        --image "$img" --debug-dir "./debug"
done
```

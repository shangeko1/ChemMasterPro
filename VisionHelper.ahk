; =====================================================================
; VisionHelper.ahk
; AHK v2 wrapper around the Python vision_cli.py detection script.
;
; Usage (from ChemMasterPro.ahk or as standalone):
;   #Include "VisionHelper.ahk"
;
;   ; Run detection on a saved image file:
;   result := VisionDetectFile("C:\path\to\screenshot.png", "C:\debug")
;
;   ; Run detection from a live screenshot:
;   result := VisionDetectScreen("C:\debug")
;
;   ; Access results:
;   if result.ok {
;       MsgBox("Panel found: " result.panel.found)
;       if result.anchors.transfer_button.found {
;           cx := result.anchors.transfer_button.rect.cx
;           cy := result.anchors.transfer_button.rect.cy
;           MouseMove(cx, cy)
;       }
;   }
;
; Toggle:  Set g_VisionEnabled := true to activate vision-assisted clicking.
; =====================================================================

; Global toggle – set true to enable vision-assisted Transfer clicking.
global g_VisionEnabled := false

; Path to the Python interpreter (must be on PATH, or provide full path).
global g_PythonExe := "python"

; Path to vision_cli.py relative to this script's directory.
global g_VisionCliPath := A_ScriptDir "\vision\vision_cli.py"

; ---------------------------------------------------------------------------
; VisionDetectFile(imagePath, debugDir := "")
;   Run detection on an image file.
;   Returns a parsed result object or an object with ok=false on error.
; ---------------------------------------------------------------------------
VisionDetectFile(imagePath, debugDir := "") {
    args := '--mode detect --input file --image "' imagePath '"'
    if (debugDir != "")
        args .= ' --debug-dir "' debugDir '"'
    return _VisionRun(args)
}

; ---------------------------------------------------------------------------
; VisionDetectScreen(debugDir := "")
;   Capture the primary monitor and run detection.
;   Returns a parsed result object or an object with ok=false on error.
; ---------------------------------------------------------------------------
VisionDetectScreen(debugDir := "") {
    args := "--mode detect --input screenshot"
    if (debugDir != "")
        args .= ' --debug-dir "' debugDir '"'
    return _VisionRun(args)
}

; ---------------------------------------------------------------------------
; VisionClickTransfer(imagePath := "", debugDir := "")
;   Convenience: detect, then move and click the Transfer button center.
;   Pass imagePath="" to use live screenshot capture.
;   Returns true on success, false otherwise.
;   Only acts when g_VisionEnabled is true.
; ---------------------------------------------------------------------------
VisionClickTransfer(imagePath := "", debugDir := "") {
    if (!g_VisionEnabled)
        return false

    result := (imagePath == "")
        ? VisionDetectScreen(debugDir)
        : VisionDetectFile(imagePath, debugDir)

    if (!result.ok)
        return false

    if (!result.anchors.transfer_button.found)
        return false

    cx := result.anchors.transfer_button.rect.cx
    cy := result.anchors.transfer_button.rect.cy
    MouseMove(cx, cy)
    Sleep(50)
    Click()
    return true
}

; ---------------------------------------------------------------------------
; Internal: run vision_cli.py with given arguments, return parsed JSON object.
; ---------------------------------------------------------------------------
_VisionRun(args) {
    cmd := '"' g_PythonExe '" "' g_VisionCliPath '" ' args

    ; Run python and capture stdout via a temp file to avoid shell window
    tmpFile := A_Temp "\vision_result_" A_TickCount ".json"
    RunWait(cmd ' > "' tmpFile '"', , "Hide")

    if (!FileExist(tmpFile))
        return _VisionError("vision_cli.py produced no output")

    rawJson := FileRead(tmpFile)
    try FileDelete(tmpFile)

    if (rawJson == "")
        return _VisionError("vision_cli.py output was empty")

    return _VisionParseJson(rawJson)
}

; ---------------------------------------------------------------------------
; _VisionError(msg) – return a minimal error object.
; ---------------------------------------------------------------------------
_VisionError(msg) {
    obj := {}
    obj.ok := false
    obj.error := msg
    return obj
}

; ---------------------------------------------------------------------------
; _VisionParseJson(rawJson)
;   Minimal JSON parser for the fixed schema returned by detector.py.
;   Returns a nested AHK object matching the JSON structure.
;
;   For a production script, consider replacing with a proper JSON library.
; ---------------------------------------------------------------------------
_VisionParseJson(rawJson) {
    ; Use AHK's COM interface to parse JSON via JavaScript engine
    try {
        js := ComObject("ScriptControl")
        js.Language := "JScript"
        js.ExecuteStatement('var _r = ' rawJson ';')

        root := {}
        root.ok                    := js.Eval("_r.ok")
        root.timing_ms             := js.Eval("_r.timing_ms")
        root.orange_title_confidence := js.Eval("_r.orange_title_confidence")
        root.error                 := ""

        ; frame
        frame := {}
        frame.w := js.Eval("_r.frame.w")
        frame.h := js.Eval("_r.frame.h")
        root.frame := frame

        ; panel
        panel := {}
        panel.found      := js.Eval("_r.panel.found")
        panel.confidence := js.Eval("_r.panel.confidence")
        panel.rect       := _ParseRect(js, "_r.panel.rect")
        root.panel := panel

        ; anchors.transfer_button
        anchors := {}
        tb := {}
        tb.found      := js.Eval("_r.anchors.transfer_button.found")
        tb.confidence := js.Eval("_r.anchors.transfer_button.confidence")
        tb.rect       := _ParseRect(js, "_r.anchors.transfer_button.rect")
        anchors.transfer_button := tb
        root.anchors := anchors

        ; debug
        dbg := {}
        dbg.overlay    := js.Eval("_r.debug.overlay")
        dbg.panel_crop := js.Eval("_r.debug.panel_crop")
        root.debug := dbg

        return root
    } catch as e {
        return _VisionError("JSON parse error: " e.Message ". Raw: " SubStr(rawJson, 1, 200))
    }
}

; Helper: parse a rect sub-object from JScript; returns {} if null.
_ParseRect(js, path) {
    r := {}
    try {
        r.x  := js.Eval(path ".x")
        r.y  := js.Eval(path ".y")
        r.w  := js.Eval(path ".w")
        r.h  := js.Eval(path ".h")
        r.cx := js.Eval(path ".cx")
        r.cy := js.Eval(path ".cy")
    }
    return r
}

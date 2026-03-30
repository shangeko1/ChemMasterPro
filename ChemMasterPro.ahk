#Requires AutoHotkey v2.0
#SingleInstance Force

; =====================================================================
; ChemMasterPro - SS14 Chemistry Automation Tool
; Created by: Shangeko
; =====================================================================

; ==================== GLOBAL STATE ====================
global g_RecipeBooks   := []
global g_DataFile      := A_ScriptDir "\ChemMasterPro_Data.txt"
global g_MainGui       := ""
global g_CurrentPage   := "home"
global g_CurrentBookIdx := 1
global g_FilterTypes   := []
global g_SearchText    := ""

; Ingredient editor state
global g_IngEditorGui      := ""
global g_TypeSelectorGui   := ""
global g_DescGui           := ""
global g_BookSelectorGui   := ""
global g_BookDescGui       := ""
global g_EditRecipeName    := ""
global g_EditIngredients   := []
global g_EditDescription   := ""
global g_EditTypes         := []
global g_IsEditingExisting := false
global g_EditingBookIdx    := 0
global g_EditingRecipeIdx  := 0
global g_EditTotalAmount   := 0

; ==================== STARTUP ====================
LoadData()
ShowHome()

; ======================================================================
; DATA PERSISTENCE
; ======================================================================

LoadData() {
    global g_RecipeBooks, g_DataFile
    if !FileExist(g_DataFile)
        return
    try {
        content := FileRead(g_DataFile)
        g_RecipeBooks := DecodeData(content)
    } catch as e {
        MsgBox("Error loading saved data:`n" e.Message "`n`nStarting with empty data.", "ChemMasterPro", "Iconx")
        g_RecipeBooks := []
    }
}

SaveData() {
    global g_RecipeBooks, g_DataFile
    try FileDelete(g_DataFile)
    FileAppend(EncodeData(g_RecipeBooks), g_DataFile)
}

EncodeData(books) {
    result := ""
    for book in books {
        result .= "BOOK_NAME:" EscLine(book.name) "`n"
        result .= "BOOK_DESC:" EscLine(book.description) "`n"
        for recipe in book.recipes {
            result .= "RECIPE_NAME:" EscLine(recipe.name) "`n"
            result .= "RECIPE_DESC:" EscLine(recipe.description) "`n"
            typesStr := ""
            for t in recipe.types
                typesStr .= t ","
            result .= "RECIPE_TYPES:" RTrim(typesStr, ",") "`n"
            if recipe.HasProp("totalAmount")
                result .= "RECIPE_TOTAL:" recipe.totalAmount "`n"
            for ing in recipe.ingredients {
                result .= "ING_NAME:" EscLine(ing.name) "`n"
                result .= "ING_AMT:"  ing.amount "`n"
            }
            result .= "ENDRECIPE`n"
        }
        result .= "ENDBOOK`n"
    }
    return result
}

EscLine(s) {
    s := StrReplace(s, "\",  "\\")
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`r", "\r")
    return s
}

UnescLine(s) {
    result := ""
    i := 1
    while i <= StrLen(s) {
        c := SubStr(s, i, 1)
        if c = "\" {
            nc := SubStr(s, i+1, 1)
            if nc = "n" {
                result .= "`n"
                i += 2
                continue
            } else if nc = "r" {
                result .= "`r"
                i += 2
                continue
            } else if nc = "\" {
                result .= "\"
                i += 2
                continue
            }
        }
        result .= c
        i++
    }
    return result
}

DecodeData(content) {
    books         := []
    currentBook   := ""
    currentRecipe := ""

    loop parse, content, "`n", "`r" {
        line := A_LoopField
        if line = ""
            continue

        if SubStr(line, 1, 10) = "BOOK_NAME:" {
            currentBook := { name: UnescLine(SubStr(line, 11)), description: "", recipes: [] }

        } else if SubStr(line, 1, 10) = "BOOK_DESC:" {
            if IsObject(currentBook)
                currentBook.description := UnescLine(SubStr(line, 11))

        } else if SubStr(line, 1, 12) = "RECIPE_NAME:" {
            currentRecipe := { name: UnescLine(SubStr(line, 13)), description: "", types: [], ingredients: [], totalAmount: 0 }

        } else if SubStr(line, 1, 12) = "RECIPE_DESC:" {
            if IsObject(currentRecipe)
                currentRecipe.description := UnescLine(SubStr(line, 13))

        } else if SubStr(line, 1, 13) = "RECIPE_TYPES:" {
            if IsObject(currentRecipe) {
                for t in StrSplit(SubStr(line, 14), ",")
                    if Trim(t) != ""
                        currentRecipe.types.Push(Trim(t))
            }

        } else if SubStr(line, 1, 12) = "RECIPE_TOTAL:" {
            if IsObject(currentRecipe)
                currentRecipe.totalAmount := Integer(Trim(SubStr(line, 13)))

        } else if SubStr(line, 1, 9) = "ING_NAME:" {
            if IsObject(currentRecipe)
                currentRecipe.ingredients.Push({ name: UnescLine(SubStr(line, 10)), amount: 0 })

        } else if SubStr(line, 1, 8) = "ING_AMT:" {
            if IsObject(currentRecipe) && currentRecipe.ingredients.Length > 0 {
                rawAmt := Trim(SubStr(line, 9))
                currentRecipe.ingredients[currentRecipe.ingredients.Length].amount := IsInteger(rawAmt) ? Integer(rawAmt) : 0
            }

        } else if line = "ENDRECIPE" {
            if IsObject(currentRecipe) && IsObject(currentBook) {
                currentBook.recipes.Push(currentRecipe)
                currentRecipe := ""
            }

        } else if line = "ENDBOOK" {
            if IsObject(currentBook) {
                books.Push(currentBook)
                currentBook := ""
            }
        }
    }
    return books
}

; ======================================================================
; UTILITY
; ======================================================================

GetTotalUnits(recipe) {
    if recipe.HasProp("totalAmount") && recipe.totalAmount > 0
        return recipe.totalAmount
    total := 0
    for ing in recipe.ingredients
        total += ing.amount
    return total
}

TypesStr(types) {
    s := ""
    for t in types
        s .= t "/"
    return RTrim(s, "/")
}

HasType(recipe, typeName) {
    for t in recipe.types
        if t = typeName
            return true
    return false
}

CloneIngredients(ings) {
    result := []
    for ing in ings
        result.Push({ name: ing.name, amount: ing.amount })
    return result
}

CloneArray(arr) {
    result := []
    for item in arr
        result.Push(item)
    return result
}

; ======================================================================
; HOME PAGE
; ======================================================================

ShowHome() {
    global g_MainGui, g_CurrentPage
    if IsObject(g_MainGui)
        g_MainGui.Destroy()
    g_MainGui := ""

    g_CurrentPage := "home"
    g_MainGui := Gui(, "ChemMasterPro")
    g_MainGui.BackColor := "1E1E2E"

    g_MainGui.SetFont("s22 Bold cFFFFFF", "Segoe UI")
    g_MainGui.Add("Text", "x0 y28 w600 Center", "ChemMasterPro")

    g_MainGui.SetFont("s10 c888888", "Segoe UI")
    g_MainGui.Add("Text", "x0 y65 w600 Center", "SS14 Chemistry Automation Tool  |  by Shangeko")

    g_MainGui.SetFont("s11 cFFFFFF", "Segoe UI")

    bW := 270
    bH := 52
    bX := 165

    b1 := g_MainGui.Add("Button", "x" bX " y118 w" bW " h" bH, "  Create New Recipe")
    b2 := g_MainGui.Add("Button", "x" bX " y182 w" bW " h" bH, "  Recipe Book")
    b3 := g_MainGui.Add("Button", "x" bX " y246 w" bW " h" bH, "  Import")
    b4 := g_MainGui.Add("Button", "x" bX " y310 w" bW " h" bH, "  Credits")

    b1.OnEvent("Click", (*) => ShowCreateRecipeName())
    b2.OnEvent("Click", (*) => ShowRecipeBookPage())
    b3.OnEvent("Click", (*) => ShowImport())
    b4.OnEvent("Click", (*) => ShowCredits())

    g_MainGui.Show("w600 h400")
}

; ======================================================================
; CREATE RECIPE  -  name prompt
; ======================================================================

ShowCreateRecipeName() {
    result := InputBox("Enter a name for this recipe:", "Create New Recipe", "w340 h130")
    if result.Result != "OK" || Trim(result.Value) = ""
        return
    ShowIngredientEditor(Trim(result.Value), false)
}

; ======================================================================
; INGREDIENT EDITOR
; ======================================================================

ShowIngredientEditor(recipeName, isEditing, bookIdx := 0, recipeIdx := 0) {
    global g_EditRecipeName, g_EditIngredients, g_EditDescription, g_EditTypes
    global g_IsEditingExisting, g_EditingBookIdx, g_EditingRecipeIdx, g_RecipeBooks

    g_EditRecipeName    := recipeName
    g_IsEditingExisting := isEditing
    g_EditingBookIdx    := bookIdx
    g_EditingRecipeIdx  := recipeIdx

    if isEditing {
        recipe            := g_RecipeBooks[bookIdx].recipes[recipeIdx]
        g_EditIngredients := CloneIngredients(recipe.ingredients)
        g_EditDescription := recipe.description
        g_EditTypes       := CloneArray(recipe.types)
        g_EditTotalAmount := recipe.HasProp("totalAmount") ? recipe.totalAmount : 0
    } else {
        g_EditIngredients := []
        g_EditDescription := ""
        g_EditTypes       := []
        g_EditTotalAmount := 0
    }

    DrawIngredientEditor()
}

DrawIngredientEditor() {
    global g_IngEditorGui, g_EditIngredients, g_EditTypes, g_EditRecipeName, g_EditDescription

    if IsObject(g_IngEditorGui)
        g_IngEditorGui.Destroy()

    g_IngEditorGui := Gui("+AlwaysOnTop", "Recipe Editor: " g_EditRecipeName)
    g_IngEditorGui.SetFont("s10", "Segoe UI")
    g_IngEditorGui.BackColor := "2A2A3E"

    ; Title
    g_IngEditorGui.SetFont("s13 Bold cFFFFFF", "Segoe UI")
    g_IngEditorGui.Add("Text", "x10 y12 w560", "Recipe: " g_EditRecipeName)
    g_IngEditorGui.Add("Text", "x10 y34 w560 h2 0x10")   ; divider

    ; Column headers
    y := 44
    g_IngEditorGui.SetFont("s9 c888888", "Segoe UI")
    if g_EditIngredients.Length > 0 {
        g_IngEditorGui.Add("Text", "x10 y" y " w185", "Ingredient")
        g_IngEditorGui.Add("Text", "x200 y" y " w60", "Amount")
        y += 17
    }

    ; Ingredient rows
    g_IngEditorGui.SetFont("s10 cFFFFFF", "Segoe UI")
    if g_EditIngredients.Length = 0 {
        g_IngEditorGui.SetFont("s10 c666666", "Segoe UI")
        g_IngEditorGui.Add("Text", "x20 y" y " w540", "(No ingredients added yet)")
        g_IngEditorGui.SetFont("s10 cFFFFFF", "Segoe UI")
        y += 28
    } else {
        for i, ing in g_EditIngredients {
            ci := i
            g_IngEditorGui.Add("Text", "x10 y" (y+4) " w185 cFFFFFF", ing.name)
            g_IngEditorGui.Add("Text", "x200 y" (y+4) " w60 c00FF88", ing.amount "u")

            bE  := g_IngEditorGui.Add("Button", "x268 y" y   " w55 h26", "Edit")
            bD  := g_IngEditorGui.Add("Button", "x328 y" y   " w58 h26", "Delete")
            bUp := g_IngEditorGui.Add("Button", "x392 y" y   " w38 h26", "▲")
            bDn := g_IngEditorGui.Add("Button", "x435 y" y   " w38 h26", "▼")

            bE.OnEvent("Click",  IngEdit_Handler.Bind(ci))
            bD.OnEvent("Click",  IngDelete_Handler.Bind(ci))
            bUp.OnEvent("Click", IngMoveUp_Handler.Bind(ci))
            bDn.OnEvent("Click", IngMoveDown_Handler.Bind(ci))

            y += 32
        }
    }

    ; Divider
    g_IngEditorGui.Add("Text", "x10 y" y " w560 h2 0x10")
    y += 10

    ; Controls row
    g_IngEditorGui.SetFont("s10 cFFFFFF", "Segoe UI")
    btnAdd := g_IngEditorGui.Add("Button", "x10 y" y " w140 h30", "Ingredient [+]")
    btnAdd.OnEvent("Click", (*) => PromptAddIngredient())

    typeLabel := (g_EditTypes.Length > 0) ? "Type: " TypesStr(g_EditTypes) : "Type: (Required)"
    btnType := g_IngEditorGui.Add("Button", "x158 y" y " w190 h30", typeLabel)
    btnType.OnEvent("Click", (*) => ShowTypeSelector())

    descLabel := (g_EditDescription != "") ? "Description (set)" : "Description"
    btnDesc := g_IngEditorGui.Add("Button", "x356 y" y " w135 h30", descLabel)
    btnDesc.OnEvent("Click", (*) => ShowDescriptionEditor())

    y += 40
    totalLabel := (g_EditTotalAmount > 0) ? "Total: " g_EditTotalAmount "u" : "Total: Auto"
    btnTotal := g_IngEditorGui.Add("Button", "x356 y" y " w135 h30", totalLabel)
    btnTotal.OnEvent("Click", (*) => ShowTotalEditor())

    y += 40
    g_IngEditorGui.Add("Text", "x10 y" y " w560 h2 0x10")
    y += 10

    btnClose := g_IngEditorGui.Add("Button", "x10 y" y " w100 h32", "Close")
    btnSave  := g_IngEditorGui.Add("Button", "x395 y" y " w155 h32", "Save Recipe")

    btnClose.OnEvent("Click", (*) => IngEditorClose())
    btnSave.OnEvent("Click",  (*) => IngEditorSave())

    g_IngEditorGui.Show("w560 h" (y + 55))
}

; ---------- Ingredient handlers ----------

IngEdit_Handler(idx, *) {
    global g_EditIngredients
    ing := g_EditIngredients[idx]

    r1 := InputBox("Edit ingredient name:", "Edit Ingredient", "w300 h130", ing.name)
    if r1.Result != "OK"
        return
    newName := Trim(r1.Value)
    if newName = ""
        return

    r2 := InputBox("Edit amount (units) for '" newName "':", "Edit Ingredient", "w300 h130", ing.amount)
    if r2.Result != "OK"
        return
    newAmt := Trim(r2.Value)
    if !IsInteger(newAmt) || Integer(newAmt) <= 0 {
        MsgBox("Please enter a valid positive number.", "Invalid Amount", "Icon!")
        return
    }

    g_EditIngredients[idx].name   := newName
    g_EditIngredients[idx].amount := Integer(newAmt)
    DrawIngredientEditor()
}

IngDelete_Handler(idx, *) {
    global g_EditIngredients
    ingName := g_EditIngredients[idx].name
    if MsgBox("Delete ingredient '" ingName "'?", "Confirm Delete", "YesNo Icon?") = "Yes" {
        g_EditIngredients.RemoveAt(idx)
        DrawIngredientEditor()
    }
}

IngMoveUp_Handler(idx, *) {
    global g_EditIngredients
    if idx <= 1
        return
    temp := g_EditIngredients[idx]
    g_EditIngredients[idx]     := g_EditIngredients[idx - 1]
    g_EditIngredients[idx - 1] := temp
    DrawIngredientEditor()
}

IngMoveDown_Handler(idx, *) {
    global g_EditIngredients
    if idx >= g_EditIngredients.Length
        return
    temp := g_EditIngredients[idx]
    g_EditIngredients[idx]     := g_EditIngredients[idx + 1]
    g_EditIngredients[idx + 1] := temp
    DrawIngredientEditor()
}

PromptAddIngredient() {
    r1 := InputBox("Enter ingredient name:", "Add Ingredient", "w300 h130")
    if r1.Result != "OK" || Trim(r1.Value) = ""
        return
    ingName := Trim(r1.Value)

    r2 := InputBox("Enter amount (units) for '" ingName "':", "Add Ingredient", "w300 h130")
    if r2.Result != "OK" || Trim(r2.Value) = ""
        return
    newAmt := Trim(r2.Value)
    if !IsInteger(newAmt) || Integer(newAmt) <= 0 {
        MsgBox("Please enter a valid positive number.", "Invalid Amount", "Icon!")
        return
    }

    global g_EditIngredients
    g_EditIngredients.Push({ name: ingName, amount: Integer(newAmt) })
    DrawIngredientEditor()
}

; ---------- Type selector ----------

ShowTypeSelector() {
    global g_EditTypes, g_TypeSelectorGui

    if IsObject(g_TypeSelectorGui)
        g_TypeSelectorGui.Destroy()

    g_TypeSelectorGui := Gui("+AlwaysOnTop", "Select Recipe Types")
    g_TypeSelectorGui.SetFont("s10", "Segoe UI")
    g_TypeSelectorGui.BackColor := "1E1E2E"

    g_TypeSelectorGui.SetFont("s13 Bold cFFFFFF", "Segoe UI")
    g_TypeSelectorGui.Add("Text", "x10 y15 w320 Center", "Select Type(s)")
    g_TypeSelectorGui.SetFont("s9 cAAAAAA", "Segoe UI")
    g_TypeSelectorGui.Add("Text", "x10 y40 w320 Center", "At least one selection is required to save")

    allTypes  := ["Burn", "Brute", "Toxin", "Oxygen"]
    checkboxes := []
    y := 72

    for t in allTypes {
        isChecked := false
        for et in g_EditTypes
            if et = t
                isChecked := true

        g_TypeSelectorGui.SetFont("s12 cFFFFFF", "Segoe UI")
        cb := g_TypeSelectorGui.Add("Checkbox", "x30 y" y " w280 h26", t)
        cb.Value := isChecked ? 1 : 0
        checkboxes.Push({ ctrl: cb, typeName: t })
        y += 32
    }

    y += 5
    g_TypeSelectorGui.SetFont("s10 cFFFFFF", "Segoe UI")
    btnOK     := g_TypeSelectorGui.Add("Button", "x30 y" y " w120 h30", "OK")
    btnCancel := g_TypeSelectorGui.Add("Button", "x170 y" y " w120 h30", "Cancel")

    btnOK.OnEvent("Click",     TypeSelectorOK_Handler.Bind(checkboxes))
    btnCancel.OnEvent("Click", (*) => g_TypeSelectorGui.Destroy())

    g_TypeSelectorGui.Show("w340 h" (y + 55))
}

TypeSelectorOK_Handler(checkboxes, *) {
    global g_EditTypes, g_TypeSelectorGui

    newTypes := []
    for item in checkboxes
        if item.ctrl.Value
            newTypes.Push(item.typeName)

    if newTypes.Length = 0 {
        MsgBox("Please select at least one type.", "Type Required", "Icon!")
        return
    }

    g_EditTypes := newTypes
    g_TypeSelectorGui.Destroy()
    DrawIngredientEditor()
}

; ---------- Description editor ----------

ShowDescriptionEditor() {
    global g_EditDescription, g_DescGui

    if IsObject(g_DescGui)
        g_DescGui.Destroy()

    g_DescGui := Gui("+AlwaysOnTop", "Recipe Description")
    g_DescGui.SetFont("s10", "Segoe UI")
    g_DescGui.BackColor := "2A2A3E"

    g_DescGui.SetFont("s12 Bold cFFFFFF", "Segoe UI")
    g_DescGui.Add("Text", "x10 y12 w380", "Recipe Description")
    g_DescGui.SetFont("s9 cAAAAAA", "Segoe UI")
    g_DescGui.Add("Text", "x10 y35 w380", "Optional — describe this recipe and its uses")

    g_DescGui.SetFont("s10 cFFFFFF", "Segoe UI")
    editCtrl := g_DescGui.Add("Edit", "x10 y58 w380 h140 Multi WantReturn +Background2A2A3E", g_EditDescription)

    btnSave   := g_DescGui.Add("Button", "x10  y208 w180 h30", "Save")
    btnCancel := g_DescGui.Add("Button", "x200 y208 w180 h30", "Cancel")

    btnSave.OnEvent("Click",   DescSave_Handler.Bind(editCtrl))
    btnCancel.OnEvent("Click", (*) => g_DescGui.Destroy())

    g_DescGui.Show("w400 h260")
}

DescSave_Handler(editCtrl, *) {
    global g_EditDescription, g_DescGui
    g_EditDescription := editCtrl.Value
    g_DescGui.Destroy()
    g_DescGui := ""
}

ShowTotalEditor() {
    global g_EditTotalAmount
    r := InputBox("Set total amount (leave empty for auto-calculated):", "Total Amount", "w350 h130", g_EditTotalAmount)
    if r.Result = "OK" {
        val := Trim(r.Value)
        g_EditTotalAmount := val = "" ? 0 : (IsInteger(val) ? Integer(val) : 0)
        DrawIngredientEditor()
    }
}

; ---------- Save recipe ----------

IngEditorClose() {
    global g_IngEditorGui
    if IsObject(g_IngEditorGui) {
        g_IngEditorGui.Destroy()
        g_IngEditorGui := ""
    }
}

IngEditorSave() {
    global g_EditIngredients, g_EditTypes, g_EditRecipeName, g_EditDescription
    global g_IsEditingExisting, g_EditingBookIdx, g_EditingRecipeIdx, g_RecipeBooks

    if g_EditIngredients.Length = 0 {
        MsgBox("Please add at least one ingredient.", "Cannot Save", "Icon!")
        return
    }
    if g_EditTypes.Length = 0 {
        MsgBox("Please select at least one type (Burn/Brute/Toxin/Oxygen).", "Cannot Save", "Icon!")
        return
    }

    ; Build recipe object
    recipe := {
        name:        g_EditRecipeName,
        description: g_EditDescription,
        types:       CloneArray(g_EditTypes),
        ingredients: CloneIngredients(g_EditIngredients),
        totalAmount: g_EditTotalAmount
    }

    ; Updating an existing recipe
    if g_IsEditingExisting {
        g_RecipeBooks[g_EditingBookIdx].recipes[g_EditingRecipeIdx] := recipe
        SaveData()
        MsgBox("Recipe updated successfully!", "Updated", "Iconi")
        IngEditorClose()
        ShowRecipeBookPage()
        return
    }

    ; Ensure at least one recipe book exists
    if g_RecipeBooks.Length = 0 {
        result := InputBox("No recipe books exist yet.`nEnter a name for your first recipe book:", "Create Recipe Book", "w340 h140")
        if result.Result != "OK" || Trim(result.Value) = ""
            return
        g_RecipeBooks.Push({ name: Trim(result.Value), description: "", recipes: [] })
        SaveData()
    }

    if g_RecipeBooks.Length = 1 {
        g_RecipeBooks[1].recipes.Push(recipe)
        SaveData()
        MsgBox("Recipe '" recipe.name "' saved to '" g_RecipeBooks[1].name "'!", "Saved", "Iconi")
        IngEditorClose()
    } else {
        ShowBookSelector(recipe)
    }
}

ShowBookSelector(recipe) {
    global g_RecipeBooks, g_BookSelectorGui

    if IsObject(g_BookSelectorGui)
        g_BookSelectorGui.Destroy()

    g_BookSelectorGui := Gui("+AlwaysOnTop", "Choose Recipe Book(s)")
    g_BookSelectorGui.SetFont("s10", "Segoe UI")
    g_BookSelectorGui.BackColor := "1E1E2E"

    g_BookSelectorGui.SetFont("s13 Bold cFFFFFF", "Segoe UI")
    g_BookSelectorGui.Add("Text", "x10 y12 w380", "Save to Recipe Book(s):")
    g_BookSelectorGui.SetFont("s9 cAAAAAA", "Segoe UI")
    g_BookSelectorGui.Add("Text", "x10 y35 w380", "Select at least one")

    checkboxes := []
    y := 62
    for i, book in g_RecipeBooks {
        g_BookSelectorGui.SetFont("s11 cFFFFFF", "Segoe UI")
        cb := g_BookSelectorGui.Add("Checkbox", "x15 y" y " w370 h26", book.name)
        cb.Value := (i = 1) ? 1 : 0
        checkboxes.Push({ ctrl: cb, bookIdx: i })
        y += 30
    }

    y += 8
    g_BookSelectorGui.SetFont("s10 cFFFFFF", "Segoe UI")
    btnSave   := g_BookSelectorGui.Add("Button", "x10  y" y " w180 h32", "Save")
    btnCancel := g_BookSelectorGui.Add("Button", "x200 y" y " w180 h32", "Cancel")

    btnSave.OnEvent("Click",   BookSelectorSave_Handler.Bind(recipe, checkboxes))
    btnCancel.OnEvent("Click", (*) => g_BookSelectorGui.Destroy())

    g_BookSelectorGui.Show("w400 h" (y + 55))
}

BookSelectorSave_Handler(recipe, checkboxes, *) {
    global g_RecipeBooks, g_BookSelectorGui

    selected := []
    for item in checkboxes
        if item.ctrl.Value
            selected.Push(item.bookIdx)

    if selected.Length = 0 {
        MsgBox("Please select at least one recipe book.", "Required", "Icon!")
        return
    }

    for bookIdx in selected {
        r := {
            name:        recipe.name,
            description: recipe.description,
            types:       CloneArray(recipe.types),
            ingredients: CloneIngredients(recipe.ingredients)
        }
        g_RecipeBooks[bookIdx].recipes.Push(r)
    }
    SaveData()
    g_BookSelectorGui.Destroy()
    MsgBox("Recipe saved to " selected.Length " recipe book(s)!", "Saved", "Iconi")
    IngEditorClose()
}

; ======================================================================
; RECIPE BOOK PAGE
; ======================================================================

ShowRecipeBookPage() {
    global g_MainGui, g_RecipeBooks, g_CurrentBookIdx, g_CurrentPage
    global g_FilterTypes, g_SearchText

    if g_RecipeBooks.Length = 0 {
        result := InputBox("No recipe books found.`nEnter a name for your first recipe book:", "Create Recipe Book", "w340 h140")
        if result.Result != "OK" || Trim(result.Value) = ""
            return
        g_RecipeBooks.Push({ name: Trim(result.Value), description: "", recipes: [] })
        SaveData()
        g_CurrentBookIdx := 1
    }

    if g_CurrentBookIdx < 1 || g_CurrentBookIdx > g_RecipeBooks.Length
        g_CurrentBookIdx := 1

    if IsObject(g_MainGui)
        g_MainGui.Destroy()
    g_MainGui := ""

    g_CurrentPage := "recipebook"
    g_MainGui := Gui("+Resize", "ChemMasterPro - Recipe Book")
    g_MainGui.SetFont("s10", "Segoe UI")
    g_MainGui.BackColor := "1E1E2E"

    ; ── Top bar ────────────────────────────────────────────────────────
    g_MainGui.SetFont("s10 cFFFFFF", "Segoe UI")
    btnHome := g_MainGui.Add("Button", "x8 y8 w75 h28", "Home")
    btnHome.OnEvent("Click", HomeBtn_Handler)

    g_MainGui.SetFont("s14 Bold cFFFFFF", "Segoe UI")
    g_MainGui.Add("Text", "x0 y12 w750 Center", "Recipe Book")
    g_MainGui.SetFont("s10 cFFFFFF", "Segoe UI")

    ; ── Search & Filter ────────────────────────────────────────────────
    y := 50
    g_MainGui.Add("Text", "x8 y" (y+4) " w55 cCCCCCC", "Search:")
    searchEdit := g_MainGui.Add("Edit", "x67 y" y " w230 h25 +Background1E1E2E", g_SearchText)

    btnSearch := g_MainGui.Add("Button", "x302 y" y " w60 h25", "Search")
    btnClearS := g_MainGui.Add("Button", "x367 y" y " w50 h25", "Clear")
    btnSearch.OnEvent("Click", SearchBtn_Handler.Bind(searchEdit))
    btnClearS.OnEvent("Click", ClearSearchBtn_Handler.Bind(searchEdit))

    g_MainGui.Add("Text", "x430 y" (y+4) " w45 cCCCCCC", "Filter:")
    allTypes := ["Burn", "Brute", "Toxin", "Oxygen"]
    fx := 480
    for t in allTypes {
        isActive := false
        for ft in g_FilterTypes
            if ft = t
                isActive := true
        btnF := g_MainGui.Add("Button", "x" fx " y" y " w68 h25", t)
        if isActive
            btnF.Opt("+Background006600")
        ct := t
        btnF.OnEvent("Click", FilterBtn_Handler.Bind(ct))
        fx += 72
    }

    ; ── Book tabs ──────────────────────────────────────────────────────
    y := 86
    g_MainGui.Add("Text", "x0 y" y " w750 h2 0x10")
    y += 6

    tx := 8
    for i, book in g_RecipeBooks {
        isActive := (i = g_CurrentBookIdx)
        tabBtn := g_MainGui.Add("Button", "x" tx " y" y " h26", " " book.name " ")
        if isActive
            tabBtn.Opt("+Background004488")
        ci := i
        tabBtn.OnEvent("Click", TabBtn_Handler.Bind(ci))
        tabW := Max(60, StrLen(book.name) * 9 + 22)
        tabBtn.Move(tx, y, tabW, 26)
        tx += tabW + 4
    }
    y += 32

    g_MainGui.Add("Text", "x0 y" y " w750 h2 0x10")
    y += 8

    ; ── Recipe list ────────────────────────────────────────────────────
    currentBook      := g_RecipeBooks[g_CurrentBookIdx]
    filteredRecipes  := []

    for i, recipe in currentBook.recipes {
        if g_SearchText != "" && !InStr(recipe.name, g_SearchText, false)
            continue
        if g_FilterTypes.Length > 0 {
            matched := false
            for ft in g_FilterTypes
                if HasType(recipe, ft)
                    matched := true
            if !matched
                continue
        }
        filteredRecipes.Push({ recipe: recipe, origIdx: i })
    }

    if filteredRecipes.Length = 0 {
        g_MainGui.SetFont("s10 c666666", "Segoe UI")
        g_MainGui.Add("Text", "x20 y" y " w700", "(No recipes found — try adjusting your search or filter)")
        g_MainGui.SetFont("s10 cFFFFFF", "Segoe UI")
        y += 28
    } else {
        g_MainGui.SetFont("s10 cFFFFFF", "Segoe UI")
        for item in filteredRecipes {
            recipe  := item.recipe
            origIdx := item.origIdx
            totalU  := GetTotalUnits(recipe)
            typesD  := TypesStr(recipe.types)

            displayName := recipe.name "    " totalU "u    [" typesD "]"

            recipeBtn := g_MainGui.Add("Button", "x8 y" y " w620 h30", displayName)
            cb := g_CurrentBookIdx
            cr := origIdx
            recipeBtn.OnEvent("Click", RecipeBtn_Handler.Bind(cb, cr))

            btnView := g_MainGui.Add("Button", "x634 y" (y+2) " w52 h26", "View")
            btnEdit := g_MainGui.Add("Button", "x691 y" (y+2) " w52 h26", "Edit")
            btnView.OnEvent("Click", ExamineRecipe_Handler.Bind(cb, cr))
            btnEdit.OnEvent("Click", EditRecipe_Handler.Bind(cb, cr))

            y += 36
        }
    }

    ; ── Bottom action bar ──────────────────────────────────────────────
    y += 6
    g_MainGui.Add("Text", "x0 y" y " w750 h2 0x10")
    y += 8

    g_MainGui.SetFont("s10 cFFFFFF", "Segoe UI")
    btnRename     := g_MainGui.Add("Button", "x8   y" y " w115 h30", "Rename Book")
    btnBookDesc   := g_MainGui.Add("Button", "x130 y" y " w120 h30", "Description")
    btnExport     := g_MainGui.Add("Button", "x258 y" y " w100 h30", "Export")
    btnClear      := g_MainGui.Add("Button", "x365 y" y " w90  h30", "Clear")
    btnNewBook    := g_MainGui.Add("Button", "x462 y" y " w120 h30", "New Book")
    btnDeleteBook := g_MainGui.Add("Button", "x589 y" y " w120 h30", "Delete Book")

    btnRename.OnEvent("Click",     (*) => EditBookName())
    btnBookDesc.OnEvent("Click",   (*) => EditBookDescription())
    btnExport.OnEvent("Click",     (*) => ExportBook())
    btnClear.OnEvent("Click",      (*) => ClearBook())
    btnNewBook.OnEvent("Click",    (*) => CreateNewBook())
    btnDeleteBook.OnEvent("Click", (*) => DeleteBook())

    g_MainGui.Show("w750 h" (y + 55))
}

; ---------- Recipe Book event handlers ----------

HomeBtn_Handler(*) {
    global g_FilterTypes, g_SearchText
    g_FilterTypes := []
    g_SearchText  := ""
    ShowHome()
}

SearchBtn_Handler(editCtrl, *) {
    global g_SearchText
    g_SearchText := editCtrl.Value
    ShowRecipeBookPage()
}

ClearSearchBtn_Handler(editCtrl, *) {
    global g_SearchText
    g_SearchText := ""
    ShowRecipeBookPage()
}

FilterBtn_Handler(typeName, *) {
    global g_FilterTypes
    for i, t in g_FilterTypes {
        if t = typeName {
            g_FilterTypes.RemoveAt(i)
            ShowRecipeBookPage()
            return
        }
    }
    g_FilterTypes.Push(typeName)
    ShowRecipeBookPage()
}

TabBtn_Handler(bookIdx, *) {
    global g_CurrentBookIdx
    g_CurrentBookIdx := bookIdx
    ShowRecipeBookPage()
}

RecipeBtn_Handler(bookIdx, recipeIdx, *) {
    ; Clicking a recipe opens the examine view
    ; (automation logic to be added in a future phase)
    ExamineRecipe_Handler(bookIdx, recipeIdx)
}

ExamineRecipe_Handler(bookIdx, recipeIdx, *) {
    global g_RecipeBooks
    recipe := g_RecipeBooks[bookIdx].recipes[recipeIdx]

    examGui := Gui("+AlwaysOnTop", "Examine: " recipe.name)
    examGui.SetFont("s10", "Segoe UI")
    examGui.BackColor := "1E1E2E"

    examGui.SetFont("s15 Bold cFFFFFF", "Segoe UI")
    examGui.Add("Text", "x10 y15 w480 Center", recipe.name)

    examGui.SetFont("s10 cFFD700", "Segoe UI")
    examGui.Add("Text", "x10 y44 w480 Center", "Total: " GetTotalUnits(recipe) "u   |   Types: " TypesStr(recipe.types))

    y := 70
    if recipe.description != "" {
        examGui.SetFont("s9 cAAAAAA", "Segoe UI")
        examGui.Add("Text", "x15 y" y " w470", recipe.description)
        y += 45
    }

    examGui.Add("Text", "x0 y" y " w500 h2 0x10")
    y += 8

    examGui.SetFont("s10 Bold cFFFFFF", "Segoe UI")
    examGui.Add("Text", "x15 y" y " w190", "Ingredient")
    examGui.Add("Text", "x210 y" y " w100", "Amount")
    y += 22

    examGui.SetFont("s10 cFFFFFF", "Segoe UI")
    for ing in recipe.ingredients {
        examGui.Add("Text", "x20 y" y " w185", ing.name)
        examGui.Add("Text", "x210 y" y " w100 c00FF88", ing.amount "u")
        y += 22
    }

    y += 10
    btnClose := examGui.Add("Button", "x170 y" y " w160 h32", "Close")
    btnClose.OnEvent("Click", (*) => examGui.Destroy())

    examGui.Show("w500 h" (y + 52))
}

EditRecipe_Handler(bookIdx, recipeIdx, *) {
    global g_RecipeBooks
    recipe := g_RecipeBooks[bookIdx].recipes[recipeIdx]
    ShowIngredientEditor(recipe.name, true, bookIdx, recipeIdx)
}

; ---------- Book management ----------

EditBookName() {
    global g_RecipeBooks, g_CurrentBookIdx
    book   := g_RecipeBooks[g_CurrentBookIdx]
    result := InputBox("Enter new name for this recipe book:", "Rename Recipe Book", "w340 h130", book.name)
    if result.Result != "OK" || Trim(result.Value) = ""
        return
    g_RecipeBooks[g_CurrentBookIdx].name := Trim(result.Value)
    SaveData()
    ShowRecipeBookPage()
}

EditBookDescription() {
    global g_RecipeBooks, g_CurrentBookIdx, g_BookDescGui

    if IsObject(g_BookDescGui)
        g_BookDescGui.Destroy()

    book := g_RecipeBooks[g_CurrentBookIdx]

    g_BookDescGui := Gui("+AlwaysOnTop", "Book Description: " book.name)
    g_BookDescGui.SetFont("s10", "Segoe UI")
    g_BookDescGui.BackColor := "2A2A3E"

    g_BookDescGui.SetFont("s12 Bold cFFFFFF", "Segoe UI")
    g_BookDescGui.Add("Text", "x10 y12 w380", book.name)
    g_BookDescGui.SetFont("s9 cAAAAAA", "Segoe UI")
    g_BookDescGui.Add("Text", "x10 y35 w380", "Optional description — useful for sharing recipe books")

    g_BookDescGui.SetFont("s10 cFFFFFF", "Segoe UI")
    editCtrl := g_BookDescGui.Add("Edit", "x10 y58 w380 h140 Multi WantReturn +Background2A2A3E", book.description)

    btnSave   := g_BookDescGui.Add("Button", "x10  y208 w180 h30", "Save & Close")
    btnCancel := g_BookDescGui.Add("Button", "x200 y208 w180 h30", "Cancel")

    btnSave.OnEvent("Click",   BookDescSave_Handler.Bind(editCtrl))
    btnCancel.OnEvent("Click", (*) => g_BookDescGui.Destroy())

    g_BookDescGui.Show("w400 h260")
}

BookDescSave_Handler(editCtrl, *) {
    global g_RecipeBooks, g_CurrentBookIdx, g_BookDescGui
    g_RecipeBooks[g_CurrentBookIdx].description := editCtrl.Value
    SaveData()
    g_BookDescGui.Destroy()
    g_BookDescGui := ""
}

ExportBook() {
    global g_RecipeBooks, g_CurrentBookIdx
    book     := g_RecipeBooks[g_CurrentBookIdx]
    ; [\\/:*?"<>|] covers all characters invalid in Windows filenames.
    ; \\ in an AHK string is two literal backslashes, which the regex engine
    ; interprets as an escaped backslash — matching one literal \ character.
    safeName := RegExReplace(book.name, "[\\/:*?`"<>`|]", "_")

    savePath := FileSelect("S8", A_MyDocuments "\" safeName ".cmp", "Export Recipe Book", "ChemMasterPro Files (*.cmp)")
    if savePath = ""
        return

    content := "CHMASTERPRO_EXPORT_V1`n" EncodeData([book])
    try FileDelete(savePath)
    try {
        FileAppend(content, savePath)
        MsgBox("Recipe book exported successfully!`n`nFile: " savePath, "Export Complete", "Iconi")
    } catch as e {
        MsgBox("Failed to write export file:`n" e.Message, "Export Error", "Iconx")
    }
}

ClearBook() {
    global g_RecipeBooks, g_CurrentBookIdx
    bookName := g_RecipeBooks[g_CurrentBookIdx].name
    if MsgBox("Clear ALL recipes from '" bookName "'?`nThis cannot be undone.", "Confirm Clear", "YesNo Icon!") != "Yes"
        return
    g_RecipeBooks[g_CurrentBookIdx].recipes := []
    SaveData()
    ShowRecipeBookPage()
}

CreateNewBook() {
    global g_RecipeBooks, g_CurrentBookIdx
    result := InputBox("Enter a name for the new recipe book:", "New Recipe Book", "w340 h130")
    if result.Result != "OK" || Trim(result.Value) = ""
        return
    g_RecipeBooks.Push({ name: Trim(result.Value), description: "", recipes: [] })
    g_CurrentBookIdx := g_RecipeBooks.Length
    SaveData()
    ShowRecipeBookPage()
}

DeleteBook() {
    global g_RecipeBooks, g_CurrentBookIdx
    if g_RecipeBooks.Length <= 1 {
        MsgBox("You cannot delete your only recipe book.", "Cannot Delete", "Icon!")
        return
    }
    bookName := g_RecipeBooks[g_CurrentBookIdx].name
    if MsgBox("Delete recipe book '" bookName "' and ALL its recipes?`nThis cannot be undone.", "Confirm Delete", "YesNo Icon!") != "Yes"
        return
    g_RecipeBooks.RemoveAt(g_CurrentBookIdx)
    if g_CurrentBookIdx > g_RecipeBooks.Length
        g_CurrentBookIdx := g_RecipeBooks.Length
    SaveData()
    ShowRecipeBookPage()
}

; ======================================================================
; IMPORT
; ======================================================================

ShowImport() {
    global g_RecipeBooks

    filePath := FileSelect(1, A_MyDocuments, "Import Recipe Book", "ChemMasterPro Files (*.cmp)")
    if filePath = ""
        return

    try {
        content := FileRead(filePath)
    } catch {
        MsgBox("Could not read the selected file.", "Import Error", "Iconx")
        return
    }

    if SubStr(content, 1, 22) != "CHMASTERPRO_EXPORT_V1`n" {
        MsgBox("Invalid file format.`nThis does not appear to be a ChemMasterPro export file.", "Import Error", "Iconx")
        return
    }

    dataContent := SubStr(content, 23)
    try {
        importedBooks := DecodeData(dataContent)
    } catch as e {
        MsgBox("Error parsing file: " e.Message, "Import Error", "Iconx")
        return
    }

    if importedBooks.Length = 0 {
        MsgBox("No valid recipe books found in this file.", "Import Error", "Iconx")
        return
    }

    importedCount := 0
    skippedCount  := 0

    for book in importedBooks {
        existsIdx := 0
        for i, existing in g_RecipeBooks {
            if existing.name = book.name {
                existsIdx := i
                break
            }
        }
        if existsIdx > 0 {
            ans := MsgBox("A recipe book named '" book.name "' already exists.`nOverwrite it?", "Import Conflict", "YesNo Icon?")
            if ans = "Yes" {
                g_RecipeBooks[existsIdx] := book
                importedCount++
            } else {
                skippedCount++
            }
        } else {
            g_RecipeBooks.Push(book)
            importedCount++
        }
    }

    SaveData()
    msg := "Import complete!`n`nImported: " importedCount " book(s)"
    if skippedCount > 0
        msg .= "`nSkipped (not overwritten): " skippedCount " book(s)"
    MsgBox(msg, "Import Complete", "Iconi")
}

; ======================================================================
; CREDITS
; ======================================================================

ShowCredits() {
    credGui := Gui("+AlwaysOnTop", "Credits")
    credGui.SetFont("s10", "Segoe UI")
    credGui.BackColor := "1E1E2E"

    credGui.SetFont("s18 Bold cFFFFFF", "Segoe UI")
    credGui.Add("Text", "x0 y22 w400 Center", "ChemMasterPro")

    credGui.SetFont("s10 c888888", "Segoe UI")
    credGui.Add("Text", "x0 y55 w400 Center", "SS14 Chemistry Automation Tool")

    credGui.SetFont("s11 cFFD700", "Segoe UI")
    credGui.Add("Text", "x0 y92 w400 Center", "-- Created by --")

    credGui.SetFont("s16 Bold cFFFFFF", "Segoe UI")
    credGui.Add("Text", "x0 y116 w400 Center", "Shangeko")

    credGui.SetFont("s9 c555555", "Segoe UI")
    credGui.Add("Text", "x0 y152 w400 Center", "Thank you for using ChemMasterPro!")

    btnClose := credGui.Add("Button", "x140 y185 w120 h32", "Close")
    btnClose.OnEvent("Click", (*) => credGui.Destroy())

    credGui.Show("w400 h245")
}

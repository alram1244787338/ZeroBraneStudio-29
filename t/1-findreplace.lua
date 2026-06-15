local findReplace = ide.findReplace

local editor = NewFile()
ok(editor, "Open New file.")

local search = "123"
local replace = "4"
editor:AppendText(search..search.."\n"..search..search)

ide.frame:ProcessEvent(wx.wxCommandEvent(wx.wxEVT_COMMAND_MENU_SELECTED, ID.FIND))
ok(findReplace.panel, "Open Find/Replace panel.")

findReplace:SetFind(search)
ok(findReplace:HasText(), "Update text to search.")

findReplace:Find()
ok(editor:GetSelectionStart() ~= editor:GetSelectionEnd(), "Find text with Find Next.")

local selend = editor:GetSelectionEnd()
findReplace:Find()
is(editor:GetSelectionStart(), selend, "Find Next doesn't skip consecutive matches.")

editor:GotoPos(0) -- reset current selection
local findnext = wx.wxUpdateUIEvent(ID.FINDNEXT)
ide.frame:ProcessEvent(findnext)
ok(findnext:GetEnabled(), "Quick find is enabled without current selection.")

ide.frame:ProcessEvent(wx.wxCommandEvent(wx.wxEVT_COMMAND_MENU_SELECTED, ID.FINDNEXT))
is(editor:GetSelectionEnd(), selend, "Quick Find works based on previous search.")

ide.frame:ProcessEvent(wx.wxCommandEvent(wx.wxEVT_COMMAND_MENU_SELECTED, ID.FINDNEXT))
is(editor:GetSelectionStart(), selend, "Quick Find finds next match.")

-- check that text in "find" control is checked against selection with replacing
findReplace:SetFind("something else")
findReplace:SetReplace(replace)
findReplace.foundString = true
findReplace:Replace()
is(select(2, editor:GetText():gsub(search, search)), 4, "Replace doesn't replace selection that doesn't match 'find' text.")

-- restore position and selection
editor:GotoPos(4) -- reset current selection
findReplace:SetFind(search)
findReplace:Find()

-- replace the text once
findReplace:Replace()
local _, replacements = editor:GetText():gsub(replace, replace)
is(replacements, 1, "Replace replaces once.")

-- replace the current text and to the end of file
editor:GotoPos(3)
findReplace:GetFlags().Wrap = false
findReplace:Replace(true)
local _, replacements = editor:GetText():gsub(replace, replace)
is(replacements, 3, "Replace All without wrapping replaces to the end of file.")

local expected = search..replace.."\n"..replace..replace
is(editor:GetText(), expected, "Replace All with Wrap Around result is as expected.")

-- start after the match to test wrapping
editor:AppendText("\n"..search..search)
editor:GotoPos(3)
findReplace:GetFlags().Wrap = true
findReplace:Replace(true)
ok(not editor:GetText():find(search), "Replace All with Wrap Around replaces everything.")

local expected = replace..replace.."\n"..replace..replace.."\n"..replace..replace
is(editor:GetText(), expected, "Replace All without Wrap Around result is as expected.")

-- check that the replacement only happens in the matched text in preview
editor:SetText("1: 123")
findReplace:SetFind("1")
findReplace:SetReplace("9")
findReplace:Replace(true, editor)
ok(editor:GetText():find("923") ~= nil, "Replace in preview replaces matched text.")
ok(editor:GetText():find("^1:") ~= nil, "Replace in preview doesn't replace line numbers.")

editor:SetText("pos pos pos pos")
findReplace:SetFind("pos")
findReplace:SetReplace("POS")
findReplace.backfocus = { spos = 3, epos = 11 }
findReplace.inselection = true
findReplace:Replace(true)
findReplace.inselection = false
is(editor:GetText(), "pos POS POS pos", "Replace in selection only replaces inside selection.")

editor:SetText("")
editor:AppendText([[
t/1-findreplace.lua
99999: some text
]])
editor.searchpreview = true
editor.replace = true
local FILE_MARKER = ide:GetMarker("searchmatchfile")
editor:MarkerAdd(0, FILE_MARKER)
ide:GetDocument(editor):Save()
is(editor:GetText():match("Updated %d"), "Updated 0", "Replace fails on invalid line numbers.")

-- saving the find-in-files preview back to the source files
-- builds a preview buffer the same way the search results are laid out:
-- a file name line (with the file marker), the matching/context lines, and
-- a blank line separating each file's block.
local function buildPreview(ed, blocks)
  ed:SetReadOnly(false)
  ed:SetText("")
  for _, b in ipairs(blocks) do
    local markerline = ed:GetLineCount()-1 -- the line the file name goes on
    ed:AppendText(b.file.."\n")
    ed:MarkerAdd(markerline, FILE_MARKER)
    for _, l in ipairs(b.lines) do
      ed:AppendText(("%5d"):format(l[1])..(l[2] == ":" and ": " or "  ")..l[3].."\n")
    end
    ed:AppendText("\n") -- blank line separates file blocks (as in real results)
  end
  ed.searchpreview = true
  ed.replace = true
end
local function findText(ed, s) return ed:GetText():find(s, 1, true) ~= nil end

local f1, f2 = "t/zbs-fr-1.txt", "t/zbs-fr-2.txt"

-- 1) a normal batch replace updates every file and reports the totals
FileWrite(f1, "keep1\nOLD\nkeep2\n")
FileWrite(f2, "head\nOLD\ntail\n")
local prev = NewFile()
buildPreview(prev, {
    {file = f1, lines = {{1," ","keep1"},{2,":","NEW"},{3," ","keep2"}}},
    {file = f2, lines = {{1," ","head"},{2,":","NEW"},{3," ","tail"}}},
  })
ide:GetDocument(prev):Save()
is(FileRead(f1), "keep1\nNEW\nkeep2\n", "Batch replace updates the first file.")
is(FileRead(f2), "head\nNEW\ntail\n", "Batch replace updates the second file.")
ok(findText(prev, "Updated 2 lines in 2 files."), "Batch replace reports the totals.")
ide:GetDocument(prev):SetModified(false)
ClosePage()

-- 2) a mismatch in one file must not affect or miscount the others
FileWrite(f1, "keep1\nOLD\nkeep2\n")
FileWrite(f2, "head\nOLD\nCHANGED\n") -- 3rd line no longer matches the preview context
prev = NewFile()
buildPreview(prev, {
    {file = f1, lines = {{1," ","keep1"},{2,":","NEW"},{3," ","keep2"}}},
    {file = f2, lines = {{1," ","head"},{2,":","NEW"},{3," ","tail"}}},
  })
ide:GetDocument(prev):Save()
is(FileRead(f1), "keep1\nNEW\nkeep2\n", "Good file is updated when another file mismatches.")
is(FileRead(f2), "head\nOLD\nCHANGED\n", "Mismatching file is left completely untouched.")
ok(findText(prev, "Updated 1 line in 1 file."), "Partial changes in a mismatching file are not counted.")
ok(findText(prev, "Skipped 1 file."), "Skipped files are counted in the summary.")
ok(findText(prev, f2..": skipped (content changed at line 3)"), "Mismatch is reported per file with a reason.")
ide:GetDocument(prev):SetModified(false)
ClosePage()

-- 3) deleted and binary files are skipped while a good file still updates
FileWrite(f1, "keep1\nOLD\nkeep2\n")
local fbin, fgone = "t/zbs-fr-bin.txt", "t/zbs-fr-gone.txt"
FileWrite(fbin, "bin\0ary\nOLD\ntail\n") -- contains a NUL byte -> treated as binary
FileRemove(fgone) -- make sure this one does not exist
prev = NewFile()
buildPreview(prev, {
    {file = f1, lines = {{1," ","keep1"},{2,":","NEW"},{3," ","keep2"}}},
    {file = fbin, lines = {{2,":","NEW"}}},
    {file = fgone, lines = {{1,":","NEW"}}},
  })
ide:GetDocument(prev):Save()
is(FileRead(f1), "keep1\nNEW\nkeep2\n", "Good file updates despite problem files in the batch.")
ok(findText(prev, "Updated 1 line in 1 file."), "Only the good file is counted as updated.")
ok(findText(prev, "Skipped 2 files."), "Both problem files are counted as skipped.")
ok(findText(prev, fbin..": skipped (binary"), "Binary/non-text file is reported as skipped.")
ok(findText(prev, fgone..": "), "Missing file is reported.")
ide:GetDocument(prev):SetModified(false)
ClosePage()

FileRemove(f1)
FileRemove(f2)
FileRemove(fbin)


findReplace:SetFind("something")
findReplace:Show() -- set focus on the find
if ide.osname == 'Windows' then
  ide.frame:ProcessEvent(wx.wxCommandEvent(wx.wxEVT_COMMAND_MENU_SELECTED, ID.CUT))
  ok(findReplace:GetFind() == nil, "`Cut` command cuts content of the `Find` control in the search panel.")
end

-- cleanup
findReplace:Hide()
ide:GetDocument(editor):SetModified(false)
ClosePage()

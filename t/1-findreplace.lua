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

-- test: successful batch replace across multiple files
local tmpfile1 = "t/tmp_test1.lua"
local tmpfile2 = "t/tmp_test2.lua"
FileWrite(tmpfile1, "hello world\nfoo bar\nbaz qux\n")
FileWrite(tmpfile2, "hello there\nfoo baz\n")

editor:SetText("")
editor:AppendText(tmpfile1.."\n")
editor:AppendText("    1: hello replaced\n")
editor:AppendText("    2  foo bar\n")
editor:AppendText(tmpfile2.."\n")
editor:AppendText("    1: hello replaced\n")
editor.searchpreview = true
editor.replace = true
editor:MarkerAdd(0, FILE_MARKER)
editor:MarkerAdd(3, FILE_MARKER)
ide:GetDocument(editor):Save()

local result1 = FileRead(tmpfile1)
local result2 = FileRead(tmpfile2)
is(result1, "hello replaced\nfoo bar\nbaz qux\n", "Batch replace updates first file correctly.")
is(result2, "hello replaced\nfoo baz\n", "Batch replace updates second file correctly.")
ok(editor:GetText():match("Updated 2 lines in 2 files"), "Batch replace reports correct summary.")

-- test: single file mismatch doesn't affect other files
FileWrite(tmpfile1, "hello world\nfoo bar\nbaz qux\n")
FileWrite(tmpfile2, "hello there\nfoo baz\n")

editor:SetText("")
editor:AppendText(tmpfile1.."\n")
editor:AppendText("    1: hello replaced\n")
editor:AppendText("    2  WRONG CONTEXT\n") -- mismatch on line 2
editor:AppendText(tmpfile2.."\n")
editor:AppendText("    1: hello replaced\n")
editor.searchpreview = true
editor.replace = true
editor:MarkerAdd(0, FILE_MARKER)
editor:MarkerAdd(3, FILE_MARKER)
ide:GetDocument(editor):Save()

result1 = FileRead(tmpfile1)
result2 = FileRead(tmpfile2)
is(result1, "hello world\nfoo bar\nbaz qux\n", "File with mismatch is not modified.")
is(result2, "hello replaced\nfoo baz\n", "Other file is still updated despite mismatch in first file.")
ok(editor:GetText():match("Updated 1 line in 1 file"), "Summary shows only successful updates.")
ok(editor:GetText():match("Skipped 1 file"), "Summary shows skipped file.")
ok(editor:GetText():match(tmpfile1..": skipped %(context mismatch"), "Report shows mismatch details for first file.")

-- test: deleted file is reported as failed
FileWrite(tmpfile1, "hello world\nfoo bar\n")
FileRemove(tmpfile2)

editor:SetText("")
editor:AppendText(tmpfile1.."\n")
editor:AppendText("    1: hello replaced\n")
editor:AppendText(tmpfile2.."\n")
editor:AppendText("    1: hello replaced\n")
editor.searchpreview = true
editor.replace = true
editor:MarkerAdd(0, FILE_MARKER)
editor:MarkerAdd(2, FILE_MARKER)
ide:GetDocument(editor):Save()

result1 = FileRead(tmpfile1)
is(result1, "hello replaced\nfoo bar\n", "Existing file is updated when another file is deleted.")
ok(editor:GetText():match("Updated 1 line in 1 file"), "Summary shows successful update.")
ok(editor:GetText():match("Failed 1 file"), "Summary shows failed file.")
ok(editor:GetText():match(tmpfile2..": failed %(file not found%)"), "Report shows deleted file details.")

-- test: modified file (mod time change) is skipped
FileWrite(tmpfile1, "hello world\nfoo bar\n")
FileWrite(tmpfile2, "hello there\nfoo baz\n")

editor:SetText("")
editor:AppendText(tmpfile1.."\n")
editor:AppendText("    1: hello replaced\n")
editor.fileMeta = {[tmpfile1] = {modTime = GetFileModTime(tmpfile1)}}
editor:AppendText(tmpfile2.."\n")
editor:AppendText("    1: hello replaced\n")
editor.searchpreview = true
editor.replace = true
editor:MarkerAdd(0, FILE_MARKER)
editor:MarkerAdd(2, FILE_MARKER)

-- modify file1 after capturing mod time
os.execute("sleep 1") -- ensure time difference
FileWrite(tmpfile1, "hello world\nfoo bar\nmodified line\n")

ide:GetDocument(editor):Save()

result1 = FileRead(tmpfile1)
result2 = FileRead(tmpfile2)
is(result1, "hello world\nfoo bar\nmodified line\n", "Modified file is not overwritten.")
is(result2, "hello replaced\nfoo baz\n", "Unmodified file is still updated.")
ok(editor:GetText():match("Updated 1 line in 1 file"), "Summary shows only unmodified file.")
ok(editor:GetText():match("Skipped 1 file"), "Summary shows skipped modified file.")
ok(editor:GetText():match(tmpfile1..": skipped %(file was modified"), "Report shows modification details.")

-- cleanup
FileRemove(tmpfile1)
FileRemove(tmpfile2)

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

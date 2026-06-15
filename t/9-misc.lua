local i18n = ide:GetFileList('cfg/i18n/', true, '*.lua')
is(#i18n, 12, "Language files are present in i18n directory.")
for _, ln in ipairs(i18n) do
  local func = loadfile(ln)
  ok(type(func) == 'function' and func() ~= nil, ("Loaded '%s' language file."):format(ln))
end

local ints = ide:GetFileList('interpreters/', true)
for _, i in ipairs(ints) do
  ok(type(loadfile(i)) == 'function', ("Loaded '%s' interpreter file."):format(i))
end

local fixed, invalid = FixUTF8("+\128\129\130+\194\127+", "+")
is(fixed, "++++++\127+", "Invalid UTF8 is fixed (1/2).")
is(#invalid, 4, "Invalid UTF8 is fixed (2/2).")

local UTF8s = {
  "ABCDE", -- 1 byte codes
  "\194\160\194\161\194\162\194\163\194\164", -- 2 byte codes
  "\225\160\160\225\161\161\225\162\162\225\163\163\225\164\164", -- 3 byte codes
}

for n, code in ipairs(UTF8s) do
  is(FixUTF8(code), code, ("Valid UTF8 code is left unmodified (%d/%d)."):format(n, #UTF8s))
end

local function copyToClipboard(text, format)
  local tdo = wx.wxTextDataObject()
  if format == wx.wxDF_TEXT then
    tdo:SetData(wx.wxDataFormat(format), text)
  else
    tdo:SetText(text)
  end

  local clip = wx.wxClipboard.Get()
  clip:Open()
  clip:SetData(tdo)
  clip:Close()
end

local editor = NewFile()

-- copying valid UTF8
local valid = "ás grande"
copyToClipboard(valid)
editor:PasteDyn()
is(editor:GetTextDyn(), valid, "Valid UTF-8 string is pasted from the clipboard.")

if ide.wxver >= "3.1" then
  -- copying invalid UTF8
  local invalid = "-- \193"
  copyToClipboard(invalid, wx.wxDF_TEXT)
  editor:SetTextDyn(invalid)
  ok(#editor:GetTextDyn() == #invalid, "Length of stored string is the same as the invalid UTF-8 string.")

  local valid = "ásg"
  ok(#editor:GetTextDyn() == #valid, "Length of copied content is the same as the valid UTF-8 string.")
  editor:SetSelectionStart(0)
  editor:SetSelectionEnd(#invalid)
  editor:CopyDyn() -- populate the buffer with the "invalid" copy
  editor:SetSelectionEnd(0)
  editor:PasteDyn()
  is(editor:GetTextDyn(), invalid..invalid, "Invalid UTF-8 string is copied and pasted.")
end

-- copying valid when the buffer is for invalid of the same length
copyToClipboard(valid)
editor:SetText("")
editor:PasteDyn()
is(editor:GetTextDyn(), valid, "Valid UTF-8 string is pasted from the clipboard after coping invalid UTF-8 string.")

for _, tst in ipairs({
  "_ = .1 + 1. + 1.1 + 0xa",
  "_ = 1e1 + 0xa.ap1",
  "_ = 0xabcULL + 0x1LL + 1LL + 1ULL",
  "_ = .1e1i + 0x1.1p1i + 0xa.ap1i",
}) do
  ok(AnalyzeString(tst) ~= nil,
    ("Numeric expression '%s' can be checked with static analysis."):format(tst))

  editor:SetText(tst)
  editor:ResetTokenList()
  while editor:IndicateSymbols() do end
  local defonly = true
  for _, token in ipairs(ide:GetEditor():GetTokenList()) do
    if token.name ~= '_' then defonly = false end
  end
  ok(defonly == true, ("Numeric expression '%s' can be checked with inline parser."):format(tst))
end

ide:GetDocument(editor):SetModified(false)
ClosePage()

local at = ide:GetAccelerators()
ok(next(at) ~= nil, "One or more accelerator is set in the accelerator table.")
for id in pairs(at) do ide:SetAccelerator(id, nil) end
at = ide:GetAccelerators()
ok(next(at) == nil, "No accelerators are present after removing all of them.")

ide:SetHotKey(ID.STARTDEBUG, "F1")
is(ide:FindMenuItem(ID.STARTDEBUG):GetItemLabel():match("\t(.*)"), "F1", "`SetHotKey` sets the requested hotkey.")
ok(ide:FindMenuItem(ID.ABOUT):GetItemLabel():match("\t(.*)") == nil, "`SetHotKey` removes conflicted hotkey (1/2).")

local keyid, keysc = ide:GetHotKey(ID.STARTDEBUG)
is(keysc, "F1", "`GetHotKey` returns hotkey assigned with SetHotKey using id lookup.")
is(ide:GetHotKey("F1"), ID.STARTDEBUG, "`GetHotKey` returns hotkey assigned with SetHotKey using shortcut lookup.")

ide:SetHotKey(ID.STARTDEBUG)
ok(ide:GetHotKey("F1") == nil, "Setting hotkey to `nil` properly removes it (1/2).")
ok(ide:GetHotKey(ID.STARTDEBUG) == nil, "Setting hotkey to `nil` properly removes it (1/2).")

ok(ide:GetHotKey("F13") == nil, "`GetHotKey` returns nothing for nonexisting shortcut.")
ok(ide:GetHotKey(1) == nil, "`GetHotKey` returns nothing for nonexisting id.")
ok(ide:GetHotKey() == nil, "`GetHotKey` returns nothing when no parameters are passed.")

ide:SetHotKey(ID.STARTDEBUG, "Ctrl+N") -- this should resolve conflict with `Ctrl-N`
ok(ide:FindMenuItem(ID.NEW):GetItemLabel():match("\t(.*)") == nil, "`SetHotKey` removes conflicted hotkey (2/2).")

local capname, cwd = [[T\TesT.LUA]], wx.wxGetCwd()
if ide.osname == "Windows" then
  -- relative path
  is(FileGetLongPath(capname), capname:lower(), "`GetLongFilePath` returns properly formatted path on Windows (1/3).")
  -- absolute path with volume
  is(FileGetLongPath(MergeFullPath(cwd,capname)), MergeFullPath(cwd,capname:lower()), "`GetLongFilePath` returns properly formatted path on Windows (2/3).")
  -- absolute path with no volume
  is(FileGetLongPath(MergeFullPath(cwd,capname):gsub("^.:","")), MergeFullPath(cwd,capname:lower()):gsub("^.:",""), "`GetLongFilePath` returns properly formatted path on Windows (3/3).")
end

local tree = ide:GetProjectTree()
ok(pcall(function() tree:SetStartFile() end) == true, "Unsetting start file without project doesn't fail.")

ide:SetProject("t")
is(ide:GetProject("t"):gsub("[/\\]$",""), MergeFullPath(cwd,"t"), "Project is set to the expected path.")
local itemid = tree:FindItem("test.lua")
ok(itemid and itemid:IsOk() and tree:IsFileKnown(itemid), ".lua files have 'known' type.")


local spec = ide:FindSpec("py", "#!/bin/env ruby")
is(spec.lexer, "lexlpeg.python", "Shebang detection is not triggered for known extensions.")

spec = ide:FindSpec("", "#!/bin/env ruby")
is(spec.lexer, "lexlpeg.ruby", "Shebang detection sets correct lexer.")
is(#spec.exts, 0, "Shebang detection doesn't add extensions.")

local p = ide:GetProject()
ide.filetree.settings.mapped[p] = {}
local res = tree:MapDirectory("foo")
is(#ide.filetree.settings.mapped[p], 0, "MapDirectory doesn't add non-existing directory.")
ok(res == nil, "MapDirectory reports failure to add directory.")
local sep = GetPathSeparator()
local dir = "../src"
res = tree:MapDirectory(dir)
is(#ide.filetree.settings.mapped[p], 1, "MapDirectory adds a new directory to the list.")
ok(res == true, "MapDirectory reports success to add directory.")
tree:MapDirectory(dir..sep)
is(#ide.filetree.settings.mapped[p], 1, "MapDirectory skips adding the same directory.")
tree:UnmapDirectory(dir..sep)
ok(not ide.filetree.settings.mapped[p], "UnmapDirectory removes directory from the list.")

ok(tree:SetStartFile("test.lua") ~= nil, "SetStartFile sets start file.")
is(tree:GetStartFile(), "test.lua", "GetStartFile returns expected value.")
tree:SetStartFile()
ok(tree:GetStartFile() == nil, "GetStartFile returns `nil` after unsetting start file.")

is(ide:IsValidProperty({}, "nonexisting"), false, "`IsValidProperty` returns `false ` for non-existing properties.")

-- create t/foo.lua with foo=1 value
local configfile = MergeFullPath(wx.wxStandardPaths.Get():GetTempDir(), "config.lua")
FileWrite(configfile, "foo=1")
local cmt = getmetatable(ide.config.styles)
ide:AddConfig("test", configfile)
FileRemove(configfile)
-- confirm ide.config.foo == 1
is(ide.config.foo, 1, "AddConfig sets specified config file.")
ide:RemoveConfig("test")
ok(ide.config.foo == nil, "RemoveConfig unsets specified config file.")

-- check that ide.config.styles still has metatable
ok(getmetatable(ide.config.styles) == cmt, "Removing config file restores original styles.")

-- ============================================================
-- Regression tests for project tree refresh
-- ============================================================
-- Project is already set to "t" from earlier tests
local sep = GetPathSeparator()

-- helper: refresh the tree root (same as manual refresh)
local function refreshTree()
  tree:RefreshChildren()
end

-- helper: check if a name exists as a child of the given tree item
local function treeHasChild(parent, name)
  local item, cookie = tree:GetFirstChild(parent)
  while item:IsOk() do
    if tree:GetItemText(item) == name then return true end
    item, cookie = tree:GetNextChild(parent, cookie)
  end
  return false
end

local root = tree:GetRootItem()

-- 1. File creation is reflected after refresh
local testfilepath = "t" .. sep .. "_refresh_test.lua"
FileWrite(testfilepath, "-- test")
refreshTree()
ok(tree:FindItem(testfilepath) ~= nil, "Tree shows newly created file after refresh.")
ok(treeHasChild(root, "_refresh_test.lua"), "New file appears as child of root after refresh.")

-- 2. File deletion is reflected after refresh
wx.wxRemoveFile(MergeFullPath(wx.wxGetCwd(), testfilepath))
refreshTree()
ok(tree:FindItem(testfilepath) == nil, "Tree removes deleted file after refresh.")

-- 3. File rename is reflected after refresh (old gone, new present)
local srcfile = "t" .. sep .. "_rsrc.lua"
local dstfile = "t" .. sep .. "_rdst.lua"
FileWrite(srcfile, "-- rename me")
refreshTree()
ok(tree:FindItem(srcfile) ~= nil, "Source file is in tree before rename.")
wx.wxRenameFile(MergeFullPath(wx.wxGetCwd(), srcfile), MergeFullPath(wx.wxGetCwd(), dstfile))
refreshTree()
ok(tree:FindItem(srcfile) == nil, "Source file removed from tree after rename.")
ok(tree:FindItem(dstfile) ~= nil, "Destination file appears in tree after rename.")
wx.wxRemoveFile(MergeFullPath(wx.wxGetCwd(), dstfile))

-- 4. Directory rename is reflected after refresh
local srcdir = "t" .. sep .. "_dirsrc"
local dstdir = "t" .. sep .. "_dirdst"
wx.wxMkdir(MergeFullPath(wx.wxGetCwd(), srcdir))
refreshTree()
local srcitem = tree:FindItem(srcdir)
ok(srcitem ~= nil, "Source directory appears in tree before rename.")
wx.wxRenameFile(MergeFullPath(wx.wxGetCwd(), srcdir), MergeFullPath(wx.wxGetCwd(), dstdir))
refreshTree()
ok(tree:FindItem(srcdir) == nil, "Source directory removed from tree after rename.")
ok(tree:FindItem(dstdir) ~= nil, "Destination directory appears in tree after rename.")
wx.wxRmdir(MergeFullPath(wx.wxGetCwd(), dstdir))

-- 5. Directory deletion is reflected after refresh
local testdir = "t" .. sep .. "_rmdir"
wx.wxMkdir(MergeFullPath(wx.wxGetCwd(), testdir))
refreshTree()
ok(tree:FindItem(testdir) ~= nil, "Directory appears in tree after creation.")
wx.wxRmdir(MergeFullPath(wx.wxGetCwd(), testdir))
refreshTree()
ok(tree:FindItem(testdir) == nil, "Directory removed from tree after deletion.")

-- 6. Files inside a renamed directory are accessible under new path
local dirbefore = "t" .. sep .. "_parentold"
local dirafter  = "t" .. sep .. "_parentnew"
wx.wxMkdir(MergeFullPath(wx.wxGetCwd(), dirbefore))
FileWrite(dirbefore .. sep .. "child.lua", "-- child")
refreshTree()
local parentitem = tree:FindItem(dirbefore)
ok(parentitem ~= nil, "Parent directory found before rename.")
tree:Expand(parentitem)
refreshTree() -- also refreshes the expanded child
ok(tree:FindItem(dirbefore .. sep .. "child.lua") ~= nil,
  "Child file visible inside parent before rename.")
wx.wxRenameFile(MergeFullPath(wx.wxGetCwd(), dirbefore), MergeFullPath(wx.wxGetCwd(), dirafter))
refreshTree()
ok(tree:FindItem(dirbefore) == nil, "Old parent directory gone after rename.")
local newchild = tree:FindItem(dirafter .. sep .. "child.lua")
ok(newchild ~= nil, "Child file accessible under renamed parent path.")
wx.wxRemoveFile(MergeFullPath(wx.wxGetCwd(), dirafter .. sep .. "child.lua"))
wx.wxRmdir(MergeFullPath(wx.wxGetCwd(), dirafter))

-- 7. Mapped directory: external file changes reflected after refresh
local mapdir = MergeFullPath(wx.wxStandardPaths.Get():GetTempDir(), "_zbtest_mapdir")
wx.wxMkdir(mapdir)
FileWrite(mapdir .. sep .. "mapped.lua", "-- mapped")
tree:MapDirectory(mapdir)
refreshTree()
ok(treeHasChild(root, mapdir:gsub(sep .. "$", "")), "Mapped directory appears in tree root.")
-- add a file to the mapped directory externally
FileWrite(mapdir .. sep .. "extra.lua", "-- extra")
refreshTree()
ok(tree:FindItem(mapdir .. sep .. "extra.lua") ~= nil,
  "File added to mapped directory externally appears after refresh.")
-- remove a file from the mapped directory externally
wx.wxRemoveFile(mapdir .. sep .. "extra.lua")
refreshTree()
ok(tree:FindItem(mapdir .. sep .. "extra.lua") == nil,
  "File removed from mapped directory externally disappears after refresh.")
tree:UnmapDirectory(mapdir)
wx.wxRemoveFile(mapdir .. sep .. "mapped.lua")
wx.wxRmdir(mapdir)

-- 8. Hidden extension rule is preserved after refresh
ide.filetree.settings.extensionignore["tmp"] = true
FileWrite("t" .. sep .. "_hidden.tmp", "temp")
FileWrite("t" .. sep .. "_visible.lua", "-- visible")
refreshTree()
ok(tree:FindItem("t" .. sep .. "_hidden.tmp") == nil,
  "Files with hidden extension are not shown after refresh.")
ok(tree:FindItem("t" .. sep .. "_visible.lua") ~= nil,
  "Files with non-hidden extension are shown after refresh.")
ide.filetree.settings.extensionignore["tmp"] = nil
refreshTree()
ok(tree:FindItem("t" .. sep .. "_hidden.tmp") ~= nil,
  "Previously hidden files appear after un-hiding extension and refreshing.")
wx.wxRemoveFile(MergeFullPath(wx.wxGetCwd(), "t" .. sep .. "_hidden.tmp"))
wx.wxRemoveFile(MergeFullPath(wx.wxGetCwd(), "t" .. sep .. "_visible.lua"))

-- 9. Start file icon is updated after rename
FileWrite("t" .. sep .. "_startfile.lua", "-- start")
refreshTree()
tree:SetStartFile("t" .. sep .. "_startfile.lua")
local sfitem = tree:FindItem("t" .. sep .. "_startfile.lua")
ok(sfitem ~= nil and tree:IsFileStart(sfitem),
  "Start file has correct start-file icon after setting.")
tree:SetStartFile() -- unset
wx.wxRemoveFile(MergeFullPath(wx.wxGetCwd(), "t" .. sep .. "_startfile.lua"))

-- 10. Collapse and re-expand refreshes directory content
local cedir = "t" .. sep .. "_collapse_test"
wx.wxMkdir(MergeFullPath(wx.wxGetCwd(), cedir))
refreshTree()
local ceitem = tree:FindItem(cedir)
ok(ceitem ~= nil, "Test directory for collapse test is in tree.")
tree:Expand(ceitem)
refreshTree()
-- add a file while the directory is collapsed
tree:Collapse(ceitem)
FileWrite(cedir .. sep .. "late.lua", "-- late")
-- re-expand: should pick up the new file via treeAddDir in EXPANDING handler
tree:Expand(ceitem)
ok(tree:FindItem(cedir .. sep .. "late.lua") ~= nil,
  "File added while directory was collapsed appears after re-expand.")
wx.wxRemoveFile(MergeFullPath(wx.wxGetCwd(), cedir .. sep .. "late.lua"))
wx.wxRmdir(MergeFullPath(wx.wxGetCwd(), cedir))

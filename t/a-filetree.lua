-- Copyright 2011-18 ZeroBrane LLC; see LICENSE in the root folder
-- Regression tests for the project tree auto-refresh chain:
-- directory rename, file deletion, mapped directory changes, and the
-- expand/collapse refresh, while preserving hidden-extension and
-- start-file display rules.

local tree = ide:GetProjectTree()
local sep = GetPathSeparator()
local origproject = ide:GetProject()

local tmpdir = wx.wxStandardPaths.Get():GetTempDir()
local proj = MergeFullPath(tmpdir, "zbsproj-filetree")
local maproot = MergeFullPath(tmpdir, "zbsmap-filetree")

local function mkdir(path)
  return wx.wxFileName.DirName(path):Mkdir(tonumber("755", 8), wx.wxPATH_MKDIR_FULL)
end

-- remove a directory tree (files first, then directories deepest-first)
local function rmrf(path)
  if not wx.wxDirExists(path) then return end
  for _, f in ipairs(ide:GetFileList(path, true, "*")) do FileRemove(f) end
  local dirs = {path}
  ide:GetFileList(path, true, "*", {ondirectory = function(d)
        table.insert(dirs, d); return true end})
  table.sort(dirs, function(a, b) return #a > #b end)
  for _, d in ipairs(dirs) do wx.wxRmdir(d) end
end

-- find a direct child of `parent` whose label matches `text`
local function childByText(parent, text)
  local item, cookie = tree:GetFirstChild(parent)
  while item:IsOk() do
    if tree:GetItemText(item) == text then return item end
    item, cookie = tree:GetNextChild(parent, cookie)
  end
end

-- does an item exist (and is valid) for the given project-relative path
local function present(relpath)
  local id = tree:FindItem(relpath)
  return id and id:IsOk() and true or false
end

-- start with a clean slate in case a previous run left files behind
rmrf(proj)
rmrf(maproot)

-- build the initial structure:
--   proj/b.txt
--   proj/keep.lua
--   proj/sub/a.lua
mkdir(proj)
mkdir(MergeFullPath(proj, "sub"))
ok(FileWrite(MergeFullPath(proj, "b.txt"), ""), "Test fixture: b.txt created.")
ok(FileWrite(MergeFullPath(proj, "keep.lua"), ""), "Test fixture: keep.lua created.")
ok(FileWrite(MergeFullPath(proj, "sub"..sep.."a.lua"), ""), "Test fixture: sub/a.lua created.")

ide:SetProject(proj)
is(ide:GetProject():gsub("[/\\]$", ""), proj, "Project is set to the temporary directory.")

-- initial tree state
ok(present("b.txt"), "File node 'b.txt' is present initially.")
ok(present("keep.lua"), "File node 'keep.lua' is present initially.")
local subid = tree:FindItem("sub")
ok(subid and subid:IsOk() and tree:IsDirectory(subid), "Directory node 'sub' is present initially.")
ok(present("sub"..sep.."a.lua"), "Nested file 'sub/a.lua' is present initially.")

-- 1) file deletion: the stale node must be dropped after a refresh
ok(FileRemove(MergeFullPath(proj, "b.txt")), "File 'b.txt' is removed from disk.")
tree:RefreshChildren()
ok(not present("b.txt"), "Deleted file 'b.txt' is no longer in the tree after refresh.")
ok(present("keep.lua"), "Unrelated file 'keep.lua' survives the refresh.")

-- 2) directory rename: old node removed, new node added with directory type,
--    and nested content reachable under the new name
ok(FileRename(MergeFullPath(proj, "sub"), MergeFullPath(proj, "sub2")),
  "Directory 'sub' is renamed to 'sub2' on disk.")
tree:RefreshChildren()
ok(not present("sub"), "Old directory node 'sub' is gone after rename.")
local sub2id = tree:FindItem("sub2")
ok(sub2id and sub2id:IsOk() and tree:IsDirectory(sub2id), "New directory node 'sub2' exists with directory type.")
ok(present("sub2"..sep.."a.lua"), "Nested file is reachable under the renamed directory.")

-- 3) expand/collapse refresh: a file added while collapsed shows up on expand
tree:Collapse(sub2id)
ok(FileWrite(MergeFullPath(proj, "sub2"..sep.."c.lua"), ""), "File 'sub2/c.lua' created while collapsed.")
tree:Expand(sub2id)
ok(childByText(sub2id, "c.lua"), "File added while collapsed appears after expand.")

-- 4a) hidden-extension rule still applies across a refresh
ok(FileWrite(MergeFullPath(proj, "hide.bak"), ""), "File 'hide.bak' created.")
tree:RefreshChildren()
ok(present("hide.bak"), "File 'hide.bak' is visible before hiding its extension.")
ide.filetree.settings.extensionignore["bak"] = true
tree:RefreshChildren()
ok(not present("hide.bak"), "File with hidden extension is not shown after refresh.")
ide.filetree.settings.extensionignore["bak"] = nil
tree:RefreshChildren()
ok(present("hide.bak"), "File reappears once the extension is shown again.")

-- 4b) start-file icon survives a refresh
ok(tree:SetStartFile("keep.lua") ~= nil, "Start file is set to 'keep.lua'.")
tree:RefreshChildren()
local keepid = tree:FindItem("keep.lua")
ok(keepid and keepid:IsOk() and tree:IsFileStart(keepid),
  "Start-file icon is preserved on 'keep.lua' after refresh.")
tree:SetStartFile()
tree:RefreshChildren()
keepid = tree:FindItem("keep.lua")
ok(keepid and keepid:IsOk() and not tree:IsFileStart(keepid),
  "Start-file icon is cleared after unsetting the start file.")

-- 5) mapped directory: node appears, its content refreshes, and unmapping removes it
mkdir(maproot)
ok(FileWrite(MergeFullPath(maproot, "m1.lua"), ""), "Test fixture: maproot/m1.lua created.")
ide.filetree.settings.mapped[ide:GetProject()] = {}
ok(tree:MapDirectory(maproot) == true, "MapDirectory maps an external directory.")
is(#ide.filetree.settings.mapped[ide:GetProject()], 1, "Mapped directory is recorded in settings.")

-- locate the mapped node and verify its content refreshes
local mapid
local item, cookie = tree:GetFirstChild(tree:GetRootItem())
while item:IsOk() do
  if tree:IsDirMapped(item) then mapid = item; break end
  item, cookie = tree:GetNextChild(tree:GetRootItem(), cookie)
end
ok(mapid and mapid:IsOk(), "Mapped directory node is present in the tree.")
if mapid then
  tree:Expand(mapid)
  ok(childByText(mapid, "m1.lua"), "Existing file is shown under the mapped directory.")
  ok(FileWrite(MergeFullPath(maproot, "m2.lua"), ""), "File 'm2.lua' added inside mapped directory.")
  tree:RefreshChildren(mapid)
  ok(childByText(mapid, "m2.lua"), "New file inside mapped directory appears after refresh.")
end

tree:UnmapDirectory(maproot)
ok(not ide.filetree.settings.mapped[ide:GetProject()], "UnmapDirectory removes the mapped directory.")

-- restore the previous project and clean up the temporary files
ide.filetree.settings.extensionignore = {}
if origproject and #origproject > 0 then ide:SetProject(origproject) end
rmrf(proj)
rmrf(maproot)

-- other tests for fuzzy searches
-- textmate: https://github.com/textmate/textmate/blob/master/Frameworks/text/tests/t_ranker.cc
-- brackets: https://github.com/adobe/brackets/blob/2c1616a6346dfee29a8321b5ecc9e0f636ec42d8/test/spec/StringMatch-test.js

local function check(s, p1, p2)
  local r = ide.test.commandBarScoreItems({p1, p2}, s)
  ok(r[1][1] == p1,
    ("'%s' is more similar to '%s' (%d) than to '%s' (%d).")
    :format(s, p1, math.floor(r[1][1] == p1 and r[1][2] or r[2][2]),
               p2, math.floor(r[2][1] == p2 and r[2][2] or r[1][2])))
end

check("mtv", "MTVStatusBar.txt", "MyTextView.txt")
check("doc", "document.lua", "MyDocument.txt")
check("paste", "Paste Selection Online", "Encrypt With Password")
check("zerobrane", "zerobrane", "ZeroBraneStudio")
check("barfileopen", "BarFileOpen", "BarFinderLabelOpen")
check("readme", "readme", "README")
check("ReadMe", "READme", "readME")
check("f", "fun", "funclist.lua")

is(#ide.test.commandBarScoreItems({"funclist.lua", "f"}, "fun"), 1,
  "Patterns longer than strings don't match.")
is(#ide.test.commandBarScoreItems({"io.read"}, "io r"), 1,
  "Patterns with whitespaces still match.")
is(ide.test.commandBarScoreItems({"2-autocomp.lua"}, "2 autocomp.lua")[1][2], 99,
  "Patterns with whitespaces match closely, but not 100%.")
is(#ide.test.commandBarScoreItems({"t\\2-autocomp.lua"}, "\\2-auto"), 1,
  "Patterns with special characters still match.")
ide.config.commandbar.prefilter=0.01
is(#ide.test.commandBarScoreItems({"t\\2-autocomp.lua"}, "\\2-auto"), 1,
  "Patterns with special characters still match after prefiltering.")
ide.config.commandbar.prefilter=nil

-- ranking: exact file name and near-basename matches win (typical Go To File)
check("main.lua", "src/main.lua", "src/mainframe.lua")
check("commandbar", "src/editor/commandbar.lua", "src/editor/commandbarextra.lua")
check("init", "src/init.lua", "src/reinitializer.lua")

-- ranking: a contiguous keyword in the path beats a scattered ngram match
check("editor", "src/editor/init.lua", "src/deiort/x.lua")
check("config", "src/config.lua", "src/cfngoi.lua")

-- patterns that contain a path separator
check("editor/command", "src/editor/commandbar.lua", "src/editor/menu_command.lua")

-- short, mixed-case queries should land on word starts (CamelCase / acronyms)
check("cb", "CommandBar.lua", "ClipboardLabel.lua")
check("gtf", "GoToFile.lua", "GroupedTreeFolder.lua")
check("Editor", "src/Editor.lua", "src/editorhelper.lua")

-- leading/trailing/extra whitespace must not break matching or ordering
check("  main  ", "src/main.lua", "src/mainframe.lua")
is(#ide.test.commandBarScoreItems({"src/main.lua"}, "  main.lua "), 1,
  "Patterns with surrounding whitespace still match.")

-- the prefilter must never drop a candidate the scorer would rank highly
local prefilterwas = ide.config.commandbar.prefilter
ide.config.commandbar.prefilter = 0.01
do
  local list = {}
  for i = 1, 400 do list[i] = ("noise_%03d.lua"):format(i) end
  table.insert(list, 1, "src/very/deep/path/CommandBar.lua")
  local found = false
  for _, it in ipairs(ide.test.commandBarScoreItems(list, "cmdbar", 30)) do
    if it[1]:find("CommandBar") then found = true; break end
  end
  ok(found, "Subsequence patterns survive prefiltering in a large list.")
end
do
  local list = {}
  for i = 1, 400 do list[i] = ("zz_%03d.lua"):format(i) end
  table.insert(list, 1, "src/MyCommandBar.lua")
  local found = false
  for _, it in ipairs(ide.test.commandBarScoreItems(list, "cb", 30)) do
    if it[1]:find("CommandBar") then found = true; break end
  end
  ok(found, "Short mid-word patterns are not dropped by prefiltering.")
end
ide.config.commandbar.prefilter = prefilterwas

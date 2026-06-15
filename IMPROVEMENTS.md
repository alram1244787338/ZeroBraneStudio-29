# 查找替换预览保存链路改进说明

## 概述

本次改进增强了 ZeroBrane Studio 的"在文件中查找/替换"功能的预览保存流程，解决了批量替换时因源文件变更导致的半成功半失败问题，并提供了更详细的每文件状态报告。

## 主要改进

### 1. 文件修改时间追踪

**改动位置**: `src/editor/findreplace.lua` 第 383-387 行

在生成预览时，系统会记录每个文件的修改时间（modification time）：

```lua
-- store file modification time for later validation during save
if not reseditor.fileMeta then reseditor.fileMeta = {} end
reseditor.fileMeta[findReplace.curfilename] = {
  modTime = GetFileModTime(findReplace.curfilename)
}
```

**作用**: 保存时可以检测文件是否在预览生成后被修改过。

### 2. 增强的保存验证流程

**改动位置**: `src/editor/findreplace.lua` 第 1287-1400 行（`onEditorPreSave` 函数）

#### 2.1 文件存在性检查

```lua
if not wx.wxFileExists(fname) then
  failed = failed + 1
  report[#report+1] = {file = fname, status = "failed", reason = "file not found"}
  line = skipFileLines(line)
```

**处理**: 如果文件在预览生成后被删除，标记为失败并跳过该文件的所有预览行。

#### 2.2 文件修改时间验证

```lua
local fileMeta = editor.fileMeta and editor.fileMeta[fname]
local currentModTime = GetFileModTime(fname)
if fileMeta and fileMeta.modTime and currentModTime
and not currentModTime:IsEqualTo(fileMeta.modTime) then
  skipped = skipped + 1
  report[#report+1] = {file = fname, status = "skipped",
    reason = "file was modified after preview was generated"}
  line = skipFileLines(line)
```

**处理**: 如果文件的修改时间与预览生成时不同，安全跳过该文件，避免覆盖用户的后续修改。

#### 2.3 修复行计数 bug

**原问题**: 原代码使用全局 `lines` 计数器，当某个文件在处理过程中出现 mismatch 时，已计数的行数仍会被报告，尽管该文件并未保存。

**修复**: 使用每文件独立计数器 `fileLines`，只在文件成功保存后才累加到全局 `lines`：

```lua
local fileLines = 0
-- ... 处理文件 ...
if fileLines > 0 and not mismatch then
  local ok
  ok, err = FileWrite(fname, oveditor:GetTextDyn())
  if ok then
    files = files + 1
    lines = lines + fileLines  -- 只在成功时累加
    report[#report+1] = {file = fname, status = "updated", count = fileLines}
  else
    failed = failed + 1
    report[#report+1] = {file = fname, status = "failed", reason = err or "write failed"}
  end
```

#### 2.4 增强上下文验证

```lua
elseif lnum-1 >= oveditor:GetLineCount() then
  mismatch = lnum
  break
elseif getRawLine(oveditor, lnum-1) ~= ltext then
  mismatch = lnum
  break
```

**处理**: 增加了对无效行号的显式检查（行号超出文件范围）。

### 3. 详细的每文件状态报告

#### 3.1 结构化报告数据

```lua
local report = {}
-- 每个文件一条记录：
-- {file = fname, status = "updated", count = fileLines}
-- {file = fname, status = "skipped", reason = "..."}
-- {file = fname, status = "failed", reason = "..."}
```

#### 3.2 详细报告输出

```
/tmp/test1.lua: updated 3 lines
/tmp/test2.lua: skipped (context mismatch on line 15)
/tmp/test3.lua: failed (file not found)
```

#### 3.3 增强的统计摘要

```
Updated 5 lines in 2 files. Skipped 1 file. Failed 1 file.
```

原版本只显示：`Updated 5 lines in 2 files.`

## 边缘情况处理

### 1. 文件被删除
- 检测：`wx.wxFileExists(fname)` 返回 false
- 处理：标记为 failed，跳过该文件的所有预览行
- 报告：`failed (file not found)`

### 2. 文件在预览后被修改
- 检测：比较当前修改时间与预览时的修改时间
- 处理：标记为 skipped，跳过该文件
- 报告：`skipped (file was modified after preview was generated)`

### 3. 上下文不匹配
- 检测：上下文行内容与当前文件不符
- 处理：标记为 skipped，不保存该文件
- 报告：`skipped (context mismatch on line N)`

### 4. 无效行号
- 检测：行号超出文件行数范围
- 处理：标记为 skipped
- 报告：`skipped (context mismatch on line N)`

### 5. 文件读取失败（编码问题等）
- 检测：`FileRead` 返回 nil
- 处理：标记为 failed
- 报告：`failed (具体错误信息)`

### 6. 文件写入失败
- 检测：`FileWrite` 返回 false
- 处理：标记为 failed
- 报告：`failed (具体错误信息)`

## 测试覆盖

**测试文件**: `t/1-findreplace.lua` 第 100-195 行

### 测试用例

1. **正常批量替换** (第 100-122 行)
   - 验证多个文件都能正确更新
   - 验证统计摘要正确

2. **单文件 mismatch 不影响其他文件** (第 124-146 行)
   - 第一个文件有上下文 mismatch
   - 验证第一个文件未被修改
   - 验证第二个文件仍被正确更新
   - 验证报告显示 skipped 和 mismatch 详情

3. **删除文件的处理** (第 148-164 行)
   - 第二个文件在预览后被删除
   - 验证第一个文件仍被正确更新
   - 验证报告显示 failed 和 file not found

4. **修改文件的处理** (第 166-195 行)
   - 第一个文件在预览后被修改
   - 验证第一个文件未被覆盖
   - 验证第二个文件仍被正确更新
   - 验证报告显示 skipped 和 modification 详情

## 向后兼容性

- 保留了原有的 preview/save 流程结构
- 单文件替换功能不受影响
- 如果没有 `fileMeta` 信息（旧版预览），会跳过修改时间检查，保持原有行为
- 报告格式向后兼容，只是增加了更多细节

## 使用建议

1. **生成预览后尽快保存**: 减少文件被外部修改的概率
2. **查看详细报告**: 保存后查看预览页底部的详细报告，了解每个文件的状态
3. **处理跳过的文件**: 如果有文件被跳过，可以重新生成预览或直接编辑
4. **处理失败的文件**: 检查失败原因（文件删除、权限问题等）

## 技术细节

### 修改时间比较

使用 `wx.wxDateTime:IsEqualTo()` 方法比较两个时间点：

```lua
if not currentModTime:IsEqualTo(fileMeta.modTime) then
  -- 文件已被修改
end
```

### 预览行跳过逻辑

当需要跳过某个文件时，使用 `skipFileLines` 函数跳过该文件在预览中的所有行：

```lua
local function skipFileLines(curline)
  while true do
    curline = curline + 1
    local nexttext = getRawLine(editor, curline)
    if not nexttext or nexttext == "" then break end
    -- 非缩进、非占位符行表示新文件开始
    if not nexttext:find("^%s") and not nexttext:find("^%s*%.+$") then break end
  end
  return curline - 1
end
```

### 计数器设计

- `files`: 成功更新的文件数
- `lines`: 成功更新的行数（只计实际替换的行）
- `skipped`: 被跳过的文件数（mismatch 或修改时间变化）
- `failed`: 失败的文件数（删除、读取失败、写入失败）

## 总结

本次改进使查找替换的预览保存流程更加健壮和透明：

✅ **更安全**: 自动检测并跳过已修改的文件，避免覆盖用户工作
✅ **更清晰**: 每文件状态报告，一目了然
✅ **更准确**: 修复行计数 bug，统计数据真实反映实际更新
✅ **更完善**: 处理多种边缘情况，减少意外失败
✅ **向后兼容**: 保留现有流程，不影响单文件替换

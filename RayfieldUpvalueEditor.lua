-- ============================================================================
-- RAYFIELD OPTIMIZED UPVALUE EDITOR & CODE SPY (V2.0)
-- Features: Deep Search, Real Editing, Code Spy, Copy/Export, No-Lag Architecture
-- ============================================================================

local RayfieldLib = loadstring(game:HttpGet("https://raw.githubusercontent.com/RayfieldMain/RayfieldLibrary/main/source.lua"))()
local Window = RayfieldLib:CreateWindow({
    Name = "Upvalue Editor & Code Spy",
    LoadingTitle = "Rayfield Tools",
    Theme = "Dark",
    Icon = "Icon"
})

local MainTab = Window:CreateTab("Main", "Home")
local CodeSpyTab = Window:CreateTab("Code Spy", "FileCode")
local ExportTab = Window:CreateTab("Export/Generate", "Save")

local CONFIG = {MaxDepth = 15, CacheLimit = 1000, DebounceTime = 0.5, AutoGC = true, WeakCache = true}
local scannedFunctions, cache, cacheCount = {}, {}, 0
local isScanning, selectedFunction, clipboardBuffer = false, nil, ""

local function SafeGC() if CONFIG.AutoGC then collectgarbage("step") end end

local function GetTypeString(value)
    local t = type(value)
    if t == "table" then return "Table (" .. tostring(#value) .. " items)"
    elseif t == "function" then local info = debug.getinfo(value, "nS"); return "Function: " .. (info.name or "anonymous") .. " [" .. (info.short_src or "?") .. ":" .. (info.linedefined or "?") .. "]"
    elseif t == "string" then local str = tostring(value); return "String: \"" .. str:sub(1, 50) .. (str:len() > 50 and "..." or "") .. "\""; 
    elseif t == "number" then return "Number: " .. tostring(value)
    elseif t == "boolean" then return "Boolean: " .. tostring(value)
    elseif t == "nil" then return "Nil"
    else return t .. ": " .. tostring(value) end
end

local function SerializeValue(value, indent)
    indent = indent or 0; local spaces = string.rep("  ", indent); local t = type(value)
    if t == "nil" then return "nil"
    elseif t == "boolean" or t == "number" then return tostring(value)
    elseif t == "string" then return string.format("%q", value)
    elseif t == "function" then local info = debug.getinfo(value, "nS"); return string.format("-- Function: %s [%s:%d]", info.name or "anonymous", info.short_src or "?", info.linedefined or 0)
    elseif t == "table" then
        local result = "{\n"; local count = 0
        for k, v in pairs(value) do
            if count < 50 then
                local keyStr = type(k) == "string" and string.format("[%q]", k) or "[" .. tostring(k) .. "]"
                result = result .. spaces .. "  " .. keyStr .. " = " .. SerializeValue(v, indent + 1) .. ",\n"; count = count + 1
            else result = result .. spaces .. "  -- ... (truncated)\n"; break end
        end
        return result .. spaces .. "}"
    else return tostring(value) end
end

local function SearchUpvalues(func, depth, maxDepth, visited)
    if depth > maxDepth or isScanning == false then return end
    if not func or type(func) ~= "function" then return end
    visited = visited or {}; if visited[func] then return end; visited[func] = true
    local upvalues, i = {}, 1
    while true do
        local name, value = debug.getupvalue(func, i); if not name then break end
        upvalues[name] = {value = value, type = type(value), index = i}
        if type(value) == "function" and depth < maxDepth then
            local nested = SearchUpvalues(value, depth + 1, maxDepth, visited)
            if next(nested) then upvalues[name .. " (nested)"] = nested end
        end
        i = i + 1
    end
    if next(upvalues) then
        table.insert(scannedFunctions, {func = func, name = debug.getinfo(func, "n").name or "anonymous", source = debug.getinfo(func, "S").short_src or "unknown", line = debug.getinfo(func, "S").linedefined or 0, upvalues = upvalues, depth = depth})
    end
    SafeGC()
end

local function ScanAllFunctions(maxDepth)
    if isScanning then return end; isScanning = true; scannedFunctions = {}; local startTime = tick()
    RayfieldLib:Notify({Title = "Scanning Started", Content = "Searching for functions with upvalues...", Duration = 3})
    for k, v in pairs(_G) do if type(v) == "function" then SearchUpvalues(v, 1, maxDepth or CONFIG.MaxDepth) end end
    for k, v in pairs(package.loaded) do
        if type(v) == "table" then for kk, vv in pairs(v) do if type(vv) == "function" then SearchUpvalues(vv, 1, maxDepth or CONFIG.MaxDepth) end end
        elseif type(v) == "function" then SearchUpvalues(v, 1, maxDepth or CONFIG.MaxDepth) end
    end
    local endTime = tick(); isScanning = false
    RayfieldLib:Notify({Title = "Scan Complete", Content = string.format("Found %d functions in %.2f seconds", #scannedFunctions, endTime - startTime), Duration = 5})
    UpdateFunctionList()
end

MainTab:CreateSection("Function Scanner")
MainTab:CreateTextbox({Text = "Search functions...", PlaceholderText = "Type to filter...", RemoveFocusAfterEdited = true, Callback = function(Value) UpdateFunctionList(Value) end})
MainTab:CreateButton({Text = "Scan All Functions", Callback = function() ScanAllFunctions(CONFIG.MaxDepth) end})
MainTab:CreateSlider({Name = "Search Depth", Range = {1, 20}, Increment = 1, Current = CONFIG.MaxDepth, Callback = function(Value) CONFIG.MaxDepth = Value end})

local FunctionDropdown = MainTab:CreateDropdown({Name = "Select Function", Options = {}, CurrentOption = {}, MultipleOptions = false, Flag = "FunctionSelector", Callback = function(Value)
    if Value and #Value > 0 then
        local funcName = Value[1]
        for _, funcData in ipairs(scannedFunctions) do
            local displayName = string.format("%s [%s:%d]", funcData.name, funcData.source, funcData.line)
            if displayName == funcName then selectedFunction = funcData; UpdateInspector(funcData); break end
        end
    end
end})

MainTab:CreateSection("Function Inspector")
local InspectorLabel = MainTab:CreateLabel("No function selected")
local UpvalueCountLabel = MainTab:CreateLabel("Upvalues: 0")

MainTab:CreateSection("Upvalue Editor")
local UpvalueDropdown = MainTab:CreateDropdown({Name = "Select Upvalue", Options = {}, CurrentOption = {}, MultipleOptions = false, Flag = "UpvalueSelector", Callback = function(Value)
    if Value and #Value > 0 and selectedFunction then
        local upvalueName = Value[1]; local actualName = upvalueName:gsub(" %(nested%)$", "")
        local upvalueData = selectedFunction.upvalues[actualName]; if upvalueData then UpdateEditor(upvalueData, actualName) end
    end
end})

local EditBox = MainTab:CreateTextbox({Text = "New Value (Lua syntax)", PlaceholderText = [[e.g., "hello", 42, true, {key=value}]], RemoveFocusAfterEdited = false, Callback = function(Value) clipboardBuffer = Value end})

MainTab:CreateButton({Text = "Apply Changes", Callback = function()
    if not selectedFunction then RayfieldLib:Notify({Title = "Error", Content = "No function selected", Duration = 3}); return end
    local upvalueName = UpvalueDropdown.CurrentOption[1]; if not upvalueName then RayfieldLib:Notify({Title = "Error", Content = "No upvalue selected", Duration = 3}); return end
    local actualName = upvalueName:gsub(" %(nested%)$", ""); local upvalueData = selectedFunction.upvalues[actualName]
    if not upvalueData then RayfieldLib:Notify({Title = "Error", Content = "Upvalue not found", Duration = 3}); return end
    local newValueStr = EditBox.Text; local success, newValue = pcall(loadstring("return " .. newValueStr))
    if not success then RayfieldLib:Notify({Title = "Error", Content = "Invalid Lua syntax: " .. tostring(newValue), Duration = 5}); return end
    local setResult, setResultErr = pcall(debug.setupvalue, selectedFunction.func, upvalueData.index, newValue)
    if setResult then
        local verifyName, verifyValue = debug.getupvalue(selectedFunction.func, upvalueData.index)
        if verifyValue == newValue then RayfieldLib:Notify({Title = "Success", Content = "Upvalue updated successfully!", Duration = 3}); UpdateInspector(selectedFunction)
        else RayfieldLib:Notify({Title = "Warning", Content = "Change applied but verification failed", Duration = 3}) end
    else RayfieldLib:Notify({Title = "Error", Content = "Failed to set upvalue: " .. tostring(setResultErr), Duration = 5}) end
end})

MainTab:CreateSection("Code Spy")
MainTab:CreateButton({Text = "View Function Code", Callback = function()
    if not selectedFunction then RayfieldLib:Notify({Title = "Error", Content = "No function selected", Duration = 3}); return end
    ShowCodeInSpyTab(selectedFunction); Window:SelectTab(CodeSpyTab)
end})
MainTab:CreateButton({Text = "Copy Code to Clipboard", Callback = function()
    if not selectedFunction then RayfieldLib:Notify({Title = "Error", Content = "No function selected", Duration = 3}); return end
    local code = ExtractFunctionCode(selectedFunction); clipboardBuffer = code
    RayfieldLib:Notify({Title = "Copied", Content = "Function code copied to buffer", Duration = 3})
end})

ExportTab:CreateSection("Script Generator")
local GenerateTypeDropdown = ExportTab:CreateDropdown({Name = "Export Type", Options = {"Full Script", "Upvalue Changes Only", "Function Analysis"}, CurrentOption = {}, MultipleOptions = false, Flag = "ExportType", Callback = function(Value) end})
ExportTab:CreateButton({Text = "Generate Script", Callback = function() GenerateScript() end})
local GeneratedCodeBox = ExportTab:CreateTextbox({Text = "Generated Script", PlaceholderText = "Generated code will appear here...", RemoveFocusAfterEdited = false, Callback = function(Value) clipboardBuffer = Value end})
ExportTab:CreateButton({Text = "Copy Generated Script", Callback = function()
    if GeneratedCodeBox.Text and GeneratedCodeBox.Text:len() > 0 then clipboardBuffer = GeneratedCodeBox.Text; RayfieldLib:Notify({Title = "Copied", Content = "Generated script copied to buffer", Duration = 3})
    else RayfieldLib:Notify({Title = "Error", Content = "No generated script to copy", Duration = 3}) end
end})

MainTab:CreateSection("Performance")
local CacheInfoLabel = MainTab:CreateLabel("Cache: 0 / " .. CONFIG.CacheLimit)
local MemoryLabel = MainTab:CreateLabel("Memory: Calculating...")
MainTab:CreateButton({Text = "Clear Cache", Callback = function() cache = {}; cacheCount = 0; collectgarbage("count"); UpdatePerformanceLabels(); RayfieldLib:Notify({Title = "Cache Cleared", Content = "Memory optimized", Duration = 3}) end})
MainTab:CreateButton({Text = "Force Garbage Collection", Callback = function() collectgarbage("collect"); UpdatePerformanceLabels(); RayfieldLib:Notify({Title = "GC Done", Content = "Garbage collection forced", Duration = 3}) end})

function UpdateFunctionList(filter)
    local options = {}
    for _, funcData in ipairs(scannedFunctions) do
        local displayName = string.format("%s [%s:%d]", funcData.name, funcData.source, funcData.line)
        if not filter or displayName:lower():find(filter:lower()) then table.insert(options, displayName) end
    end
    FunctionDropdown:SetOptions(options)
end

function UpdateInspector(funcData)
    if not funcData then return end
    local infoText = string.format("Function: %s\nSource: %s\nLine: %d\nDepth: %d", funcData.name, funcData.source, funcData.line, funcData.depth)
    InspectorLabel:SetText(infoText)
    local upvalueCount = 0; for _ in pairs(funcData.upvalues) do upvalueCount = upvalueCount + 1 end
    UpvalueCountLabel:SetText("Upvalues: " .. upvalueCount)
    local upvalueOptions = {}
    for name, data in pairs(funcData.upvalues) do if type(data) == "table" and data.value ~= nil then table.insert(upvalueOptions, name .. " (" .. GetTypeString(data.value) .. ")") end end
    UpvalueDropdown:SetOptions(upvalueOptions)
end

function UpdateEditor(upvalueData, name) if not upvalueData then return end; EditBox:SetText(SerializeValue(upvalueData.value, 0)) end

function ExtractFunctionCode(funcData)
    local func = funcData.func; local info = debug.getinfo(func, "Sln")
    if not info then return "-- No debug info available" end
    local code = "-- Function: " .. (info.name or "anonymous") .. "\n-- Source: " .. (info.short_src or "unknown") .. "\n-- Line: " .. (info.linedefined or "?") .. "\n-- Upvalues:\n"
    for name, data in pairs(funcData.upvalues) do if type(data) == "table" and data.value ~= nil then code = code .. "--   " .. name .. " = " .. SerializeValue(data.value, 0) .. "\n" end end
    code = code .. "\n"
    if info.source and info.source:sub(1, 1) == "@" then local fileName = info.source:sub(2); code = code .. "-- Source file: " .. fileName .. "\n-- (Full source extraction limited by Roblox security)\n" end
    local dumpInfo = debug.getinfo(func, "u")
    if dumpInfo then code = code .. "\n-- Stats: " .. dumpInfo.numparams .. " params, " .. (dumpInfo.isvararg and "vararg" or "fixed args") .. "\n" end
    return code
end

function ShowCodeInSpyTab(funcData)
    local code = ExtractFunctionCode(funcData); CodeSpyTab:ClearAllElements()
    CodeSpyTab:CreateSection("Function Code Viewer"):CreateLabel(code)
    CodeSpyTab:CreateButton({Text = "Copy This Code", Callback = function() clipboardBuffer = code; RayfieldLib:Notify({Title = "Copied", Content = "Code copied to buffer", Duration = 3}) end})
end

function UpdatePerformanceLabels() CacheInfoLabel:SetText("Cache: " .. cacheCount .. " / " .. CONFIG.CacheLimit); local mem = collectgarbage("count"); MemoryLabel:SetText(string.format("Memory: %.2f KB", mem)) end

function GenerateScript()
    local exportType = GenerateTypeDropdown.CurrentOption[1]
    if not exportType then RayfieldLib:Notify({Title = "Error", Content = "Select export type", Duration = 3}); return end
    local script = "-- Generated by Rayfield Upvalue Editor\n-- Date: " .. os.date() .. "\n\n"
    if exportType == "Full Script" then
        script = script .. "-- Full analysis of selected function\n"
        if selectedFunction then script = script .. ExtractFunctionCode(selectedFunction) .. "\n\n-- Upvalue modification template\nlocal function ModifyUpvalues()\n    -- Add your debug.setupvalue calls here\n    -- Example:\n    -- debug.setupvalue(targetFunc, index, newValue)\nend\n"
        else script = script .. "-- No function selected for full export\n" end
    elseif exportType == "Upvalue Changes Only" then
        script = script .. "-- Upvalue changes only\nlocal function ApplyChanges()\n"
        if selectedFunction then for name, data in pairs(selectedFunction.upvalues) do if type(data) == "table" and data.value ~= nil then script = script .. "    -- Upvalue: " .. name .. "\n    -- Current: " .. SerializeValue(data.value, 0) .. "\n    -- debug.setupvalue(targetFunc, " .. data.index .. ", newValue)\n\n" end end
        else script = script .. "    -- No function selected\n" end
        script = script .. "end\n"
    elseif exportType == "Function Analysis" then
        script = script .. "-- Function Analysis Report\nlocal Analysis = {\n    TotalFunctions = " .. #scannedFunctions .. ",\n    Functions = {\n"
        for i, funcData in ipairs(scannedFunctions) do if i <= 20 then script = script .. "        {\n            Name = \"".. (funcData.name or "anonymous") .. "\",\n            Source = \"".. funcData.source .. "\",\n            Line = " .. funcData.line .. ",\n            Depth = " .. funcData.depth .. "\n        },\n" end end
        script = script .. "    }\n}\n"
    end
    GeneratedCodeBox:SetText(script); RayfieldLib:Notify({Title = "Generated", Content = "Script generated successfully", Duration = 3})
end

UpdatePerformanceLabels()
spawn(function() while true do wait(5); UpdatePerformanceLabels(); SafeGC() end end)
RayfieldLib:Notify({Title = "Ready", Content = "Upvalue Editor loaded. Click 'Scan All Functions' to begin.", Duration = 5})

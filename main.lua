-- Boui's Remote Spy
-- Synapse Z Only

if not ImGui or not ImGui.OnRender then
    return warn("Remote Spy runs only on Synapse Z!");
end;

-- make folders and load settings

if not isfolder("brs") then
    makefolder("brs");
end;

if not isfile("brs/settings.json") then
    writefile("brs/settings.json", "{}");
end;

-- some optimization vars

local HttpService = game:GetService("HttpService");

local Color3NEW, Color3RGB = Color3.new, Color3.fromRGB;
local tableInsert, tableClear, tableConcat, tableFind, tableRemove = table.insert, table.clear, table.concat, table.find, table.remove;
local stringSub, stringRep, stringLower, stringGsub, stringFind = string.sub, string.rep, string.lower, string.gsub, string.find;
local taskDefer = task.defer;
local vector2New = Vector2.new;

-- initialize ui (settings)

local ui = {showNil = false, showStringArguments = false};

do
    for i, v in next, HttpService:JSONDecode(readfile("brs/settings.json")) do
        ui[i] = v;
    end;
end;

-- initialize utility

local utility = {indentString = "    ", alphabet = "abcdefghijklmnopqrstuvwxyz"};

do
    local ICON_REMOTE_EVENT = ImGui.LoadImage(game:HttpGet("https://i-dont-wanna.live/xlt45ibiaqb9a0g1uc.png"));
    local ICON_REMOTE_FUNCTION = ImGui.LoadImage(game:HttpGet("https://i-dont-wanna.live/c22mzbc05mowxowp3h.png"));

    utility.icons = {
        RemoteEvent = ICON_REMOTE_EVENT;
        UnreliableRemoteEvent = ICON_REMOTE_EVENT;
        RemoteFunction = ICON_REMOTE_FUNCTION;
    }

    function utility.Indent(offset: number) -- a bad impl
        ImGui.Text("");
        ImGui.SameLine(number);
    end;

    function utility.PushStyleColor(id: number, color: Color3) -- i hope grh fixes this shit
        ImGui.PushStyleColor(id, color);
    end;

    function utility.Selectable(name: string, value: boolean) -- this is better
        local held, clicked = ImGui.Selectable(name, value);
        return clicked; -- since held is always false
    end;

    function utility.isValidName(name: string)
        return stringGsub(stringGsub(stringLower(name), "%a", ""), "%d", "") == "" and stringFind(name, "%d") ~= 1;
    end;

    function utility.getPath(target: Instance)
        local path = {target};
        local current = target;
        while current ~= game do
            current = current.Parent;
            tableInsert(path, current);
        end;
        local pathString = `game:GetService("{path[#path-1].ClassName}").`;
        for i = -#path+2, -1 do
            local name = path[-i].Name;
            if not utility.isValidName(name) then
                pathString = stringSub(pathString, 1, -2) .. `["{name}"].`;
            else
                pathString ..= name .. ".";
            end;
        end;
        return stringSub(pathString, -1, -1) == "." and stringSub(pathString, 1, -2) or pathString;
    end;

    function utility.tableToString(target: table, indent: number)
        indent = indent or 1;
        local str = "{\n";
        for i, v in next, target do
            local valueString = utility.valueToString(v, indent+1);
            local indexString = utility.valueToString(i, indent+1);
            str = str .. stringRep(utility.indentString, indent) .. `[{indexString}] = {valueString};\n`
        end;
        return str .. stringRep(utility.indentString, indent-1) .. "}";
    end;

    function utility.valueToString(value: any, indent: number)
        local valueString = tostring(value);
        if typeof(value) == "table" then
            valueString = utility.tableToString(value, indent);
        elseif typeof(value) == "string" then
            valueString = `"{value}"`;
        elseif typeof(value) == "Instance" then
            if value.Parent == nil then
                valueString = `nil.{value.Name}`; -- to lazy to make this shit;
            else
                valueString = utility.getPath(value);
            end;
        elseif typeof(value) == "Vector2" then
            valueString = `Vector2.new({valueString})`;
        elseif typeof(value) == "Vector3" then
            valueString = `Vector3.new({valueString})`;
        elseif typeof(value) == "Color3" then
            valueString = `Color3.new({valueString})`;
        elseif typeof(value) == "CFrame" then
            valueString = `CFrame.new({valueString})`;
        elseif typeof(value) == "UDim" then
            valueString = `UDim.new({valueString})`;
        elseif typeof(value) == "UDim2" then
            valueString = `UDIm2.new({tostring(value.X.Scale)}, {tostring(value.X.Offset)}, {tostring(value.Y.Scale)}, {tostring(value.Y.Offset)})`;
        elseif typeof(value) == "Axes" then
            valueString = `Axes.new({valueString})`;
        elseif typeof(value) == "Ray" then
            valueString = `Ray.new({utility.valueToString(value.Origin)}, {utility.valueToString(value.Direction)})`;
        end;
        return valueString;
    end;

    function utility.generateScript(remote: Instance, args: table, count: number)
        local start = "--Script generated by Boui's Remote Spy\n";

        if #args > 0 then
            start ..= "local arguments = {\n";

             for i = 1, #args do
                local arg = args[i];
                local argString = utility.valueToString(arg, 2);
                start ..= utility.indentString .. `{argString};\n`;
            end;

            return start .. `};\n\n{utility.getPath(remote)}:FireServer(unpack(arguments, 1, {tostring(count)}));`;
        else
            if count > 0 then
                return start .. `\n{utility.getPath(remote)}:FireServer({stringSub(stringRep("nil, ", count), 1, -3)});`;
            else
                return start .. `\n{utility.getPath(remote)}:FireServer();`;
            end;
        end;
       
    end;

    function utility.saveSettings()
        writefile("brs/settings.json", HttpService:JSONEncode(ui));
    end;
end;

-- initalize rspy (vars&funcs)

local remoteSpy = {cached = 0, unique_caches = 0, cache = {}, ignore = {}, block = {}};

do

    --[[remoteSpy.cache = {
        [game:GetService("ReplicatedStorage").Remotes.Information] = {
            {args = {"hi", "test"}, count = 2, called = getcallingscript()};
        };
    }; -- for tests only!]]

    function remoteSpy.recalculate() -- recalculate cache count
        local total, unique = 0, 0;

        for remote, calls in next, remoteSpy.cache do
            unique += 1;
            total += #calls;
        end;

        remoteSpy.cached = total;
        remoteSpy.unique_caches = unique;
    end;

    function remoteSpy.clear() -- remove all the 0 calls
        local newCache = {};

        for remote, calls in next, remoteSpy.cache do
            if #calls == 0 then
                continue;
            end;
            newCache[remote] = calls;
        end;

        tableClear(remoteSpy.cache);
        remoteSpy.cache = newCache;
    end;

end;

-- imgui variables

local tab = 0;
local remoteTab = 0;

ImGui.OnRender(function()
    ImGui.SetNextWindowSize(Vector2.new(400, 300), ImGuiCond_FirstUseEver);
    ImGui.Begin("Boui's Remote Spy");

    if remoteTab == 0 then
        if ImGui.Button("Remotes") then
            tab = 0;
        end; ImGui.SameLine();
        if ImGui.Button("Settings") then
            tab = 1;
        end;
    end;

    if tab == 0 then
        if remoteTab == 0 then
            if remoteSpy.cached == 0 then
                ImGui.TextColored(Color3NEW(1, 0, 0), "No calls cached!");
            else
                ImGui.Text("Cached:"); ImGui.SameLine();
                ImGui.TextColored(Color3NEW(0, 1, 0), `{tostring(remoteSpy.cached)} calls; {tostring(remoteSpy.unique_caches)} remotes`);
            end;
            if ImGui.Button("Clear Ignore List") then
                tableClear(remoteSpy.ignore)
            end; ImGui.SameLine();
            if ImGui.Button("Clear Block List") then
                tableClear(remoteSpy.block);
            end; ImGui.SameLine();
            if ImGui.Button("Clear All Calls") then
                tableClear(remoteSpy.cache);
                remoteSpy.recalculate();
            end;
            --utility.PushStyleColor(24, ImGui.GetColorU32(255, 255, 255, 0.5)); -- this shit doesn't work :sob:
            utility.PushStyleColor(25, Color3RGB(165, 165, 165));
            utility.PushStyleColor(26, Color3RGB(180, 180, 180));
            for remote, calls in next, remoteSpy.cache do
                utility.Indent(5);
                ImGui.Image(utility.icons[calls.class], vector2New(16, 16)); ImGui.SameLine();
                if utility.Selectable(tostring(remote), false) then
                    remoteTab = remote;
                end; ImGui.SameLine();
                ImGui.Text("  Calls:"); ImGui.SameLine();
                ImGui.TextColored(Color3NEW(0, 1, 0), tostring(#calls)); --[[ImGui.SameLine();
                ImGui.Button("Ignore"); ImGui.SameLine();
                ImGui.Button("Block");]] -- port in future versions
            end;
            ImGui.PopStyleColor(3);
        else
            local ignored, blocked = tableFind(remoteSpy.ignore, remoteTab) ~= nil, tableFind(remoteSpy.block, remoteTab) ~= nil;

            local calls = remoteSpy.cache[remoteTab];
            ImGui.TextColored(Color3NEW(1, 0, 0), "Instance: "); ImGui.SameLine();
            ImGui.Text(tostring(remoteTab)); ImGui.SameLine();
            ImGui.Image(utility.icons[calls.class or "RemoteEvent"], vector2New(16, 16));
            utility.PushStyleColor(21, Color3RGB(200, 0, 0));
            utility.PushStyleColor(22, Color3RGB(225, 0, 0));
            utility.PushStyleColor(23, Color3RGB(255, 0, 0));
            if ImGui.Button("Close") then
                remoteTab = 0;
                remoteSpy.clear();
                remoteSpy.recalculate();
            end; ImGui.SameLine();
            ImGui.PopStyleColor(3);
            if ImGui.Button("Clear") then
                tableClear(calls);
            end; ImGui.SameLine();
            if ImGui.Button(ignored and "Unignore" or "Ignore") then
                if ignored then
                    tableRemove(remoteSpy.ignore, tableFind(remoteSpy.ignore, remoteTab));
                else
                    tableInsert(remoteSpy.ignore, remoteTab);
                end;
            end; ImGui.SameLine();
            if ImGui.Button(blocked and "Unblock" or "Block") then
                if blocked then
                    tableRemove(remoteSpy.block, tableFind(remoteSpy.block, remoteTab));
                else
                    tableInsert(remoteSpy.block, remoteTab);
                end;
            end; -- remove in future

            local requestFrom = ui.showStringArguments and "stringified" or "args";

            for i = 1, #calls do
                --i = -i;
                ImGui.Text(`Call {tostring(i)}`);
                local call = calls[i];
                for n = 1, ui.showNil and call.count or #call.args do
                    local argument = call[requestFrom][n];
                    ImGui.TextColored(Color3RGB(250, 150, 0), `{tostring(n)}.  `); ImGui.SameLine();
                    ImGui.Text(tostring(argument));
                end;
                if ImGui.Button("Generate Script##Call"..i) then
                    task.defer(setclipboard, utility.generateScript(remoteTab, call.args, call.count));
                end; ImGui.SameLine();
                if ImGui.Button("Get Calling Script##Call"..i) then
                    local script = call.called;
                    if script == nil then
                        taskDefer(setclipboard, "NO SCRIPT FOUND");
                    elseif script.Parent == nil then
                        taskDefer(setclipboard, script.Name.."--PARENTED TO NIL");
                    else
                        taskDefer(setclipboard, utility.getPath(script));
                    end;
                end; ImGui.SameLine();
                if ImGui.Button("Repeat##Call"..i) then
                    taskDefer(remoteTab.FireServer, remoteTab, unpack(call.args, 1, call.count));
                end;
            end;
        end;
    elseif tab == 1 then
        ui.showNil = ImGui.Checkbox("Show Nil Arguments", ui.showNil);
        ui.showStringArguments = ImGui.Checkbox("Show Stringified Arguments", ui.showStringArguments);
        if ImGui.Button("Save") then
            taskDefer(utility.saveSettings);
            taskDefer(rconsoleprint, "[BRS] Settings saved");
        end; ImGui.SameLine();
        if ImGui.Button("Reset") then
            ui.showNil = false;
            ui.showStringArguments = false;
        end;
        ImGui.Text("Credits:\n    -boui: developing this thing\n    -GRH for adding ImGui & help\n    -DracoFAAD for helping me");
    end;

    ImGui.End();
end);

-- hooks

local oldNamecall; oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)

    if not checkcaller() then -- add toggle in future
        local arguments = {...};
        local count = select("#", ...);
        local method = getnamecallmethod();
        if method == "FireServer" and self.ClassName == "RemoteEvent" or self.ClassName == "UnreliableRemoteEvent" then
            if tableFind(remoteSpy.block, self) then
                return;
            end;
            if tableFind(remoteSpy.ignore, self) then
                return oldNamecall(self, ...);
            end;
            local cache = remoteSpy.cache[self];
            if not cache then
                cache = {class = self.ClassName};
                remoteSpy.cache[self] = cache;
            end;
            local stringified = {};
            for i = 1, #arguments do
                local argument = arguments[i];
                stringified[i] = utility.valueToString(argument);
            end;
            tableInsert(cache, {
                args = arguments;
                count = count;
                called = getcallingscript();
                stringified = stringified;
            });
            remoteSpy.recalculate();
        elseif method == "RemoteFunction" and self.ClassName == "RemoteFunction" then
            if tableFind(remoteSpy.block, self) then
                return;
            end;
            if tableFind(remoteSpy.ignore, self) then
                return oldNamecall(self, ...);
            end;
            local cache = remoteSpy.cache[self];
            if not cache then
                cache = {class = self.ClassName};
                remoteSpy.cache[self] = cache;
            end;
            local stringified = {};
            for i = 1, #arguments do
                local argument = arguments[i];
                stringified[i] = utility.valueToString(argument);
            end;
            tableInsert(cache, {
                args = arguments;
                count = count;
                called = getcallingscript();
                stringified = stringified;
            });
            remoteSpy.recalculate();
        end;
    end;

    return oldNamecall(self, ...);
end));

rconsoleprint("[BRS] Loaded");

return function(TAS)
    local MapEngine = {}
    local RunService = game:GetService("RunService")
    local Players = game:GetService("Players")
    local Lighting = game:GetService("Lighting")
    local LocalPlayer = Players.LocalPlayer
    
    local State = TAS.Services.State
    local Serializer = TAS.Services.Serializer
    local UI = TAS.Services.Interface
    
    -- // INTERNAL VARIABLES //
    local MapRecorderCache = {}
    
    function MapEngine.CaptureLighting()
        State.SavedLighting.Props = {
            Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, Brightness = Lighting.Brightness,
            ClockTime = Lighting.ClockTime, FogColor = Lighting.FogColor, FogEnd = Lighting.FogEnd,
            FogStart = Lighting.FogStart, GlobalShadows = Lighting.GlobalShadows,
            ExposureCompensation = Lighting.ExposureCompensation, TimeOfDay = Lighting.TimeOfDay
        }
        State.SavedLighting.Children = {}
        for _, child in ipairs(Lighting:GetChildren()) do table.insert(State.SavedLighting.Children, child:Clone()) end
        State.LightingCaptured = true
        UI.SendAlert("Lighting Captured", Color3.fromRGB(255, 255, 0))
    end
    
    function MapEngine.EnforceLighting()
        if not State.LightingCaptured then return end
        for prop, val in pairs(State.SavedLighting.Props) do 
            if Lighting[prop] ~= val then Lighting[prop] = val end 
        end
        local CurrentChildren = Lighting:GetChildren()
        if #CurrentChildren ~= #State.SavedLighting.Children then
            Lighting:ClearAllChildren()
            for _, c in ipairs(State.SavedLighting.Children) do c:Clone().Parent = Lighting end
        end
    end
    
    function MapEngine.SetupMap()
        local MP = game.Workspace.Multiplayer
        local LiveMap = MP:WaitForChild("Map", 9e9)
        local Settings = LiveMap:FindFirstChild("Settings")
        local MapName = Settings and Settings:GetAttribute("MapName") or "Unknown Map"
        
        UI.SendAlert("Map Detected: " .. MapName, Color3.fromRGB(0, 255, 255))
        
        local Spawn = LiveMap:FindFirstChild("Spawn", true)
        if not Spawn then
            -- Fallback spawn finder
            LiveMap.PrimaryPart = LiveMap:FindFirstChild("Part", true) -- simplified for brevity
        else
            LiveMap.PrimaryPart = Spawn
        end
        
        MapEngine.CaptureLighting()
        
        for _, desc in ipairs(LiveMap:GetDescendants()) do
            if desc:IsA("BasePart") or desc:IsA("Decal") or desc:IsA("Texture") then Serializer.GetUUID(desc) end
        end
        
        LiveMap.Archivable = true
        for _, d in pairs(LiveMap:GetDescendants()) do d.Archivable = true end
        
        State.ClonedMap = LiveMap:Clone()
        State.ClonedMap.Parent = nil 
        
        local Char = LocalPlayer.Character
        local Root = Char:WaitForChild("HumanoidRootPart")
        local Hum = Char:WaitForChild("Humanoid")
        
        local Recording = true
        local StartTime = os.clock()
        local Recorders = {}
        local ButtonPressTimings = {}
        
        -- [[ CHANGED TRACKER LOGIC ]] --
        local function TrackPart(Part)
            local id = Serializer.GetUUID(Part)
            if not id then return end
            
            local PropWhitelist = {
                BasePart = {["CFrame"]=true,["Transparency"]=true,["CanCollide"]=true,["Color"]=true,["Size"]=true,["Anchored"]=true,["Material"]=true,["Reflectance"]=true},
                Decal = {["Transparency"]=true,["Color3"]=true,["Texture"]=true},
                Texture = {["Transparency"]=true,["Color3"]=true,["Texture"]=true,["OffsetStudsU"]=true,["OffsetStudsV"]=true,["StudsPerTileU"]=true,["StudsPerTileV"]=true}
            }
            
            local MyWhitelist = nil
            if Part:IsA("BasePart") then MyWhitelist = PropWhitelist.BasePart
            elseif Part:IsA("Decal") then MyWhitelist = PropWhitelist.Decal
            elseif Part:IsA("Texture") then MyWhitelist = PropWhitelist.Texture end
            
            if not MyWhitelist then return end
            
            MapRecorderCache[Part] = {}
            for prop, _ in pairs(MyWhitelist) do
                local s, val = pcall(function() return Part[prop] end)
                if s then MapRecorderCache[Part][prop] = val end
            end
            
            table.insert(Recorders, Part.Changed:Connect(function(Prop)
                if not Recording or not MyWhitelist[Prop] then return end
                local NewVal = Part[Prop]
                local OldVal = MapRecorderCache[Part][Prop]
                
                if NewVal ~= OldVal then
                    local EventData = { Time = os.clock() - StartTime, UUID = id, Prop = Prop, OldVal = OldVal, NewVal = NewVal }
                    if Prop == "Anchored" and Part:IsA("BasePart") then
                        EventData.StoredCFrame = Part.CFrame; EventData.StoredCanCollide = Part.CanCollide
                    end
                    table.insert(State.MapEvents, EventData)
                    MapRecorderCache[Part][Prop] = NewVal
                end
            end))
            
            table.insert(Recorders, Part.Destroying:Connect(function()
                if not Recording then return end
                local StateData = Serializer.DeepCopy(MapRecorderCache[Part])
                table.insert(State.MapEvents, { Time = os.clock() - StartTime, UUID = id, Prop = "Destroyed", OldVal = StateData, NewVal = true })
            end))
        end

        for _, Object in ipairs(LiveMap:GetDescendants()) do
            if Object:IsA("BasePart") or Object:IsA("Decal") or Object:IsA("Texture") then TrackPart(Object) end
        end
        
        -- [[ BUTTON SCANNER ]] --
        UI.SendAlert("Scanning for Buttons...", Color3.fromRGB(255, 170, 0))
        Hum.Health = 99999
        
        local Buttons = {}
        for i, MapObject in pairs(LiveMap:GetDescendants()) do
            if Serializer.IsRandomString(MapObject.Name) and MapObject:IsA("Model") then
                local Hitbox
                for i, Candidate in pairs(MapObject:GetChildren()) do
                    if Candidate:IsA("BasePart") and tostring(Candidate.BrickColor) ~= "Medium stone grey" then
                        Hitbox = Candidate; break
                    end
                end
                if Hitbox and Serializer.IsRandomString(Hitbox.Name) then
                    Hitbox.Name = "Hitbox"
                    table.insert(Buttons, MapObject)
                end
            end
        end
        UI.SendAlert("Found " .. #Buttons .. " Buttons. Farming...", Color3.fromRGB(0, 255, 0))

        -- [[ GODMODE FARM LOOP ]] --
        -- Simplified Noclip
        for _, v in pairs(Char:GetChildren()) do if v:IsA("BasePart") then v.CanCollide = false end end
        
        local GodModeCon = RunService.RenderStepped:Connect(function() if Hum then Hum.Health = 99999 end end)
        
        local LastTargetButton = nil
        State.RecordedButtonSequence = {}
        
        while Recording and LiveMap.Parent and Hum.Health > 0 do
            Hum.Jump = true
            local FailedScan = true
            Root.Anchored = true
            
            for i, Button in pairs(Buttons) do
                local ButtonHitbox = Button:FindFirstChild("Hitbox")
                if ButtonHitbox and Button:FindFirstChild("TouchInterest", true) and Button:FindFirstChildWhichIsA("BillboardGui", true) then
                    FailedScan = false
                    Root.Anchored = false
                    
                    if Button ~= LastTargetButton then
                        local uuid = Serializer.GetUUID(ButtonHitbox)
                        if uuid and not table.find(State.RecordedButtonSequence, uuid) then
                            table.insert(State.RecordedButtonSequence, uuid)
                            ButtonPressTimings[uuid] = (os.clock() - StartTime) + LocalPlayer:GetNetworkPing()
                        end
                        if LastTargetButton ~= nil then task.wait(0.1) end
                        LastTargetButton = Button
                    else
                         local uuid = Serializer.GetUUID(ButtonHitbox)
                         if uuid and not table.find(State.RecordedButtonSequence, uuid) then
                            table.insert(State.RecordedButtonSequence, uuid)
                            ButtonPressTimings[uuid] = (os.clock() - StartTime) + LocalPlayer:GetNetworkPing()
                        end
                    end
                    
                    Root.CFrame = CFrame.new(ButtonHitbox.Position)
                    Root.Velocity = Vector3.new(0,0,0)
                    Hum:ChangeState(Enum.HumanoidStateType.Jumping)
                    task.wait(0.255/15)
                end
            end
            
            if FailedScan then Root.CFrame = CFrame.new(0, 1000, 0); Root.Velocity = Vector3.new(0,0,0) end
            RunService.Heartbeat:Wait()
        end
        
        Recording = false
        if GodModeCon then GodModeCon:Disconnect() end
        for _, r in ipairs(Recorders) do r:Disconnect() end
        
        MapEngine.CaptureLighting()
        if LiveMap then LiveMap:Destroy() end
        
        State.ClonedMap.Parent = workspace
        State.MapUUIDs = {}
        for _, desc in ipairs(State.ClonedMap:GetDescendants()) do
            local id = desc:GetAttribute("TAS_UUID")
            if id then State.MapUUIDs[id] = desc end
        end
        
        -- Restore Initial State
        for _, Event in ipairs(State.MapEvents) do Event.Instance = State.MapUUIDs[Event.UUID] end
        for i = #State.MapEvents, 1, -1 do
            local Event = State.MapEvents[i]
            if Event.Instance and Event.Prop ~= "Destroyed" then Event.Instance[Event.Prop] = Event.OldVal end
        end
        
        -- Final Setup
        if not State.ClonedMap.PrimaryPart then State.ClonedMap.PrimaryPart = State.ClonedMap:FindFirstChild("Spawn", true) end
        State.MapPos = State.ClonedMap.PrimaryPart.Position
        State.MapX, State.MapY, State.MapZ = State.MapPos.X, State.MapPos.Y, State.MapPos.Z
        
        LocalPlayer.Character:BreakJoints()
        UI.SendAlert("Respawning...", Color3.fromRGB(255, 255, 0))
        LocalPlayer.CharacterAdded:Wait()
        Char = LocalPlayer.Character
        task.wait(1)
        
        Root = Char:WaitForChild("HumanoidRootPart")
        Hum = Char:WaitForChild("Humanoid")
        Root.CFrame = State.ClonedMap.PrimaryPart.CFrame + Vector3.new(0, 5, 0)
        task.wait(0.5)
        
        State.PauseStart = tick()
        State.RunStart = tick()
        State.PlaybackIndex = 1
        
        TAS.Services.Controller.HookAnimations()
        UI.Create(MapName)
        
        -- Register Buttons to UI
        State.ButtonRegistry = {}
        local CheckedButtonParts = {}
        
        local function RegisterButton(btn)
            if not btn or CheckedButtonParts[btn] then return end
            CheckedButtonParts[btn] = true
            table.insert(State.TotalButtons, btn)
            
            local sel = Instance.new("SelectionBox", btn)
            sel.Adornee = btn
            sel.Color3 = Color3.fromRGB(255, 140, 0)
            
            local uuid = Serializer.GetUUID(btn)
            local order = table.find(State.RecordedButtonSequence, uuid) or 999
            local recTime = ButtonPressTimings[uuid]
            
            local bData = { IsPressed = false, SelectionBox = sel, Order = order, RecordedTime = recTime }
            State.ButtonRegistry[btn] = bData
            State.OrderedButtonRegistry[order] = bData
            
            table.insert(TAS.Connections, btn.Touched:Connect(function(hit)
                if hit.Parent == LocalPlayer.Character and not bData.IsPressed then
                    if not State.RunStart then return end
                    
                    if State.AutoResetEnv and bData.RecordedTime then
                         local RealTime = tick() - State.RunStart - State.TimeOffset
                         State.PreviewOffset = bData.RecordedTime - RealTime
                         UI.SendAlert("Synced to " .. string.format("%.2fs", bData.RecordedTime), Color3.fromRGB(0, 255, 255))
                    end
                    
                    bData.IsPressed = true
                    bData.TruePressTime = tick() - State.RunStart - State.TimeOffset
                    sel.Color3 = Color3.fromRGB(0, 255, 0)
                    UI.SendAlert("Button " .. (order ~= 999 and "#"..order or "") .. " Pressed!", Color3.fromRGB(0, 255, 0))
                end
            end))
        end

        for _, obj in ipairs(State.ClonedMap:GetDescendants()) do
             if obj.Name:find("_Water") and obj:IsA("BasePart") then table.insert(State.WaterParts, obj) end
             if obj.Name == "ButtonIcon" then
                 local p = obj.Parent and obj.Parent.Parent
                 if p and p:IsA("BasePart") then RegisterButton(p) end
             end
             if Serializer.IsRandomString(obj.Name) and obj:IsA("Model") and not obj.Name:find("NPC") then
                 local hp = obj:FindFirstChild("Hitbox")
                 if hp then RegisterButton(hp) end
             end
        end
        
        UI.SendAlert("Map Ready & Linked", Color3.fromRGB(0, 255, 0))
    end
    
    function MapEngine.UpdateMapState(TargetTime)
        if State.EnvPaused then return end
        if not State.PlaybackIndex then State.PlaybackIndex = 1 end
        
        -- Forward
        while State.PlaybackIndex <= #State.MapEvents and State.MapEvents[State.PlaybackIndex].Time <= TargetTime do
            local Event = State.MapEvents[State.PlaybackIndex]
            if Event.Instance then
                if Event.Prop == "Destroyed" then
                    Event.Instance.Transparency = 1
                    if Event.Instance:IsA("BasePart") then Event.Instance.CanCollide = false; Event.Instance.Anchored = true end
                elseif Event.Prop == "Anchored" then
                    Event.Instance.Anchored = Event.NewVal
                else
                    Event.Instance[Event.Prop] = Event.NewVal
                end
            end
            State.PlaybackIndex = State.PlaybackIndex + 1
        end
        
        -- Backward
        while State.PlaybackIndex > 1 and State.MapEvents[State.PlaybackIndex - 1].Time > TargetTime do
            State.PlaybackIndex = State.PlaybackIndex - 1
            local Event = State.MapEvents[State.PlaybackIndex]
            if Event.Instance then
                if Event.Prop == "Destroyed" then
                     local s = Event.OldVal
                     Event.Instance.Transparency = s.Transparency
                     if Event.Instance:IsA("BasePart") then Event.Instance.CanCollide = s.CanCollide; Event.Instance.CFrame = s.CFrame; Event.Instance.Anchored = s.Anchored end
                else
                     Event.Instance[Event.Prop] = Event.OldVal
                end
            end
        end
    end
    
    function MapEngine.SyncButtonState(VisualTime, RealTime)
        for part, data in pairs(State.ButtonRegistry) do
            if data.IsPressed and data.TruePressTime and data.TruePressTime > RealTime then
                data.IsPressed = false
            end
            
            local isVisuallyPressed = (data.TruePressTime and data.TruePressTime <= VisualTime)
            if isVisuallyPressed then data.SelectionBox.Color3 = Color3.fromRGB(0, 255, 0)
            elseif data.Order ~= 999 then data.SelectionBox.Color3 = Color3.fromRGB(255, 140, 0) end
        end
    end
    
    function MapEngine.Cleanup()
         if State.ClonedMap then State.ClonedMap:Destroy() end
    end
    
    return MapEngine
end

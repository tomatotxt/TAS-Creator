return function(TAS)
    local Core = {}
    local Services = {
        Run = game:GetService("RunService"),
        Input = game:GetService("UserInputService"),
        Lighting = game:GetService("Lighting"),
        Players = game:GetService("Players"),
        ReplicatedStorage = game:GetService("ReplicatedStorage")
    }
    local LocalPlayer = Services.Players.LocalPlayer
    
    local State = TAS.Services.State
    local UI = TAS.Services.UI
    local Serializer = TAS.Services.Serializer

    -- // 1. CORE FUNCTIONS //
    function Core.CaptureLighting()
        State.SavedLighting.Props = {
            Ambient = Services.Lighting.Ambient, OutdoorAmbient = Services.Lighting.OutdoorAmbient, 
            Brightness = Services.Lighting.Brightness, ClockTime = Services.Lighting.ClockTime, 
            FogColor = Services.Lighting.FogColor, FogEnd = Services.Lighting.FogEnd
        }
        State.SavedLighting.Children = {}
        for _, c in ipairs(Services.Lighting:GetChildren()) do table.insert(State.SavedLighting.Children, c:Clone()) end
        State.LightingCaptured = true
        UI.SendAlert("Lighting Captured", Color3.fromRGB(255, 255, 0))
    end
    
    function Core.EnforceLighting()
        if not State.LightingCaptured then return end
        for p, v in pairs(State.SavedLighting.Props) do if Services.Lighting[p] ~= v then Services.Lighting[p] = v end end
        if #Services.Lighting:GetChildren() ~= #State.SavedLighting.Children then
            Services.Lighting:ClearAllChildren()
            for _, c in ipairs(State.SavedLighting.Children) do c:Clone().Parent = Services.Lighting end
        end
    end
    
    function Core.UpdateMapState(TargetTime)
        if State.EnvPaused then return end
        -- Forward
        while State.PlaybackIndex <= #State.MapEvents and State.MapEvents[State.PlaybackIndex].Time <= TargetTime do
            local Ev = State.MapEvents[State.PlaybackIndex]
            if Ev.Instance then
                if Ev.Prop == "Destroyed" then
                    Ev.Instance.Transparency = 1
                    if Ev.Instance:IsA("BasePart") then Ev.Instance.CanCollide = false; Ev.Instance.Anchored = true end
                elseif Ev.Prop == "Anchored" then Ev.Instance.Anchored = Ev.NewVal
                else Ev.Instance[Ev.Prop] = Ev.NewVal end
            end
            State.PlaybackIndex = State.PlaybackIndex + 1
        end
        -- Backward
        while State.PlaybackIndex > 1 and State.MapEvents[State.PlaybackIndex - 1].Time > TargetTime do
            State.PlaybackIndex = State.PlaybackIndex - 1
            local Ev = State.MapEvents[State.PlaybackIndex]
            if Ev.Instance then
                if Ev.Prop == "Destroyed" then
                     Ev.Instance.Transparency = Ev.OldVal.Transparency
                     if Ev.Instance:IsA("BasePart") then Ev.Instance.CanCollide = Ev.OldVal.CanCollide; Ev.Instance.CFrame = Ev.OldVal.CFrame end
                else Ev.Instance[Ev.Prop] = Ev.OldVal end
            end
        end
    end
    
    function Core.SyncButtonState(VisualTime, RealTime)
        for _, data in pairs(State.ButtonRegistry) do
            if data.IsPressed and data.TruePressTime > RealTime then data.IsPressed = false end
            if data.TruePressTime and data.TruePressTime <= VisualTime then data.SelectionBox.Color3 = Color3.fromRGB(0, 255, 0)
            else data.SelectionBox.Color3 = (data.Order ~= 999) and Color3.fromRGB(255, 140, 0) or Color3.fromRGB(255, 140, 0) end
        end
    end

    function Core.HookAnimations()
        local script = LocalPlayer.Character:WaitForChild("Animate", 10)
        if not script then return end
        local success, env = pcall(getsenv, script)
        if success then
            State.AnimEnv = env
            State.OriginalPlayAnim = State.AnimEnv.playAnimation
            State.AnimEnv.playAnimation = function(anim, speed)
                if not State.IsPaused then
                    State.CurrentAnim = {anim, speed}
                    State.OriginalPlayAnim(State.CurrentAnim[1], State.CurrentAnim[2], LocalPlayer.Character.Humanoid)
                end
            end
        end
    end

    -- // 2. MAP SETUP & GODMODE //
    function Core.SetupMap()
        local MP = workspace:WaitForChild("Multiplayer")
        local LiveMap = MP:WaitForChild("Map", 10)
        
        if not LiveMap then 
            UI.SendAlert("Error: Map not found!", Color3.fromRGB(255, 0, 0))
            return 
        end
        
        local MapName = LiveMap:FindFirstChild("Settings") and LiveMap.Settings:GetAttribute("MapName") or "Unknown"
        UI.SendAlert("Initializing: " .. MapName, Color3.fromRGB(0, 255, 255))
        
        LiveMap.PrimaryPart = LiveMap:FindFirstChild("Spawn", true) or LiveMap:FindFirstChild("Part", true)
        Core.CaptureLighting()
        
        -- SCANNING
        for _, d in ipairs(LiveMap:GetDescendants()) do 
            if d:IsA("BasePart") or d:IsA("Decal") or d:IsA("Texture") then Serializer.GetUUID(d) end
            d.Archivable = true 
        end
        State.ClonedMap = LiveMap:Clone(); State.ClonedMap.Parent = nil
        
        -- RECORDER
        local Recording = true
        local StartTime = os.clock()
        local Recorders = {}
        
        local function Track(Part)
            local id = Serializer.GetUUID(Part)
            if not id then return end
            State.MapRecorderCache[Part] = {}
            local props = {CFrame=true, Transparency=true, CanCollide=true, Anchored=true}
            for p, _ in pairs(props) do pcall(function() State.MapRecorderCache[Part][p] = Part[p] end) end
            
            table.insert(Recorders, Part.Changed:Connect(function(Prop)
                if not Recording or not props[Prop] then return end
                local New = Part[Prop]; local Old = State.MapRecorderCache[Part][Prop]
                if New ~= Old then
                    table.insert(State.MapEvents, {Time=os.clock()-StartTime, UUID=id, Prop=Prop, OldVal=Old, NewVal=New})
                    State.MapRecorderCache[Part][Prop] = New
                end
            end))
            table.insert(Recorders, Part.Destroying:Connect(function()
                if not Recording then return end
                table.insert(State.MapEvents, {Time=os.clock()-StartTime, UUID=id, Prop="Destroyed", OldVal=Serializer.DeepCopy(State.MapRecorderCache[Part]), NewVal=true})
            end))
        end
        for _, d in ipairs(LiveMap:GetDescendants()) do if d:IsA("BasePart") then Track(d) end end
        
        -- GODMODE & BUTTONS
        local Buttons = {}
        for _, v in pairs(LiveMap:GetDescendants()) do
             if v:IsA("Model") and Serializer.isRandomString(v.Name) then
                 local hb = v:FindFirstChild("Hitbox")
                 if not hb then for _,c in pairs(v:GetChildren()) do if c:IsA("BasePart") and tostring(c.BrickColor)~="Medium stone grey" then hb=c break end end end
                 if hb then hb.Name="Hitbox"; table.insert(Buttons, v) end
             end
        end
        UI.SendAlert("Farming " .. #Buttons .. " Buttons...", Color3.fromRGB(255, 170, 0))
        
        local Char = LocalPlayer.Character
        local Hum = Char:WaitForChild("Humanoid")
        local Root = Char:WaitForChild("HumanoidRootPart")
        
        local GodCon = Services.Run.RenderStepped:Connect(function() if Hum then Hum.Health = 99999 end end)
        for _,v in pairs(Char:GetChildren()) do if v:IsA("BasePart") then v.CanCollide=false end end
        
        -- FARM LOOP
        local LastBtn = nil
        while Recording and LiveMap.Parent and Hum.Health > 0 do
            Hum.Jump = true
            local Found = false
            for _, Btn in pairs(Buttons) do
                local HB = Btn:FindFirstChild("Hitbox")
                if HB and Btn:FindFirstChild("TouchInterest", true) then
                    Found = true
                    Root.CFrame = HB.CFrame
                    Root.Velocity = Vector3.zero
                    if Btn ~= LastBtn then
                         local id = Serializer.GetUUID(HB)
                         if id and not table.find(State.RecordedButtonSequence, id) then 
                             table.insert(State.RecordedButtonSequence, id)
                             State.ButtonPressTimings[id] = (os.clock()-StartTime) + LocalPlayer:GetNetworkPing()
                         end
                         LastBtn = Btn; task.wait(0.1)
                    end
                end
            end
            if not Found then Root.CFrame = CFrame.new(0, 1000, 0) end
            Services.Run.Heartbeat:Wait()
        end
        
        -- CLEANUP RECORDING
        Recording = false; GodCon:Disconnect(); for _,r in pairs(Recorders) do r:Disconnect() end
        if LiveMap then LiveMap:Destroy() end
        State.ClonedMap.Parent = workspace
        
        -- RESTORE
        State.MapUUIDs = {}
        for _, d in ipairs(State.ClonedMap:GetDescendants()) do
            local id = d:GetAttribute("TAS_UUID"); if id then State.MapUUIDs[id] = d end
        end
        for _, Ev in ipairs(State.MapEvents) do Ev.Instance = State.MapUUIDs[Ev.UUID] end
        
        -- RESPAWN & FREEZE
        LocalPlayer.Character:BreakJoints()
        UI.SendAlert("Respawning...", Color3.fromRGB(255, 255, 0))
        LocalPlayer.CharacterAdded:Wait()
        Char = LocalPlayer.Character
        task.wait(1)
        
        State.MapPos = State.ClonedMap.PrimaryPart.Position
        State.MapX, State.MapY, State.MapZ = State.MapPos.X, State.MapPos.Y, State.MapPos.Z
        
        Root = Char:WaitForChild("HumanoidRootPart")
        Char:WaitForChild("Humanoid").WalkSpeed = 0
        Root.CFrame = State.ClonedMap.PrimaryPart.CFrame + Vector3.new(0,5,0)
        task.wait(0.5)
        Root.Anchored = true
        Char.Humanoid.WalkSpeed = 20
        Char.Humanoid.JumpPower = 50
        
        -- START ENGINE
        State.RunStart = tick(); State.PauseStart = tick()
        Core.HookAnimations()
        UI.LoadUI(MapName)
        
        -- REGISTER BUTTONS TO UI
        State.ButtonRegistry = {}; local Checked = {}
        local function RegBtn(b)
            if not b or Checked[b] then return end; Checked[b]=true
            table.insert(State.TotalButtons, b)
            local sel = Instance.new("SelectionBox", b); sel.Color3 = Color3.fromRGB(255, 140, 0); sel.Adornee = b
            local id = Serializer.GetUUID(b)
            local ord = table.find(State.RecordedButtonSequence, id) or 999
            local dat = {IsPressed=false, SelectionBox=sel, Order=ord, RecordedTime=State.ButtonPressTimings[id]}
            State.ButtonRegistry[b] = dat
            State.OrderedButtonRegistry[ord] = dat
            b.Touched:Connect(function(h)
                if h.Parent==Char and not dat.IsPressed then
                     dat.IsPressed=true; dat.TruePressTime = tick()-State.RunStart-State.TimeOffset
                     UI.SendAlert("Button Pressed!", Color3.fromRGB(0,255,0))
                end
            end)
        end
        for _, v in pairs(State.ClonedMap:GetDescendants()) do
             if v:IsA("Model") and Serializer.isRandomString(v.Name) then RegBtn(v:FindFirstChild("Hitbox")) end
        end
        UI.SendAlert("Map Ready", Color3.fromRGB(0, 255, 0))
    end
    
    -- // 3. CONTROLS //
    function Core.TogglePause()
        if not LocalPlayer.Character then return end
        State.IsPaused = not State.IsPaused
        local Root = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not Root then return end
        
        if State.IsPaused then
            State.SavedVelocity = Root.Velocity; Root.Anchored = true; State.PauseStart = tick()
            UI.SendAlert("Paused", Color3.fromRGB(255, 255, 0))
        else
            Root.Anchored = false; Root.Velocity = State.SavedVelocity; State.TimeOffset = State.TimeOffset + tick() - State.PauseStart
            UI.SendAlert("Unpaused", Color3.fromRGB(0, 255, 0))
        end
    end
    
    function Core.LoadLastSavestate()
        if #State.Savestates == 0 then return UI.SendAlert("No States", Color3.fromRGB(255,0,0)) end
        local FramePacked = State.Savestates[#State.Savestates][#State.Savestates[#State.Savestates]]
        local Frame = Serializer.UnpackFrame(FramePacked)
        
        State.Frames = {}; State.IsPaused = true; State.PreviewOffset = 0
        local Root = LocalPlayer.Character.HumanoidRootPart
        Root.Anchored = true; Root.CFrame = Frame.CFrame + Vector3.new(State.MapX, State.MapY-1000, State.MapZ)
        Root.Velocity = Frame.Velocity; State.SavedVelocity = Frame.Velocity
        workspace.CurrentCamera.CFrame = Frame.CameraCFrame
        State.PauseStart = tick(); State.RunStart = tick() - Frame.Time; State.TimeOffset = 0
        Core.SyncButtonState(Frame.Time, Frame.Time); Core.UpdateMapState(Frame.Time)
        if State.OriginalPlayAnim then
            State.OriginalPlayAnim(Frame.Animation[1], Frame.Animation[2], LocalPlayer.Character.Humanoid)
        end
        UI.SendAlert("Loaded State", Color3.fromRGB(0, 255, 255))
    end
    
    -- // 4. LOOPS & BINDS //
    table.insert(TAS.Connections, Services.Run.Heartbeat:Connect(function(dt)
        if not getgenv().TAS_Active or not State.RunStart then return end
        Core.EnforceLighting()
        if not State.IsPaused then
            State.RecordAccumulator = State.RecordAccumulator + dt
            if State.RecordAccumulator >= State.RECORD_INTERVAL then
                State.RecordAccumulator = 0; table.insert(State.Frames, Serializer.CaptureFrameData())
            end
        end
        local RT = State.IsPaused and ((State.PauseStart or tick()) - State.RunStart - State.TimeOffset) or (tick() - State.RunStart - State.TimeOffset)
        if State.IsPreviewingForward then State.PreviewOffset = State.PreviewOffset + dt*5 end
        if State.IsPreviewingBackward then State.PreviewOffset = State.PreviewOffset - dt*5 end
        local VT = math.max(0, RT + State.PreviewOffset)
        Core.UpdateMapState(VT); Core.SyncButtonState(VT, RT); UI.UpdateDisplay()
    end))
    
    table.insert(TAS.Connections, Services.Input.InputBegan:Connect(function(i, g)
        if g then return end
        local k = i.KeyCode.Name
        if k == "CapsLock" then Core.TogglePause()
        elseif k == "One" then table.insert(State.Savestates, Serializer.DeepCopy(State.Frames)); State.Frames={}; UI.SendAlert("Saved State", Color3.fromRGB(0,255,0))
        elseif k == "Two" then table.remove(State.Savestates); UI.SendAlert("Removed State", Color3.fromRGB(255,0,0))
        elseif k == "Three" then task.spawn(Core.LoadLastSavestate)
        elseif k == "Six" then Serializer.SaveRun()
        elseif k == "Up" then State.IsPreviewingForward = true
        elseif k == "Down" then State.IsPreviewingBackward = true
        end
    end))
    
    table.insert(TAS.Connections, Services.Input.InputEnded:Connect(function(i)
        if i.KeyCode.Name == "Up" then State.IsPreviewingForward = false end
        if i.KeyCode.Name == "Down" then State.IsPreviewingBackward = false end
    end))

    -- // 5. STARTUP CHECK //
    task.spawn(function()
        print("TAS: Checking Game State...")
        local MP = workspace:WaitForChild("Multiplayer", 10)
        
        -- Check if map is ALREADY loaded
        if MP and MP:FindFirstChild("Map") then
             print("TAS: Map found immediately! Starting...")
             UI.SendAlert("Map found! Starting...", Color3.fromRGB(0,255,0))
             -- We need to wait for player to spawn if they just joined
             if not LocalPlayer.Character then LocalPlayer.CharacterAdded:Wait() end
             repeat task.wait(0.5) until LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
             Core.SetupMap()
        else
             print("TAS: Waiting for New Round...")
             UI.SendAlert("Waiting for next round...", Color3.fromRGB(255, 170, 0))
             MP:WaitForChild("NewMap", 9e9)
             MP:WaitForChild("Map", 9e9)
             repeat task.wait() until LocalPlayer.Character.HumanoidRootPart.Anchored == false
             Core.SetupMap()
        end
    end)
    
    return Core
end

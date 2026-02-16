return function(TAS)
    local Controller = {}
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer
    
    local State = TAS.Services.State
    local Engine = TAS.Services.MapEngine
    local UI = TAS.Services.Interface
    local Serializer = TAS.Services.Serializer
    
    local Keybinds = {
        AddSavestate = "One", RemoveSavestate = "Two", BackSavestate = "Three",
        GoFrameBack = "Four", GoFrameForward = "Five", SaveRun = "Six",
        UserPause = "CapsLock", CollisionToggler = "C", ResetToNormal = "Delete",
        EnvPause = "Equals", ToggleTimeReset = "Seven"
    }

    -- // ANIMATION HOOK //
    function Controller.HookAnimations()
        local char = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
        local script = char:WaitForChild("Animate", 10)
        if not script then return end
        
        repeat task.wait() until script and script.Parent
        
        local success, env = pcall(getsenv, script)
        if not success then return end
        
        State.AnimEnv = env
        if State.AnimEnv.playAnimation then
            State.OriginalPlayAnim = State.AnimEnv.playAnimation
            State.AnimEnv.playAnimation = function(anim, speed)
                if not State.IsPaused then
                    State.CurrentAnim = {anim, speed}
                    State.OriginalPlayAnim(State.CurrentAnim[1], State.CurrentAnim[2], LocalPlayer.Character.Humanoid)
                end
            end
        end
    end

    -- // ACTIONS //
    function Controller.TogglePause()
        if not LocalPlayer.Character then return end
        State.IsPaused = not State.IsPaused
        local Root = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if not Root then return end

        if State.IsPaused then
            State.SavedVelocity = Root.Velocity
            Root.Anchored = true
            State.PauseStart = tick()
            UI.SendAlert("Paused", Color3.fromRGB(255, 255, 0))
        else
            Root.Anchored = false
            Root.Velocity = State.SavedVelocity
            State.TimeOffset = State.TimeOffset + tick() - State.PauseStart
            State.RecordAccumulator = 0
            UI.SendAlert("Unpaused", Color3.fromRGB(0, 255, 0))
        end
    end
    
    function Controller.LoadLastSavestate()
        if #State.Savestates == 0 then 
            UI.SendAlert("No Savestates!", Color3.fromRGB(255, 0, 0))
            return 
        end
        
        local LastState = State.Savestates[#State.Savestates]
        if LastState then
            local FramePacked = LastState[#LastState]
            if not FramePacked then return end
            
            local Frame = Serializer.UnpackFrame(FramePacked)
            State.Frames = {}
            State.IsPaused = true
            State.PreviewOffset = 0
            
            local Root = LocalPlayer.Character.HumanoidRootPart
            Root.Anchored = true
            Root.CFrame = Frame.CFrame + Vector3.new(State.MapX, State.MapY - 1000, State.MapZ)
            Root.Velocity = Frame.Velocity
            State.SavedVelocity = Frame.Velocity
            
            workspace.CurrentCamera.CFrame = Frame.CameraCFrame
            State.PauseStart = tick()
            State.RunStart = tick() - Frame.Time
            State.TimeOffset = 0
            
            Engine.SyncButtonState(Frame.Time, Frame.Time)
            Engine.UpdateMapState(Frame.Time)
            
            if State.OriginalPlayAnim then
                State.OriginalPlayAnim(Frame.Animation[1], Frame.Animation[2], LocalPlayer.Character.Humanoid)
            end
            UI.SendAlert("Savestate Loaded", Color3.fromRGB(0, 255, 255))
        end
    end

    function Controller.AddSavestate()
        table.insert(State.Savestates, Serializer.DeepCopy(State.Frames))
        State.Frames = {}
        UI.SendAlert("Savestate Added", Color3.fromRGB(0, 255, 0))
    end
    
    -- // MAIN LOOP //
    local function Heartbeat(dt)
        if not getgenv().TAS_Active then return end
        if not State.RunStart then return end
        
        Engine.EnforceLighting()

        if not State.IsPaused then
            State.RecordAccumulator = State.RecordAccumulator + dt
            if State.RecordAccumulator >= State.RECORD_INTERVAL then
                State.RecordAccumulator = 0
                table.insert(State.Frames, Serializer.CaptureFrameData())
            end
        end

        local RealTime = 0
        if not State.IsPaused then RealTime = tick() - State.RunStart - State.TimeOffset
        else RealTime = (State.PauseStart or tick()) - State.RunStart - State.TimeOffset end
        
        if State.IsPreviewingForward then State.PreviewOffset = State.PreviewOffset + (dt * 5) end
        if State.IsPreviewingBackward then State.PreviewOffset = State.PreviewOffset - (dt * 5) end

        local VisualTime = RealTime + State.PreviewOffset
        if VisualTime < 0 then VisualTime = 0 end

        Engine.UpdateMapState(VisualTime)
        Engine.SyncButtonState(VisualTime, RealTime)
        UI.UpdateDisplay()
    end
    
    -- // INPUTS //
    local function InputBegan(input, gpe)
        if gpe then return end
        local k = input.KeyCode.Name
        if k == Keybinds.UserPause then Controller.TogglePause()
        elseif k == Keybinds.AddSavestate then Controller.AddSavestate()
        elseif k == Keybinds.BackSavestate then task.spawn(Controller.LoadLastSavestate)
        elseif k == Keybinds.SaveRun then Serializer.SaveRun()
        elseif k == "Up" then State.IsPreviewingForward = true
        elseif k == "Down" then State.IsPreviewingBackward = true
        end
    end
    
    local function InputEnded(input, gpe)
        if gpe then return end
        if input.KeyCode.Name == "Up" then State.IsPreviewingForward = false end
        if input.KeyCode.Name == "Down" then State.IsPreviewingBackward = false end
    end

    -- // INIT & STARTUP SEQUENCE //
    table.insert(TAS.Connections, RunService.Heartbeat:Connect(Heartbeat))
    table.insert(TAS.Connections, UserInputService.InputBegan:Connect(InputBegan))
    table.insert(TAS.Connections, UserInputService.InputEnded:Connect(InputEnded))
    
    -- The Main Thread that waits for the game to start
    task.spawn(function()
        UI.SendAlert("TAS Active: Waiting for Game...", Color3.fromRGB(255, 170, 0))
        print("[TAS] Waiting for Multiplayer folder...")
        
        local MP = workspace:WaitForChild("Multiplayer", 10)
        if not MP then warn("[TAS] Multiplayer folder not found!"); return end

        print("[TAS] Waiting for NewMap...")
        MP:WaitForChild("NewMap", 9e9) -- Infinite wait until map loads
        
        print("[TAS] Waiting for Map rename...")
        MP:WaitForChild("Map", 9e9) -- Infinite wait until map is ready
        
        print("[TAS] Waiting for Player Unanchor...")
        repeat 
            task.wait(0.1)
            if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
                if not LocalPlayer.Character.HumanoidRootPart.Anchored then break end
            end
        until false
        
        print("[TAS] Game Started! Initializing Engine...")
        Engine.SetupMap()
    end)
    
    return Controller
end

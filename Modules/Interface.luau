return function(TAS)
    local Interface = {}
    
    -- // DEPENDENCIES //
    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer
    local RunService = game:GetService("RunService")
    
    -- // CONFIG //
    local UI_API_URL = "https://raw.githubusercontent.com/tomatotxt/Flood-GUI/refs/heads/testing/TAS/CREATOR/uiapi.luau"
    
    -- // INTERNAL VARIABLES //
    local UI_Lib = nil
    local UI_Elements = nil
    local NewAlert = nil -- The game's native alert function
    
    -- // 1. ALERT SYSTEM HOOK //
    local function SetupAlerts()
        local GameScript = LocalPlayer.PlayerScripts:WaitForChild("CL_MAIN_GameScript", 5)
        if GameScript then
            local success, env = pcall(getsenv, GameScript)
            if success and env.newAlert then 
                NewAlert = env.newAlert 
            end
        end
    end
    SetupAlerts()

    function Interface.SendAlert(msg, color)
        if NewAlert then
            pcall(function() NewAlert(msg, color, 1.5, nil) end)
        else
            -- Retry finding it if it wasn't there initially
            SetupAlerts() 
            if NewAlert then
                pcall(function() NewAlert(msg, color, 1.5, nil) end)
            else
                -- Fallback to console/warn if game script is inaccessible
                -- This prevents the script from breaking if alerts fail
                warn("[TAS ALERT]: " .. tostring(msg)) 
            end
        end
    end

    -- // 2. GUI MANAGEMENT //
    function Interface.Create(MapName)
        -- Cleanup existing UI if present
        Interface.Destroy()
        
        -- Load external library if not already loaded
        if not UI_Lib then
            local success, res = pcall(function() return loadstring(game:HttpGet(UI_API_URL))() end)
            if success then
                UI_Lib = res
            else
                warn("[TAS] Failed to load UI API from URL")
                Interface.SendAlert("Failed to load UI API", Color3.fromRGB(255, 0, 0))
                return
            end
        end

        UI_Elements = UI_Lib.Create()
        
        -- Set Initial Map Name
        if UI_Elements.MapEventInfo then 
            UI_Elements.MapEventInfo.Text = MapName or "Unknown Map" 
        end
        
        Interface.SendAlert("TAS UI Initialized", Color3.fromRGB(0, 255, 255))
    end

    function Interface.Destroy()
        if UI_Elements and UI_Elements.ScreenGui then
            UI_Elements.ScreenGui:Destroy()
            UI_Elements = nil
        end
    end

    -- // 3. UPDATE LOOP //
    function Interface.UpdateDisplay()
        if not UI_Elements then return end
        
        -- Pull state dynamically
        local State = TAS.Services.State
        if not State then return end
        
        -- Calculate Visual Time
        local RealTime = 0
        if not State.IsPaused then 
            RealTime = tick() - State.RunStart - State.TimeOffset
        else 
            RealTime = (State.PauseStart or tick()) - State.RunStart - State.TimeOffset 
        end
        
        local VisualTime = RealTime + State.PreviewOffset
        if VisualTime < 0 then VisualTime = 0 end

        -- Update Time Text
        if UI_Elements.TimeText then
            local m = math.floor(VisualTime / 60)
            local s = math.floor(VisualTime % 60)
            local ms = math.floor(VisualTime * 1000 % 1000)
            UI_Elements.TimeText.Text = string.format("%d:%02d.%03d", m, s, ms)
            
            -- Color Logic (Sync Status)
            if State.PreviewOffset > 0.1 then 
                UI_Elements.TimeText.TextColor3 = Color3.fromRGB(0, 255, 0) -- Forward/Fast
            elseif State.PreviewOffset < -0.1 then 
                UI_Elements.TimeText.TextColor3 = Color3.fromRGB(255, 0, 0) -- Backward/Lag
            else 
                if State.IsPaused then 
                    UI_Elements.TimeText.TextColor3 = Color3.fromRGB(255, 255, 0) -- Paused
                else 
                    UI_Elements.TimeText.TextColor3 = Color3.fromRGB(255, 255, 255) -- Normal
                end
            end
        end

        -- Update Counts
        if UI_Elements.FrameCount then 
            UI_Elements.FrameCount.Text = "Frames: " .. tostring(#State.Frames) 
        end
        
        if UI_Elements.SavestatesCount then 
            UI_Elements.SavestatesCount.Text = "States: " .. tostring(#State.Savestates) 
        end

        -- Update Status Label
        if UI_Elements.StatusText then
            if State.IsPaused then
                UI_Elements.StatusText.Text = "PAUSED"
                UI_Elements.StatusText.TextColor3 = Color3.fromRGB(255, 200, 80)
            else
                UI_Elements.StatusText.Text = "PLAYING"
                UI_Elements.StatusText.TextColor3 = Color3.fromRGB(255, 255, 255)
            end
        end
    end

    return Interface
end

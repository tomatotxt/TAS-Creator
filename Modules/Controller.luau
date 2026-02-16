-- // Modules/Controller.luau //
return function(TAS)
    local Controller = {}
    local RunService = game:GetService("RunService")
    local UserInputService = game:GetService("UserInputService")
    
    local State = TAS.Services.State
    local Engine = TAS.Services.MapEngine
    local UI = TAS.Services.Interface
    local Serializer = TAS.Services.Serializer

    -- Main Loop
    local function Heartbeat(dt)
        if not getgenv().TAS_Active then return end
        
        -- Logic using other modules
        if not State.IsPaused then
            local data = TAS.Services.Utils.CaptureFrameData() -- You'd move CaptureFrameData to Utils
            table.insert(State.Frames, data)
        end
        
        Engine.UpdateMapState(VisualTime)
        UI.UpdateDisplay(VisualTime)
    end

    -- Hook inputs
    local function InputBegan(input, gpe)
        if input.KeyCode.Name == "C" then
            State.IsPaused = not State.IsPaused
            -- Handle Pause Logic
        end
    end

    -- Register connections so the Loader can clean them up
    table.insert(TAS.Connections, RunService.Heartbeat:Connect(Heartbeat))
    table.insert(TAS.Connections, UserInputService.InputBegan:Connect(InputBegan))

    return Controller
end

return function(TAS)
    local Interface = {}
    local Players = game:GetService("Players")
    local LocalPlayer = Players.LocalPlayer
    local TweenService = game:GetService("TweenService")
    
    -- // ALERT SYSTEM //
    local NewAlert = nil
    local function SetupAlerts()
        local GameScript = LocalPlayer.PlayerScripts:WaitForChild("CL_MAIN_GameScript", 5)
        if GameScript then
            local success, env = pcall(getsenv, GameScript)
            if success and env.newAlert then NewAlert = env.newAlert end
        end
    end
    SetupAlerts()

    function Interface.SendAlert(msg, color)
        if NewAlert then
            pcall(function() NewAlert(msg, color, 1.5, nil) end)
        else
            SetupAlerts()
            if NewAlert then pcall(function() NewAlert(msg, color, 1.5, nil) end)
            else warn("[TAS ALERT] " .. tostring(msg)) end
        end
    end
    
    Interface.SendAlert("TAS Creator Initialized", Color3.fromRGB(183, 0, 255))

    -- // UI LIBRARY (EMBEDDED) //
    local TAS_UI = {}
    local THEME = {
        Background = Color3.fromRGB(25, 25, 30), Stroke = Color3.fromRGB(60, 60, 70),
        TextMain = Color3.fromRGB(240, 240, 240), TextDim = Color3.fromRGB(180, 180, 180),
        Accent = Color3.fromRGB(85, 170, 255), Alert = Color3.fromRGB(255, 200, 80),
    }

    function TAS_UI.Create()
        for _, v in pairs(game:GetService("CoreGui"):GetChildren()) do
            if v.Name == "TAS_HUD" then v:Destroy() end
        end
        
        local ScreenGui = Instance.new("ScreenGui")
        ScreenGui.Name = "TAS_HUD"
        ScreenGui.Parent = game:GetService("CoreGui")
        ScreenGui.ResetOnSpawn = false
        
        local Container = Instance.new("Frame")
        Container.Name = "LayoutContainer"
        Container.Parent = ScreenGui
        Container.BackgroundTransparency = 1
        Container.AnchorPoint = Vector2.new(0.5, 1) 
        Container.Position = UDim2.new(0.5, 0, 0.95, 0)
        Container.AutomaticSize = Enum.AutomaticSize.XY 
        
        local Layout = Instance.new("UIListLayout")
        Layout.Parent = Container
        Layout.FillDirection = Enum.FillDirection.Horizontal
        Layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
        Layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
        Layout.Padding = UDim.new(0, 15)

        local StatsPanel = Instance.new("Frame")
        StatsPanel.Name = "StatsPanel"
        StatsPanel.Parent = Container
        StatsPanel.BackgroundColor3 = THEME.Background
        StatsPanel.BackgroundTransparency = 0.15
        StatsPanel.LayoutOrder = 1
        StatsPanel.Size = UDim2.new(0, 360, 0, 85)
        
        local PCorner = Instance.new("UICorner"); PCorner.CornerRadius = UDim.new(0, 12); PCorner.Parent = StatsPanel
        local PStroke = Instance.new("UIStroke"); PStroke.Color = THEME.Stroke; PStroke.Thickness = 1.5; PStroke.Parent = StatsPanel
        
        local KBFrame = Instance.new("Frame")
        KBFrame.Name = "KeybindFrame"
        KBFrame.Parent = Container
        KBFrame.BackgroundColor3 = THEME.Background
        KBFrame.BackgroundTransparency = 0.1
        KBFrame.LayoutOrder = 2
        KBFrame.Size = UDim2.new(0, 240, 0, 390)
        KBFrame.Visible = false
        KBFrame.ClipsDescendants = true
        
        local KBFCorner = Instance.new("UICorner"); KBFCorner.CornerRadius = UDim.new(0, 10); KBFCorner.Parent = KBFrame
        local KBFStroke = Instance.new("UIStroke"); KBFStroke.Color = THEME.Accent; KBFStroke.Transparency = 0.5; KBFStroke.Parent = KBFrame

        local TimeText = Instance.new("TextLabel"); TimeText.Parent = StatsPanel; TimeText.BackgroundTransparency=1
        TimeText.Position = UDim2.new(0.05, 0, 0.1, 0); TimeText.Size = UDim2.new(0.5, 0, 0.5, 0)
        TimeText.Font = Enum.Font.Highway; TimeText.Text = "0:00.000"; TimeText.TextColor3 = THEME.TextMain; TimeText.TextScaled = true; TimeText.TextXAlignment = Enum.TextXAlignment.Left

        local function CreateLabel(n, y)
            local L = Instance.new("TextLabel"); L.Parent = StatsPanel; L.BackgroundTransparency=1
            L.Position = UDim2.new(0.6, 0, y, 0); L.Size = UDim2.new(0.35, 0, 0.2, 0)
            L.Font = Enum.Font.Highway; L.Text = n; L.TextColor3 = THEME.TextDim; L.TextScaled=true; L.TextXAlignment=Enum.TextXAlignment.Right
            return L
        end
        local SavestatesCount = CreateLabel("Savestates 0", 0.15)
        local FrameCount = CreateLabel("Frames 0", 0.38)
        
        local MapEventInfo = Instance.new("TextLabel"); MapEventInfo.Parent = StatsPanel; MapEventInfo.BackgroundTransparency=1
        MapEventInfo.Position = UDim2.new(0.05, 0, 0.65, 0); MapEventInfo.Size = UDim2.new(0.5, 0, 0.25, 0)
        MapEventInfo.Font = Enum.Font.GothamBold; MapEventInfo.Text = "Map: Waiting..."; MapEventInfo.TextColor3 = THEME.Accent; MapEventInfo.TextScaled=true; MapEventInfo.TextXAlignment=Enum.TextXAlignment.Left

        local StatusBadge = Instance.new("TextLabel"); StatusBadge.Parent = StatsPanel; StatusBadge.BackgroundTransparency=1
        StatusBadge.Position = UDim2.new(0.4, 0, 0.15, 0); StatusBadge.Size = UDim2.new(0.15, 0, 0.15, 0)
        StatusBadge.Font = Enum.Font.GothamMedium; StatusBadge.Text = "PAUSED"; StatusBadge.TextColor3 = THEME.Alert; StatusBadge.TextScaled=true; StatusBadge.TextXAlignment=Enum.TextXAlignment.Left

        local KBBtn = Instance.new("TextButton"); KBBtn.Parent = StatsPanel; KBBtn.BackgroundColor3 = Color3.fromRGB(40,40,45)
        KBBtn.Position = UDim2.new(0.6, 0, 0.65, 0); KBBtn.Size = UDim2.new(0.35, 0, 0.25, 0)
        KBBtn.Font = Enum.Font.GothamBold; KBBtn.Text = "Controls"; KBBtn.TextColor3 = THEME.TextMain; KBBtn.TextSize = 14
        Instance.new("UICorner", KBBtn).CornerRadius = UDim.new(0,6)
        
        local KBList = Instance.new("UIListLayout"); KBList.Parent = KBFrame; KBList.SortOrder = Enum.SortOrder.LayoutOrder; KBList.Padding = UDim.new(0,4); KBList.HorizontalAlignment=Enum.HorizontalAlignment.Center
        local KBPadding = Instance.new("UIPadding"); KBPadding.Parent = KBFrame; KBPadding.PaddingTop=UDim.new(0,10)
        
        local function AddRow(k, a, o)
            local R = Instance.new("Frame"); R.BackgroundTransparency=1; R.Size=UDim2.new(1,0,0,20); R.LayoutOrder=o; R.Parent=KBFrame
            local K = Instance.new("TextLabel"); K.Parent=R; K.BackgroundTransparency=1; K.Size=UDim2.new(0.4,0,1,0); K.Font=Enum.Font.GothamBold; K.Text=k; K.TextColor3=THEME.Accent; K.TextSize=12
            local A = Instance.new("TextLabel"); A.Parent=R; A.BackgroundTransparency=1; A.Size=UDim2.new(0.6,0,1,0); A.Position=UDim2.new(0.4,0,0,0); A.Font=Enum.Font.Gotham; A.Text=a; A.TextColor3=THEME.TextMain; A.TextSize=12; A.TextXAlignment=Enum.TextXAlignment.Right
        end
        AddRow("CAPSLOCK", "Pause/Unpause", 1); AddRow("1/2/3", "States: Add/Rem/Load", 2); AddRow("4/5", "Frame Step", 3); AddRow("6", "Save Run", 4); AddRow("0", "View TAS", 5); AddRow("C", "Collision", 6); AddRow("UP/DOWN", "Time Travel", 7); AddRow("DEL", "Destroy UI", 8)
        
        local open = false
        KBBtn.Activated:Connect(function()
            open = not open
            KBFrame.Visible = open
            KBBtn.Text = open and "Hide" or "Controls"
        end)
        
        return { ScreenGui = ScreenGui, TimeText = TimeText, SavestatesCount = SavestatesCount, FrameCount = FrameCount, StatusText = StatusBadge, MapEventInfo = MapEventInfo }
    end

    -- // UI INTERFACE METHODS //
    local UI_Elements = nil
    
    function Interface.LoadUI(MapName)
        UI_Elements = TAS_UI.Create()
        if MapName then UI_Elements.MapEventInfo.Text = MapName end
    end
    
    function Interface.UpdateDisplay()
        if not UI_Elements then return end
        local State = TAS.Services.State
        
        local RealTime = 0
        if not State.IsPaused then RealTime = tick() - State.RunStart - State.TimeOffset
        else RealTime = (State.PauseStart or tick()) - State.RunStart - State.TimeOffset end
        
        local VisualTime = RealTime + State.PreviewOffset
        if VisualTime < 0 then VisualTime = 0 end
        
        local m = math.floor(VisualTime / 60)
        local s = math.floor(VisualTime % 60)
        local ms = math.floor(VisualTime * 1000 % 1000)
        UI_Elements.TimeText.Text = string.format("%d:%02d.%03d", m, s, ms)
        
        if State.PreviewOffset > 0.1 then UI_Elements.TimeText.TextColor3 = Color3.fromRGB(0, 255, 0)
        elseif State.PreviewOffset < -0.1 then UI_Elements.TimeText.TextColor3 = Color3.fromRGB(255, 0, 0)
        else UI_Elements.TimeText.TextColor3 = State.IsPaused and Color3.fromRGB(255, 255, 0) or Color3.fromRGB(255, 255, 255) end
        
        UI_Elements.FrameCount.Text = "Frames: " .. #State.Frames
        UI_Elements.SavestatesCount.Text = "States: " .. #State.Savestates
        UI_Elements.StatusText.Text = State.IsPaused and "PAUSED" or "PLAYING"
        UI_Elements.StatusText.TextColor3 = State.IsPaused and Color3.fromRGB(255, 200, 80) or Color3.fromRGB(255, 255, 255)
    end
    
    function Interface.Destroy() if UI_Elements then UI_Elements.ScreenGui:Destroy() end end

    return Interface
end

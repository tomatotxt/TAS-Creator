--[[
	TAS Recorder Enhanced (CameraType Removed)
	- Playback: Unanchored + Zero Velocity.
	- Camera: Default Behavior (Scriptable mode removed).
	- Animation: Gatekeeper Hook.
	- Recording: 60 FPS Cap.
]]

--// PREVENT DUPLICATES //--
if getgenv().TAS_Recorder_Running then
	pcall(function() getgenv().TAS_Recorder_Disconnect() end)
	wait(0.2)
end
getgenv().TAS_Recorder_Running = true

--// SERVICES //--
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")
local MarketplaceService = game:GetService("MarketplaceService")

--// LOCAL PLAYER //--
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

--// UTILS //--
local function round(num)
	return math.floor(num * 1000 + 0.5) / 1000
end

--// ANIMATION SYSTEM (GATEKEEPER) //--
local AnimateEnv
local OriginalPlayAnim
local FrameAnimBuffer = {} 

-- State Flags
getgenv().TAS_IsRecording = false 
getgenv().TAS_IsPlaying = false 

local function SetupAnimationHook()
	local Char = LocalPlayer.Character
	if not Char then return end
	
	local AnimateScript = Char:WaitForChild("Animate", 10)
	if not AnimateScript then return end

	task.wait(0.2)

	AnimateEnv = nil
	OriginalPlayAnim = nil

	local SuccessHook, Err = pcall(function()
		AnimateEnv = getsenv(AnimateScript)
		OriginalPlayAnim = AnimateEnv.playAnimation
		
		-- [[ THE GATEKEEPER HOOK ]]
		AnimateEnv.playAnimation = function(...)
			local args = {...}
			
			-- 1. RECORDING MODE
			if getgenv().TAS_IsRecording then
				pcall(function()
					local name = args[1]
					local fade = args[2]
					if type(name) == "string" then
						table.insert(FrameAnimBuffer, {N = name, F = fade})
					end
				end)
				return OriginalPlayAnim(...)
			
			-- 2. PLAYBACK MODE (Block Game Script)
			elseif getgenv().TAS_IsPlaying then
				return 
				
			-- 3. NORMAL MODE
			else
				if OriginalPlayAnim then
					return OriginalPlayAnim(...)
				end
			end
		end
	end)

	if not SuccessHook then
		warn("TAS Warning: Could not hook Animate script.")
	end
end

local function PlayRecordedAnim(animName, transitionTime)
	if AnimateEnv and OriginalPlayAnim and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
		pcall(function()
			OriginalPlayAnim(animName, transitionTime, LocalPlayer.Character.Humanoid)
		end)
	end
end

--// CONFIGURATION //--
local Keybinds = {
	AddSavestate    = Enum.KeyCode.One,
	RemoveSavestate = Enum.KeyCode.Two,
	EnterSavestate  = Enum.KeyCode.Three,
	BackSavestate   = Enum.KeyCode.Eight,
	GoFrameBack     = Enum.KeyCode.R,
	GoFrameForward  = Enum.KeyCode.F,
	GoBack          = Enum.KeyCode.Four,
	GoForward       = Enum.KeyCode.Five,
	SaveRun         = Enum.KeyCode.Six,
	UserPause       = Enum.KeyCode.CapsLock,
	CollisionToggler= Enum.KeyCode.C,
	ResetToNormal   = Enum.KeyCode.Delete,
	ViewTAS         = Enum.KeyCode.Zero,
	LoadRun         = Enum.KeyCode.Minus,
	DebugToggler    = Enum.KeyCode.V
}

--// VARIABLES //--
local Savestates = {}
local PlayerInfo = {}
local TimePaused = 0
local Pause = true
local ViewingTAS = false
local TimePauseHolder
local TimeStart
local DebugView = false
local OriginalVisuals = {} 
local LastRecordTime = 0 

--// GUI OBJECTS //--
local HUD
local FrameCountLabel, SavestatesCountLabel, TimeTextLabel, TASNameBox, CapLockPauseLabel, KeyBindFrame, MainFrame

--// CONNECTIONS //--
local Connections = {}
local CharConnections = {} 

--// HELPER FUNCTIONS //--

local function notify(text, title, dur)
	StarterGui:SetCore("SendNotification", {Title = title or "TAS Recorder", Text = text or "", Duration = dur or 3})
end

local function makeDraggable(guiObject)
	local dragging, dragInput, dragStart, startPos
	local function update(input)
		local delta = input.Position - dragStart
		guiObject.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
	guiObject.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true; dragStart = input.Position; startPos = guiObject.Position
			input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
		end
	end)
	guiObject.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
	end)
	UserInputService.InputChanged:Connect(function(input) if input == dragInput and dragging then update(input) end end)
end

local function updateStatusColor()
	if not MainFrame then return end
	if ViewingTAS then MainFrame.BorderColor3 = Color3.fromRGB(0, 255, 100)
	elseif Pause then MainFrame.BorderColor3 = Color3.fromRGB(255, 200, 0)
	else MainFrame.BorderColor3 = Color3.fromRGB(255, 50, 50) end
end

--// DEBUG VIEW LOGIC //--

local function ToggleDebugView()
	DebugView = not DebugView
	if DebugView then
		notify("Debug View: Enabled", "TAS Tools")
		OriginalVisuals = {}
		for _, v in ipairs(workspace:GetDescendants()) do
			if v:IsA("BasePart") and not v:IsDescendantOf(LocalPlayer.Character) then
				OriginalVisuals[v] = {Color = v.Color, Transparency = v.Transparency}
				local shade = math.random(30, 90) / 100
				v.Color = Color3.new(shade, shade, shade)
				if v.Transparency == 1 then v.Transparency = 0.5 end
				if v.CanCollide == false then v.Transparency = 0.9 end
				if v:FindFirstChild("TouchInterest") then v.Color = Color3.new(1, 0, 0); v.Transparency = 0 end
				if math.min(v.Size.X, v.Size.Y, v.Size.Z) <= 1.1 and not v:FindFirstChild("TouchInterest") then v.Color = Color3.fromRGB(0, 255, 255) end
			end
		end
	else
		notify("Debug View: Disabled", "TAS Tools")
		for part, props in pairs(OriginalVisuals) do
			if part and part.Parent then part.Color = props.Color; part.Transparency = props.Transparency end
		end
		OriginalVisuals = {}
	end
end

--// DATA CAPTURE //--

local function getCurrentCFrame()
	return (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")) and LocalPlayer.Character.HumanoidRootPart.CFrame or CFrame.new()
end

local function getCurrentVelocity()
	return (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")) and LocalPlayer.Character.HumanoidRootPart.Velocity or Vector3.new()
end

local function getCurrentCameraCFrame()
	return Workspace.CurrentCamera.CFrame
end

local function ReturnPlayerInfo(animEvents)
	local cf = getCurrentCFrame()
	local camCf = getCurrentCameraCFrame()
	local vel = getCurrentVelocity()
	
	local cfComps = {cf:GetComponents()}
	for i = 1, #cfComps do cfComps[i] = round(cfComps[i]) end
	
	local camComps = {camCf:GetComponents()}
	for i = 1, #camComps do camComps[i] = round(camComps[i]) end

	local frameData = {
		CF = cfComps,
		CCF = camComps,
		V = {round(vel.X), round(vel.Y), round(vel.Z)},
		T = round(tick() - TimeStart - TimePaused)
	}

	if animEvents and #animEvents > 0 then
		frameData.AE = animEvents
	end

	return frameData
end

--// GUI SETUP //--

local function UpdateGUIText()
	if SavestatesCountLabel then SavestatesCountLabel.Text = "Savestates: " .. #Savestates end
	if FrameCountLabel then FrameCountLabel.Text = "Frames: " .. #PlayerInfo end
end

local function FormatTime(TimeValue)
	local m = math.floor(TimeValue / 60)
	local s = math.floor(TimeValue % 60)
	local ms = math.floor((TimeValue * 1000) % 1000)
	return string.format("%d:%02d.%03d", m, s, ms)
end

local function UpdateTimeGUI()
	if TimeTextLabel then
		local TimePlayed = tick() - TimeStart - TimePaused
		TimeTextLabel.Text = FormatTime(TimePlayed)
	end
end

local function SetUpGui()
	if HUD then HUD:Destroy() end

	HUD = Instance.new("ScreenGui", LocalPlayer.PlayerGui)
	HUD.Name = "TASRecorderGUI"
	HUD.ResetOnSpawn = false
	HUD.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	MainFrame = Instance.new("Frame", HUD)
	MainFrame.AnchorPoint = Vector2.new(0.5, 1)
	MainFrame.Position = UDim2.new(0.5, 0, 0.9, 0)
	MainFrame.Size = UDim2.new(0, 260, 0, 130)
	MainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	MainFrame.BackgroundTransparency = 0.2
	MainFrame.BorderColor3 = Color3.fromRGB(200, 200, 200)
	MainFrame.BorderSizePixel = 2
	makeDraggable(MainFrame)

	local UIListLayout = Instance.new("UIListLayout", MainFrame)
	UIListLayout.Padding = UDim.new(0, 4)
	UIListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	UIListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center

	local Spacer = Instance.new("Frame", MainFrame)
	Spacer.Size = UDim2.new(1,0,0,2)
	Spacer.BackgroundTransparency = 1
	Spacer.LayoutOrder = 0

	TimeTextLabel = Instance.new("TextLabel", MainFrame)
	TimeTextLabel.LayoutOrder = 1
	TimeTextLabel.Size = UDim2.new(0.9, 0, 0, 25)
	TimeTextLabel.BackgroundTransparency = 1
	TimeTextLabel.Font = Enum.Font.RobotoMono
	TimeTextLabel.Text = "0:00.000"
	TimeTextLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	TimeTextLabel.TextScaled = true

	SavestatesCountLabel = Instance.new("TextLabel", MainFrame)
	SavestatesCountLabel.LayoutOrder = 2
	SavestatesCountLabel.Size = UDim2.new(0.9, 0, 0, 15)
	SavestatesCountLabel.BackgroundTransparency = 1
	SavestatesCountLabel.Font = Enum.Font.SourceSans
	SavestatesCountLabel.Text = "Savestates: 0"
	SavestatesCountLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	SavestatesCountLabel.TextScaled = true

	FrameCountLabel = Instance.new("TextLabel", MainFrame)
	FrameCountLabel.LayoutOrder = 3
	FrameCountLabel.Size = UDim2.new(0.9, 0, 0, 15)
	FrameCountLabel.BackgroundTransparency = 1
	FrameCountLabel.Font = Enum.Font.SourceSans
	FrameCountLabel.Text = "Frames: 0"
	FrameCountLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	FrameCountLabel.TextScaled = true

	TASNameBox = Instance.new("TextBox", MainFrame)
	TASNameBox.LayoutOrder = 4
	TASNameBox.Size = UDim2.new(0.9, 0, 0, 20)
	TASNameBox.BackgroundColor3 = Color3.fromRGB(50,50,50)
	TASNameBox.BackgroundTransparency = 0.5
	TASNameBox.Font = Enum.Font.SourceSans
	TASNameBox.PlaceholderText = "File Name (e.g. Run1)"
	TASNameBox.Text = ""
	TASNameBox.TextColor3 = Color3.fromRGB(255, 255, 255)
	TASNameBox.TextSize = 14

	local KeybindsButton = Instance.new("TextButton", MainFrame)
	KeybindsButton.LayoutOrder = 5
	KeybindsButton.Size = UDim2.new(0.9, 0, 0, 20)
	KeybindsButton.BackgroundColor3 = Color3.fromRGB(80, 80, 80)
	KeybindsButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	KeybindsButton.Text = "Toggle Keybinds"
	KeybindsButton.Font = Enum.Font.SourceSansBold
	KeybindsButton.TextSize = 14

	KeyBindFrame = Instance.new("Frame", HUD)
	KeyBindFrame.AnchorPoint = Vector2.new(0.5, 1)
	KeyBindFrame.Position = UDim2.new(0.5, 0, 0.9, -140)
	KeyBindFrame.Size = UDim2.new(0, 320, 0, 320)
	KeyBindFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	KeyBindFrame.BackgroundTransparency = 0.2
	KeyBindFrame.BorderColor3 = Color3.fromRGB(200, 200, 200)
	KeyBindFrame.Visible = false
	makeDraggable(KeyBindFrame)

	local KBLayout = Instance.new("UIListLayout", KeyBindFrame)
	KBLayout.Padding = UDim.new(0, 2)
	KBLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	KBLayout.SortOrder = Enum.SortOrder.LayoutOrder

	local function AddKeyLabel(keyName, actionName)
		local l = Instance.new("TextLabel", KeyBindFrame)
		l.Size = UDim2.new(1, -10, 0, 20)
		l.BackgroundTransparency = 1
		l.Font = Enum.Font.SourceSansBold
		l.Text = keyName .. " : " .. actionName
		l.TextColor3 = Color3.fromRGB(230, 230, 230)
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextSize = 16
		return l
	end

	local kbSpacer = Instance.new("Frame", KeyBindFrame)
	kbSpacer.BackgroundTransparency = 1
	kbSpacer.Size = UDim2.new(1,0,0,5)

	CapLockPauseLabel = AddKeyLabel(Keybinds.UserPause.Name, "Pause/Unpause")
	CapLockPauseLabel.TextColor3 = Color3.fromRGB(255, 255, 0)
	AddKeyLabel(Keybinds.AddSavestate.Name, "Add Savestate")
	AddKeyLabel(Keybinds.RemoveSavestate.Name, "Remove Savestate")
	AddKeyLabel(Keybinds.EnterSavestate.Name, "Enter Last Savestate (Edit)")
	AddKeyLabel(Keybinds.BackSavestate.Name, "Load Last Savestate")
	AddKeyLabel(Keybinds.GoFrameBack.Name, "-1 Frame")
	AddKeyLabel(Keybinds.GoFrameForward.Name, "+1 Frame")
	AddKeyLabel(Keybinds.SaveRun.Name, "Save JSON")
	AddKeyLabel(Keybinds.CollisionToggler.Name, "Toggle Collision")
	AddKeyLabel(Keybinds.DebugToggler.Name, "Debug View (Colors)")
	AddKeyLabel(Keybinds.ViewTAS.Name, "Playback TAS")
	AddKeyLabel(Keybinds.LoadRun.Name, "Load JSON")
	AddKeyLabel(Keybinds.ResetToNormal.Name, "STOP SCRIPT")

	KeybindsButton.MouseButton1Click:Connect(function()
		KeyBindFrame.Visible = not KeyBindFrame.Visible
	end)
end

--// STATE MANAGEMENT //--

local function SetCharacterState(InfoState)
	if not LocalPlayer.Character then return end
	local Root = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not Root then return end

	-- Decompress
	local charCF = CFrame.new(unpack(InfoState.CF))
	local camCF = CFrame.new(unpack(InfoState.CCF))
	local vel = Vector3.new(unpack(InfoState.V))

	Root.CFrame = charCF
	Root.Velocity = vel
	Root.RotVelocity = Vector3.new()
	Workspace.CurrentCamera.CFrame = camCF
end

local function UserPauseToggle()
	if ViewingTAS then return end
	Pause = not Pause
	getgenv().TAS_IsRecording = not Pause
	
	local Root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if Root then
		Root.Anchored = Pause
	end

	if Pause then
		TimePauseHolder = tick()
		if TimeTextLabel then TimeTextLabel.TextColor3 = Color3.fromRGB(255, 255, 0) end
	else
		if TimePauseHolder then
			TimePaused = TimePaused + (tick() - TimePauseHolder)
			TimePauseHolder = nil
		end
		if TimeTextLabel then TimeTextLabel.TextColor3 = Color3.fromRGB(255, 255, 255) end
	end
	updateStatusColor()
end

--// RECORDING FUNCTIONS //--

local function AddSavestate()
	local CurrentPlayerInfoCopy = HttpService:JSONDecode(HttpService:JSONEncode(PlayerInfo))
	table.insert(Savestates, CurrentPlayerInfoCopy)
	PlayerInfo = {}
	UpdateGUIText()
	notify("Savestate Added", "TAS", 1)
end

local function RemoveSavestate()
	if #Savestates > 1 then
		table.remove(Savestates)
		local lastSegment = Savestates[#Savestates]
		if lastSegment and #lastSegment > 0 then
			local lastFrame = lastSegment[#lastSegment]
			PlayerInfo = {}
			Pause = true
			getgenv().TAS_IsRecording = false
			TimePauseHolder = tick()
			TimeStart = tick() - lastFrame.T
			TimePaused = 0
			SetCharacterState(lastFrame)
			UpdateTimeGUI()
		end
		UpdateGUIText()
		notify("Savestate Removed", "TAS", 1)
	else
		notify("Cannot remove initial state", "TAS", 1)
	end
	updateStatusColor()
end

local function EnterSavestate()
	if #Savestates > 0 then
		local lastSegment = table.remove(Savestates)
		PlayerInfo = lastSegment
		local lastFrame = PlayerInfo[#PlayerInfo]
		if lastFrame then
			Pause = true
			getgenv().TAS_IsRecording = false
			SetCharacterState(lastFrame)
			TimePaused = 0
			TimeStart = tick() - lastFrame.T
			UpdateGUIText()
			UpdateTimeGUI()
			updateStatusColor()
			notify("Entered Last Savestate (Edited)", "TAS", 2)
		end
	else
		notify("No Savestates to enter!", "TAS", 1)
	end
end

local function BackSavestate()
	if #Savestates > 0 and Savestates[#Savestates] and #Savestates[#Savestates] > 0 then
		local InfoState = Savestates[#Savestates][#Savestates[#Savestates]]
		PlayerInfo = {}
		Pause = true
		getgenv().TAS_IsRecording = false
		if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
			LocalPlayer.Character.HumanoidRootPart.Anchored = true
		end
		TimePauseHolder = tick()
		TimeStart = tick() - InfoState.T
		TimePaused = 0
		SetCharacterState(InfoState)
		updateStatusColor()
		UpdateTimeGUI()
	end
end

local function GoFrameForward()
	if Pause then
		getgenv().TAS_IsRecording = true
		if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
			LocalPlayer.Character.HumanoidRootPart.Anchored = false
		end
		RunService.Heartbeat:Wait()
		RunService.Heartbeat:Wait()
		if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
			LocalPlayer.Character.HumanoidRootPart.Anchored = true
		end
		getgenv().TAS_IsRecording = false
	end
end

local function GoFrameBack()
	if not LocalPlayer.Character then return end
	local TargetFrameInfo = nil
	if #PlayerInfo > 1 then
		TargetFrameInfo = PlayerInfo[#PlayerInfo - 1]
		PlayerInfo[#PlayerInfo] = nil
	elseif #Savestates > 0 and #Savestates[#Savestates] > 1 then
		TargetFrameInfo = Savestates[#Savestates][#Savestates[#Savestates] - 1]
		Savestates[#Savestates][#Savestates[#Savestates]] = nil
	end
	if TargetFrameInfo then
		if not Pause then 
			Pause = true 
			getgenv().TAS_IsRecording = false
			if LocalPlayer.Character.HumanoidRootPart then LocalPlayer.Character.HumanoidRootPart.Anchored = true end
		end
		TimePauseHolder = tick()
		TimeStart = tick() - TargetFrameInfo.T
		TimePaused = 0
		SetCharacterState(TargetFrameInfo)
		UpdateTimeGUI()
		UpdateGUIText()
		updateStatusColor()
	end
end

--// REPEATED INPUT HANDLERS //--
local heldInputs = {}
local function handleHold(key, action)
	heldInputs[key] = true
	action()
	task.wait(0.2)
	while heldInputs[key] do
		action()
		task.wait(0.05)
	end
end

--// IO FUNCTIONS //--

local function GetFileName()
	local rawName = TASNameBox.Text
	local cleanName = rawName:gsub("[^%w%s%-%_]", ""):gsub("^%s*(.-)%s*$", "%1")
	if cleanName == "" then cleanName = "Untitled" end
	return cleanName .. ".json"
end

local function SaveRun()
	if not writefile then notify("Executor does not support writefile!", "Error"); return end
	local Data = {Savestates, PlayerInfo}
	local fileName = GetFileName()
	local success, err = pcall(function()
		local Encoded = HttpService:JSONEncode(Data)
		if not isfolder("TAS_Recorder") then makefolder("TAS_Recorder") end
		writefile("TAS_Recorder/" .. fileName, Encoded)
	end)
	if success then notify("Saved " .. fileName, "Success")
	else notify("Save Failed: " .. tostring(err), "Error") end
end

local function LoadRun()
	if not readfile then notify("Executor does not support readfile!", "Error"); return end
	local fileName = GetFileName()
	if not isfile("TAS_Recorder/" .. fileName) then
		notify("File not found: TAS_Recorder/" .. fileName, "Error")
		return
	end
	local success, err = pcall(function()
		local content = readfile("TAS_Recorder/" .. fileName)
		local loadedTAS = HttpService:JSONDecode(content)
		if type(loadedTAS) ~= "table" then error("Invalid File") end
		Savestates = loadedTAS[1] or {}
		PlayerInfo = loadedTAS[2] or {}
		if #PlayerInfo > 0 or (#Savestates > 0 and #Savestates[#Savestates] > 0) then
			BackSavestate()
		else
			TimeStart = tick()
		end
		UpdateGUIText()
		UpdateTimeGUI()
	end)
	if success then notify("Loaded " .. fileName, "Success") 
	else notify("Load Failed: " .. tostring(err), "Error") end
end

local function ViewTASPlayback()
	if ViewingTAS then return end
	
	local FlatFrames = {}
	for _, state in ipairs(Savestates) do
		for _, frame in ipairs(state) do
			table.insert(FlatFrames, frame)
		end
	end
	for _, frame in ipairs(PlayerInfo) do
		table.insert(FlatFrames, frame)
	end
	
	if #FlatFrames == 0 then notify("No frames to play!", "Error"); return end

	ViewingTAS = true
	getgenv().TAS_IsRecording = false 
	getgenv().TAS_IsPlaying = true 
	
	updateStatusColor()
	notify("Starting Playback...", "TAS")
	
	local Character = LocalPlayer.Character
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")
	if not Root then 
		ViewingTAS = false
		getgenv().TAS_IsPlaying = false
		return 
	end
	
	-- [[ UNANCHOR START ]]
	Root.Anchored = false 
	
	local StartPlay = tick()
	local PlayConn
	local CurrentIndex = 1
	
	PlayConn = RunService.Heartbeat:Connect(function()
		local Elapsed = tick() - StartPlay
		
		while CurrentIndex < #FlatFrames and FlatFrames[CurrentIndex + 1].T <= Elapsed do
			CurrentIndex = CurrentIndex + 1
			if FlatFrames[CurrentIndex].AE then
				for _, event in ipairs(FlatFrames[CurrentIndex].AE) do
					PlayRecordedAnim(event.N, event.F)
				end
			end
		end
		
		local FrameA = FlatFrames[CurrentIndex]
		local FrameB = FlatFrames[CurrentIndex + 1]
		
		if FrameB then
			local Delta = FrameB.T - FrameA.T
			local Alpha = 0
			if Delta > 0 then
				Alpha = (Elapsed - FrameA.T) / Delta
			end
			Alpha = math.clamp(Alpha, 0, 1)
			
			local cfA = CFrame.new(unpack(FrameA.CF))
			local cfB = CFrame.new(unpack(FrameB.CF))
			local camA = CFrame.new(unpack(FrameA.CCF))
			local camB = CFrame.new(unpack(FrameB.CCF))
			
			Root.CFrame = cfA:Lerp(cfB, Alpha)
			Workspace.CurrentCamera.CFrame = camA:Lerp(camB, Alpha)
			
			-- [[ UNANCHORED + ZERO VELOCITY ]]
			-- Replicate position while freezing momentum
			Root.Anchored = false
			Root.Velocity = Vector3.zero
			Root.RotVelocity = Vector3.zero
		else
			PlayConn:Disconnect()
			ViewingTAS = false
			getgenv().TAS_IsPlaying = false 
			Pause = true
			Root.Anchored = true -- Freeze at end
			
			updateStatusColor()
			notify("Playback Finished", "TAS")
		end
	end)
end

local function CollisionToggler()
	if not Mouse.Target then return end
	local t = Mouse.Target
	if t:IsA("BasePart") then
		t.CanCollide = not t.CanCollide
		t.Transparency = t.CanCollide and 0 or 0.5
	end
end

--// INITIALIZATION //--

local function DisconnectAll()
	for _, c in pairs(Connections) do c:Disconnect() end
	for _, c in pairs(CharConnections) do c:Disconnect() end
	if HUD then HUD:Destroy() end
	if DebugView then ToggleDebugView() end
	getgenv().TAS_Recorder_Running = false
	getgenv().TAS_IsRecording = false
	getgenv().TAS_IsPlaying = false
	if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
		LocalPlayer.Character.HumanoidRootPart.Anchored = false
	end
	notify("TAS Recorder Unloaded", "TAS")
end
getgenv().TAS_Recorder_Disconnect = DisconnectAll

--// ROBUST DEATH & CHARACTER LOGIC //--
local function SetupCharacterConnections(char)
	for _, c in pairs(CharConnections) do c:Disconnect() end
	CharConnections = {}

	if not char then return end
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then return end
	
	SetupAnimationHook()
	
	table.insert(CharConnections, hum.Died:Connect(function()
		Pause = true
		getgenv().TAS_IsRecording = false
		getgenv().TAS_IsPlaying = false
		updateStatusColor()
		notify("Character Died! Paused. Waiting for Respawn...", "TAS Warning", 5)
		
		local newChar = LocalPlayer.CharacterAdded:Wait()
		local newRoot = newChar:WaitForChild("HumanoidRootPart", 10)
		
		task.wait(0.5) 
		
		local lastState = nil
		if #PlayerInfo > 0 then
			lastState = PlayerInfo[#PlayerInfo]
		elseif #Savestates > 0 then
			lastState = Savestates[#Savestates][#Savestates[#Savestates]]
		end
		
		if lastState then
			SetCharacterState(lastState)
			notify("Restored Position. Press '8' to Undo death, or Unpause to continue.", "TAS System", 8)
		end
		
		Pause = true
		if newRoot then newRoot.Anchored = true end
		updateStatusColor()
	end))
end

local function Initialize()
	Savestates = {}
	PlayerInfo = {}
	TimePaused = 0
	Pause = true
	getgenv().TAS_IsRecording = false
	getgenv().TAS_IsPlaying = false
	TimeStart = tick()
	TimePauseHolder = tick()
	
	local initialCF = getCurrentCFrame()
	local initialCamCF = getCurrentCameraCFrame()
	local initialVel = Vector3.new()
	
	local cfComps = {initialCF:GetComponents()}
	for i = 1, #cfComps do cfComps[i] = round(cfComps[i]) end
	
	local camComps = {initialCamCF:GetComponents()}
	for i = 1, #camComps do camComps[i] = round(camComps[i]) end
	
	table.insert(Savestates, {{
		CF = cfComps,
		CCF = camComps,
		V = {0, 0, 0},
		T = 0
	}})
	
	SetUpGui()
	updateStatusColor()
	
	-- Main Recording Loop
	table.insert(Connections, RunService.Heartbeat:Connect(function(dt)
		if not Pause and not ViewingTAS then
			local now = tick()
			if now - LastRecordTime < (1/60) then
				return 
			end
			LastRecordTime = now

			if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return end
			if LocalPlayer.Character.Humanoid.Health <= 0 then return end

			local success, err = pcall(function()
				UpdateTimeGUI()
				
				-- Pull animation events from the buffer
				local animEventsForThisFrame = nil
				if #FrameAnimBuffer > 0 then
					animEventsForThisFrame = FrameAnimBuffer
					FrameAnimBuffer = {} -- Clear buffer immediately
				end
				
				table.insert(PlayerInfo, ReturnPlayerInfo(animEventsForThisFrame))
				UpdateGUIText()
			end)
			if not success then warn("TAS Recording Glitch:", err) end
		end
	end))
	
	-- Input Handling
	table.insert(Connections, UserInputService.InputBegan:Connect(function(Input, Processed)
		if Processed then return end
		local Key = Input.KeyCode
		if Key == Keybinds.UserPause then UserPauseToggle()
		elseif Key == Keybinds.AddSavestate then AddSavestate()
		elseif Key == Keybinds.RemoveSavestate then RemoveSavestate()
		elseif Key == Keybinds.EnterSavestate then EnterSavestate()
		elseif Key == Keybinds.BackSavestate then BackSavestate()
		elseif Key == Keybinds.CollisionToggler then CollisionToggler()
		elseif Key == Keybinds.SaveRun then SaveRun()
		elseif Key == Keybinds.ViewTAS then ViewTASPlayback()
		elseif Key == Keybinds.LoadRun then LoadRun()
		elseif Key == Keybinds.ResetToNormal then DisconnectAll()
		elseif Key == Keybinds.DebugToggler then ToggleDebugView()
		elseif Key == Keybinds.GoFrameForward then task.spawn(function() handleHold(Key, GoFrameForward) end)
		elseif Key == Keybinds.GoFrameBack then task.spawn(function() handleHold(Key, GoFrameBack) end)
		end
	end))
	
	table.insert(Connections, UserInputService.InputEnded:Connect(function(Input)
		heldInputs[Input.KeyCode] = false
	end))
	
	-- Persist Character Hooks
	table.insert(Connections, LocalPlayer.CharacterAdded:Connect(SetupCharacterConnections))
	if LocalPlayer.Character then SetupCharacterConnections(LocalPlayer.Character) end
	
	if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
		LocalPlayer.Character.HumanoidRootPart.Anchored = true
		LocalPlayer.Character.HumanoidRootPart.Velocity = Vector3.new()
	end
	
	notify("TAS Recorder Initialized", "TAS")
end

Initialize()

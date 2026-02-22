--// AUTO LOAD & PLAY //--
-- Type a file name here (e.g. "MyRun") to instantly load and play it without the GUI. Leave blank ("") to use the normal creator tools.
local AutoLoadAndPlayFile = getgenv().AutoLoadAndPlayFile
if AutoLoadAndPlayFile == nil then AutoLoadAndPlayFile = "" end

-- Set to true to severely downsample the recorded frames and smoothly interpolate between them (Warning: Will cause massive clipping/floating!)
local ExtremeSmoothing = getgenv().ExtremeSmoothing
if ExtremeSmoothing == nil then ExtremeSmoothing = false end

-- The target FPS to compress the recording into before playback (e.g., 1 = keeps only 1 frame per second)
local TargetSmoothingFPS = getgenv().TargetSmoothingFPS
if TargetSmoothingFPS == nil then TargetSmoothingFPS = 24 end

-- Set to true to show the predicted velocity trajectory curve even while a TAS is playing.
local ShowVelocityDuringPlayback = getgenv().ShowVelocityDuringPlayback
if ShowVelocityDuringPlayback == nil then ShowVelocityDuringPlayback = false end

-- Set to true to draw a line tracing the future path of the TAS during playback.
local ShowTASPathDuringPlayback = getgenv().ShowTASPathDuringPlayback
if ShowTASPathDuringPlayback == nil then ShowTASPathDuringPlayback = false end

-- Set to true to playback the recorded camera movements (applies smoothing if ExtremeSmoothing is enabled).
local PlaybackCamera = getgenv().PlaybackCamera
if PlaybackCamera == nil then PlaybackCamera = true end

-- Maximum frames to predict for the trajectory visualizer
local MaxTrajectoryFrames = getgenv().MaxTrajectoryFrames
if MaxTrajectoryFrames == nil then MaxTrajectoryFrames = 150 end

--// PREVENT DUPLICATES //--
if getgenv().TAS_Recorder_Running then
	pcall(function() getgenv().TAS_Recorder_Disconnect() end)
	task.wait(0.2)
end
getgenv().TAS_Recorder_Running = true

--// SERVICES //--
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")

--// LOCAL PLAYER //--
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

--// UTILS //--
local function round(num)
	return math.floor(num * 10000 + 0.5) / 10000 -- Increased precision for TAS interpolation
end

local ValToStateName = {}
for _, state in ipairs(Enum.HumanoidStateType:GetEnumItems()) do
	ValToStateName[state.Value] = state.Name
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
	DebugToggler    = Enum.KeyCode.V,
	ToggleVelocityVis= Enum.KeyCode.L
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
local ShowVelocityDuringRecording = true
local OriginalVisuals = {} 
local LastRecordTime = 0 

-- State Flags & Playback Variables
getgenv().TAS_IsRecording = false 
getgenv().TAS_IsPlaying = false 
local ActivePlaybackFrames = nil
local CurrentPlaybackIndex = 1

--// GUI OBJECTS //--
local HUD
local FrameCountLabel, SavestatesCountLabel, TimeTextLabel, TASNameBox, CapLockPauseLabel, KeyBindFrame, MainFrame
local TrajectoryFolder 
local TrajectoryLines = {} 
local PathLines = {} 

--// CONNECTIONS //--
local Connections = {}
local CharConnections = {} 
local PlayConn -- Tracks the playback loop so we can cancel it directly

--// HELPER FUNCTIONS //--
local function notify(text, title, dur)
	pcall(function()
		StarterGui:SetCore("SendNotification", {Title = title or "TAS Recorder", Text = text or "", Duration = dur or 3})
	end)
end

local function makeDraggable(guiObject)
	local dragging, dragInput, dragStart, startPos
	local function update(input)
		local delta = input.Position - dragStart
		guiObject.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
	
	local inputConn
	inputConn = UserInputService.InputChanged:Connect(function(input) 
		if input == dragInput and dragging then update(input) end 
	end)
	
	guiObject.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true; dragStart = input.Position; startPos = guiObject.Position
			input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
		end
	end)
	
	guiObject.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
	end)

	guiObject.Destroying:Connect(function()
		if inputConn then inputConn:Disconnect() end
	end)
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
		for _, v in ipairs(Workspace:GetDescendants()) do
			if v:IsA("BasePart") and not v:IsDescendantOf(LocalPlayer.Character) then
				OriginalVisuals[v] = {Color = v.Color, Transparency = v.Transparency}
				
				-- Deeply varied gray shades (thousands of variations for border contrast)
				local gray = math.random(200, 800) / 1000
				v.Color = Color3.new(gray, gray, gray)
				
				if v.Transparency == 1 then v.Transparency = 0.5 end
				if v.CanCollide == false then v.Transparency = 0.9 end
				
				local minSize = math.min(v.Size.X, v.Size.Y, v.Size.Z)
				
				-- Check for TouchInterest first (Killbricks/Teleporters)
				if v:FindFirstChild("TouchInterest") then 
					-- Immensely varied shades of RED
					v.Color = Color3.fromRGB(math.random(100, 255), math.random(0, 50), math.random(0, 50))
					v.Transparency = 0 
					
				-- Check for parts less than 1 stud thick
				elseif minSize < 1 then
					-- Random color (except cyan) with random brightness/darkness using HSV
					local h
					repeat
						h = math.random()
					until h < 0.45 or h > 0.55 -- Skip the cyan hue range (~0.5)
					
					local s = math.random(40, 100) / 100 -- Random saturation
					local val = math.random(20, 100) / 100 -- Random brightness/darkness
					
					v.Color = Color3.fromHSV(h, s, val)
				end
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
local function ReturnPlayerInfo()
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChild("Humanoid")
	
	local cf = root and root.CFrame or CFrame.new()
	local vel = root and root.Velocity or Vector3.zero
	local rvel = root and root.RotVelocity or Vector3.zero
	local camCf = Workspace.CurrentCamera.CFrame
	
	-- Save numeric enum value (18 is the value for Enum.HumanoidStateType.None)
	local hs = hum and hum:GetState().Value or 18
	
	-- FIX: Only round position vector components (X, Y, Z). 
	-- Rounding the rotation matrix breaks matrix orthogonality, causing micro-drift over time.
	local cfComps = {cf:GetComponents()}
	for i = 1, 3 do cfComps[i] = round(cfComps[i]) end
	
	local camComps = {camCf:GetComponents()}
	for i = 1, 3 do camComps[i] = round(camComps[i]) end

	return {
		CF = cfComps,
		CCF = camComps,
		V = {round(vel.X), round(vel.Y), round(vel.Z)},
		RV = {round(rvel.X), round(rvel.Y), round(rvel.Z)},
		HS = hs,
		T = round(os.clock() - TimeStart - TimePaused)
	}
end

--// GUI SETUP //--
local function UpdateGUIText()
	if SavestatesCountLabel then SavestatesCountLabel.Text = "Savestates: " .. tostring(#Savestates) end
	if FrameCountLabel then FrameCountLabel.Text = "Frames: " .. tostring(#PlayerInfo) end
end

local function FormatTime(TimeValue)
	local m = math.floor(TimeValue / 60)
	local s = math.floor(TimeValue % 60)
	local ms = math.floor((TimeValue * 1000) % 1000)
	return string.format("%d:%02d.%03d", m, s, ms)
end

local function UpdateTimeGUI()
	if TimeTextLabel then
		local TimePlayed = os.clock() - TimeStart - TimePaused
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
	KeyBindFrame.Size = UDim2.new(0, 320, 0, 340)
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
	AddKeyLabel(Keybinds.ToggleVelocityVis.Name, "Toggle Velocity Vis")
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
	local Hum = LocalPlayer.Character:FindFirstChild("Humanoid")
	if not Root then return end

	local charCF = CFrame.new(unpack(InfoState.CF))
	local vel = Vector3.new(unpack(InfoState.V))
	local rvel = Vector3.new(unpack(InfoState.RV))

	Root.CFrame = charCF
	
	-- Apply physics exactly to all limbs for flawless visual state reproduction
	for _, part in ipairs(LocalPlayer.Character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Velocity = vel
			part.RotVelocity = rvel
		end
	end

	-- Backwards compatible decode
	local hsName = type(InfoState.HS) == "number" and ValToStateName[InfoState.HS] or InfoState.HS

	if Hum and hsName and hsName ~= "None" then
		-- Only ever call ChangeState if the current state strictly mismatches
		if Hum:GetState().Name ~= hsName then
			pcall(function() Hum:ChangeState(Enum.HumanoidStateType[hsName]) end)
		end
	end
end

local function UserPauseToggle()
	if ViewingTAS then return end
	Pause = not Pause
	getgenv().TAS_IsRecording = not Pause
	
	local Root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if Root then Root.Anchored = Pause end

	if Pause then
		TimePauseHolder = os.clock()
		if TimeTextLabel then TimeTextLabel.TextColor3 = Color3.fromRGB(255, 255, 0) end
	else
		if TimePauseHolder then
			TimePaused = TimePaused + (os.clock() - TimePauseHolder)
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
			
			TimeStart = os.clock() - lastFrame.T
			TimePaused = 0
			TimePauseHolder = os.clock() 
			
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
			
			TimeStart = os.clock() - lastFrame.T
			TimePaused = 0
			TimePauseHolder = os.clock()
			
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
	if #Savestates > 0 then
		local lastStateList = Savestates[#Savestates]
		if lastStateList and #lastStateList > 0 then
			local InfoState = lastStateList[#lastStateList]
			PlayerInfo = {}
			Pause = true
			getgenv().TAS_IsRecording = false
			if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
				LocalPlayer.Character.HumanoidRootPart.Anchored = true
			end
			
			TimeStart = os.clock() - InfoState.T
			TimePaused = 0
			TimePauseHolder = os.clock()
			
			SetCharacterState(InfoState)
			updateStatusColor()
			UpdateTimeGUI()
		end
	end
end

local function GoFrameForward()
	if Pause then
		local CurrentFrameCount = #PlayerInfo
		UserPauseToggle()
		repeat RunService.Heartbeat:Wait() until #PlayerInfo > CurrentFrameCount
		UserPauseToggle()
	end
end

local function GoFrameBack()
	if not LocalPlayer.Character then return end
	local TargetFrameInfo = nil
	
	if #PlayerInfo > 1 then
		TargetFrameInfo = PlayerInfo[#PlayerInfo - 1]
		PlayerInfo[#PlayerInfo] = nil
	end

	if TargetFrameInfo then
		if not Pause then 
			Pause = true 
			getgenv().TAS_IsRecording = false
			if LocalPlayer.Character.HumanoidRootPart then 
				LocalPlayer.Character.HumanoidRootPart.Anchored = true 
			end
		end
		
		TimeStart = os.clock() - TargetFrameInfo.T
		TimePaused = 0
		TimePauseHolder = os.clock()
		
		SetCharacterState(TargetFrameInfo)
		UpdateTimeGUI()
		UpdateGUIText()
		updateStatusColor()
	end
end

--// REPEATED INPUT HANDLERS //--
local heldInputs = {}
local function handleHold(key, action)
	-- FIX: Prevent concurrency duplication by tying the loop to a unique execution ID
	local pressId = os.clock()
	heldInputs[key] = pressId
	action()
	task.wait(0.2)
	while heldInputs[key] == pressId do
		action()
		task.wait(1/50)
	end
end

--// IO FUNCTIONS //--
local function GetFileName(overrideName)
	if overrideName and overrideName ~= "" then
		local name = overrideName:gsub("^%s*(.-)%s*$", "%1")
		if not name:match("%.json$") then name = name .. ".json" end
		return name
	end
	local rawName = TASNameBox and TASNameBox.Text or "Untitled"
	local cleanName = rawName:gsub("%p", ""):gsub("^%s*(.-)%s*$", "%1")
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

local function LoadRun(overrideName)
	if type(overrideName) ~= "string" then overrideName = nil end
	if not readfile then notify("Executor does not support readfile!", "Error"); return false end
	
	local fileName = GetFileName(overrideName)
	if not isfile("TAS_Recorder/" .. fileName) then
		notify("File not found: TAS_Recorder/" .. fileName, "Error")
		return false
	end
	
	local success, err = pcall(function()
		local content = readfile("TAS_Recorder/" .. fileName)
		local loadedTAS = HttpService:JSONDecode(content)
		
		-- FIX: Strict structural validation
		if type(loadedTAS) ~= "table" or type(loadedTAS[1]) ~= "table" or type(loadedTAS[2]) ~= "table" then 
			error("Invalid TAS file format") 
		end
		
		Savestates = loadedTAS[1]
		PlayerInfo = loadedTAS[2]
		
		-- Load the run into memory silently, do not artificially advance physics frames
		TimeStart = os.clock()
		TimePaused = 0
		TimePauseHolder = os.clock()
		
		Pause = true
		getgenv().TAS_IsRecording = false
		
		UpdateGUIText()
		UpdateTimeGUI()
		updateStatusColor()
	end)
	
	if success then 
		notify("Loaded " .. fileName, "Success") 
		return true
	else 
		notify("Load Failed: " .. tostring(err), "Error") 
		return false
	end
end

--// INITIALIZATION (Forward Declaration) //--
local DisconnectAll

local function ViewTASPlayback()
	if ViewingTAS then return end
	
	local FlatFrames = {}
	for _, state in ipairs(Savestates) do
		for _, frame in ipairs(state) do table.insert(FlatFrames, frame) end
	end
	for _, frame in ipairs(PlayerInfo) do table.insert(FlatFrames, frame) end
	
	if #FlatFrames == 0 then 
		notify("No frames to play!", "Error")
		if AutoLoadAndPlayFile and AutoLoadAndPlayFile ~= "" then DisconnectAll() end
		return 
	end

	-- Maintain a parallel reference to the original raw 60fps frames for absolute State precision
	local FullFrames = FlatFrames

	-- EXTREME SMOOTHING LOGIC (Downsampling Positional Frames)
	if ExtremeSmoothing then
		local smoothedFrames = {}
		local interval = 1 / math.max(0.001, TargetSmoothingFPS)
		local nextTargetTime = 0
		
		for i, frame in ipairs(FlatFrames) do
			if frame.T >= nextTargetTime or i == 1 or i == #FlatFrames then
				table.insert(smoothedFrames, frame)
				nextTargetTime = frame.T + interval
			end
		end
		FlatFrames = smoothedFrames
	end

	ViewingTAS = true
	getgenv().TAS_IsRecording = false 
	getgenv().TAS_IsPlaying = true 
	
	ActivePlaybackFrames = FlatFrames
	CurrentPlaybackIndex = 1
	
	updateStatusColor()
	notify("Starting Playback...", "TAS")
	
	local Character = LocalPlayer.Character
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")
	local Humanoid = Character and Character:FindFirstChild("Humanoid")

	if not Root then 
		ViewingTAS = false
		getgenv().TAS_IsPlaying = false
		ActivePlaybackFrames = nil
		if AutoLoadAndPlayFile and AutoLoadAndPlayFile ~= "" then DisconnectAll() end
		return 
	end

	Root.Anchored = false 
	
	local StartPlay = os.clock()
	local CurrentIndex = 1
	local FullCurrentIndex = 1
	
	if PlayConn then PlayConn:Disconnect() end
	
	-- Utilizing Heartbeat: Because Root is unanchored, Heartbeat updates CFrame and Velocity 
	-- *after* the physics step but without blocking the Render thread, causing optimal visual smoothness.
	PlayConn = RunService.Heartbeat:Connect(function()
		-- Graceful death handling: Stop if character breaks/dies during playback
		if not Character or not Character.Parent or not Root or not Root.Parent or (Humanoid and Humanoid.Health <= 0) then
			return -- Let the hum.Died event safely handle the rest
		end
		
		local Elapsed = os.clock() - StartPlay
		
		-- Advance Positional Interpolation Frame (Smoothed)
		while CurrentIndex < #FlatFrames and FlatFrames[CurrentIndex + 1] and FlatFrames[CurrentIndex + 1].T <= Elapsed do
			CurrentIndex = CurrentIndex + 1
			CurrentPlaybackIndex = CurrentIndex
		end
		
		-- Advance State Frame (Raw 60fps)
		while FullCurrentIndex < #FullFrames and FullFrames[FullCurrentIndex + 1] and FullFrames[FullCurrentIndex + 1].T <= Elapsed do
			FullCurrentIndex = FullCurrentIndex + 1
		end
		
		local FrameA = FlatFrames[CurrentIndex]
		local FrameB = FlatFrames[CurrentIndex + 1]
		local StateFrame = FullFrames[FullCurrentIndex]
		
		if FrameB then
			-- Perfectly interpolates the elapsed time mathematically for smoothed positional visuals
			local Delta = FrameB.T - FrameA.T
			local Alpha = 0
			if Delta > 0 then Alpha = (Elapsed - FrameA.T) / Delta end
			Alpha = math.clamp(Alpha, 0, 1)
			
			local cfA = CFrame.new(unpack(FrameA.CF))
			local cfB = CFrame.new(unpack(FrameB.CF))
			local velA = Vector3.new(unpack(FrameA.V))
			local velB = Vector3.new(unpack(FrameB.V))
			local rvelA = Vector3.new(unpack(FrameA.RV))
			local rvelB = Vector3.new(unpack(FrameB.RV))
			
			-- Spherical Linear Interpolation for pure rotational CFrame precision
			Root.CFrame = cfA:Lerp(cfB, Alpha)
			
			-- Apply Camera playback if enabled
			if PlaybackCamera and FrameA.CCF and FrameB.CCF then
				local camA = CFrame.new(unpack(FrameA.CCF))
				local camB = CFrame.new(unpack(FrameB.CCF))
				Workspace.CurrentCamera.CFrame = camA:Lerp(camB, Alpha)
			end
			
			-- Accurately apply exact playback velocity to all limbs so hitboxes and physics flow smoothly
			local curV = velA:Lerp(velB, Alpha)
			local curRV = rvelA:Lerp(rvelB, Alpha)
			for _, part in ipairs(Character:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Velocity = curV
					part.RotVelocity = curRV
				end
			end

			-- Forceably check and inject Humanoid state on EVERY single frame using full 60FPS data!
			if Humanoid and StateFrame and StateFrame.HS then
				local targetStateName = type(StateFrame.HS) == "number" and ValToStateName[StateFrame.HS] or StateFrame.HS
				
				if targetStateName and targetStateName ~= "None" then
					local currentState = Humanoid:GetState().Name
					-- Only ever call ChangeState if the current state strictly mismatches
					if currentState ~= targetStateName then
						local targetStateEnum = Enum.HumanoidStateType[targetStateName]
						if targetStateEnum then
							pcall(function() Humanoid:ChangeState(targetStateEnum) end)
						end
					end
				end
			end
		else
			-- IF AUTO LOAD PLAYING: Clean everything up and unanchor
			if AutoLoadAndPlayFile and AutoLoadAndPlayFile ~= "" then
				DisconnectAll()
				return
			end
			
			-- IF MANUAL TAS CREATOR: End playback cleanly but remain paused for further editing
			PlayConn:Disconnect()
			PlayConn = nil
			ViewingTAS = false
			getgenv().TAS_IsPlaying = false 
			Pause = true
			Root.Anchored = true
			ActivePlaybackFrames = nil
			CurrentPlaybackIndex = 1
			
			-- Cleanup getting up state with checks
			if Humanoid and Humanoid:GetState() ~= Enum.HumanoidStateType.GettingUp then
				pcall(function() Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end)
			end

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
DisconnectAll = function()
	if PlayConn then 
		PlayConn:Disconnect()
		PlayConn = nil 
	end
	
	if TrajectoryFolder then
		TrajectoryFolder:Destroy()
		TrajectoryFolder = nil
	end
	TrajectoryLines = {}
	PathLines = {}
	
	ViewingTAS = false
	Pause = true
	ActivePlaybackFrames = nil
	CurrentPlaybackIndex = 1
	
	for _, c in pairs(Connections) do c:Disconnect() end
	for _, c in pairs(CharConnections) do c:Disconnect() end
	if HUD then HUD:Destroy() end
	if DebugView then ToggleDebugView() end
	
	local char = LocalPlayer.Character
	if char then
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then 
			root.Anchored = false
			root.Velocity = Vector3.zero 
			root.RotVelocity = Vector3.zero
		end
		
		local hum = char:FindFirstChild("Humanoid")
		if hum and hum:GetState() ~= Enum.HumanoidStateType.GettingUp then
			pcall(function() hum:ChangeState(Enum.HumanoidStateType.GettingUp) end)
		end
	end

	getgenv().TAS_Recorder_Running = false
	getgenv().TAS_IsRecording = false
	getgenv().TAS_IsPlaying = false
	notify("TAS Recorder Unloaded", "TAS")
end
getgenv().TAS_Recorder_Disconnect = DisconnectAll

local function SetupCharacterConnections(char)
	for _, c in pairs(CharConnections) do c:Disconnect() end
	CharConnections = {}

	if not char then return end
	local hum = char:WaitForChild("Humanoid", 10)
	if not hum then return end
	
	-- Graceful Death Handling
	table.insert(CharConnections, hum.Died:Connect(function()
		local wasPlaying = getgenv().TAS_IsPlaying
		
		Pause = true
		getgenv().TAS_IsRecording = false
		getgenv().TAS_IsPlaying = false
		ViewingTAS = false
		
		if PlayConn then
			PlayConn:Disconnect()
			PlayConn = nil
		end
		
		ActivePlaybackFrames = nil
		CurrentPlaybackIndex = 1
		
		if AutoLoadAndPlayFile and AutoLoadAndPlayFile ~= "" and wasPlaying then
			DisconnectAll()
			return
		end
		
		updateStatusColor()
		notify("Character Died! Paused. Waiting for Respawn...", "TAS Warning", 5)
		
		local newChar = LocalPlayer.CharacterAdded:Wait()
		local newRoot = newChar:WaitForChild("HumanoidRootPart", 10)
		task.wait(0.5) 
		
		local lastState = nil
		if #PlayerInfo > 0 then
			lastState = PlayerInfo[#PlayerInfo]
		elseif #Savestates > 0 then
			local lastList = Savestates[#Savestates]
			if lastList and #lastList > 0 then
				lastState = lastList[#lastList]
			end
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
	TimeStart = os.clock()
	TimePauseHolder = os.clock()
	
	local initialData = ReturnPlayerInfo()
	initialData.T = 0
	table.insert(Savestates, {initialData})
	
	-- Setup Visualizer Trajectory Folder
	TrajectoryFolder = Instance.new("Folder")
	TrajectoryFolder.Name = "TAS_Trajectory"
	TrajectoryFolder.Parent = Workspace:FindFirstChild("Terrain") or Workspace
	
	local isAuto = (AutoLoadAndPlayFile and AutoLoadAndPlayFile ~= "")
	
	-- Only generate UI if not in Auto-Play mode
	if not isAuto then
		SetUpGui()
		updateStatusColor()
	end
	
	-- Render visualizers smoothly (Post-Physics execution)
	table.insert(Connections, RunService.Heartbeat:Connect(function()
		
		-- 1. VELOCITY TRAJECTORY PREDICTION
		local shouldShowVel = (not ViewingTAS and ShowVelocityDuringRecording) or (ViewingTAS and ShowVelocityDuringPlayback)
		
		if shouldShowVel then
			local char = LocalPlayer.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local hum = char and char:FindFirstChild("Humanoid")
			
			if root and hum and (root.Velocity.Magnitude > 0.5 or hum.MoveDirection.Magnitude > 0.1) then
				local p = root.Position
				local v = root.Velocity
				
				-- Roblox internal physics perfectly documented values
				local dt240 = 1 / 240
				local grav = Vector3.new(0, -196.2, 0)
				
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				rayParams.FilterDescendantsInstances = {char}
				rayParams.RespectCanCollide = true
				
				local points = {p}
				local velocities = {v}
				
				-- Blockcast sizes matching character collision boundaries exactly
				local charRot = root.CFrame.Rotation
				local floorBox = Vector3.new(1.5, 0.2, 1.5) 
				local wallBox = Vector3.new(1.5, 4.5, 1.5)  
				
				local feetOffset = Vector3.new(0, -3.1, 0)
				local walkSpeed = hum.WalkSpeed
				
				-- When recording, use actual MoveDirection. When playing back, guess intended direction based on velocity
				local targetDir = hum.MoveDirection
				local isHoldingJump = false
				
				if ViewingTAS then
					local flatV = Vector3.new(v.X, 0, v.Z)
					if flatV.Magnitude > 0.5 then
						targetDir = flatV.Unit
					else
						targetDir = Vector3.zero
					end
					isHoldingJump = false
				else
					isHoldingJump = UserInputService:IsKeyDown(Enum.KeyCode.Space) or hum.Jump
				end
				
				local targetVXZ = targetDir * walkSpeed
				
				-- Calculate correct jump force based on game settings
				local jumpVelocity = 50
				pcall(function()
					if hum.UseJumpPower then
						jumpVelocity = hum.JumpPower
					else
						jumpVelocity = math.sqrt(2 * Workspace.Gravity * hum.JumpHeight)
					end
				end)
				
				-- The exact derived constants from the physics data!
				local airAccelStep = 0.59584 * (walkSpeed / 16)
				local groundFactorTarget = 0.625
				local groundFactorCurrent = 0.375
				
				local jumpTimer = 0
				local currentState = hum:GetState()
				if currentState == Enum.HumanoidStateType.Freefall or currentState == Enum.HumanoidStateType.Jumping or currentState == Enum.HumanoidStateType.FallingDown then
					jumpTimer = 15
				end
				if v.Y > 10 then
					jumpTimer = 15
				end
				
				-- Simulate optimized frames into the future
				for frame = 1, MaxTrajectoryFrames do
					local hitSomething = false
					
					for step = 1, 4 do
						local currVXZ = Vector3.new(v.X, 0, v.Z)
						local floorHit = nil
						
						if jumpTimer == 0 then
							floorHit = Workspace:Blockcast(CFrame.new(p) * charRot, floorBox, feetOffset, rayParams)
						end
						
						if floorHit then
							currVXZ = (currVXZ * groundFactorCurrent) + (targetVXZ * groundFactorTarget)
							
							if isHoldingJump then
								v = Vector3.new(currVXZ.X, jumpVelocity, currVXZ.Z)
								jumpTimer = 15
							else
								local normal = floorHit.Normal
								v = currVXZ - (currVXZ:Dot(normal) * normal)
							end
						else
							if jumpTimer > 0 then
								jumpTimer = jumpTimer - 1
							end
							
							local diff = targetVXZ - currVXZ
							if diff.Magnitude > 0 then
								local accelStep = math.min(diff.Magnitude, airAccelStep)
								currVXZ = currVXZ + (diff.Unit * accelStep)
							end
							v = Vector3.new(currVXZ.X, v.Y, currVXZ.Z) + (grav * dt240)
						end
						
						local stepVec = v * dt240
						if stepVec.Magnitude > 0.0001 then
							local hitCenter = Workspace:Blockcast(CFrame.new(p) * charRot, wallBox, stepVec, rayParams)
							if hitCenter then
								p = p + (stepVec.Unit * hitCenter.Distance)
								hitSomething = true
								break
							else
								p = p + stepVec
							end
						end
					end
					
					table.insert(points, p)
					table.insert(velocities, v)
					if hitSomething then break end
					if (not isHoldingJump) and v.Magnitude <= 1 and targetVXZ.Magnitude < 0.5 then break end
				end
				
				local ws = hum.WalkSpeed > 0 and hum.WalkSpeed or 16
				
				for i = 1, #points - 1 do
					local line = TrajectoryLines[i]
					if not line then
						line = Instance.new("CylinderHandleAdornment")
						line.Radius = 0.08
						line.ZIndex = 5
						line.AlwaysOnTop = false
						line.Adornee = Workspace.Terrain
						line.Parent = TrajectoryFolder
						TrajectoryLines[i] = line
					end
					
					local p1, p2 = points[i], points[i+1]
					local length = (p2 - p1).Magnitude
					local mag = velocities[i].Magnitude
					
					if length > 0.001 then
						line.Height = length
						line.CFrame = CFrame.lookAt(p1 + (p2 - p1) / 2, p2)
						
						local cG = Color3.new(0, 1, 0)
						local cY = Color3.new(1, 1, 0)
						local cR = Color3.new(1, 0, 0)
						
						if mag <= ws then
							line.Color3 = cG:Lerp(cY, mag / ws)
						else
							line.Color3 = cY:Lerp(cR, math.clamp((mag - ws) / ws, 0, 1))
						end
						line.Visible = true
					else
						line.Visible = false
					end
				end
				for i = #points, #TrajectoryLines do TrajectoryLines[i].Visible = false end
			else
				for _, line in ipairs(TrajectoryLines) do line.Visible = false end
			end
		else
			for _, line in ipairs(TrajectoryLines) do line.Visible = false end
		end
		
		-- 2. TAS FUTURE PATH VISUALIZER
		if ViewingTAS and ShowTASPathDuringPlayback and ActivePlaybackFrames then
			local frames = ActivePlaybackFrames
			local startIdx = CurrentPlaybackIndex
			local maxFrames = math.min(#frames, startIdx + 1200) -- Show up to 1200 frames (20 seconds) ahead
			
			local lineIndex = 1
			for i = startIdx, maxFrames - 1 do
				local p1 = Vector3.new(unpack(frames[i].CF))
				local p2 = Vector3.new(unpack(frames[i+1].CF))
				local dist = (p2 - p1).Magnitude
				
				if dist > 0.005 then 
					local line = PathLines[lineIndex]
					if not line then
						line = Instance.new("CylinderHandleAdornment")
						line.Radius = 0.06
						line.Color3 = Color3.fromRGB(0, 200, 255) -- Cyan Blue
						line.Transparency = 0.2
						line.ZIndex = 4
						line.AlwaysOnTop = false
						line.Adornee = Workspace.Terrain
						line.Parent = TrajectoryFolder
						PathLines[lineIndex] = line
					end
					
					line.Height = dist
					line.CFrame = CFrame.lookAt(p1 + (p2 - p1) / 2, p2)
					line.Visible = true
					lineIndex = lineIndex + 1
				end
			end
			
			for i = lineIndex, #PathLines do
				PathLines[i].Visible = false
			end
		else
			for _, line in ipairs(PathLines) do
				line.Visible = false
			end
		end
	end))
	
	table.insert(Connections, RunService.Heartbeat:Connect(function(dt)
		if not Pause and not ViewingTAS then
			local now = os.clock()
			if now - LastRecordTime < (1/60) then return end
			LastRecordTime = now

			if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then return end
			if LocalPlayer.Character.Humanoid.Health <= 0 then return end

			local success, err = pcall(function()
				UpdateTimeGUI()
				table.insert(PlayerInfo, ReturnPlayerInfo())
				UpdateGUIText()
			end)
			if not success then warn("TAS Recording Glitch:", err) end
		end
	end))
	
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
		elseif Key == Keybinds.ToggleVelocityVis then 
			ShowVelocityDuringRecording = not ShowVelocityDuringRecording
			notify("Velocity Visualizer: " .. (ShowVelocityDuringRecording and "ON" or "OFF"), "TAS Tools", 1)
		elseif Key == Keybinds.GoFrameForward then task.spawn(function() handleHold(Key, GoFrameForward) end)
		elseif Key == Keybinds.GoFrameBack then task.spawn(function() handleHold(Key, GoFrameBack) end)
		end
	end))
	
	table.insert(Connections, UserInputService.InputEnded:Connect(function(Input)
		heldInputs[Input.KeyCode] = nil
	end))
	
	table.insert(Connections, LocalPlayer.CharacterAdded:Connect(SetupCharacterConnections))
	if LocalPlayer.Character then SetupCharacterConnections(LocalPlayer.Character) end
	
	if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
		LocalPlayer.Character.HumanoidRootPart.Anchored = true
		LocalPlayer.Character.HumanoidRootPart.Velocity = Vector3.new()
	end
	
	notify("TAS Recorder Initialized", "TAS")
	
	-- IF AUTO-PLAY IS ACTIVATED:
	if isAuto then
		task.spawn(function()
			if not LocalPlayer.Character then LocalPlayer.CharacterAdded:Wait() end
			local char = LocalPlayer.Character
			if not char:FindFirstChild("HumanoidRootPart") then char:WaitForChild("HumanoidRootPart", 5) end
			
			local loadSuccess = LoadRun(AutoLoadAndPlayFile)
			if loadSuccess then
				task.wait(0.1)
				ViewTASPlayback()
			else
				DisconnectAll()
			end
		end)
	end
end

Initialize()

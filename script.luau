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
	return math.floor(num * 1000 + 0.5) / 1000
end

local function GetPriorityEnum(name)
	for _, enumItem in ipairs(Enum.AnimationPriority:GetEnumItems()) do
		if enumItem.Name == name then
			return enumItem
		end
	end
	return Enum.AnimationPriority.Action
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

-- Unique Track Tracking
local RecTrackCache = setmetatable({}, {__mode = "k"})
local RecTrackCounter = 0

-- State Flags
getgenv().TAS_IsRecording = false 
getgenv().TAS_IsPlaying = false 

--// GUI OBJECTS //--
local HUD
local FrameCountLabel, SavestatesCountLabel, TimeTextLabel, TASNameBox, CapLockPauseLabel, KeyBindFrame, MainFrame

--// CONNECTIONS //--
local Connections = {}
local CharConnections = {} 
local PlaybackTracks = {} 

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
		for _, v in ipairs(Workspace:GetDescendants()) do
			if v:IsA("BasePart") and not v:IsDescendantOf(LocalPlayer.Character) then
				rawset(OriginalVisuals, v, {Color = v.Color, Transparency = v.Transparency})
				
				-- Default grey shade 
				local shade = math.random(30, 90) / 100
				v.Color = Color3.new(shade, shade, shade)
				
				if v.Transparency == 1 then v.Transparency = 0.5 end
				if v.CanCollide == false then v.Transparency = 0.9 end
				
				-- Check for TouchInterest first (Killbricks/Teleporters)
				if v:FindFirstChild("TouchInterest") then 
					local rShade = math.random(120, 255) / 255
					v.Color = Color3.new(rShade, 0, 0)
					v.Transparency = 0 
					
				-- Check for thin parts (<= 1 stud)
				elseif math.min(v.Size.X, v.Size.Y, v.Size.Z) <= 1 then 
					local cShade = math.random(120, 255) / 255
					v.Color = Color3.new(0, cShade, cShade)
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
local function GetActiveAnimations()
	local anims = {}
	local char = LocalPlayer.Character
	if char then
		local hum = char:FindFirstChild("Humanoid")
		local animator = hum and hum:FindFirstChildOfClass("Animator")
		if animator then
			for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
				if track.Animation and track.Animation.AnimationId ~= "" then
					
					local uID = rawget(RecTrackCache, track)
					if not uID then
						RecTrackCounter = RecTrackCounter + 1
						uID = RecTrackCounter
						rawset(RecTrackCache, track, uID)
					end
					
					table.insert(anims, {
						Id = track.Animation.AnimationId,
						T = round(track.TimePosition),
						W = round(track.WeightCurrent),
						P = track.Priority.Name,
						S = round(track.Speed),
						U = uID 
					})
				end
			end
		end
	end
	return anims
end

local function ReturnPlayerInfo()
	local char = LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	
	local cf = root and root.CFrame or CFrame.new()
	local vel = root and root.Velocity or Vector3.zero
	local camCf = Workspace.CurrentCamera.CFrame
	
	local cfComps = {cf:GetComponents()}
	for index, value in ipairs(cfComps) do 
		rawset(cfComps, index, round(value)) 
	end
	
	local camComps = {camCf:GetComponents()}
	for index, value in ipairs(camComps) do 
		rawset(camComps, index, round(value)) 
	end

	return {
		CF = cfComps,
		CCF = camComps,
		V = {round(vel.X), round(vel.Y), round(vel.Z)},
		T = round(tick() - TimeStart - TimePaused),
		A = GetActiveAnimations()
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

	local charCF = CFrame.new(unpack(InfoState.CF))
	local camCF = CFrame.new(unpack(InfoState.CCF))
	local vel = Vector3.new(unpack(InfoState.V))

	Root.CFrame = charCF
	Root.Velocity = vel
	Root.RotVelocity = Vector3.zero
	Workspace.CurrentCamera.CFrame = camCF
end

local function UserPauseToggle()
	if ViewingTAS then return end
	Pause = not Pause
	getgenv().TAS_IsRecording = not Pause
	
	local Root = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if Root then Root.Anchored = Pause end

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
		local lastSegment = rawget(Savestates, #Savestates)
		if lastSegment and #lastSegment > 0 then
			local lastFrame = rawget(lastSegment, #lastSegment)
			PlayerInfo = {}
			Pause = true
			getgenv().TAS_IsRecording = false
			
			TimeStart = tick() - lastFrame.T
			TimePaused = 0
			TimePauseHolder = tick() 
			
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
		local lastFrame = rawget(PlayerInfo, #PlayerInfo)
		if lastFrame then
			Pause = true
			getgenv().TAS_IsRecording = false
			SetCharacterState(lastFrame)
			
			TimeStart = tick() - lastFrame.T
			TimePaused = 0
			TimePauseHolder = tick()
			
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
		local lastStateList = rawget(Savestates, #Savestates)
		if lastStateList and #lastStateList > 0 then
			local InfoState = rawget(lastStateList, #lastStateList)
			PlayerInfo = {}
			Pause = true
			getgenv().TAS_IsRecording = false
			if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
				LocalPlayer.Character.HumanoidRootPart.Anchored = true
			end
			
			TimeStart = tick() - InfoState.T
			TimePaused = 0
			TimePauseHolder = tick()
			
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
		TargetFrameInfo = rawget(PlayerInfo, #PlayerInfo - 1)
		rawset(PlayerInfo, #PlayerInfo, nil)
	end

	if TargetFrameInfo then
		if not Pause then 
			Pause = true 
			getgenv().TAS_IsRecording = false
			if LocalPlayer.Character.HumanoidRootPart then 
				LocalPlayer.Character.HumanoidRootPart.Anchored = true 
			end
		end
		
		TimeStart = tick() - TargetFrameInfo.T
		TimePaused = 0
		TimePauseHolder = tick()
		
		SetCharacterState(TargetFrameInfo)
		UpdateTimeGUI()
		UpdateGUIText()
		updateStatusColor()
	end
end

--// REPEATED INPUT HANDLERS //--
local heldInputs = {}
local function handleHold(key, action)
	rawset(heldInputs, key, true)
	action()
	task.wait(0.2)
	while rawget(heldInputs, key) do
		action()
		task.wait(1/50)
	end
end

--// IO FUNCTIONS //--
local function GetFileName()
	local rawName = TASNameBox.Text
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
		
		Savestates = rawget(loadedTAS, 1) or {}
		PlayerInfo = rawget(loadedTAS, 2) or {}
		
		local hasFrames = (#PlayerInfo > 0)
		if not hasFrames and #Savestates > 0 then
			local lastList = rawget(Savestates, #Savestates)
			if lastList and #lastList > 0 then
				hasFrames = true
			end
		end

		if hasFrames then
			BackSavestate()
		else
			TimeStart = tick()
			TimePaused = 0
			TimePauseHolder = tick()
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
		for _, frame in ipairs(state) do table.insert(FlatFrames, frame) end
	end
	for _, frame in ipairs(PlayerInfo) do table.insert(FlatFrames, frame) end
	
	if #FlatFrames == 0 then notify("No frames to play!", "Error"); return end

	ViewingTAS = true
	getgenv().TAS_IsRecording = false 
	getgenv().TAS_IsPlaying = true 
	
	updateStatusColor()
	notify("Starting Playback...", "TAS")
	
	local Character = LocalPlayer.Character
	local Root = Character and Character:FindFirstChild("HumanoidRootPart")
	local Humanoid = Character and Character:FindFirstChild("Humanoid")
	local Animator = Humanoid and Humanoid:FindFirstChildOfClass("Animator")

	if not Root then 
		ViewingTAS = false
		getgenv().TAS_IsPlaying = false
		return 
	end

	local animateScript = Character:FindFirstChild("Animate")
	if animateScript then animateScript.Disabled = true end

	if Animator then
		for _, track in ipairs(Animator:GetPlayingAnimationTracks()) do
			track:Stop(0)
		end
	end

	Root.Anchored = false 
	
	local StartPlay = tick()
	local PlayConn
	local CurrentIndex = 1
	
	PlayConn = RunService.Heartbeat:Connect(function()
		local Elapsed = tick() - StartPlay
		
		while CurrentIndex < #FlatFrames and rawget(FlatFrames, CurrentIndex + 1) and rawget(FlatFrames, CurrentIndex + 1).T <= Elapsed do
			CurrentIndex = CurrentIndex + 1
		end
		
		local FrameA = rawget(FlatFrames, CurrentIndex)
		local FrameB = rawget(FlatFrames, CurrentIndex + 1)
		
		if FrameB then
			local Delta = FrameB.T - FrameA.T
			local Alpha = 0
			if Delta > 0 then Alpha = (Elapsed - FrameA.T) / Delta end
			Alpha = math.clamp(Alpha, 0, 1)
			
			local cfA = CFrame.new(unpack(FrameA.CF))
			local cfB = CFrame.new(unpack(FrameB.CF))
			local camA = CFrame.new(unpack(FrameA.CCF))
			local camB = CFrame.new(unpack(FrameB.CCF))
			
			Root.CFrame = cfA:Lerp(cfB, Alpha)
			Workspace.CurrentCamera.CFrame = camA:Lerp(camB, Alpha)
			Root.Velocity = Vector3.zero
			Root.RotVelocity = Vector3.zero

			if Animator and FrameA.A then
				local activeIds = {}
				local mergedAnims = {}

				if FrameA.A then
					for _, animA in ipairs(FrameA.A) do
						local pair = {A = animA, B = nil}
						rawset(mergedAnims, animA.U, pair)
					end
				end

				if FrameB.A then
					for _, animB in ipairs(FrameB.A) do
						local existing = rawget(mergedAnims, animB.U)
						if existing then
							rawset(existing, "B", animB)
						else
							local pair = {A = nil, B = animB}
							rawset(mergedAnims, animB.U, pair)
						end
					end
				end

				for uId, animPair in pairs(mergedAnims) do
					rawset(activeIds, uId, true)
					local track = rawget(PlaybackTracks, uId)
					
					local dataA = rawget(animPair, "A")
					local dataB = rawget(animPair, "B")
					local refData = dataA or dataB

					if not track then
						local anim = Instance.new("Animation")
						anim.AnimationId = refData.Id
						track = Animator:LoadAnimation(anim)
						rawset(PlaybackTracks, uId, track)
					end

					if refData.P then
						track.Priority = GetPriorityEnum(refData.P)
					end

					local startW = 0
					local endW = 0
					local startS = 1
					local endS = 1
					
					if dataA then 
						startW = dataA.W 
						startS = dataA.S or 1
					end
					if dataB then 
						endW = dataB.W 
						endS = dataB.S or 1
					end

					local targetWeight = startW + (endW - startW) * Alpha
					local targetSpeed = startS + (endS - startS) * Alpha
					local targetTime = 0

					if dataA and dataB then
						if dataB.T >= dataA.T then
							targetTime = dataA.T + (dataB.T - dataA.T) * Alpha
						else
							local len = track.Length
							if len > 0 then
								local dist = (len - dataA.T) + dataB.T
								targetTime = dataA.T + dist * Alpha
								if targetTime >= len then
									targetTime = targetTime - len
								end
							else
								targetTime = dataA.T
							end
						end
					elseif dataA then
						targetTime = dataA.T + Delta * Alpha
					elseif dataB then
						targetTime = math.max(0, dataB.T - Delta * (1 - Alpha))
					end

					if not track.IsPlaying then 
						track:Play(0, targetWeight, targetSpeed) 
						track.TimePosition = targetTime
					else
						track:AdjustWeight(targetWeight)
						track:AdjustSpeed(targetSpeed)
						
						if math.abs(track.TimePosition - targetTime) > 0.15 then
							track.TimePosition = targetTime
						end
					end
				end
				
				for uId, track in pairs(PlaybackTracks) do
					if not rawget(activeIds, uId) and track.IsPlaying then 
						track:Stop(0) 
					end
				end
			end
		else
			PlayConn:Disconnect()
			ViewingTAS = false
			getgenv().TAS_IsPlaying = false 
			Pause = true
			Root.Anchored = true
			
			if animateScript then animateScript.Disabled = false end
			for _, track in pairs(PlaybackTracks) do track:Stop(0) end
			PlaybackTracks = {}
			
			if Humanoid then
				Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
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
local function DisconnectAll()
	for _, c in pairs(Connections) do c:Disconnect() end
	for _, c in pairs(CharConnections) do c:Disconnect() end
	if HUD then HUD:Destroy() end
	if DebugView then ToggleDebugView() end
	
	local char = LocalPlayer.Character
	if char then
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then root.Anchored = false; root.Velocity = Vector3.zero end
		local animateScript = char:FindFirstChild("Animate")
		if animateScript then animateScript.Disabled = false end
	end
	
	for _, track in pairs(PlaybackTracks) do pcall(function() track:Stop(0) end) end
	PlaybackTracks = {}

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
			lastState = rawget(PlayerInfo, #PlayerInfo)
		elseif #Savestates > 0 then
			local lastList = rawget(Savestates, #Savestates)
			if lastList and #lastList > 0 then
				lastState = rawget(lastList, #lastList)
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
	TimeStart = tick()
	TimePauseHolder = tick()
	
	local initialData = ReturnPlayerInfo()
	initialData.T = 0
	table.insert(Savestates, {initialData})
	
	SetUpGui()
	updateStatusColor()
	
	table.insert(Connections, RunService.Heartbeat:Connect(function(dt)
		if not Pause and not ViewingTAS then
			local now = tick()
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
		elseif Key == Keybinds.GoFrameForward then task.spawn(function() handleHold(Key, GoFrameForward) end)
		elseif Key == Keybinds.GoFrameBack then task.spawn(function() handleHold(Key, GoFrameBack) end)
		end
	end))
	
	table.insert(Connections, UserInputService.InputEnded:Connect(function(Input)
		rawset(heldInputs, Input.KeyCode, false)
	end))
	
	table.insert(Connections, LocalPlayer.CharacterAdded:Connect(SetupCharacterConnections))
	if LocalPlayer.Character then SetupCharacterConnections(LocalPlayer.Character) end
	
	if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart") then
		LocalPlayer.Character.HumanoidRootPart.Anchored = true
		LocalPlayer.Character.HumanoidRootPart.Velocity = Vector3.new()
	end
	
	notify("TAS Recorder Initialized", "TAS")
end

Initialize()

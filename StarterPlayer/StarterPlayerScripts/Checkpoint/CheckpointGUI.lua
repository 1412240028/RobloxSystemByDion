-- CheckpointGUI.lua (FIXED VERSION)
-- ✅ FIXED: Removed DataStore access (client can't access DataStore)
-- ✅ FIXED: Proper cooldown handling for reset button
-- UI for checkpoint system (reset button and race status)

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.Config)
local SharedTypes = require(ReplicatedStorage.Modules.SharedTypes)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)

local CheckpointGUI = {}

-- Private variables
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = nil
local resetButton = nil
local statusLabel = nil
local cooldownOverlay = nil
local cooldownLabel = nil
local raceStatusLabel = nil

local isCooldown = false
local isInitialized = false

-- Store original button size
local originalButtonSize = nil

-- Client reference
local checkpointClient = nil

-- Notification variables
local skipNotificationLabel = nil
local successNotificationLabel = nil
local notificationTweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

-- Initialize GUI
function CheckpointGUI.Init()
	if isInitialized then
		warn("[CheckpointGUI] Already initialized, skipping")
		return
	end

	print("[CheckpointGUI] Initializing GUI")

	-- Create GUI structure
	CheckpointGUI.CreateGUI()

	-- Setup interactions
	CheckpointGUI.SetupInteractions()

	-- Set initial state
	CheckpointGUI.UpdateCheckpointData({currentCheckpoint = 0})

	isInitialized = true
	print("[CheckpointGUI] GUI initialized")
end

-- Create GUI structure
function CheckpointGUI.CreateGUI()
	-- ScreenGui
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CheckpointGUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	-- Main Frame (positioned next to sprint button)
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.BackgroundTransparency = 1
	mainFrame.Size = Config.IS_MOBILE and Config.CHECKPOINT_BUTTON_SIZE_MOBILE or Config.CHECKPOINT_BUTTON_SIZE_PC
	mainFrame.Position = Config.IS_MOBILE and Config.CHECKPOINT_BUTTON_POSITION_MOBILE or Config.CHECKPOINT_BUTTON_POSITION_PC
	mainFrame.AnchorPoint = Vector2.new(0, 0.5)
	mainFrame.Parent = screenGui

	-- Button
	resetButton = Instance.new("TextButton")
	resetButton.Name = "ResetButton"
	resetButton.BackgroundColor3 = Color3.fromRGB(150, 50, 50) -- Dark red for reset
	resetButton.Size = Config.IS_MOBILE and Config.CHECKPOINT_BUTTON_SIZE_MOBILE or Config.CHECKPOINT_BUTTON_SIZE_PC
	resetButton.Text = ""
	resetButton.AutoButtonColor = false
	resetButton.Parent = mainFrame

	-- Store original size
	originalButtonSize = resetButton.Size

	-- Corner radius
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Config.BUTTON_CORNER_RADIUS
	corner.Parent = resetButton

	-- Stroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = Config.BUTTON_STROKE_THICKNESS
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = resetButton

	-- Icon Label
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.BackgroundTransparency = 1
	iconLabel.Size = UDim2.new(1, 0, 0.4, 0)
	iconLabel.Position = UDim2.new(0, 0, 0.1, 0)
	iconLabel.Text = "🔄"
	iconLabel.TextScaled = true
	iconLabel.Font = Enum.Font.SourceSansBold
	iconLabel.TextColor3 = Color3.new(1, 1, 1)
	iconLabel.Parent = resetButton

	-- Status Label
	statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.BackgroundTransparency = 1
	statusLabel.Size = UDim2.new(1, 0, 0.25, 0)
	statusLabel.Position = UDim2.new(0, 0, 0.55, 0)
	statusLabel.Text = "CP: 0"
	statusLabel.TextScaled = true
	statusLabel.Font = Enum.Font.SourceSansBold
	statusLabel.TextColor3 = Color3.new(1, 1, 1)
	statusLabel.Parent = resetButton

	-- Cooldown Overlay
	cooldownOverlay = Instance.new("Frame")
	cooldownOverlay.Name = "CooldownOverlay"
	cooldownOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
	cooldownOverlay.BackgroundTransparency = 0.5
	cooldownOverlay.Size = UDim2.new(1, 0, 1, 0)
	cooldownOverlay.Visible = false
	cooldownOverlay.ZIndex = 3
	cooldownOverlay.Parent = resetButton

	local cooldownCorner = Instance.new("UICorner")
	cooldownCorner.CornerRadius = Config.BUTTON_CORNER_RADIUS
	cooldownCorner.Parent = cooldownOverlay

	-- ✅ NEW: Cooldown countdown label
	cooldownLabel = Instance.new("TextLabel")
	cooldownLabel.Name = "CooldownLabel"
	cooldownLabel.BackgroundTransparency = 1
	cooldownLabel.Size = UDim2.new(1, 0, 1, 0)
	cooldownLabel.Position = UDim2.new(0, 0, 0, 0)
	cooldownLabel.Text = "3"
	cooldownLabel.TextScaled = true
	cooldownLabel.Font = Enum.Font.SourceSansBold
	cooldownLabel.TextColor3 = Color3.new(1, 1, 1)
	cooldownLabel.ZIndex = 4
	cooldownLabel.Parent = cooldownOverlay

	-- ✅ NEW: Skip notification label
	skipNotificationLabel = Instance.new("TextLabel")
	skipNotificationLabel.Name = "SkipNotification"
	skipNotificationLabel.BackgroundColor3 = Color3.fromRGB(200, 50, 50) -- Red background
	skipNotificationLabel.BackgroundTransparency = 0.5
	skipNotificationLabel.Size = Config.NOTIFICATION_SIZE
	skipNotificationLabel.Position = Config.NOTIFICATION_POSITION -- Start at top center
	skipNotificationLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	skipNotificationLabel.Text = ""
	skipNotificationLabel.TextScaled = true
	skipNotificationLabel.Font = Enum.Font.SourceSansBold
	skipNotificationLabel.TextColor3 = Color3.new(1, 1, 1)
	skipNotificationLabel.Visible = false
	skipNotificationLabel.ZIndex = 10
	skipNotificationLabel.Parent = screenGui

	local skipCorner = Instance.new("UICorner")
	skipCorner.CornerRadius = UDim.new(0, 10)
	skipCorner.Parent = skipNotificationLabel

	local skipStroke = Instance.new("UIStroke")
	skipStroke.Thickness = 2
	skipStroke.Color = Color3.fromRGB(255, 100, 100)
	skipStroke.Parent = skipNotificationLabel

	-- ✅ NEW: Success notification label
	successNotificationLabel = Instance.new("TextLabel")
	successNotificationLabel.Name = "SuccessNotification"
	successNotificationLabel.BackgroundColor3 = Color3.fromRGB(50, 200, 50) -- Green background
	successNotificationLabel.BackgroundTransparency = 0.2
	successNotificationLabel.Size = Config.NOTIFICATION_SIZE
	successNotificationLabel.Position = Config.NOTIFICATION_POSITION -- Start at top center
	successNotificationLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	successNotificationLabel.Text = ""
	successNotificationLabel.TextScaled = true
	successNotificationLabel.Font = Enum.Font.SourceSansBold
	successNotificationLabel.TextColor3 = Color3.new(1, 1, 1)
	successNotificationLabel.Visible = false
	successNotificationLabel.ZIndex = 10
	successNotificationLabel.Parent = screenGui

	local successCorner = Instance.new("UICorner")
	successCorner.CornerRadius = UDim.new(0, 10)
	successCorner.Parent = successNotificationLabel

	local successStroke = Instance.new("UIStroke")
	successStroke.Thickness = 2
	successStroke.Color = Color3.fromRGB(100, 255, 100)
	successStroke.Parent = successNotificationLabel
end

-- Setup button interactions
function CheckpointGUI.SetupInteractions()
	-- PC Click
	resetButton.MouseButton1Click:Connect(function()
		CheckpointGUI.OnButtonPressed()
	end)

	-- Mobile Touch
	if Config.IS_MOBILE then
		resetButton.TouchTap:Connect(function()
			CheckpointGUI.OnButtonPressed()
		end)
	end

	-- Press animation
	resetButton.MouseButton1Down:Connect(function()
		CheckpointGUI.AnimatePress(true)
	end)

	resetButton.MouseButton1Up:Connect(function()
		CheckpointGUI.AnimatePress(false)
	end)
end

-- Handle button press
function CheckpointGUI.OnButtonPressed()
	if isCooldown then 
		print("[CheckpointGUI] Button press ignored - cooldown active")
		return 
	end

	-- Request reset through client reference
	if checkpointClient then
		print("[CheckpointGUI] Reset button pressed - requesting reset")
		checkpointClient.RequestReset()
		CheckpointGUI.ShowCooldown(3) -- 3 second cooldown for reset
	else
		warn("[CheckpointGUI] CheckpointClient reference not set!")
	end
end

-- Update checkpoint data
function CheckpointGUI.UpdateCheckpointData(syncData)
	if not statusLabel then return end

	local cp = syncData.currentCheckpoint or 0
	statusLabel.Text = "CP: " .. tostring(cp)

	print(string.format("[CheckpointGUI] Updated checkpoint display: CP %d", cp))
end

-- ✅ FIXED: Show cooldown with countdown
function CheckpointGUI.ShowCooldown(duration)
	if isCooldown then return end

	isCooldown = true
	cooldownOverlay.Visible = true

	print(string.format("[CheckpointGUI] Cooldown started: %d seconds", duration))

	-- Countdown timer
	local timeLeft = duration
	cooldownLabel.Text = tostring(math.ceil(timeLeft))

	-- Update countdown every 0.1 seconds
	local startTime = tick()
	local countdownConnection
	countdownConnection = game:GetService("RunService").Heartbeat:Connect(function()
		timeLeft = duration - (tick() - startTime)

		if timeLeft <= 0 then
			countdownConnection:Disconnect()
			CheckpointGUI.HideCooldown()
		else
			cooldownLabel.Text = tostring(math.ceil(timeLeft))
		end
	end)
end

-- Hide cooldown
function CheckpointGUI.HideCooldown()
	isCooldown = false
	cooldownOverlay.Visible = false
	print("[CheckpointGUI] Cooldown ended")
end

-- Animate button press
function CheckpointGUI.AnimatePress(isPressed)
	if not resetButton or not originalButtonSize then return end

	local targetScale = isPressed and Config.PRESS_SCALE or 1
	local duration = isPressed and Config.PRESS_DURATION or Config.RELEASE_DURATION

	local targetSize = UDim2.new(
		originalButtonSize.X.Scale * targetScale,
		originalButtonSize.X.Offset * targetScale,
		originalButtonSize.Y.Scale * targetScale,
		originalButtonSize.Y.Offset * targetScale
	)

	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local scaleTween = TweenService:Create(resetButton, tweenInfo, {Size = targetSize})
	scaleTween:Play()
end

-- Set client reference
function CheckpointGUI.SetClient(clientModule)
	checkpointClient = clientModule
	print("[CheckpointGUI] Client reference set successfully")
end

-- Show skip notification
function CheckpointGUI.ShowSkipNotification(message)
	if not skipNotificationLabel then return end

	skipNotificationLabel.Text = "❌ " .. message
	skipNotificationLabel.Visible = true

	-- Hide after display time
	task.delay(Config.NOTIFICATION_DISPLAY_TIME, function()
		if skipNotificationLabel then
			skipNotificationLabel.Visible = false
		end
	end)

	print("[CheckpointGUI] Skip notification shown: " .. message)
end

-- Show success notification
function CheckpointGUI.ShowSuccessNotification(checkpointId)
	if not successNotificationLabel then return end

	successNotificationLabel.Text = "✅ Checkpoint " .. checkpointId .. " tercapai!"
	successNotificationLabel.Visible = true

	-- Hide after display time
	task.delay(Config.NOTIFICATION_DISPLAY_TIME, function()
		if successNotificationLabel then
			successNotificationLabel.Visible = false
		end
	end)

	print("[CheckpointGUI] Success notification shown for checkpoint " .. checkpointId)
end

-- Cleanup
function CheckpointGUI.Cleanup()
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
	originalButtonSize = nil
	isInitialized = false
	print("[CheckpointGUI] Cleanup complete")
end

return CheckpointGUI

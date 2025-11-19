-- CheckpointGUI.lua
-- UI for checkpoint system (reset button and race status)
-- Similar to SprintGUI but for checkpoints

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
local raceStatusLabel = nil

local isCooldown = false
local isInitialized = false

-- Store original button size
local originalButtonSize = nil

-- Client reference
local checkpointClient = nil

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
	mainFrame.Size = Config.IS_MOBILE and Config.BUTTON_SIZE_MOBILE or Config.BUTTON_SIZE_PC
	mainFrame.Position = Config.IS_MOBILE and UDim2.new(0.05, 0, 0.85, 0) or UDim2.new(0.05, 0, 0.85, 0) -- Next to sprint
	mainFrame.AnchorPoint = Vector2.new(0, 0.5)
	mainFrame.Parent = screenGui

	-- Button
	resetButton = Instance.new("TextButton")
	resetButton.Name = "ResetButton"
	resetButton.BackgroundColor3 = Color3.new(0.5, 0.2, 0.2) -- Reddish color for reset
	resetButton.Size = UDim2.new(1, 0, 1, 0)
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
	cooldownOverlay.BackgroundTransparency = 0.7
	cooldownOverlay.Size = UDim2.new(1, 0, 1, 0)
	cooldownOverlay.Visible = false
	cooldownOverlay.ZIndex = 2
	cooldownOverlay.Parent = resetButton

	local cooldownCorner = Instance.new("UICorner")
	cooldownCorner.CornerRadius = Config.BUTTON_CORNER_RADIUS
	cooldownCorner.Parent = cooldownOverlay
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
	if isCooldown then return end

	-- Request reset through client reference
	if checkpointClient then
		checkpointClient.RequestReset()
		CheckpointGUI.ShowCooldown(1) -- 1 second cooldown for reset
	else
		warn("[CheckpointGUI] CheckpointClient reference not set!")
	end
end

-- Update checkpoint data
function CheckpointGUI.UpdateCheckpointData(syncData)
	if not statusLabel then return end

	local cp = syncData.currentCheckpoint or 0
	statusLabel.Text = "CP: " .. tostring(cp)
end

-- Show cooldown
function CheckpointGUI.ShowCooldown(duration)
	isCooldown = true
	cooldownOverlay.Visible = true

	task.delay(duration, function()
		CheckpointGUI.HideCooldown()
	end)
end

-- Hide cooldown
function CheckpointGUI.HideCooldown()
	isCooldown = false
	cooldownOverlay.Visible = false
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

-- Cleanup
function CheckpointGUI.Cleanup()
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
	originalButtonSize = nil
	isInitialized = false
end

return CheckpointGUI
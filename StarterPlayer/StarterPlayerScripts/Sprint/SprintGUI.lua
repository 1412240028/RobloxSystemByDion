-- SprintGUI.lua (FIXED BUTTON SHRINKING BUG)
-- Pure UI rendering & interaction
-- Visual only, logic handled by SprintClient

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Sprint.Config)
local SharedTypes = require(ReplicatedStorage.Sprint.SharedTypes)

local SprintGUI = {}

-- Private variables
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = nil
local sprintButton = nil
local statusLabel = nil
local cooldownOverlay = nil

local currentState = SharedTypes.UIState.OFF
local isCooldown = false

-- NEW: Store original button size to prevent shrinking
local originalButtonSize = nil

-- Client reference
local sprintClient = nil

-- Initialize GUI
function SprintGUI.Init()
	print("[SprintGUI] Initializing GUI")

	-- Create GUI structure
	SprintGUI.CreateGUI()

	-- Setup interactions
	SprintGUI.SetupInteractions()

	-- Set initial state
	SprintGUI.UpdateVisualState(false)

	print("[SprintGUI] GUI initialized")
end

-- Create GUI structure
function SprintGUI.CreateGUI()
	-- ScreenGui
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "SprintGUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	-- Main Frame
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.BackgroundTransparency = 1
	mainFrame.Size = Config.IS_MOBILE and Config.BUTTON_SIZE_MOBILE or Config.BUTTON_SIZE_PC
	mainFrame.Position = Config.IS_MOBILE and Config.BUTTON_POSITION_MOBILE or Config.BUTTON_POSITION_PC
	mainFrame.AnchorPoint = Vector2.new(0, 0.5)
	mainFrame.Parent = screenGui

	-- Button
	sprintButton = Instance.new("TextButton")
	sprintButton.Name = "SprintButton"
	sprintButton.BackgroundColor3 = Config.BUTTON_COLOR_OFF
	sprintButton.Size = UDim2.new(1, 0, 1, 0)
	sprintButton.Text = ""
	sprintButton.AutoButtonColor = false
	sprintButton.Parent = mainFrame

	-- NEW: Store original size
	originalButtonSize = sprintButton.Size

	-- Corner radius
	local corner = Instance.new("UICorner")
	corner.CornerRadius = Config.BUTTON_CORNER_RADIUS
	corner.Parent = sprintButton

	-- Stroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = Config.BUTTON_STROKE_THICKNESS
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = sprintButton

	-- Icon Label
	local iconLabel = Instance.new("TextLabel")
	iconLabel.Name = "Icon"
	iconLabel.BackgroundTransparency = 1
	iconLabel.Size = UDim2.new(1, 0, 0.4, 0)
	iconLabel.Position = UDim2.new(0, 0, 0.1, 0)
	iconLabel.Text = "⚡"
	iconLabel.TextScaled = true
	iconLabel.Font = Enum.Font.SourceSansBold
	iconLabel.TextColor3 = Color3.new(1, 1, 1)
	iconLabel.Parent = sprintButton

	-- Status Label
	statusLabel = Instance.new("TextLabel")
	statusLabel.Name = "Status"
	statusLabel.BackgroundTransparency = 1
	statusLabel.Size = UDim2.new(1, 0, 0.25, 0)
	statusLabel.Position = UDim2.new(0, 0, 0.55, 0)
	statusLabel.Text = "OFF"
	statusLabel.TextScaled = true
	statusLabel.Font = Enum.Font.SourceSansBold
	statusLabel.TextColor3 = Color3.new(1, 1, 1)
	statusLabel.Parent = sprintButton

	-- Cooldown Overlay
	cooldownOverlay = Instance.new("Frame")
	cooldownOverlay.Name = "CooldownOverlay"
	cooldownOverlay.BackgroundColor3 = Color3.new(0, 0, 0)
	cooldownOverlay.BackgroundTransparency = 0.7
	cooldownOverlay.Size = UDim2.new(1, 0, 1, 0)
	cooldownOverlay.Visible = false
	cooldownOverlay.ZIndex = 2
	cooldownOverlay.Parent = sprintButton

	local cooldownCorner = Instance.new("UICorner")
	cooldownCorner.CornerRadius = Config.BUTTON_CORNER_RADIUS
	cooldownCorner.Parent = cooldownOverlay
end

-- Setup button interactions
function SprintGUI.SetupInteractions()
	-- PC Click
	sprintButton.MouseButton1Click:Connect(function()
		SprintGUI.OnButtonPressed()
	end)

	-- Mobile Touch
	if Config.IS_MOBILE then
		sprintButton.TouchTap:Connect(function()
			SprintGUI.OnButtonPressed()
		end)
	end

	-- Press animation
	sprintButton.MouseButton1Down:Connect(function()
		SprintGUI.AnimatePress(true)
	end)

	sprintButton.MouseButton1Up:Connect(function()
		SprintGUI.AnimatePress(false)
	end)
end

-- Handle button press
function SprintGUI.OnButtonPressed()
	if isCooldown then return end

	-- Request toggle through client reference
	if sprintClient then
		sprintClient.RequestToggle()
	end
end

-- Update visual state
function SprintGUI.UpdateVisualState(isSprinting)
	local newState = isSprinting and SharedTypes.UIState.ON or SharedTypes.UIState.OFF
	currentState = newState

	-- Update colors
	local targetColor = isSprinting and Config.BUTTON_COLOR_ON or Config.BUTTON_COLOR_OFF
	local tweenInfo = TweenInfo.new(Config.STATE_CHANGE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	local colorTween = TweenService:Create(sprintButton, tweenInfo, {BackgroundColor3 = targetColor})
	colorTween:Play()

	-- Update text
	statusLabel.Text = isSprinting and "ON" or "OFF"
end

-- Show cooldown
function SprintGUI.ShowCooldown(duration)
	isCooldown = true
	cooldownOverlay.Visible = true

	task.delay(duration, function()
		SprintGUI.HideCooldown()
	end)
end

-- Hide cooldown
function SprintGUI.HideCooldown()
	isCooldown = false
	cooldownOverlay.Visible = false
end

-- Show error state
function SprintGUI.ShowError(message)
	statusLabel.Text = "ERROR"
	sprintButton.BackgroundColor3 = Color3.new(1, 0, 0) -- Red

	task.delay(1, function()
		SprintGUI.UpdateVisualState(currentState == SharedTypes.UIState.ON)
	end)
end

-- Animate button press (FIXED)
function SprintGUI.AnimatePress(isPressed)
	if not sprintButton or not originalButtonSize then return end

	-- NEW: Always calculate from original size, not current size
	local targetScale = isPressed and Config.PRESS_SCALE or 1
	local duration = isPressed and Config.PRESS_DURATION or Config.RELEASE_DURATION

	-- Calculate target size based on ORIGINAL size
	local targetSize = UDim2.new(
		originalButtonSize.X.Scale * targetScale,
		originalButtonSize.X.Offset * targetScale,
		originalButtonSize.Y.Scale * targetScale,
		originalButtonSize.Y.Offset * targetScale
	)

	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local scaleTween = TweenService:Create(sprintButton, tweenInfo, {Size = targetSize})
	scaleTween:Play()
end

-- Get current UI state
function SprintGUI.GetCurrentState()
	return currentState
end

-- Set client reference
function SprintGUI.SetClient(clientModule)
	sprintClient = clientModule
end

-- Cleanup
function SprintGUI.Cleanup()
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
	originalButtonSize = nil
end

-- Initialize when script runs
SprintGUI.Init()

return SprintGUI
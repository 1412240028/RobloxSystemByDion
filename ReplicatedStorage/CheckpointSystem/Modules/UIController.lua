-- Checkpoint System V1.0 - UI Controller Module
-- Handles all client-side UI notifications and animations

local TweenService = game:GetService("TweenService")
local Settings = require(game.ReplicatedStorage.CheckpointSystem.Config.Settings)

local UIController = {}

-- Private variables
local notificationFrame = nil
local isInitialized = false

-- Logger utility
local function Log(level, message, ...)
	if not Settings.DEBUG_MODE and level == "DEBUG" then return end

	local prefix = "[UIController]"
	if level == "ERROR" then
		warn(prefix .. " " .. string.format(message, ...))
	elseif level == "WARN" then
		warn(prefix .. " " .. string.format(message, ...))
	elseif level == "INFO" or (Settings.DEBUG_MODE and level == "DEBUG") then
		print(prefix .. " " .. string.format(message, ...))
	end
end

-- Initialize the UI controller
function UIController.Initialize()
	if isInitialized then
		Log("WARN", "UIController already initialized")
		return true
	end

	Log("INFO", "Initializing UIController...")

	-- Create notification UI
	local success = UIController.CreateNotificationUI()

	if success then
		isInitialized = true
		Log("INFO", "UIController initialized successfully")
	else
		Log("ERROR", "Failed to initialize UIController")
	end

	return success
end

-- Create the notification UI frame
function UIController.CreateNotificationUI()
	-- Check if StarterGui exists
	local starterGui = game:GetService("StarterGui")
	if not starterGui then
		Log("ERROR", "StarterGui not found")
		return false
	end

	-- Create main frame
	notificationFrame = Instance.new("Frame")
	notificationFrame.Name = "CheckpointNotification"
	notificationFrame.Size = UDim2.new(0.4, 0, 0.1, 0)
	notificationFrame.Position = UDim2.new(0.3, 0, -0.1, 0) -- Start above screen
	notificationFrame.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
	notificationFrame.BackgroundTransparency = 0.1
	notificationFrame.BorderSizePixel = 0

	-- Add corner radius
	local cornerRadius = Instance.new("UICorner")
	cornerRadius.CornerRadius = UDim.new(0.2, 0)
	cornerRadius.Parent = notificationFrame

	-- Add stroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 2
	stroke.Parent = notificationFrame

	-- Create text label
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "NotificationText"
	textLabel.Size = UDim2.new(1, 0, 1, 0)
	textLabel.Position = UDim2.new(0, 0, 0, 0)
	textLabel.BackgroundTransparency = 1
	textLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	textLabel.TextScaled = true
	textLabel.Font = Enum.Font.SourceSansBold
	textLabel.Text = "Checkpoint Reached!"
	textLabel.Parent = notificationFrame

	-- Add text stroke for better visibility
	local textStroke = Instance.new("UIStroke")
	textStroke.Color = Color3.fromRGB(0, 0, 0)
	textStroke.Thickness = 1
	textStroke.Parent = textLabel

	-- Create ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CheckpointUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Parent the frame to ScreenGui
	notificationFrame.Parent = screenGui

	-- Parent ScreenGui to StarterGui
	screenGui.Parent = starterGui

	Log("DEBUG", "Notification UI created successfully")
	return true
end

-- Show checkpoint notification
function UIController.ShowCheckpointNotification(checkpointOrder, totalCheckpoints)
	if not isInitialized or not notificationFrame then
		Log("ERROR", "UIController not initialized or notification frame missing")
		return false
	end

	-- Update text
	local textLabel = notificationFrame:FindFirstChild("NotificationText")
	if textLabel then
		local progressText = string.format("Checkpoint %d/%d Reached!", checkpointOrder, totalCheckpoints or 0)
		textLabel.Text = progressText
		Log("DEBUG", "Showing notification: %s", progressText)
	end

	-- Animate in
	UIController.AnimateNotificationIn()

	-- Schedule auto-hide
	delay(Settings.NOTIFICATION_DURATION, function()
		UIController.AnimateNotificationOut()
	end)

	return true
end

-- Animate notification sliding in
function UIController.AnimateNotificationIn()
	if not notificationFrame then return end

	-- Start position (above screen)
	notificationFrame.Position = UDim2.new(0.3, 0, -0.1, 0)

	-- Tween to visible position
	local tweenInfo = TweenInfo.new(
		Settings.NOTIFICATION_ANIMATION_SPEED,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	)

	local tween = TweenService:Create(notificationFrame, tweenInfo, {
		Position = UDim2.new(0.3, 0, 0.05, 0)
	})

	tween:Play()
	Log("DEBUG", "Animating notification in")
end

-- Animate notification sliding out
function UIController.AnimateNotificationOut()
	if not notificationFrame then return end

	-- Tween back up
	local tweenInfo = TweenInfo.new(
		Settings.NOTIFICATION_ANIMATION_SPEED,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.In
	)

	local tween = TweenService:Create(notificationFrame, tweenInfo, {
		Position = UDim2.new(0.3, 0, -0.1, 0)
	})

	tween:Play()
	Log("DEBUG", "Animating notification out")
end

-- Show custom notification
function UIController.ShowCustomNotification(message, duration)
	if not isInitialized or not notificationFrame then
		Log("ERROR", "UIController not initialized")
		return false
	end

	duration = duration or Settings.NOTIFICATION_DURATION

	-- Update text
	local textLabel = notificationFrame:FindFirstChild("NotificationText")
	if textLabel then
		textLabel.Text = message
		Log("DEBUG", "Showing custom notification: %s", message)
	end

	-- Animate in
	UIController.AnimateNotificationIn()

	-- Schedule auto-hide
	delay(duration, function()
		UIController.AnimateNotificationOut()
	end)

	return true
end

-- Hide notification immediately
function UIController.HideNotification()
	if not notificationFrame then return end

	notificationFrame.Position = UDim2.new(0.3, 0, -0.1, 0)
	Log("DEBUG", "Notification hidden immediately")
end

-- Update notification style (for theming)
function UIController.UpdateNotificationStyle(style)
	if not notificationFrame then return false end

	style = style or {}

	-- Update colors
	if style.backgroundColor then
		notificationFrame.BackgroundColor3 = style.backgroundColor
	end

	if style.textColor then
		local textLabel = notificationFrame:FindFirstChild("NotificationText")
		if textLabel then
			textLabel.TextColor3 = style.textColor
		end
	end

	if style.strokeColor then
		local stroke = notificationFrame:FindFirstChild("UIStroke")
		if stroke then
			stroke.Color = style.strokeColor
		end
	end

	Log("DEBUG", "Updated notification style")
	return true
end

-- Get notification status
function UIController.GetNotificationStatus()
	if not notificationFrame then
		return { Visible = false }
	end

	return {
		Visible = notificationFrame.Position.Y.Scale > 0,
		Position = notificationFrame.Position,
		Text = notificationFrame:FindFirstChild("NotificationText") and
			notificationFrame.NotificationText.Text or ""
	}
end

-- Test notification (for debugging)
function UIController.TestNotification()
	if not Settings.DEBUG_MODE then
		Log("WARN", "Test notification called outside debug mode")
		return
	end

	UIController.ShowCustomNotification("Test Notification", 2)
	Log("INFO", "Test notification shown")
end

-- Cleanup function
function UIController.Cleanup()
	if notificationFrame then
		local screenGui = notificationFrame.Parent
		if screenGui then
			screenGui:Destroy()
		end
		notificationFrame = nil
	end

	isInitialized = false
	Log("INFO", "UIController cleaned up")
end

return UIController

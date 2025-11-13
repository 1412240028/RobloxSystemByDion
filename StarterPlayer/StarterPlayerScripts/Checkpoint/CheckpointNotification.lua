-- CheckpointNotification.lua
-- UI for race notifications and status
-- Displays race start, finish, winner notifications

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.Config)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)

local CheckpointNotification = {}

-- Private variables
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = nil
local notificationFrame = nil
local notificationLabel = nil
local raceStatusFrame = nil
local raceStatusLabel = nil

local activeNotifications = {}
local isInitialized = false

-- Initialize notification system
function CheckpointNotification.Init()
	if isInitialized then
		warn("[CheckpointNotification] Already initialized, skipping")
		return
	end

	print("[CheckpointNotification] Initializing notification system")

	-- Create GUI structure
	CheckpointNotification.CreateGUI()

	-- Connect to race events
	CheckpointNotification.ConnectEvents()

	isInitialized = true
	print("[CheckpointNotification] Notification system initialized")
end

-- Create GUI structure
function CheckpointNotification.CreateGUI()
	-- ScreenGui
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CheckpointNotificationGUI"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	-- Notification Frame (for race notifications)
	notificationFrame = Instance.new("Frame")
	notificationFrame.Name = "NotificationFrame"
	notificationFrame.BackgroundColor3 = Color3.new(0, 0, 0)
	notificationFrame.BackgroundTransparency = 0.3
	notificationFrame.Size = Config.NOTIFICATION_SIZE
	notificationFrame.Position = Config.NOTIFICATION_POSITION
	notificationFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	notificationFrame.Visible = false
	notificationFrame.ZIndex = 10
	notificationFrame.Parent = screenGui

	local notificationCorner = Instance.new("UICorner")
	notificationCorner.CornerRadius = UDim.new(0, 8)
	notificationCorner.Parent = notificationFrame

	local notificationStroke = Instance.new("UIStroke")
	notificationStroke.Thickness = 2
	notificationStroke.Color = Color3.new(1, 1, 1)
	notificationStroke.Parent = notificationFrame

	notificationLabel = Instance.new("TextLabel")
	notificationLabel.Name = "NotificationLabel"
	notificationLabel.BackgroundTransparency = 1
	notificationLabel.Size = UDim2.new(1, -20, 1, -20)
	notificationLabel.Position = UDim2.new(0, 10, 0, 10)
	notificationLabel.Text = ""
	notificationLabel.TextScaled = true
	notificationLabel.Font = Enum.Font.SourceSansBold
	notificationLabel.TextColor3 = Color3.new(1, 1, 1)
	notificationLabel.TextWrapped = true
	notificationLabel.Parent = notificationFrame

	-- Race Status Frame (persistent race info)
	raceStatusFrame = Instance.new("Frame")
	raceStatusFrame.Name = "RaceStatusFrame"
	raceStatusFrame.BackgroundColor3 = Color3.new(0, 0, 0)
	raceStatusFrame.BackgroundTransparency = 0.5
	raceStatusFrame.Size = UDim2.new(0, 200, 0, 40)
	raceStatusFrame.Position = UDim2.new(0.5, 0, 0.05, 0)
	raceStatusFrame.AnchorPoint = Vector2.new(0.5, 0)
	raceStatusFrame.Visible = false
	raceStatusFrame.ZIndex = 5
	raceStatusFrame.Parent = screenGui

	local raceStatusCorner = Instance.new("UICorner")
	raceStatusCorner.CornerRadius = UDim.new(0, 6)
	raceStatusCorner.Parent = raceStatusFrame

	raceStatusLabel = Instance.new("TextLabel")
	raceStatusLabel.Name = "RaceStatusLabel"
	raceStatusLabel.BackgroundTransparency = 1
	raceStatusLabel.Size = UDim2.new(1, -10, 1, -10)
	raceStatusLabel.Position = UDim2.new(0, 5, 0, 5)
	raceStatusLabel.Text = "Race: Not Active"
	raceStatusLabel.TextScaled = true
	raceStatusLabel.Font = Enum.Font.SourceSansBold
	raceStatusLabel.TextColor3 = Config.RACE_INACTIVE_COLOR
	raceStatusLabel.Parent = raceStatusFrame
end

-- Connect to race events
function CheckpointNotification.ConnectEvents()
	-- Race start
	RemoteEvents.OnRaceStartReceived(function(raceData)
		CheckpointNotification.ShowNotification("🏁 Race Started! Go!", Config.RACE_ACTIVE_COLOR)
		CheckpointNotification.UpdateRaceStatus(true, raceData)
	end)

	-- Race end
	RemoteEvents.OnRaceEndReceived(function(raceResults)
		local message = "🏁 Race Ended!"
		if raceResults.winner then
			if raceResults.winner == player.Name then
				message = "🏆 You Won the Race!"
			else
				message = string.format("🏁 Race Ended - Winner: %s", raceResults.winner)
			end
		end
		CheckpointNotification.ShowNotification(message, Config.RACE_FINISHED_COLOR)
		CheckpointNotification.UpdateRaceStatus(false)
	end)

	-- Race notifications (personal)
	RemoteEvents.OnRaceNotificationReceived(function(notificationData)
		local color = Config.RACE_ACTIVE_COLOR
		if notificationData.type == "winner" then
			color = Config.RACE_FINISHED_COLOR
		elseif notificationData.type == "finished" then
			color = Color3.fromRGB(0, 150, 255) -- Blue for placement
		end
		CheckpointNotification.ShowNotification(notificationData.message, color)
	end)

	-- Leaderboard updates
	RemoteEvents.OnLeaderboardUpdateReceived(function(leaderboard)
		-- Could update a leaderboard display here if implemented
		print("[CheckpointNotification] Leaderboard updated")
	end)
end

-- Show notification
function CheckpointNotification.ShowNotification(message, color)
	-- Cancel any existing notification
	if activeNotifications[1] then
		activeNotifications[1]:Cancel()
		table.remove(activeNotifications, 1)
	end

	notificationLabel.Text = message
	notificationFrame.BackgroundColor3 = color or Config.RACE_ACTIVE_COLOR
	notificationFrame.Visible = true

	-- Animate in
	local fadeInTween = TweenService:Create(notificationFrame,
		TweenInfo.new(Config.NOTIFICATION_FADE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{BackgroundTransparency = 0.1})
	fadeInTween:Play()

	-- Schedule hide
	local notificationId = {}
	notificationId.tween = task.delay(Config.NOTIFICATION_DISPLAY_TIME, function()
		CheckpointNotification.HideNotification(notificationId)
	end)

	table.insert(activeNotifications, notificationId)
end

-- Hide notification
function CheckpointNotification.HideNotification(notificationId)
	if not notificationId or not notificationId.active then return end

	local fadeOutTween = TweenService:Create(notificationFrame,
		TweenInfo.new(Config.NOTIFICATION_FADE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.In),
		{BackgroundTransparency = 1})

	fadeOutTween:Play()
	fadeOutTween.Completed:Connect(function()
		notificationFrame.Visible = false
	end)

	notificationId.active = false
end

-- Update race status display
function CheckpointNotification.UpdateRaceStatus(isActive, raceData)
	if not raceStatusFrame or not raceStatusLabel then return end

	if isActive and raceData then
		raceStatusFrame.Visible = true
		raceStatusLabel.Text = string.format("Race Active - %d Players", raceData.participantCount or 0)
		raceStatusLabel.TextColor3 = Config.RACE_ACTIVE_COLOR
	else
		raceStatusFrame.Visible = false
		raceStatusLabel.Text = "Race: Not Active"
		raceStatusLabel.TextColor3 = Config.RACE_INACTIVE_COLOR
	end
end

-- Cleanup
function CheckpointNotification.Cleanup()
	-- Cancel all notifications
	for _, notificationId in ipairs(activeNotifications) do
		if notificationId.tween then
			task.cancel(notificationId.tween)
		end
	end
	activeNotifications = {}

	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end

	isInitialized = false
end

return CheckpointNotification

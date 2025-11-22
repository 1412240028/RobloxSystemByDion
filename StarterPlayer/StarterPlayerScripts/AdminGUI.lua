-- AdminGUI.lua
-- Modern Admin Control Panel with Command Execution
-- ⚠️ LOKASI: StarterPlayer/StarterPlayerScripts/AdminGUI.lua (FILE BARU)
-- ⚠️ ATAU: StarterGui/AdminGUI (LocalScript)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ✅ Wait for modules (kompatibel dengan struktur repo)
local SystemManager = nil
local Config = nil
local RemoteEvents = nil
local RemoteFunctions = nil

-- Load modules dengan error handling
local function loadModules()
	local maxAttempts = 10
	local attempt = 0

	while attempt < maxAttempts do
		attempt = attempt + 1

		local success = pcall(function()
			SystemManager = require(ReplicatedStorage.Modules.SystemManager)
			Config = require(ReplicatedStorage.Config.Config)
			RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
			RemoteFunctions = require(ReplicatedStorage.Remotes.RemoteFunctions)
		end)

		if success and SystemManager and Config and RemoteFunctions then
			print("[AdminGUI] ✅ Modules loaded successfully")
			return true
		end

		warn(string.format("[AdminGUI] ⚠️ Module load attempt %d/%d failed", attempt, maxAttempts))
		wait(1)
	end

	warn("[AdminGUI] ❌ Failed to load modules after", maxAttempts, "attempts")
	return false
end

if not loadModules() then
	return -- Exit if modules failed to load
end

-- Client-side admin cache
local clientAdminCache = {}

-- Listen for admin cache sync from server
RemoteEvents.OnAdminCacheSyncReceived(function(adminCache)
	clientAdminCache = {}
	for k, v in pairs(adminCache or {}) do
		local numKey = tonumber(k)
		if numKey then
			clientAdminCache[numKey] = v
		end
	end
	local count = 0
	for _ in pairs(clientAdminCache) do count = count + 1 end
	print("[AdminGUI] Admin cache synced from server - " .. count .. " admins")
end)

-- Request admin cache sync from server on startup
RemoteEvents.FireAdminCacheSyncRequest()
print("[AdminGUI] Requested admin cache sync from server")

-- GUI State
local adminData = nil
local isOpen = false
local currentPage = "Dashboard"

-- ✅ Commands by Permission Level
local COMMANDS_BY_LEVEL = {
	MEMBER = {
		{name = "status", desc = "Show system status", args = ""},
		{name = "players", desc = "List all players", args = ""},
		{name = "help", desc = "Show help", args = ""},
	},
	HELPER = {
		{name = "cp_status", desc = "Check checkpoint status", args = "[playerName]"},
	},
	MODERATOR = {
		{name = "reset_cp", desc = "Reset checkpoints", args = "<playerName>"},
		{name = "set_cp", desc = "Set checkpoint", args = "<playerName> <id>"},
		{name = "startrace", desc = "Start race", args = ""},
		{name = "endrace", desc = "End race", args = ""},
	},
	DEVELOPER = {
		{name = "reset_all_cp", desc = "Reset all checkpoints", args = ""},
		{name = "finish_race", desc = "Force finish race", args = "<playerName>"},
	},
	OWNER = {
		{name = "add_admin", desc = "Add admin", args = "<userId> <permission>"},
		{name = "remove_admin", desc = "Remove admin", args = "<userId>"},
	}
}

-- ✅ Create Main GUI
local function CreateAdminGUI()
	-- Screen GUI
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "AdminControlPanel"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- Toggle Button (when closed)
	local toggleButton = Instance.new("TextButton")
	toggleButton.Name = "ToggleButton"
	toggleButton.Size = UDim2.new(0, 180, 0, 45)
	toggleButton.Position = UDim2.new(0.5, -90, 0, 20)
	toggleButton.BackgroundColor3 = Color3.fromRGB(20, 40, 80)
	toggleButton.BorderSizePixel = 0
	toggleButton.Font = Enum.Font.GothamBold
	toggleButton.Text = "⚙️ ADMIN PANEL"
	toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	toggleButton.TextSize = 16
	toggleButton.Visible = true
	toggleButton.Parent = screenGui

	-- Corner
	local toggleCorner = Instance.new("UICorner")
	toggleCorner.CornerRadius = UDim.new(0, 8)
	toggleCorner.Parent = toggleButton

	-- Main Frame (Panel)
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(0, 700, 0, 500)
	mainFrame.Position = UDim2.new(0.5, -350, 0.5, -250)
	mainFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	mainFrame.BorderSizePixel = 0
	mainFrame.Visible = false
	mainFrame.Parent = screenGui

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0, 12)
	mainCorner.Parent = mainFrame

	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 50)
	header.BackgroundColor3 = Color3.fromRGB(20, 40, 80)
	header.BorderSizePixel = 0
	header.Parent = mainFrame

	local headerCorner = Instance.new("UICorner")
	headerCorner.CornerRadius = UDim.new(0, 12)
	headerCorner.Parent = header

	-- Fix corner overlap
	local headerFix = Instance.new("Frame")
	headerFix.Size = UDim2.new(1, 0, 0, 12)
	headerFix.Position = UDim2.new(0, 0, 1, -12)
	headerFix.BackgroundColor3 = Color3.fromRGB(20, 40, 80)
	headerFix.BorderSizePixel = 0
	headerFix.Parent = header

	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -120, 1, 0)
	title.Position = UDim2.new(0, 15, 0, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = "⚙️ ADMIN CONTROL PANEL"
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = header

	-- Close Button
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.new(0, 100, 0, 35)
	closeButton.Position = UDim2.new(1, -110, 0.5, -17.5)
	closeButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeButton.BorderSizePixel = 0
	closeButton.Font = Enum.Font.GothamBold
	closeButton.Text = "✕ CLOSE"
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.TextSize = 14
	closeButton.Parent = header

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0, 6)
	closeCorner.Parent = closeButton

	-- Content Container
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(1, -20, 1, -70)
	content.Position = UDim2.new(0, 10, 0, 60)
	content.BackgroundTransparency = 1
	content.Parent = mainFrame

	-- Tab Buttons Container
	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
	tabBar.Size = UDim2.new(1, 0, 0, 40)
	tabBar.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	tabBar.BorderSizePixel = 0
	tabBar.Parent = content

	local tabCorner = Instance.new("UICorner")
	tabCorner.CornerRadius = UDim.new(0, 8)
	tabCorner.Parent = tabBar

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 5)
	tabLayout.Parent = tabBar

	-- Pages Container
	local pagesContainer = Instance.new("Frame")
	pagesContainer.Name = "Pages"
	pagesContainer.Size = UDim2.new(1, 0, 1, -50)
	pagesContainer.Position = UDim2.new(0, 0, 0, 50)
	pagesContainer.BackgroundTransparency = 1
	pagesContainer.Parent = content

	return screenGui, mainFrame, toggleButton, closeButton, tabBar, pagesContainer
end

-- ✅ Create Tab Button
local function CreateTabButton(parent, name, index)
	local button = Instance.new("TextButton")
	button.Name = name .. "Tab"
	button.Size = UDim2.new(0, 160, 1, -10)
	button.Position = UDim2.new(0, (index - 1) * 165 + 5, 0, 5)
	button.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBold
	button.Text = name
	button.TextColor3 = Color3.fromRGB(150, 150, 150)
	button.TextSize = 14
	button.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	return button
end

-- ✅ Create Dashboard Page
local function CreateDashboard(parent, adminData)
	local page = Instance.new("ScrollingFrame")
	page.Name = "DashboardPage"
	page.Size = UDim2.new(1, 0, 1, 0)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 6
	page.CanvasSize = UDim2.new(0, 0, 0, 300)
	page.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = page

	-- Admin Info Card
	local infoCard = Instance.new("Frame")
	infoCard.Size = UDim2.new(1, 0, 0, 120)
	infoCard.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	infoCard.BorderSizePixel = 0
	infoCard.Parent = page

	local infoCorner = Instance.new("UICorner")
	infoCorner.CornerRadius = UDim.new(0, 10)
	infoCorner.Parent = infoCard

	local infoTitle = Instance.new("TextLabel")
	infoTitle.Size = UDim2.new(1, -20, 0, 30)
	infoTitle.Position = UDim2.new(0, 10, 0, 10)
	infoTitle.BackgroundTransparency = 1
	infoTitle.Font = Enum.Font.GothamBold
	infoTitle.Text = "👤 ADMIN INFORMATION"
	infoTitle.TextColor3 = Color3.fromRGB(100, 180, 255)
	infoTitle.TextSize = 16
	infoTitle.TextXAlignment = Enum.TextXAlignment.Left
	infoTitle.Parent = infoCard

	local infoText = Instance.new("TextLabel")
	infoText.Size = UDim2.new(1, -20, 0, 70)
	infoText.Position = UDim2.new(0, 10, 0, 45)
	infoText.BackgroundTransparency = 1
	infoText.Font = Enum.Font.Gotham
	infoText.Text = string.format(
		"Name: %s\nUserID: %d\nPermission: %s\nLevel: %d",
		player.Name, player.UserId,
		adminData.permission or "UNKNOWN",
		adminData.level or 0
	)
	infoText.TextColor3 = Color3.fromRGB(200, 200, 200)
	infoText.TextSize = 14
	infoText.TextXAlignment = Enum.TextXAlignment.Left
	infoText.TextYAlignment = Enum.TextYAlignment.Top
	infoText.Parent = infoCard

	-- Server Stats Card
	local statsCard = Instance.new("Frame")
	statsCard.Size = UDim2.new(1, 0, 0, 150)
	statsCard.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	statsCard.BorderSizePixel = 0
	statsCard.Parent = page

	local statsCorner = Instance.new("UICorner")
	statsCorner.CornerRadius = UDim.new(0, 10)
	statsCorner.Parent = statsCard

	local statsTitle = Instance.new("TextLabel")
	statsTitle.Size = UDim2.new(1, -20, 0, 30)
	statsTitle.Position = UDim2.new(0, 10, 0, 10)
	statsTitle.BackgroundTransparency = 1
	statsTitle.Font = Enum.Font.GothamBold
	statsTitle.Text = "📊 SERVER STATISTICS"
	statsTitle.TextColor3 = Color3.fromRGB(100, 255, 150)
	statsTitle.TextSize = 16
	statsTitle.TextXAlignment = Enum.TextXAlignment.Left
	statsTitle.Parent = statsCard

	local statsText = Instance.new("TextLabel")
	statsText.Name = "StatsText"
	statsText.Size = UDim2.new(1, -20, 0, 100)
	statsText.Position = UDim2.new(0, 10, 0, 45)
	statsText.BackgroundTransparency = 1
	statsText.Font = Enum.Font.Gotham
	statsText.Text = "Loading..."
	statsText.TextColor3 = Color3.fromRGB(200, 200, 200)
	statsText.TextSize = 14
	statsText.TextXAlignment = Enum.TextXAlignment.Left
	statsText.TextYAlignment = Enum.TextYAlignment.Top
	statsText.Parent = statsCard

	-- Update stats
	spawn(function()
		while page.Parent do
			if SystemManager then
				local status = SystemManager:GetSystemStatus()
				statsText.Text = string.format(
					"Players Online: %d\nAdmin Count: %d\nCheckpoint System: %s\nSprint System: %s\nVersion: %s",
					status.playerCount or 0,
					status.adminCount or 0,
					status.checkpointSystemActive and "✅ Active" or "❌ Inactive",
					status.sprintSystemActive and "✅ Active" or "❌ Inactive",
					status.version or "Unknown"
				)
			end
			wait(5)
		end
	end)

	return page
end

-- ✅ Create Command Page
local function CreateCommandPage(parent, adminData)
	local page = Instance.new("ScrollingFrame")
	page.Name = "CommandPage"
	page.Size = UDim2.new(1, 0, 1, 0)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 6
	page.Visible = false
	page.Parent = parent

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = page

	-- Get available commands based on permission
	local availableCommands = {}
	local permissionOrder = {"MEMBER", "HELPER", "MODERATOR", "DEVELOPER", "OWNER"}

	for _, perm in ipairs(permissionOrder) do
		local permLevel = Config and Config.ADMIN_PERMISSION_LEVELS[perm] or 0
		if adminData.level >= permLevel then
			for _, cmd in ipairs(COMMANDS_BY_LEVEL[perm] or {}) do
				table.insert(availableCommands, {
					name = cmd.name,
					desc = cmd.desc,
					args = cmd.args,
					permission = perm
				})
			end
		end
	end

	-- Create command cards
	for _, cmd in ipairs(availableCommands) do
		local cmdCard = Instance.new("Frame")
		cmdCard.Size = UDim2.new(1, 0, 0, 60)
		cmdCard.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
		cmdCard.BorderSizePixel = 0
		cmdCard.Parent = page

		local cmdCorner = Instance.new("UICorner")
		cmdCorner.CornerRadius = UDim.new(0, 8)
		cmdCorner.Parent = cmdCard

		-- Command Name
		local cmdName = Instance.new("TextLabel")
		cmdName.Size = UDim2.new(0, 200, 0, 25)
		cmdName.Position = UDim2.new(0, 10, 0, 5)
		cmdName.BackgroundTransparency = 1
		cmdName.Font = Enum.Font.GothamBold
		cmdName.Text = "/" .. cmd.name
		cmdName.TextColor3 = Color3.fromRGB(100, 180, 255)
		cmdName.TextSize = 14
		cmdName.TextXAlignment = Enum.TextXAlignment.Left
		cmdName.Parent = cmdCard

		-- Command Description
		local cmdDesc = Instance.new("TextLabel")
		cmdDesc.Size = UDim2.new(0, 300, 0, 20)
		cmdDesc.Position = UDim2.new(0, 10, 0, 30)
		cmdDesc.BackgroundTransparency = 1
		cmdDesc.Font = Enum.Font.Gotham
		cmdDesc.Text = cmd.desc .. (cmd.args ~= "" and (" • Args: " .. cmd.args) or "")
		cmdDesc.TextColor3 = Color3.fromRGB(150, 150, 150)
		cmdDesc.TextSize = 11
		cmdDesc.TextXAlignment = Enum.TextXAlignment.Left
		cmdDesc.Parent = cmdCard

		-- Play Button
		local playBtn = Instance.new("TextButton")
		playBtn.Name = "PlayButton"
		playBtn.Size = UDim2.new(0, 45, 0, 45)
		playBtn.Position = UDim2.new(1, -100, 0.5, -22.5)
		playBtn.BackgroundColor3 = Color3.fromRGB(20, 40, 80)
		playBtn.BorderSizePixel = 0
		playBtn.Font = Enum.Font.GothamBold
		playBtn.Text = "▶"
		playBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		playBtn.TextSize = 18
		playBtn.Parent = cmdCard

		local playCorner = Instance.new("UICorner")
		playCorner.CornerRadius = UDim.new(0, 8)
		playCorner.Parent = playBtn

		-- Stop Button
		local stopBtn = Instance.new("TextButton")
		stopBtn.Name = "StopButton"
		stopBtn.Size = UDim2.new(0, 45, 0, 45)
		stopBtn.Position = UDim2.new(1, -50, 0.5, -22.5)
		stopBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
		stopBtn.BorderSizePixel = 0
		stopBtn.Font = Enum.Font.GothamBold
		stopBtn.Text = "■"
		stopBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
		stopBtn.TextSize = 18
		stopBtn.Visible = false
		stopBtn.Parent = cmdCard

		local stopCorner = Instance.new("UICorner")
		stopCorner.CornerRadius = UDim.new(0, 8)
		stopCorner.Parent = stopBtn

		-- ✅ FIXED: Actually execute the command via chat
		playBtn.MouseButton1Click:Connect(function()
			local commandText = "/" .. cmd.name

			-- Visual feedback
			playBtn.BackgroundColor3 = Color3.fromRGB(100, 180, 255)
			task.wait(0.1)
			playBtn.BackgroundColor3 = Color3.fromRGB(20, 40, 80)

			if cmd.args == "" then
				-- ✅ FIXED: Send command via chat system
				local TextChatService = game:GetService("TextChatService")
				local TextChannels = TextChatService:FindFirstChild("TextChannels")

				if TextChannels then
					-- New chat system
					local generalChannel = TextChannels:FindFirstChild("RBXGeneral")
					if generalChannel then
						generalChannel:SendAsync(commandText)
						print("[AdminGUI] 🎮 Executed command:", commandText)
					else
						warn("[AdminGUI] ⚠️ RBXGeneral channel not found")
					end
				else
					-- Legacy chat fallback
					local ReplicatedStorage = game:GetService("ReplicatedStorage")
					local DefaultChatSystemChatEvents = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
					if DefaultChatSystemChatEvents then
						local SayMessageRequest = DefaultChatSystemChatEvents:FindFirstChild("SayMessageRequest")
						if SayMessageRequest then
							SayMessageRequest:FireServer(commandText, "All")
							print("[AdminGUI] 🎮 Executed command (legacy):", commandText)
						end
					else
						warn("[AdminGUI] ⚠️ Could not execute command - no chat system found")
					end
				end
			else
				-- Command needs arguments - show input
				local message = string.format("💡 Type in chat: %s %s", commandText, cmd.args)
				if RemoteEvents and RemoteEvents.SendRaceNotification then
					pcall(function()
						RemoteEvents.SendRaceNotification(player, {message = message})
					end)
				end
				print("[AdminGUI] ℹ️ Command needs args:", commandText, cmd.args)
			end
		end)
	end

	-- Auto-resize canvas
	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		page.CanvasSize = UDim2.new(0, 0, 0, layout.AbsoluteContentSize.Y + 10)
	end)

	return page
end

-- ✅ Initialize GUI
local function InitGUI()
	-- Check if player is admin
	if not SystemManager then
		warn("[AdminGUI] SystemManager not found!")
		return
	end

	-- Wait for cache
	local maxWait = 10
	local startTime = tick()
	while not SystemManager:IsCacheReady() and (tick() - startTime) < maxWait do
		wait(0.1)
	end

-- Get admin data (use client cache if available)
if clientAdminCache[player.UserId] then
	adminData = {
		permission = clientAdminCache[player.UserId].permission,
		level = clientAdminCache[player.UserId].level,
		isAdmin = clientAdminCache[player.UserId].permission ~= "MEMBER"
	}
else
	adminData = SystemManager:GetPlayerRoleInfo(player)
end

	if not adminData or not adminData.isAdmin then
		print("[AdminGUI] Not an admin, GUI disabled")
		return
	end

	print("[AdminGUI] Initializing for", player.Name, "-", adminData.permission)

	-- Create GUI
	local gui, mainFrame, toggleBtn, closeBtn, tabBar, pages = CreateAdminGUI()

	-- Create tabs
	local dashTab = CreateTabButton(tabBar, "Dashboard", 1)
	local cmdTab = CreateTabButton(tabBar, "Commands", 2)
	local serverTab = CreateTabButton(tabBar, "Server Data", 3)

	-- Create pages
	local dashPage = CreateDashboard(pages, adminData)
	local cmdPage = CreateCommandPage(pages, adminData)

	-- Tab switching
	local function SwitchTab(tabName)
		dashPage.Visible = (tabName == "Dashboard")
		cmdPage.Visible = (tabName == "Commands")

		dashTab.BackgroundColor3 = (tabName == "Dashboard") and Color3.fromRGB(20, 40, 80) or Color3.fromRGB(30, 30, 30)
		cmdTab.BackgroundColor3 = (tabName == "Commands") and Color3.fromRGB(20, 40, 80) or Color3.fromRGB(30, 30, 30)

		dashTab.TextColor3 = (tabName == "Dashboard") and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 150, 150)
		cmdTab.TextColor3 = (tabName == "Commands") and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 150, 150)
	end

	dashTab.MouseButton1Click:Connect(function() SwitchTab("Dashboard") end)
	cmdTab.MouseButton1Click:Connect(function() SwitchTab("Commands") end)

	-- Toggle functionality
	toggleBtn.MouseButton1Click:Connect(function()
		isOpen = true
		mainFrame.Visible = true
		toggleBtn.Visible = false
	end)

	closeBtn.MouseButton1Click:Connect(function()
		isOpen = false
		mainFrame.Visible = false
		toggleBtn.Visible = true
	end)

	-- Keyboard shortcut (Ctrl + `)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then return end
		if input.KeyCode == Enum.KeyCode.Backquote and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
			isOpen = not isOpen
			mainFrame.Visible = isOpen
			toggleBtn.Visible = not isOpen
		end
	end)

	gui.Parent = playerGui
	print("[AdminGUI] ✅ Initialized successfully")
end

-- Start
wait(2) -- Wait for replication
InitGUI()
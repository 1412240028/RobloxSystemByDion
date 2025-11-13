-- Checkpoint System V1.0 - Server Main Script (CORRECTED)
-- Main server-side controller for the checkpoint system

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Module imports
local Settings = require(game.ReplicatedStorage.CheckpointSystem.Config.Settings)
local CheckpointManager = require(game.ReplicatedStorage.CheckpointSystem.Modules.CheckpointManager)
local DataHandler = require(game.ReplicatedStorage.CheckpointSystem.Modules.DataHandler)
local SecurityValidator = require(game.ReplicatedStorage.CheckpointSystem.Modules.SecurityValidator)
local RespawnHandler = require(game.ServerScriptService.CheckpointSystem.RespawnHandler)
local AutoSaveService = require(game.ServerScriptService.CheckpointSystem.AutoSaveService)
local AdminManager = require(game.ReplicatedStorage.CheckpointSystem.Modules.AdminManager)
local HealthMonitor = require(game.ServerScriptService.CheckpointSystem.HealthMonitor)
local DisasterRecovery = require(game.ServerScriptService.CheckpointSystem.DisasterRecovery)

-- Remote events
local CheckpointReachedEvent = game.ReplicatedStorage.CheckpointSystem.Remotes.CheckpointReached
local AdminCommandEvent = game.ReplicatedStorage.CheckpointSystem.Remotes.AdminCommand
local SystemStatusEvent = game.ReplicatedStorage.CheckpointSystem.Remotes.SystemStatus
local GlobalDataEvent = game.ReplicatedStorage.CheckpointSystem.Remotes.GlobalData

-- Private variables
local playerSessions = {}
local autoSaveConnections = {}
local isSaving = {}
local isInitialized = false

-- Logger utility
local function Log(level, message, ...)
	if not Settings.DEBUG_MODE and level == "DEBUG" then return end

	local prefix = "[ServerMain]"
	if level == "ERROR" then
		warn(prefix .. " " .. string.format(message, ...))
	elseif level == "WARN" then
		warn(prefix .. " " .. string.format(message, ...))
	elseif level == "INFO" or (Settings.DEBUG_MODE and level == "DEBUG") then
		print(prefix .. " " .. string.format(message, ...))
	end
end

-- Get player checkpoint (needed by RespawnHandler)
local function GetPlayerCheckpoint(userId)
	local session = playerSessions[userId]
	return session and session.CurrentCheckpoint or 0
end

-- Update player death count (needed by RespawnHandler)
local function UpdatePlayerDeathCount(userId)
	local session = playerSessions[userId]
	if session then
		session.DeathCount = session.DeathCount + 1
		
		-- Track respawn metric
		HealthMonitor:IncrementMetric("respawns")
		
		Log("DEBUG", "Death count updated for %d: %d", userId, session.DeathCount)
		return session.DeathCount
	end
	return 0
end

-- Spawn player at specific checkpoint
local function SpawnPlayerAtCheckpoint(player, checkpointOrder)
	-- Wait for character to load
	local character = player.Character or player.CharacterAdded:Wait()

	-- Wait for HumanoidRootPart
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoidRootPart then
		Log("ERROR", "HumanoidRootPart not found for %s", player.Name)
		return false
	end

	-- Get spawn position from CheckpointManager
	local spawnPosition = CheckpointManager.GetSpawnPosition(checkpointOrder)
	if not spawnPosition then
		Log("WARN", "No spawn position for checkpoint %d, using default", checkpointOrder)
		return false
	end

	-- Teleport player
	task.wait(0.5)
	humanoidRootPart.CFrame = CFrame.new(spawnPosition)

	Log("INFO", "Spawned %s at checkpoint %d", player.Name, checkpointOrder)
	return true
end

-- Initialize the server system
local function Initialize()
	if isInitialized then
		Log("WARN", "Server system already initialized")
		return true
	end

	Log("INFO", "Initializing Checkpoint System Server...")

	-- Initialize modules
	local modulesInitialized = true

	if not CheckpointManager.Initialize() then
		Log("ERROR", "Failed to initialize CheckpointManager")
		modulesInitialized = false
	end

	if not DataHandler.Initialize() then
		Log("ERROR", "Failed to initialize DataHandler")
		modulesInitialized = false
	end

	if not SecurityValidator.Initialize() then
		Log("ERROR", "Failed to initialize SecurityValidator")
		modulesInitialized = false
	end

	if not RespawnHandler.Initialize() then
		Log("ERROR", "Failed to initialize RespawnHandler")
		modulesInitialized = false
	end

	-- CRITICAL: Link RespawnHandler to ServerMain functions
	RespawnHandler.ServerMainModule = {
		UpdatePlayerDeathCount = UpdatePlayerDeathCount,
		GetPlayerCheckpoint = GetPlayerCheckpoint
	}
	Log("INFO", "RespawnHandler linked to ServerMain functions")

	if not AutoSaveService.Initialize() then
		Log("ERROR", "Failed to initialize AutoSaveService")
		modulesInitialized = false
	end

	-- Initialize Admin Manager
	AdminManager:Init()

	-- Initialize Health Monitoring
	HealthMonitor:Init()

	-- Initialize Disaster Recovery
	DisasterRecovery:CheckAndRecover()

	if not modulesInitialized then
		Log("ERROR", "Failed to initialize one or more modules")
		return false
	end

	-- Set up player connections
	Players.PlayerAdded:Connect(OnPlayerAdded)
	Players.PlayerRemoving:Connect(OnPlayerRemoving)

	-- Set up remote event handlers
	CheckpointReachedEvent.OnServerEvent:Connect(OnCheckpointReached)
	AdminCommandEvent.OnServerEvent:Connect(OnAdminCommand)
	SystemStatusEvent.OnServerEvent:Connect(OnSystemStatusRequest)
	GlobalDataEvent.OnServerEvent:Connect(OnGlobalDataRequest)

	-- Start background services
	StartBackgroundServices()

	-- Periodic snapshots (every 30 minutes)
	task.spawn(function()
		while true do
			task.wait(1800)
			DisasterRecovery:CreateSnapshot()
		end
	end)

	-- Mark healthy every 5 minutes
	task.spawn(function()
		while true do
			task.wait(300)
			DisasterRecovery:MarkHealthy()
		end
	end)

	isInitialized = true
	Log("INFO", "Checkpoint System Server initialized successfully")
	return true
end

-- Handle player joining
function OnPlayerAdded(player)
	if not isInitialized then
		Log("ERROR", "System not initialized, cannot handle player join")
		return
	end

	local userId = player.UserId
	Log("INFO", "Player %s (%d) joined", player.Name, userId)

	-- Load player data
	local playerData = DataHandler.LoadCheckpoint(userId)

	-- Create session
	local session = {
		Player = player,
		UserId = userId,
		CurrentCheckpoint = playerData.checkpoint or 0,
		DeathCount = playerData.deathCount or 0,
		SessionStartTime = playerData.sessionStartTime or os.time(),
		LastSaveTime = 0,
		JoinTime = tick()
	}

	playerSessions[userId] = session

	-- Update security validator
	SecurityValidator.SetCurrentCheckpoint(userId, session.CurrentCheckpoint)

	-- Set up auto-save
	SetupAutoSave(userId)

	-- Spawn player at their last checkpoint
	if session.CurrentCheckpoint > 0 then
		SpawnPlayerAtCheckpoint(player, session.CurrentCheckpoint)
	end

	Log("DEBUG", "Player session created for %s: checkpoint=%d", player.Name, session.CurrentCheckpoint)
end

-- Handle player leaving
local function OnPlayerLeaving(player)
	if not isInitialized then return end

	local userId = player.UserId
	Log("INFO", "Player %s (%d) leaving", player.Name, userId)

	-- Force save on leave
	ForceSavePlayerData(userId)

	-- Cleanup session
	CleanupPlayerSession(userId)
end

-- Handle player removal (alias for leaving)
OnPlayerRemoving = OnPlayerLeaving

-- Handle checkpoint reached event from client
function OnCheckpointReached(player, checkpointOrder, checkpointPart)
	if not isInitialized then
		Log("ERROR", "System not initialized")
		return
	end

	local userId = player.UserId
	Log("DEBUG", "Checkpoint reached event from %s: order=%d", player.Name, checkpointOrder)

	-- Get or create session if first checkpoint touch
	if not playerSessions[userId] then
		Log("INFO", "First checkpoint touch - creating session for %s", player.Name)
		OnPlayerAdded(player)
	end

	-- Validate the touch
	local valid, reason = SecurityValidator.ValidateCheckpointTouch(player, checkpointPart, checkpointOrder)

	if not valid then
		Log("WARN", "Invalid checkpoint touch from %s: %s", player.Name, reason)
		return
	end

	-- Update session
	local session = playerSessions[userId]
	if session then
		session.CurrentCheckpoint = checkpointOrder
		session.LastSaveTime = tick()
	end

	-- Save data (async)
	SavePlayerDataAsync(userId)

	-- Track metric
	HealthMonitor:IncrementMetric("checkpointTouches")

	-- Fire event to all clients for effects/UI
	CheckpointReachedEvent:FireAllClients(player, checkpointOrder, checkpointPart)

	Log("INFO", "Checkpoint %d reached by %s", checkpointOrder, player.Name)
end

-- Save player data asynchronously
function SavePlayerDataAsync(userId)
	-- Check if already saving
	if isSaving[userId] then
		Log("DEBUG", "Save already in progress for %d, skipping", userId)
		return false
	end

	if not SecurityValidator.CanSave(userId) then
		Log("WARN", "Cannot save data for %d (lock held)", userId)
		return false
	end

	-- Acquire save lock
	if not SecurityValidator.AcquireSaveLock(userId) then
		Log("ERROR", "Failed to acquire save lock for %d", userId)
		return false
	end

	-- Get session data
	local session = playerSessions[userId]
	if not session then
		SecurityValidator.ReleaseSaveLock(userId)
		Log("ERROR", "No session found for %d", userId)
		return false
	end

	-- Set saving flag
	isSaving[userId] = true

	-- Prepare data
	local data = {
		checkpoint = session.CurrentCheckpoint,
		deathCount = session.DeathCount,
		sessionStartTime = session.SessionStartTime,
		timestamp = os.time()
	}

	-- Save asynchronously
	task.spawn(function()
		local success = DataHandler.SaveCheckpoint(userId, data)

		-- Track metrics
		if success then
			HealthMonitor:IncrementMetric("saves")
		else
			HealthMonitor:IncrementMetric("saveFails")
		end

		-- Release lock
		SecurityValidator.ReleaseSaveLock(userId)

		-- Clear saving flag
		isSaving[userId] = nil

		-- Update last save time on success
		if success then
			if session then
				session.LastSaveTime = tick()
			end
			Log("DEBUG", "Data saved successfully for %d", userId)
		else
			Log("ERROR", "Failed to save data for %d", userId)
		end
	end)

	return true
end

-- Force save (blocking, for player leaving)
function ForceSavePlayerData(userId)
	local session = playerSessions[userId]
	if not session then
		Log("WARN", "No session to save for %d", userId)
		return false
	end

	local data = {
		checkpoint = session.CurrentCheckpoint,
		deathCount = session.DeathCount,
		sessionStartTime = session.SessionStartTime,
		timestamp = os.time()
	}

	local success = DataHandler.SaveCheckpoint(userId, data)
	if success then
		Log("INFO", "Force saved data for %d", userId)
	else
		Log("ERROR", "Failed to force save data for %d", userId)
	end

	return success
end

-- Set up auto-save for player
function SetupAutoSave(userId)
	-- Clear existing connection
	if autoSaveConnections[userId] then
		autoSaveConnections[userId]:Disconnect()
	end

	-- Set up new auto-save
	autoSaveConnections[userId] = RunService.Heartbeat:Connect(function()
		local session = playerSessions[userId]
		if not session then return end

		local timeSinceLastSave = tick() - session.LastSaveTime
		if timeSinceLastSave >= Settings.AUTO_SAVE_INTERVAL_SECONDS then
			SavePlayerDataAsync(userId)
		end
	end)

	Log("DEBUG", "Auto-save set up for %d", userId)
end

-- Spawn player at specific checkpoint
local function SpawnPlayerAtCheckpoint(player, checkpointOrder)
	-- Wait for character to load
	local character = player.Character or player.CharacterAdded:Wait()

	-- Wait for HumanoidRootPart
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoidRootPart then
		Log("ERROR", "HumanoidRootPart not found for %s", player.Name)
		return false
	end

	-- Get spawn position from CheckpointManager
	local spawnPosition = CheckpointManager.GetSpawnPosition(checkpointOrder)
	if not spawnPosition then
		Log("WARN", "No spawn position for checkpoint %d, using default", checkpointOrder)
		return false
	end

	-- Teleport player
	task.wait(0.5)
	humanoidRootPart.CFrame = CFrame.new(spawnPosition)

	Log("INFO", "Spawned %s at checkpoint %d", player.Name, checkpointOrder)
	return true
end

-- Start background services
function StartBackgroundServices()
	-- Process save queue periodically
	RunService.Heartbeat:Connect(function()
		DataHandler.ProcessSaveQueue()
	end)

	Log("DEBUG", "Background services started")
end

-- Get player session
local function GetPlayerSession(userId)
	return playerSessions[userId]
end

-- Cleanup player session
function CleanupPlayerSession(userId)
	playerSessions[userId] = nil
	isSaving[userId] = nil

	if autoSaveConnections[userId] then
		autoSaveConnections[userId]:Disconnect()
		autoSaveConnections[userId] = nil
	end

	Log("DEBUG", "Session cleaned up for %d", userId)
end

-- Get system status
local function GetSystemStatus()
	local status = {
		Initialized = isInitialized,
		ActivePlayers = 0,
		TotalCheckpoints = CheckpointManager.GetCheckpointCount(),
		DataQueueSize = DataHandler.GetQueueStatus().Size
	}

	for _ in pairs(playerSessions) do
		status.ActivePlayers = status.ActivePlayers + 1
	end

	return status
end

-- Debug function
local function DebugSystem()
	if not Settings.DEBUG_MODE then return end

	Log("INFO", "=== System Debug ===")
	Log("INFO", "Status: %s", isInitialized and "Initialized" or "Not Initialized")

	local status = GetSystemStatus()
	Log("INFO", "Active Players: %d", status.ActivePlayers)
	Log("INFO", "Total Checkpoints: %d", status.TotalCheckpoints)
	Log("INFO", "Data Queue Size: %d", status.DataQueueSize)

	CheckpointManager.DebugPrintCheckpoints()

	Log("INFO", "=== End Debug ===")
end

-- Cleanup function
local function Cleanup()
	-- Force save all players
	for userId, _ in pairs(playerSessions) do
		ForceSavePlayerData(userId)
	end

	-- Cleanup sessions
	for userId, _ in pairs(playerSessions) do
		CleanupPlayerSession(userId)
	end

	-- Cleanup modules
	CheckpointManager.Cleanup()
	DataHandler.Cleanup()
	SecurityValidator.Cleanup()
	RespawnHandler.Cleanup()
	AutoSaveService.Cleanup()

	isInitialized = false
	Log("INFO", "Server system cleaned up")
end

-- Handle admin command from client
function OnAdminCommand(player, command, args)
	if not isInitialized or not Settings.ENABLE_ADMIN_SYSTEM then
		return
	end

	Log("DEBUG", "Admin command from %s: %s", player.Name, command)

	-- Execute command through AdminManager
	local success, result = AdminManager:ExecuteCommand(player, command, args)

	-- Send result back to player
	AdminCommandEvent:FireClient(player, success, result)
end

-- Handle system status request
function OnSystemStatusRequest(player)
	if not isInitialized then
		SystemStatusEvent:FireClient(player, false, "System not initialized")
		return
	end

	-- Check if player is admin
	if not AdminManager:IsAdmin(player) then
		SystemStatusEvent:FireClient(player, false, "Admin access required")
		return
	end

	local status = AdminManager:GetSystemStatus()
	SystemStatusEvent:FireClient(player, true, status)
end

-- Handle global data request
function OnGlobalDataRequest(player, requestType, targetUser)
	if not isInitialized or not Settings.ENABLE_ADMIN_SYSTEM then
		GlobalDataEvent:FireClient(player, false, "System not available")
		return
	end

	-- Check if player is admin
	if not AdminManager:IsAdmin(player) then
		GlobalDataEvent:FireClient(player, false, "Admin access required")
		return
	end

	if requestType == "PLAYER_DATA" then
		local result = AdminManager:GetPlayerData(targetUser)
		GlobalDataEvent:FireClient(player, true, result)
	elseif requestType == "GLOBAL_STATUS" then
		local result = AdminManager:GetGlobalStatus()
		GlobalDataEvent:FireClient(player, true, result)
	else
		GlobalDataEvent:FireClient(player, false, "Unknown request type")
	end
end

-- Export functions to global for external access
_G.CheckpointServerMain = {
	GetPlayerCheckpoint = GetPlayerCheckpoint,
	UpdatePlayerDeathCount = UpdatePlayerDeathCount,
	GetPlayerSession = GetPlayerSession,
	ForceSavePlayerData = ForceSavePlayerData,
	GetSystemStatus = GetSystemStatus,
	DebugSystem = DebugSystem,
	Cleanup = Cleanup
}

Log("INFO", "Module functions exported to _G.CheckpointServerMain")

-- ========================================
-- CRITICAL: Game closing handler
-- ========================================
game:BindToClose(function()
	print("[ServerMain] 🛑 Server closing, running graceful shutdown...")
	
	local result = DisasterRecovery:GracefulShutdown()
	
	print(string.format("[ServerMain] Shutdown complete: %d saved, %d failed", 
		result.saved, result.failed))
	
	-- Give extra time for final saves
	task.wait(5)
end)

-- ========================================
-- Initialize on script run
-- ========================================
if Initialize() then
	Log("INFO", "✅ Checkpoint System Server started successfully")
else
	Log("ERROR", "❌ Failed to start Checkpoint System Server")
end
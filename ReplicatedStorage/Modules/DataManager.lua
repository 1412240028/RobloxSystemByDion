-- DataManager.lua (FIXED VERSION)
-- Unified data management for checkpoint and sprint systems
-- ✅ FIXED: Added DirectSavePlayerData function to prevent line 318 error
-- ✅ FIXED: Improved queue processor reliability

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.Config)

local DataManager = {}

-- Private variables
local dataStore = DataStoreService:GetDataStore(Config.DATASTORE_NAME)
local adminDataStore = DataStoreService:GetDataStore(Config.ADMIN_GLOBAL_DATASTORE)
local playerDataCache = {} -- player -> data
local adminDataCache = {} -- admin data cache: {userId = {permission, level, addedBy, addedAt, lastActive}}
local saveQueue = {} -- Queue for save operations to prevent race conditions
local isSaving = {} -- player -> boolean to prevent concurrent saves
local queueProcessorActive = {} -- player -> boolean to track if queue processor is running
local queueMetrics = {} -- player -> {size = number, processed = number, errors = number}
local dirtyPlayers = {} -- player -> boolean (true if data has changed and needs saving)
local adminDataDirty = false -- true if admin data has changed and needs saving

-- Create new unified player data structure
function DataManager.CreatePlayerData(player)
	local data = {
		userId = player.UserId,
		-- Sprint data
		isSprinting = false,
		lastToggleTime = 0,
		toggleCount = 0,
		character = nil,
		humanoid = nil,
		lastSpeedCheck = 0,
		speedViolations = 0,
		-- Checkpoint data
		currentCheckpoint = 0,
		checkpointHistory = {},
		touchedCheckpoints = {},
		spawnPosition = Vector3.new(0, 0, 0),
		lastTouchTime = 0,
		deathCount = 0,
		sessionStartTime = tick(),
		-- Race data
		raceTimes = {}, -- List of completed race times
		bestTime = nil, -- Best race completion time
		isRacing = false, -- Currently in a race
		raceStartTime = 0, -- When current race started
		raceCheckpoints = 0, -- Checkpoints collected in current race
		totalRaces = 0, -- Total races participated in
		racesWon = 0, -- Number of races won
		finishCount = 0 -- Number of times reached finish
	}

	playerDataCache[player] = data
	return data
end

-- Get player data safely
function DataManager.GetPlayerData(player)
	return playerDataCache[player]
end

-- Update sprint state
function DataManager.UpdateSprintState(player, isSprinting)
	local data = playerDataCache[player]
	if not data then return end

	data.isSprinting = isSprinting
	data.lastToggleTime = tick()
	data.toggleCount = data.toggleCount + 1

	-- Mark as dirty for auto-save
	dirtyPlayers[player] = true
end

-- Update checkpoint data
function DataManager.UpdateCheckpointData(player, checkpointId, spawnPosition)
	local data = playerDataCache[player]
	if not data then return end

	data.currentCheckpoint = checkpointId
	data.spawnPosition = spawnPosition or data.spawnPosition
	data.lastTouchTime = tick()

	-- Add to checkpoint history if not already present
	if not table.find(data.checkpointHistory, checkpointId) then
		table.insert(data.checkpointHistory, checkpointId)
		table.sort(data.checkpointHistory)
	end

	-- Mark checkpoint as touched
	data.touchedCheckpoints[checkpointId] = true

	-- Mark as dirty for auto-save
	dirtyPlayers[player] = true
end

-- ✅ NEW: Reset checkpoint data (for reset button)
function DataManager.ResetCheckpointData(player)
	local data = playerDataCache[player]
	if not data then return end

	data.currentCheckpoint = 0
	data.checkpointHistory = {}
	data.touchedCheckpoints = {}
	data.spawnPosition = Vector3.new(0, 0, 0)

	-- Mark as dirty for auto-save
	dirtyPlayers[player] = true
end

-- Update death count
function DataManager.UpdateDeathCount(player)
	local data = playerDataCache[player]
	if not data then return end

	data.deathCount = data.deathCount + 1

	-- Mark as dirty for auto-save
	dirtyPlayers[player] = true
end

-- Update finish count
function DataManager.UpdateFinishCount(player)
	local data = playerDataCache[player]
	if not data then return end

	data.finishCount = (data.finishCount or 0) + 1

	-- Mark as dirty for auto-save
	dirtyPlayers[player] = true
end

-- Update race data
function DataManager.UpdateRaceData(player, raceTime, checkpointsCollected)
	local data = playerDataCache[player]
	if not data then return end

	-- Record race completion
	table.insert(data.raceTimes, raceTime)
	data.totalRaces = data.totalRaces + 1
	data.raceCheckpoints = checkpointsCollected

	-- Update best time
	if not data.bestTime or raceTime < data.bestTime then
		data.bestTime = raceTime
	end

	-- Reset race state
	data.isRacing = false
	data.raceStartTime = 0

	-- Mark as dirty for auto-save
	dirtyPlayers[player] = true
end

-- Start race for player
function DataManager.StartRaceForPlayer(player)
	local data = playerDataCache[player]
	if not data then return end

	data.isRacing = true
	data.raceStartTime = tick()
	data.raceCheckpoints = 0

	-- Mark as dirty for auto-save
	dirtyPlayers[player] = true
end

-- End race for player
function DataManager.EndRaceForPlayer(player, completed)
	local data = playerDataCache[player]
	if not data or not data.isRacing then return end

	if completed then
		local raceTime = tick() - data.raceStartTime
		DataManager.UpdateRaceData(player, raceTime, data.raceCheckpoints)
	else
		-- Race failed/didn't complete
		data.isRacing = false
		data.raceStartTime = 0
		data.raceCheckpoints = 0

		-- Mark as dirty for auto-save
		dirtyPlayers[player] = true
	end
end

-- Get race leaderboard
function DataManager.GetRaceLeaderboard()
	local leaderboard = {}

	for player, data in pairs(playerDataCache) do
		if data.bestTime then
			table.insert(leaderboard, {
				playerName = player.Name,
				userId = data.userId,
				bestTime = data.bestTime,
				totalRaces = data.totalRaces,
				racesWon = data.racesWon
			})
		end
	end

	-- Sort by best time (ascending)
	table.sort(leaderboard, function(a, b)
		return a.bestTime < b.bestTime
	end)

	-- Limit to leaderboard size
	local Config = require(game.ReplicatedStorage.Config.Config)
	while #leaderboard > Config.LEADERBOARD_SIZE do
		table.remove(leaderboard)
	end

	return leaderboard
end

-- Save player data to DataStore (with queue system to prevent race conditions)
function DataManager.SavePlayerData(player)
	local data = playerDataCache[player]
	if not data then return end

	-- Initialize queue metrics if not exists
	if not queueMetrics[player] then
		queueMetrics[player] = {size = 0, processed = 0, errors = 0}
	end

	-- Prevent concurrent saves for the same player
	if isSaving[player] then
		-- Queue the save operation
		if not saveQueue[player] then
			saveQueue[player] = {}
		end
		table.insert(saveQueue[player], true) -- Just a marker
		queueMetrics[player].size = #saveQueue[player]
		return
	end

	isSaving[player] = true

	-- Clear dirty flag on save attempt
	dirtyPlayers[player] = false

	local key = Config.DATASTORE_KEY_PREFIX .. tostring(data.userId)
	local saveData = {
		-- Sprint data
		isSprinting = data.isSprinting,
		toggleCount = data.toggleCount,
		speedViolations = data.speedViolations,
		-- Checkpoint data
		currentCheckpoint = data.currentCheckpoint,
		checkpointHistory = data.checkpointHistory,
		touchedCheckpoints = data.touchedCheckpoints or {},
		spawnPosition = {data.spawnPosition.X, data.spawnPosition.Y, data.spawnPosition.Z},
		deathCount = data.deathCount,
		-- Race data
		raceTimes = data.raceTimes,
		bestTime = data.bestTime,
		totalRaces = data.totalRaces,
		racesWon = data.racesWon,
		finishCount = data.finishCount,
		lastPlayedVersion = Config.VERSION
	}

	-- Retry logic with exponential backoff
	for attempt = 1, Config.SAVE_RETRY_ATTEMPTS do
		local success, errorMessage = pcall(function()
			dataStore:SetAsync(key, saveData)
		end)

		if success then
			print(string.format("[DataManager] Saved data for %s", player.Name))
			isSaving[player] = false

			-- Process queued saves using proper queue processor
			DataManager.ProcessSaveQueue(player)

			return true
		else
			warn(string.format("[DataManager] Save attempt %d failed for %s: %s",
				attempt, player.Name, errorMessage))
			queueMetrics[player].errors = queueMetrics[player].errors + 1

			-- Restore dirty flag on failure
			dirtyPlayers[player] = true

			if attempt < Config.SAVE_RETRY_ATTEMPTS then
				task.wait(Config.SAVE_RETRY_BACKOFF[attempt] or 2)
			end
		end
	end

	warn(string.format("[DataManager] Failed to save data for %s after %d attempts",
		player.Name, Config.SAVE_RETRY_ATTEMPTS))
	isSaving[player] = false
	return false
end

-- ✅ FIXED: Direct save without queue logic (for queue processor)
function DataManager.DirectSavePlayerData(player)
	local data = playerDataCache[player]
	if not data then 
		warn("[DataManager] DirectSave failed: player data not found")
		return false 
	end

	-- Check if player still exists
	if not player or not player.Parent then
		warn("[DataManager] DirectSave failed: player no longer exists")
		return false
	end

	local key = Config.DATASTORE_KEY_PREFIX .. tostring(data.userId)
	local saveData = {
		-- Sprint data
		isSprinting = data.isSprinting,
		toggleCount = data.toggleCount,
		speedViolations = data.speedViolations,
		-- Checkpoint data
		currentCheckpoint = data.currentCheckpoint,
		checkpointHistory = data.checkpointHistory,
		touchedCheckpoints = data.touchedCheckpoints or {},
		spawnPosition = {data.spawnPosition.X, data.spawnPosition.Y, data.spawnPosition.Z},
		deathCount = data.deathCount,
		-- Race data
		raceTimes = data.raceTimes,
		bestTime = data.bestTime,
		totalRaces = data.totalRaces,
		racesWon = data.racesWon,
		finishCount = data.finishCount,
		lastPlayedVersion = Config.VERSION
	}

	-- Single save attempt (no retry for queue processor)
	local success, errorMessage = pcall(function()
		dataStore:SetAsync(key, saveData)
	end)

	if success then
		print(string.format("[DataManager] Direct saved data for %s", player.Name))
		return true
	else
		warn(string.format("[DataManager] Direct save failed for %s: %s", player.Name, errorMessage))
		return false
	end
end

-- ✅ FIXED: Process save queue for a player (background queue processor)
function DataManager.ProcessSaveQueue(player)
	-- Prevent multiple processors for same player
	if queueProcessorActive[player] then
		return
	end

	if not saveQueue[player] or #saveQueue[player] == 0 then
		return
	end

	queueProcessorActive[player] = true

	-- Process queue in background
	task.spawn(function()
		local processedCount = 0
		local startTime = tick()

		while saveQueue[player] and #saveQueue[player] > 0 do
			-- Safety timeout: don't process for more than 30 seconds
			if tick() - startTime > 30 then
				warn(string.format("[DataManager] Queue processor timeout (30s) for %s", player.Name or "Unknown"))
				break
			end

			-- Check if player data still exists (player might have left)
			if not playerDataCache[player] then
				print(string.format("[DataManager] Queue processor stopped - player data cleaned up for %s", player.Name or "Unknown"))
				break
			end

			-- Check if player still exists
			if not player or not player.Parent then
				print(string.format("[DataManager] Queue processor stopped - player left"))
				break
			end

			-- Check if currently saving
			if isSaving[player] then
				warn("[DataManager] Queue processor paused - concurrent save detected")
				task.wait(0.5)
				continue
			end

			-- Remove one item from queue
			table.remove(saveQueue[player], 1)
			queueMetrics[player].size = #saveQueue[player]
			queueMetrics[player].processed = queueMetrics[player].processed + 1
			processedCount = processedCount + 1

			-- Small delay to prevent overwhelming DataStore
			task.wait(0.1)

			-- Try to save again (direct save, no queue)
			local success = DataManager.DirectSavePlayerData(player)
			if not success then
				warn(string.format("[DataManager] Queue processor failed to save for %s", player.Name or "Unknown"))
				break -- Stop processing if save fails
			end

			-- Safety limit: don't process more than 10 items at once
			if processedCount >= 10 then
				warn(string.format("[DataManager] Queue processor item limit reached for %s", player.Name or "Unknown"))
				break
			end
		end

		queueProcessorActive[player] = false
		print(string.format("[DataManager] Queue processor finished for %s (processed: %d)", player.Name or "Unknown", processedCount))
	end)
end

-- Get queue metrics for debugging
function DataManager.GetQueueMetrics(player)
	return queueMetrics[player] or {size = 0, processed = 0, errors = 0}
end

-- Load player data from DataStore
function DataManager.LoadPlayerData(player)
	local data = playerDataCache[player]
	if not data then return end

	local key = Config.DATASTORE_KEY_PREFIX .. tostring(data.userId)

	local success, loadedData = pcall(function()
		return dataStore:GetAsync(key)
	end)

	if success and loadedData then
		-- Apply loaded data
		data.isSprinting = loadedData.isSprinting or false
		data.toggleCount = loadedData.toggleCount or 0
		data.speedViolations = loadedData.speedViolations or 0
		data.currentCheckpoint = loadedData.currentCheckpoint or 0
		data.checkpointHistory = loadedData.checkpointHistory or {}
		data.touchedCheckpoints = loadedData.touchedCheckpoints or {}
		data.deathCount = loadedData.deathCount or 0
		if loadedData.spawnPosition then
			data.spawnPosition = Vector3.new(unpack(loadedData.spawnPosition))
		end
		-- Race data
		data.raceTimes = loadedData.raceTimes or {}
		data.bestTime = loadedData.bestTime
		data.totalRaces = loadedData.totalRaces or 0
		data.racesWon = loadedData.racesWon or 0
		data.finishCount = loadedData.finishCount or 0

		print(string.format("[DataManager] Loaded data for %s (sprint: %s, checkpoint: %d, history: %d, deaths: %d)",
			player.Name, tostring(data.isSprinting), data.currentCheckpoint, #data.checkpointHistory, data.deathCount))
	else
		-- Use defaults
		warn(string.format("[DataManager] Load failed for %s, using defaults", player.Name))
		data.isSprinting = false
		data.toggleCount = 0
		data.speedViolations = 0
		data.currentCheckpoint = 0
		data.checkpointHistory = {}
		data.deathCount = 0
		data.spawnPosition = Vector3.new(0, 0, 0)
	end
end

-- Cleanup player data
function DataManager.CleanupPlayerData(player)
	playerDataCache[player] = nil
	dirtyPlayers[player] = nil
	saveQueue[player] = nil
	isSaving[player] = nil
	queueProcessorActive[player] = nil
	queueMetrics[player] = nil
end

-- Get all active player data (for debugging)
function DataManager.GetAllPlayerData()
	return playerDataCache
end

-- Force save all data (emergency)
function DataManager.SaveAllData()
	for player in pairs(playerDataCache) do
		DataManager.SavePlayerData(player)
	end
end

-- Clear save queue for a player (used when player is leaving)
function DataManager.ClearSaveQueue(player)
	if saveQueue[player] then
		saveQueue[player] = nil
	end
	if queueProcessorActive[player] then
		queueProcessorActive[player] = false
	end
end

-- Mark player data as dirty (needs saving)
function DataManager.MarkDirty(player)
	dirtyPlayers[player] = true
end

-- Check if player data is dirty
function DataManager.IsDirty(player)
	return dirtyPlayers[player] == true
end

-- Set checkpoint for player (admin command)
function DataManager.SetCheckpoint(player, checkpointId)
	local data = playerDataCache[player]
	if not data then return false end

	data.currentCheckpoint = checkpointId

	-- Update spawn position based on checkpoint
	local Checkpoints = workspace:WaitForChild("Checkpoints")
	local checkpoint = Checkpoints:FindFirstChild("Checkpoint" .. checkpointId)
	if checkpoint then
		local spawnPosition = checkpoint.Position + Config.CHECKPOINT_SPAWN_OFFSET
		data.spawnPosition = spawnPosition
	end

	-- Mark as dirty for auto-save
	dirtyPlayers[player] = true

	print(string.format("[DataManager] Admin set checkpoint %d for %s", checkpointId, player.Name))
	return true
end

-- Force complete checkpoint (admin command)
function DataManager.ForceCompleteCheckpoint(player, checkpointId)
	local data = playerDataCache[player]
	if not data then return false end

	-- Mark checkpoint as touched
	data.touchedCheckpoints[checkpointId] = true

	-- Update current checkpoint if higher
	if checkpointId > data.currentCheckpoint then
		data.currentCheckpoint = checkpointId

		-- Update spawn position
		local Checkpoints = workspace:WaitForChild("Checkpoints")
		local checkpoint = Checkpoints:FindFirstChild("Checkpoint" .. checkpointId)
		if checkpoint then
			local spawnPosition = checkpoint.Position + Config.CHECKPOINT_SPAWN_OFFSET
			data.spawnPosition = spawnPosition
		end
	end

	-- Add to history if not present
	if not table.find(data.checkpointHistory, checkpointId) then
		table.insert(data.checkpointHistory, checkpointId)
		table.sort(data.checkpointHistory)
	end

	-- Mark as dirty for auto-save
	dirtyPlayers[player] = true

	print(string.format("[DataManager] Admin force completed checkpoint %d for %s", checkpointId, player.Name))
	return true
end

-- Admin Data Management Functions

-- Load admin data from DataStore
function DataManager.LoadAdminData()
	local success, loadedData = pcall(function()
		return adminDataStore:GetAsync("AdminData")
	end)

	if success and loadedData then
		adminDataCache = loadedData
		print(string.format("[DataManager] Loaded admin data for %d admins", #adminDataCache))
	else
		-- Use default admin data from config if no saved data
		adminDataCache = {}
		for userId, permission in pairs(Config.ADMIN_UIDS or {}) do
			adminDataCache[userId] = {
				permission = permission,
				level = Config.ADMIN_PERMISSION_LEVELS[permission] or 1,
				addedBy = "SYSTEM",
				addedAt = tick(),
				lastActive = tick()
			}
		end
		warn("[DataManager] Admin data load failed, using defaults")
	end
end

-- Save admin data to DataStore
function DataManager.SaveAdminData()
	if not adminDataDirty then return true end

	local success, errorMessage = pcall(function()
		adminDataStore:SetAsync("AdminData", adminDataCache)
	end)

	if success then
		adminDataDirty = false
		print("[DataManager] Admin data saved successfully")
		return true
	else
		warn(string.format("[DataManager] Admin data save failed: %s", errorMessage))
		return false
	end
end

-- Get admin data for a user
function DataManager.GetAdminData(userId)
	return adminDataCache[userId]
end

-- Add admin to cache
function DataManager.AddAdmin(userId, permission, addedBy)
	if adminDataCache[userId] then return false, "User is already an admin" end

	adminDataCache[userId] = {
		permission = permission,
		level = Config.ADMIN_PERMISSION_LEVELS[permission] or 1,
		addedBy = addedBy and addedBy.Name or "SYSTEM",
		addedAt = tick(),
		lastActive = tick()
	}

	adminDataDirty = true
	print(string.format("[DataManager] Admin added: %d (%s) by %s", userId, permission, addedBy and addedBy.Name or "SYSTEM"))
	return true
end

-- Remove admin from cache
function DataManager.RemoveAdmin(userId)
	if not adminDataCache[userId] then return false, "User is not an admin" end

	adminDataCache[userId] = nil
	adminDataDirty = true
	print(string.format("[DataManager] Admin removed: %d", userId))
	return true
end

-- Update admin last active time
function DataManager.UpdateAdminActivity(userId)
	if adminDataCache[userId] then
		adminDataCache[userId].lastActive = tick()
		adminDataDirty = true
	end
end

-- Get all admin data
function DataManager.GetAllAdminData()
	return adminDataCache
end

-- Force save admin data (emergency)
function DataManager.SaveAllAdminData()
	return DataManager.SaveAdminData()
end

-- Auto-save loop (call this from MainServer.Init)
function DataManager.StartAutoSave()
	task.spawn(function()
		while true do
			task.wait(Config.AUTO_SAVE_INTERVAL or 30) -- Default 30 seconds

			-- Save all dirty players
			for player, isDirty in pairs(dirtyPlayers) do
				if isDirty and playerDataCache[player] then
					DataManager.SavePlayerData(player)
				end
			end

			-- Save admin data if dirty
			if adminDataDirty then
				DataManager.SaveAdminData()
			end
		end
	end)
	print("[DataManager] Auto-save system started")
end

return DataManager

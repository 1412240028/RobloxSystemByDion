-- ServerScriptService/CheckpointSystem/DisasterRecovery.lua
-- Disaster Recovery & Emergency Procedures

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Settings = require(game.ReplicatedStorage.CheckpointSystem.Config.Settings)

local DisasterRecovery = {}

-- Logger
local function Log(level, message, ...)
	local prefix = "[DisasterRecovery]"
	if level == "ERROR" or level == "WARN" then
		warn(prefix .. " " .. string.format(message, ...))
	else
		print(prefix .. " " .. string.format(message, ...))
	end
end

-- Emergency save all players
function DisasterRecovery:EmergencySaveAll()
	Log("WARN", "🚨 EMERGENCY SAVE INITIATED 🚨")
	
	local saved = 0
	local failed = 0
	local startTime = tick()
	
	for _, player in ipairs(Players:GetPlayers()) do
		local success = pcall(function()
			-- Use global ServerMain function
			if _G.CheckpointServerMain and _G.CheckpointServerMain.ForceSavePlayerData then
				_G.CheckpointServerMain.ForceSavePlayerData(player.UserId)
			else
				-- Fallback: direct save
				local DataHandler = require(game.ReplicatedStorage.CheckpointSystem.Modules.DataHandler)
				local session = _G.CheckpointServerMain.GetPlayerSession(player.UserId)
				if session then
					DataHandler.SaveCheckpoint(player.UserId, {
						checkpoint = session.CurrentCheckpoint,
						deathCount = session.DeathCount,
						sessionStartTime = session.SessionStartTime,
						timestamp = os.time()
					})
				end
			end
		end)
		
		if success then
			saved = saved + 1
		else
			failed = failed + 1
			Log("ERROR", "Failed to save player: %s", player.Name)
		end
	end
	
	local elapsed = tick() - startTime
	Log("WARN", "Emergency save complete: %d saved, %d failed (%.1fs)", saved, failed, elapsed)
	
	return saved, failed
end

-- Restore from backup
function DisasterRecovery:RestoreFromBackup(userId)
	Log("WARN", "Restoring data for user %d from backup", userId)
	
	local backupStore = DataStoreService:GetDataStore("CheckpointBackup_v" .. Settings.VERSION)
	local primaryStore = DataStoreService:GetDataStore("CheckpointSystem_v" .. Settings.VERSION)
	
	local success, data = pcall(function()
		return backupStore:GetAsync("Player_" .. userId)
	end)
	
	if success and data then
		-- Restore to primary
		local restoreSuccess = pcall(function()
			primaryStore:SetAsync("Player_" .. userId, data)
		end)
		
		if restoreSuccess then
			Log("INFO", "Successfully restored data for user %d", userId)
			return true, data
		else
			Log("ERROR", "Failed to restore to primary store for user %d", userId)
			return false, nil
		end
	else
		Log("ERROR", "No backup data found for user %d", userId)
		return false, nil
	end
end

-- Create snapshot of all player data
function DisasterRecovery:CreateSnapshot()
	Log("INFO", "Creating full system snapshot...")
	
	local snapshotStore = DataStoreService:GetDataStore("SystemSnapshot_v1")
	
	local snapshot = {
		timestamp = os.time(),
		serverId = game.JobId,
		placeId = game.PlaceId,
		players = {}
	}
	
	local DataHandler = require(game.ReplicatedStorage.CheckpointSystem.Modules.DataHandler)
	
	for _, player in ipairs(Players:GetPlayers()) do
		local success, data = pcall(function()
			return DataHandler.LoadCheckpoint(player.UserId)
		end)
		
		if success and data then
			snapshot.players[player.UserId] = {
				name = player.Name,
				data = data,
				timestamp = os.time()
			}
		end
	end
	
	-- Save snapshot
	local saveSuccess = pcall(function()
		snapshotStore:SetAsync("Snapshot_" .. os.time(), snapshot)
		
		-- Also update "Latest" snapshot
		snapshotStore:SetAsync("Latest", snapshot)
	end)
	
	if saveSuccess then
		Log("INFO", "Snapshot created with %d players", self:CountPlayers(snapshot.players))
	else
		Log("ERROR", "Failed to save snapshot")
	end
	
	return saveSuccess
end

-- Helper: count players in snapshot
function DisasterRecovery:CountPlayers(playerTable)
	local count = 0
	for _ in pairs(playerTable) do
		count = count + 1
	end
	return count
end

-- Graceful shutdown procedure
function DisasterRecovery:GracefulShutdown()
	Log("WARN", "🛑 GRACEFUL SHUTDOWN INITIATED 🛑")
	
	local startTime = tick()
	
	-- 1. Stop accepting new checkpoint touches
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local shutdownFlag = Instance.new("BoolValue")
	shutdownFlag.Name = "ShutdownFlag"
	shutdownFlag.Value = true
	shutdownFlag.Parent = ReplicatedStorage
	
	-- 2. Emergency save all players
	local saved, failed = self:EmergencySaveAll()
	
	-- 3. Create final snapshot
	self:CreateSnapshot()
	
	-- 4. Wait for DataStore queue to clear
	local DataHandler = require(game.ReplicatedStorage.CheckpointSystem.Modules.DataHandler)
	local maxWait = 30
	local waited = 0
	
	while waited < maxWait do
		local queueStatus = DataHandler.GetQueueStatus()
		if queueStatus.Size == 0 then
			Log("INFO", "Queue cleared")
			break
		end
		
		Log("DEBUG", "Waiting for queue to clear: %d items remaining", queueStatus.Size)
		task.wait(1)
		waited = waited + 1
	end
	
	local elapsed = tick() - startTime
	Log("WARN", "Graceful shutdown complete: %d saved, %d failed, %.1fs elapsed", 
		saved, failed, elapsed)
	
	return {
		saved = saved,
		failed = failed,
		elapsed = elapsed,
		queueCleared = waited < maxWait
	}
end

-- Auto-recovery on server start
function DisasterRecovery:CheckAndRecover()
	Log("INFO", "Checking for recovery needs...")
	
	-- Check for crash indicators
	local crashStore = DataStoreService:GetDataStore("CrashDetection_v1")
	
	local success, lastCrash = pcall(function()
		return crashStore:GetAsync("LastCrash_" .. game.PlaceId)
	end)
	
	if success and lastCrash then
		Log("WARN", "Previous crash detected at %s", os.date("%Y-%m-%d %H:%M:%S", lastCrash.timestamp))
		
		-- Check if crash was recent (within 5 minutes)
		local timeSinceCrash = os.time() - lastCrash.timestamp
		if timeSinceCrash < 300 then
			Log("WARN", "Recent crash detected, running recovery procedures")
			
			-- Run recovery procedures here
			-- Example: verify data integrity, restore corrupted data, etc.
		end
		
		-- Clear crash indicator
		pcall(function()
			crashStore:RemoveAsync("LastCrash_" .. game.PlaceId)
		end)
	end
end

-- Mark potential crash (call periodically)
function DisasterRecovery:MarkHealthy()
	local crashStore = DataStoreService:GetDataStore("CrashDetection_v1")
	
	pcall(function()
		crashStore:SetAsync("LastHealthy_" .. game.PlaceId, {
			timestamp = os.time(),
			serverId = game.JobId
		})
	end)
end

-- Get recovery status
function DisasterRecovery:GetStatus()
	local snapshotStore = DataStoreService:GetDataStore("SystemSnapshot_v1")
	
	local latestSnapshot = nil
	local snapshotAge = nil
	
	pcall(function()
		latestSnapshot = snapshotStore:GetAsync("Latest")
		if latestSnapshot then
			snapshotAge = os.time() - latestSnapshot.timestamp
		end
	end)
	
	return {
		hasSnapshot = latestSnapshot ~= nil,
		snapshotAge = snapshotAge,
		snapshotPlayers = latestSnapshot and self:CountPlayers(latestSnapshot.players) or 0
	}
end

return DisasterRecovery
-- Checkpoint System V1.0 - Data Handler Module
-- Handles all DataStore operations with retry, backup, and migration support

local DataStoreService = game:GetService("DataStoreService")
local Settings = require(game.ReplicatedStorage.CheckpointSystem.Config.Settings)

local DataHandler = {}

-- Private variables
local primaryStore = nil
local backupStore = nil
local saveQueue = {}
local isInitialized = false

-- Logger utility
local function Log(level, message, ...)
	if not Settings.DEBUG_MODE and level == "DEBUG" then return end

	local prefix = "[DataHandler]"
	if level == "ERROR" then
		warn(prefix .. " " .. string.format(message, ...))
	elseif level == "WARN" then
		warn(prefix .. " " .. string.format(message, ...))
	elseif level == "INFO" or (Settings.DEBUG_MODE and level == "DEBUG") then
		print(prefix .. " " .. string.format(message, ...))
	end
end

-- Initialize DataStores
function DataHandler.Initialize()
	if isInitialized then
		Log("WARN", "DataHandler already initialized")
		return true
	end

	Log("INFO", "Initializing DataHandler...")

	-- Initialize primary DataStore
	local success, errorMsg = pcall(function()
		primaryStore = DataStoreService:GetDataStore("CheckpointSystem_v" .. Settings.VERSION)
		Log("DEBUG", "Primary DataStore initialized: CheckpointSystem_v%s", Settings.VERSION)
	end)

	if not success then
		Log("ERROR", "Failed to initialize primary DataStore: %s", errorMsg)
		return false
	end

	-- Initialize backup DataStore if enabled
	if Settings.ENABLE_BACKUP_DATASTORE then
		local backupSuccess, backupError = pcall(function()
			backupStore = DataStoreService:GetDataStore("CheckpointBackup_v" .. Settings.VERSION)
			Log("DEBUG", "Backup DataStore initialized: CheckpointBackup_v%s", Settings.VERSION)
		end)

		if not backupSuccess then
			Log("WARN", "Failed to initialize backup DataStore: %s", backupError)
			-- Continue without backup
		end
	end

	isInitialized = true
	Log("INFO", "DataHandler initialized successfully")
	return true
end

-- Load checkpoint data for a player
function DataHandler.LoadCheckpoint(userId)
	if not isInitialized then
		Log("ERROR", "DataHandler not initialized")
		return nil
	end

	if not userId or type(userId) ~= "number" then
		Log("ERROR", "Invalid userId: %s", tostring(userId))
		return nil
	end

	local key = "Player_" .. userId
	local data = nil
	local success = false

	-- Try to load from primary store
	success, data = DataHandler.LoadFromStore(primaryStore, key)

	if not success and backupStore then
		Log("WARN", "Primary load failed for %s, trying backup", key)
		success, data = DataHandler.LoadFromStore(backupStore, key)
		if success then
			Log("INFO", "Loaded data from backup for %s", key)
		end
	end

	if not success then
		Log("WARN", "Failed to load data for %s, using defaults", key)
		data = DataHandler.CreateFreshData()
	else
		-- Migrate data if needed
		if Settings.ENABLE_MIGRATION_SYSTEM then
			data = DataHandler.MigrateData(data, Settings.DATA_VERSION)
		end
	end

	Log("DEBUG", "Loaded data for %s: checkpoint=%s", key, tostring(data.checkpoint))
	return data
end

-- Load from a specific DataStore
function DataHandler.LoadFromStore(store, key)
	local success, data = pcall(function()
		return store:GetAsync(key)
	end)

	if not success then
		Log("ERROR", "Failed to load from store: %s", data)
		return false, nil
	end

	if not data then
		Log("DEBUG", "No data found for key: %s", key)
		return true, nil
	end

	-- Validate data structure
	if not DataHandler.ValidateDataStructure(data) then
		Log("WARN", "Invalid data structure for key: %s", key)
		return false, nil
	end

	return true, data
end

-- Save checkpoint data for a player
function DataHandler.SaveCheckpoint(userId, data)
	if not isInitialized then
		Log("ERROR", "DataHandler not initialized")
		return false
	end

	if not userId or type(userId) ~= "number" then
		Log("ERROR", "Invalid userId: %s", tostring(userId))
		return false
	end

	if not data or type(data) ~= "table" then
		Log("ERROR", "Invalid data: %s", tostring(data))
		return false
	end

	-- Ensure data has version
	data.version = Settings.DATA_VERSION
	data.timestamp = os.time()

	local key = "Player_" .. userId
	local success = false

	-- Try primary save
	success = DataHandler.SaveToStore(primaryStore, key, data)

	-- If primary fails and backup is available, try backup
	if not success and backupStore and Settings.ENABLE_BACKUP_DATASTORE then
		Log("WARN", "Primary save failed for %s, trying backup", key)
		local backupSuccess = DataHandler.SaveToStore(backupStore, key, data)
		if backupSuccess then
			Log("INFO", "Saved data to backup for %s", key)
			success = true
		end
	end

	-- If save failed, queue for later retry
	if not success then
		Log("ERROR", "Failed to save data for %s, queuing", key)
		DataHandler.QueueSave(key, data)
	else
		Log("DEBUG", "Saved data for %s: checkpoint=%s", key, tostring(data.checkpoint))
	end

	return success
end

-- Save to a specific DataStore with retry
function DataHandler.SaveToStore(store, key, data)
	for attempt = 1, Settings.SAVE_RETRY_ATTEMPTS do
		local success, errorMsg = pcall(function()
			store:SetAsync(key, data)
		end)

		if success then
			if attempt > 1 then
				Log("INFO", "Save succeeded on attempt %d for %s", attempt, key)
			end
			return true
		else
			Log("WARN", "Save attempt %d failed for %s: %s", attempt, key, errorMsg)

			if attempt < Settings.SAVE_RETRY_ATTEMPTS then
				local delay = Settings.SAVE_RETRY_BACKOFF[attempt] or 1
				wait(delay)
			end
		end
	end

	return false
end

-- Queue failed saves for background processing
function DataHandler.QueueSave(key, data)
	if #saveQueue >= Settings.MAX_QUEUE_SIZE then
		Log("ERROR", "Save queue full, dropping save for %s", key)
		return false
	end

	table.insert(saveQueue, {
		Key = key,
		Data = data,
		Timestamp = os.time(),
		Attempts = 0
	})

	Log("DEBUG", "Queued save for %s, queue size: %d", key, #saveQueue)
	return true
end

-- Process save queue (call this periodically)
function DataHandler.ProcessSaveQueue()
	if #saveQueue == 0 then return end

	Log("DEBUG", "Processing save queue (%d items)", #saveQueue)

	local remaining = {}
	for _, queued in ipairs(saveQueue) do
		queued.Attempts = queued.Attempts + 1

		-- Try to save
		local success = DataHandler.SaveToStore(primaryStore, queued.Key, queued.Data)

		if success then
			Log("INFO", "Processed queued save for %s", queued.Key)
		elseif queued.Attempts >= Settings.SAVE_RETRY_ATTEMPTS then
			Log("ERROR", "Dropping queued save for %s after %d attempts", queued.Key, queued.Attempts)
		else
			table.insert(remaining, queued)
		end
	end

	saveQueue = remaining
	Log("DEBUG", "Save queue processed, remaining: %d", #saveQueue)
end

-- Validate data structure
function DataHandler.ValidateDataStructure(data)
	if type(data) ~= "table" then return false end

	-- Required fields
	if type(data.checkpoint) ~= "number" or data.checkpoint < 0 then return false end
	if data.timestamp and type(data.timestamp) ~= "number" then return false end

	-- Optional fields with defaults
	if data.deathCount and type(data.deathCount) ~= "number" then return false end
	if data.sessionStartTime and type(data.sessionStartTime) ~= "number" then return false end

	return true
end

-- Create fresh data structure
function DataHandler.CreateFreshData()
	return {
		checkpoint = 0,
		deathCount = 0,
		sessionStartTime = os.time(),
		timestamp = os.time(),
		version = Settings.DATA_VERSION
	}
end

-- Migrate data to new version
function DataHandler.MigrateData(oldData, targetVersion)
	if not oldData or type(oldData) ~= "table" then
		Log("WARN", "Invalid data for migration, creating fresh")
		return DataHandler.CreateFreshData()
	end

	local data = table.clone(oldData)

	-- Migration logic for different versions
	if data.version < 1 then
		-- Version 0 → 1: Add deathCount if missing
		if not data.deathCount then
			data.deathCount = 0
		end
		data.version = 1
		Log("INFO", "Migrated data from v0 to v1")
	end

	-- Future migrations can be added here
	-- if data.version < 2 then
	--     Add new fields for v2
	--     data.version = 2
	-- end

	data.version = targetVersion
	return data
end

-- Get queue status for monitoring
function DataHandler.GetQueueStatus()
	return {
		Size = #saveQueue,
		MaxSize = Settings.MAX_QUEUE_SIZE,
		Items = saveQueue -- Be careful with this in production
	}
end

-- Force process queue (for debugging)
function DataHandler.ForceProcessQueue()
	if not Settings.DEBUG_MODE then
		Log("WARN", "ForceProcessQueue called outside debug mode")
		return
	end

	DataHandler.ProcessSaveQueue()
end

-- Generic save data to DataStore (for AdminManager)
function DataHandler.SaveData(datastoreName, key, data)
	if not isInitialized then
		Log("ERROR", "DataHandler not initialized")
		return false
	end

	local store = DataStoreService:GetDataStore(datastoreName)

	for attempt = 1, Settings.SAVE_RETRY_ATTEMPTS do
		local success, errorMsg = pcall(function()
			store:SetAsync(key, data)
		end)

		if success then
			Log("DEBUG", "Saved data to DataStore '%s' with key '%s'", datastoreName, key)
			return true
		else
			Log("WARN", "Save attempt %d failed for DataStore '%s' key '%s': %s", attempt, datastoreName, key, errorMsg)
			if attempt < Settings.SAVE_RETRY_ATTEMPTS then
				local delay = Settings.SAVE_RETRY_BACKOFF[attempt] or 1
				wait(delay)
			end
		end
	end

	return false
end

-- Generic load data from DataStore (for AdminManager)
function DataHandler.LoadData(datastoreName, key)
	if not isInitialized then
		Log("ERROR", "DataHandler not initialized")
		return nil
	end

	local store = DataStoreService:GetDataStore(datastoreName)

	local success, data = pcall(function()
		return store:GetAsync(key)
	end)

	if not success then
		Log("ERROR", "Failed to load from DataStore '%s' with key '%s'", datastoreName, key)
		return nil
	end

	Log("DEBUG", "Loaded data from DataStore '%s' with key '%s'", datastoreName, key)
	return data
end

-- Cleanup function
function DataHandler.Cleanup()
	saveQueue = {}
	primaryStore = nil
	backupStore = nil
	isInitialized = false
	Log("INFO", "DataHandler cleaned up")
end

return DataHandler
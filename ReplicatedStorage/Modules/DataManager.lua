-- DataManager.lua
-- Unified data management for checkpoint and sprint systems
-- Single Responsibility: data management, persistence, cleanup

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.Config)

local DataManager = {}

-- Private variables
local dataStore = DataStoreService:GetDataStore(Config.DATASTORE_NAME)
local playerDataCache = {} -- player -> data
local saveQueue = {} -- Queue for save operations to prevent race conditions
local isSaving = {} -- player -> boolean to prevent concurrent saves
local queueProcessorActive = {} -- player -> boolean to track if queue processor is running
local queueMetrics = {} -- player -> {size = number, processed = number, errors = number}
local dirtyPlayers = {} -- player -> boolean (true if data has changed and needs saving)

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
        racesWon = 0 -- Number of races won
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

-- Update death count
function DataManager.UpdateDeathCount(player)
    local data = playerDataCache[player]
    if not data then return end

    data.deathCount = data.deathCount + 1

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

-- Process save queue for a player (background queue processor)
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
                warn(string.format("[DataManager] Queue processor timeout (30s) for %s", player.Name))
                break
            end

            -- Check if player still exists and not currently saving
            if not playerDataCache[player] or isSaving[player] then
                break
            end

            -- Remove one item from queue
            table.remove(saveQueue[player], 1)
            queueMetrics[player].size = #saveQueue[player]
            queueMetrics[player].processed = queueMetrics[player].processed + 1
            processedCount = processedCount + 1

            -- Small delay to prevent overwhelming DataStore
            task.wait(0.1)

            -- Try to save again
            local success = DataManager.SavePlayerData(player)
            if not success then
                warn(string.format("[DataManager] Queue processor failed to save for %s", player.Name))
                break -- Stop processing if save fails
            end

            -- Safety limit: don't process more than 10 items at once
            if processedCount >= 10 then
                warn(string.format("[DataManager] Queue processor item limit reached for %s", player.Name))
                break
            end
        end

        queueProcessorActive[player] = false
        print(string.format("[DataManager] Queue processor finished for %s (processed: %d)", player.Name, processedCount))
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

-- Mark player data as dirty (needs saving)
function DataManager.MarkDirty(player)
    dirtyPlayers[player] = true
end

-- Check if player data is dirty
function DataManager.IsDirty(player)
    return dirtyPlayers[player] == true
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
        end
    end)
    print("[DataManager] Auto-save system started")
end

return DataManager

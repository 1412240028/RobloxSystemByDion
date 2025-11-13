-- DataManager.lua
-- Unified data management for checkpoint and sprint systems
-- Single Responsibility: data management, persistence, cleanup

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Settings = require(ReplicatedStorage.Config.Settings)

local DataManager = {}

-- Private variables
local dataStore = DataStoreService:GetDataStore(Settings.DATASTORE_NAME)
local playerDataCache = {} -- player -> data

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
        spawnPosition = Vector3.new(0, 0, 0),
        lastTouchTime = 0,
        deathCount = 0,
        sessionStartTime = tick()
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
end

-- Update checkpoint data
function DataManager.UpdateCheckpointData(player, checkpointId, spawnPosition)
    local data = playerDataCache[player]
    if not data then return end

    data.currentCheckpoint = checkpointId
    data.spawnPosition = spawnPosition or data.spawnPosition
    data.lastTouchTime = tick()
end

-- Update death count
function DataManager.UpdateDeathCount(player)
    local data = playerDataCache[player]
    if not data then return end

    data.deathCount = data.deathCount + 1
end

-- Save player data to DataStore
function DataManager.SavePlayerData(player)
    local data = playerDataCache[player]
    if not data then return end

    local key = Settings.DATASTORE_KEY_PREFIX .. tostring(data.userId)
    local saveData = {
        -- Sprint data
        isSprinting = data.isSprinting,
        toggleCount = data.toggleCount,
        speedViolations = data.speedViolations,
        -- Checkpoint data
        currentCheckpoint = data.currentCheckpoint,
        spawnPosition = {data.spawnPosition.X, data.spawnPosition.Y, data.spawnPosition.Z},
        deathCount = data.deathCount,
        lastPlayedVersion = Settings.VERSION
    }

    -- Retry logic with exponential backoff
    for attempt = 1, Settings.SAVE_RETRY_ATTEMPTS do
        local success, errorMessage = pcall(function()
            dataStore:SetAsync(key, saveData)
        end)

        if success then
            print(string.format("[DataManager] Saved data for %s", player.Name))
            return true
        else
            warn(string.format("[DataManager] Save attempt %d failed for %s: %s",
                attempt, player.Name, errorMessage))

            if attempt < Settings.SAVE_RETRY_ATTEMPTS then
                task.wait(Settings.SAVE_RETRY_BACKOFF[attempt] or 2)
            end
        end
    end

    warn(string.format("[DataManager] Failed to save data for %s after %d attempts",
        player.Name, Settings.SAVE_RETRY_ATTEMPTS))
    return false
end

-- Load player data from DataStore
function DataManager.LoadPlayerData(player)
    local data = playerDataCache[player]
    if not data then return end

    local key = Settings.DATASTORE_KEY_PREFIX .. tostring(data.userId)

    local success, loadedData = pcall(function()
        return dataStore:GetAsync(key)
    end)

    if success and loadedData then
        -- Apply loaded data
        data.isSprinting = loadedData.isSprinting or false
        data.toggleCount = loadedData.toggleCount or 0
        data.speedViolations = loadedData.speedViolations or 0
        data.currentCheckpoint = loadedData.currentCheckpoint or 0
        data.deathCount = loadedData.deathCount or 0
        if loadedData.spawnPosition then
            data.spawnPosition = Vector3.new(unpack(loadedData.spawnPosition))
        end

        print(string.format("[DataManager] Loaded data for %s (sprint: %s, checkpoint: %d, deaths: %d)",
            player.Name, tostring(data.isSprinting), data.currentCheckpoint, data.deathCount))
    else
        -- Use defaults
        warn(string.format("[DataManager] Load failed for %s, using defaults", player.Name))
        data.isSprinting = false
        data.toggleCount = 0
        data.speedViolations = 0
        data.currentCheckpoint = 0
        data.deathCount = 0
        data.spawnPosition = Vector3.new(0, 0, 0)
    end
end

-- Cleanup player data
function DataManager.CleanupPlayerData(player)
    playerDataCache[player] = nil
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

return DataManager

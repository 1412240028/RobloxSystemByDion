-- Checkpoint System V1.0 - Auto Save Service
-- Handles periodic background saving and data integrity checks

local RunService = game:GetService("RunService")
local Settings = require(game.ReplicatedStorage.CheckpointSystem.Config.Settings)

local AutoSaveService = {}

-- Private variables
local isRunning = false
local lastIntegrityCheck = 0
local saveStats = {
    TotalSaves = 0,
    FailedSaves = 0,
    LastSaveTime = 0
}

-- Logger utility
local function Log(level, message, ...)
    if not Settings.DEBUG_MODE and level == "DEBUG" then return end

    local prefix = "[AutoSaveService]"
    if level == "ERROR" then
        warn(prefix .. " " .. string.format(message, ...))
    elseif level == "WARN" then
        warn(prefix .. " " .. string.format(message, ...))
    elseif level == "INFO" or (Settings.DEBUG_MODE and level == "DEBUG") then
        print(prefix .. " " .. string.format(message, ...))
    end
end

-- Initialize the auto save service
function AutoSaveService.Initialize()
    if isRunning then
        Log("WARN", "AutoSaveService already running")
        return true
    end

    Log("INFO", "Initializing AutoSaveService...")

    -- Start the service
    AutoSaveService.Start()

    Log("INFO", "AutoSaveService initialized successfully")
    return true
end

-- Start the auto save service
function AutoSaveService.Start()
    if isRunning then return end

    isRunning = true

    -- Set up heartbeat connection for periodic tasks
    RunService.Heartbeat:Connect(function(deltaTime)
        AutoSaveService.OnHeartbeat(deltaTime)
    end)

    Log("DEBUG", "AutoSaveService started")
end

-- Stop the auto save service
function AutoSaveService.Stop()
    if not isRunning then return end

    isRunning = false
    Log("INFO", "AutoSaveService stopped")
end

-- Heartbeat callback
function AutoSaveService.OnHeartbeat(deltaTime)
    if not isRunning then return end

    -- Perform integrity checks periodically
    AutoSaveService.CheckDataIntegrity()

    -- Process any queued saves (this is also done in ServerMain, but as backup)
    local DataHandler = require(game.ReplicatedStorage.CheckpointSystem.Modules.DataHandler)
    DataHandler.ProcessSaveQueue()
end

-- Check data integrity
function AutoSaveService.CheckDataIntegrity()
    local currentTime = tick()

    -- Only check every 5 minutes
    if currentTime - lastIntegrityCheck < 300 then return end
    lastIntegrityCheck = currentTime

    Log("DEBUG", "Performing data integrity check")

    -- Check DataStore connectivity
    local DataHandler = require(game.ReplicatedStorage.CheckpointSystem.Modules.DataHandler)
    local testData = { test = true, timestamp = os.time() }
    local testSuccess = DataHandler.SaveCheckpoint(0, testData) -- Use 0 as test userId

    if testSuccess then
        Log("DEBUG", "DataStore connectivity OK")
    else
        Log("ERROR", "DataStore connectivity FAILED - saves may not work")
    end

    -- Check queue status
    local queueStatus = DataHandler.GetQueueStatus()
    if queueStatus.Size > Settings.MAX_QUEUE_SIZE * 0.8 then
        Log("WARN", "Save queue is getting full: %d/%d", queueStatus.Size, Settings.MAX_QUEUE_SIZE)
    end

    -- Update stats
    saveStats.LastIntegrityCheck = currentTime
end

-- Force integrity check
function AutoSaveService.ForceIntegrityCheck()
    lastIntegrityCheck = 0
    AutoSaveService.CheckDataIntegrity()
    Log("INFO", "Forced integrity check completed")
end

-- Get service status
function AutoSaveService.GetStatus()
    return {
        IsRunning = isRunning,
        LastIntegrityCheck = lastIntegrityCheck,
        TimeSinceLastCheck = tick() - lastIntegrityCheck,
        SaveStats = saveStats
    }
end

-- Update save statistics
function AutoSaveService.UpdateSaveStats(success)
    saveStats.TotalSaves = saveStats.TotalSaves + 1
    saveStats.LastSaveTime = tick()

    if not success then
        saveStats.FailedSaves = saveStats.FailedSaves + 1
    end
end

-- Get save statistics
function AutoSaveService.GetSaveStatistics()
    local successRate = 0
    if saveStats.TotalSaves > 0 then
        successRate = ((saveStats.TotalSaves - saveStats.FailedSaves) / saveStats.TotalSaves) * 100
    end

    return {
        TotalSaves = saveStats.TotalSaves,
        FailedSaves = saveStats.FailedSaves,
        SuccessRate = successRate,
        LastSaveTime = saveStats.LastSaveTime,
        TimeSinceLastSave = tick() - saveStats.LastSaveTime
    }
end

-- Reset statistics
function AutoSaveService.ResetStatistics()
    saveStats = {
        TotalSaves = 0,
        FailedSaves = 0,
        LastSaveTime = 0
    }
    Log("INFO", "Save statistics reset")
end

-- Emergency save all players
function AutoSaveService.EmergencySaveAll()
    if not Settings.DEBUG_MODE then
        Log("WARN", "Emergency save called outside debug mode")
        return false
    end

    Log("WARN", "Performing emergency save of all players")

    local Players = game:GetService("Players")
    local ServerMain = require(game.ServerScriptService.CheckpointSystem.ServerMain)

    local saved = 0
    local failed = 0

    for _, player in ipairs(Players:GetPlayers()) do
        local success = ServerMain.ForceSavePlayerData(player.UserId)
        if success then
            saved = saved + 1
        else
            failed = failed + 1
        end
    end

    Log("INFO", "Emergency save completed: %d saved, %d failed", saved, failed)
    return saved, failed
end

-- Cleanup function
function AutoSaveService.Cleanup()
    AutoSaveService.Stop()
    saveStats = {
        TotalSaves = 0,
        FailedSaves = 0,
        LastSaveTime = 0
    }
    Log("INFO", "AutoSaveService cleaned up")
end

return AutoSaveService

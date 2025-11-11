-- Checkpoint System V1.0 - Server Main Script
-- Main server-side controller for the checkpoint system

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Module imports
local Settings = require(game.ReplicatedStorage.CheckpointSystem.Config.Settings)
local CheckpointManager = require(game.ReplicatedStorage.CheckpointSystem.Modules.CheckpointManager)
local DataHandler = require(game.ReplicatedStorage.CheckpointSystem.Modules.DataHandler)
local SecurityValidator = require(game.ReplicatedStorage.CheckpointSystem.Modules.SecurityValidator)

-- Remote events
local CheckpointReachedEvent = game.ReplicatedStorage.CheckpointSystem.Remotes.CheckpointReached

-- Private variables
local playerSessions = {} -- {userId: sessionData}
local autoSaveConnections = {} -- {userId: connection}
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

-- Initialize the server system
function Initialize()
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

    if not modulesInitialized then
        Log("ERROR", "Failed to initialize one or more modules")
        return false
    end

    -- Set up player connections
    Players.PlayerAdded:Connect(OnPlayerAdded)
    Players.PlayerRemoving:Connect(OnPlayerRemoving)

    -- Set up remote event handler
    CheckpointReachedEvent.OnServerEvent:Connect(OnCheckpointReached)

    -- Start background services
    StartBackgroundServices()

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

    Log("DEBUG", "Player session created for %s: checkpoint=%d", player.Name, session.CurrentCheckpoint)
end

-- Handle player leaving
function OnPlayerLeaving(player)
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

    -- Fire event to all clients for effects/UI
    CheckpointReachedEvent:FireAllClients(player, checkpointOrder, checkpointPart)

    Log("INFO", "Checkpoint %d reached by %s", checkpointOrder, player.Name)
end

-- Save player data asynchronously
function SavePlayerDataAsync(userId)
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

        -- Release lock
        SecurityValidator.ReleaseSaveLock(userId)

        if success then
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

-- Start background services
function StartBackgroundServices()
    -- Process save queue periodically
    RunService.Heartbeat:Connect(function()
        DataHandler.ProcessSaveQueue()
    end)

    Log("DEBUG", "Background services started")
end

-- Get player session
function GetPlayerSession(userId)
    return playerSessions[userId]
end

-- Get player checkpoint
function GetPlayerCheckpoint(userId)
    local session = playerSessions[userId]
    return session and session.CurrentCheckpoint or 0
end

-- Update player death count
function UpdatePlayerDeathCount(userId)
    local session = playerSessions[userId]
    if session then
        session.DeathCount = session.DeathCount + 1
        Log("DEBUG", "Death count updated for %d: %d", userId, session.DeathCount)
        return session.DeathCount
    end
    return 0
end

-- Cleanup player session
function CleanupPlayerSession(userId)
    playerSessions[userId] = nil

    if autoSaveConnections[userId] then
        autoSaveConnections[userId]:Disconnect()
        autoSaveConnections[userId] = nil
    end

    Log("DEBUG", "Session cleaned up for %d", userId)
end

-- Get system status
function GetSystemStatus()
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
function DebugSystem()
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
function Cleanup()
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

    isInitialized = false
    Log("INFO", "Server system cleaned up")
end

-- Initialize on script run
if Initialize() then
    Log("INFO", "Checkpoint System Server started successfully")
else
    Log("ERROR", "Failed to start Checkpoint System Server")
end

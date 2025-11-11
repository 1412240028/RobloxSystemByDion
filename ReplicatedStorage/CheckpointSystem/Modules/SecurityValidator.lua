-- Checkpoint System V1.0 - Security Validator Module
-- Handles all checkpoint touch validation with race condition protection

local Players = game:GetService("Players")
local Settings = require(game.ReplicatedStorage.CheckpointSystem.Config.Settings)

local SecurityValidator = {}

-- Private variables
local playerSessions = {} -- {userId: {lastTouchTime, flags, currentCheckpoint}}
local saveLocks = {} -- {userId: boolean} - prevent concurrent saves
local isInitialized = false

-- Logger utility
local function Log(level, message, ...)
    if not Settings.DEBUG_MODE and level == "DEBUG" then return end

    local prefix = "[SecurityValidator]"
    if level == "ERROR" then
        warn(prefix .. " " .. string.format(message, ...))
    elseif level == "WARN" then
        warn(prefix .. " " .. string.format(message, ...))
    elseif level == "INFO" or (Settings.DEBUG_MODE and level == "DEBUG") then
        print(prefix .. " " .. string.format(message, ...))
    end
end

-- Initialize the security validator
function SecurityValidator.Initialize()
    if isInitialized then
        Log("WARN", "SecurityValidator already initialized")
        return true
    end

    Log("INFO", "Initializing SecurityValidator...")

    -- Set up player session cleanup
    Players.PlayerRemoving:Connect(function(player)
        SecurityValidator.CleanupPlayerSession(player.UserId)
    end)

    isInitialized = true
    Log("INFO", "SecurityValidator initialized successfully")
    return true
end

-- Main validation function for checkpoint touches
function SecurityValidator.ValidateCheckpointTouch(player, checkpointPart, checkpointOrder)
    if not isInitialized then
        Log("ERROR", "SecurityValidator not initialized")
        return false, "System not initialized"
    end

    if not player or not player:IsA("Player") then
        Log("WARN", "Invalid player object")
        return false, "Invalid player"
    end

    local userId = player.UserId
    local character = player.Character

    -- Layer 1: Basic validation
    local basicValid, basicReason = SecurityValidator.BasicValidation(player, character, checkpointPart)
    if not basicValid then
        Log("DEBUG", "Basic validation failed for %s: %s", player.Name, basicReason)
        return false, basicReason
    end

    -- Layer 2: Security validation
    local securityValid, securityReason = SecurityValidator.SecurityValidation(userId, checkpointPart.Position, checkpointOrder)
    if not securityValid then
        Log("WARN", "Security validation failed for %s: %s", player.Name, securityReason)
        SecurityValidator.HandleValidationFailure(userId, securityReason)
        return false, securityReason
    end

    -- Layer 3: Progression validation
    local progressionValid, progressionReason = SecurityValidator.ProgressionValidation(userId, checkpointOrder)
    if not progressionValid then
        Log("WARN", "Progression validation failed for %s: %s", player.Name, progressionReason)
        SecurityValidator.HandleValidationFailure(userId, progressionReason)
        return false, progressionReason
    end

    -- All validations passed
    SecurityValidator.UpdatePlayerSession(userId, checkpointOrder)
    Log("DEBUG", "Validation passed for %s at checkpoint %d", player.Name, checkpointOrder)
    return true, "Valid"
end

-- Layer 1: Basic validation checks
function SecurityValidator.BasicValidation(player, character, checkpointPart)
    -- Check if player is valid
    if not player or not player:IsA("Player") then
        return false, "Invalid player"
    end

    -- Check if character exists and is alive
    if not character then
        return false, "No character"
    end

    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid or humanoid.Health <= 0 then
        return false, "Character not alive"
    end

    -- Check if checkpoint part is valid
    if not checkpointPart or not checkpointPart:IsA("BasePart") then
        return false, "Invalid checkpoint"
    end

    -- Check if checkpoint still exists in workspace
    if checkpointPart.Parent == nil then
        return false, "Checkpoint removed"
    end

    return true, "Basic checks passed"
end

-- Layer 2: Security validation checks
function SecurityValidator.SecurityValidation(userId, checkpointPosition, checkpointOrder)
    local session = SecurityValidator.GetPlayerSession(userId)

    -- Check cooldown
    if session.lastTouchTime then
        local timeSinceLastTouch = tick() - session.lastTouchTime
        if timeSinceLastTouch < Settings.COOLDOWN_SECONDS then
            return false, string.format("Cooldown active (%.1fs remaining)",
                Settings.COOLDOWN_SECONDS - timeSinceLastTouch)
        end
    end

    -- Check distance (if player character exists)
    local player = Players:GetPlayerByUserId(userId)
    if player and player.Character and player.Character.PrimaryPart then
        local playerPosition = player.Character.PrimaryPart.Position
        local distance = (playerPosition - checkpointPosition).Magnitude

        if distance > Settings.MAX_DISTANCE_STUDS then
            return false, string.format("Too far from checkpoint (%.1f studs > %d limit)",
                distance, Settings.MAX_DISTANCE_STUDS)
        end
    end

    -- Check if player is flagged
    if session.flags and session.flags.ignoreUntil then
        if tick() < session.flags.ignoreUntil then
            local remaining = session.flags.ignoreUntil - tick()
            return false, string.format("Player flagged (%.1fs remaining)", remaining)
        else
            -- Flag expired, clear it
            session.flags = nil
        end
    end

    return true, "Security checks passed"
end

-- Layer 3: Progression validation checks
function SecurityValidator.ProgressionValidation(userId, checkpointOrder)
    local session = SecurityValidator.GetPlayerSession(userId)
    local currentCheckpoint = session.currentCheckpoint or 0

    -- Allow touching current checkpoint (for respawns)
    if checkpointOrder == currentCheckpoint then
        return true, "Same checkpoint"
    end

    -- Allow progressing forward
    if checkpointOrder == currentCheckpoint + 1 then
        return true, "Valid progression"
    end

    -- Reject skipping checkpoints
    if checkpointOrder > currentCheckpoint + 1 then
        return false, string.format("Cannot skip checkpoints (current: %d, attempted: %d)",
            currentCheckpoint, checkpointOrder)
    end

    -- Reject going backwards (except for special cases)
    if checkpointOrder < currentCheckpoint then
        return false, string.format("Cannot go backwards (current: %d, attempted: %d)",
            currentCheckpoint, checkpointOrder)
    end

    return true, "Progression checks passed"
end

-- Handle validation failures with progressive penalties
function SecurityValidator.HandleValidationFailure(userId, reason)
    local session = SecurityValidator.GetPlayerSession(userId)

    -- Initialize flags if needed
    if not session.flags then
        session.flags = {
            warningCount = 0,
            ignoreUntil = 0,
            resetTime = 0
        }
    end

    local flags = session.flags

    -- Progressive throttling
    flags.warningCount = flags.warningCount + 1

    if flags.warningCount == 1 then
        -- First offense: Warning (no penalty yet)
        Log("INFO", "Warning issued to user %d for: %s", userId, reason)
    elseif flags.warningCount == 2 then
        -- Second offense: Temporary ignore
        flags.ignoreUntil = tick() + Settings.FLAG_WARNING_DURATION
        Log("WARN", "User %d flagged for %d seconds: %s", userId, Settings.FLAG_WARNING_DURATION, reason)
    elseif flags.warningCount >= 3 then
        -- Third+ offense: Extended ignore
        flags.ignoreUntil = tick() + Settings.FLAG_IGNORE_DURATION
        flags.resetTime = tick() + Settings.DEATH_RESET_SECONDS
        Log("ERROR", "User %d severely flagged for %d seconds: %s", userId, Settings.FLAG_IGNORE_DURATION, reason)
    end
end

-- Update player session after successful validation
function SecurityValidator.UpdatePlayerSession(userId, checkpointOrder)
    local session = SecurityValidator.GetPlayerSession(userId)

    session.currentCheckpoint = checkpointOrder
    session.lastTouchTime = tick()

    -- Reset flags on successful touch
    if session.flags then
        session.flags.warningCount = 0
        session.flags.ignoreUntil = 0
    end

    Log("DEBUG", "Updated session for %d: checkpoint=%d", userId, checkpointOrder)
end

-- Get or create player session
function SecurityValidator.GetPlayerSession(userId)
    if not playerSessions[userId] then
        playerSessions[userId] = {
            currentCheckpoint = 0,
            lastTouchTime = 0,
            flags = nil
        }
    end
    return playerSessions[userId]
end

-- Check if player can save (race condition protection)
function SecurityValidator.CanSave(userId)
    if not Settings.ENABLE_RACE_CONDITION_LOCKS then
        return true
    end

    return not saveLocks[userId]
end

-- Acquire save lock
function SecurityValidator.AcquireSaveLock(userId)
    if not Settings.ENABLE_RACE_CONDITION_LOCKS then
        return true
    end

    if saveLocks[userId] then
        Log("WARN", "Save lock already held for %d", userId)
        return false
    end

    saveLocks[userId] = true
    Log("DEBUG", "Acquired save lock for %d", userId)
    return true
end

-- Release save lock
function SecurityValidator.ReleaseSaveLock(userId)
    if not Settings.ENABLE_RACE_CONDITION_LOCKS then
        return
    end

    if saveLocks[userId] then
        saveLocks[userId] = false
        Log("DEBUG", "Released save lock for %d", userId)
    end
end

-- Get current checkpoint for player
function SecurityValidator.GetCurrentCheckpoint(userId)
    local session = SecurityValidator.GetPlayerSession(userId)
    return session.currentCheckpoint or 0
end

-- Set current checkpoint (for loading from DataStore)
function SecurityValidator.SetCurrentCheckpoint(userId, checkpoint)
    local session = SecurityValidator.GetPlayerSession(userId)
    session.currentCheckpoint = checkpoint
    Log("DEBUG", "Set checkpoint for %d to %d", userId, checkpoint)
end

-- Check if player is flagged
function SecurityValidator.IsPlayerFlagged(userId)
    local session = SecurityValidator.GetPlayerSession(userId)
    return session.flags and session.flags.ignoreUntil and tick() < session.flags.ignoreUntil
end

-- Get player status for debugging
function SecurityValidator.GetPlayerStatus(userId)
    local session = SecurityValidator.GetPlayerSession(userId)
    return {
        CurrentCheckpoint = session.currentCheckpoint or 0,
        LastTouchTime = session.lastTouchTime or 0,
        IsFlagged = SecurityValidator.IsPlayerFlagged(userId),
        Flags = session.flags,
        HasSaveLock = saveLocks[userId] or false
    }
end

-- Cleanup player session
function SecurityValidator.CleanupPlayerSession(userId)
    playerSessions[userId] = nil
    saveLocks[userId] = nil
    Log("DEBUG", "Cleaned up session for %d", userId)
end

-- Cleanup all sessions (for testing/debugging)
function SecurityValidator.Cleanup()
    playerSessions = {}
    saveLocks = {}
    isInitialized = false
    Log("INFO", "SecurityValidator cleaned up")
end

return SecurityValidator

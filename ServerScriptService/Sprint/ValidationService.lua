-- ValidationService.lua
-- Semua validasi & security checks
-- Anti-cheat & validation logic

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Sprint.Config)
local SharedTypes = require(ReplicatedStorage.Sprint.SharedTypes)

local PlayerDataManager = require(script.Parent.PlayerDataManager)

local ValidationService = {}

-- Validate toggle request
function ValidationService.ValidateToggleRequest(player, requestedState)
    local response = table.clone(SharedTypes.ValidationResponse)
    response.success = false
    response.reason = SharedTypes.ValidationResult.INVALID_REQUEST
    response.targetSpeed = Config.NORMAL_SPEED

    -- Basic type validation
    if typeof(requestedState) ~= "boolean" then
        response.reason = SharedTypes.ValidationResult.INVALID_REQUEST
        return response
    end

    -- Check if player exists
    if not player or not player:IsA("Player") then
        response.reason = SharedTypes.ValidationResult.PLAYER_NOT_FOUND
        return response
    end

    -- Get player data
    local playerData = PlayerDataManager.GetPlayerData(player)
    if not playerData then
        response.reason = SharedTypes.ValidationResult.PLAYER_NOT_FOUND
        return response
    end

    -- Check character and humanoid
    if not playerData.character or not playerData.humanoid then
        response.reason = SharedTypes.ValidationResult.CHARACTER_NOT_FOUND
        return response
    end

    -- Rate limiting check
    local timeSinceLastToggle = tick() - playerData.lastToggleTime
    if timeSinceLastToggle < Config.DEBOUNCE_TIME then
        response.reason = SharedTypes.ValidationResult.DEBOUNCE_ACTIVE
        return response
    end

    -- All checks passed
    response.success = true
    response.reason = SharedTypes.ValidationResult.SUCCESS
    response.playerData = playerData
    response.targetSpeed = requestedState and Config.SPRINT_SPEED or Config.NORMAL_SPEED

    return response
end

-- Validate speed value
function ValidationService.ValidateSpeed(requestedSpeed)
    if typeof(requestedSpeed) ~= "number" then
        return false, Config.NORMAL_SPEED
    end

    -- Clamp to allowed range
    local clampedSpeed = math.clamp(requestedSpeed, 0, Config.MAX_ALLOWED_SPEED)
    return true, clampedSpeed
end

-- Check speed integrity (anti-cheat)
function ValidationService.CheckSpeedIntegrity(player)
    local playerData = PlayerDataManager.GetPlayerData(player)
    if not playerData or not playerData.humanoid then
        return false
    end

    local actualSpeed = playerData.humanoid.WalkSpeed
    local expectedSpeed = playerData.isSprinting and Config.SPRINT_SPEED or Config.NORMAL_SPEED

    local difference = math.abs(actualSpeed - expectedSpeed)
    return difference > Config.SPEED_TOLERANCE
end

-- Validate player has permission to sprint (future use)
function ValidationService.ValidateSprintPermission(player)
    -- For now, always allow
    -- Future: check game mode, admin status, etc.
    return true
end

-- Get rate limit status
function ValidationService.GetRateLimitStatus(player)
    local playerData = PlayerDataManager.GetPlayerData(player)
    if not playerData then return false end

    local timeSinceLastToggle = tick() - playerData.lastToggleTime
    return timeSinceLastToggle >= Config.DEBOUNCE_TIME
end

-- Log validation failure
function ValidationService.LogValidationFailure(player, reason, details)
    warn(string.format("[ValidationService] Validation failed for %s: %s (%s)",
        player and player.Name or "Unknown", reason, details or "No details"))
end

return ValidationService

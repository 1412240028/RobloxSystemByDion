-- SystemManager.lua
-- Unified system manager for checkpoint and sprint systems
-- Handles admin functions, system coordination, and cross-system operations

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Settings = require(ReplicatedStorage.Config.Settings)

local SystemManager = {}

-- Private variables
local adminCache = {}
local systemStatus = {
    initialized = false,
    checkpointSystemActive = false,
    sprintSystemActive = false,
    playerCount = 0,
    lastUpdate = 0
}

-- Logger utility
local function Log(level, message, ...)
    if not Settings.DEBUG_MODE and level == "DEBUG" then return end

    local prefix = "[SystemManager]"
    if level == "ERROR" then
        warn(prefix .. " " .. string.format(message, ...))
    elseif level == "WARN" then
        warn(prefix .. " " .. string.format(message, ...))
    elseif level == "INFO" or (Settings.DEBUG_MODE and level == "DEBUG") then
        print(prefix .. " " .. string.format(message, ...))
    end
end

-- Initialize the unified system
function SystemManager:Init()
    Log("INFO", "Initializing unified checkpoint and sprint system...")

    -- Validate configuration
    local configErrors = Settings.ValidateConfig()
    if #configErrors > 0 then
        Log("ERROR", "Configuration validation failed:")
        for _, error in ipairs(configErrors) do
            Log("ERROR", "  - " .. error)
        end
        return false
    end

    -- Build admin cache
    self:BuildAdminCache()

    -- Initialize subsystems
    systemStatus.checkpointSystemActive = true -- Will be set by actual modules
    systemStatus.sprintSystemActive = true -- Will be set by actual modules
    systemStatus.initialized = true
    systemStatus.lastUpdate = tick()

    Log("INFO", "System initialized successfully")
    Log("INFO", "Admins loaded: %d", #adminCache)
    return true
end

-- Build admin cache from settings
function SystemManager:BuildAdminCache()
    adminCache = {}
    for userId, permission in pairs(Settings.ADMIN_UIDS) do
        adminCache[userId] = {
            permission = permission,
            level = Settings.ADMIN_PERMISSION_LEVELS[permission] or 1,
            lastActive = 0
        }
    end
    Log("DEBUG", "Admin cache built with %d entries", #adminCache)
end

-- Check if player is admin
function SystemManager:IsAdmin(player)
    if not player then return false end

    local adminData = adminCache[player.UserId]
    if adminData then
        adminData.lastActive = tick()
        return true
    end
    return false
end

-- Get admin permission level
function SystemManager:GetAdminLevel(player)
    if not player then return 0 end

    local adminData = adminCache[player.UserId]
    return adminData and adminData.level or 0
end

-- Get admin permission name
function SystemManager:GetAdminPermission(player)
    if not player then return nil end

    local adminData = adminCache[player.UserId]
    return adminData and adminData.permission or nil
end

-- Add admin at runtime (for owner-level operations)
function SystemManager:AddAdmin(addedBy, userId, permission)
    if not self:IsAdmin(addedBy) or self:GetAdminLevel(addedBy) < Settings.ADMIN_PERMISSION_LEVELS.OWNER then
        return false, "Insufficient permissions"
    end

    if adminCache[userId] then
        return false, "User is already an admin"
    end

    if not Settings.ADMIN_PERMISSION_LEVELS[permission] then
        return false, "Invalid permission level"
    end

    adminCache[userId] = {
        permission = permission,
        level = Settings.ADMIN_PERMISSION_LEVELS[permission],
        lastActive = tick()
    }

    -- Update settings (runtime only, not persisted)
    Settings.ADMIN_UIDS[userId] = permission

    Log("INFO", "Admin added: %d (%s) by %s", userId, permission, addedBy.Name)
    return true, "Admin added successfully"
end

-- Remove admin at runtime
function SystemManager:RemoveAdmin(removedBy, userId)
    if not self:IsAdmin(removedBy) or self:GetAdminLevel(removedBy) < Settings.ADMIN_PERMISSION_LEVELS.OWNER then
        return false, "Insufficient permissions"
    end

    if not adminCache[userId] then
        return false, "User is not an admin"
    end

    local oldPermission = adminCache[userId].permission
    adminCache[userId] = nil
    Settings.ADMIN_UIDS[userId] = nil

    Log("INFO", "Admin removed: %d (%s) by %s", userId, oldPermission, removedBy.Name)
    return true, "Admin removed successfully"
end

-- Get system status
function SystemManager:GetSystemStatus()
    systemStatus.playerCount = #Players:GetPlayers()
    systemStatus.lastUpdate = tick()

    return {
        initialized = systemStatus.initialized,
        checkpointSystemActive = systemStatus.checkpointSystemActive,
        sprintSystemActive = systemStatus.sprintSystemActive,
        playerCount = systemStatus.playerCount,
        adminCount = #adminCache,
        lastUpdate = systemStatus.lastUpdate,
        version = Settings.VERSION,
        debugMode = Settings.DEBUG_MODE
    }
end

-- Get player data (unified view)
function SystemManager:GetPlayerData(player)
    if not player then return nil end

    -- This will be implemented when DataManager is available
    -- For now, return basic info
    return {
        userId = player.UserId,
        name = player.Name,
        isAdmin = self:IsAdmin(player),
        adminLevel = self:GetAdminLevel(player),
        -- DataManager will add checkpoint and sprint data here
    }
end

-- Get global status (for cross-server admin)
function SystemManager:GetGlobalStatus()
    -- This will integrate with MessagingService for cross-server data
    return self:GetSystemStatus()
end

-- Execute admin command
function SystemManager:ExecuteAdminCommand(player, command, args)
    if not self:IsAdmin(player) then
        return false, "Admin access required"
    end

    local adminLevel = self:GetAdminLevel(player)

    -- Command routing based on permission level
    if command == "status" then
        return true, self:GetSystemStatus()
    elseif command == "players" then
        local playerList = {}
        for _, p in ipairs(Players:GetPlayers()) do
            table.insert(playerList, {
                name = p.Name,
                userId = p.UserId,
                isAdmin = self:IsAdmin(p)
            })
        end
        return true, playerList
    elseif command == "add_admin" and adminLevel >= Settings.ADMIN_PERMISSION_LEVELS.OWNER then
        if not args or #args < 2 then
            return false, "Usage: add_admin <userId> <permission>"
        end
        local targetUserId = tonumber(args[1])
        local permission = args[2]
        return self:AddAdmin(player, targetUserId, permission)
    elseif command == "remove_admin" and adminLevel >= Settings.ADMIN_PERMISSION_LEVELS.OWNER then
        if not args or #args < 1 then
            return false, "Usage: remove_admin <userId>"
        end
        local targetUserId = tonumber(args[1])
        return self:RemoveAdmin(player, targetUserId)
    else
        return false, "Unknown command or insufficient permissions"
    end
end

-- Cleanup on player leave
function SystemManager:CleanupPlayer(player)
    -- Any player-specific cleanup can go here
    Log("DEBUG", "Player cleanup: %s", player.Name)
end

return SystemManager

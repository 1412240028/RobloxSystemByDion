-- SystemManager.lua
-- Unified system manager for checkpoint and sprint systems
-- Handles admin functions, system coordination, and cross-system operations

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.Config)
local AdminLogger = require(ReplicatedStorage.Modules.AdminLogger)

local SystemManager = {}

-- Private variables
local adminCache = {}
local commandCooldowns = {} -- {userId = {command = lastUsedTime}}
local systemStatus = {
    initialized = false,
    checkpointSystemActive = false,
    sprintSystemActive = false,
    playerCount = 0,
    lastUpdate = 0
}

-- Logger utility
local function Log(level, message, ...)
    if not Config.DEBUG_MODE and level == "DEBUG" then return end

    local prefix = "[SystemManager]"
    if level == "ERROR" then
        warn(prefix .. " " .. string.format(message, ...))
    elseif level == "WARN" then
        warn(prefix .. " " .. string.format(message, ...))
    elseif level == "INFO" or (Config.DEBUG_MODE and level == "DEBUG") then
        print(prefix .. " " .. string.format(message, ...))
    end
end

-- Initialize the unified system
function SystemManager:Init()
    Log("INFO", "Initializing unified checkpoint and sprint system...")

    -- Validate configuration
    local configErrors = Config.ValidateConfig()
    if #configErrors > 0 then
        Log("ERROR", "Configuration validation failed:")
        for _, error in ipairs(configErrors) do
            Log("ERROR", "  - " .. error)
        end
        return false
    end

    -- Initialize admin logger
    AdminLogger:Init()

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

-- Build admin cache from DataStore
function SystemManager:BuildAdminCache()
    adminCache = {}
    local DataManager = require(game.ReplicatedStorage.Modules.DataManager)
    DataManager.LoadAdminData()

    local allAdminData = DataManager.GetAllAdminData()
    for userId, adminData in pairs(allAdminData) do
        adminCache[userId] = {
            permission = adminData.permission,
            level = adminData.level,
            lastActive = adminData.lastActive or 0
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
	-- Allow bootstrap: if no admins exist, allow adding first admin without permissions
	local hasExistingAdmins = false
	for _ in pairs(adminCache) do
		hasExistingAdmins = true
		break
	end

	if hasExistingAdmins and (not self:IsAdmin(addedBy) or self:GetAdminLevel(addedBy) < Config.ADMIN_PERMISSION_LEVELS.OWNER) then
		return false, "Insufficient permissions"
	end

	if adminCache[userId] then
		return false, "User is already an admin"
	end

	if not Config.ADMIN_PERMISSION_LEVELS[permission] then
		return false, "Invalid permission level"
	end

	local DataManager = require(game.ReplicatedStorage.Modules.DataManager)
	local success, errorMsg = DataManager.AddAdmin(userId, permission, addedBy)
	if not success then
		return false, errorMsg
	end

	adminCache[userId] = {
		permission = permission,
		level = Config.ADMIN_PERMISSION_LEVELS[permission],
		lastActive = tick()
	}

	Log("INFO", "Admin added: %d (%s) by %s", userId, permission, addedBy.Name)
	return true, "Admin added successfully"
end

-- Remove admin at runtime
function SystemManager:RemoveAdmin(removedBy, userId)
    if not self:IsAdmin(removedBy) or self:GetAdminLevel(removedBy) < Config.ADMIN_PERMISSION_LEVELS.OWNER then
        return false, "Insufficient permissions"
    end

    if not adminCache[userId] then
        return false, "User is not an admin"
    end

    local oldPermission = adminCache[userId].permission
    adminCache[userId] = nil
    Config.ADMIN_UIDS[userId] = nil

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
        version = Config.VERSION,
        debugMode = Config.DEBUG_MODE
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

-- Parse command with prefix triggers
function SystemManager:ParseCommand(message)
    -- Check for command prefixes: /, !, ;
    local prefix = message:sub(1, 1)
    if prefix ~= "/" and prefix ~= "!" and prefix ~= ";" then
        return nil -- Not a command
    end

    -- Remove prefix and trim whitespace
    local commandText = message:sub(2):gsub("^%s+", "")

    -- Split command and arguments
    local parts = {}
    for part in commandText:gmatch("%S+") do
        table.insert(parts, part)
    end

    if #parts == 0 then
        return nil -- Empty command
    end

    local command = parts[1]:lower()
    local args = {}
    for i = 2, #parts do
        table.insert(args, parts[i])
    end

    return command, args
end

-- Execute admin command
function SystemManager:ExecuteAdminCommand(player, command, args)
    -- Allow basic commands for all players (MEMBER level and above)
    local isBasicCommand = (command == "status" or command == "players" or command == "help" or command == "cp_status")
    local adminLevel = self:GetAdminLevel(player)

    if not isBasicCommand and not self:IsAdmin(player) then
        AdminLogger:LogPermissionDenied(player, command, "Not an admin")
        return false, "Admin access required"
    end

    -- For basic commands, require at least MEMBER level (everyone)
    if isBasicCommand and adminLevel < Config.ADMIN_PERMISSION_LEVELS.MEMBER then
        return false, "Access denied"
    end

    -- Rate limiting check
    local playerId = player.UserId
    commandCooldowns[playerId] = commandCooldowns[playerId] or {}

    local lastUsed = commandCooldowns[playerId][command] or 0
    local cooldownTime = Config.ADMIN_COMMAND_COOLDOWN or 1
    if tick() - lastUsed < cooldownTime then
        AdminLogger:LogRateLimitHit(player, command)
        return false, string.format("Command on cooldown. Wait %.1f seconds.", cooldownTime - (tick() - lastUsed))
    end

    -- Input validation and sanitization
    if not self:ValidateCommandInput(command, args) then
        AdminLogger:Log(AdminLogger.Levels.WARN, "INVALID_COMMAND_INPUT", player, nil, {
            command = command,
            args = args and table.concat(args, " ") or "none"
        })
        return false, "Invalid command input"
    end

    -- Command routing based on permission level
    local success, result
    if command == "status" then
        success, result = true, self:GetSystemStatus()
    elseif command == "players" then
        local playerList = {}
        for _, p in ipairs(Players:GetPlayers()) do
            table.insert(playerList, {
                name = p.Name,
                userId = p.UserId,
                isAdmin = self:IsAdmin(p)
            })
        end
        success, result = true, playerList
    elseif command == "add_admin" and adminLevel >= Config.ADMIN_PERMISSION_LEVELS.OWNER then
        if not args or #args < 2 then
            return false, "Usage: add_admin <userId> <permission>"
        end
        local targetUserId = tonumber(args[1])
        local permission = args[2]
        success, result = self:AddAdmin(player, targetUserId, permission)
    elseif command == "remove_admin" and adminLevel >= Config.ADMIN_PERMISSION_LEVELS.OWNER then
        if not args or #args < 1 then
            return false, "Usage: remove_admin <userId>"
        end
        local targetUserId = tonumber(args[1])
        success, result = self:RemoveAdmin(player, targetUserId)
    elseif command == "startrace" and adminLevel >= Config.ADMIN_PERMISSION_LEVELS.MODERATOR then
        -- Import RaceController here to avoid circular dependency
        local RaceController = require(game.ReplicatedStorage.Modules.RaceController)
        local canStart, reason = RaceController.CanStartRace()
        if canStart then
            local raceSuccess = RaceController.StartRace()
            if raceSuccess then
                success, result = true, "Race started successfully"
            else
                return false, "Failed to start race"
            end
        else
            return false, reason
        end
    elseif command == "endrace" and adminLevel >= Config.ADMIN_PERMISSION_LEVELS.MODERATOR then
        local RaceController = require(game.ReplicatedStorage.Modules.RaceController)
        local raceSuccess = RaceController.ForceEndRace()
        if raceSuccess then
            success, result = true, "Race ended successfully"
        else
            return false, "No active race to end"
        end
    elseif command == "race" and args and args[1] == "status" then
        local RaceController = require(game.ReplicatedStorage.Modules.RaceController)
        local status = RaceController.GetRaceStatus()
        local stats = RaceController.GetRaceStats()
        success, result = true, {
            active = status.active,
            participants = status.participantCount,
            timeRemaining = status.timeRemaining,
            winner = status.winner,
            totalRaces = stats.totalRaces,
            averageParticipants = string.format("%.1f", stats.averageParticipants),
            cooldownRemaining = stats.cooldownRemaining > 0 and string.format("%.1f", stats.cooldownRemaining) or "0"
        }
    elseif command == "reset_cp" and adminLevel >= Config.ADMIN_PERMISSION_LEVELS.MODERATOR then
        if not args or #args < 1 then
            return false, "Usage: reset_cp <playerName>"
        end
        local targetPlayer = self:FindPlayerByName(args[1])
        if not targetPlayer then
            return false, "Player not found"
        end
        -- Import MainServer to access reset function
        local MainServer = require(game.ServerScriptService.MainServer)
        MainServer.ResetPlayerCheckpoints(targetPlayer)
        success, result = true, string.format("Reset checkpoints for %s", targetPlayer.Name)
    elseif command == "reset_all_cp" and adminLevel >= Config.ADMIN_PERMISSION_LEVELS.ADMIN then
        local MainServer = require(game.ServerScriptService.MainServer)
        local resetCount = 0
        for _, p in ipairs(Players:GetPlayers()) do
            MainServer.ResetPlayerCheckpoints(p)
            resetCount = resetCount + 1
        end
        success, result = true, string.format("Reset checkpoints for %d players", resetCount)
    elseif command == "set_cp" and adminLevel >= Config.ADMIN_PERMISSION_LEVELS.MODERATOR then
        if not args or #args < 2 then
            return false, "Usage: set_cp <playerName> <checkpointId>"
        end
        local targetPlayer = self:FindPlayerByName(args[1])
        if not targetPlayer then
            return false, "Player not found"
        end
        local checkpointId = tonumber(args[2])
        if not checkpointId or checkpointId < 0 then
            return false, "Invalid checkpoint ID"
        end
        -- Import DataManager to set checkpoint
        local DataManager = require(game.ReplicatedStorage.Modules.DataManager)
        DataManager.SetCheckpoint(targetPlayer, checkpointId)
        success, result = true, string.format("Set %s to checkpoint %d", targetPlayer.Name, checkpointId)
    elseif command == "cp_status" then
        if args and #args >= 1 then
            local targetPlayer = self:FindPlayerByName(args[1])
            if not targetPlayer then
                return false, "Player not found"
            end
            local DataManager = require(game.ReplicatedStorage.Modules.DataManager)
            local playerData = DataManager.GetPlayerData(targetPlayer)
            if playerData then
                success, result = true, {
                    player = targetPlayer.Name,
                    currentCheckpoint = playerData.currentCheckpoint or 0,
                    finishCount = playerData.finishCount or 0,
                    touchedCheckpoints = playerData.touchedCheckpoints and #playerData.touchedCheckpoints or 0
                }
            else
                return false, "No data found for player"
            end
        else
            -- Show all players' checkpoint status
            local DataManager = require(game.ReplicatedStorage.Modules.DataManager)
            local statusList = {}
            for _, p in ipairs(Players:GetPlayers()) do
                local playerData = DataManager.GetPlayerData(p)
                if playerData then
                    table.insert(statusList, {
                        name = p.Name,
                        cp = playerData.currentCheckpoint or 0,
                        finishes = playerData.finishCount or 0
                    })
                end
            end
            success, result = true, statusList
        end
    elseif command == "complete_cp" and adminLevel >= Config.ADMIN_PERMISSION_LEVELS.MODERATOR then
        if not args or #args < 2 then
            return false, "Usage: complete_cp <playerName> <checkpointId>"
        end
        local targetPlayer = self:FindPlayerByName(args[1])
        if not targetPlayer then
            return false, "Player not found"
        end
        local checkpointId = tonumber(args[2])
        if not checkpointId or checkpointId < 1 then
            return false, "Invalid checkpoint ID"
        end
        -- Import DataManager to force complete checkpoint
        local DataManager = require(game.ReplicatedStorage.Modules.DataManager)
        DataManager.ForceCompleteCheckpoint(targetPlayer, checkpointId)
        success, result = true, string.format("Force completed checkpoint %d for %s", checkpointId, targetPlayer.Name)
    elseif command == "finish_race" and adminLevel >= Config.ADMIN_PERMISSION_LEVELS.MODERATOR then
        if not args or #args < 1 then
            return false, "Usage: finish_race <playerName>"
        end
        local targetPlayer = self:FindPlayerByName(args[1])
        if not targetPlayer then
            return false, "Player not found"
        end
        -- Import DataManager to increment finish count
        local DataManager = require(game.ReplicatedStorage.Modules.DataManager)
        DataManager.UpdateFinishCount(targetPlayer)
        success, result = true, string.format("Force finished race for %s", targetPlayer.Name)
    elseif command == "help" then
        local helpText = [[
=== Checkpoint System Admin Commands ===

GENERAL:
  status - Show system status
  players - List all players
  help - Show this help

CHECKPOINT COMMANDS:
  reset_cp <playerName> - Reset checkpoints for specific player
  reset_all_cp - Reset checkpoints for all players (ADMIN+)
  set_cp <playerName> <checkpointId> - Set player to specific checkpoint
  cp_status [playerName] - Show checkpoint status (all players if no name)
  complete_cp <playerName> <checkpointId> - Force complete checkpoint
  finish_race <playerName> - Force finish race for player

RACE COMMANDS:
  startrace - Start a race (MOD+)
  endrace - End current race (MOD+)
  race status - Show race status

ADMIN MANAGEMENT (OWNER+):
  add_admin <userId> <permission> - Add admin
  remove_admin <userId> - Remove admin

Permission levels: OWNER(5), DEVELOPER(4), MODERATOR(3), HELPER(2), TESTER(1)
        ]]
        success, result = true, helpText
    else
        return false, "Unknown command or insufficient permissions. Use 'help' for command list."
    end

    -- Update cooldown after successful command execution
    if success then
        commandCooldowns[playerId][command] = tick()

        -- Log successful command execution
        AdminLogger:Log(AdminLogger.Levels.INFO, "COMMAND_EXECUTED", player, nil, {
            command = command,
            args = args and table.concat(args, " ") or "none"
        })
    end

    return success, result
end

-- Validate command input
function SystemManager:ValidateCommandInput(command, args)
    -- Basic validation for known commands
    if command == "add_admin" then
        if not args or #args < 2 then return false end
        local userId = tonumber(args[1])
        if not userId or userId <= 0 then return false end
        local permission = args[2]
        if not Config.ADMIN_PERMISSION_LEVELS[permission] then return false end
    elseif command == "remove_admin" then
        if not args or #args < 1 then return false end
        local userId = tonumber(args[1])
        if not userId or userId <= 0 then return false end
    elseif command == "set_cp" or command == "complete_cp" then
        if not args or #args < 2 then return false end
        local checkpointId = tonumber(args[2])
        if not checkpointId or checkpointId < 0 then return false end
    elseif command == "reset_cp" or command == "cp_status" or command == "finish_race" then
        if not args or #args < 1 then return false end
    end

    -- Sanitize args (remove potentially harmful characters)
    if args then
        for i, arg in ipairs(args) do
            -- Remove null bytes and other control characters
            args[i] = arg:gsub("[%z\1-\31\127-\255]", "")
            -- Limit length to prevent abuse
            if #args[i] > 100 then
                args[i] = args[i]:sub(1, 100)
            end
        end
    end

    return true
end

-- Find player by name (case-insensitive partial match)
function SystemManager:FindPlayerByName(name)
    if not name then return nil end

    name = name:lower()
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Name:lower():find(name, 1, true) then
            return player
        end
    end
    return nil
end

-- Cleanup on player leave
function SystemManager:CleanupPlayer(player)
    -- Clean up command cooldowns
    if commandCooldowns[player.UserId] then
        commandCooldowns[player.UserId] = nil
    end

    Log("DEBUG", "Player cleanup: %s", player.Name)
end

return SystemManager

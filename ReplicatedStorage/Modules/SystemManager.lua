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
local cacheReady = false
local commandCooldowns = {} -- {userId = {command = lastUsedTime}}
local remoteEventRateLimits = {} -- {userId = {eventName = {count, lastReset}}}
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

	-- Initialize admin logger (only on server)
	if AdminLogger then
		AdminLogger:Init()
	end

	-- Build admin cache
	self:BuildAdminCache()

	-- Initialize rate limiting system
	self:InitRateLimiting()

	-- Initialize subsystems
	systemStatus.checkpointSystemActive = true -- Will be set by actual modules
	systemStatus.sprintSystemActive = true -- Will be set by actual modules
	systemStatus.initialized = true
	systemStatus.lastUpdate = tick()

	Log("INFO", "System initialized successfully")

	-- ✅ FIXED: Count admins correctly (moved to proper location)
	local adminCount = 0
	for _ in pairs(adminCache) do
		adminCount = adminCount + 1
	end
	Log("INFO", "Admins loaded: %d", adminCount)
	return true
end

-- Build admin cache from DataStore
-- Build admin cache from DataStore
function SystemManager:BuildAdminCache()
	Log("INFO", "Building admin cache from DataStore...")
	adminCache = {}
	cacheReady = false

	local DataManager = require(game.ReplicatedStorage.Modules.DataManager)

	local loadSuccess, adminCount = DataManager.LoadAdminData()

	if not loadSuccess then
		Log("INFO", "📦 No existing admin data in DataStore - using Config defaults")
	else
		Log("INFO", "📦 Admin data loaded from DataStore")
	end

	local allAdminData = DataManager.GetAllAdminData()

	if not allAdminData or type(allAdminData) ~= "table" then
		warn("[SystemManager] ❌ Failed to get admin data from DataManager!")
		cacheReady = true
		return
	end

	-- Build local cache
	local cachedCount = 0
	for userId, adminData in pairs(allAdminData) do
		if type(adminData) == "table" and adminData.permission then
			-- ✅ CRITICAL FIX: Convert userId to NUMBER
			local numericUserId = tonumber(userId)

			if numericUserId then
				adminCache[numericUserId] = {  -- ✅ Use NUMBER as key
					permission = adminData.permission,
					level = adminData.level or Config.ADMIN_PERMISSION_LEVELS[adminData.permission] or 1,
					lastActive = adminData.lastActive or tick()
				}
				cachedCount = cachedCount + 1

				if Config.DEBUG_MODE then
					Log("DEBUG", "Admin cached: UserID %d (%s, Level %d)", 
						numericUserId, adminData.permission, adminCache[numericUserId].level)
				end
			else
				warn(string.format("[SystemManager] ⚠️ Invalid UserID (not a number): %s", tostring(userId)))
			end
		else
			warn(string.format("[SystemManager] ⚠️ Invalid admin data for UserID %s", tostring(userId)))
		end
	end

	cacheReady = true

	if cachedCount > 0 then
		Log("INFO", "✅ Admin cache built successfully: %d admins loaded", cachedCount)
	else
		warn("[SystemManager] ⚠️ Admin cache is empty! No admins loaded.")
		warn("[SystemManager] Use /add_admin command to add first admin (bootstrap mode)")
	end
end

-- Check if cache is ready
function SystemManager:IsCacheReady()
	return cacheReady
end

-- Check if player is admin
function SystemManager:IsAdmin(player)
	if not player then return false end

	local numericUserId = tonumber(player.UserId)  -- ✅ Ensure NUMBER
	local adminData = adminCache[numericUserId]  -- ✅ Use NUMBER key

	if adminData then
		if adminData.permission == "MEMBER" then
			return false
		end
		adminData.lastActive = tick()
		return true
	end
	return false
end

-- Get admin permission level
function SystemManager:GetAdminLevel(player)
	if not player then return 0 end

	local numericUserId = tonumber(player.UserId)  -- ✅ Ensure NUMBER
	local adminData = adminCache[numericUserId]  -- ✅ Use NUMBER key
	return adminData and adminData.level or 0
end

-- Get admin permission name
function SystemManager:GetAdminPermission(player)
	if not player then return nil end

	local numericUserId = tonumber(player.UserId)  -- ✅ Ensure NUMBER
	local adminData = adminCache[numericUserId]  -- ✅ Use NUMBER key
	return adminData and adminData.permission or nil
end

-- Add admin at runtime (for owner-level operations)
function SystemManager:AddAdmin(addedBy, userId, permission)
	local numericUserId = tonumber(userId)  -- ✅ Ensure NUMBER

	if not numericUserId then
		return false, "Invalid UserID"
	end

	-- Bootstrap check
	local hasExistingAdmins = false
	for _ in pairs(adminCache) do
		hasExistingAdmins = true
		break
	end

	if hasExistingAdmins and (not self:IsAdmin(addedBy) or self:GetAdminLevel(addedBy) < Config.ADMIN_PERMISSION_LEVELS.OWNER) then
		return false, "Insufficient permissions"
	end

	if adminCache[numericUserId] then  -- ✅ Use NUMBER key
		return false, "User is already an admin"
	end

	if not Config.ADMIN_PERMISSION_LEVELS[permission] then
		return false, "Invalid permission level"
	end

	local DataManager = require(game.ReplicatedStorage.Modules.DataManager)
	local success, errorMsg = DataManager.AddAdmin(numericUserId, permission, addedBy)  -- ✅ Pass NUMBER
	if not success then
		return false, errorMsg
	end

	adminCache[numericUserId] = {  -- ✅ Use NUMBER key
		permission = permission,
		level = Config.ADMIN_PERMISSION_LEVELS[permission],
		lastActive = tick()
	}

	Log("INFO", "Admin added: %d (%s) by %s", numericUserId, permission, addedBy.Name)
	return true, "Admin added successfully"
end

-- Remove admin at runtime
function SystemManager:RemoveAdmin(removedBy, userId)
	local numericUserId = tonumber(userId)  -- ✅ Ensure NUMBER

	if not numericUserId then
		return false, "Invalid UserID"
	end

	if not self:IsAdmin(removedBy) or self:GetAdminLevel(removedBy) < Config.ADMIN_PERMISSION_LEVELS.OWNER then
		return false, "Insufficient permissions"
	end

	if not adminCache[numericUserId] then  -- ✅ Use NUMBER key
		return false, "User is not an admin"
	end

	local oldPermission = adminCache[numericUserId].permission
	adminCache[numericUserId] = nil  -- ✅ Use NUMBER key
	Config.ADMIN_UIDS[numericUserId] = nil

	Log("INFO", "Admin removed: %d (%s) by %s", numericUserId, oldPermission, removedBy.Name)
	return true, "Admin removed successfully"
end

-- ✅ NEW: Helper to count admins in cache
function SystemManager:GetAdminCount()
	local count = 0
	for _ in pairs(adminCache) do
		count = count + 1
	end
	return count
end

-- Get system status
function SystemManager:GetSystemStatus()
	systemStatus.playerCount = #Players:GetPlayers()
	systemStatus.lastUpdate = tick()

	-- ✅ FIXED: Count admins correctly
	local adminCount = 0
	for _ in pairs(adminCache) do
		adminCount = adminCount + 1
	end

	return {
		initialized = systemStatus.initialized,
		checkpointSystemActive = systemStatus.checkpointSystemActive,
		sprintSystemActive = systemStatus.sprintSystemActive,
		playerCount = systemStatus.playerCount,
		adminCount = adminCount, -- ✅ FIXED: Use calculated count
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
		Log("WARN", "Command rejected - not admin: %s (%d) tried %s", player.Name, player.UserId, command)
		return false, "Admin access required"
	end

	-- For basic commands, require at least MEMBER level (everyone)
	if isBasicCommand and adminLevel < Config.ADMIN_PERMISSION_LEVELS.MEMBER then
		Log("WARN", "Command rejected - insufficient level: %s (%d, level %d) tried %s", player.Name, player.UserId, adminLevel, command)
		return false, "Access denied"
	end

	-- Rate limiting check
	local playerId = player.UserId
	commandCooldowns[playerId] = commandCooldowns[playerId] or {}

	local lastUsed = commandCooldowns[playerId][command] or 0
	local cooldownTime = Config.ADMIN_COMMAND_COOLDOWN or 1
	if tick() - lastUsed < cooldownTime then
		AdminLogger:LogRateLimitHit(player, command)
		Log("WARN", "Command rejected - rate limited: %s tried %s", player.Name, command)
		return false, string.format("Command on cooldown. Wait %.1f seconds.", cooldownTime - (tick() - lastUsed))
	end

	-- Input validation and sanitization
	if not self:ValidateCommandInput(command, args) then
		AdminLogger:Log(AdminLogger.Levels.WARN, "INVALID_COMMAND_INPUT", player, nil, {
			command = command,
			args = args and table.concat(args, " ") or "none"
		})
		Log("WARN", "Command rejected - invalid input: %s tried %s", player.Name, command)
		return false, "Invalid command input"
	end

	Log("INFO", "Executing command: %s by %s (level %d)", command, player.Name, adminLevel)

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
		-- Fire the reset event to avoid circular dependency
		local ResetCheckpointsEvent = require(game.ReplicatedStorage.Remotes.ResetCheckpointsEvent)
		ResetCheckpointsEvent.Event:Fire(targetPlayer)
		success, result = true, string.format("Reset checkpoints for %s", targetPlayer.Name)
	elseif command == "reset_all_cp" and adminLevel >= Config.ADMIN_PERMISSION_LEVELS.ADMIN then
		local ResetCheckpointsEvent = require(game.ReplicatedStorage.Remotes.ResetCheckpointsEvent)
		local resetCount = 0
		for _, p in ipairs(Players:GetPlayers()) do
			ResetCheckpointsEvent.Event:Fire(p)
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

RACE TESTING (MOD+):
  testrace - Manually trigger a race for testing

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

-- Handle player joining
function SystemManager:OnPlayerAdded(player)
	print(string.format("[SystemManager] Player joined: %s (UserID: %d)", 
		player.Name, player.UserId))

	-- Wait for cache to be ready
	local maxWaitTime = 10
	local startTime = tick()

	while not cacheReady and (tick() - startTime) < maxWaitTime do
		task.wait(0.1)
	end

	if not cacheReady then
		warn(string.format("[SystemManager] ⚠️ Cache still not ready after %ds for %s", 
			maxWaitTime, player.Name))
	end

	-- ✅ DEBUG: Log cache state with TYPE info
	print(string.format("[SystemManager] DEBUG - Cache check for UserID %d (type: %s):", 
		player.UserId, type(player.UserId)))
	print(string.format("[SystemManager] DEBUG - adminCache type: %s", type(adminCache)))
	print(string.format("[SystemManager] DEBUG - adminCache size: %d", self:GetAdminCount()))

	-- ✅ Debug: Print all cached admins WITH KEY TYPES
	if Config.DEBUG_MODE then
		print("[SystemManager] DEBUG - Current adminCache contents:")
		for userId, data in pairs(adminCache) do
			print(string.format("  - UserID %s (type: %s): %s (Level %d)", 
				tostring(userId), type(userId), data.permission, data.level))
		end
	end

	-- ✅ CRITICAL FIX: Ensure we're checking with NUMBER key
	local numericUserId = tonumber(player.UserId)
	local existingAdmin = adminCache[numericUserId]  -- ✅ Use NUMBER key

	print(string.format("[SystemManager] DEBUG - Looking for key: %d, Found: %s", 
		numericUserId, existingAdmin and "YES" or "NO"))

	if existingAdmin then
		print(string.format("[SystemManager] ✅ FOUND in cache - %s has role: %s (Level %d)", 
			player.Name, existingAdmin.permission, existingAdmin.level))

		existingAdmin.lastActive = tick()

		local DataManager = require(game.ReplicatedStorage.Modules.DataManager)
		DataManager.UpdateAdminActivity(player.UserId)

		print(string.format("[SystemManager] Welcome %s - Role: %s (Level %d)", 
			player.Name, existingAdmin.permission, existingAdmin.level))
	else
		print(string.format("[SystemManager] ⚠️ NOT FOUND in cache - UserID %d", player.UserId))

		-- Double-check DataManager directly
		local DataManager = require(game.ReplicatedStorage.Modules.DataManager)
		local dmAdminData = DataManager.GetAdminData(player.UserId)

		if dmAdminData then
			warn(string.format("[SystemManager] ❌ CRITICAL: Found in DataManager but NOT in SystemManager cache!"))
			warn(string.format("[SystemManager] ❌ DataManager has: %s (Level %d)", dmAdminData.permission, dmAdminData.level))

			-- Sync to local cache
			adminCache[numericUserId] = {  -- ✅ Use NUMBER key
				permission = dmAdminData.permission,
				level = dmAdminData.level,
				lastActive = tick()
			}

			print(string.format("[SystemManager] ✅ Synced from DataManager - %s: %s (Level %d)", 
				player.Name, dmAdminData.permission, dmAdminData.level))
		else
			-- Truly new player - assign MEMBER
			self:AssignMemberRole(player)
			print(string.format("[SystemManager] ℹ️ %s assigned default role: MEMBER", player.Name))
		end
	end
end

-- Auto-assign MEMBER role to new players
function SystemManager:AssignMemberRole(player)
	if not player then return end

	local userId = player.UserId
	local numericUserId = tonumber(userId)  -- ✅ Ensure NUMBER type

	-- Triple-check before assigning
	if adminCache[numericUserId] then  -- ✅ Use NUMBER key
		warn(string.format("[SystemManager] ⚠️ AssignMemberRole blocked - %s already has role: %s", 
			player.Name, adminCache[numericUserId].permission))
		return
	end

	-- Check DataManager one last time
	local DataManager = require(game.ReplicatedStorage.Modules.DataManager)
	local dmAdminData = DataManager.GetAdminData(userId)

	if dmAdminData then
		warn(string.format("[SystemManager] ⚠️ AssignMemberRole blocked - DataManager has: %s", dmAdminData.permission))

		-- Sync to local cache
		adminCache[numericUserId] = {  -- ✅ Use NUMBER key
			permission = dmAdminData.permission,
			level = dmAdminData.level,
			lastActive = tick()
		}
		return
	end

	-- NOW safe to assign MEMBER
	print(string.format("[SystemManager] Assigning MEMBER role to %s (UserID: %d)", player.Name, userId))

	adminCache[numericUserId] = {  -- ✅ Use NUMBER key
		permission = "MEMBER",
		level = Config.ADMIN_PERMISSION_LEVELS.MEMBER or 1,
		lastActive = tick()
	}

	-- Save to DataStore
	local success, errorMsg = DataManager.AddAdmin(userId, "MEMBER", nil)

	if success then
		print(string.format("[SystemManager] ✅ Auto-assigned MEMBER role to %s (UserID: %d)", player.Name, userId))
	else
		warn(string.format("[SystemManager] ⚠️ MEMBER assignment failed for %s: %s", 
			player.Name, errorMsg or "unknown error"))
	end
end

-- Get player's current role info
function SystemManager:GetPlayerRoleInfo(player)
	if not player then return nil end

	local userId = player.UserId
	if not adminCache[userId] then
		return {
			permission = "NONE",
			level = 0,
			isAdmin = false
		}
	end

	local roleData = adminCache[userId]
	return {
		permission = roleData.permission,
		level = roleData.level,
		isAdmin = roleData.permission ~= "MEMBER",
		lastActive = roleData.lastActive
	}
end

-- Initialize rate limiting system
function SystemManager:InitRateLimiting()
	Log("INFO", "Initializing rate limiting system...")

	-- Connect to remote events for rate limiting
	local RemoteEvents = require(game.ReplicatedStorage.Remotes.RemoteEvents)

	-- Rate limit sprint toggle events
	RemoteEvents.OnToggleRequested(function(player, requestedState)
		if not self:CheckRateLimit(player, "SprintToggle", Config.MAX_TOGGLES_PER_SECOND or 5) then
			AdminLogger:Log(AdminLogger.Levels.WARN, "RATE_LIMIT_EXCEEDED", player, nil, {
				event = "SprintToggle",
				limit = Config.MAX_TOGGLES_PER_SECOND or 5
			})
			Log("WARN", "Rate limit exceeded for sprint toggle: %s", player.Name)
			return -- Block the event
		end
		-- Continue with normal processing (this would be handled by MainServer)
	end)

	-- Rate limit checkpoint touch events
	RemoteEvents.OnCheckpointTouched(function(player, checkpointId)
		if not self:CheckRateLimit(player, "CheckpointTouch", 10) then -- 10 touches per second max
			AdminLogger:Log(AdminLogger.Levels.WARN, "RATE_LIMIT_EXCEEDED", player, nil, {
				event = "CheckpointTouch",
				checkpointId = checkpointId,
				limit = 10
			})
			Log("WARN", "Rate limit exceeded for checkpoint touch: %s", player.Name)
			return -- Block the event
		end
		-- Continue with normal processing
	end)

	-- Rate limit race queue events
	RemoteEvents.OnRaceQueueJoinReceived(function(player)
		if not self:CheckRateLimit(player, "RaceQueue", 2) then -- 2 queue actions per second max
			AdminLogger:Log(AdminLogger.Levels.WARN, "RATE_LIMIT_EXCEEDED", player, nil, {
				event = "RaceQueue",
				limit = 2
			})
			Log("WARN", "Rate limit exceeded for race queue: %s", player.Name)
			return -- Block the event
		end
		-- Continue with normal processing
	end)

	Log("INFO", "Rate limiting system initialized")
end

-- Check rate limit for a player and event
function SystemManager:CheckRateLimit(player, eventName, maxPerSecond)
	if not player then return false end

	local userId = player.UserId
	local currentTime = tick()

	-- Initialize rate limit tracking for user if not exists
	remoteEventRateLimits[userId] = remoteEventRateLimits[userId] or {}
	remoteEventRateLimits[userId][eventName] = remoteEventRateLimits[userId][eventName] or {
		count = 0,
		lastReset = currentTime
	}

	local rateData = remoteEventRateLimits[userId][eventName]

	-- Reset counter if a second has passed
	if currentTime - rateData.lastReset >= 1 then
		rateData.count = 0
		rateData.lastReset = currentTime
	end

	-- Check if under limit
	if rateData.count < maxPerSecond then
		rateData.count = rateData.count + 1
		return true
	else
		-- Rate limit exceeded
		return false
	end
end

-- Get rate limit status for debugging
function SystemManager:GetRateLimitStatus(player)
	if not player then return nil end

	return remoteEventRateLimits[player.UserId] or {}
end

-- Reset rate limits for a player (admin command)
function SystemManager:ResetRateLimits(player)
	if player and remoteEventRateLimits[player.UserId] then
		remoteEventRateLimits[player.UserId] = nil
		Log("INFO", "Rate limits reset for %s", player.Name)
		return true
	end
	return false
end

-- Cleanup on player leave
function SystemManager:CleanupPlayer(player)
	-- Clean up command cooldowns
	if commandCooldowns[player.UserId] then
		commandCooldowns[player.UserId] = nil
	end

	-- Clean up rate limit data
	if remoteEventRateLimits[player.UserId] then
		remoteEventRateLimits[player.UserId] = nil
	end

	Log("DEBUG", "Player cleanup: %s", player.Name)
end

return SystemManager
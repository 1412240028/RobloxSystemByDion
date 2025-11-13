-- Admin Manager Module V1.0 - COMPLETE FIXED VERSION
-- Global admin system with secure DataStore backend and rate-limited messaging

local AdminManager = {}

-- Module imports
local Settings = require(game.ReplicatedStorage.CheckpointSystem.Config.Settings)
local DataHandler = require(game.ReplicatedStorage.CheckpointSystem.Modules.DataHandler)
local GlobalMessenger = require(game.ReplicatedStorage.CheckpointSystem.Modules.GlobalMessenger)
local AdminConfigManager = require(game.ReplicatedStorage.CheckpointSystem.Modules.AdminConfigManager)

-- Services
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")

-- Admin data structure (for backwards compatibility)
AdminManager.AdminData = {
	CommandLogs = {},
	GlobalStats = {
		TotalCommands = 0,
		LastActivity = os.time()
	},
	BannedPlayers = {}
}

-- Permission level names
AdminManager.PERMISSION_NAMES = {
	[1] = "TESTER",
	[2] = "HELPER",
	[3] = "MODERATOR",
	[4] = "DEVELOPER",
	[5] = "OWNER"
}

-- ========================================
-- INITIALIZATION
-- ========================================

function AdminManager:Init()
	if not Settings.ENABLE_ADMIN_SYSTEM then
		print("[AdminManager] Admin system disabled in settings")
		return
	end

	print("[AdminManager] Initializing admin system...")

	-- 1. Initialize secure admin config
	AdminConfigManager:Init()

	-- 2. Initialize global messenger
	GlobalMessenger:Init()

	-- 3. Subscribe to global topics if enabled
	if Settings.ENABLE_GLOBAL_ADMIN_COMMANDS then
		GlobalMessenger:Subscribe(Settings.GLOBAL_MESSAGE_TOPIC, function(message)
			self:HandleGlobalMessage(message)
		end)

		GlobalMessenger:Subscribe(Settings.GLOBAL_STATUS_TOPIC, function(message)
			self:HandleStatusRequest(message)
		end)

		GlobalMessenger:Subscribe(Settings.GLOBAL_DATA_REQUEST_TOPIC, function(message)
			self:HandleDataRequest(message)
		end)

		print("[AdminManager] Global messaging enabled")
	end

	-- 4. Load legacy data (ban list, logs)
	self:LoadLegacyData()

	-- 5. Set up API if enabled
	if Settings.ENABLE_EXTERNAL_API then
		self:SetupAPI()
	end

	print("[AdminManager] Initialized with", AdminConfigManager:GetAdminCount(), "admins")
end

-- Load legacy data (bans, logs) from DataStore
function AdminManager:LoadLegacyData()
	local success, data = pcall(function()
		return DataHandler.LoadData(Settings.ADMIN_GLOBAL_DATASTORE, "LegacyAdminData")
	end)

	if success and data then
		self.AdminData.BannedPlayers = data.BannedPlayers or {}
		self.AdminData.CommandLogs = data.CommandLogs or {}
		self.AdminData.GlobalStats = data.GlobalStats or {
			TotalCommands = 0,
			LastActivity = os.time()
		}
	end
end

-- Save legacy data
function AdminManager:SaveLegacyData()
	local data = {
		BannedPlayers = self.AdminData.BannedPlayers,
		CommandLogs = self.AdminData.CommandLogs,
		GlobalStats = self.AdminData.GlobalStats
	}

	pcall(function()
		DataHandler.SaveData(Settings.ADMIN_GLOBAL_DATASTORE, "LegacyAdminData", data)
	end)
end

-- ========================================
-- ADMIN PERMISSION CHECKS
-- ========================================

-- Check if player is admin (using AdminConfigManager)
function AdminManager:IsAdmin(player)
	if not player or not player.UserId then return false end
	local isAdmin = AdminConfigManager:IsAdmin(player.UserId)
	local permission = AdminConfigManager:GetPermission(player.UserId)
	return isAdmin, permission
end

-- Get admin permission level
function AdminManager:GetPermissionLevel(player)
	local permission = AdminConfigManager:GetPermission(player.UserId)
	return Settings.ADMIN_PERMISSION_LEVELS[permission] or 0
end

-- ========================================
-- ADMIN MANAGEMENT COMMANDS
-- ========================================

-- Add admin by UID (using AdminConfigManager)
function AdminManager:AddAdminByUID(uid, permission, addedBy)
	if typeof(uid) == "string" then
		uid = tonumber(uid)
	end

	if not uid or uid <= 0 then
		return false, "Invalid UID"
	end

	permission = permission or "TESTER"
	if not Settings.ADMIN_PERMISSION_LEVELS[permission] then
		return false, "Invalid permission level"
	end

	-- Check if adder has permission
	if addedBy then
		local adderLevel = self:GetPermissionLevel(addedBy)
		local targetLevel = Settings.ADMIN_PERMISSION_LEVELS[permission]

		if adderLevel <= targetLevel then
			return false, "Insufficient permission to add this admin level"
		end
	end

	-- Use AdminConfigManager
	local success, message = AdminConfigManager:AddAdmin(uid, permission, addedBy)

	if success then
		-- Broadcast globally
		if Settings.ENABLE_GLOBAL_ADMIN_COMMANDS then
			self:BroadcastGlobalMessage("ADMIN_ADDED", {
				uid = uid,
				permission = permission,
				addedBy = addedBy and addedBy.UserId
			})
		end
	end

	return success, message
end

-- Add admin by username
function AdminManager:AddAdminByUsername(username, permission, addedBy)
	if not username or username == "" then
		return false, "Invalid username"
	end

	-- Get UID from username
	local success, uid = pcall(function()
		return Players:GetUserIdFromNameAsync(username)
	end)

	if not success or not uid then
		return false, "Username not found"
	end

	return self:AddAdminByUID(uid, permission, addedBy)
end

-- Remove admin (using AdminConfigManager)
function AdminManager:RemoveAdmin(targetPlayer, removedBy)
	if not targetPlayer then
		return false, "Player not found"
	end

	local uid = targetPlayer.UserId

	-- Check permissions
	if removedBy then
		local removerLevel = self:GetPermissionLevel(removedBy)
		local targetLevel = self:GetPermissionLevel(targetPlayer)

		if removerLevel <= targetLevel then
			return false, "Insufficient permission to remove this admin"
		end
	end

	-- Use AdminConfigManager
	local success, message = AdminConfigManager:RemoveAdmin(uid, removedBy)

	if success then
		-- Broadcast globally
		if Settings.ENABLE_GLOBAL_ADMIN_COMMANDS then
			self:BroadcastGlobalMessage("ADMIN_REMOVED", {
				uid = uid,
				removedBy = removedBy and removedBy.UserId
			})
		end
	end

	return success, message
end

-- Set admin permission level
function AdminManager:SetAdminPermission(targetName, newLevel, setter)
	if not targetName or not newLevel then
		return "Usage: SET_PERMISSION <username> <level>"
	end

	local targetPlayer = self:FindPlayerByName(targetName)
	if not targetPlayer then
		return "Player not found: " .. targetName
	end

	local targetUID = targetPlayer.UserId
	local setterLevel = self:GetPermissionLevel(setter)
	local targetLevel = self:GetPermissionLevel(targetPlayer)

	-- Check permissions
	if setterLevel <= targetLevel then
		return "Cannot modify permission of admin with equal or higher level"
	end

	-- Validate new level
	newLevel = newLevel:upper()
	if not Settings.ADMIN_PERMISSION_LEVELS[newLevel] then
		return "Invalid permission level. Valid levels: TESTER, HELPER, MODERATOR, DEVELOPER, OWNER"
	end

	local newLevelNum = Settings.ADMIN_PERMISSION_LEVELS[newLevel]
	if setterLevel <= newLevelNum then
		return "Cannot set permission level equal to or higher than your own"
	end

	-- Remove old admin and add with new permission
	local oldPermission = AdminConfigManager:GetPermission(targetUID)
	AdminConfigManager:RemoveAdmin(targetUID, setter)
	local success, message = AdminConfigManager:AddAdmin(targetUID, newLevel, setter)

	if success then
		-- Log command
		self:LogCommand(setter, "SET_PERMISSION", {targetName, newLevel}, 
			"Changed from " .. (oldPermission or "NONE") .. " to " .. newLevel)
		
		return "Permission updated: " .. targetName .. " -> " .. newLevel
	else
		return "Failed to update permission: " .. message
	end
end

-- ========================================
-- COMMAND PARSING & EXECUTION
-- ========================================

-- Parse command with multiple prefixes
function AdminManager:ParseCommand(input)
	if not input or input == "" then return nil end

	-- Supported prefixes
	local prefixes = {"/", "!", ";"}

	for _, prefix in ipairs(prefixes) do
		if input:sub(1, 1) == prefix then
			local commandText = input:sub(2):gsub("^%s+", "")
			local parts = {}
			for part in commandText:gmatch("%S+") do
				table.insert(parts, part)
			end

			if #parts > 0 then
				return parts[1]:upper(), {unpack(parts, 2)}
			end
		end
	end

	return nil
end

-- Execute admin command
function AdminManager:ExecuteCommand(player, command, args)
	if not self:IsAdmin(player) then
		return false, "You are not authorized to use admin commands"
	end

	local permissionLevel = self:GetPermissionLevel(player)
	command = command:upper()

	-- Command definitions with required permission levels
	local commands = {
		-- Level 1+ commands
		HELP = {level = 1, func = function() return self:GetHelpText(permissionLevel) end},
		CMD = {level = 1, func = function() return self:GetHelpText(permissionLevel) end},
		COMMANDS = {level = 1, func = function() return self:GetHelpText(permissionLevel) end},

		-- Level 2+ commands
		STATUS = {level = 2, func = function() return self:GetSystemStatus() end},
		LIST_ADMINS = {level = 2, func = function() return self:ListAdmins() end},
		ADMINLIST = {level = 2, func = function() return self:ListAdmins() end},
		ADMINS = {level = 2, func = function() return self:ListAdmins() end},
		SYSTEM_INFO = {level = 2, func = function() return self:GetDetailedSystemInfo() end},
		SYSINFO = {level = 2, func = function() return self:GetDetailedSystemInfo() end},
		PLAYER_LIST = {level = 2, func = function() return self:GetPlayerList() end},
		PLAYERS = {level = 2, func = function() return self:GetPlayerList() end},

		-- Level 3+ commands
		KICK_PLAYER = {level = 3, func = function(target) return self:KickPlayer(player, target) end},
		KICK = {level = 3, func = function(target) return self:KickPlayer(player, target) end},
		VIEW_PLAYER_DATA = {level = 3, func = function(target) return self:GetPlayerData(target) end},
		PLAYERDATA = {level = 3, func = function(target) return self:GetPlayerData(target) end},
		CHECKDATA = {level = 3, func = function(target) return self:GetPlayerData(target) end},
		LIST_BANS = {level = 3, func = function() return self:ListBans() end},
		BANS = {level = 3, func = function() return self:ListBans() end},
		TELEPORT_TO = {level = 3, func = function(target) return self:TeleportToPlayer(player, target) end},
		TPTO = {level = 3, func = function(target) return self:TeleportToPlayer(player, target) end},
		TELEPORT_HERE = {level = 3, func = function(target) return self:TeleportPlayerHere(player, target) end},
		TPH = {level = 3, func = function(target) return self:TeleportPlayerHere(player, target) end},
		FREEZE = {level = 3, func = function(target) return self:FreezePlayer(player, target) end},
		UNFREEZE = {level = 3, func = function(target) return self:UnfreezePlayer(player, target) end},
		MUTE = {level = 3, func = function(target) return self:MutePlayer(player, target) end},
		UNMUTE = {level = 3, func = function(target) return self:UnmutePlayer(player, target) end},

		-- Level 4+ commands
		RESET_PLAYER = {level = 4, func = function(target) return self:ResetPlayerData(target) end},
		RESET = {level = 4, func = function(target) return self:ResetPlayerData(target) end},
		GLOBAL_STATUS = {level = 4, func = function() return self:GetGlobalStatus() end},
		GLOBALSTATUS = {level = 4, func = function() return self:GetGlobalStatus() end},
		BAN_PLAYER = {level = 4, func = function(target, reason) return self:BanPlayer(player, target, reason) end},
		BAN = {level = 4, func = function(target, reason) return self:BanPlayer(player, target, reason) end},
		UNBAN_PLAYER = {level = 4, func = function(target) return self:UnbanPlayer(player, target) end},
		UNBAN = {level = 4, func = function(target) return self:UnbanPlayer(player, target) end},
		SERVER_MESSAGE = {level = 4, func = function(...) return self:SendServerMessage(player, table.concat({...}, " ")) end},
		SERVERMSG = {level = 4, func = function(...) return self:SendServerMessage(player, table.concat({...}, " ")) end},
		BROADCAST = {level = 4, func = function(...) return self:SendServerMessage(player, table.concat({...}, " ")) end},
		FORCE_SAVE = {level = 4, func = function(target) return self:ForceSavePlayerData(target) end},
		FORCESAVE = {level = 4, func = function(target) return self:ForceSavePlayerData(target) end},
		VIEW_LOGS = {level = 4, func = function(count) return self:GetCommandLogsText(count or 10) end},
		LOGS = {level = 4, func = function(count) return self:GetCommandLogsText(count or 10) end},

		-- Level 5 commands (Owner only)
		ADD_ADMIN_UID = {level = 5, func = function(uid, perm) return self:AddAdminByUID(uid, perm, player) end},
		ADDADMIN = {level = 5, func = function(uid, perm) return self:AddAdminByUID(uid, perm, player) end},
		ADD_ADMIN_USERNAME = {level = 5, func = function(username, perm) return self:AddAdminByUsername(username, perm, player) end},
		REMOVE_ADMIN = {level = 5, func = function(target) return self:RemoveAdminByName(target, player) end},
		REMOVEADMIN = {level = 5, func = function(target) return self:RemoveAdminByName(target, player) end},
		SET_PERMISSION = {level = 5, func = function(target, level) return self:SetAdminPermission(target, level, player) end},
		SETPERM = {level = 5, func = function(target, level) return self:SetAdminPermission(target, level, player) end},
		SHUTDOWN_SYSTEM = {level = 5, func = function() return self:ShutdownSystem(player) end},
		SHUTDOWN = {level = 5, func = function() return self:ShutdownSystem(player) end},
		CLEAR_LOGS = {level = 5, func = function() return self:ClearCommandLogs(player) end},
		CLEARLOGS = {level = 5, func = function() return self:ClearCommandLogs(player) end},
	}

	local cmdData = commands[command]
	if not cmdData then
		return false, "Unknown command: " .. command .. ". Type /help for available commands."
	end

	if permissionLevel < cmdData.level then
		return false, "Insufficient permission for command: " .. command
	end

	-- Execute command
	local success, result = pcall(cmdData.func, unpack(args or {}))

	if success then
		-- Log successful command
		self:LogCommand(player, command, args, result)
		return true, result
	else
		-- Log failed command
		self:LogCommand(player, command, args, "ERROR: " .. tostring(result))
		return false, "Command failed: " .. tostring(result)
	end
end

-- ========================================
-- COMMAND IMPLEMENTATIONS
-- ========================================

-- Get help text based on permission level
function AdminManager:GetHelpText(permissionLevel)
	local help = "=== Checkpoint System Admin Commands ===\n"
	help = help .. "Prefixes: / ! ;\n\n"

	if permissionLevel >= 1 then
		help = help .. "HELP/CMD/COMMANDS - Show this help message\n"
	end

	if permissionLevel >= 2 then
		help = help .. "STATUS - Show current server status\n"
		help = help .. "LIST_ADMINS/ADMINLIST/ADMINS - List all admins\n"
		help = help .. "SYSTEM_INFO/SYSINFO - Show detailed system info\n"
		help = help .. "PLAYER_LIST/PLAYERS - List online players\n"
	end

	if permissionLevel >= 3 then
		help = help .. "KICK_PLAYER/KICK <username> - Kick a player\n"
		help = help .. "VIEW_PLAYER_DATA/PLAYERDATA/CHECKDATA <username> - View player data\n"
		help = help .. "LIST_BANS/BANS - List banned players\n"
		help = help .. "TELEPORT_TO/TPTO <username> - Teleport to player\n"
		help = help .. "TELEPORT_HERE/TPH <username> - Teleport player to you\n"
		help = help .. "FREEZE/UNFREEZE <username> - Freeze/unfreeze player\n"
	end

	if permissionLevel >= 4 then
		help = help .. "RESET_PLAYER/RESET <username> - Reset player's progress\n"
		help = help .. "GLOBAL_STATUS/GLOBALSTATUS - Show global system status\n"
		help = help .. "BAN_PLAYER/BAN <username> [reason] - Ban a player\n"
		help = help .. "UNBAN_PLAYER/UNBAN <username> - Unban a player\n"
		help = help .. "SERVER_MESSAGE/SERVERMSG/BROADCAST <message> - Broadcast message\n"
		help = help .. "FORCE_SAVE/FORCESAVE <username> - Force save player data\n"
		help = help .. "VIEW_LOGS/LOGS [count] - View command logs\n"
	end

	if permissionLevel >= 5 then
		help = help .. "ADD_ADMIN_UID/ADDADMIN <uid> <permission> - Add admin by UID\n"
		help = help .. "ADD_ADMIN_USERNAME <username> <permission> - Add admin by username\n"
		help = help .. "REMOVE_ADMIN/REMOVEADMIN <username> - Remove admin\n"
		help = help .. "SET_PERMISSION/SETPERM <username> <level> - Change admin permission\n"
		help = help .. "SHUTDOWN_SYSTEM/SHUTDOWN - Emergency shutdown\n"
		help = help .. "CLEAR_LOGS/CLEARLOGS - Clear command logs\n"
	end

	help = help .. "\nPermission Levels: TESTER(1), HELPER(2), MODERATOR(3), DEVELOPER(4), OWNER(5)"
	return help
end

-- Get system status
function AdminManager:GetSystemStatus()
	local status = {
		ServerId = game.JobId:sub(1, 8),
		PlayerCount = #Players:GetPlayers(),
		MaxPlayers = Settings.MAX_PLAYERS,
		Uptime = workspace.DistributedGameTime,
		CheckpointCount = #CollectionService:GetTagged(Settings.CHECKPOINT_TAG),
		AdminCount = AdminConfigManager:GetAdminCount(),
		DataStoreStatus = "Unknown"
	}

	-- Test DataStore connectivity
	local success = pcall(function()
		DataHandler.LoadData("Test", "Test")
	end)
	status.DataStoreStatus = success and "Connected" or "Disconnected"

	return string.format(
		"Server Status:\n" ..
		"Players: %d/%d\n" ..
		"Checkpoints: %d\n" ..
		"Admins: %d\n" ..
		"DataStore: %s\n" ..
		"Uptime: %.1f minutes",
		status.PlayerCount, status.MaxPlayers,
		status.CheckpointCount, status.AdminCount,
		status.DataStoreStatus, status.Uptime / 60
	)
end

-- List all admins
function AdminManager:ListAdmins()
	local list = "Current Admins:\n"
	local admins = AdminConfigManager:GetAllAdmins()
	local count = 0

	for uid, permission in pairs(admins) do
		local success, username = pcall(function()
			return Players:GetNameFromUserIdAsync(uid)
		end)

		if success then
			list = list .. string.format("%s (%d) - %s\n", username, uid, permission)
			count = count + 1
		end
	end

	if count == 0 then
		list = list .. "No admins configured"
	end

	return list
end

-- Get detailed system info
function AdminManager:GetDetailedSystemInfo()
	local info = self:GetSystemStatus()

	info = info .. string.format("\n\nDetailed Info:\n" ..
		"Server Job ID: %s\n" ..
		"Place ID: %d\n" ..
		"Total Admin Commands: %d\n" ..
		"Last Admin Activity: %s\n" ..
		"Memory Usage: %.2f MB",
		game.JobId,
		game.PlaceId,
		self.AdminData.GlobalStats.TotalCommands or 0,
		self.AdminData.GlobalStats.LastActivity and 
			os.date("%Y-%m-%d %H:%M:%S", self.AdminData.GlobalStats.LastActivity) or "Never",
		gcinfo() / 1024
	)

	return info
end

-- Get player list
function AdminManager:GetPlayerList()
	local list = "Online Players:\n"
	local players = Players:GetPlayers()

	for i, player in ipairs(players) do
		local isAdmin, permission = self:IsAdmin(player)
		local adminTag = isAdmin and " [" .. permission .. "]" or ""
		local ping = player:GetNetworkPing() * 1000

		list = list .. string.format("%d. %s (ID: %d)%s - Ping: %.0fms\n",
			i, player.Name, player.UserId, adminTag, ping)
	end

	list = list .. "\nTotal Players: " .. #players
	return list
end

-- Kick player
function AdminManager:KickPlayer(admin, targetName)
	if not targetName then
		return "Usage: KICK_PLAYER <username>"
	end

	local targetPlayer = self:FindPlayerByName(targetName)
	if not targetPlayer then
		return "Player not found: " .. targetName
	end

	if targetPlayer == admin then
		return "Cannot kick yourself"
	end

	if self:GetPermissionLevel(targetPlayer) >= self:GetPermissionLevel(admin) then
		return "Cannot kick admin with equal or higher permission"
	end

	targetPlayer:Kick("Kicked by admin: " .. admin.Name)
	return "Player kicked: " .. targetName
end

-- Get player checkpoint data
function AdminManager:GetPlayerData(targetName)
	if not targetName then
		return "Usage: VIEW_PLAYER_DATA <username>"
	end

	local targetPlayer = self:FindPlayerByName(targetName)
	if not targetPlayer then
		return "Player not found: " .. targetName
	end

	local success, data = pcall(function()
		return DataHandler.LoadCheckpoint(targetPlayer.UserId)
	end)

	if not success or not data then
		return "No checkpoint data found for: " .. targetName
	end

	return string.format(
		"Player Data for %s:\n" ..
		"Current Checkpoint: %d\n" ..
		"Last Save: %s\n" ..
		"Death Count: %d\n" ..
		"Session Start: %s",
		targetName,
		data.checkpoint or 0,
		data.timestamp and os.date("%Y-%m-%d %H:%M:%S", data.timestamp) or "Never",
		data.deathCount or 0,
		data.sessionStartTime and os.date("%Y-%m-%d %H:%M:%S", data.sessionStartTime) or "Unknown"
	)
end

-- Reset player data
function AdminManager:ResetPlayerData(targetName)
	if not targetName then
		return "Usage: RESET_PLAYER <username>"
	end

	local targetPlayer = self:FindPlayerByName(targetName)
	if not targetPlayer then
		return "Player not found: " .. targetName
	end

	local success = pcall(function()
		DataHandler.SaveCheckpoint(targetPlayer.UserId, {
			checkpoint = 0,
			timestamp = os.time(),
			version = Settings.DATA_VERSION,
			deathCount = 0
		})
	end)

	if success then
		return "Player data reset: " .. targetName
	else
		return "Failed to reset data for: " .. targetName
	end
end

-- Ban player
function AdminManager:BanPlayer(admin, targetName, reason)
	if not targetName then
		return "Usage: BAN_PLAYER <username> [reason]"
	end

	local targetPlayer = self:FindPlayerByName(targetName)
	if not targetPlayer then
		return "Player not found: " .. targetName
	end

	if self:GetPermissionLevel(targetPlayer) >= self:GetPermissionLevel(admin) then
		return "Cannot ban admin with equal or higher permission"
	end

	if not self.AdminData.BannedPlayers then
		self.AdminData.BannedPlayers = {}
	end

	self.AdminData.BannedPlayers[targetPlayer.UserId] = {
		username = targetPlayer.Name,
		bannedBy = admin.UserId,
		reason = reason or "No reason provided",
		timestamp = os.time()
	}

	self:SaveLegacyData()

	targetPlayer:Kick("You have been banned. Reason: " .. (reason or "No reason provided"))
	self:LogCommand(admin, "BAN_PLAYER", {targetName, reason})

	return "Player banned: " .. targetName
end

-- Unban player
function AdminManager:UnbanPlayer(admin, targetName)
	if not targetName then
		return "Usage: UNBAN_PLAYER <username>"
	end

	if not self.AdminData.BannedPlayers then
		return "No players are currently banned"
	end

	for uid, banData in pairs(self.AdminData.BannedPlayers) do
		if banData.username:lower() == targetName:lower() then
			self.AdminData.BannedPlayers[uid] = nil
			self:SaveLegacyData()
			self:LogCommand(admin, "UNBAN_PLAYER", {targetName})
			return "Player unbanned: " .. targetName
		end
	end

	return "Player not found in ban list: " .. targetName
end

-- List banned players
function AdminManager:ListBans()
	if not self.AdminData.BannedPlayers then
		return "No players are currently banned"
	end

	local list = "Banned Players:\n"
	local count = 0

	for uid, banData in pairs(self.AdminData.BannedPlayers) do
		local bannedByName = "Unknown"
		pcall(function()
			bannedByName = Players:GetNameFromUserIdAsync(banData.bannedBy)
		end)

		list = list .. string.format("%s (%d) - By: %s, Reason: %s\n",
			banData.username, uid, bannedByName, banData.reason)
		count = count + 1
	end

	if count == 0 then
		list = "No players are currently banned"
	end

	return list
end

-- Teleport to player
function AdminManager:TeleportToPlayer(admin, targetName)
	if not targetName then
		return "Usage: TELEPORT_TO <username>"
	end

	local targetPlayer = self:FindPlayerByName(targetName)
	if not targetPlayer then
		return "Player not found: " .. targetName
	end

	local adminCharacter = admin.Character
	local targetCharacter = targetPlayer.Character

	if not adminCharacter or not targetCharacter then
		return "Character not found"
	end

	local targetHRP = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not targetHRP then
		return "Target player has no HumanoidRootPart"
	end

	local adminHRP = adminCharacter:FindFirstChild("HumanoidRootPart")
	if adminHRP then
		adminHRP.CFrame = targetHRP.CFrame
	end

	self:LogCommand(admin, "TELEPORT_TO", {targetName})
	return "Teleported to: " .. targetName
end

-- Teleport player here
function AdminManager:TeleportPlayerHere(admin, targetName)
	if not targetName then
		return "Usage: TELEPORT_HERE <username>"
	end

	local targetPlayer = self:FindPlayerByName(targetName)
	if not targetPlayer then
		return "Player not found: " .. targetName
	end

	if self:GetPermissionLevel(targetPlayer) >= self:GetPermissionLevel(admin) then
		return "Cannot teleport admin with equal or higher permission"
	end

	local adminCharacter = admin.Character
	local targetCharacter = targetPlayer.Character

	if not adminCharacter or not targetCharacter then
		return "Character not found"
	end

	local adminHRP = adminCharacter:FindFirstChild("HumanoidRootPart")
	if not adminHRP then
		return "Admin has no HumanoidRootPart"
	end

	local targetHRP = targetCharacter:FindFirstChild("HumanoidRootPart")
	if targetHRP then
		targetHRP.CFrame = adminHRP.CFrame
	end

	self:LogCommand(admin, "TELEPORT_HERE", {targetName})
	return "Teleported " .. targetName .. " to your location"
end

-- Freeze player
function AdminManager:FreezePlayer(admin, targetName)
	if not targetName then
		return "Usage: FREEZE <username>"
	end

	local targetPlayer = self:FindPlayerByName(targetName)
	if not targetPlayer then
		return "Player not found: " .. targetName
	end

	if self:GetPermissionLevel(targetPlayer) >= self:GetPermissionLevel(admin) then
		return "Cannot freeze admin with equal or higher permission"
	end

	local targetCharacter = targetPlayer.Character
	if not targetCharacter then
		return "Target character not found"
	end

	local humanoid = targetCharacter:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end

	for _, part in ipairs(targetCharacter:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end

	self:LogCommand(admin, "FREEZE", {targetName})
	return "Player frozen: " .. targetName
end

-- Unfreeze player
function AdminManager:UnfreezePlayer(admin, targetName)
	if not targetName then
		return "Usage: UNFREEZE <username>"
	end

	local targetPlayer = self:FindPlayerByName(targetName)
	if not targetPlayer then
		return "Player not found: " .. targetName
	end

	local targetCharacter = targetPlayer.Character
	if not targetCharacter then
		return "Target character not found"
	end

	local humanoid = targetCharacter:FindFirstChild("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
	end

	for _, part in ipairs(targetCharacter:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			part.Anchored = false
		end
	end

	self:LogCommand(admin, "UNFREEZE", {targetName})
	return "Player unfrozen: " .. targetName
end

-- Mute player (placeholder)
function AdminManager:MutePlayer(admin, targetName)
	if not targetName then
		return "Usage: MUTE <username>"
	end

	local targetPlayer = self:FindPlayerByName(targetName)
	if not targetPlayer then
		return "Player not found: " .. targetName
	end

	if self:GetPermissionLevel(targetPlayer) >= self:GetPermissionLevel(admin) then
		return "Cannot mute admin with equal or higher permission"
	end

	self:LogCommand(admin, "MUTE", {targetName})
	return "Mute functionality requires chat system integration"
end

-- Unmute player (placeholder)
function AdminManager:UnmutePlayer(admin, targetName)
	if not targetName then
		return "Usage: UNMUTE <username>"
	end

	local targetPlayer = self:FindPlayerByName(targetName)
	if not targetPlayer then
		return "Player not found: " .. targetName
	end

	self:LogCommand(admin, "UNMUTE", {targetName})
	return "Unmute functionality requires chat system integration"
end

-- Send server message
function AdminManager:SendServerMessage(admin, message)
	if not message or message == "" then
		return "Usage: SERVER_MESSAGE <message>"
	end

	-- Send to all players using RemoteEvent (more reliable than SetCore)
	local messageEvent = game.ReplicatedStorage.CheckpointSystem.Remotes:FindFirstChild("ServerMessage")
	if messageEvent then
		messageEvent:FireAllClients("[ADMIN] " .. message)
	else
		-- Fallback: try StarterGui method
		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(function()
				pcall(function()
					local remoteEvent = Instance.new("RemoteEvent")
					remoteEvent.Name = "AdminMessage"
					remoteEvent.Parent = game.ReplicatedStorage.CheckpointSystem.Remotes
					remoteEvent:FireClient(player, message)
				end)
			end)
		end
	end

	self:LogCommand(admin, "SERVER_MESSAGE", {message})
	return "Server message sent: " .. message
end

-- Force save player data
function AdminManager:ForceSavePlayerData(targetName)
	if not targetName then
		return "Usage: FORCE_SAVE <username>"
	end

	local targetPlayer = self:FindPlayerByName(targetName)
	if not targetPlayer then
		return "Player not found: " .. targetName
	end

	-- Use global ServerMain function
	if _G.CheckpointServerMain and _G.CheckpointServerMain.ForceSavePlayerData then
		local success = _G.CheckpointServerMain.ForceSavePlayerData(targetPlayer.UserId)
		if success then
			return "Data force-saved for: " .. targetName
		else
			return "Failed to force-save data for: " .. targetName
		end
	else
		return "ServerMain not available for force save"
	end
end

-- Get command logs as text
function AdminManager:GetCommandLogsText(count)
	count = tonumber(count) or 10
	
	if #self.AdminData.CommandLogs == 0 then
		return "No command logs available"
	end

	local list = "Recent Admin Commands:\n"
	for i = 1, math.min(count, #self.AdminData.CommandLogs) do
		local log = self.AdminData.CommandLogs[i]
		list = list .. string.format("%d. [%s] %s: %s\n",
			i,
			os.date("%H:%M:%S", log.timestamp),
			log.adminName,
			log.command
		)
	end

	return list
end

-- Clear command logs
function AdminManager:ClearCommandLogs(admin)
	local oldCount = #self.AdminData.CommandLogs
	self.AdminData.CommandLogs = {}
	self:SaveLegacyData()

	self:LogCommand(admin, "CLEAR_LOGS", {}, "Cleared " .. oldCount .. " log entries")
	return "Command logs cleared. " .. oldCount .. " entries removed."
end

-- Get global status across servers
function AdminManager:GetGlobalStatus()
	if not Settings.ENABLE_GLOBAL_ADMIN_COMMANDS then
		return "Global commands disabled"
	end

	self:BroadcastGlobalMessage("REQUEST_STATUS", {
		requestingServer = game.JobId,
		timestamp = os.time()
	})

	return "Global status request sent. Check server logs for responses."
end

-- Shutdown system (emergency)
function AdminManager:ShutdownSystem(admin)
	warn("[AdminManager] SYSTEM SHUTDOWN initiated by:", admin.Name)

	Settings.ENABLE_ADMIN_SYSTEM = false
	Settings.ENABLE_BACKUP_DATASTORE = false
	Settings.ENABLE_MIGRATION_SYSTEM = false

	self:BroadcastGlobalMessage("SYSTEM_SHUTDOWN", {
		initiatedBy = admin.UserId,
		timestamp = os.time()
	})

	return "SYSTEM SHUTDOWN initiated. All checkpoint features disabled."
end

-- Remove admin by name (wrapper for RemoveAdmin)
function AdminManager:RemoveAdminByName(targetName, removedBy)
	if not targetName then
		return "Usage: REMOVE_ADMIN <username>"
	end

	local targetPlayer = self:FindPlayerByName(targetName)
	if not targetPlayer then
		-- Try to find by UID in admin list
		local admins = AdminConfigManager:GetAllAdmins()
		for uid, permission in pairs(admins) do
			local success, username = pcall(function()
				return Players:GetNameFromUserIdAsync(uid)
			end)
			
			if success and username:lower() == targetName:lower() then
				-- Create mock player object
				local mockPlayer = {UserId = uid, Name = username}
				return self:RemoveAdmin(mockPlayer, removedBy)
			end
		end
		
		return "Player/Admin not found: " .. targetName
	end

	return self:RemoveAdmin(targetPlayer, removedBy)
end

-- ========================================
-- UTILITY FUNCTIONS
-- ========================================

-- Find player by name
function AdminManager:FindPlayerByName(name)
	if not name then return nil end
	name = name:lower()

	for _, player in ipairs(Players:GetPlayers()) do
		if player.Name:lower() == name or player.Name:lower():find(name) then
			return player
		end
	end

	return nil
end

-- Log admin command
function AdminManager:LogCommand(admin, command, args, result)
	local logEntry = {
		timestamp = os.time(),
		adminUID = admin and admin.UserId or 0,
		adminName = admin and admin.Name or "SYSTEM",
		command = command,
		args = args or {},
		result = result or "",
		serverId = game.JobId
	}

	table.insert(self.AdminData.CommandLogs, 1, logEntry)

	-- Trim log if too long
	if #self.AdminData.CommandLogs > Settings.ADMIN_LOG_RETENTION then
		table.remove(self.AdminData.CommandLogs)
	end

	-- Update stats
	self.AdminData.GlobalStats.TotalCommands = (self.AdminData.GlobalStats.TotalCommands or 0) + 1
	self.AdminData.GlobalStats.LastActivity = os.time()

	-- Save periodically
	if #self.AdminData.CommandLogs % 10 == 0 then
		self:SaveLegacyData()
	end

	if Settings.DEBUG_MODE then
		print(string.format("[AdminManager] Command: %s by %s - %s",
			command, logEntry.adminName, result or "Success"))
	end
end

-- ========================================
-- GLOBAL MESSAGING
-- ========================================

-- Broadcast global message (using GlobalMessenger)
function AdminManager:BroadcastGlobalMessage(messageType, data)
	if not Settings.ENABLE_GLOBAL_ADMIN_COMMANDS then return end

	data.type = messageType
	data.serverId = game.JobId
	data.timestamp = os.time()

	-- High priority for admin commands
	local priority = 5

	GlobalMessenger:QueueMessage(Settings.GLOBAL_MESSAGE_TOPIC, data, priority)
end

-- Handle global messages
function AdminManager:HandleGlobalMessage(message)
	local data = message.Data

	if data.type == "ADMIN_ADDED" then
		-- Refresh cache to get updated admin list
		AdminConfigManager:RefreshCache()
		
		if Settings.DEBUG_MODE then
			print("[AdminManager] Admin added globally:", data.uid, data.permission)
		end

	elseif data.type == "ADMIN_REMOVED" then
		-- Refresh cache to get updated admin list
		AdminConfigManager:RefreshCache()
		
		if Settings.DEBUG_MODE then
			print("[AdminManager] Admin removed globally:", data.uid)
		end

	elseif data.type == "SYSTEM_SHUTDOWN" then
		Settings.ENABLE_ADMIN_SYSTEM = false
		warn("[AdminManager] System shutdown received from server:", data.initiatedBy)
	end
end

-- Handle status requests
function AdminManager:HandleStatusRequest(message)
	local data = message.Data

	if data.type == "REQUEST_STATUS" then
		local status = self:GetSystemStatus()
		
		GlobalMessenger:QueueMessage(Settings.GLOBAL_STATUS_TOPIC, {
			type = "STATUS_RESPONSE",
			serverId = game.JobId,
			status = status,
			timestamp = os.time()
		}, 3)
	elseif data.type == "STATUS_RESPONSE" then
		if Settings.DEBUG_MODE then
			print("[AdminManager] Global status response from:", data.serverId)
			print(data.status)
		end
	end
end

-- Handle data requests
function AdminManager:HandleDataRequest(message)
	local data = message.Data

	if data.type == "PLAYER_DATA_REQUEST" then
		if Settings.DEBUG_MODE then
			print("[AdminManager] Cross-server data request received")
		end
	end
end

-- ========================================
-- EXTERNAL API SETUP (Optional)
-- ========================================

-- Setup external API (placeholder)
function AdminManager:SetupAPI()
	if not Settings.ENABLE_EXTERNAL_API or Settings.API_ENDPOINT_URL == "" then
		return
	end

	warn("[AdminManager] External API setup not implemented in V1.0")
end

-- ========================================
-- EXPORTS
-- ========================================

return AdminManager
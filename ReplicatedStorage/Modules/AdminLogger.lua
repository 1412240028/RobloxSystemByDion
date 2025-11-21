-- AdminLogger.lua
-- Audit logging system for admin actions
-- Provides comprehensive logging with DataStore persistence and rotation

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.Config)

local AdminLogger = {}

-- Check if running on server (DataStore is server-only)
local isServer = game:GetService("RunService"):IsServer()

-- Private variables (only initialize on server)
local logDataStore
if isServer then
	local DataStoreService = game:GetService("DataStoreService")
	logDataStore = DataStoreService:GetDataStore("AdminLogs_v1")
end
local logCache = {} -- {timestamp = {action, player, target, details}}
local logDirty = false
local logRetention = Config.ADMIN_LOG_RETENTION or 100

-- Log levels
AdminLogger.Levels = {
	INFO = "INFO",
	WARN = "WARN",
	ERROR = "ERROR",
	SECURITY = "SECURITY"
}

-- Log an admin action
function AdminLogger:Log(level, action, player, target, details)
	if not Config.DEBUG_MODE and level == AdminLogger.Levels.INFO then return end

	local logEntry = {
		timestamp = tick(),
		level = level,
		action = action,
		playerId = player and player.UserId or nil,
		playerName = player and player.Name or "SYSTEM",
		targetId = target and target.UserId or nil,
		targetName = target and target.Name or nil,
		details = details or {},
		serverId = game.JobId
	}

	-- Add to cache
	table.insert(logCache, logEntry)

	-- Maintain retention limit
	while #logCache > logRetention do
		table.remove(logCache, 1)
	end

	logDirty = true

	-- Immediate console logging
	local prefix = string.format("[AdminLogger:%s]", level)
	local message = string.format("%s %s by %s", action, target and target.Name or "", player and player.Name or "SYSTEM")
	if details and next(details) then
		message = message .. " (" .. table.concat(details, ", ") .. ")"
	end

	if level == AdminLogger.Levels.ERROR then
		warn(prefix .. " " .. message)
	elseif level == AdminLogger.Levels.WARN or level == AdminLogger.Levels.SECURITY then
		warn(prefix .. " " .. message)
	else
		print(prefix .. " " .. message)
	end

	-- Auto-save if critical
	if level == AdminLogger.Levels.SECURITY or level == AdminLogger.Levels.ERROR then
		self:SaveLogs()
	end
end

-- Convenience methods for common actions
function AdminLogger:LogAdminAdded(addedBy, newAdmin, permission)
	self:Log(AdminLogger.Levels.SECURITY, "ADMIN_ADDED", addedBy, newAdmin, {
		permission = permission,
		level = Config.ADMIN_PERMISSION_LEVELS[permission] or 1
	})
end

function AdminLogger:LogAdminRemoved(removedBy, targetAdmin, oldPermission)
	self:Log(AdminLogger.Levels.SECURITY, "ADMIN_REMOVED", removedBy, targetAdmin, {
		oldPermission = oldPermission
	})
end

function AdminLogger:LogCommandExecuted(player, command, args, success, result)
	local level = success and AdminLogger.Levels.INFO or AdminLogger.Levels.WARN
	self:Log(level, "COMMAND_EXECUTED", player, nil, {
		command = command,
		args = table.concat(args or {}, " "),
		success = success,
		result = typeof(result) == "string" and result or "complex_result"
	})
end

function AdminLogger:LogPermissionDenied(player, command, reason)
	self:Log(AdminLogger.Levels.SECURITY, "PERMISSION_DENIED", player, nil, {
		command = command,
		reason = reason
	})
end

function AdminLogger:LogRateLimitHit(player, command)
	self:Log(AdminLogger.Levels.WARN, "RATE_LIMIT_HIT", player, nil, {
		command = command
	})
end

function AdminLogger:LogCheckpointModified(player, targetPlayer, action, checkpointId)
	self:Log(AdminLogger.Levels.INFO, "CHECKPOINT_MODIFIED", player, targetPlayer, {
		action = action,
		checkpointId = checkpointId
	})
end

function AdminLogger:LogRaceControl(player, action, details)
	self:Log(AdminLogger.Levels.INFO, "RACE_CONTROL", player, nil, {
		action = action,
		details = details
	})
end

-- Load logs from DataStore
function AdminLogger:LoadLogs()
	local success, loadedData = pcall(function()
		return logDataStore:GetAsync("Logs")
	end)

	if success and loadedData then
		logCache = loadedData
		-- Filter out old entries
		local cutoffTime = tick() - (7 * 24 * 60 * 60) -- 7 days
		local filteredLogs = {}
		for _, entry in ipairs(logCache) do
			if entry.timestamp > cutoffTime then
				table.insert(filteredLogs, entry)
			end
		end
		logCache = filteredLogs

		print(string.format("[AdminLogger] Loaded %d log entries", #logCache))
	else
		logCache = {}
		warn("[AdminLogger] Failed to load logs, starting fresh")
	end
end

-- Save logs to DataStore
function AdminLogger:SaveLogs()
	if not logDirty then return true end

	local success, errorMessage = pcall(function()
		logDataStore:SetAsync("Logs", logCache)
	end)

	if success then
		logDirty = false
		print("[AdminLogger] Logs saved successfully")
		return true
	else
		warn(string.format("[AdminLogger] Failed to save logs: %s", errorMessage))
		return false
	end
end

-- Get recent logs (for admin viewing)
function AdminLogger:GetRecentLogs(count, levelFilter)
	count = count or 50
	local filteredLogs = {}

	-- Iterate backwards for most recent first
	for i = #logCache, 1, -1 do
		local entry = logCache[i]
		if not levelFilter or entry.level == levelFilter then
			table.insert(filteredLogs, entry)
			if #filteredLogs >= count then break end
		end
	end

	return filteredLogs
end

-- Get logs for specific player
function AdminLogger:GetPlayerLogs(playerId, count)
	count = count or 20
	local playerLogs = {}

	for i = #logCache, 1, -1 do
		local entry = logCache[i]
		if entry.playerId == playerId or entry.targetId == playerId then
			table.insert(playerLogs, entry)
			if #playerLogs >= count then break end
		end
	end

	return playerLogs
end

-- Search logs by criteria
function AdminLogger:SearchLogs(criteria)
	local results = {}
	criteria = criteria or {}

	for _, entry in ipairs(logCache) do
		local matches = true

		if criteria.level and entry.level ~= criteria.level then
			matches = false
		end

		if criteria.action and entry.action ~= criteria.action then
			matches = false
		end

		if criteria.playerId and entry.playerId ~= criteria.playerId and entry.targetId ~= criteria.playerId then
			matches = false
		end

		if criteria.timeStart and entry.timestamp < criteria.timeStart then
			matches = false
		end

		if criteria.timeEnd and entry.timestamp > criteria.timeEnd then
			matches = false
		end

		if matches then
			table.insert(results, entry)
		end
	end

	return results
end

-- Get log statistics
function AdminLogger:GetStats()
	local stats = {
		totalLogs = #logCache,
		levels = {},
		actions = {},
		recentActivity = {}
	}

	-- Count by level and action
	for _, entry in ipairs(logCache) do
		stats.levels[entry.level] = (stats.levels[entry.level] or 0) + 1
		stats.actions[entry.action] = (stats.actions[entry.action] or 0) + 1
	end

	-- Recent activity (last 24 hours)
	local dayAgo = tick() - (24 * 60 * 60)
	for i = #logCache, 1, -1 do
		local entry = logCache[i]
		if entry.timestamp > dayAgo then
			table.insert(stats.recentActivity, entry)
		else
			break
		end
	end

	return stats
end

-- Clear old logs (cleanup)
function AdminLogger:CleanupOldLogs(daysOld)
	daysOld = daysOld or 30
	local cutoffTime = tick() - (daysOld * 24 * 60 * 60)

	local originalCount = #logCache
	local newLogs = {}

	for _, entry in ipairs(logCache) do
		if entry.timestamp > cutoffTime then
			table.insert(newLogs, entry)
		end
	end

	logCache = newLogs
	logDirty = true

	local removed = originalCount - #logCache
	if removed > 0 then
		print(string.format("[AdminLogger] Cleaned up %d old log entries", removed))
	end

	return removed
end

-- Initialize logger
function AdminLogger:Init()
	self:LoadLogs()

	-- Auto-save every 5 minutes
	task.spawn(function()
		while true do
			task.wait(300) -- 5 minutes
			self:SaveLogs()
		end
	end)

	-- Cleanup old logs weekly
	task.spawn(function()
		while true do
			task.wait(7 * 24 * 60 * 60) -- 7 days
			self:CleanupOldLogs(30)
			self:SaveLogs()
		end
	end)

	print("[AdminLogger] Initialized with " .. #logCache .. " log entries")
end

return AdminLogger

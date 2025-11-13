-- ReplicatedStorage/CheckpointSystem/Modules/AdminConfigManager.lua
-- Secure Admin Configuration Manager with DataStore Backend

local DataStoreService = game:GetService("DataStoreService")
local Settings = require(game.ReplicatedStorage.CheckpointSystem.Config.Settings)

local AdminConfigManager = {}

-- Secure DataStore for admin config
local ADMIN_CONFIG_STORE = "SecureAdminConfig_v1"
local ADMIN_BACKUP_STORE = "SecureAdminBackup_v1"
local AUDIT_LOG_STORE = "AdminAuditLog_v1"

-- Cache
local adminConfigCache = nil
local lastCacheUpdate = 0
local CACHE_TTL = 300 -- 5 minutes

-- Logger
local function Log(level, message, ...)
	if not Settings.DEBUG_MODE and level == "DEBUG" then return end
	local prefix = "[AdminConfigManager]"
	if level == "ERROR" or level == "WARN" then
		warn(prefix .. " " .. string.format(message, ...))
	else
		print(prefix .. " " .. string.format(message, ...))
	end
end

-- Initialize with migration from Settings.lua
function AdminConfigManager:Init()
	Log("INFO", "Initializing secure admin config...")
	
	-- Try load from DataStore
	local success, config = self:LoadConfig()
	
	if not success or not config or not config.admins then
		Log("WARN", "No config in DataStore, migrating from Settings.lua")
		config = self:MigrateFromSettings()
		self:SaveConfig(config)
	end
	
	adminConfigCache = config
	lastCacheUpdate = tick()
	
	Log("INFO", "Initialized with %d admins", self:GetAdminCount())
end

-- Load config from DataStore with backup fallback
function AdminConfigManager:LoadConfig()
	local primaryStore = DataStoreService:GetDataStore(ADMIN_CONFIG_STORE)
	
	-- Try primary
	local success, data = pcall(function()
		return primaryStore:GetAsync("AdminList")
	end)
	
	if success and data then
		Log("DEBUG", "Loaded from primary store")
		return true, data
	end
	
	-- Try backup
	Log("WARN", "Primary store failed, trying backup")
	local backupStore = DataStoreService:GetDataStore(ADMIN_BACKUP_STORE)
	success, data = pcall(function()
		return backupStore:GetAsync("AdminList")
	end)
	
	if success and data then
		Log("INFO", "Loaded from backup store")
		return true, data
	end
	
	Log("ERROR", "Failed to load from both stores")
	return false, nil
end

-- Save config to both stores
function AdminConfigManager:SaveConfig(config)
	config.lastModified = os.time()
	config.version = config.version or 1
	
	local primarySuccess = false
	local backupSuccess = false
	
	-- Save to primary
	local primaryStore = DataStoreService:GetDataStore(ADMIN_CONFIG_STORE)
	primarySuccess = pcall(function()
		primaryStore:SetAsync("AdminList", config)
	end)
	
	-- Save to backup
	local backupStore = DataStoreService:GetDataStore(ADMIN_BACKUP_STORE)
	backupSuccess = pcall(function()
		backupStore:SetAsync("AdminList", config)
	end)
	
	if primarySuccess or backupSuccess then
		adminConfigCache = config
		lastCacheUpdate = tick()
		Log("INFO", "Config saved (primary: %s, backup: %s)", 
			primarySuccess and "OK" or "FAIL",
			backupSuccess and "OK" or "FAIL")
		return true
	end
	
	Log("ERROR", "Failed to save admin config to any store")
	return false
end

-- Migrate from Settings.lua (one-time)
function AdminConfigManager:MigrateFromSettings()
	local config = {
		admins = {},
		version = 1,
		createdAt = os.time(),
		lastModified = os.time()
	}
	
	-- Copy from Settings.ADMIN_UIDS
	for uid, permission in pairs(Settings.ADMIN_UIDS or {}) do
		config.admins[uid] = permission
	end
	
	Log("INFO", "Migrated %d admins from Settings.lua", self:CountAdmins(config.admins))
	return config
end

-- Helper: count admins
function AdminConfigManager:CountAdmins(adminTable)
	local count = 0
	for _ in pairs(adminTable) do
		count = count + 1
	end
	return count
end

-- Get cached config (with TTL refresh)
function AdminConfigManager:GetConfig()
	if tick() - lastCacheUpdate > CACHE_TTL then
		Log("DEBUG", "Cache expired, refreshing")
		self:Init()
	end
	return adminConfigCache
end

-- Add admin at runtime
function AdminConfigManager:AddAdmin(userId, permission, addedBy)
	local config = self:GetConfig()
	
	-- Validation
	if config.admins[userId] then
		return false, "Admin already exists"
	end
	
	if not Settings.ADMIN_PERMISSION_LEVELS[permission] then
		return false, "Invalid permission level"
	end
	
	-- Add admin
	config.admins[userId] = permission
	
	-- Save
	if self:SaveConfig(config) then
		-- Log audit trail
		self:LogAdminAction(addedBy, "ADD_ADMIN", {
			userId = userId,
			permission = permission
		})
		
		return true, "Admin added successfully"
	end
	
	return false, "Failed to save admin config"
end

-- Remove admin at runtime
function AdminConfigManager:RemoveAdmin(userId, removedBy)
	local config = self:GetConfig()
	
	if not config.admins[userId] then
		return false, "Admin not found"
	end
	
	local oldPermission = config.admins[userId]
	config.admins[userId] = nil
	
	if self:SaveConfig(config) then
		self:LogAdminAction(removedBy, "REMOVE_ADMIN", {
			userId = userId,
			oldPermission = oldPermission
		})
		
		return true, "Admin removed successfully"
	end
	
	return false, "Failed to save admin config"
end

-- Audit trail logging
function AdminConfigManager:LogAdminAction(actor, action, data)
	local auditStore = DataStoreService:GetDataStore(AUDIT_LOG_STORE)
	
	local logEntry = {
		timestamp = os.time(),
		actorUserId = actor and actor.UserId or 0,
		actorName = actor and actor.Name or "SYSTEM",
		action = action,
		data = data,
		serverId = game.JobId
	}
	
	pcall(function()
		local logs = auditStore:GetAsync("AuditLog") or {}
		table.insert(logs, 1, logEntry)
		
		-- Keep last 1000 entries
		while #logs > 1000 do
			table.remove(logs)
		end
		
		auditStore:SetAsync("AuditLog", logs)
	end)
	
	Log("INFO", "Audit: %s by %s", action, logEntry.actorName)
end

-- Get admin count
function AdminConfigManager:GetAdminCount()
	local config = self:GetConfig()
	return self:CountAdmins(config.admins)
end

-- Check if user is admin
function AdminConfigManager:IsAdmin(userId)
	local config = self:GetConfig()
	return config.admins[userId] ~= nil
end

-- Get admin permission
function AdminConfigManager:GetPermission(userId)
	local config = self:GetConfig()
	return config.admins[userId]
end

-- Get all admins (for listing)
function AdminConfigManager:GetAllAdmins()
	local config = self:GetConfig()
	return config.admins
end

-- Force cache refresh
function AdminConfigManager:RefreshCache()
	lastCacheUpdate = 0
	self:Init()
end

return AdminConfigManager
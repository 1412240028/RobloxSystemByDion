-- AdminConfig.lua
-- Server-side admin configuration (security sensitive)
-- This file is server-only and not replicated to clients

local AdminConfig = {
	-- Admin System Settings
	ENABLE_ADMIN_SYSTEM = true,
	ADMIN_PERMISSION_LEVELS = {
		OWNER = 5,
		DEVELOPER = 4,
		MODERATOR = 3,
		HELPER = 2,
		MEMBER = 1,
		TESTER = 1
	},

	-- Admin User IDs (MOVED FROM CLIENT-SIDE CONFIG FOR SECURITY)
	-- ⚠️  SECURITY: These UIDs are now server-only to prevent client-side exposure
	ADMIN_UIDS = {
		-- Format: [UserID] = "PERMISSION_LEVEL"
		-- Example:
		[8806688001] = "OWNER",
		[9653762582] = "DEVELOPER"

	},

	-- Admin Commands Settings
	ADMIN_COMMAND_COOLDOWN = 1, -- seconds
	ADMIN_LOG_RETENTION = 100, -- max log entries
	ADMIN_GLOBAL_DATASTORE = "AdminData_v1",

	-- Global Communication Settings
	ENABLE_GLOBAL_ADMIN_COMMANDS = true,
	GLOBAL_MESSAGE_TOPIC = "AdminCommands",
	GLOBAL_STATUS_TOPIC = "AdminSystemStatus",
	GLOBAL_DATA_REQUEST_TOPIC = "AdminGlobalData",
}

return AdminConfig

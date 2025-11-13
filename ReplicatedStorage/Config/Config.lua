-- Config.lua
-- Consolidated configuration for all systems
-- Single source of truth for sprint, checkpoint, and unified settings

local Config = {
	-- System Version
	VERSION = "1.0.0",
	DATA_VERSION = 1,

	-- Performance Settings
	TARGET_FPS = 60,
	MAX_PLAYERS = 40,
	TOUCH_RESPONSE_TIME_MS = 100,
	SAVE_TIME_MS = 500,

	-- Speed Settings
	NORMAL_SPEED = 16,
	SPRINT_SPEED = 28,

	-- Validation
	MAX_ALLOWED_SPEED = 30,
	SPEED_TOLERANCE = 2,

	-- Timing
	DEBOUNCE_TIME = 0.2,
	SYNC_DELAY = 0.5,

	-- Rate Limiting
	MAX_TOGGLES_PER_SECOND = 5,

	-- UI Config
	BUTTON_SIZE_PC = UDim2.new(0, 40, 0, 60),
	BUTTON_SIZE_MOBILE = UDim2.new(0, 60, 0, 60),
	BUTTON_POSITION_PC = UDim2.new(0, 30, 0.5, -30),
	BUTTON_POSITION_MOBILE = UDim2.new(0, 20, 0, 150),
	BUTTON_COLOR_OFF = Color3.fromRGB(255, 50, 50),
	BUTTON_COLOR_ON = Color3.fromRGB(50, 150, 255),
	BUTTON_CORNER_RADIUS = UDim.new(0, 8),
	BUTTON_STROKE_THICKNESS = 2,

	-- Animations
	PRESS_SCALE = 0.9,
	PRESS_DURATION = 0.1,
	RELEASE_DURATION = 0.15,
	STATE_CHANGE_DURATION = 0.2,

	-- Data Persistence
	DATASTORE_KEY_PREFIX = "Player_",
	DATASTORE_NAME = "UnifiedCheckpointSprint_v1",
	SAVE_RETRY_ATTEMPTS = 3,
	SAVE_RETRY_DELAY_BASE = 2,
	SAVE_THROTTLE_SECONDS = 10,
	AUTO_SAVE_INTERVAL_SECONDS = 60,
	QUEUE_PROCESS_INTERVAL = 30,
	MAX_QUEUE_SIZE = 100,

	-- Anti-Cheat
	HEARTBEAT_CHECK_INTERVAL = 0.5,
	SPEED_CHECK_TOLERANCE = 2,

	-- Platform Detection
	IS_MOBILE = false, -- Will be set dynamically
	IS_PC = true, -- Will be set dynamically

	-- Default Keybind
	DEFAULT_KEYBIND = Enum.KeyCode.LeftShift,

	-- Error Messages
	ERROR_REQUEST_FAILED = "Request failed!",
	ERROR_CHARACTER_NOT_FOUND = "Character not found",

	-- Logging
	LOG_LEVEL = "INFO", -- DEBUG, INFO, WARN, ERROR
	DEBUG_MODE = true,

	-- Checkpoint Settings
	DEFAULT_SPAWN_POSITION = Vector3.new(0, 5, 0),
	RESPAWN_DELAY = 2,
	TOUCH_COOLDOWN = 1,
	MAX_CHECKPOINTS = 10,
	CHECKPOINT_TAG = "Checkpoint",
	CHECKPOINT_ORDER_ATTRIBUTE = "Order",
	CHECKPOINT_SPAWN_OFFSET = Vector3.new(0, 3, 0),
	MAX_DISTANCE_STUDS = 25,
	COOLDOWN_SECONDS = 0,
	DEATH_RESET_SECONDS = 300, -- 5 minutes

	-- Security Settings
	FLAG_WARNING_DURATION = 60, -- 1 minute
	FLAG_IGNORE_DURATION = 300, -- 5 minutes
	MAX_DEATH_COUNT = 3,

	-- Respawn Settings
	CHARACTER_LOAD_TIMEOUT = 10,
	DEATH_LOOP_THRESHOLD = 3,
	DEATH_LOOP_FALLBACK_STEPS = 2,
	TEMPORARY_SHIELD_DURATION = 3,
	RESPAWN_COOLDOWN = 1,

	-- Spawn Validation Settings
	SPAWN_VALIDATION_RADIUS_START = 5,
	SPAWN_VALIDATION_RADIUS_END = 20,
	SPAWN_VALIDATION_RADIUS_STEP = 5,
	SPAWN_VALIDATION_ANGLE_STEP = 45,
	SPAWN_RAYCAST_DISTANCE_DOWN = 10,
	SPAWN_RAYCAST_DISTANCE_UP = 5,
	SPAWN_RAYCAST_DISTANCE_WALL = 2,

	-- UI Settings
	NOTIFICATION_DURATION = 3,
	NOTIFICATION_ANIMATION_SPEED = 0.3,

	-- Effects Settings
	PARTICLE_POOL_SIZE = 10,
	CHECKPOINT_GLOW_DURATION = 2,
	AUDIO_VOLUME = 0.5,
	AUDIO_PITCH_VARIATION = 0.1,

	-- Feature Flags
	ENABLE_BACKUP_DATASTORE = true,
	ENABLE_MIGRATION_SYSTEM = true,
	ENABLE_DEATH_LOOP_PROTECTION = true,
	ENABLE_SPAWN_VALIDATION = true,
	ENABLE_RACE_CONDITION_LOCKS = true,

	-- Admin System Settings
	ENABLE_ADMIN_SYSTEM = true,
	ADMIN_PERMISSION_LEVELS = {
		OWNER = 5,
		DEVELOPER = 4,
		MODERATOR = 3,
		HELPER = 2,
		TESTER = 1
	},

	-- Admin UIDs (Add your UID and other admins here)
	ADMIN_UIDS = {
		[8806688001] = "OWNER", -- Owner
		[9653762582] = "TESTER", -- Co-Owner/Test Account
		-- Add more admin UIDs here as needed
	},

	-- Admin Commands Settings
	ADMIN_COMMAND_COOLDOWN = 1, -- seconds
	ADMIN_LOG_RETENTION = 100, -- max log entries
	ADMIN_GLOBAL_DATASTORE = "CheckpointAdminData_v1",

	-- Global Communication Settings
	ENABLE_GLOBAL_ADMIN_COMMANDS = true,
	GLOBAL_MESSAGE_TOPIC = "CheckpointAdminCommands",
	GLOBAL_STATUS_TOPIC = "CheckpointSystemStatus",
	GLOBAL_DATA_REQUEST_TOPIC = "CheckpointGlobalData",

	-- API Settings (for external admin panels)
	ENABLE_EXTERNAL_API = false, -- Set to true if using external admin tools
	API_ENDPOINT_URL = "", -- Leave empty for Roblox-only operation
	API_AUTH_KEY = "", -- Generate secure key for external access
}

-- Validation functions
function Config.ValidateConfig()
	local errors = {}

	-- Basic validation
	if Config.MAX_CHECKPOINTS < 1 or Config.MAX_CHECKPOINTS > 50 then
		table.insert(errors, "MAX_CHECKPOINTS must be between 1 and 50")
	end

	if Config.MAX_DISTANCE_STUDS <= 0 then
		table.insert(errors, "MAX_DISTANCE_STUDS must be positive")
	end

	if Config.COOLDOWN_SECONDS < 0 then
		table.insert(errors, "COOLDOWN_SECONDS cannot be negative")
	end

	-- Performance validation
	if Config.TARGET_FPS < 30 or Config.TARGET_FPS > 120 then
		table.insert(errors, "TARGET_FPS must be between 30 and 120")
	end

	if Config.MAX_PLAYERS < 1 or Config.MAX_PLAYERS > 100 then
		table.insert(errors, "MAX_PLAYERS must be between 1 and 100")
	end

	-- Sprint validation
	if Config.SPRINT_SPEED <= Config.NORMAL_SPEED then
		table.insert(errors, "SPRINT_SPEED must be greater than NORMAL_SPEED")
	end

	if Config.MAX_ALLOWED_SPEED < Config.SPRINT_SPEED then
		table.insert(errors, "MAX_ALLOWED_SPEED must be >= SPRINT_SPEED")
	end

	return errors
end

-- Runtime configuration override (for testing)
function Config.SetRuntimeConfig(key, value)
	if Config[key] ~= nil then
		Config[key] = value
		if Config.DEBUG_MODE then
			warn("[Config] Runtime config updated:", key, "=", value)
		end	else
		warn("[Config] Invalid config key:", key)
	end
end

-- Dynamic platform detection (set on client)
if game:GetService("UserInputService").TouchEnabled then
	Config.IS_MOBILE = true
	Config.IS_PC = false
end

return Config

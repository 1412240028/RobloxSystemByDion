-- Config.lua
-- Consolidated configuration for all systems
-- Single source of truth for sprint, checkpoint, and unified settings

local Config = {
	-- System Version
	VERSION = "1.2.0",
	DATA_VERSION = 1,

	-- Performance Settings
	TARGET_FPS = 60,
	MAX_PLAYERS = 40,
	TOUCH_RESPONSE_TIME_MS = 100,
	SAVE_TIME_MS = 500,

	-- Speed Settings
	NORMAL_SPEED = 22,
	SPRINT_SPEED = 30,

	-- Validation
	MAX_ALLOWED_SPEED = 35,
	SPEED_TOLERANCE = 3,

	-- Timing
	DEBOUNCE_TIME = 0.2,
	SYNC_DELAY = 0.5,

	-- Rate Limiting
	MAX_TOGGLES_PER_SECOND = 5,

	-- UI Config
	BUTTON_SIZE_PC = UDim2.new(0, 40, 0, 60),
	BUTTON_SIZE_MOBILE_PORTRAIT = UDim2.new(0, 20, 0, 40),
	BUTTON_SIZE_MOBILE_LANDSCAPE = UDim2.new(0, 20, 0, 40),
	BUTTON_POSITION_PC = UDim2.new(0, 30, 0.5, -30),
	BUTTON_POSITION_MOBILE_PORTRAIT = UDim2.new(0, 20, 0, 150),
	BUTTON_POSITION_MOBILE_LANDSCAPE = UDim2.new(0, 20, 0.5, -25),
	BUTTON_COLOR_OFF = Color3.fromRGB(255, 50, 50),
	BUTTON_COLOR_ON = Color3.fromRGB(50, 150, 255),
	BUTTON_CORNER_RADIUS = UDim.new(0, 8),
	BUTTON_STROKE_THICKNESS = 2,

	-- Checkpoint UI Config
	CHECKPOINT_BUTTON_SIZE_PC = UDim2.new(0, 40, 0, 60),
	CHECKPOINT_BUTTON_SIZE_MOBILE_PORTRAIT = UDim2.new(0, 20, 0, 20),
	CHECKPOINT_BUTTON_SIZE_MOBILE_LANDSCAPE = UDim2.new(0, 20, 0, 40),
	CHECKPOINT_BUTTON_POSITION_PC = UDim2.new(0, 30, 0.5, 40), -- Below sprint button
	CHECKPOINT_BUTTON_POSITION_MOBILE_PORTRAIT = UDim2.new(0, 20, 0, 180), -- Below sprint button
	CHECKPOINT_BUTTON_POSITION_MOBILE_LANDSCAPE = UDim2.new(0, 20, 0.5, 30), -- Below sprint button

	-- Animations
	PRESS_SCALE = 0.9,
	PRESS_DURATION = 0.1,
	RELEASE_DURATION = 0.15,
	STATE_CHANGE_DURATION = 0.2,

	-- Data Persistence
	DATASTORE_NAME = "PlayerProgressData_v1",
	DATASTORE_KEY_PREFIX = "Player_",
	SAVE_RETRY_ATTEMPTS = 3,
	SAVE_RETRY_BACKOFF = {1, 2, 4},
	SAVE_RETRY_DELAY_BASE = 2,
	SAVE_THROTTLE_SECONDS = 10,
	AUTO_SAVE_INTERVAL = 30, -- Auto-save every 30 seconds
	QUEUE_PROCESS_INTERVAL = 30,
	MAX_QUEUE_SIZE = 100,

	-- Anti-Cheat
	HEARTBEAT_CHECK_INTERVAL = 1,
	SPEED_CHECK_TOLERANCE = 2,

	-- Platform Detection
	IS_MOBILE = false, -- Will be set dynamically
	IS_PC = true, -- Will be set dynamically

	-- Default Keybind (DEPRECATED - Using GUI button only)
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

	-- Race Settings
	RACE_DURATION_SECONDS = 300, -- 5 minutes max race time
	LEADERBOARD_SIZE = 10, -- Top 10 players
	RACE_START_DELAY = 3, -- Seconds before race starts
	RACE_COOLDOWN_SECONDS = 30, -- Cooldown between races
	MIN_PLAYERS_FOR_RACE = 2, -- Minimum players needed
	MAX_RACE_PARTICIPANTS = 20, -- Maximum concurrent racers
	AUTO_RACE_INTERVAL_MINUTES = 10, -- Auto-race every 10 minutes
	RACE_VOTE_THRESHOLD = 0.6, -- 60% of players need to vote
	RACE_VOTE_COOLDOWN = 30, -- Seconds between votes

	-- Notification Settings
	NOTIFICATION_FADE_TIME = 0.5,
	NOTIFICATION_DISPLAY_TIME = 3,
	NOTIFICATION_POSITION = UDim2.new(0.5, 0, 0.1, 0),
	NOTIFICATION_SIZE = UDim2.new(0, 300, 0, 50),

	-- Race UI Colors
	RACE_ACTIVE_COLOR = Color3.fromRGB(0, 255, 0), -- Green
	RACE_INACTIVE_COLOR = Color3.fromRGB(255, 255, 255), -- White
	RACE_FINISHED_COLOR = Color3.fromRGB(255, 215, 0), -- Gold

	-- Feature Flags
	ENABLE_BACKUP_DATASTORE = true,
	ENABLE_MIGRATION_SYSTEM = true,
	ENABLE_DEATH_LOOP_PROTECTION = true,
	ENABLE_SPAWN_VALIDATION = true,
	ENABLE_RACE_CONDITION_LOCKS = true,
	ENABLE_RACE_SYSTEM = true,

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
		end	
	else
		warn("[Config] Invalid config key:", key)
	end
end

-- Dynamic platform detection (set on client)
if game:GetService("UserInputService").TouchEnabled then
	Config.IS_MOBILE = true
	Config.IS_PC = false

	-- Detect orientation for mobile
	local viewportSize = workspace.CurrentCamera.ViewportSize
	if viewportSize.X > viewportSize.Y then
		Config.IS_LANDSCAPE = true
		Config.IS_PORTRAIT = false
	else
		Config.IS_LANDSCAPE = false
		Config.IS_PORTRAIT = true
	end
else
	Config.IS_PC = true
	Config.IS_MOBILE = false
	Config.IS_LANDSCAPE = false
	Config.IS_PORTRAIT = false
end

return Config

-- Checkpoint System V1.0 - Configuration Settings
-- All tunable values for the checkpoint system

local Settings = {
    -- System Version
    VERSION = "1.0.0",
    DATA_VERSION = 1,

    -- Performance Settings
    TARGET_FPS = 60,
    MAX_PLAYERS = 40,
    TOUCH_RESPONSE_TIME_MS = 100,
    SAVE_TIME_MS = 500,

    -- Checkpoint Settings
    MAX_CHECKPOINTS = 10,
    CHECKPOINT_TAG = "Checkpoint",
    CHECKPOINT_ORDER_ATTRIBUTE = "Order",
    CHECKPOINT_SPAWN_OFFSET = Vector3.new(0, 3, 0),

    -- Validation Settings
    MAX_DISTANCE_STUDS = 25,
    COOLDOWN_SECONDS = 0,
    DEATH_RESET_SECONDS = 300, -- 5 minutes

    -- Security Settings
    FLAG_WARNING_DURATION = 60, -- 1 minute
    FLAG_IGNORE_DURATION = 300, -- 5 minutes
    MAX_DEATH_COUNT = 3,

    -- Data Persistence Settings
    SAVE_THROTTLE_SECONDS = 10,
    AUTO_SAVE_INTERVAL_SECONDS = 60,
    SAVE_RETRY_ATTEMPTS = 3,
    SAVE_RETRY_BACKOFF = {2, 4, 8}, -- seconds
    QUEUE_PROCESS_INTERVAL = 30,
    MAX_QUEUE_SIZE = 100,

    -- Respawn Settings
    CHARACTER_LOAD_TIMEOUT = 10,
    DEATH_LOOP_THRESHOLD = 3,
    DEATH_LOOP_FALLBACK_STEPS = 2,
    TEMPORARY_SHIELD_DURATION = 3,

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

    -- Debug Settings
    DEBUG_MODE = true,
    LOG_LEVEL = "INFO", -- "DEBUG", "INFO", "WARN", "ERROR"

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
function Settings.ValidateConfig()
    local errors = {}

    -- Basic validation
    if Settings.MAX_CHECKPOINTS < 1 or Settings.MAX_CHECKPOINTS > 50 then
        table.insert(errors, "MAX_CHECKPOINTS must be between 1 and 50")
    end

    if Settings.MAX_DISTANCE_STUDS <= 0 then
        table.insert(errors, "MAX_DISTANCE_STUDS must be positive")
    end

    if Settings.COOLDOWN_SECONDS < 0 then
        table.insert(errors, "COOLDOWN_SECONDS cannot be negative")
    end

    -- Performance validation
    if Settings.TARGET_FPS < 30 or Settings.TARGET_FPS > 120 then
        table.insert(errors, "TARGET_FPS must be between 30 and 120")
    end

    if Settings.MAX_PLAYERS < 1 or Settings.MAX_PLAYERS > 100 then
        table.insert(errors, "MAX_PLAYERS must be between 1 and 100")
    end

    return errors
end

-- Runtime configuration override (for testing)
function Settings.SetRuntimeConfig(key, value)
    if Settings[key] ~= nil then
        Settings[key] = value
        if Settings.DEBUG_MODE then
            warn("[CheckpointSystem] Runtime config updated:", key, "=", value)
        end
    else
        warn("[CheckpointSystem] Invalid config key:", key)
    end
end

-- Export
return Settings

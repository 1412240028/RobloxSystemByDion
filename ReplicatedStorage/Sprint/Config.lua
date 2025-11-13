-- Config.lua
-- Single source of truth untuk semua konfigurasi
-- Shared antara client & server untuk konsistensi

local Config = {
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
	DATASTORE_NAME = "SprintSystem_v1",
	SAVE_RETRY_ATTEMPTS = 3,
	SAVE_RETRY_DELAY_BASE = 2,

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
}

-- Dynamic platform detection (set on client)
if game:GetService("UserInputService").TouchEnabled then
	Config.IS_MOBILE = true
	Config.IS_PC = false
end

return Config
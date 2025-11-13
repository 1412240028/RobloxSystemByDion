-- SharedTypes.lua
-- Type definitions & enums untuk code clarity
-- Konsistensi data structure & self-documenting code

local SharedTypes = {
    -- Sprint State Enum
    SprintState = {
        STOPPED = false,
        RUNNING = true
    },

    -- Validation Result Enum
    ValidationResult = {
        SUCCESS = "success",
        INVALID_SPEED = "invalid_speed",
        RATE_LIMITED = "rate_limited",
        PLAYER_NOT_FOUND = "player_not_found",
        CHARACTER_NOT_FOUND = "character_not_found",
        DEBOUNCE_ACTIVE = "debounce_active",
        INVALID_REQUEST = "invalid_request"
    },

    -- Player Data Structure
    PlayerData = {
        userId = 0,
        isSprinting = false,
        lastToggleTime = 0,
        toggleCount = 0,
        character = nil, -- CharacterModel
        humanoid = nil, -- HumanoidObject
        lastSpeedCheck = 0,
        speedViolations = 0
    },

    -- Toggle Request Structure
    ToggleRequest = {
        player = nil, -- Player object
        requestedState = false, -- boolean
        timestamp = 0 -- tick()
    },

    -- Validation Response Structure
    ValidationResponse = {
        success = false,
        reason = "",
        targetSpeed = 16,
        playerData = nil
    },

    -- Sync Data Structure
    SyncData = {
        isSprinting = false,
        currentSpeed = 16,
        timestamp = 0
    },

    -- UI State Enum
    UIState = {
        OFF = "OFF",
        ON = "ON",
        COOLDOWN = "COOLDOWN",
        ERROR = "ERROR"
    },

    -- Platform Enum
    Platform = {
        PC = "PC",
        MOBILE = "MOBILE",
        UNKNOWN = "UNKNOWN"
    }
}

return SharedTypes

-- Checkpoint System V1.0 - Client Script
-- Handles client-side checkpoint detection and effects

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local Settings = require(game.ReplicatedStorage.CheckpointSystem.Config.Settings)

local CheckpointClient = {}

-- Private variables
local player = Players.LocalPlayer
local character = nil
local touchedCheckpoints = {} -- {checkpointPart: true}
local isInitialized = false

-- Module imports
local UIController = require(game.ReplicatedStorage.CheckpointSystem.Modules.UIController)
local EffectsController = require(game.ReplicatedStorage.CheckpointSystem.Modules.EffectsController)

-- Remote events
local CheckpointReachedEvent = game.ReplicatedStorage.CheckpointSystem.Remotes.CheckpointReached

-- Logger utility
local function Log(level, message, ...)
    if not Settings.DEBUG_MODE and level == "DEBUG" then return end

    local prefix = "[CheckpointClient]"
    if level == "ERROR" then
        warn(prefix .. " " .. string.format(message, ...))
    elseif level == "WARN" then
        warn(prefix .. " " .. string.format(message, ...))
    elseif level == "INFO" or (Settings.DEBUG_MODE and level == "DEBUG") then
        print(prefix .. " " .. string.format(message, ...))
    end
end

-- Initialize the client
function CheckpointClient.Initialize()
    if isInitialized then
        Log("WARN", "CheckpointClient already initialized")
        return true
    end

    Log("INFO", "Initializing CheckpointClient...")

    -- Initialize UI and Effects
    if not UIController.Initialize() then
        Log("ERROR", "Failed to initialize UIController")
        return false
    end

    if not EffectsController.Initialize() then
        Log("ERROR", "Failed to initialize EffectsController")
        return false
    end

    -- Set up character connections
    CheckpointClient.SetupCharacterConnections()

    -- Set up remote event listeners
    CheckpointReachedEvent.OnClientEvent:Connect(OnCheckpointReachedRemote)

    isInitialized = true
    Log("INFO", "CheckpointClient initialized successfully")
    return true
end

-- Set up character connections
function CheckpointClient.SetupCharacterConnections()
    -- Handle character added
    player.CharacterAdded:Connect(function(newCharacter)
        character = newCharacter
        CheckpointClient.SetupCheckpointDetection(newCharacter)
        Log("DEBUG", "Character added, checkpoint detection set up")
    end)

    -- Handle current character
    if player.Character then
        character = player.Character
        CheckpointClient.SetupCheckpointDetection(character)
    end
end

-- Set up checkpoint detection for character
function CheckpointClient.SetupCheckpointDetection(character)
    if not character then return end

    -- Find humanoid root part
    local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 5)
    if not humanoidRootPart then
        Log("ERROR", "HumanoidRootPart not found")
        return
    end

    -- Connect to touched event
    humanoidRootPart.Touched:Connect(function(hit)
        CheckpointClient.OnTouch(hit)
    end)

    Log("DEBUG", "Checkpoint detection set up for character")
end

-- Handle touch events
function CheckpointClient.OnTouch(hit)
    if not isInitialized or not character then return end

    -- Check if hit is a checkpoint
    if not CollectionService:HasTag(hit, Settings.CHECKPOINT_TAG) then
        return
    end

    -- Check if already touched this checkpoint
    if touchedCheckpoints[hit] then
        return
    end

    -- Get checkpoint order
    local checkpointOrder = hit:GetAttribute(Settings.CHECKPOINT_ORDER_ATTRIBUTE)
    if not checkpointOrder or type(checkpointOrder) ~= "number" then
        Log("WARN", "Checkpoint missing or invalid order attribute")
        return
    end

    -- Mark as touched
    touchedCheckpoints[hit] = true

    -- Fire remote event to server
    CheckpointReachedEvent:FireServer(checkpointOrder, hit)

    Log("DEBUG", "Checkpoint touched: order=%d, part=%s", checkpointOrder, hit.Name)
end

-- Handle checkpoint reached from server (for effects/UI)
function OnCheckpointReachedRemote(reachedPlayer, checkpointOrder, checkpointPart)
    if not isInitialized then return end

    -- Only process if it's this player
    if reachedPlayer ~= player then return end

    Log("DEBUG", "Checkpoint reached notification: order=%d", checkpointOrder)

    -- Get total checkpoints for progress display
    local CheckpointManager = require(game.ReplicatedStorage.CheckpointSystem.Modules.CheckpointManager)
    local totalCheckpoints = CheckpointManager.GetCheckpointCount()

    -- Show UI notification
    UIController.ShowCheckpointNotification(checkpointOrder, totalCheckpoints)

    -- Play effects
    EffectsController.PlayCheckpointEffects(checkpointPart)
end

-- Reset touched checkpoints (for respawn)
function CheckpointClient.ResetTouchedCheckpoints()
    touchedCheckpoints = {}
    Log("DEBUG", "Touched checkpoints reset")
end

-- Get client status
function CheckpointClient.GetStatus()
    return {
        Initialized = isInitialized,
        Character = character and character.Name or "None",
        TouchedCheckpoints = 0, -- Count them
        UIStatus = UIController.GetNotificationStatus(),
        EffectsStatus = EffectsController.GetEffectsStatus()
    }
end

-- Test functions (debug only)
function CheckpointClient.TestNotification()
    if not Settings.DEBUG_MODE then return end

    UIController.ShowCustomNotification("Test Notification", 2)
    Log("INFO", "Test notification shown")
end

function CheckpointClient.TestEffects()
    if not Settings.DEBUG_MODE then return end

    -- Find a checkpoint to test on
    local checkpoints = CollectionService:GetTagged(Settings.CHECKPOINT_TAG)
    if #checkpoints > 0 then
        EffectsController.TestEffects(checkpoints[1])
        Log("INFO", "Test effects played")
    else
        Log("WARN", "No checkpoints found for testing")
    end
end

-- Cleanup function
function CheckpointClient.Cleanup()
    touchedCheckpoints = {}
    character = nil

    UIController.Cleanup()
    EffectsController.Cleanup()

    isInitialized = false
    Log("INFO", "CheckpointClient cleaned up")
end

-- Initialize on script run
if CheckpointClient.Initialize() then
    Log("INFO", "CheckpointClient started successfully")
else
    Log("ERROR", "Failed to start CheckpointClient")
end

return CheckpointClient

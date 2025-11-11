-- Checkpoint System V1.0 - Checkpoint Manager Module
-- Handles automatic checkpoint detection, validation, and management

local CollectionService = game:GetService("CollectionService")
local Settings = require(game.ReplicatedStorage.CheckpointSystem.Config.Settings)

local CheckpointManager = {}

-- Private variables
local checkpoints = {}
local isInitialized = false

-- Logger utility
local function Log(level, message, ...)
    if not Settings.DEBUG_MODE and level == "DEBUG" then return end

    local prefix = "[CheckpointManager]"
    if level == "ERROR" then
        warn(prefix .. " " .. string.format(message, ...))
    elseif level == "WARN" then
        warn(prefix .. " " .. string.format(message, ...))
    elseif level == "INFO" or (Settings.DEBUG_MODE and level == "DEBUG") then
        print(prefix .. " " .. string.format(message, ...))
    end
end

-- Initialize the checkpoint manager
function CheckpointManager.Initialize()
    if isInitialized then
        Log("WARN", "CheckpointManager already initialized")
        return true
    end

    Log("INFO", "Initializing CheckpointManager...")

    -- Scan for checkpoints
    local success = CheckpointManager.ScanCheckpoints()

    if success then
        isInitialized = true
        Log("INFO", "CheckpointManager initialized successfully with %d checkpoints", #checkpoints)
    else
        Log("ERROR", "Failed to initialize CheckpointManager")
    end

    return success
end

-- Scan workspace for checkpoints tagged with CollectionService
function CheckpointManager.ScanCheckpoints()
    Log("DEBUG", "Scanning for checkpoints with tag: %s", Settings.CHECKPOINT_TAG)

    local taggedParts = CollectionService:GetTagged(Settings.CHECKPOINT_TAG)
    local foundCheckpoints = {}

    for _, part in ipairs(taggedParts) do
        if CheckpointManager.ValidateCheckpoint(part) then
            table.insert(foundCheckpoints, part)
        end
    end

    -- Sort by Order attribute
    table.sort(foundCheckpoints, function(a, b)
        local orderA = a:GetAttribute(Settings.CHECKPOINT_ORDER_ATTRIBUTE) or 0
        local orderB = b:GetAttribute(Settings.CHECKPOINT_ORDER_ATTRIBUTE) or 0
        return orderA < orderB
    end)

    -- Validate sequence and assign orders if missing
    local validatedCheckpoints = CheckpointManager.ValidateCheckpointSequence(foundCheckpoints)

    checkpoints = validatedCheckpoints
    Log("INFO", "Found and validated %d checkpoints", #checkpoints)

    return true
end

-- Validate a single checkpoint part
function CheckpointManager.ValidateCheckpoint(part)
    -- Basic validation
    if not part:IsA("BasePart") then
        Log("WARN", "Checkpoint must be a BasePart, got %s", part.ClassName)
        return false
    end

    if not part.CanCollide then
        Log("WARN", "Checkpoint %s should have CanCollide = true", part.Name)
    end

    -- Check for required attributes
    local order = part:GetAttribute(Settings.CHECKPOINT_ORDER_ATTRIBUTE)
    if order and (type(order) ~= "number" or order < 0) then
        Log("WARN", "Checkpoint %s has invalid Order attribute: %s", part.Name, tostring(order))
        return false
    end

    Log("DEBUG", "Validated checkpoint: %s (Order: %s)", part.Name, tostring(order))
    return true
end

-- Validate checkpoint sequence and fix issues
function CheckpointManager.ValidateCheckpointSequence(checkpointList)
    local validated = {}
    local usedOrders = {}
    local nextOrder = 1

    for _, checkpoint in ipairs(checkpointList) do
        local order = checkpoint:GetAttribute(Settings.CHECKPOINT_ORDER_ATTRIBUTE)

        if order then
            -- Check for duplicates
            if usedOrders[order] then
                Log("WARN", "Duplicate checkpoint order %d, reassigning", order)
                order = nil
            else
                usedOrders[order] = true
            end
        end

        -- Assign order if missing
        if not order then
            while usedOrders[nextOrder] do
                nextOrder = nextOrder + 1
            end
            order = nextOrder
            checkpoint:SetAttribute(Settings.CHECKPOINT_ORDER_ATTRIBUTE, order)
            usedOrders[order] = true
            Log("INFO", "Assigned Order %d to checkpoint %s", order, checkpoint.Name)
        end

        -- Validate order is sequential (allow gaps but warn)
        if order > nextOrder then
            Log("WARN", "Gap in checkpoint sequence: expected %d, got %d", nextOrder, order)
        end

        table.insert(validated, {
            Part = checkpoint,
            Order = order,
            Position = checkpoint.Position,
            SpawnPosition = checkpoint.Position + Settings.CHECKPOINT_SPAWN_OFFSET
        })

        nextOrder = order + 1
    end

    -- Final validation
    if #validated == 0 then
        Log("ERROR", "No valid checkpoints found")
        return {}
    end

    if #validated > Settings.MAX_CHECKPOINTS then
        Log("WARN", "Found %d checkpoints, maximum allowed is %d", #validated, Settings.MAX_CHECKPOINTS)
    end

    return validated
end

-- Get checkpoint by order
function CheckpointManager.GetCheckpointByOrder(order)
    for _, checkpoint in ipairs(checkpoints) do
        if checkpoint.Order == order then
            return checkpoint
        end
    end
    return nil
end

-- Get next checkpoint after given order
function CheckpointManager.GetNextCheckpoint(currentOrder)
    return CheckpointManager.GetCheckpointByOrder(currentOrder + 1)
end

-- Get all checkpoints
function CheckpointManager.GetAllCheckpoints()
    return checkpoints
end

-- Get checkpoint count
function CheckpointManager.GetCheckpointCount()
    return #checkpoints
end

-- Check if checkpoint exists
function CheckpointManager.CheckpointExists(order)
    return CheckpointManager.GetCheckpointByOrder(order) ~= nil
end

-- Get spawn position for checkpoint
function CheckpointManager.GetSpawnPosition(order)
    local checkpoint = CheckpointManager.GetCheckpointByOrder(order)
    return checkpoint and checkpoint.SpawnPosition or nil
end

-- Validate checkpoint is still valid (not deleted)
function CheckpointManager.IsCheckpointValid(order)
    local checkpoint = CheckpointManager.GetCheckpointByOrder(order)
    return checkpoint and checkpoint.Part and checkpoint.Part.Parent ~= nil
end

-- Debug function to print all checkpoints
function CheckpointManager.DebugPrintCheckpoints()
    if not Settings.DEBUG_MODE then return end

    Log("INFO", "=== Checkpoint Debug Info ===")
    for i, checkpoint in ipairs(checkpoints) do
        Log("INFO", "%d. %s (Order: %d, Position: %s)",
            i, checkpoint.Part.Name, checkpoint.Order, tostring(checkpoint.Position))
    end
    Log("INFO", "=== End Debug Info ===")
end

-- Cleanup function
function CheckpointManager.Cleanup()
    checkpoints = {}
    isInitialized = false
    Log("INFO", "CheckpointManager cleaned up")
end

return CheckpointManager

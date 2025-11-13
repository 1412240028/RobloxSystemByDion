-- AutoSetup.lua
-- Automatic setup script for RobloxSystemByDion
-- Creates all necessary folders, parts, and basic structure

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local AutoSetup = {}

-- Configuration for setup
local SETUP_CONFIG = {
    CHECKPOINT_COUNT = 3,
    CHECKPOINT_SPACING = 50,
    CHECKPOINT_HEIGHT = 4,
    CHECKPOINT_SIZE = Vector3.new(8, 8, 2),
    CHECKPOINT_COLORS = {
        Color3.fromRGB(0, 255, 0),   -- Green
        Color3.fromRGB(0, 150, 255), -- Blue
        Color3.fromRGB(255, 0, 0),   -- Red
    }
}

-- Utility function to create folder if it doesn't exist
function AutoSetup.CreateFolder(parent, folderName)
    local folder = parent:FindFirstChild(folderName)
    if not folder then
        folder = Instance.new("Folder")
        folder.Name = folderName
        folder.Parent = parent
        print("[AutoSetup] Created folder: " .. folderName)
    else
        print("[AutoSetup] Folder already exists: " .. folderName)
    end
    return folder
end

-- Create all necessary folders
function AutoSetup.CreateFolders()
    print("[AutoSetup] Creating folder structure...")

    -- ReplicatedStorage folders
    AutoSetup.CreateFolder(ReplicatedStorage, "Config")
    AutoSetup.CreateFolder(ReplicatedStorage, "Modules")
    AutoSetup.CreateFolder(ReplicatedStorage, "Remotes")

    -- Remote events folders
    local sprintFolder = AutoSetup.CreateFolder(ReplicatedStorage, "Sprint")
    AutoSetup.CreateFolder(sprintFolder, "RemoteEvents")

    local checkpointFolder = AutoSetup.CreateFolder(ReplicatedStorage, "Checkpoint")
    AutoSetup.CreateFolder(checkpointFolder, "Remotes")

    -- StarterPlayer folders
    local starterScripts = AutoSetup.CreateFolder(StarterPlayer, "StarterPlayerScripts")
    AutoSetup.CreateFolder(starterScripts, "Sprint")
    AutoSetup.CreateFolder(starterScripts, "Checkpoint")

    -- StarterGui folders
    AutoSetup.CreateFolder(StarterGui, "CheckpointUI")

    -- Workspace folders
    AutoSetup.CreateFolder(Workspace, "Checkpoints")

    print("[AutoSetup] Folder structure created successfully!")
end

-- Create checkpoint parts
function AutoSetup.CreateCheckpoints()
    print("[AutoSetup] Creating checkpoint parts...")

    local checkpointsFolder = Workspace:FindFirstChild("Checkpoints")
    if not checkpointsFolder then
        warn("[AutoSetup] Checkpoints folder not found!")
        return
    end

    for i = 1, SETUP_CONFIG.CHECKPOINT_COUNT do
        local checkpointName = "Checkpoint" .. i
        local existingCheckpoint = checkpointsFolder:FindFirstChild(checkpointName)

        if not existingCheckpoint then
            -- Create checkpoint part
            local checkpoint = Instance.new("Part")
            checkpoint.Name = checkpointName
            checkpoint.Size = SETUP_CONFIG.CHECKPOINT_SIZE
            checkpoint.Position = Vector3.new(
                (i - 1) * SETUP_CONFIG.CHECKPOINT_SPACING,
                SETUP_CONFIG.CHECKPOINT_HEIGHT,
                0
            )
            checkpoint.Anchored = true
            checkpoint.CanCollide = true
            checkpoint.BrickColor = BrickColor.new(SETUP_CONFIG.CHECKPOINT_COLORS[i] or Color3.new(1, 1, 1))

            -- Add glow effect
            local glow = Instance.new("PointLight")
            glow.Color = SETUP_CONFIG.CHECKPOINT_COLORS[i] or Color3.new(1, 1, 1)
            glow.Range = 15
            glow.Brightness = 0.5
            glow.Parent = checkpoint

            -- Add order attribute
            checkpoint:SetAttribute("Order", i)

            -- Add tag for identification
            local tag = Instance.new("StringValue")
            tag.Name = "CheckpointTag"
            tag.Value = "Checkpoint"
            tag.Parent = checkpoint

            checkpoint.Parent = checkpointsFolder

            print(string.format("[AutoSetup] Created checkpoint %d at position (%.1f, %.1f, %.1f)",
                i, checkpoint.Position.X, checkpoint.Position.Y, checkpoint.Position.Z))
        else
            print("[AutoSetup] Checkpoint " .. i .. " already exists")
        end
    end

    print("[AutoSetup] Checkpoint parts created successfully!")
end

-- Create remote events
function AutoSetup.CreateRemoteEvents()
    print("[AutoSetup] Creating remote events...")

    -- Sprint remote events
    local sprintEventsFolder = ReplicatedStorage.Sprint:FindFirstChild("RemoteEvents")
    if sprintEventsFolder then
        AutoSetup.CreateRemoteEvent(sprintEventsFolder, "SprintToggleEvent", "RemoteEvent")
        AutoSetup.CreateRemoteEvent(sprintEventsFolder, "SprintSyncEvent", "RemoteEvent")
    end

    -- Checkpoint remote events
    local checkpointEventsFolder = ReplicatedStorage.Checkpoint:FindFirstChild("Remotes")
    if checkpointEventsFolder then
        AutoSetup.CreateRemoteEvent(checkpointEventsFolder, "CheckpointTouchedEvent", "RemoteEvent")
        AutoSetup.CreateRemoteEvent(checkpointEventsFolder, "CheckpointSyncEvent", "RemoteEvent")
        AutoSetup.CreateRemoteEvent(checkpointEventsFolder, "ResetCheckpoints", "RemoteEvent")
    end

    print("[AutoSetup] Remote events created successfully!")
end

-- Utility to create remote event
function AutoSetup.CreateRemoteEvent(parent, name, eventType)
    local existing = parent:FindFirstChild(name)
    if not existing then
        local remote = Instance.new(eventType)
        remote.Name = name
        remote.Parent = parent
        print("[AutoSetup] Created " .. eventType .. ": " .. name)
    else
        print("[AutoSetup] " .. eventType .. " already exists: " .. name)
    end
end

-- Create basic scripts (optional)
function AutoSetup.CreateBasicScripts()
    print("[AutoSetup] Creating basic script templates...")

    -- This would create basic script templates if needed
    -- For now, we'll skip this as the main scripts are already implemented

    print("[AutoSetup] Basic scripts setup complete!")
end

-- Main setup function
function AutoSetup.RunSetup()
    print("=========================================")
    print("🚀 ROBLOX SYSTEM BY DION - AUTO SETUP")
    print("=========================================")

    -- Run all setup steps
    AutoSetup.CreateFolders()
    AutoSetup.CreateCheckpoints()
    AutoSetup.CreateRemoteEvents()
    AutoSetup.CreateBasicScripts()

    print("=========================================")
    print("✅ SETUP COMPLETE!")
    print("=========================================")
    print("Next steps:")
    print("1. Run the game to test the basic structure")
    print("2. The main scripts should be placed manually or through additional setup")
    print("3. Check the IMPLEMENTATION_PLAN.md for detailed file placement")
    print("=========================================")
end

-- Run setup when script executes
AutoSetup.RunSetup()

return AutoSetup

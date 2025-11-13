-- SprintClient.lua (MODIFIED FOR ROBUST RESPAWN)
-- Client-side controller & input handling
-- Logic & input, separate from GUI

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Sprint.Config)
local SharedTypes = require(ReplicatedStorage.Sprint.SharedTypes)
local RemoteEvents = require(ReplicatedStorage.Sprint.RemoteEvents)

local SprintClient = {}

-- Private variables
local player = Players.LocalPlayer
local isSprinting = false
local lastRequestTime = 0
local throttleActive = false
local character = nil
local humanoid = nil
local isWaitingForSync = false -- NEW: Prevent duplicate requests

-- GUI reference (will be set by SprintGUI)
local sprintGUI = nil

-- Initialize client
function SprintClient.Init()
    print("[SprintClient] Initializing client for", player.Name)

    -- Set GUI reference
    local SprintGUI = require(script.Parent.SprintGUI)
    SprintGUI.SetClient(SprintClient)
    SprintClient.SetGUI(SprintGUI)

    -- Wait for character
    SprintClient.WaitForCharacter()

    -- Setup input handling
    SprintClient.SetupInputHandling()

    -- Connect to server sync
    RemoteEvents.OnSyncReceived(SprintClient.OnSyncReceived)

    print("[SprintClient] Client initialized")
end

-- Wait for character and setup
function SprintClient.WaitForCharacter()
    local function onCharacterAdded(newCharacter)
        character = newCharacter
        humanoid = character:WaitForChild("Humanoid")

        -- NEW: Wait for server to send authoritative state
        -- Don't send toggle request, just wait for sync
        isWaitingForSync = true
        lastRequestTime = 0

        print("[SprintClient] Character loaded - waiting for server sync...")

        -- NEW: Timeout fallback if server doesn't respond
        task.delay(2, function()
            if isWaitingForSync then
                warn("[SprintClient] Server sync timeout - requesting manual sync")
                -- Send current state as query (server will respond with correct state)
                RemoteEvents.FireToggle(isSprinting)
            end
        end)
    end

    if player.Character then
        onCharacterAdded(player.Character)
    end

    player.CharacterAdded:Connect(onCharacterAdded)
end

-- Setup input handling
function SprintClient.SetupInputHandling()
    -- No keyboard input - using GUI button only
    -- Mobile touch (handled by GUI)
end

-- Request sprint toggle
function SprintClient.RequestToggle()
    if throttleActive then return end
    if isWaitingForSync then 
        warn("[SprintClient] Still waiting for server sync - ignoring toggle")
        return 
    end

    -- Local throttle check
    local timeSinceLastRequest = tick() - lastRequestTime
    if timeSinceLastRequest < Config.DEBOUNCE_TIME then
        return
    end

    -- Toggle state
    local newState = not isSprinting

    -- Send request to server
    RemoteEvents.FireToggle(newState)

    -- Update local state optimistically
    SprintClient.SetLocalState(newState)

    -- Start throttle
    throttleActive = true
    task.delay(Config.DEBOUNCE_TIME, function()
        throttleActive = false
    end)

    lastRequestTime = tick()
end

-- Handle server sync (MODIFIED)
function SprintClient.OnSyncReceived(syncData)
    -- NEW: Clear waiting flag
    isWaitingForSync = false

    -- Update local state from server (authoritative)
    local previousState = isSprinting
    SprintClient.SetLocalState(syncData.isSprinting)

    -- Update GUI
    if sprintGUI then
        sprintGUI.UpdateVisualState(syncData.isSprinting)
    end

    -- NEW: Log state changes for debugging
    if previousState ~= syncData.isSprinting then
        print(string.format("[SprintClient] State synced from server: %s -> %s",
            tostring(previousState), tostring(syncData.isSprinting)))
    end
end

-- Set local sprint state
function SprintClient.SetLocalState(newState)
    isSprinting = newState

    -- Update GUI
    if sprintGUI then
        sprintGUI.UpdateVisualState(newState)
    end
end

-- Get current state
function SprintClient.GetCurrentState()
    return isSprinting
end

-- Check if can toggle
function SprintClient.CanToggle()
    return not throttleActive and not isWaitingForSync and character and humanoid
end

-- Set GUI reference
function SprintClient.SetGUI(guiModule)
    sprintGUI = guiModule
end

-- Handle request failure (called by GUI)
function SprintClient.OnRequestFailed()
    -- Revert optimistic update
    SprintClient.SetLocalState(not isSprinting)
end

-- Cleanup
function SprintClient.Cleanup()
    -- Disconnect connections if needed
    character = nil
    humanoid = nil
    sprintGUI = nil
    isWaitingForSync = false
end

-- Initialize when script runs
SprintClient.Init()

return SprintClient
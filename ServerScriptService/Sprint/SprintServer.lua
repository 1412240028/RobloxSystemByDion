-- SprintServer.lua (MODIFIED FOR ROBUST RESPAWN)
-- Main server orchestrator
-- Handles player management, remote events, anti-cheat monitoring

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Sprint.Config)
local SharedTypes = require(ReplicatedStorage.Sprint.SharedTypes)
local RemoteEvents = require(ReplicatedStorage.Sprint.RemoteEvents)

local PlayerDataManager = require(script.Parent.PlayerDataManager)
local ValidationService = require(script.Parent.ValidationService)

local SprintServer = {}

-- Private variables
local activePlayers = {} -- player -> playerData
local heartbeatConnection = nil

-- Initialize server
function SprintServer.Init()
    print("[SprintServer] Initializing Sprint System v1.0")

    -- Setup player connections
    Players.PlayerAdded:Connect(SprintServer.OnPlayerAdded)
    Players.PlayerRemoving:Connect(SprintServer.OnPlayerRemoving)

    -- Setup remote event connections
    RemoteEvents.OnToggleRequested(SprintServer.OnToggleRequested)

    -- Start anti-cheat heartbeat
    SprintServer.StartHeartbeat()

    print("[SprintServer] Sprint System initialized successfully")
end

-- Handle player joining
function SprintServer.OnPlayerAdded(player)
    print("[SprintServer] Player joined:", player.Name)

    -- Create player data
    local playerData = PlayerDataManager.CreatePlayerData(player)
    activePlayers[player] = playerData

    -- Load saved data
    PlayerDataManager.LoadPlayerData(player)

    -- Wait for character and setup
    player.CharacterAdded:Connect(function(character)
        SprintServer.SetupCharacter(player, character)
    end)

    -- If character already exists
    if player.Character then
        SprintServer.SetupCharacter(player, player.Character)
    end
end

-- Setup character connections (MODIFIED)
function SprintServer.SetupCharacter(player, character)
    local playerData = activePlayers[player]
    if not playerData then return end

    -- Wait a frame to ensure character is fully loaded
    task.wait(0.1)

    playerData.character = character
    local humanoid = character:FindFirstChild("Humanoid")
    if humanoid then
        playerData.humanoid = humanoid

        -- NEW: Apply saved sprint state IMMEDIATELY
        local targetSpeed = playerData.isSprinting and Config.SPRINT_SPEED or Config.NORMAL_SPEED
        humanoid.WalkSpeed = targetSpeed

        -- NEW: Force sync to client multiple times to ensure delivery
        local function sendSync()
            RemoteEvents.SendSync(player, {
                isSprinting = playerData.isSprinting,
                currentSpeed = targetSpeed,
                timestamp = tick()
            })
        end

        -- Send initial sync
        sendSync()

        -- Send again after small delay (in case client wasn't ready)
        task.delay(0.1, sendSync)
        task.delay(0.3, sendSync)

        print(string.format("[SprintServer] Character setup for %s - sprint state: %s (speed: %d)",
            player.Name, playerData.isSprinting and "ON" or "OFF", targetSpeed))
    end

    -- Handle character removal (MODIFIED - DON'T reset state)
    humanoid.Died:Connect(function()
        SprintServer.OnCharacterDied(player)
    end)
end

-- Handle character death (MODIFIED - Keep sprint state)
function SprintServer.OnCharacterDied(player)
    local playerData = activePlayers[player]
    if not playerData then return end

    -- NEW: DON'T reset sprint state - keep it for next respawn
    -- OLD CODE (REMOVED):
    -- playerData.isSprinting = false
    -- PlayerDataManager.UpdateSprintState(player, false)

    -- NEW: Just clear character references
    playerData.character = nil
    playerData.humanoid = nil

    print(string.format("[SprintServer] %s died - sprint state preserved: %s",
        player.Name, playerData.isSprinting and "ON" or "OFF"))
end

-- Handle player leaving
function SprintServer.OnPlayerRemoving(player)
    print("[SprintServer] Player leaving:", player.Name)

    local playerData = activePlayers[player]
    if playerData then
        -- Save data
        PlayerDataManager.SavePlayerData(player)
        -- Cleanup
        PlayerDataManager.CleanupPlayerData(player)
        activePlayers[player] = nil
    end
end

-- Handle sprint toggle request
function SprintServer.OnToggleRequested(player, requestedState)
    local validation = ValidationService.ValidateToggleRequest(player, requestedState)

    if validation.success then
        -- Apply speed change
        local humanoid = validation.playerData.humanoid
        humanoid.WalkSpeed = validation.targetSpeed

        -- Update data
        PlayerDataManager.UpdateSprintState(player, requestedState)

        -- Send sync to client
        RemoteEvents.SendSync(player, {
            isSprinting = requestedState,
            currentSpeed = validation.targetSpeed,
            timestamp = tick()
        })

        print(string.format("[SprintServer] Sprint %s for %s (speed: %d)",
            requestedState and "enabled" or "disabled", player.Name, validation.targetSpeed))
    else
        warn(string.format("[SprintServer] Toggle rejected for %s: %s",
            player.Name, validation.reason))
        
        -- NEW: Send current state back to client even if rejected
        local playerData = activePlayers[player]
        if playerData then
            RemoteEvents.SendSync(player, {
                isSprinting = playerData.isSprinting,
                currentSpeed = playerData.isSprinting and Config.SPRINT_SPEED or Config.NORMAL_SPEED,
                timestamp = tick()
            })
        end
    end
end

-- Start anti-cheat heartbeat
function SprintServer.StartHeartbeat()
    heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
        SprintServer.CheckSpeedIntegrity()
    end)
end

-- Check speed integrity for all players
function SprintServer.CheckSpeedIntegrity()
    for player, playerData in pairs(activePlayers) do
        if playerData.humanoid and tick() - playerData.lastSpeedCheck > Config.HEARTBEAT_CHECK_INTERVAL then
            local needsCorrection = ValidationService.CheckSpeedIntegrity(player)

            if needsCorrection then
                -- Force correct speed
                local expectedSpeed = playerData.isSprinting and Config.SPRINT_SPEED or Config.NORMAL_SPEED
                playerData.humanoid.WalkSpeed = expectedSpeed

                -- Send correction sync
                RemoteEvents.SendSync(player, {
                    isSprinting = playerData.isSprinting,
                    currentSpeed = expectedSpeed,
                    timestamp = tick()
                })

                playerData.speedViolations = playerData.speedViolations + 1
                warn(string.format("[SprintServer] Speed corrected for %s (violations: %d)",
                    player.Name, playerData.speedViolations))
            end

            playerData.lastSpeedCheck = tick()
        end
    end
end

-- Cleanup on server shutdown
function SprintServer.Cleanup()
    if heartbeatConnection then
        heartbeatConnection:Disconnect()
        heartbeatConnection = nil
    end

    -- Save all player data
    for player in pairs(activePlayers) do
        PlayerDataManager.SavePlayerData(player)
    end

    activePlayers = {}
end

-- Initialize when script runs
SprintServer.Init()

-- Handle server shutdown
game:BindToClose(function()
    SprintServer.Cleanup()
end)

return SprintServer
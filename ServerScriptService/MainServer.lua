-- MainServer.lua
-- Unified server script for checkpoint and sprint systems
-- HYBRID VERSION: Combines flexible checkpoint system with leaderstats & respawn
-- v1.2 - Best of both worlds

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config.Config)
local SharedTypes = require(ReplicatedStorage.Modules.SharedTypes)
local RemoteEvents = require(ReplicatedStorage.Remotes.RemoteEvents)
local DataManager = require(ReplicatedStorage.Modules.DataManager)

local MainServer = {}

-- Private variables
local activePlayers = {} -- player -> playerData
local heartbeatConnection = nil
local Checkpoints = workspace:WaitForChild("Checkpoints") -- Reference to checkpoints folder
local checkpointCooldowns = {} -- cooldownKey -> lastTouchTime

-- Initialize server
function MainServer.Init()
    print("[MainServer] Initializing Unified System v1.2 (Hybrid)")

    -- Setup player connections
    Players.PlayerAdded:Connect(MainServer.OnPlayerAdded)
    Players.PlayerRemoving:Connect(MainServer.OnPlayerRemoving)

    -- Setup remote event connections
    RemoteEvents.OnToggleRequested(MainServer.OnSprintToggleRequested)
    RemoteEvents.OnCheckpointTouched(MainServer.OnCheckpointTouched)

    -- Setup physical checkpoint touch detection
    MainServer.SetupCheckpointTouches()

    -- Start anti-cheat heartbeat
    MainServer.StartHeartbeat()

    print("[MainServer] Unified System initialized successfully")
end

-- Setup checkpoint touch detection
function MainServer.SetupCheckpointTouches()
    for i, checkpoint in pairs(Checkpoints:GetChildren()) do
        checkpoint.Touched:Connect(function(hit)
            if hit.Parent:FindFirstChild("Humanoid") then
                local character = hit.Parent
                local player = Players:GetPlayerFromCharacter(character)
                
                if player then
                    MainServer.OnCheckpointTouched(player, checkpoint)
                end
            end)
        end)
    end
    print("[MainServer] Checkpoint touch detection setup complete")
end

-- Create leaderstats for player
function MainServer.CreateLeaderstats(player)
    local leaderstats = Instance.new("Folder")
    leaderstats.Name = "leaderstats"
    leaderstats.Parent = player
    
    local checkpointValue = Instance.new("IntValue")
    checkpointValue.Name = "CP"
    checkpointValue.Value = 0 -- Start at 0, will be updated when checkpoint is touched
    checkpointValue.Parent = leaderstats
    
    print(string.format("[MainServer] Leaderstats created for %s", player.Name))
    return checkpointValue
end

-- Handle player joining
function MainServer.OnPlayerAdded(player)
    print("[MainServer] Player joined:", player.Name)

    -- Create leaderstats
    local checkpointValue = MainServer.CreateLeaderstats(player)

    -- Create player data
    local playerData = DataManager.CreatePlayerData(player)
    activePlayers[player] = playerData

    -- Load saved data
    DataManager.LoadPlayerData(player)

    -- Sync leaderstats with saved checkpoint data
    local savedCheckpoint = playerData.currentCheckpoint
    if savedCheckpoint then
        checkpointValue.Value = savedCheckpoint
    end

    -- Wait for character and setup
    player.CharacterAdded:Connect(function(character)
        MainServer.SetupCharacter(player, character)
    end)

    -- If character already exists
    if player.Character then
        MainServer.SetupCharacter(player, player.Character)
    end
end

-- Setup character connections
function MainServer.SetupCharacter(player, character)
    local playerData = activePlayers[player]
    if not playerData then return end

    -- Wait a frame to ensure character is fully loaded
    task.wait(0.1)

    playerData.character = character
    local humanoid = character:FindFirstChild("Humanoid")
    if humanoid then
        playerData.humanoid = humanoid

        -- Apply saved sprint state
        local targetSpeed = playerData.isSprinting and Config.SPRINT_SPEED or Config.NORMAL_SPEED
        humanoid.WalkSpeed = targetSpeed

        -- Respawn at last checkpoint if available
        if playerData.spawnPosition then
            character:MoveTo(playerData.spawnPosition)
            print(string.format("[MainServer] %s respawned at checkpoint %d", 
                player.Name, playerData.currentCheckpoint or 0))
        end

        -- Force sync to client multiple times to ensure delivery
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

        print(string.format("[MainServer] Character setup for %s - sprint state: %s (speed: %d)",
            player.Name, playerData.isSprinting and "ON" or "OFF", targetSpeed))
    end

    -- Handle character death
    humanoid.Died:Connect(function()
        MainServer.OnCharacterDied(player)
    end)
end

-- Handle character death
function MainServer.OnCharacterDied(player)
    local playerData = activePlayers[player]
    if not playerData then return end

    -- Update death count
    DataManager.UpdateDeathCount(player)

    -- Keep sprint state for next respawn
    playerData.character = nil
    playerData.humanoid = nil

    print(string.format("[MainServer] %s died - sprint state preserved: %s (total deaths: %d)",
        player.Name, playerData.isSprinting and "ON" or "OFF", playerData.deathCount or 0))
end

-- Handle player leaving
function MainServer.OnPlayerRemoving(player)
    print("[MainServer] Player leaving:", player.Name)

    local playerData = activePlayers[player]
    if playerData then
        -- Save data
        DataManager.SavePlayerData(player)
        -- Cleanup
        DataManager.CleanupPlayerData(player)
        activePlayers[player] = nil
    end
end

-- Handle sprint toggle request
function MainServer.OnSprintToggleRequested(player, requestedState)
    local validation = MainServer.ValidateSprintToggleRequest(player, requestedState)

    if validation.success then
        -- Apply speed change
        local humanoid = validation.playerData.humanoid
        humanoid.WalkSpeed = validation.targetSpeed

        -- Update data
        DataManager.UpdateSprintState(player, requestedState)

        -- Send sync to client
        RemoteEvents.SendSync(player, {
            isSprinting = requestedState,
            currentSpeed = validation.targetSpeed,
            timestamp = tick()
        })

        print(string.format("[MainServer] Sprint %s for %s (speed: %d)",
            requestedState and "enabled" or "disabled", player.Name, validation.targetSpeed))
    else
        warn(string.format("[MainServer] Toggle rejected for %s: %s",
            player.Name, validation.reason))

        -- Send current state back to client even if rejected
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

-- Handle checkpoint touch (server-side only - no remote events)
function MainServer.OnCheckpointTouched(player, checkpointPart)
    -- Extract checkpoint ID from part name (e.g., "Checkpoint1" -> 1)
    local checkpointId = tonumber(string.match(checkpointPart.Name, "Checkpoint(%d+)"))
    if not checkpointId then
        warn("[MainServer] Invalid checkpoint name:", checkpointPart.Name)
        return
    end

    -- Validate distance (25 studs max)
    local playerData = activePlayers[player]
    if not playerData or not playerData.character then return end

    local distance = (checkpointPart.Position - playerData.character.HumanoidRootPart.Position).Magnitude
    if distance > Config.MAX_DISTANCE_STUDS then
        warn(string.format("[MainServer] %s tried to touch checkpoint from too far: %.1f studs", player.Name, distance))
        return
    end

    -- Check cooldown per checkpoint per player
    local cooldownKey = string.format("%s_%d", player.UserId, checkpointId)
    local lastTouch = checkpointCooldowns[cooldownKey]
    if lastTouch and tick() - lastTouch < Config.TOUCH_COOLDOWN then
        return -- Still in cooldown
    end

    -- Update cooldown
    checkpointCooldowns[cooldownKey] = tick()

    print(string.format("[MainServer] %s touched checkpoint %d", player.Name, checkpointId))

    -- Update checkpoint data
    DataManager.UpdateCheckpointData(player, checkpointId, checkpointPart.Position + Config.CHECKPOINT_SPAWN_OFFSET)

    -- Update leaderstats
    MainServer.UpdateLeaderstats(player)

    -- Send sync to client
    local playerData = DataManager.GetPlayerData(player)
    RemoteEvents.SendCheckpointSync(player, {
        currentCheckpoint = playerData.currentCheckpoint,
        checkpointHistory = playerData.checkpointHistory,
        spawnPosition = playerData.spawnPosition,
    })
end

-- Update leaderstats for player
function MainServer.UpdateLeaderstats(player)
    local leaderstats = player:FindFirstChild("leaderstats")
    if not leaderstats then return end

    local checkpointValue = leaderstats:FindFirstChild("CP")
    if not checkpointValue then return end

    local playerData = DataManager.GetPlayerData(player)
    if playerData then
        checkpointValue.Value = playerData.currentCheckpoint or 0
    end
end

-- Validate sprint toggle request
function MainServer.ValidateSprintToggleRequest(player, requestedState)
    local response = table.clone(SharedTypes.ValidationResponse)
    response.success = false
    response.reason = SharedTypes.ValidationResult.INVALID_REQUEST
    response.targetSpeed = Config.NORMAL_SPEED

    -- Basic type validation
    if typeof(requestedState) ~= "boolean" then
        response.reason = SharedTypes.ValidationResult.INVALID_REQUEST
        return response
    end

    -- Check if player exists
    if not player or not player:IsA("Player") then
        response.reason = SharedTypes.ValidationResult.PLAYER_NOT_FOUND
        return response
    end

    -- Get player data
    local playerData = DataManager.GetPlayerData(player)
    if not playerData then
        response.reason = SharedTypes.ValidationResult.PLAYER_NOT_FOUND
        return response
    end

    -- Check character and humanoid
    if not playerData.character or not playerData.humanoid then
        response.reason = SharedTypes.ValidationResult.CHARACTER_NOT_FOUND
        return response
    end

    -- Rate limiting check
    local timeSinceLastToggle = tick() - playerData.lastToggleTime
    if timeSinceLastToggle < Config.DEBOUNCE_TIME then
        response.reason = SharedTypes.ValidationResult.DEBOUNCE_ACTIVE
        return response
    end

    -- All checks passed
    response.success = true
    response.reason = SharedTypes.ValidationResult.SUCCESS
    response.playerData = playerData
    response.targetSpeed = requestedState and Config.SPRINT_SPEED or Config.NORMAL_SPEED

    return response
end

-- Start anti-cheat heartbeat (optimized - check only moving players)
function MainServer.StartHeartbeat()
    heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
        MainServer.CheckSpeedIntegrity()
    end)
end

-- Check speed integrity for all players
function MainServer.CheckSpeedIntegrity()
    for player, playerData in pairs(activePlayers) do
        if playerData.humanoid and tick() - playerData.lastSpeedCheck > Config.HEARTBEAT_CHECK_INTERVAL then
            local needsCorrection = MainServer.CheckPlayerSpeedIntegrity(player)

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
                warn(string.format("[MainServer] Speed corrected for %s (violations: %d)",
                    player.Name, playerData.speedViolations))
            end

            playerData.lastSpeedCheck = tick()
        end
    end
end

-- Check speed integrity for a player
function MainServer.CheckPlayerSpeedIntegrity(player)
    local playerData = DataManager.GetPlayerData(player)
    if not playerData or not playerData.humanoid then
        return false
    end

    local actualSpeed = playerData.humanoid.WalkSpeed
    local expectedSpeed = playerData.isSprinting and Config.SPRINT_SPEED or Config.NORMAL_SPEED

    local difference = math.abs(actualSpeed - expectedSpeed)
    return difference > Config.SPEED_TOLERANCE
end

-- Cleanup on server shutdown
function MainServer.Cleanup()
    if heartbeatConnection then
        heartbeatConnection:Disconnect()
        heartbeatConnection = nil
    end

    -- Save all player data
    for player in pairs(activePlayers) do
        DataManager.SavePlayerData(player)
    end

    -- Clear character references to prevent memory leaks
    for player, playerData in pairs(activePlayers) do
        playerData.character = nil
        playerData.humanoid = nil
    end

    activePlayers = {}
    checkpointCooldowns = {}
end

-- Initialize when script runs
MainServer.Init()

-- Handle server shutdown
game:BindToClose(function()
    MainServer.Cleanup()
end)

return MainServer
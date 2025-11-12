-- Checkpoint System V1.0 - Respawn Handler
-- Handles player death detection and respawn logic

local Players = game:GetService("Players")
local Settings = require(game.ReplicatedStorage.CheckpointSystem.Config.Settings)

local RespawnHandler = {}

-- Private variables
local deathConnections = {} -- {player: connection}
local characterConnections = {} -- {player: {connections}}
local isInitialized = false

-- Logger utility
local function Log(level, message, ...)
	if not Settings.DEBUG_MODE and level == "DEBUG" then return end

	local prefix = "[RespawnHandler]"
	if level == "ERROR" then
		warn(prefix .. " " .. string.format(message, ...))
	elseif level == "WARN" then
		warn(prefix .. " " .. string.format(message, ...))
	elseif level == "INFO" or (Settings.DEBUG_MODE and level == "DEBUG") then
		print(prefix .. " " .. string.format(message, ...))
	end
end

-- Initialize the respawn handler
function RespawnHandler.Initialize()
	if isInitialized then
		Log("WARN", "RespawnHandler already initialized")
		return true
	end

	Log("INFO", "Initializing RespawnHandler...")

	-- Set up player connections
	Players.PlayerAdded:Connect(OnPlayerAdded)
	Players.PlayerRemoving:Connect(OnPlayerRemoving)

	isInitialized = true
	Log("INFO", "RespawnHandler initialized successfully")
	return true
end

-- Handle player joining
function OnPlayerAdded(player)
	if not isInitialized then return end

	Log("DEBUG", "Setting up respawn handling for %s", player.Name)

	-- Set up death detection
	SetupDeathDetection(player)

	-- Set up character connections
	SetupCharacterConnections(player)
end

-- Handle player leaving
function OnPlayerRemoving(player)
	if not isInitialized then return end

	CleanupPlayerConnections(player)
end

-- Set up death detection for player
function SetupDeathDetection(player)
	-- Clean up existing connection
	if deathConnections[player] then
		deathConnections[player]:Disconnect()
	end

	-- Connect to character events
	deathConnections[player] = player.CharacterAdded:Connect(function(character)
		SetupCharacterDeathDetection(player, character)
	end)

	-- Set up for current character
	if player.Character then
		SetupCharacterDeathDetection(player, player.Character)
	end
end

-- Set up death detection for specific character
function SetupCharacterDeathDetection(player, character)
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then
		Log("WARN", "No humanoid found in character for %s", player.Name)
		return
	end

	-- Connect to death event
	humanoid.Died:Connect(function()
		HandlePlayerDeath(player, character)
	end)

	Log("DEBUG", "Death detection set up for %s", player.Name)
end

function HandlePlayerDeath(player, character)
	if not isInitialized then return end

	local userId = player.UserId
	Log("INFO", "Player %s died", player.Name)

	-- Update death count via global module (fixed circular dependency)
	local deathCount = 0

	if _G.CheckpointServerMain then
		deathCount = _G.CheckpointServerMain.UpdatePlayerDeathCount(userId)
	else
		-- Fallback: use player attribute
		deathCount = (player:GetAttribute("DeathCount") or 0) + 1
		player:SetAttribute("DeathCount", deathCount)
		Log("WARN", "ServerMain not available, using fallback death count: %d", deathCount)
	end

	-- Wait for character removal or position check
	task.delay(0.1, function()
		RespawnHandler.RespawnPlayer(player, deathCount)
	end)
end

function RespawnHandler.RespawnPlayer(player, deathCount)
    if not player or not player:IsA("Player") then
        Log("ERROR", "Invalid player for respawn")
        return false
    end

    local userId = player.UserId
    Log("DEBUG", "Respawning %s (death count: %d)", player.Name, deathCount)

    -- Get current checkpoint via global module
    local checkpointOrder = 0
    
    if _G.CheckpointServerMain then
        checkpointOrder = _G.CheckpointServerMain.GetPlayerCheckpoint(userId)
    else
        checkpointOrder = player:GetAttribute("CurrentCheckpoint") or 0
        Log("WARN", "ServerMain not available, using fallback checkpoint: %d", checkpointOrder)
    end

    -- NEW PLAYER (No Checkpoint Data): Let Roblox handle default spawn
    if checkpointOrder == 0 then
        Log("INFO", "Player %s has no checkpoint data - using default spawn location", player.Name)
        return true
    end

    -- ============================================================
    -- FIX: Death loop protection - minimum checkpoint is 1, not 0!
    -- ============================================================
    if Settings.ENABLE_DEATH_LOOP_PROTECTION and deathCount >= Settings.DEATH_LOOP_THRESHOLD then
        local fallbackCheckpoint = math.max(1, checkpointOrder - Settings.DEATH_LOOP_FALLBACK_STEPS)
        
        Log("WARN", "Death loop protection activated for %s, falling back from checkpoint %d to %d",
            player.Name, checkpointOrder, fallbackCheckpoint)
        
        checkpointOrder = fallbackCheckpoint  -- ✅ Minimum is 1, not 0!
    end
    -- ============================================================

    -- Get spawn position
    local CheckpointManager = require(game.ReplicatedStorage.CheckpointSystem.Modules.CheckpointManager)
    local spawnPosition = CheckpointManager.GetSpawnPosition(checkpointOrder)

    if not spawnPosition then
        Log("ERROR", "No spawn position found for checkpoint %d", checkpointOrder)
        
        -- FALLBACK: Try checkpoint 1
        Log("INFO", "Trying fallback to checkpoint 1...")
        spawnPosition = CheckpointManager.GetSpawnPosition(1)
        
        if not spawnPosition then
            Log("WARN", "Checkpoint 1 also not found, using default spawn")
            return true  -- Let default spawn happen
        else
            Log("INFO", "Using checkpoint 1 as fallback")
        end
    end

    -- Validate spawn position (optional - can disable if causing issues)
    if Settings.ENABLE_SPAWN_VALIDATION then
        spawnPosition = RespawnHandler.ValidateSpawnPosition(spawnPosition)
    end

    -- WAIT FOR CHARACTER AND TELEPORT
    task.spawn(function()
        local character = RespawnHandler.WaitForCharacterLoad(player, Settings.CHARACTER_LOAD_TIMEOUT)

        if not character then
            Log("ERROR", "Character failed to load for %s within timeout", player.Name)
            return
        end

        task.wait(0.3)

        local success = RespawnHandler.TeleportCharacter(character, spawnPosition)
        
        if success then
            Log("INFO", "Player %s respawned at checkpoint %d", player.Name, checkpointOrder)
            
            if Settings.ENABLE_DEATH_LOOP_PROTECTION and deathCount >= Settings.DEATH_LOOP_THRESHOLD then
                RespawnHandler.ApplyTemporaryShield(character)
            end
        else
            Log("ERROR", "Failed to teleport %s to checkpoint %d", player.Name, checkpointOrder)
        end
    end)

    return true
end

-- Validate spawn position for safety
function RespawnHandler.ValidateSpawnPosition(position, skipRecursion)
	if not position then return Vector3.new(0, 10, 0) end

	-- Check ground
	local rayOrigin = position + Vector3.new(0, 1, 0)
	local rayDirection = Vector3.new(0, -Settings.SPAWN_RAYCAST_DISTANCE_DOWN, 0)

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
	raycastParams.FilterDescendantsInstances = {}

	local raycastResult = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

	if not raycastResult then
		Log("WARN", "No ground found at spawn position")

		-- Only try to find nearby position if not already in recursion
		if not skipRecursion then
			return RespawnHandler.FindNearbyValidPosition(position)
		else
			-- Fallback: just add some height
			return position + Vector3.new(0, 5, 0)
		end
	end

	-- Adjust position to be on ground
	local groundPosition = raycastResult.Position + Vector3.new(0, 3, 0)

	-- Check ceiling
	local ceilingRay = workspace:Raycast(
		groundPosition + Vector3.new(0, 1, 0), 
		Vector3.new(0, Settings.SPAWN_RAYCAST_DISTANCE_UP, 0),
		raycastParams
	)

	if ceilingRay then
		Log("WARN", "Ceiling too low at spawn position")

		if not skipRecursion then
			return RespawnHandler.FindNearbyValidPosition(position)
		else
			return groundPosition
		end
	end

	-- Check walls in 4 directions
	local directions = {
		Vector3.new(1, 0, 0),
		Vector3.new(-1, 0, 0),
		Vector3.new(0, 0, 1),
		Vector3.new(0, 0, -1)
	}

	for _, direction in ipairs(directions) do
		local wallRay = workspace:Raycast(
			groundPosition + Vector3.new(0, 1, 0), 
			direction * Settings.SPAWN_RAYCAST_DISTANCE_WALL,
			raycastParams
		)

		if wallRay then
			Log("WARN", "Wall too close at spawn position")

			if not skipRecursion then
				return RespawnHandler.FindNearbyValidPosition(position)
			else
				return groundPosition
			end
		end
	end

	Log("DEBUG", "Spawn position validated")
	return groundPosition
end

-- ============================================================
-- FIXED: FindNearbyValidPosition (WITH RECURSION PROTECTION!)
-- ============================================================
function RespawnHandler.FindNearbyValidPosition(centerPosition)
	Log("DEBUG", "Searching for nearby valid position from %s", tostring(centerPosition))

	local angle = 0
	local radius = Settings.SPAWN_VALIDATION_RADIUS_START

	while radius <= Settings.SPAWN_VALIDATION_RADIUS_END do
		for i = 1, 8 do -- 8 directions per radius
			local radians = math.rad(angle)
			local offset = Vector3.new(
				math.cos(radians) * radius,
				0,
				math.sin(radians) * radius
			)

			local testPosition = centerPosition + offset

			-- CRITICAL FIX: Pass skipRecursion=true to prevent infinite loop!
			local validatedPosition = RespawnHandler.ValidateSpawnPosition(testPosition, true)

			-- Check if position was actually validated (has ground)
			local rayOrigin = validatedPosition + Vector3.new(0, 1, 0)
			local rayDirection = Vector3.new(0, -10, 0)

			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
			raycastParams.FilterDescendantsInstances = {}

			local hasGround = workspace:Raycast(rayOrigin, rayDirection, raycastParams)

			if hasGround then
				Log("DEBUG", "Found valid position at radius %d", radius)
				return validatedPosition
			end

			angle = angle + 45 -- 45-degree steps
		end

		radius = radius + Settings.SPAWN_VALIDATION_RADIUS_STEP
	end

	Log("WARN", "No valid position found in search radius, using original position with offset")
	return centerPosition + Vector3.new(0, 10, 0) -- Safe fallback: just add height
end

-- Wait for character to load
function RespawnHandler.WaitForCharacterLoad(player, timeout)
	local startTime = tick()

	while tick() - startTime < timeout do
		if player.Character and player.Character:IsDescendantOf(workspace) then
			local humanoid = player.Character:FindFirstChild("Humanoid")
			if humanoid and humanoid.Health > 0 then
				return player.Character
			end
		end
		wait(0.1)
	end

	return nil
end

-- Teleport character to position
function RespawnHandler.TeleportCharacter(character, position)
	if not character or not character:IsA("Model") then
		Log("ERROR", "Invalid character for teleport")
		return false
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart then
		Log("ERROR", "No HumanoidRootPart found in character")
		return false
	end

	-- Set position
	humanoidRootPart.CFrame = CFrame.new(position)

	-- Reset character state
	local humanoid = character:FindFirstChild("Humanoid")
	if humanoid then
		humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		wait(0.1)
		humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
	end

	Log("DEBUG", "Character teleported to %s", tostring(position))
	return true
end

-- Apply temporary shield/invulnerability
function RespawnHandler.ApplyTemporaryShield(character)
	if not character then return end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return end

	-- Create shield effect (visual)
	local shieldPart = Instance.new("Part")
	shieldPart.Name = "DeathLoopShield"
	shieldPart.Size = Vector3.new(6, 6, 6)
	shieldPart.Shape = Enum.PartType.Ball
	shieldPart.Anchored = true
	shieldPart.CanCollide = false
	shieldPart.Transparency = 0.7
	shieldPart.Material = Enum.Material.ForceField
	shieldPart.BrickColor = BrickColor.new("Bright blue")

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart then
		shieldPart.CFrame = humanoidRootPart.CFrame
		shieldPart.Parent = character

		-- Follow character
		local connection
		connection = game:GetService("RunService").Heartbeat:Connect(function()
			if humanoidRootPart and humanoidRootPart:IsDescendantOf(workspace) then
				shieldPart.CFrame = humanoidRootPart.CFrame
			else
				connection:Disconnect()
				shieldPart:Destroy()
			end
		end)

		-- Remove after duration
		delay(Settings.TEMPORARY_SHIELD_DURATION, function()
			if connection then connection:Disconnect() end
			if shieldPart and shieldPart.Parent then
				shieldPart:Destroy()
			end
		end)
	end

	Log("DEBUG", "Temporary shield applied for %d seconds", Settings.TEMPORARY_SHIELD_DURATION)
end

-- Set up character-specific connections
function SetupCharacterConnections(player)
	-- Clean up existing connections
	if characterConnections[player] then
		for _, connection in ipairs(characterConnections[player]) do
			connection:Disconnect()
		end
	end

	characterConnections[player] = {}

	-- Monitor for falling out of map
	local connection = player.CharacterAdded:Connect(function(character)
		local rootPart = character:WaitForChild("HumanoidRootPart", 5)
		if rootPart then
			table.insert(characterConnections[player], rootPart:GetPropertyChangedSignal("Position"):Connect(function()
				if rootPart.Position.Y < -100 then
					HandlePlayerDeath(player, character)
				end
			end))
		end
	end)

	table.insert(characterConnections[player], connection)
end

-- Cleanup player connections
function CleanupPlayerConnections(player)
	if deathConnections[player] then
		deathConnections[player]:Disconnect()
		deathConnections[player] = nil
	end

	if characterConnections[player] then
		for _, connection in ipairs(characterConnections[player]) do
			connection:Disconnect()
		end
		characterConnections[player] = nil
	end

	Log("DEBUG", "Connections cleaned up for %s", player.Name)
end

-- Force respawn player (for testing)
function RespawnHandler.ForceRespawn(player)
	if not Settings.DEBUG_MODE then
		Log("WARN", "Force respawn called outside debug mode")
		return false
	end

	return RespawnHandler.RespawnPlayer(player, 0)
end

-- Get respawn status
function RespawnHandler.GetRespawnStatus()
	return {
		Initialized = isInitialized,
		ActiveConnections = 0
	}
end

-- Cleanup function
function RespawnHandler.Cleanup()
	-- Cleanup all connections
	for player, _ in pairs(deathConnections) do
		CleanupPlayerConnections(player)
	end

	deathConnections = {}
	characterConnections = {}
	isInitialized = false
	Log("INFO", "RespawnHandler cleaned up")
end

return RespawnHandler
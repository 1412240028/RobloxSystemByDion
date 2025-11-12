-- Checkpoint System V1.0 - Effects Controller Module
-- Handles visual and audio effects for checkpoints

local TweenService = game:GetService("TweenService")
local Settings = require(game.ReplicatedStorage.CheckpointSystem.Config.Settings)

local EffectsController = {}

-- Private variables
local particlePool = {} -- Object pool for particles
local activeEffects = {} -- {checkpointPart: effectData}
local isInitialized = false

-- Logger utility
local function Log(level, message, ...)
	if not Settings.DEBUG_MODE and level == "DEBUG" then return end

	local prefix = "[EffectsController]"
	if level == "ERROR" then
		warn(prefix .. " " .. string.format(message, ...))
	elseif level == "WARN" then
		warn(prefix .. " " .. string.format(message, ...))
	elseif level == "INFO" or (Settings.DEBUG_MODE and level == "DEBUG") then
		print(prefix .. " " .. string.format(message, ...))
	end
end

-- Initialize the effects controller
function EffectsController.Initialize()
	if isInitialized then
		Log("WARN", "EffectsController already initialized")
		return true
	end

	Log("INFO", "Initializing EffectsController...")

	-- Pre-populate particle pool
	EffectsController.InitializeParticlePool()

	isInitialized = true
	Log("INFO", "EffectsController initialized successfully")
	return true
end

-- Initialize particle pool for performance
function EffectsController.InitializeParticlePool()
	Log("DEBUG", "Initializing particle pool with %d particles", Settings.PARTICLE_POOL_SIZE)

	for i = 1, Settings.PARTICLE_POOL_SIZE do
		local particle = EffectsController.CreateParticleEmitter()
		particle.Enabled = false
		particle.Parent = game.ReplicatedStorage -- Store in ReplicatedStorage temporarily
		table.insert(particlePool, particle)
	end

	Log("DEBUG", "Particle pool initialized")
end

-- Create a particle emitter
function EffectsController.CreateParticleEmitter()
	local emitter = Instance.new("ParticleEmitter")

	-- Configure particle appearance
	emitter.Texture = "rbxassetid://241685484" -- Default sparkle texture
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(1, 0)
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1)
	})
	emitter.Lifetime = NumberRange.new(1, 1.5)
	emitter.Rate = 50
	emitter.Speed = NumberRange.new(5, 10)
	emitter.SpreadAngle = Vector2.new(-180, 180)
	emitter.Color = ColorSequence.new(Color3.fromRGB(0, 170, 255))

	return emitter
end

-- Get particle from pool
function EffectsController.GetParticleFromPool()
	-- Find disabled particle
	for _, particle in ipairs(particlePool) do
		if not particle.Enabled then
			return particle
		end
	end

	-- Create new particle if pool is empty
	Log("WARN", "Particle pool exhausted, creating new particle")
	local newParticle = EffectsController.CreateParticleEmitter()
	table.insert(particlePool, newParticle)
	return newParticle
end

-- Return particle to pool
function EffectsController.ReturnParticleToPool(particle)
	if particle and particle:IsA("ParticleEmitter") then
		particle.Enabled = false
		particle.Parent = game.ReplicatedStorage
	end
end

-- Play checkpoint glow effect
function EffectsController.PlayCheckpointGlow(checkpointPart)
	if not isInitialized or not checkpointPart or not checkpointPart:IsA("BasePart") then
		Log("ERROR", "Invalid parameters for checkpoint glow")
		return false
	end

	-- Create or get existing glow effect
	local glowEffect = checkpointPart:FindFirstChild("CheckpointGlow")
	if not glowEffect then
		glowEffect = Instance.new("Highlight")
		glowEffect.Name = "CheckpointGlow"
		glowEffect.FillColor = Color3.fromRGB(0, 170, 255)
		glowEffect.OutlineColor = Color3.fromRGB(255, 255, 255)
		glowEffect.FillTransparency = 0.5
		glowEffect.OutlineTransparency = 0
		glowEffect.Parent = checkpointPart
	end

	-- Animate glow
	local tweenInfo = TweenInfo.new(
		Settings.CHECKPOINT_GLOW_DURATION,
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		0,
		true -- Repeat
	)

	local tween = TweenService:Create(glowEffect, tweenInfo, {
		FillTransparency = 0.8,
		OutlineTransparency = 0.3
	})

	tween:Play()

	-- Store effect data
	activeEffects[checkpointPart] = {
		Type = "glow",
		Tween = tween,
		StartTime = tick()
	}

	Log("DEBUG", "Playing glow effect on checkpoint")
	return true
end

-- Play particle effect
function EffectsController.PlayParticleEffect(checkpointPart)
	if not isInitialized or not checkpointPart or not checkpointPart:IsA("BasePart") then
		Log("ERROR", "Invalid parameters for particle effect")
		return false
	end

	-- Get particle from pool
	local particle = EffectsController.GetParticleFromPool()
	if not particle then
		Log("ERROR", "Failed to get particle from pool")
		return false
	end

	-- Position particle
	particle.Parent = checkpointPart
	particle.Enabled = true

	-- Auto-disable after lifetime
	delay(particle.Lifetime.Max, function()
		EffectsController.ReturnParticleToPool(particle)
	end)

	-- Store effect data
	activeEffects[checkpointPart] = activeEffects[checkpointPart] or {}
	activeEffects[checkpointPart].Particle = particle

	Log("DEBUG", "Playing particle effect on checkpoint")
	return true
end

-- Play checkpoint reached effects
function EffectsController.PlayCheckpointEffects(checkpointPart)
	if not checkpointPart then
		Log("ERROR", "No checkpoint part provided")
		return false
	end

	-- Play glow effect
	EffectsController.PlayCheckpointGlow(checkpointPart)

	-- Play particle effect
	EffectsController.PlayParticleEffect(checkpointPart)

	-- Play sound effect
	EffectsController.PlaySoundEffect(checkpointPart)

	Log("INFO", "Playing all checkpoint effects")
	return true
end

-- Play sound effect
function EffectsController.PlaySoundEffect(checkpointPart)
	if not checkpointPart then return false end

	-- Create sound
	local sound = Instance.new("Sound")
	sound.Name = "CheckpointSound"
	sound.SoundId = "rbxassetid://9120386436" -- ← FIX INI!
	sound.Volume = Settings.AUDIO_VOLUME
	sound.PlaybackSpeed = 1 + math.random(-Settings.AUDIO_PITCH_VARIATION, Settings.AUDIO_PITCH_VARIATION)
	sound.Parent = checkpointPart

	-- Play and cleanup
	sound:Play()
	sound.Ended:Wait()
	sound:Destroy()

	Log("DEBUG", "Played sound effect")
	return true
end

-- Stop effects for checkpoint
function EffectsController.StopCheckpointEffects(checkpointPart)
	if not checkpointPart or not activeEffects[checkpointPart] then
		return false
	end

	local effectData = activeEffects[checkpointPart]

	-- Stop glow effect
	if effectData.Tween then
		effectData.Tween:Cancel()
	end

	local glowEffect = checkpointPart:FindFirstChild("CheckpointGlow")
	if glowEffect then
		glowEffect:Destroy()
	end

	-- Stop particle effect
	if effectData.Particle then
		EffectsController.ReturnParticleToPool(effectData.Particle)
	end

	-- Stop sound effect
	local sound = checkpointPart:FindFirstChild("CheckpointSound")
	if sound then
		sound:Stop()
		sound:Destroy()
	end

	activeEffects[checkpointPart] = nil
	Log("DEBUG", "Stopped effects for checkpoint")
	return true
end

-- Stop all active effects
function EffectsController.StopAllEffects()
	for checkpointPart, _ in pairs(activeEffects) do
		EffectsController.StopCheckpointEffects(checkpointPart)
	end

	activeEffects = {}
	Log("INFO", "Stopped all effects")
end

-- Update particle pool size
function EffectsController.UpdateParticlePoolSize(newSize)
	if newSize <= 0 then
		Log("ERROR", "Invalid particle pool size: %d", newSize)
		return false
	end

	local currentSize = #particlePool

	if newSize > currentSize then
		-- Add more particles
		for i = currentSize + 1, newSize do
			local particle = EffectsController.CreateParticleEmitter()
			particle.Enabled = false
			particle.Parent = game.ReplicatedStorage
			table.insert(particlePool, particle)
		end
		Log("INFO", "Expanded particle pool to %d", newSize)
	elseif newSize < currentSize then
		-- Remove excess particles (only disabled ones)
		local newPool = {}
		local removed = 0
		for _, particle in ipairs(particlePool) do
			if #newPool < newSize and not particle.Enabled then
				table.insert(newPool, particle)
			elseif particle.Enabled then
				table.insert(newPool, particle) -- Keep enabled particles
			else
				particle:Destroy()
				removed = removed + 1
			end
		end
		particlePool = newPool
		Log("INFO", "Shrunk particle pool to %d (removed %d)", #particlePool, removed)
	end

	return true
end

-- Get effects status
function EffectsController.GetEffectsStatus()
	local status = {
		PoolSize = #particlePool,
		ActiveEffects = 0,
		PoolUtilization = 0
	}

	for _, effectData in pairs(activeEffects) do
		status.ActiveEffects = status.ActiveEffects + 1
	end

	if #particlePool > 0 then
		status.PoolUtilization = status.ActiveEffects / #particlePool
	end

	return status
end

-- Test effects (for debugging)
function EffectsController.TestEffects(checkpointPart)
	if not Settings.DEBUG_MODE then
		Log("WARN", "Test effects called outside debug mode")
		return
	end

	if not checkpointPart then
		Log("ERROR", "No checkpoint part provided for testing")
		return
	end

	EffectsController.PlayCheckpointEffects(checkpointPart)
	Log("INFO", "Test effects played on checkpoint")
end

-- Cleanup function
function EffectsController.Cleanup()
	-- Stop all effects
	EffectsController.StopAllEffects()

	-- Clean up particle pool
	for _, particle in ipairs(particlePool) do
		particle:Destroy()
	end
	particlePool = {}

	activeEffects = {}
	isInitialized = false
	Log("INFO", "EffectsController cleaned up")
end

return EffectsController

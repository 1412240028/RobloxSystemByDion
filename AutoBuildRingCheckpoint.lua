-- CheckpointRingBuilder.lua - ROUNDED CORNERS VERSION
-- COMMAND BAR VERSION - Frame dengan sudut tumpul/rounded
-- Copy paste ke Command Bar di Roblox Studio

local Workspace = game:GetService("Workspace")

local CheckpointBuilder = {}

	print("🚀 Starting Checkpoint Builder...")

-- Configuration
local CONFIG = {
	CHECKPOINT_COUNT = 5,           -- Jumlah checkpoint
	SPACING = 50,                   -- Jarak antar checkpoint (studs)
	RING_SIZE = 10,                 -- Ukuran ring (height & width)
	BAR_THICKNESS = 1,              -- Ketebalan frame ring
	WALL_THICKNESS = 0.2,           -- Ketebalan wall transparan
	WALL_TRANSPARENCY = 0.7,        -- Transparansi wall
	START_POSITION = Vector3.new(26, 13.55, 0),  -- Posisi checkpoint pertama
	DIRECTION = Vector3.new(1, 0, 0),        -- Arah checkpoint (X axis)
	AUTO_DELETE_OLD = true,         -- Auto hapus checkpoint lama
	
	-- ✨ NEW: Rounded corner settings
	USE_CYLINDERS = true,           -- true = pake cylinder (rounded), false = part (kotak)
	ADD_CORNER_SPHERES = true,      -- true = tambahin sphere di sudut buat extra smooth
	CORNER_SPHERE_SIZE = 1,       -- Ukuran sphere di sudut (dikit lebih besar dari thickness)
	-- Note: Bars and spheres removed as per user request
}

-- ✨ Create single ring checkpoint with ROUNDED CORNERS
function CheckpointBuilder.CreateRingCheckpoint(checkpointId, position)
	-- Create Model container
	local model = Instance.new("Model")
	model.Name = "Checkpoint" .. checkpointId
	model.Parent = Workspace:FindFirstChild("Checkpoints") or Workspace

	-- Set checkpoint order attribute
	model:SetAttribute("Order", checkpointId)
	
	local size = CONFIG.RING_SIZE
	local thickness = CONFIG.BAR_THICKNESS
	

	
	-- Create Transparent Wall (the part that detects touch)
	local wall = Instance.new("Part")
	wall.Name = "Wall"
	wall.Size = Vector3.new(12, 27.1, 14.2)
	wall.Position = position
	wall.Orientation = Vector3.new(0, 90, 0)  -- Tengkurap (lying down)
	wall.Anchored = true
	wall.CanCollide = false
	wall.Transparency = CONFIG.WALL_TRANSPARENCY
	wall.Material = Enum.Material.ForceField
	wall.Color = Color3.fromRGB(255, 0, 0)
	wall.Parent = model
	
	-- Add attribute to wall for detection
	wall:SetAttribute("IsCheckpointWall", true)
	
	-- Create PointLight for glow effect
	local light = Instance.new("PointLight")
	light.Brightness = 2
	light.Range = 15
	light.Color = Color3.fromRGB(255, 0, 0)
	light.Parent = wall
	
	-- Set model PrimaryPart
	model.PrimaryPart = wall
	
	print(string.format("[CheckpointBuilder] ✓ Created Checkpoint%d (Rounded) at position (%.1f, %.1f, %.1f)", 
		checkpointId, position.X, position.Y, position.Z))
	
	return model
end

-- Build all checkpoints
function CheckpointBuilder.BuildAllCheckpoints()
	print("========================================")
	print("🔨 CHECKPOINT BUILDER")
	print("========================================")
	
	-- Create or get Checkpoints folder
	local checkpointsFolder = Workspace:FindFirstChild("Checkpoints")
	if not checkpointsFolder then
		checkpointsFolder = Instance.new("Folder")
		checkpointsFolder.Name = "Checkpoints"
		checkpointsFolder.Parent = Workspace
		print("✅ Created Checkpoints folder in Workspace")
	else
		print("📁 Found existing Checkpoints folder")
	end
	
	-- Clear existing checkpoints if AUTO_DELETE_OLD is true
	if CONFIG.AUTO_DELETE_OLD then
		print("🗑️  Deleting old checkpoints...")
		local deletedCount = 0
		for _, child in pairs(checkpointsFolder:GetChildren()) do
			if child:IsA("Model") or child:IsA("Part") then
				child:Destroy()
				deletedCount = deletedCount + 1
			end
		end
		if deletedCount > 0 then
			print(string.format("✅ Deleted %d old checkpoint(s)", deletedCount))
		else
			print("ℹ️  No old checkpoints to delete")
		end
		wait(0.5)
	end
	
	-- Build new checkpoints
	print("🔨 Building new rounded ring checkpoints...")
	if CONFIG.USE_CYLINDERS then
		print("   ✓ Using Cylinders for rounded bars")
	end
	if CONFIG.ADD_CORNER_SPHERES then
		print("   ✓ Adding corner spheres for extra smoothness")
	end
	
	for i = 1, CONFIG.CHECKPOINT_COUNT do
		local offset = CONFIG.DIRECTION * CONFIG.SPACING * (i - 1)
		local position = CONFIG.START_POSITION + offset
		
		CheckpointBuilder.CreateRingCheckpoint(i, position)
		wait(0.05)
	end
	
	print("========================================")
	print(string.format("✅ SUCCESS! Created %d checkpoints", CONFIG.CHECKPOINT_COUNT))
	print("========================================")
	print("📍 Location: Workspace > Checkpoints")
	print("========================================")
end

-- Advanced: Custom path (circle, spiral, etc)
function CheckpointBuilder.BuildCirclePath(centerPosition, radius, checkpointCount)
	print("[CheckpointBuilder] Building circular path with rounded checkpoints...")
	
	local checkpointsFolder = Workspace:FindFirstChild("Checkpoints")
	if not checkpointsFolder then
		checkpointsFolder = Instance.new("Folder")
		checkpointsFolder.Name = "Checkpoints"
		checkpointsFolder.Parent = Workspace
	end
	
	-- Clear old checkpoints if enabled
	if CONFIG.AUTO_DELETE_OLD then
		for _, child in pairs(checkpointsFolder:GetChildren()) do
			if child:IsA("Model") or child:IsA("Part") then
				child:Destroy()
			end
		end
		wait(0.5)
	end
	
	for i = 1, checkpointCount do
		local angle = (i - 1) * (2 * math.pi / checkpointCount)
		local x = centerPosition.X + radius * math.cos(angle)
		local z = centerPosition.Z + radius * math.sin(angle)
		local position = Vector3.new(x, centerPosition.Y, z)
		
		CheckpointBuilder.CreateRingCheckpoint(i, position)
		wait(0.05)
	end
	
	print(string.format("✅ Created %d rounded checkpoints in circle pattern", checkpointCount))
end

-- ✨ AUTO-RUN when pasted in Command Bar
CheckpointBuilder.BuildAllCheckpoints()

-- ✨ Uncomment line di bawah untuk bikin circular path:
-- CheckpointBuilder.BuildCirclePath(Vector3.new(0, 10, 0), 50, 8)
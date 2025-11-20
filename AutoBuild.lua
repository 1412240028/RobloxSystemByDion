-- FinishBuilder.lua - Build Finish Line
-- COMMAND BAR VERSION - Untuk membuat finish line di Roblox
-- Copy paste ke Command Bar di Roblox Studio

local Workspace = game:GetService("Workspace")

local FinishBuilder = {}

print("🚀 Starting Finish Builder...")

-- Configuration
local CONFIG = {
	WALL_SIZE = Vector3.new(12, 27.1, 14.2),  -- Ukuran wall
	WALL_TRANSPARENCY = 0.7,        -- Transparansi wall
	POSITION = Vector3.new(312.9, -4.45, 0),  -- Posisi finish line
	ORIENTATION = Vector3.new(0, 90, 0),   -- Rotasi wall
	AUTO_DELETE_OLD = true,         -- Auto hapus finish line lama
}

-- Create Finish Model
function FinishBuilder.CreateFinish(position)
	-- Create Model container
	local model = Instance.new("Model")
	model.Name = "Finish"
	model.Parent = Workspace
	
	-- Set finish attribute
	model:SetAttribute("IsFinish", true)
	
	-- Create Transparent Wall (the part that detects touch)
	local wall = Instance.new("Part")
	wall.Name = "Wall"
	wall.Size = CONFIG.WALL_SIZE
	wall.Position = position
	wall.Orientation = CONFIG.ORIENTATION
	wall.Anchored = true
	wall.CanCollide = false
	wall.Transparency = CONFIG.WALL_TRANSPARENCY
	wall.Material = Enum.Material.ForceField
	wall.Color = Color3.fromRGB(255, 0, 0)
	wall.Parent = model
	
	-- Add attribute to wall for detection
	wall:SetAttribute("IsFinishWall", true)
	
	-- Set model PrimaryPart
	model.PrimaryPart = wall
	
	print(string.format("[FinishBuilder] ✓ Created Finish at position (%.1f, %.1f, %.1f)", 
		position.X, position.Y, position.Z))
	
	return model
end

-- Build Finish
function FinishBuilder.Build()
	print("========================================")
	print("🏁 FINISH LINE BUILDER")
	print("========================================")
	
	-- Clear existing finish if AUTO_DELETE_OLD is true
	if CONFIG.AUTO_DELETE_OLD then
		local existingFinish = Workspace:FindFirstChild("Finish")
		if existingFinish then
			print("🗑️  Deleting old Finish...")
			existingFinish:Destroy()
			wait(0.2)
		end
	end
	
	-- Build new finish
	print("🔨 Building Finish line...")
	FinishBuilder.CreateFinish(CONFIG.POSITION)
	
	print("========================================")
	print("✅ SUCCESS! Created Finish line")
	print("========================================")
	print("📍 Location: Workspace > Finish")
	print("========================================")
end

-- ✨ AUTO-RUN when pasted in Command Bar
FinishBuilder.Build()

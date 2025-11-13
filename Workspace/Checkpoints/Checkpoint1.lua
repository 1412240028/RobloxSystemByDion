-- Checkpoint1.lua
-- Sample checkpoint part script
-- This is a placeholder - actual checkpoints should be Parts in the workspace

-- Note: This is a script file, but checkpoints should be Parts with Touch events
-- The actual checkpoint logic is handled in MainServer.lua when parts are touched

local checkpointPart = script.Parent

-- Set checkpoint properties
checkpointPart.Name = "1"  -- Checkpoint ID
checkpointPart:SetAttribute("Order", 1)  -- Alternative way to set ID
checkpointPart.Anchored = true
checkpointPart.CanCollide = true
checkpointPart.Size = Vector3.new(4, 8, 4)
checkpointPart.Position = Vector3.new(0, 4, 0)  -- Adjust position as needed
checkpointPart.BrickColor = BrickColor.new("Bright green")
checkpointPart.Material = Enum.Material.Neon

-- Add a glow effect
local glow = Instance.new("PointLight")
glow.Parent = checkpointPart
glow.Brightness = 1
glow.Range = 10
glow.Color = Color3.fromRGB(0, 255, 0)

print("[Checkpoint1] Initialized checkpoint part")

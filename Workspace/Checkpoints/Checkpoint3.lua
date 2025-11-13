-- Checkpoint3.lua
-- Sample checkpoint part script

local checkpointPart = script.Parent

-- Set checkpoint properties
checkpointPart.Name = "3"  -- Checkpoint ID
checkpointPart:SetAttribute("Order", 3)
checkpointPart.Anchored = true
checkpointPart.CanCollide = true
checkpointPart.Size = Vector3.new(4, 8, 4)
checkpointPart.Position = Vector3.new(100, 4, 0)  -- Adjust position as needed
checkpointPart.BrickColor = BrickColor.new("Bright red")
checkpointPart.Material = Enum.Material.Neon

-- Add a glow effect
local glow = Instance.new("PointLight")
glow.Parent = checkpointPart
glow.Brightness = 1
glow.Range = 10
glow.Color = Color3.fromRGB(255, 0, 0)

print("[Checkpoint3] Initialized checkpoint part")

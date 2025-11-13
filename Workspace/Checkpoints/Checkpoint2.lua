-- Checkpoint2.lua
-- Sample checkpoint part script

local checkpointPart = script.Parent

-- Set checkpoint properties
checkpointPart.Name = "2"  -- Checkpoint ID
checkpointPart:SetAttribute("Order", 2)
checkpointPart.Anchored = true
checkpointPart.CanCollide = true
checkpointPart.Size = Vector3.new(4, 8, 4)
checkpointPart.Position = Vector3.new(50, 4, 0)  -- Adjust position as needed
checkpointPart.BrickColor = BrickColor.new("Bright blue")
checkpointPart.Material = Enum.Material.Neon

-- Add a glow effect
local glow = Instance.new("PointLight")
glow.Parent = checkpointPart
glow.Brightness = 1
glow.Range = 10
glow.Color = Color3.fromRGB(0, 0, 255)

print("[Checkpoint2] Initialized checkpoint part")

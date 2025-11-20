-- ResetCheckpointsEvent.lua
-- BindableEvent for resetting player checkpoints to avoid circular dependencies

local ResetCheckpointsEvent = Instance.new("BindableEvent")
ResetCheckpointsEvent.Name = "ResetCheckpointsEvent"
ResetCheckpointsEvent.Parent = script.Parent

return ResetCheckpointsEvent

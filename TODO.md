# Checkpoint Logic Implementation TODO

## Tasks
- [x] Update DataManager.lua to include `checkpointHistory` in player data structure
- [x] Fix MainServer.lua OnCheckpointTouched function to extract checkpointId from checkpointPart and call UpdateCheckpointData correctly
- [x] Create sample checkpoint parts in Workspace/Checkpoints with proper attributes (Order, Position)
- [x] Verify data structure consistency across all modules

## Details
- DataManager: Added checkpointHistory array to track touched checkpoints
- MainServer: Fixed OnCheckpointTouched to extract checkpointId from checkpointPart.Name or checkpointPart:GetAttribute("Order")
- Checkpoints: Created 3 sample checkpoints (Checkpoint1.lua, Checkpoint2.lua, Checkpoint3.lua) with increasing Order values
- Testing: Need to test checkpoint touch events - requires client-side script to fire RemoteEvents when touching parts

## Next Steps
- [x] Update Config.lua version to 1.2.0 and datastore name
- [x] Add UpdateDeathCount() call in OnCharacterDied()
- [ ] Create client-side checkpoint touch detection script
- [ ] Test the complete checkpoint system integration
- [ ] Add checkpoint validation logic (sequential touching, cooldowns)

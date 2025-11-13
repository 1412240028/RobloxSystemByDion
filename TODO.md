# Checkpoint Logic Implementation TODO

## Tasks
- [x] Update DataManager.lua to include `checkpointHistory` in player data structure
- [x] Fix MainServer.lua OnCheckpointTouched function to extract checkpointId from checkpointPart and call UpdateCheckpointData correctly
- [x] Create sample checkpoint parts in Workspace/Checkpoints with proper attributes (Order, Position)
- [x] Verify data structure consistency across all modules

## Critical Bug Fixes (URGENT)
- [x] Fix Config.lua syntax error (missing comma after DATASTORE_NAME)
- [x] Fix checkpoint double touch (remove remote event, use only physical touch)
- [x] Implement save queue system in DataManager (prevent race conditions)
- [x] Add distance validation for checkpoint touches
- [x] Fix memory leak in character references
- [x] Add rate limiting and security validations
- [x] Optimize heartbeat performance

## Details
- Config: Fix syntax error on line 42 (missing comma)
- Checkpoint: Remove RemoteEvents usage, use only .Touched event with debounce
- DataManager: Add save queue with locks to prevent concurrent saves
- MainServer: Add distance validation (25 studs max), cooldown per checkpoint
- Performance: Reduce heartbeat frequency, add dirty flag system

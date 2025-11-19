# TODO: Fix Checkpoint System Issues

## Issues Identified
1. **DataManager Error (Line 318)**: `DirectSavePlayerData` may be nil in game's version (current file has it).
2. **Checkpoint Reset Not Working**: Reset function doesn't sync to client or fully reset DataManager.
3. **CheckpointGUI Error**: No DataStore access in current file.

## Tasks
- [x] Update `ResetPlayerCheckpoints` in MainServer.lua to properly reset DataManager data and send client sync.
- [x] Test reset functionality after changes.

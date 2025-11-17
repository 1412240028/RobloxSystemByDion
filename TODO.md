# TODO: Critical Fixes Implementation Plan

## TIER 1: Critical Bugs (Must Fix Immediately)

### 1. Fix Save Queue System (TIER 1.1)
- [x] Implement proper queue processor in DataManager.lua with background worker and timeout handling
- [x] Prevent infinite loops in queue processing
- [x] Add metrics for queue monitoring

### 2. Fix Checkpoint Persistence (TIER 1.2)
- [x] Ensure playerTouchedCheckpoints syncs with DataStore
- [x] Add immediate saves after checkpoint touches
- [x] Implement backup mechanism for save failures

### 3. Implement Auto-Save (TIER 1.3)
- [x] Add periodic save loop in MainServer.lua using dirty flag system
- [x] Use AUTO_SAVE_INTERVAL_SECONDS from Config
- [x] Add per-player save timers

### 4. Complete Race System Trigger (TIER 1.4)
- [x] Add admin command `/startrace` in SystemManager.lua
- [x] Implement auto-race scheduler (every X minutes)
- [x] Add race queue system

### 5. Fix Memory Leaks (TIER 2.5)
- [x] Implement connection tracking in MainServer.lua
- [x] Disconnect all connections in OnPlayerRemoving()
- [x] Add proper cleanup pattern

## Progress Tracking
- Started: [Date/Time]
- Current Step: All Critical Fixes Complete
- Completed Steps: 5/5

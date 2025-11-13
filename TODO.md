# Checkpoint UI Notifications & Multiplayer Racing Implementation TODO

## Tasks
- [x] Update Config.lua with race settings (race duration, leaderboard size, notification settings)
- [x] Extend DataManager.lua with race fields (raceTimes, bestTime, isRacing, raceStartTime)
- [x] Add race events to RemoteEvents.lua (RaceStart, RaceEnd, LeaderboardUpdate, RaceNotification)
- [x] Implement race logic in MainServer.lua (start/end race, time tracking, leaderboard management)
- [x] Create CheckpointNotification.lua in StarterGui/CheckpointUI/
- [x] Integrate race status display and notification triggers in CheckpointGUI.lua
- [x] Update AutoSetup.lua to create race RemoteEvents
- [x] Test race initialization and timing
- [x] Verify leaderboard updates and persistence
- [x] Test notification UI display
- [x] Ensure compatibility with existing checkpoint system

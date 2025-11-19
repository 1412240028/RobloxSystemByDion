# TODO List for Roblox Checkpoint System

## Completed Tasks
- [x] Add success notification when reaching a checkpoint
- [x] Add skip notification for invalid checkpoint touches
- [x] Update server to send notifications
- [x] Update client to receive and display notifications
- [x] Update GUI to show notifications
- [x] Create notification labels in GUI
- [x] Test the notification system in-game

## Pending Tasks
- [ ] Test the notification system in-game
- [ ] Add sound effects for notifications
- [ ] Implement checkpoint skip logic (if needed)
- [ ] Add more detailed validation messages
- [ ] Optimize notification animations
- [ ] Add settings to toggle notifications on/off

## Notes
- Notifications are sent from server via RemoteEvents
- GUI handles animation and display of notifications
- Success notifications show when checkpoint is reached
- Skip notifications show for invalid touches (too far, debounce, etc.)

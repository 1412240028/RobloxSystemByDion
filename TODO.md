# Admin System Improvements TODO

## 1. Implement DataStore Admin Persistence
- [x] Add admin data structure to DataManager.lua (adminData table, load/save functions)
- [x] Modify SystemManager.lua to load admin data from DataStore instead of hardcoded Config.ADMIN_UIDS
- [x] Update Config.lua to remove hardcoded ADMIN_UIDS and add admin DataStore settings
- [ ] Test admin persistence (add/remove admins, verify saves across sessions)

## 2. Add Audit Logging System
- [x] Create new AdminLogger.lua module with logging functions
- [x] Implement log storage in DataStore with rotation/cleanup
- [x] Integrate logging into SystemManager for all admin actions
- [x] Add log viewing commands and functions

## 3. Add Rate Limiting for Admin Commands
- [x] Add command cooldown tracking to SystemManager
- [x] Implement configurable rate limits per command/permission level
- [x] Add rate limit violation handling and notifications
- [ ] Test rate limiting (spam commands, verify blocks)

## 4. Improve Input Validation and Error Handling
- [x] Add comprehensive validation for all admin command arguments
- [x] Improve error messages with more context and suggestions
- [x] Add try-catch blocks around critical admin operations
- [ ] Test error handling (invalid inputs, permission errors)

## 5. Create Admin GUI Panel
- [ ] Create AdminGUI.lua client script with management interface
- [ ] Add remote events for GUI communication (view logs, manage admins, execute commands)
- [ ] Update MainServer.lua to handle admin GUI remotes
- [ ] Test admin GUI (open panel, execute commands, view logs)

## 6. Final Testing and Verification
- [ ] Test all improvements work together
- [ ] Verify production readiness (no hardcoded data, proper error handling)
- [ ] Performance testing (DataStore operations, GUI responsiveness)
- [ ] Security audit (rate limiting effectiveness, permission checks)

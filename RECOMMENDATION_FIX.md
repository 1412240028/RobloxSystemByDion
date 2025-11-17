# 🔧 DAFTAR PERBAIKAN YANG HARUS DILAKUKAN

## 📋 **STRUKTUR PRIORITAS PERBAIKAN**

---

## 🔴 **TIER 1: CRITICAL BUGS (Must Fix Immediately)**

### **1. Save Queue System Rusak**
**Lokasi:** `ReplicatedStorage/Modules/DataManager.lua`
**Line:** 119-126

**Masalah:**
- Save queue diisi tapi tidak pernah diproses dengan benar
- Recursive call yang bisa infinite loop
- Tidak ada worker/processor untuk queue

**Apa yang perlu diperbaiki:**
- Buat queue processor yang jalan di background
- Implement proper queue drain mechanism
- Add timeout untuk prevent infinite loop
- Tambahin metrics untuk monitor queue size

**Dampak kalau tidak diperbaiki:**
- Data player bisa hilang saat concurrent saves
- Memory leak dari queue yang terus bertambah
- Server crash kalau queue overflow

---

### **2. Checkpoint Touch Tidak Persistent**
**Lokasi:** `ServerScriptService/MainServer.lua`
**Line:** 125-135, 295-385

**Masalah:**
- `playerTouchedCheckpoints` hanya di RAM
- Setelah server restart, player bisa touch checkpoint yang sama lagi
- `checkpointHistory` di-save tapi restore logic tidak sempurna
- Race condition antara auto-save dan player disconnect

**Apa yang perlu diperbaiki:**
- Ensure `playerTouchedCheckpoints` di-sync dengan DataStore
- Tambah immediate save setelah checkpoint touched (jangan tunggu auto-save)
- Implement backup mechanism kalau save gagal
- Add verification saat player rejoin

**Dampak kalau tidak diperbaiki:**
- Player bisa exploit checkpoint system
- Progress tidak konsisten
- Leaderboard tidak akurat

---

### **3. Auto-Save Tidak Jalan**
**Lokasi:** `ReplicatedStorage/Modules/DataManager.lua` & `ServerScriptService/MainServer.lua`

**Masalah:**
- Config ada `AUTO_SAVE_INTERVAL_SECONDS = 60` tapi tidak digunakan
- Tidak ada periodic save mechanism
- Data hanya di-save saat player leave atau manual call

**Apa yang perlu diperbaiki:**
- Implement auto-save loop di MainServer
- Add per-player save timers
- Implement dirty flag system (hanya save yang berubah)
- Add graceful shutdown handler

**Lokasi implementasi:**
- `MainServer.lua` - tambah auto-save loop di `Init()`
- `DataManager.lua` - tambah `MarkDirty()` function

**Dampak kalau tidak diperbaiki:**
- Data loss saat server crash
- Player kehilangan progress kalau DC
- Frustasi player karena harus repeat

---

### **4. Race System Tidak Ada Trigger**
**Lokasi:** `ServerScriptService/MainServer.lua`
**Line:** 515-578

**Masalah:**
- `StartRace()` function complete tapi tidak dipanggil dari mana-mana
- Tidak ada admin command untuk start race
- Tidak ada automatic race scheduler
- Race UI notification jalan tapi race tidak pernah start

**Apa yang perlu diperbaiki:**
- Tambah admin command `/startrace` di SystemManager
- Implement auto-race scheduler (every X minutes)
- Tambah voting system untuk players
- Tambah race queue system

**Lokasi implementasi:**
- `SystemManager.lua` - tambah race commands
- `MainServer.lua` - tambah race scheduler
- Bikin `RaceController.lua` baru untuk manage race lifecycle

**Dampak kalau tidak diperbaiki:**
- Race system mubazir (90% code tidak terpakai)
- Features tidak accessible
- Wasted development effort

---

## 🟡 **TIER 2: HIGH PRIORITY (Should Fix Soon)**

### **5. Memory Leak dari Event Connections**
**Lokasi:** `ServerScriptService/MainServer.lua`
**Line:** 53-65 (SetupCheckpointTouches), 99-103 (CharacterDied)

**Masalah:**
- `.Touched:Connect()` untuk checkpoint tidak di-disconnect
- `.Died:Connect()` tidak di-cleanup saat player leave
- Character connections tidak di-track
- `Cleanup()` hanya clear tables, tidak disconnect events

**Apa yang perlu diperbaiki:**
- Buat connection tracker table
- Disconnect semua connections di `OnPlayerRemoving()`
- Implement proper cleanup pattern
- Add connection pooling untuk checkpoint touches

**Lokasi yang perlu diubah:**
```
MainServer.lua:
- Tambah `playerConnections = {}` table
- Track semua connections per player
- Disconnect di Cleanup()
```

**Dampak kalau tidak diperbaiki:**
- Memory usage naik terus over time
- Server lag setelah beberapa jam
- Eventual server crash

---

### **6. Admin System Hardcoded & Tidak Secure**
**Lokasi:** `ReplicatedStorage/Config/Config.lua`
**Line:** 113-117

**Masalah:**
- Admin UIDs hardcoded di config
- Kalau UID leaked, permanent admin access
- Tidak bisa revoke admin tanpa server restart
- Tidak ada admin action logging
- Tidak ada rate limiting untuk admin commands

**Apa yang perlu diperbaiki:**
- Pindah admin data ke DataStore terpisah
- Implement admin action logging
- Tambah rate limiting per admin level
- Tambah temporary admin grants
- Bikin admin dashboard/UI

**Lokasi implementasi baru:**
```
- Buat AdminService.lua di ServerScriptService
- Buat AdminDataStore.lua untuk persist admin list
- Tambah AdminCommands.lua untuk command handling
- Update SystemManager.lua untuk use new admin service
```

**Dampak kalau tidak diperbaiki:**
- Security risk kalau exploiter dapat admin UID
- Tidak bisa manage admin dengan mudah
- No audit trail untuk admin actions

---

### **7. Client-Side Rate Limiting Lemah**
**Lokasi:** `StarterPlayer/StarterPlayerScripts/Sprint/SprintClient.lua` & `Checkpoint/CheckpointClient.lua`

**Masalah:**
- Throttle hanya di client (bisa di-bypass)
- Server-side validation ada tapi tidak konsisten
- Remote event bisa di-spam
- No punishment untuk spammers

**Apa yang perlu diperbaiki:**
- Implement server-side rate limiter per player per remote
- Add exponential backoff untuk repeat offenders
- Track spam violations
- Auto-kick/ban setelah threshold

**Lokasi implementasi:**
```
Buat RateLimiter.lua di ReplicatedStorage/Modules:
- TrackRequest(player, eventName)
- IsRateLimited(player, eventName)
- GetViolationCount(player)
- ResetViolations(player)

Update MainServer.lua:
- Validate SEMUA remote calls dengan rate limiter
- Log violations
- Implement punishment system
```

**Dampak kalau tidak diperbaiki:**
- Exploiter bisa spam requests
- Server performance degradation
- DoS attack vulnerable

---

### **8. DataStore Error Handling Tidak Lengkap**
**Lokasi:** `ReplicatedStorage/Modules/DataManager.lua`
**Line:** 148-182

**Masalah:**
- Retry logic bagus tapi tidak handle semua error types
- Tidak ada fallback ke backup datastore
- Budget throttling tidak di-handle
- Error message tidak informatif untuk player

**Apa yang perlu diperbaiki:**
- Implement different retry strategies per error type
- Add backup datastore failover
- Implement request budgeting
- Add player-friendly error messages via GUI

**Error types yang perlu di-handle:**
```
- 403 Forbidden → Check API key
- 429 Too Many Requests → Implement backoff
- 500 Internal Error → Retry dengan longer delay
- 503 Service Unavailable → Use backup datastore
- Request was throttled → Wait untuk budget refresh
```

**Dampak kalau tidak diperbaiki:**
- Data loss pada DataStore outage
- Poor player experience saat errors
- Tidak bisa diagnose issues dengan mudah

---

## 🟢 **TIER 3: MEDIUM PRIORITY (Nice to Have)**

### **9. Config Terlalu Bloated**
**Lokasi:** `ReplicatedStorage/Config/Config.lua`

**Masalah:**
- 200+ lines config untuk 4 systems
- Hard to maintain
- Changes require full file reload
- Sprint, Checkpoint, Race configs mixed

**Apa yang perlu diperbaiki:**
- Pecah jadi modular configs:
  ```
  ReplicatedStorage/Config/
  ├── Config.lua (main loader)
  ├── SprintConfig.lua
  ├── CheckpointConfig.lua
  ├── RaceConfig.lua
  └── AdminConfig.lua
  ```
- Implement config hot-reload
- Add config validation per module
- Add config presets (Easy, Normal, Hard)

---

### **10. No Data Migration System**
**Lokasi:** `ReplicatedStorage/Modules/DataManager.lua`

**Masalah:**
- `DATA_VERSION = 1` ada tapi tidak digunakan
- Breaking changes akan corrupt existing data
- No migration scripts
- No rollback mechanism

**Apa yang perlu diperbaiki:**
- Implement version checker
- Create migration functions per version
- Add safe rollback mechanism
- Test migrations di staging

**Structure yang diperlukan:**
```lua
Migrations = {
    [1] = function(data) 
        -- v1 → v2 migration
    end,
    [2] = function(data)
        -- v2 → v3 migration
    end
}

function MigrateData(data, fromVersion, toVersion)
    -- Run migrations sequentially
end
```

---

### **11. Race Leaderboard Tidak Persistent**
**Lokasi:** `ReplicatedStorage/Modules/DataManager.lua`
**Line:** 96-120

**Masalah:**
- Leaderboard hanya di RAM
- Server restart = leaderboard hilang
- Tidak ada all-time leaderboard
- Tidak ada seasonal rankings

**Apa yang perlu diperbaiki:**
- Save leaderboard ke OrderedDataStore
- Implement weekly/monthly/all-time boards
- Add leaderboard caching
- Add pagination untuk large leaderboards

**Lokasi implementasi:**
```
Buat LeaderboardManager.lua baru:
- UpdateLeaderboard(player, time)
- GetTopPlayers(timeframe, limit)
- GetPlayerRank(player, timeframe)
- SaveLeaderboard() (periodic)
```

---

### **12. UI/UX Improvements**

**Checkpoint GUI Issues:**
**Lokasi:** `StarterPlayer/StarterPlayerScripts/Checkpoint/CheckpointGUI.lua`

**Masalah:**
- Reset button tidak ada confirmation
- No visual feedback saat checkpoint touched
- Notifications bisa overlap
- No tutorial untuk new players

**Apa yang perlu diperbaiki:**
- Add confirmation dialog untuk reset
- Add checkpoint touch particles/sound
- Implement notification queue system
- Add first-time tutorial

---

**Sprint GUI Issues:**
**Lokasi:** `StarterPlayer/StarterPlayerScripts/Sprint/SprintGUI.lua`

**Masalah:**
- No keybind customization
- No visual indicator untuk sprint cooldown
- Button position tidak bisa digeser
- No accessibility options

**Apa yang perlu diperbaiki:**
- Add settings menu
- Add cooldown timer visual
- Implement draggable buttons
- Add colorblind mode

---

### **13. Anti-Cheat Enhancements**
**Lokasi:** `ServerScriptService/MainServer.lua`
**Line:** 465-505

**Current Anti-Cheat:**
- ✅ Speed validation
- ✅ Distance validation untuk checkpoints
- ❌ No teleport detection
- ❌ No fly detection
- ❌ No noclip detection

**Apa yang perlu diperbaiki:**
- Implement position history tracking
- Add velocity validation
- Check for impossible movements
- Add suspicious activity scoring
- Auto-kick after threshold

**Lokasi implementasi:**
```
Buat AntiCheat.lua di ServerScriptService:
- ValidateMovement(player, oldPos, newPos, deltaTime)
- CheckTeleport(player)
- CheckFly(player)
- CheckNoclip(player)
- TrackViolations(player, violationType)
```

---

### **14. Performance Optimizations**

**14A. Heartbeat Anti-Cheat Loop**
**Lokasi:** `ServerScriptService/MainServer.lua`
**Line:** 478-505

**Masalah:**
- Loop semua players every frame
- Tidak ada early exit conditions
- Speed check setiap 1 detik per player

**Apa yang perlu diperbaiki:**
- Implement staggered checking (split players per frame)
- Add early exit jika player tidak moving
- Increase interval to 2-3 seconds
- Only check players yang sprinting

---

**14B. DataStore Batching**
**Lokasi:** `ReplicatedStorage/Modules/DataManager.lua`

**Masalah:**
- Individual SetAsync calls per player
- No request batching
- Hitting DataStore limits pada high player count

**Apa yang perlu diperbaiki:**
- Implement save batching (multiple players per request)
- Use UpdateAsync instead of SetAsync
- Implement request queue dengan priority
- Add budget tracking

---

**14C. Remote Event Broadcasting**
**Lokasi:** `ReplicatedStorage/Remotes/RemoteEvents.lua`

**Masalah:**
- `FireAllClients()` broadcasts ke semua player
- Unnecessary data sent ke players yang tidak perlu

**Apa yang perlu diperbaiki:**
- Implement proximity-based broadcasting
- Only send updates ke nearby players
- Add interest management system
- Batch multiple updates jadi single packet

---

## 🔵 **TIER 4: LOW PRIORITY (Future Enhancements)**

### **15. Analytics & Metrics**
- Add telemetry untuk player behavior
- Track feature usage
- Monitor server performance
- Implement crash reporting

### **16. Testing Infrastructure**
- Add unit tests untuk core systems
- Implement integration tests
- Add load testing
- Create test utilities

### **17. Documentation**
- API documentation
- System architecture diagrams
- Developer onboarding guide
- Player-facing wiki

### **18. Advanced Features**
- Multiple race modes (time trial, elimination, relay)
- Custom checkpoint types (bonus, penalty, teleport)
- Power-ups system
- Achievement system
- Social features (friends, teams)

---

## 📊 **ROADMAP ESTIMASI WAKTU**

```
TIER 1 (Critical): 20-25 hours
├── Save Queue Fix: 4h
├── Checkpoint Persistence: 6h
├── Auto-Save Implementation: 5h
└── Race System Trigger: 5h

TIER 2 (High): 25-30 hours
├── Memory Leak Fixes: 6h
├── Admin System Overhaul: 8h
├── Rate Limiting: 5h
└── DataStore Error Handling: 6h

TIER 3 (Medium): 20-25 hours
├── Config Refactor: 6h
├── Data Migration: 5h
├── Leaderboard Persistence: 4h
├── UI/UX Improvements: 8h
├── Anti-Cheat Enhancement: 8h
└── Performance Optimization: 10h

TIER 4 (Low): 40+ hours
└── Various enhancements

TOTAL ESTIMATE: 105-120 hours (~3-4 weeks full-time)
```

---

## 🎯 **REKOMENDASI URUTAN PERBAIKAN**

**Week 1: Foundation Fixes**
1. Fix Save Queue System (TIER 1.1)
2. Fix Checkpoint Persistence (TIER 1.2)
3. Implement Auto-Save (TIER 1.3)
4. Fix Memory Leaks (TIER 2.5)

**Week 2: System Completion**
5. Complete Race System (TIER 1.4)
6. Enhance Admin System (TIER 2.6)
7. Add Rate Limiting (TIER 2.7)
8. Improve Error Handling (TIER 2.8)

**Week 3: Polish & Optimization**
9. Refactor Config (TIER 3.9)
10. Add Data Migration (TIER 3.10)
11. Optimize Performance (TIER 3.14)
12. Enhance Anti-Cheat (TIER 3.13)

**Week 4: UX & Features**
13. UI/UX Improvements (TIER 3.12)
14. Leaderboard System (TIER 3.11)
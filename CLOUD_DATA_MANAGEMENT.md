# Cloud Data Management Architecture

This document formalizes the **Cloud Data Management Matrix** governing data flow between the local companion system (`WCSession` / local state) and Cloud infrastructure (Firebase Real-Time Database / Cloud Functions).

---

## 1. Cloud Data Management Matrix

| | **From: Local Data** | **From: Cloud (Firebase RTDB)** |
|---|---|---|
| **To: Local Data** | **Resilient WCSession:**<br>• Exclusively uses `WCSession.updateApplicationContext`<br>• Timestamp-driven merge resolution (`*_ts` per structure)<br>• Directional payloads (`p2w_hs`, `w2p_hs`, `p2w_ls`, `w2p_ls`) | **Unidirectional telemetry download channel:**<br>• No resilience requirements, stale data locally OK<br>• Out of order rejection of each remote player's telemetry stream to avoid jumping<br>• Packet integrity checked before storing in `WCSession`<br>• Watch relies on Phone cache when reachable and fresh; falls back to Firebase directly |
| **To: Cloud (Firebase RTDB)** | **Bidirectional room and tactical channels:**<br>• Standard Firebase REST/JSON atomic updates<br>• Roster is handled via room so players don't blink based on telemetry<br>• On change only to reduce bandwidth<br>• Tactical channel: create and delete only<br><br>**Unidirectional telemetry upload channel:**<br>• Ephemeral updates throttled by dead reckoning & delta gating | **Hourly cleanup based on `expireAt`:**<br>• Scheduled Cloud Function (`cleanExpiredRooms`) purges expired rooms and associated data across `/rooms`, `/tactical`, and `/telemetry` |

---

## 2. Channel Breakdown & Implementation Details

### A. Local Data ➔ Local Data (WCSession)
* **Components:** [`WatchConnectivityManager.swift`](RadarMap/Managers/WatchConnectivityManager.swift), [`CompanionSyncModels.swift`](RadarMap/Models/CompanionSyncModels.swift), [`COMPANION_DATA_SYNC_MODEL.md`](COMPANION_DATA_SYNC_MODEL.md).
* **Guarantees:** Resilient local synchronization between iPhone and Apple Watch using directional snapshots and per-structure timestamp resolution.
* **Mechanism:** Single transport via `WCSession.updateApplicationContext`. `sync_ts` is rolled only when local owns a winning structure not yet acknowledged by peer.

---

### B. Cloud ➔ Local Data (Telemetry Download)
* **Components:** [`FirebaseSyncManager.swift`](RadarMap/Managers/FirebaseSyncManager.swift).
* **Guarantees:** Ephemeral stream, stale data tolerated, strict ordering per-member.
* **Mechanisms:**
  * **Late / Out-of-Order Packet Rejection:** Maintains per-member monotonically increasing sequence counters (`memberLatestSequences`) and timestamp watermarks (`memberLatestTimestamps`) to drop packets arriving out of order.
  * **Active State Gating:** Client-driven adaptive REST polling throttles when the device/wrist is inactive (`isWristActive == false`, interval = 5.0s / 0.2 Hz) and resumes full speed on wake bursts to eliminate server socket costs and maximize battery life.
  * **Watch Data Source Selection:** If Phone is reachable and fresh (`now < fresh_until`), Watch pauses direct Firebase polling and consumes Phone's high-speed broadcast. If Phone disconnects or stream becomes stale, Watch resumes direct Firebase polling.

---

### C. Local Data ➔ Cloud (Room, Tactical, & Telemetry Uploads)
* **Components:** [`FirebaseSyncManager.swift`](RadarMap/Managers/FirebaseSyncManager.swift), [`GameStateManager.swift`](RadarMap/Managers/GameStateManager.swift).
* **Guarantees:**
  * **Room & Tactical (Reliable / Bidirectional):** Atomic REST / transaction mutations for room state (host, join, leave, disband, callsign renames) and tactical markers (create/delete). Updates sent **on change only** to minimize cloud bandwidth.
  * **Squad Roster Decoupling:** Roster annotations remain stable from the room state regardless of individual telemetry packet reception.
  * **Telemetry Upload (Unreliable / Unidirectional):** Ephemeral updates throttled by **Dead Reckoning & Delta Gating** (suppressed if displacement $< 3.5\text{ m}$ and $\Delta\text{HR} < 12\text{ BPM}$, protected by periodic fallback heartbeats).

---

### D. Cloud ➔ Cloud (Lifecycle & Pruning)
* **Components:** [`functions/index.js`](functions/index.js).
* **Guarantees:** Automatic garbage collection of orphaned sessions.
* **Mechanism:** 2nd-gen scheduled Cloud Function (`cleanExpiredRooms`) executes hourly (`every 1 hours` UTC) to identify rooms with `expireAt <= now` and atomically purge their sub-trees across `/rooms/{roomId}`, `/tactical/{roomId}`, and `/telemetry/{roomId}`.

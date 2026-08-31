# Firebase Schema & Daily Cleanup Cloud Functions Specification

This document provides a comprehensive technical reference for the Firebase Realtime Database (RTDB) schema, Cloud Functions lifecycle triggers, scheduling logic, and pruning rules implemented in RadarMap.

---

## 1. Firebase Realtime Database (RTDB) Architecture & Schema

RadarMap organizes its cloud state into three decoupled top-level sub-trees to optimize bandwidth, prevent packet stampedes, and separate ephemeral high-frequency telemetry from durable room session state.

```
/ (Root)
├── /rooms/{roomId}         # Room metadata, settings, and member roster
├── /tactical/{roomId}      # Tactical map markers, orders, and enemy callouts
└── /telemetry/{roomId}     # Real-time streaming GPS coordinates and biometrics
```

### A. `/rooms/{roomId}` — Squad Room & Roster Node
Maintains squad metadata, security hashes, capacity limits, TTL timers, and roster registrations.

```json
{
  "id": "ALPHA-01",
  "hostId": "member_usr_01",
  "maxCapacity": 4,
  "hasPin": true,
  "pinHash": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "createdAt": 1756512000.0,
  "lastActivityTimestamp": 1756512300.0,
  "expireAt": 1757116800.0,
  "members": {
    "member_usr_01": {
      "id": "member_usr_01",
      "callsign": "GHOST-1",
      "isHost": true
    },
    "member_usr_02": {
      "id": "member_usr_02",
      "callsign": "VIPER-2",
      "isHost": false
    }
  }
}
```

#### Field Definitions:
* **`id`** `(String)`: Unique room/squad identifier (sanitized uppercase, e.g., `"ALPHA-01"`).
* **`hostId`** `(String)`: Member ID of the squad creator / host.
* **`maxCapacity`** `(Integer)`: Squad size cap (`4` for Free Tier, `999` or `12` for Pro Tier).
* **`hasPin`** `(Boolean)`: Whether PIN protection is enabled.
* **`pinHash`** `(String, Optional)`: SHA-256 hash formatted as `SHA256("\(roomId):\(pin)")`.
* **`createdAt`** `(Float/Double)`: Epoch timestamp in seconds when the room was created.
* **`lastActivityTimestamp`** `(Float/Double)`: Epoch timestamp in seconds of the most recent member interaction or heartbeat.
* **`expireAt`** `(Float/Double)`: Absolute expiration timestamp (epoch seconds), calculated as `lastActivityTimestamp + (7 days * 86400)`.
* **`members`** `(Map<String, MemberMetadata>)`:
  * **`id`** `(String)`: Member unique ID.
  * **`callsign`** `(String)`: Tactical callsign (must be unique within the room).
  * **`isHost`** `(Boolean)`: Squad leadership status.
  *(Note: Dynamic coordinates and heart rates are excluded from the `/rooms` node to avoid high-frequency write churn on the roster).*

---

### B. `/tactical/{roomId}` — Tactical Indicators & Orders Node
Stores placed objective markers, tactical enemy indicators, and team waypoint orders.

```json
{
  "meta": {
    "updatedAt": 1756512300.0,
    "expireAt": 1757116800.0
  },
  "-NxIndicatorKey1": {
    "type": "infantry",
    "latitude": 37.785834,
    "longitude": -122.406417,
    "placedByMemberId": "member_usr_01",
    "timestamp": 1756512290.0,
    "expiresAt": 1756512590.0
  },
  "-NxIndicatorKey2": {
    "type": "attackHere",
    "latitude": 37.787120,
    "longitude": -122.405300,
    "placedByMemberId": "member_usr_02",
    "timestamp": 1756512305.0
  }
}
```

#### Field Definitions:
* **`meta/updatedAt`** `(Float/Double)`: Timestamp of latest indicator placement or deletion.
* **`meta/expireAt`** `(Float/Double)`: Room expiration TTL mirror.
* **`[indicatorId]`** `(Map<String, Any>)`:
  * **`type`** `(String)`: Indicator identifier:
    * **Squad Orders:** `"watchHere"`, `"goHere"`, `"attackHere"`, `"protectHere"`
    * **Enemy Indicators:** `"infantry"`, `"lightVehicle"`, `"heavyVehicle"`
  * **`latitude`** `(Double)`: Geodetic WGS-84 latitude.
  * **`longitude`** `(Double)`: Geodetic WGS-84 longitude.
  * **`placedByMemberId`** `(String)`: Author member ID.
  * **`timestamp`** `(Float/Double)`: Epoch timestamp when placed.
  * **`expiresAt`** `(Float/Double, Optional)`: Individual marker expiration (e.g. 5-minute desaturation/fade window).

---

### C. `/telemetry/{roomId}` — Real-Time Streaming Telemetry Node
Stores active stream coordinates using ultra-compact positional arrays to minimize packet overhead and parse time on constrained watchOS / iOS hardware.

```json
{
  "expireAt": 1757116800.0,
  "member_usr_01": [
    37.785834,
    -122.406417,
    78.0,
    1756512300.5
  ],
  "member_usr_02": [
    37.786100,
    -122.407200,
    84.0,
    1756512301.0
  ]
}
```

#### Compact Array Formats:
* **Primary Ultra-Lean 4-Element Format:** `[latitude, longitude, heartRate, timestamp]`
  * `[0]` `latitude` `(Double)`: Latitude in degrees.
  * `[1]` `longitude` `(Double)`: Longitude in degrees.
  * `[2]` `heartRate` `(Double)`: Current BPM (`0.0` = KIA / Downed).
  * `[3]` `timestamp` `(Double)`: Generation timestamp in seconds since epoch.
* **Extended / Legacy Formats Supported by Deserializer:**
  * 6-Element: `[latitude, longitude, altitude, heartRate, sequenceNumber, timestamp]`
  * 7-Element: `[latitude, longitude, altitude, heading, heartRate, sequenceNumber, timestamp]`

---

## 2. Cloud Functions & Daily Cleanup Architecture

All cloud cleanup functions reside in [`functions/index.js`](functions/index.js) and ensure multi-path atomic consistency across all sub-trees.

```mermaid
flowchart TD
    A[Scheduled Trigger: scheduledDailyCleanup] -->|Runs daily at 00:00 UTC| B[Scan /rooms]
    B --> C{Is room idle > 7 days OR members count == 0?}
    C -->|Yes| D[Stage atomic null mutation]
    C -->|No| E[Retain room]
    D --> F[Execute multi-path update]
    F --> G["Delete /rooms/{id}, /tactical/{id}, /telemetry/{id}"]
    
    H[RTDB Trigger: cleanupEmptyRoom] -->|onWrite /rooms/{id}/members| I{Are members empty or null?}
    I -->|Yes| J[Instant Atomic Multi-Path Purge]
    I -->|No| K[No-op]
```

### 1. `scheduledDailyCleanup` (Daily 7-Day Inactivity Cleanup)
* **Trigger:** PubSub Schedule `every 24 hours` (`00:00 UTC`).
* **Cutoff Threshold:** $7\text{ days} = 604,800,000\text{ ms} = 604,800\text{ s}$.
* **Logic:**
  1. Performs a full read on `/rooms`.
  2. For each room, evaluates `lastActivityTimestamp` (with fallback to `createdAt`). Supports both unix seconds and millisecond epoch timestamps.
  3. Checks if `(now - lastActive) >= 7 days` **OR** `members` dictionary is empty.
  4. Batches multi-path deletions into a single atomic `.update()` call:
     ```javascript
     updates[`/rooms/${roomId}`] = null;
     updates[`/tactical/${roomId}`] = null;
     updates[`/telemetry/${roomId}`] = null;
     ```
  5. Logs total purged rooms and execution metadata.

### 2. `cleanExpiredRooms` (Hourly TTL Expiration Scheduler)
* **Trigger:** Cloud Functions v2 Scheduler `every 1 hours` (`UTC`, `us-central1`).
* **Query Mechanism:** Index-accelerated query on indexed property:
  ```javascript
  db.ref("/rooms").orderByChild("expireAt").endAt(nowSeconds).once("value");
  ```
* **Logic:**
  1. Identifies any room where `expireAt <= nowSeconds`.
  2. Builds an atomic multi-path deletion payload purging `/rooms/{roomId}`, `/tactical/{roomId}`, and `/telemetry/{roomId}`.
  3. Executes atomic `.update(updates)`.

### 3. `cleanupEmptyRoom` (Instant Reactive Host Departure & Roster Trigger)
* **Trigger:** Realtime Database `onWrite` trigger on `/rooms/{roomId}/members`.
* **Logic:**
  1. Guard check: if `!change.after.exists()`, returns early to avoid infinite cascades.
  2. Inspects `change.after.val()`. If `members` is `null` or `Object.keys(membersData).length === 0`, OR if the room's `hostId` is no longer in `membersData`:
  3. Instantly cascades an atomic purge across `/rooms/{roomId}`, `/tactical/{roomId}`, and `/telemetry/{roomId}`. Non-host player departures do not purge the room.

---

## 3. Database Rules & Indexing Guidelines (`database.rules.json`)

To support query performance for `cleanExpiredRooms` and guard user data, the following rules configuration should be applied to Firebase RTDB:

```json
{
  "rules": {
    ".read": false,
    ".write": false,
    "rooms": {
      ".indexOn": ["expireAt", "createdAt", "lastActivityTimestamp"],
      "$roomId": {
        ".read": true,
        ".write": "data.exists() || newData.child('id').exists() || newData.child('createdAt').exists()",
        ".validate": "$roomId.length > 0 && $roomId.length <= 64",
        "members": {
          ".read": "root.child('rooms').child($roomId).exists()",
          ".write": "root.child('rooms').child($roomId).exists()"
        }
      }
    },
    "telemetry": {
      "$roomId": {
        ".read": "root.child('rooms').child($roomId).exists()",
        ".write": "!newData.exists() || (root.child('rooms').child($roomId).exists() && newData.hasChild('expireAt'))",
        "$memberId": {
          ".write": "root.child('rooms').child($roomId).child('members').child($memberId).exists() || !newData.exists()"
        }
      }
    },
    "tactical": {
      "$roomId": {
        ".read": "root.child('rooms').child($roomId).exists()",
        ".write": "!newData.exists() || (root.child('rooms').child($roomId).exists() && (newData.hasChild('meta') || newData.hasChild('updatedAt')))",
        "meta": {
          ".write": "root.child('rooms').child($roomId).exists()"
        },
        "updatedAt": {
          ".write": "root.child('rooms').child($roomId).exists()"
        },
        "indicators": {
          "$indicatorId": {
            ".write": "!newData.exists() || (root.child('rooms').child($roomId).exists() && newData.child('placedByMemberId').exists() && root.child('rooms').child($roomId).child('members').child(newData.child('placedByMemberId').val()).exists())"
          }
        },
        "$legacyIndicatorId": {
          ".write": "!newData.exists() || (root.child('rooms').child($roomId).exists() && newData.child('placedByMemberId').exists() && root.child('rooms').child($roomId).child('members').child(newData.child('placedByMemberId').val()).exists())"
        }
      }
    }
  }
}
```

---

## 4. Key Takeaways for Future Iterations

1. **Atomic Multi-Path Purging:** Never delete `/rooms/{roomId}` in isolation without simultaneously purging `/tactical/{roomId}` and `/telemetry/{roomId}` in the same atomic `update()` payload.
2. **Bandwidth Optimization:** Keep `/rooms/{roomId}/members` strictly for roster membership and presence; never pipe high-frequency GPS or biometrics through the roster node.
3. **Timestamp Normalization:** Ensure client timestamps remain in decimal seconds (epoch TimeInterval) across Swift and Node.js Cloud Functions.

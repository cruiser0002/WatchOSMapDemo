# Local Companion Data Sync Architecture

This document formalizes the **Local Companion Data Sync Model** between iPhone (iOS) and Apple Watch (watchOS) apps via `WatchConnectivity` (`WCSession.updateApplicationContext`).

---

## 1. Protocol Architecture & Invariants

* **Transport Mechanism:** Uses **exclusively `WCSession.updateApplicationContext`** for all data synchronization (high-speed telemetry stream and low-speed state changes).
* **No Remote Forwarding:** Remote button action forwarding, `sendMessage`, and `transferUserInfo` queues have been completely removed.
* **Directional Envelopes:**
  * **Phone ➔ Watch:** Advertises `p2w_hs` (high-speed remote telemetry) and `p2w_ls` (merged low-speed snapshot).
  * **Watch ➔ Phone:** Advertises `w2p_hs` (high-speed optical heart rate) and `w2p_ls` (merged low-speed snapshot).
* **Heading Independence:** Heading is computed independently on each device using local sensors + weighted Course Over Ground (COG). Phone heading remains on Phone; Watch heading remains on Watch.

---

## 2. Payload Structure

### High-Speed Payloads (`p2w_hs`, `w2p_hs`)
Target Cadence: **1 Hz**

* **`p2w_hs` (Phone to Watch):**
  * `fresh_until`: Epoch timestamp until which this telemetry snapshot is fresh.
  * `remote_player_telemetry`: Compressed JSON map of remote squad members' telemetry (`latitude`, `longitude`, `altitude`, `heading`, `heart_rate`, `timestamp`).
* **`w2p_hs` (Watch to Phone):**
  * `fresh_until`: Epoch timestamp until which optical heart rate measurement is fresh.
  * `hr`: Live optical heart rate (or flatline 0.0 BPM when downed).

### Low-Speed Mergeable Structures (`p2w_ls`, `w2p_ls`)
Transmitted only on state change or rolling convergence retry.

1. **`config`**: `callsign`, `room_name`, `pin`, `theme`, `is_pro`, `member_id`, `config_ts`
2. **`login_cycle`**: `login_cycle` (`inactive`, `host_active`, `join_active`), `login_cycle_ts`
3. **`membership`**: `members` JSON array of squad members, `member_ts`
4. **`tactical`**: `tactical_indicators` JSON array of placed map markers, `tactical_ts`
5. **`player_state`**: `is_dead`, `is_dead_ts`

---

## 3. Merge Engine & Conflict Resolution Rules

1. **Per-Structure Timestamp Winner:** For each individual structure (`config`, `login_cycle`, `membership`, `tactical`, `player_state`), the structure with the larger timestamp (`*_ts`) wins.
2. **Phone Tie-Breaker:** If timestamps are equal but values differ, **Phone wins**.
3. **Equivalence & sync_ts:**
   * `sync_ts` is control metadata used only to trigger delivery of coalesced contexts in `WCSession`.
   * `sync_ts` is **excluded** from domain equivalence checks.
4. **Rolling sync_ts Retransmission:**
   * A device rolls `sync_ts` periodically (e.g. 1 Hz) if and only if it advertises at least one winning structure against its peer's last advertised snapshot.
   * As soon as the peer mirrors the winning structure or domain equivalence is reached, rolling `sync_ts` stops.
5. **Local Persistence:** Local owned snapshots, timestamps, and counterpart snapshots are persisted to `UserDefaults` and restored across application restarts.

---

## 4. Watch Cloud Access Policy

When the Watch requires cloud-backed room telemetry:
```swift
if phoneReachable && now < phoneFreshUntil {
    // Rely on Phone's WCSession high-speed stream; pause direct polling
    return .wcSession
} else {
    // Fall back to direct Firebase Realtime Database polling
    return .firebase
}
```

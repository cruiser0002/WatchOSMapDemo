# RadarMap - Jupyter Notebooks & Player Simulation

This directory contains Jupyter notebooks and Python scripts for simulating squad players in the **RadarMap** watchOS / iOS tactical application.

---

## 📁 Directory Contents

- [`player_simulation.ipynb`](file:///Users/cruiser/Documents/antigravity/jolly-hypatia/notebooks/player_simulation.ipynb): Interactive Jupyter notebook with setup cells, Host/Join operations, live circular trajectory simulation, tactical indicators placement, KIA flatline simulation, and rate adaptation equations.
- [`player_simulator.py`](file:///Users/cruiser/Documents/antigravity/jolly-hypatia/notebooks/player_simulator.py): Self-contained Python module and CLI script implementing the circular motion engine, geodesic bearing / COG calculations, tactical indicator endpoints, and Firebase RTDB synchronization.

---

## ⚙️ Setup Parameters

In the setup section of the notebook (or CLI arguments), you can configure:

| Parameter | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `CALLSIGN` | `str` | `"VIPER-1"` | Player tactical callsign displayed on the radar map. |
| `ROOM_NAME` | `str` | `"ALPHA"` | Room name / Squad identifier (case-insensitive). |
| `PIN` | `str` | `""` | Optional 4-digit PIN for protected rooms. |
| `LATITUDE` | `float` | `37.785834` | Center GPS latitude of circular orbit. |
| `LONGITUDE` | `float` | `-122.406417` | Center GPS longitude of circular orbit. |
| `HEART_RATE` | `float` | `115.0` | Heart rate in BPM (`0.0` simulates KIA / downed state). |
| `CIRCLE_RADIUS_METERS` | `float` | `50.0` | Radius of circular path in meters. |
| `SPEED_MPS` | `float` | `4.5` | Movement speed along the circle in meters/second. |
| `UPDATE_INTERVAL_SEC` | `float` | `1.0` | Telemetry packet transmission interval in seconds. |
| `TELEMETRY_FORMAT` | `str` | `"compact4"` | `"compact4"` (`[lat, lng, hr, ts]`), `"compact6"`, `"compact7"`, or `"dict"`. |
| `ENABLE_DELTA_GATING` | `bool` | `False` | Gating movement ($< 3.5\text{m}$) and HR ($< 12\text{ BPM}$) with $7.5\text{s}$ heartbeat fallback. |

---

## 📡 Firebase Schema & Protocol Support

1. **Room Node (`/rooms/{roomId}.json`)**:
   - `id`, `hostId`, `maxCapacity`, `createdAt`, `lastActivityTimestamp`, `hasPin`, `pinHash` (SHA-256), `members`, `indicators`.
   - `members` map contains streamlined member metadata `{id, callsign, isHost}`.

2. **Telemetry Stream (`/telemetry/{roomId}/{memberId}.json`)**:
   - Primary ultra-lean 4-element compact array: `[latitude, longitude, heartRate, timestamp]`.
   - Forward Course Over Ground (COG) is automatically derived from GPS coordinates or heading tangent.

3. **Tactical Indicators (`/tactical/{roomId}/{indicatorId}.json`)**:
   - **Squad Orders**: `watchHere`, `goHere`, `attackHere`.
   - **Enemy Indicators**: `infantry`, `lightVehicle`, `heavyVehicle`.
   - Synchronized via `_updatedAt` timestamp for bandwidth conservation.

4. **Constant Bandwidth Adaptation**:
   - Formula: $R_{max}(P) = R_{base} \times \min(1.0, N_{threshold} / P)$ with $N=12$ and $R_{base}=1.0\text{ Hz}$.

---

## 🚀 How to Run

### Option 1: Using Jupyter Notebook
1. Open [`player_simulation.ipynb`](file:///Users/cruiser/Documents/antigravity/jolly-hypatia/notebooks/player_simulation.ipynb) in your Jupyter environment or IDE.
2. Run **Section 1** to load configuration parameters.
3. Run **Section 2** to initialize the simulator engine.
4. Run **Section 3A (Host)** or **Section 3B (Join)** to connect to the squad room.
5. Run **Section 4** to start the live telemetry stream.
6. Run **Section 5** to test placing tactical indicators.
7. Run **Section 6** to test biometrics / KIA downed states.
8. Run **Section 8** when finished to cleanly leave and clean up Firebase nodes.

### Option 2: Running via Terminal CLI
```bash
# Host a new room 'ALPHA' with callsign 'VIPER-1' running at 4.5 m/s:
python3 notebooks/player_simulator.py --mode host --room ALPHA --callsign VIPER-1 --radius 50 --speed 4.5 --hr 120

# Join an existing room 'ALPHA' with callsign 'BRAVO-2' using compact4 format:
python3 notebooks/player_simulator.py --mode join --room ALPHA --callsign BRAVO-2 --radius 30 --speed 3.5 --format compact4
```

# RadarMap - Jupyter Notebooks & Player Simulation

This directory contains Jupyter notebooks and Python scripts for simulating squad players in the **RadarMap** watchOS / iOS tactical application.

---

## 📁 Directory Contents

- [`player_simulation.ipynb`](file:///Users/cruiser/Documents/antigravity/jolly-hypatia/notebooks/player_simulation.ipynb): Interactive Jupyter notebook with setup cells, Host/Join operations, and live circular trajectory simulation.
- [`player_simulator.py`](file:///Users/cruiser/Documents/antigravity/jolly-hypatia/notebooks/player_simulator.py): Self-contained Python module and CLI script implementing the circular motion engine and Firebase RTDB synchronization.

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
| `HEART_RATE` | `float` | `115.0` | Heart rate in BPM (`0.0` simulates KIA / downed). |
| `CIRCLE_RADIUS_METERS` | `float` | `50.0` | Radius of circular path in meters. |
| `SPEED_MPS` | `float` | `4.5` | Movement speed along the circle in meters/second. |
| `UPDATE_INTERVAL_SEC` | `float` | `1.0` | Telemetry packet transmission interval in seconds. |

---

## 🚀 How to Run

### Option 1: Using Jupyter Notebook / VS Code
1. Open [`player_simulation.ipynb`](file:///Users/cruiser/Documents/antigravity/jolly-hypatia/notebooks/player_simulation.ipynb) in your Jupyter environment or IDE.
2. Edit your parameters in **Section 1 (Setup)**.
3. Run **Section 2** to initialize the simulator engine.
4. Run **Section 3A** to **Host** a new room OR **Section 3B** to **Join** an existing room.
5. Run **Section 4** to start the circular movement simulation and live Firebase telemetry stream.
6. Run **Section 5** when finished to clean up or leave the room.

### Option 2: Running Directly via Terminal CLI
```bash
# Host a new room 'ALPHA' with callsign 'VIPER-1' running at 5 m/s around coordinates:
python3 notebooks/player_simulator.py --mode host --room ALPHA --callsign VIPER-1 --radius 50 --speed 5.0 --hr 120

# Join an existing room 'ALPHA' with callsign 'BRAVO-2':
python3 notebooks/player_simulator.py --mode join --room ALPHA --callsign BRAVO-2 --radius 30 --speed 3.5
```

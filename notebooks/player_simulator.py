"""
RadarMap Player Simulator
Simulates squad players moving in circular or tactical trajectories around GPS coordinates
and streams live telemetry and tactical indicators to Firebase Realtime Database.
Matches the Swift WatchOS/iOS client schema and communication protocol.
"""

import math
import time
import hashlib
import json
import uuid
import urllib.request
import urllib.error
from typing import Optional, Dict, Any, Tuple, List


class RadarPlayerSimulator:
    """
    Simulates a single squad member connected to RadarMap Firebase Realtime Database.
    
    Supports:
    - Lean 4-element compact array telemetry ([lat, lng, hr, ts])
    - Extended 6-element and 7-element legacy telemetry formats
    - Hosting & joining rooms with case-insensitive IDs and SHA-256 PIN security
    - Real-time geodesic bearing & Course Over Ground (COG) calculation
    - Placing and clearing Tactical Indicators (Squad Orders & Enemy Indicators)
    - Constant bandwidth rate adaptation R_max(P) = R_base * min(1.0, N / P)
    - Biometrics & KIA / Downed state simulation (HR = 0.0 BPM)
    - Dead reckoning & delta gating with heartbeat fallback
    """

    # Constants matching AppConstants.swift
    DEFAULT_DATABASE_URL = "https://radarmap-8adf0-default-rtdb.firebaseio.com"
    METERS_PER_DEG_LAT = 111139.0
    CONSTANT_BANDWIDTH_PLAYER_THRESHOLD = 12
    BASELINE_MAX_UPDATE_RATE_HZ = 1.0
    MIN_DISPLACEMENT_FOR_COG_METERS = 0.5
    FREE_TIER_MAX_CAPACITY = 4
    PRO_TIER_MAX_CAPACITY = 999

    # Tactical Indicator types
    SQUAD_ORDERS = ["watchHere", "goHere", "attackHere"]
    ENEMY_INDICATORS = ["infantry", "lightVehicle", "heavyVehicle"]

    def __init__(
        self,
        callsign: str = "VIPER-1",
        room_name: str = "ALPHA",
        pin: Optional[str] = None,
        latitude: float = 37.785834,
        longitude: float = -122.406417,
        altitude: Optional[float] = None,
        heart_rate: float = 85.0,
        circle_radius_meters: float = 50.0,
        speed_mps: float = 3.0,
        update_interval_sec: float = 1.0,
        database_url: str = DEFAULT_DATABASE_URL,
        member_id: Optional[str] = None,
        color_hex: str = "#00FF66",
        telemetry_format: str = "compact4",  # "compact4", "compact6", "compact7", or "dict"
        enable_delta_gating: bool = False,
        min_movement_delta_meters: float = 3.5,
        min_hr_delta_bpm: float = 12.0,
        heartbeat_interval_sec: float = 7.5,
    ):
        self.callsign = callsign.strip()
        self.room_name = room_name.strip().upper()
        self.pin = pin.strip() if pin else ""
        self.center_lat = latitude
        self.center_lon = longitude
        self.altitude = altitude
        self.heart_rate = heart_rate
        self.radius = max(0.1, circle_radius_meters)
        self.speed = max(0.0, speed_mps)
        self.update_interval = max(0.1, update_interval_sec)
        self.database_url = database_url.rstrip("/")
        self.member_id = (member_id or f"sim_{uuid.uuid4().hex[:8]}").strip()
        self.color_hex = color_hex
        self.telemetry_format = telemetry_format
        
        # State tracking
        self.is_host = False
        self.is_connected = False
        self.is_running = False
        self.sequence_number = 0
        self.current_angle_rad = 0.0
        self.last_sent_lat: Optional[float] = None
        self.last_sent_lon: Optional[float] = None
        self.last_sent_hr: Optional[float] = None
        self.last_sent_time: float = 0.0
        
        # Delta gating parameters
        self.enable_delta_gating = enable_delta_gating
        self.min_movement_delta_meters = min_movement_delta_meters
        self.min_hr_delta_bpm = min_hr_delta_bpm
        self.heartbeat_interval_sec = heartbeat_interval_sec

    @staticmethod
    def sanitize_pin(pin: str) -> str:
        """Sanitizes PIN input, filtering digits up to 4 characters matching GameStateManager."""
        digits = [c for c in pin if c.isdigit()]
        return "".join(digits[:4])

    @staticmethod
    def hash_pin(pin: str, salt: str) -> str:
        """Computes SHA-256 hash matching FirebaseSyncManager: salt:pin"""
        sanitized = RadarPlayerSimulator.sanitize_pin(pin)
        if not sanitized:
            return ""
        combined = f"{salt}:{sanitized}"
        return hashlib.sha256(combined.encode("utf-8")).hexdigest()

    # MARK: - Rate Adaptation Equations
    @staticmethod
    def solve_max_update_rate_hz(
        player_count: int,
        player_threshold: int = CONSTANT_BANDWIDTH_PLAYER_THRESHOLD,
        baseline_rate_hz: float = BASELINE_MAX_UPDATE_RATE_HZ,
    ) -> float:
        """
        Solves for the maximum update rate (in Hz) given active player count:
        R_max(P) = R_base * min(1.0, N_threshold / max(1, P))
        """
        if player_count <= 0:
            return baseline_rate_hz
        if player_count <= player_threshold:
            return baseline_rate_hz
        return baseline_rate_hz * (float(player_threshold) / float(player_count))

    @staticmethod
    def solve_update_interval(
        player_count: int,
        player_threshold: int = CONSTANT_BANDWIDTH_PLAYER_THRESHOLD,
        baseline_rate_hz: float = BASELINE_MAX_UPDATE_RATE_HZ,
    ) -> float:
        """Solves for update interval in seconds corresponding to solve_max_update_rate_hz."""
        rate_hz = RadarPlayerSimulator.solve_max_update_rate_hz(
            player_count=player_count,
            player_threshold=player_threshold,
            baseline_rate_hz=baseline_rate_hz,
        )
        return 1.0 / rate_hz if rate_hz > 0 else (1.0 / baseline_rate_hz)

    # MARK: - Geodesic Navigation
    @staticmethod
    def calculate_bearing(start_lat: float, start_lon: float, end_lat: float, end_lon: float) -> float:
        """
        Calculates forward geodesic bearing / Course Over Ground (0 - 360 degrees)
        from start coordinate to end coordinate matching FirebaseSyncManager.calculateBearing.
        """
        deg_to_rad = math.pi / 180.0
        rad_to_deg = 180.0 / math.pi
        
        lat1 = start_lat * deg_to_rad
        lon1 = start_lon * deg_to_rad
        lat2 = end_lat * deg_to_rad
        lon2 = end_lon * deg_to_rad
        
        d_lon = lon2 - lon1
        y = math.sin(d_lon) * math.cos(lat2)
        x = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(d_lon)
        radians_bearing = math.atan2(y, x)
        
        degrees = radians_bearing * rad_to_deg
        return (degrees + 360.0) % 360.0

    @staticmethod
    def distance_between_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        """Computes approximate distance in meters between two coordinates."""
        d_lat = (lat2 - lat1) * RadarPlayerSimulator.METERS_PER_DEG_LAT
        lat_rad = math.radians((lat1 + lat2) / 2.0)
        d_lon = (lon2 - lon1) * RadarPlayerSimulator.METERS_PER_DEG_LAT * math.cos(lat_rad)
        return math.hypot(d_lat, d_lon)

    # MARK: - HTTP REST Helper
    def _http_request(self, method: str, path: str, data: Optional[Any] = None) -> Tuple[int, Any]:
        """Performs an HTTP request against Firebase Realtime Database REST API."""
        url = f"{self.database_url}/{path.lstrip('/')}"
        req = urllib.request.Request(url, method=method)
        req.add_header("Content-Type", "application/json")

        body_bytes = None
        if data is not None:
            body_bytes = json.dumps(data).encode("utf-8")

        try:
            with urllib.request.urlopen(req, data=body_bytes, timeout=10) as response:
                status_code = response.getcode()
                raw = response.read().decode("utf-8")
                res_data = json.loads(raw) if raw and raw != "null" else None
                return status_code, res_data
        except urllib.error.HTTPError as e:
            raw = e.read().decode("utf-8") if e.fp else ""
            res_data = json.loads(raw) if raw and raw != "null" else None
            return e.code, res_data
        except Exception as e:
            return -1, str(e)

    # MARK: - Trajectory Math
    def calculate_position(self, delta_time: float) -> Tuple[float, float, float]:
        """
        Advances position along the circular orbit based on delta_time and speed.
        Returns: (latitude, longitude, heading_degrees)
        """
        omega = self.speed / self.radius
        self.current_angle_rad = (self.current_angle_rad + omega * delta_time) % (2.0 * math.pi)

        offset_east = self.radius * math.cos(self.current_angle_rad)
        offset_north = self.radius * math.sin(self.current_angle_rad)

        lat_rad = math.radians(self.center_lat)
        meters_per_deg_lon = self.METERS_PER_DEG_LAT * math.cos(lat_rad)
        if meters_per_deg_lon == 0:
            meters_per_deg_lon = 1.0

        current_lat = self.center_lat + (offset_north / self.METERS_PER_DEG_LAT)
        current_lon = self.center_lon + (offset_east / meters_per_deg_lon)

        # Velocity tangent vector
        v_east = -math.sin(self.current_angle_rad)
        v_north = math.cos(self.current_angle_rad)

        heading_rad = math.atan2(v_east, v_north)
        heading_deg = (math.degrees(heading_rad) + 360.0) % 360.0

        return current_lat, current_lon, heading_deg

    # MARK: - Room Management
    def host_room(self, max_capacity: int = PRO_TIER_MAX_CAPACITY) -> bool:
        """Creates a new squad room on Firebase as Host matching SquadRoom schema."""
        now = time.time()
        pin_hash = self.hash_pin(self.pin, self.room_name) if self.pin else None
        has_pin = bool(self.pin)

        # Check if room already exists
        status, existing = self._http_request("GET", f"rooms/{self.room_name}.json")
        if status == 200 and existing and isinstance(existing, dict) and existing.get("id"):
            print(f"[ERROR] Room '{self.room_name}' already exists. Use join_room() or choose another room name.")
            return False

        host_member = {
            "id": self.member_id,
            "callsign": self.callsign,
            "isHost": True
        }

        room_payload = {
            "id": self.room_name,
            "hostId": self.member_id,
            "maxCapacity": max_capacity,
            "hasPin": has_pin,
            "createdAt": now,
            "lastActivityTimestamp": now,
            "members": {
                self.member_id: host_member
            },
            "indicators": {}
        }
        if pin_hash:
            room_payload["pinHash"] = pin_hash

        status, resp = self._http_request("PUT", f"rooms/{self.room_name}.json", room_payload)
        if 200 <= status < 300:
            self.is_host = True
            self.is_connected = True
            print(f"[SUCCESS] Hosted room '{self.room_name}' as '{self.callsign}' (Host: Yes, PIN: {'Enabled' if has_pin else 'None'}).")
            return True
        else:
            print(f"[ERROR] Failed to create room: HTTP {status} - {resp}")
            return False

    def join_room(self) -> bool:
        """Joins an existing squad room on Firebase."""
        status, room_data = self._http_request("GET", f"rooms/{self.room_name}.json")

        if status != 200 or not room_data or not isinstance(room_data, dict):
            print(f"[ERROR] Room '{self.room_name}' not found on server.")
            return False

        # Validate PIN if required
        has_pin = room_data.get("hasPin", False)
        expected_pin_hash = room_data.get("pinHash")
        if has_pin and expected_pin_hash:
            input_hash = self.hash_pin(self.pin, self.room_name)
            if input_hash != expected_pin_hash:
                print(f"[ERROR] Incorrect PIN for room '{self.room_name}'.")
                return False

        # Validate Callsign uniqueness
        members = room_data.get("members", {}) or {}
        trimmed_callsign = self.callsign.upper()
        for mid, mdata in members.items():
            if mid != self.member_id and isinstance(mdata, dict):
                if mdata.get("callsign", "").strip().upper() == trimmed_callsign:
                    print(f"[ERROR] Callsign '{self.callsign}' is already taken in room '{self.room_name}'.")
                    return False

        # Validate capacity
        max_cap = room_data.get("maxCapacity", self.PRO_TIER_MAX_CAPACITY)
        if len(members) >= max_cap and self.member_id not in members:
            print(f"[ERROR] Room '{self.room_name}' has reached maximum capacity ({max_cap}).")
            return False

        member_payload = {
            "id": self.member_id,
            "callsign": self.callsign,
            "isHost": False
        }

        status, resp = self._http_request("PUT", f"rooms/{self.room_name}/members/{self.member_id}.json", member_payload)
        if 200 <= status < 300:
            self.is_host = False
            self.is_connected = True
            print(f"[SUCCESS] Joined room '{self.room_name}' as '{self.callsign}'.")
            return True
        else:
            print(f"[ERROR] Failed to register member: HTTP {status} - {resp}")
            return False

    # MARK: - Telemetry Dispatch
    def should_suppress_update(self, lat: float, lon: float, hr: float, now: float) -> bool:
        """Implements Dead Reckoning & Delta Gating matching AppConstants.Timing.DeltaGating."""
        if not self.enable_delta_gating:
            return False

        # If heartbeat interval exceeded, must send update
        if self.last_sent_time > 0 and (now - self.last_sent_time) >= self.heartbeat_interval_sec:
            return False

        # First update always sent
        if self.last_sent_lat is None or self.last_sent_lon is None or self.last_sent_hr is None:
            return False

        # Check movement delta
        distance_moved = self.distance_between_meters(self.last_sent_lat, self.last_sent_lon, lat, lon)
        hr_delta = abs(self.heart_rate - self.last_sent_hr)

        if distance_moved < self.min_movement_delta_meters and hr_delta < self.min_hr_delta_bpm:
            return True  # Suppress upload (gated)

        return False

    def send_telemetry(self, lat: float, lon: float, hdg: float, altitude: Optional[float] = None) -> bool:
        """
        Sends telemetry packet to Firebase Realtime Database at /telemetry/{roomId}/{memberId}.json.
        Supports 4-element compact array (default), 6-element, 7-element, and dict formats.
        """
        now = time.time()
        self.sequence_number += 1
        alt = altitude if altitude is not None else self.altitude

        # Construct payload based on telemetry_format
        if self.telemetry_format == "compact4":
            # Primary ultra-lean 4-element format: [lat, lng, hr, ts]
            payload = [lat, lon, self.heart_rate, now]
        elif self.telemetry_format == "compact6":
            # 6-element format: [lat, lng, alt, hr, seq, ts]
            payload = [lat, lon, alt if alt is not None else 0.0, self.heart_rate, self.sequence_number, now]
        elif self.telemetry_format == "compact7":
            # 7-element legacy format: [lat, lng, alt, hdg, hr, seq, ts]
            payload = [lat, lon, alt if alt is not None else 0.0, hdg, self.heart_rate, self.sequence_number, now]
        else:
            # JSON dictionary format
            payload = {
                "lat": lat,
                "lng": lon,
                "hdg": hdg,
                "hr": self.heart_rate,
                "seq": self.sequence_number,
                "ts": now
            }
            if alt is not None:
                payload["alt"] = alt

        status, _ = self._http_request("PUT", f"telemetry/{self.room_name}/{self.member_id}.json", payload)
        if 200 <= status < 300:
            self.last_sent_lat = lat
            self.last_sent_lon = lon
            self.last_sent_hr = self.heart_rate
            self.last_sent_time = now
            return True
        return False

    def touch_activity(self):
        """Refreshes lastActivityTimestamp for the room."""
        now = time.time()
        self._http_request("PUT", f"rooms/{self.room_name}/lastActivityTimestamp.json", now)

    # MARK: - Tactical Indicators API
    def place_tactical_indicator(self, indicator_type: str, lat: float, lon: float, indicator_id: Optional[str] = None) -> Optional[str]:
        """
        Places a tactical indicator on the server at /tactical/{roomId}/{indicatorId}.json
        and updates /tactical/{roomId}/_updatedAt.json.
        """
        ind_id = indicator_id or f"ind_{uuid.uuid4().hex[:8]}"
        now = time.time()
        payload = {
            "id": ind_id,
            "type": indicator_type,
            "latitude": lat,
            "longitude": lon,
            "placedByMemberId": self.member_id,
            "placedByCallsign": self.callsign,
            "timestamp": now
        }
        status, _ = self._http_request("PUT", f"tactical/{self.room_name}/{ind_id}.json", payload)
        if 200 <= status < 300:
            self._http_request("PUT", f"tactical/{self.room_name}/_updatedAt.json", now)
            print(f"[TACTICAL] Placed indicator '{indicator_type}' ({ind_id}) at ({lat:.6f}, {lon:.6f}).")
            return ind_id
        return None

    def remove_tactical_indicator(self, indicator_id: str) -> bool:
        """Deletes a tactical indicator and updates _updatedAt timestamp."""
        status, _ = self._http_request("DELETE", f"tactical/{self.room_name}/{indicator_id}.json")
        now = time.time()
        self._http_request("PUT", f"tactical/{self.room_name}/_updatedAt.json", now)
        return 200 <= status < 300

    def clear_all_tactical_indicators(self) -> bool:
        """Purges all tactical indicators in the room."""
        status, _ = self._http_request("DELETE", f"tactical/{self.room_name}.json")
        now = time.time()
        self._http_request("PUT", f"tactical/{self.room_name}/_updatedAt.json", now)
        return 200 <= status < 300

    def get_tactical_indicators(self) -> Dict[str, Any]:
        """Fetches active tactical indicators from the server."""
        status, data = self._http_request("GET", f"tactical/{self.room_name}.json")
        if status == 200 and isinstance(data, dict):
            return {k: v for k, v in data.items() if not k.startswith("_")}
        return {}

    # MARK: - Biometrics & Player State
    def set_heart_rate(self, bpm: float):
        """Updates simulated heart rate (0.0 BPM simulates Downed / KIA)."""
        self.heart_rate = bpm
        state = "DOWNED / KIA" if bpm == 0.0 else f"{bpm:.0f} BPM"
        print(f"[BIOMETRICS] Heart rate updated to {state}.")

    def set_downed(self, downed: bool = True):
        """Quick toggle for KIA / Downed state."""
        self.set_heart_rate(0.0 if downed else 85.0)

    # MARK: - Room Cleanup & Leave
    def leave_room(self):
        """Leaves the room and cleans up Firebase entries matching FirebaseSyncManager."""
        if not self.is_connected:
            return

        print(f"\n[INFO] Leaving room '{self.room_name}'...")
        if self.is_host:
            # Host disbanding room: delete room node, telemetry node, and tactical node
            self._http_request("DELETE", f"rooms/{self.room_name}.json")
            self._http_request("DELETE", f"telemetry/{self.room_name}.json")
            self._http_request("DELETE", f"tactical/{self.room_name}.json")
            print(f"[SUCCESS] Disbanded room '{self.room_name}' and purged all nodes.")
        else:
            # Check remaining members
            status, room_data = self._http_request("GET", f"rooms/{self.room_name}.json")
            members = (room_data.get("members", {}) if isinstance(room_data, dict) else {}) or {}
            remaining = [m for m in members if m != self.member_id]

            self._http_request("DELETE", f"rooms/{self.room_name}/members/{self.member_id}.json")
            self._http_request("DELETE", f"telemetry/{self.room_name}/{self.member_id}.json")

            if not remaining:
                # Room now empty: delete room node, telemetry node, and tactical node
                self._http_request("DELETE", f"rooms/{self.room_name}.json")
                self._http_request("DELETE", f"telemetry/{self.room_name}.json")
                self._http_request("DELETE", f"tactical/{self.room_name}.json")
                print(f"[SUCCESS] Room '{self.room_name}' is now empty. Purged entire room and tactical nodes.")
            else:
                print(f"[SUCCESS] Removed player '{self.callsign}' from room '{self.room_name}'.")

        self.is_connected = False
        self.is_running = False

    # MARK: - Main Simulation Loop
    def run_simulation(self, duration_sec: Optional[float] = None):
        """
        Starts circular telemetry simulation loop.
        Updates position in a circle at `speed` m/s with `radius` meters,
        broadcasting telemetry every `update_interval` seconds.
        """
        if not self.is_connected:
            print("[ERROR] Must host or join a room before running simulation.")
            return

        self.is_running = True
        start_time = time.time()
        last_tick = start_time
        ticks = 0

        print(f"\n🚀 Simulation started for player '{self.callsign}' in room '{self.room_name}'!")
        print(f"📍 Center: ({self.center_lat:.6f}, {self.center_lon:.6f})")
        print(f"🔄 Radius: {self.radius:.1f} m | Speed: {self.speed:.1f} m/s | Interval: {self.update_interval:.1f}s")
        print(f"❤️ Heart Rate: {self.heart_rate:.0f} BPM | Format: {self.telemetry_format}")
        print("Press Ctrl+C or Interrupt Kernel to stop...\n")

        try:
            while self.is_running:
                now = time.time()
                elapsed = now - start_time
                if duration_sec is not None and elapsed >= duration_sec:
                    print(f"\n⏱️ Reached duration limit ({duration_sec}s). Stopping simulation.")
                    break

                dt = now - last_tick
                last_tick = now

                lat, lon, hdg = self.calculate_position(dt)

                if self.should_suppress_update(lat, lon, self.heart_rate, now):
                    status_mark = "⚡"  # Gated / Delta suppressed
                    ok = True
                else:
                    ok = self.send_telemetry(lat, lon, hdg)
                    status_mark = "✅" if ok else "❌"

                ticks += 1
                if ticks % 10 == 0:
                    self.touch_activity()

                print(
                    f"\r{status_mark} [T+{elapsed:6.1f}s] Lat: {lat:10.6f} | Lon: {lon:11.6f} | "
                    f"Hdg: {hdg:5.1f}° | HR: {self.heart_rate:3.0f} BPM | Seq: {self.sequence_number:<5}",
                    end="",
                    flush=True
                )

                time.sleep(self.update_interval)

        except KeyboardInterrupt:
            print("\n\n⏹️ Simulation interrupted by user.")
        finally:
            self.is_running = False
            print(f"\nCompleted {self.sequence_number} telemetry updates.")


def main():
    import argparse

    parser = argparse.ArgumentParser(description="RadarMap Player Simulator")
    parser.add_argument("--mode", choices=["host", "join"], default="host", help="Host a new room or join existing")
    parser.add_argument("--callsign", default="VIPER-1", help="Player callsign")
    parser.add_argument("--room", default="ALPHA", help="Room name")
    parser.add_argument("--pin", default="", help="Optional 4-digit PIN")
    parser.add_argument("--lat", type=float, default=37.785834, help="Center latitude")
    parser.add_argument("--lon", type=float, default=-122.406417, help="Center longitude")
    parser.add_argument("--hr", type=float, default=110.0, help="Heart rate BPM")
    parser.add_argument("--radius", type=float, default=40.0, help="Circle radius in meters")
    parser.add_argument("--speed", type=float, default=4.0, help="Speed in m/s")
    parser.add_argument("--interval", type=float, default=1.0, help="Update interval in seconds")
    parser.add_argument("--format", choices=["compact4", "compact6", "compact7", "dict"], default="compact4", help="Telemetry format")
    parser.add_argument("--duration", type=float, default=None, help="Run duration in seconds (optional)")

    args = parser.parse_args()

    sim = RadarPlayerSimulator(
        callsign=args.callsign,
        room_name=args.room,
        pin=args.pin,
        latitude=args.lat,
        longitude=args.lon,
        heart_rate=args.hr,
        circle_radius_meters=args.radius,
        speed_mps=args.speed,
        update_interval_sec=args.interval,
        telemetry_format=args.format,
    )

    success = sim.host_room() if args.mode == "host" else sim.join_room()
    if success:
        try:
            sim.run_simulation(duration_sec=args.duration)
        finally:
            sim.leave_room()


if __name__ == "__main__":
    main()

"""
RadarMap Player Simulator
Simulates a single player moving in a circular orbit around a GPS coordinate
and streams live telemetry to Firebase Realtime Database.
"""

import math
import time
import hashlib
import json
import urllib.request
import urllib.error
from typing import Optional, Dict, Any, Tuple


class RadarPlayerSimulator:
    def __init__(
        self,
        callsign: str = "GHOST-1",
        room_name: str = "ALPHA",
        pin: Optional[str] = None,
        latitude: float = 37.785834,
        longitude: float = -122.406417,
        heart_rate: float = 85.0,
        circle_radius_meters: float = 50.0,
        speed_mps: float = 5.0,
        update_interval_sec: float = 1.0,
        database_url: str = "https://radarmap-8adf0-default-rtdb.firebaseio.com",
        member_id: Optional[str] = None,
        color_hex: str = "#00FF66",
    ):
        self.callsign = callsign.strip()
        self.room_name = room_name.strip().upper()
        self.pin = pin.strip() if pin else ""
        self.center_lat = latitude
        self.center_lon = longitude
        self.heart_rate = heart_rate
        self.radius = max(0.1, circle_radius_meters)
        self.speed = max(0.0, speed_mps)
        self.update_interval = max(0.1, update_interval_sec)
        self.database_url = database_url.rstrip("/")
        # In RadarMap, memberId defaults to callsign so other clients display the callsign correctly
        self.member_id = (member_id or self.callsign).strip()
        self.color_hex = color_hex
        
        self.is_host = False
        self.is_connected = False
        self.is_running = False
        self.sequence_number = 0
        self.current_angle_rad = 0.0  # Angle on circle in radians
        
        # Geodesic constants (WGS-84 / AppConstants)
        self.meters_per_deg_lat = 111139.0

    @staticmethod
    def hash_pin(pin: str, salt: str) -> str:
        """Computes SHA-256 hash matching FirebaseSyncManager: salt:pin"""
        trimmed = pin.strip()
        if not trimmed:
            return ""
        combined = f"{salt}:{trimmed}"
        return hashlib.sha256(combined.encode("utf-8")).hexdigest()

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

    def calculate_position(self, delta_time: float) -> Tuple[float, float, float]:
        """
        Advances position along the circular orbit based on delta_time and speed.
        Returns: (latitude, longitude, heading_degrees)
        """
        # Angular velocity: omega = speed / radius (rad/sec)
        omega = self.speed / self.radius
        self.current_angle_rad = (self.current_angle_rad + omega * delta_time) % (2.0 * math.pi)

        # Position offsets in meters (x = East, y = North)
        offset_east = self.radius * math.cos(self.current_angle_rad)
        offset_north = self.radius * math.sin(self.current_angle_rad)

        # Convert meter offsets to GPS coordinates
        lat_rad = math.radians(self.center_lat)
        meters_per_deg_lon = self.meters_per_deg_lat * math.cos(lat_rad)
        if meters_per_deg_lon == 0:
            meters_per_deg_lon = 1.0

        current_lat = self.center_lat + (offset_north / self.meters_per_deg_lat)
        current_lon = self.center_lon + (offset_east / meters_per_deg_lon)

        # Heading is the direction of instantaneous velocity tangent to the circle:
        # v_East = -omega * radius * sin(theta) = -speed * sin(theta)
        # v_North = omega * radius * cos(theta) = speed * cos(theta)
        v_east = -math.sin(self.current_angle_rad)
        v_north = math.cos(self.current_angle_rad)

        # Geodesic bearing: 0 deg = North, 90 deg = East, 180 deg = South, 270 deg = West
        heading_rad = math.atan2(v_east, v_north)
        heading_deg = (math.degrees(heading_rad) + 360.0) % 360.0

        return current_lat, current_lon, heading_deg

    def host_room(self, max_capacity: int = 12) -> bool:
        """Creates a new squad room on Firebase as Host."""
        now = time.time()
        pin_hash = self.hash_pin(self.pin, self.room_name) if self.pin else None
        has_pin = bool(self.pin)

        # Check if room already exists
        status, existing = self._http_request("GET", f"rooms/{self.room_name}.json")
        if status == 200 and existing and isinstance(existing, dict) and existing.get("id"):
            print(f"[ERROR] Room '{self.room_name}' already exists. Use join_room() instead or pick another room name.")
            return False

        lat, lon, hdg = self.calculate_position(0.0)

        host_member = {
            "id": self.member_id,
            "callsign": self.callsign,
            "latitude": lat,
            "longitude": lon,
            "altitude": 0.0,
            "heading": hdg,
            "heartRate": self.heart_rate,
            "batteryLevel": 1.0,
            "lastUpdatedTimestamp": now,
            "sequenceNumber": self.sequence_number,
            "status": "active" if self.heart_rate > 0 else "downed",
            "isHost": True,
            "colorHex": self.color_hex
        }

        room_payload = {
            "id": self.room_name,
            "hostId": self.member_id,
            "maxCapacity": max_capacity,
            "hasPin": has_pin,
            "pinHash": pin_hash,
            "createdAt": now,
            "lastActivityTimestamp": now,
            "members": {
                self.member_id: host_member
            },
            "indicators": {}
        }

        status, resp = self._http_request("PUT", f"rooms/{self.room_name}.json", room_payload)
        if 200 <= status < 300:
            self.is_host = True
            self.is_connected = True
            print(f"[SUCCESS] Hosted room '{self.room_name}' as '{self.callsign}'.")
            return True
        else:
            print(f"[ERROR] Failed to create room: HTTP {status} - {resp}")
            return False

    def join_room(self) -> bool:
        """Joins an existing squad room on Firebase."""
        now = time.time()
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
        max_cap = room_data.get("maxCapacity", 12)
        if len(members) >= max_cap and self.member_id not in members:
            print(f"[ERROR] Room '{self.room_name}' has reached maximum capacity ({max_cap}).")
            return False

        lat, lon, hdg = self.calculate_position(0.0)

        member_payload = {
            "id": self.member_id,
            "callsign": self.callsign,
            "latitude": lat,
            "longitude": lon,
            "altitude": 0.0,
            "heading": hdg,
            "heartRate": self.heart_rate,
            "batteryLevel": 1.0,
            "lastUpdatedTimestamp": now,
            "sequenceNumber": self.sequence_number,
            "status": "active" if self.heart_rate > 0 else "downed",
            "isHost": False,
            "colorHex": self.color_hex
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

    def send_telemetry(self, lat: float, lon: float, hdg: float) -> bool:
        """Sends a lean 4-element telemetry packet [lat, lng, hr, ts] to Firebase."""
        now = time.time()
        self.sequence_number += 1
        
        # 4-element compact array matching TelemetryPacket.toCompactArray()
        payload = [
            lat,
            lon,
            self.heart_rate,
            now
        ]

        status, _ = self._http_request("PUT", f"telemetry/{self.room_name}/{self.member_id}.json", payload)
        return 200 <= status < 300

    def touch_activity(self):
        """Refreshes lastActivityTimestamp for the room."""
        now = time.time()
        self._http_request("PUT", f"rooms/{self.room_name}/lastActivityTimestamp.json", now)

    def leave_room(self):
        """Leaves the room and cleans up Firebase entries."""
        if not self.is_connected:
            return

        print(f"\n[INFO] Leaving room '{self.room_name}'...")
        if self.is_host:
            # Disband room
            self._http_request("DELETE", f"rooms/{self.room_name}.json")
            self._http_request("DELETE", f"telemetry/{self.room_name}.json")
            self._http_request("DELETE", f"tactical/{self.room_name}.json")
            print(f"[SUCCESS] Disbanded room '{self.room_name}'.")
        else:
            # Remove member and telemetry node
            self._http_request("DELETE", f"rooms/{self.room_name}/members/{self.member_id}.json")
            self._http_request("DELETE", f"telemetry/{self.room_name}/{self.member_id}.json")
            print(f"[SUCCESS] Removed player '{self.callsign}' from room '{self.room_name}'.")

        self.is_connected = False
        self.is_running = False

    def run_simulation(self, duration_sec: Optional[float] = None):
        """
        Starts the telemetry simulation loop.
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
        print(f"❤️ Heart Rate: {self.heart_rate:.0f} BPM")
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
                ok = self.send_telemetry(lat, lon, hdg)

                ticks += 1
                if ticks % 10 == 0:
                    self.touch_activity()

                status_mark = "✅" if ok else "❌"
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
        update_interval_sec=args.interval
    )

    success = sim.host_room() if args.mode == "host" else sim.join_room()
    if success:
        try:
            sim.run_simulation(duration_sec=args.duration)
        finally:
            sim.leave_room()


if __name__ == "__main__":
    main()

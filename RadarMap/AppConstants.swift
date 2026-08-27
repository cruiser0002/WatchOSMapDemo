import Foundation
import CoreLocation
import CoreBluetooth
import SwiftUI

/// Centralized configuration constants for the RadarMap application.
/// Modify these values to adjust application behaviors, thresholds, intervals, and UI scales.
public enum AppConstants {
    
    // MARK: - Local Storage & UserDefaults Keys
    public enum Storage {
        public static let userCallsignKey = "user_callsign"
        public static let savedRoomNameKey = "saved_room_name"
        public static let userMemberIdKey = "user_member_id"
        public static let radarColorThemeKey = "radar_color_theme"
        public static let hasUnlimitedSquadUnlockKey = "hasUnlimitedSquadUnlock"
        public static let savedPinKey = "saved_pin"
    }
    
    // MARK: - Networking & Realtime Database
    public enum Network {
        /// Firebase Realtime Database default endpoint URL
        public static let defaultDatabaseURL = "https://radarmap-8adf0-default-rtdb.firebaseio.com"
        
        /// Firebase Realtime Database path endpoints
        public enum Endpoints {
            public static let rooms = "rooms"
            public static let telemetry = "telemetry"
            public static let tactical = "tactical"
            public static let lastActivityTimestamp = "lastActivityTimestamp"
            public static let members = "members"
        }
        
        /// Bluetooth Low Energy (BLE) Radar Constants
        public enum Bluetooth {
            public static let radarServiceUUID = CBUUID(string: "A495FA01-C5B1-4B44-B512-1370F02D74DE")
            public static let roomDataCharacteristicUUID = CBUUID(string: "A495FA02-C5B1-4B44-B512-1370F02D74DE")
            public static let advertisementPrefix = "RM:"
            public static let defaultLocalName = "Radar-Room"
        }
        
        /// Quality monitoring and latency grading thresholds
        public enum Quality {
            public static let initialLatencyMs: Double = 50.0
            public static let initialJitterMs: Double = 0.0
            public static let emaAlpha: Double = 0.2 // Weight for Exponential Moving Average
            
            // Latency boundaries in milliseconds
            public static let excellentLatencyMs: Double = 150.0
            public static let excellentJitterMs: Double = 50.0
            public static let goodLatencyMs: Double = 300.0
            public static let goodJitterMs: Double = 100.0
            public static let poorLatencyMs: Double = 700.0
        }
    }
    
    // MARK: - In-App Purchase & Subscriptions
    public enum Subscription {
        public static let mockRevenueCatApiKey = "appl_BImCxHPjqYqcXAVSdaxcyvcHhbw"
        public static let revenueCatApiKey: String = Bundle.main.infoDictionary?["REVENUECAT_API_KEY"] as? String ?? mockRevenueCatApiKey
        public static let entitlementID = "radarmap_pro"
        public static let offeringID = "default"
        public static let packageID = "$rc_lifetime"
        public static let productID = "com.radarmap.watch.pro"
        public static let lifetimePriceString = "$9.99"
        public static let promotionalPriceMessage: String? = nil
        
        /// Squad player capacity limits
        public static let freeTierMaxCapacity: Int = 4
        public static let proTierMaxCapacity: Int = 999
        
        /// Tactical Indicators Constants
        public static let maxEnemyIndicatorsCount: Int = 20
        public static let enemyIndicatorFadeDurationSeconds: TimeInterval = 300.0 // 5 minutes
        public static let indicatorHoldToDeleteDurationSeconds: TimeInterval = 1.2
        
        /// Mock purchase simulated sleep delays
        public static let mockPurchaseSleepNanoseconds: UInt64 = 1_000_000_000
        public static let mockRestoreSleepNanoseconds: UInt64 = 800_000_000
    }
    
    // MARK: - Privacy & Policy
    public enum Policy {
        public static let privacyPolicyURL = "https://radarmap.app/privacy"
        public static let contactEmail = "sweetdreamsdeveloper@gmail.com"
        public static let contactFormURL = "https://forms.gle/pCuy2zJtSfLoyqj16"
        
        public static let summary = "Radar Map is committed to protecting your privacy. We collect real-time location and heart rate data solely for live squad tactical coordination during active sessions."
        public static let locationDataDescription = "Location data (GPS coordinates, heading, course over ground) is streamed in real time to your squad room and is automatically purged when the room is disbanded or after 7 days of inactivity."
        public static let healthDataDescription = "Heart rate biometrics are read via Apple HealthKit to display squad stress levels and vital status. This data is never sold, used for advertising, or shared with third parties."
        public static let dataRetentionDescription = "We do not sell your data or use tracking cookies. All session data is ephemeral and tied to temporary squad rooms."
    }
    
    // MARK: - Location & Geodesic Navigation
    public enum Location {
        /// Default fallback coordinate (San Francisco, CA)
        public static let fallbackLatitude: Double = 37.785834
        public static let fallbackLongitude: Double = -122.406417
        public static let fallbackCoordinate = CLLocationCoordinate2D(
            latitude: fallbackLatitude,
            longitude: fallbackLongitude
        )
        
        /// Sensor sensitivity filters
        public static let distanceFilterMeters: Double = 1.0 // 1 meter update sensitivity
        public static let headingFilterDegrees: Double = 2.0  // 2 degree heading sensitivity
        
        /// Meters per degree latitude approximation (WGS-84 geodesic)
        public static let metersPerDegreeLatitude: Double = 111_139.0
        
        /// Metric conversion factors
        public static let metersPerKilometer: Double = 1000.0
        
        /// Angular trigonometry and calculation factors
        public static let degreesToRadiansFactor: Double = .pi / 180.0
        public static let radiansToDegreesFactor: Double = 180.0 / .pi
        public static let fullCircleDegrees: Double = 360.0
        public static let vectorEpsilon: Double = 1e-6
        
        /// Speed-weighted heading blending thresholds (m/s)
        public static let stationarySpeedThresholdMps: Double = 0.5 // ~1.1 mph: 100% Compass
        public static let runningSpeedThresholdMps: Double = 2.5    // ~5.6 mph: 100% GPS COG
        
        /// Minimum displacement required to compute Course Over Ground (COG)
        /// Set to 2.0m to filter out GPS drift / noise jitter that causes player headings to bob up and down
        public static let minDisplacementForCourseOverGroundMeters: Double = 2.0
        
        /// Default map delta zoom span
        public static let defaultMapSpanDelta: Double = 0.005
    }
    
    // MARK: - HealthKit & Biometrics
    public enum Health {
        public static let defaultRestingHeartRate: Double = 75.0 // BPM
        public static let flatlineHeartRate: Double = 0.0        // BPM for KIA / Downed
        public static let referenceBpm: Double = 100.0           // Reference BPM for scanning sweep (BPM / 100 equation)
        public static let secondsPerMinute: Double = 60.0
        
        /// Mock fallback values for simulator/host execution
        public static let mockRestingHeartRate: Double = 78.0
        public static let mockWorkoutHeartRate: Double = 82.0
        
        /// Heart rate pulse clamping bounds for visual pulse animation
        public static let minPulseBpm: Double = 30.0
        public static let maxPulseBpm: Double = 220.0
        
        /// Heart rate stress level thresholds (BPM)
        public enum Zones {
            public static let blueMax: Double = 60.0    // < 60: Rest (Blue)
            public static let greenMax: Double = 100.0  // 60 - 99: Normal (Green)
            public static let yellowMax: Double = 140.0 // 100 - 139: Elevated (Yellow)
            public static let orangeMax: Double = 175.0 // 140 - 174: High Stress (Orange)
            // >= 175: Max Stress (Red)
        }
    }
    
    // MARK: - Timing, Intervals & Rates
    public enum Timing {
        /// Standard time unit conversion factors
        public static let secondsPerMinute: Double = 60.0
        public static let secondsPerHour: Double = 3600.0
        public static let secondsPerDay: Double = 86400.0
        public static let millisecondsPerSecond: Double = 1000.0
        
        /// Telemetry upload and polling adaptive intervals (in seconds)
        public enum AdaptiveRate {
            public static let criticalInterval: TimeInterval = 5.0
            public static let poorInterval: TimeInterval = 4.0
            public static let largeSquadInterval: TimeInterval = 3.0
            public static let mediumSquadInterval: TimeInterval = 2.0
            public static let baselineInterval: TimeInterval = 1.0
            public static let minimumInterval: TimeInterval = 1.0
            public static let wristDownPollingInterval: TimeInterval = 10.0 // Low power throttle when wrist is down
            
            // Member count thresholds for throttling
            public static let largeSquadMemberCount: Int = 50
            public static let mediumSquadMemberCount: Int = 20
            public static let smallSquadMemberCount: Int = 4
            
            // Threshold for triggering interval update
            public static let intervalChangeEpsilon: Double = 0.01
        }
        
        /// Refresh rates for display animations and dead-reckoning smoothing
        public enum DisplayRefresh {
            public static let radarUIHz: Double = 20.0
            public static let radarUIIntervalSeconds: TimeInterval = 1.0 / 20.0
            public static let teammateDeadReckoningHz: Double = 5.0
            public static let teammateDeadReckoningIntervalSeconds: TimeInterval = 1.0 / 5.0
        }
        
        /// Movement and telemetry delta gating thresholds (Dead Reckoning optimization)
        public enum DeltaGating {
            public static let minMovementDeltaMeters: Double = 3.5 // Ignore natural GPS drift (< 3.5m)
            public static let minHeartRateDeltaBpm: Double = 12.0  // Ignore respiration & PPG sensor jitter (< 12 BPM)
            public static let staleHeartbeatFrequencyDivisor: Double = 2.0 // Upload fallback is twice as frequent as stale timeout duration
            public static let heartbeatFallbackIntervalSeconds: TimeInterval = 10.0 // Fixed fallback timer constant for upload liveness (10s)
        }
        
        /// Theoretical constant bandwidth rate adaptation equation constants
        public enum ConstantBandwidth {
            public static let playerThreshold: Int = 12
            public static let baselineMaxUpdateRateHz: Double = 1.0
        }
        
        /// Stale telemetry timeout constants
        public enum Stale {
            /// Stale timeout multiplier (M): timeout = M * updateInterval
            public static let defaultTimeoutMultiplier: Double = 15.0
            public static let defaultUpdateInterval: TimeInterval = 1.0
        }
        
        /// Inactivity room cleanup threshold
        public enum Inactivity {
            public static let idleCutoffDays: Double = 7.0
            public static let secondsPerDay: Double = 86400.0
        }
        
        /// Hold-to-Die gesture timing parameters
        public enum DeathHold {
            public static let delayBeforeChargeSeconds: TimeInterval = 1.0
            public static let chargeDurationSeconds: TimeInterval = 3.0
            public static let timerTickIntervalSeconds: TimeInterval = 0.03
            public static let actionHoldDurationSeconds: TimeInterval = 1.2
            public static let holdTimerTickIntervalSeconds: TimeInterval = 0.02
        }
    }
    
    // MARK: - UI, Display & Styling
    public enum UI {
        public static let defaultCallsign = ""
        public static let defaultRoomName = ""
        public static let defaultSquadPrefix = "SQUAD-"
        public static let defaultTacticalColorHex = "#00FF66"
        public static let defaultBatteryLevel: Double = 0.95
        
        /// Gesture timing & interaction parameters
        public enum Gestures {
            public static let actionHoldDurationSeconds: TimeInterval = 1.2
            public static let holdTimerTickIntervalSeconds: TimeInterval = 0.02
            public static let actionAnimationDurationSeconds: Double = 0.25
        }
        
        /// PIN Input formatting & length
        public static let maxPinLength: Int = 4
        
        /// Voice dictation word mapping for PIN entry
        public static let pinWordMapping: [String: String] = [
            "zero": "0", "oh": "0",
            "one": "1", "won": "1",
            "two": "2", "to": "2", "too": "2",
            "three": "3",
            "four": "4", "for": "4", "fore": "4",
            "five": "5",
            "six": "6",
            "seven": "7",
            "eight": "8", "ate": "8",
            "nine": "9"
        ]
        
        /// Radar scale distance bounds (meters)
        public enum RadarScale {
            public static let defaultScaleMeters: Double = 100.0
            public static let minScaleMeters: Double = 10.0
            public static let maxWatchScaleMeters: Double = 5000.0
            public static let maxiOSScaleMeters: Double = 20000.0
            public static let crownStepMeters: Double = 10.0
            
            /// Display geometry ratios
            public static let radarRadiusRatio: Double = 0.44
            public static let crosshairExtensionRatio: Double = 1.05
            public static let centerReticleSize: Double = 9.0
            
            #if os(watchOS)
            public static let referenceScreenAspectRatio: Double = 1.22 // Height / Width for Apple Watch
            #else
            public static let referenceScreenAspectRatio: Double = 2.16 // Height / Width for iPhone
            #endif
            
            /// Range ring fractional ratios from center
            public static let rangeRingRatios: [Double] = [0.25, 0.50, 0.75, 1.0]
            
            /// Converts a radar scale in meters to an equivalent MapKit coordinate span latitude delta.
            public static func mapSpanDelta(forRadarScaleMeters radarScaleMeters: Double) -> Double {
                let visibleMetersLat = (radarScaleMeters / radarRadiusRatio) * referenceScreenAspectRatio
                return visibleMetersLat / AppConstants.Location.metersPerDegreeLatitude
            }
            
            /// Converts a MapKit coordinate span latitude delta to an equivalent clamped radar scale in meters.
            public static func radarScaleMeters(forMapSpanDelta mapSpanDelta: Double) -> Double {
                let visibleMetersLat = (mapSpanDelta * AppConstants.Location.metersPerDegreeLatitude) / referenceScreenAspectRatio
                let calculatedMeters = visibleMetersLat * radarRadiusRatio
                #if os(watchOS)
                let maxScale = maxWatchScaleMeters
                #else
                let maxScale = maxiOSScaleMeters
                #endif
                return min(max(calculatedMeters, minScaleMeters), maxScale)
            }
        }
        
        /// Tactical scale ruler display thresholds
        public enum ScaleRuler {
            public static let rulerWidthPoints: Double = 40.0
            #if os(watchOS)
            public static let referenceScreenHeight: Double = 200.0
            #else
            public static let referenceScreenHeight: Double = 800.0
            #endif
            
            /// Meter thresholds for discrete scale labels
            public static let thresholds: [(maxMeters: Double, label: String)] = [
                (18.0, "10m"),
                (38.0, "25m"),
                (75.0, "50m"),
                (150.0, "100m"),
                (350.0, "250m"),
                (750.0, "500m"),
                (1500.0, "1km"),
                (3500.0, "2.5km"),
                (7500.0, "5km"),
                (15000.0, "10km")
            ]
            
            /// Formats a distance in meters to a discrete ruler label based on defined thresholds.
            public static func formatRulerDistance(meters: Double) -> String {
                for threshold in thresholds {
                    if meters < threshold.maxMeters {
                        return threshold.label
                    }
                }
                return "\(max(1, Int(round(meters / AppConstants.Location.metersPerKilometer))))km"
            }
            
            /// Formats a distance in meters for display (e.g. range ring distance label).
            public static func formatDistance(meters: Double) -> String {
                if meters < AppConstants.Location.metersPerKilometer {
                    return "\(Int(round(meters)))m"
                } else {
                    let km = meters / AppConstants.Location.metersPerKilometer
                    return String(format: "%.1fkm", km)
                }
            }
        }
        
        /// Tactical HUD overlay corner padding constants to place controls just outside radar rings
        public enum HUD {
            public static let horizontalPadding: CGFloat = 12.0
            public static let topPadding: CGFloat = 14.0
            public static let bottomPadding: CGFloat = 12.0
        }
        
        /// Tactical Vector Shapes Geometry Calculation Constants
        public enum TacticalShapes {
            // Player Shape
            public static let playerRadiusFactor: Double = 0.38
            public static let playerLeftShoulderAngleDegrees: Double = 220.0
            public static let playerRightShoulderAngleDegrees: Double = 320.0
            
            // Squad Leader Shape
            public static let leaderRadiusFactor: Double = 0.36
            public static let leaderShoulderOffsetRatio: Double = 0.85
            public static let leaderShoulderHeightRatio: Double = 0.35
            public static let leaderWingOuterRatio: Double = 0.98
            public static let leaderWingHeightRatio: Double = 0.2
            public static let leaderInnerNotchAngle1Degrees: Double = 35.0
            public static let leaderInnerNotchAngle2Degrees: Double = 145.0
            
            // KIA Dead X Shape
            public static let deadXArmLengthRatio: Double = 0.46
            public static let deadXHalfThicknessRatio: Double = 0.13
            public static let sqrtTwo: CGFloat = 1.4142135623730951
            
            // ECG Waveform Progress Keyframes & Amplitude Ratios
            public enum ECG {
                public static let pWaveStart: CGFloat = 0.20
                public static let pWavePeak: CGFloat = 0.28
                public static let pWaveEnd: CGFloat = 0.35
                public static let qDip: CGFloat = 0.42
                public static let rPeak: CGFloat = 0.50
                public static let sDip: CGFloat = 0.58
                public static let tWaveStart: CGFloat = 0.65
                public static let tWavePeak: CGFloat = 0.73
                public static let tWaveEnd: CGFloat = 0.81
                
                public static let pWaveHeightRatio: CGFloat = 0.16
                public static let qDipDepthRatio: CGFloat = 0.15
                public static let rPeakHeightRatio: CGFloat = 0.44
                public static let sDipDepthRatio: CGFloat = 0.38
                public static let tWaveHeightRatio: CGFloat = 0.20
            }
        }
    }
}

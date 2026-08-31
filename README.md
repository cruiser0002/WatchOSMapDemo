# Radar Map: Your Milsim Companion (watchOS & iOS)

**Radar Map** is a tactical companion application built with SwiftUI for watchOS and iOS, engineered for milsim (military simulation), airsoft, paintball, and outdoor tactical squad coordination.

---

## 🎯 Core Features

- 🛰️ **Dual-Mode Tactical Maps**:
  - **Standard MapKit Mode**: Native MapKit integration supporting **Standard (Flat)**, **Topography**, and **Satellite / Hybrid** imagery.
  - **Tactical OLED Radar Mode**: High-contrast, battery-optimized vector CRT radar display with animated range rings, cardinal markings, and radar sweep.
- 🧭 **Live Telemetry & Biometrics**:
  - Continuous GPS coordinates with true/magnetic heading cone ($0-360^\circ$).
  - Real-time HealthKit (`HKWorkoutSession`) heart rate ($BPM$) badge with color-coded biometric stress zones and pulsating indicator core.
  - One-touch KIA / Downed status reporting with visual cross-out icons across the squad map.
- ⚡ **Local Companion Sync (`WatchConnectivity`)**:
  - **Immediate Local Rendering**: Zero-latency local UI updates with persistent context staging in `WCSession`.
  - **Dual-Stream Pipeline**: High-speed unidirectional stream for live sensor data (Phone GPS priority & Watch biometrics) and low-speed bidirectional stream for tactical markers, room lifecycle, and configuration.
  - **Network Handover**: Phone is designated as primary gateway with automatic Watch standalone fallback when disconnected.
- 📍 **Tactical Markers & Orders**:
  - Squad Leaders can drop field markers including **Enemy Spotted**, **Rally Point**, **Objective**, **Danger Zone**, **Supply Drop**, and **Extraction**.
  - Enemy markers feature automated **5-minute linear decay** to grayscale.
- 🔍 **Digital Crown Decade Zoom**:
  - Seamless altitude control stepping through discrete $1 \to 2.5 \to 5$ decade scales ($1\text{m} \to 2500\text{m}$).
  - Non-destructive centering preserving active zoom distance.
- 🔄 **Cloud Telemetry & Late-Packet Rejection**:
  - Client-driven adaptive REST polling engine powered by Firebase Real-Time Database with zero stale socket overhead during suspension.
  - Monotonic sequence numbers and timestamp watermarks eliminate out-of-order jitter and rubberbanding.
  - **Dead Reckoning & Delta Gating** ($< 3.5\text{m}$, $\Delta\text{HR} < 12\text{ BPM}$) and wrist-down throttling minimize cellular bandwidth and battery drain.
- 🎨 **Tactical HUD Themes**:
  - **Night Vision Green (NVG)**, **Amber CRT**, **Tactical Cyan**, and **Monochromatic Stealth**.
- 💳 **RevenueCat Squad Leader Paywall**:
  - Free tier supports squads of up to 4 operators.
  - $29.99 lifetime unlock enables unlimited squad sizes and custom tactical marker placement. Joining rooms of any size is free for all operators.
- 📖 **Interactive HUD Field Manual**:
  - Integrated onboarding guide with interactive diagrams for hardware controls, tactical glyphs, and compass telemetry.

---

## ⚠️ Core Engineering Rule: No Fallback Datasources or Placeholder Masking

- **Datasource Resilience Over Fallbacks**: NEVER introduce fallback data sources, secondary compensatory lookup pipelines, or synthetic placeholder stitching unless explicitly specified.
- **Direct Authoritative Consumption**: Consume data directly from authoritative sources as-is. If a field or property (e.g., player callsign) is not yet available, it remains empty or unrendered until delivered by the authoritative stream.
- **No ID / Mock Leakage**: NEVER fall back to internal identifiers (such as UUIDs, member IDs, or synthetic keys) as user-facing values. Doing so masks data gaps, causes unpredictable race conditions, and produces UI flickering.

---

## 🏗️ Project Architecture

```
RadarMap/
├── RadarMapApp.swift                       # Multiplatform app entry point (watchOS & iOS)
├── AppConstants.swift                      # Global constants, decade scales & API keys
├── Models/
│   ├── AppBuildVersion.swift               # Version tracking & schema migration
│   ├── MapCenterLockState.swift            # Map locking modes (Free Roam, Self, Squad Centroid)
│   ├── MapStateMachine.swift               # MapKit camera altitude & tracking state coordinator
│   ├── PlayerVitalStateMachine.swift       # Biometric stress zones & KIA/Downed state machine
│   ├── RadarColorTheme.swift               # Tactical CRT & NVG color palettes
│   ├── SessionStateMachine.swift           # Squad session lifecycle (Discovery, Lobby, Active Combat)
│   ├── SquadMember.swift                   # Member profile, coordinates, heading, vitals, role & stale status
│   ├── SquadRoom.swift                     # Squad room configuration, PIN, capacity & expiry
│   ├── TacticalHUDCallout.swift            # Off-screen teammate indicators, bearing & distance callouts
│   ├── TacticalIndicator.swift             # Field markers (Enemy, Rally, Objective, Danger, Supply, Extraction)
│   ├── TacticalMapStyle.swift              # Map style definitions (Standard, Topography, Satellite, Radar)
│   └── TelemetryPacket.swift               # Wire format with sequence numbers, timestamps & delta gating
├── Managers/
│   ├── FirebaseSyncManager.swift           # Firebase RTDB client-driven REST engine with late-packet rejection
│   ├── GameStateManager.swift              # Central environment coordinator binding sensors, room & UI
│   ├── HealthKitManager.swift              # HKWorkoutSession for live watchOS heart rate collection
│   ├── LocationHeadingManager.swift        # CoreLocation GPS & compass heading stream
│   ├── NetworkQualityMonitor.swift         # NWPathMonitor network reachability & offline tracking
│   ├── SubscriptionManager.swift           # RevenueCat $29.99 lifetime squad unlock & StoreKit logic
│   └── WatchConnectivityManager.swift      # WCSession companion data bridge & network handover
├── Views/
│   ├── ContentView.swift                   # Dynamic root navigation based on SessionStateMachine
│   ├── ModelPresentationExtensions.swift   # Presentation helpers and UI formatters
│   ├── Map/
│   │   ├── TacticalRadarMapView.swift      # Primary tactical interface with Crown zoom & HUD overlays
│   │   ├── StandardMapView.swift           # Native MapKit map with custom vector annotations
│   │   ├── RadarMapView.swift              # High-contrast OLED CRT radar sweep view
│   │   ├── MemberAnnotationView.swift      # Teammate directional blip, heading cone & BPM pulse badge
│   │   ├── TacticalIndicatorMenuView.swift # Quick action menu for dropping tactical markers
│   │   ├── TacticalIndicatorOverlayView.swift # Tactical marker layer with 5-minute decay & GPU caching
│   │   └── SquadTacticalIcons.swift        # Custom vector shapes for leaders, players, and markers
│   ├── Guide/
│   │   └── HUDGuideView.swift              # Interactive HUD field manual & visual onboarding guide
│   ├── Room/
│   │   ├── RoomDiscoveryView.swift         # Squad creation & direct PIN join interface
│   │   ├── CreateRoomView.swift            # Room creator with capacity selector & paywall trigger
│   │   └── SquadLobbyView.swift            # Squad roster, member ready states & mission countdown
│   ├── Paywall/
│   │   └── PaywallView.swift               # RevenueCat $29.99 lifetime unlock paywall
│   └── Settings/
│       ├── SettingsView.swift              # Callsign config, theme selector, dead reckoning & stats
│       └── PolicyView.swift                # Privacy policy & terms of service modal
├── Resources/
│   ├── Assets.xcassets                     # App icons, colors, and HUD diagram assets
│   ├── GoogleService-Info.plist            # Firebase configuration
│   ├── Info.plist                          # CoreLocation & HealthKit permissions
│   └── RadarMap.storekit                   # Local StoreKit testing configuration
└── Tests/
    └── RadarMapTests/
        └── RadarMapTests.swift             # Unit & integration test suite (187+ tests)
```

---

## 📚 Technical Architecture Documents

For detailed technical specifications, refer to the companion documentation:
- [**Cloud Data Management Architecture**](CLOUD_DATA_MANAGEMENT.md): Cloud Data Matrix, delta gating, dead reckoning, late packet rejection, and scheduled Cloud Functions garbage collection.
- [**Local Companion Data Sync Architecture**](COMPANION_DATA_SYNC_MODEL.md): `WatchConnectivity` (`WCSession`) dual-stream sync protocol, immediate local rendering, and phone preference network handover.
- [**MapKit Equivalents & Native Behavioral Standards**](MAPKIT_EQUIVALENTS.md): MapKit native behaviors, camera altitude trigonometry, `UserAnnotation` standards, and discrete decade zoom scales.

---

## 💳 In-App Purchase & RevenueCat Configuration

### 1. App Store Connect Setup
1. Log into [App Store Connect](https://appstoreconnect.apple.com/) and navigate to **In-App Purchases**.
2. Click **Create In-App Purchase (+)** and select **Non-Consumable**.
3. Configure the product:
   - **Reference Name**: `Squad Leader Lifetime Unlock`
   - **Product ID**: `com.radarmap.watch.unlimited_squad`
   - **Price**: Tier ($29.99 USD) or desired price
   - **Family Sharing**: Enable
   - **Localization**: Add English (U.S.) displayName `"Squad Leader Lifetime"` and description `"Create squads of >4 operators and place tactical map indicators."`

### 2. RevenueCat Dashboard Setup
1. In the [RevenueCat Dashboard](https://app.revenuecat.com/), select the **RadarMap** project.
2. **Entitlement**:
   - Identifier: `unlimited_squad_size`
   - Description: `Squad Leader Unlimited Capacity & Tactical Markers`
3. **Product**:
   - Add App Store product identifier: `com.radarmap.watch.unlimited_squad`
   - Attach to Entitlement `unlimited_squad_size`
4. **Offering**:
   - Identifier: `default`
   - Package: `$rc_lifetime` (Lifetime) pointing to `com.radarmap.watch.unlimited_squad`
5. **API Key**:
   - Copy your Public Apple API Key (`appl_...`) and update `revenueCatApiKey` in `RadarMap/AppConstants.swift`.

### 3. Local Xcode Testing with StoreKit Configuration
1. Open the project in Xcode (`xed .`).
2. Edit Scheme (**Product > Scheme > Edit Scheme...**).
3. Select **Run** on the left, navigate to the **Options** tab.
4. Under **StoreKit Configuration**, select `RadarMap.storekit` (located in `RadarMap/Resources/`).
5. Run on watchOS or iOS Simulator — all purchase and restore flows execute locally with StoreKit test dialogs.

---

## 🚀 Running & Testing

### Prerequisites
- Xcode 15.0+
- Swift 5.9+
- Target Platforms: **watchOS 10.0+**, **iOS 17.0+**, **macOS 14.0+**

### Run Unit Tests
```bash
swift test
```

### Opening in Xcode
Open the directory in Xcode or run:
```bash
xed .
```
Select an Apple Watch target (e.g. Apple Watch Series 9 or Ultra 2, watchOS 10+) or iPhone target (iOS 17+) to build and run.


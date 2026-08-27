# Radar Map: Your Milsim Companion (Apple Watch)

**Radar Map** is a tactical companion application built with SwiftUI for watchOS, designed for milsim (military simulation), airsoft, paintball, and outdoor tactical squad coordination.

---

## Features

- 🛰️ **Tactical Map View**: Real-time squad positioning with support for **Standard**, **Topography**, and **Satellite / Imagery** map layers.
- 🧭 **Live Telemetry & Heading**: Renders each teammate's location, heading directional pointer ($0-360^\circ$), and HealthKit live Heart Rate ($BPM$) badge with color-coded biometric stress zones.
- 📶 **Bluetooth Low Energy Discovery**: Scan and broadcast rooms over CoreBluetooth for 1-tap local squad joining without typing codes.
- 🔄 **Firebase Real-Time Sync & Late Packet Rejection**: Telemetry pipeline with automatic rejection of out-of-order, stale, and transit-lagged packets to eliminate map jitter and rubberbanding.
- 💳 **RevenueCat Squad Leader Paywall**: Free tier supports creating squads of up to 4 operators. Creating squads of unlimited operators requires the $9.99 lifetime unlock. Joining rooms of any size is free for all operators.

---

## Project Architecture

```
RadarMap/
├── RadarMapApp.swift                   # App entrypoint
├── Models/
│   ├── SquadMember.swift               # Callsign, coordinates, heading, heart rate, stress color
│   ├── SquadRoom.swift                 # Room configuration, capacity, active squad roster
│   ├── TacticalMapStyle.swift          # Map layer styles (Standard, Topography, Satellite)
│   └── TelemetryPacket.swift           # Wire format packet with sequence numbers & timestamps
├── Managers/
│   ├── LocationHeadingManager.swift    # CoreLocation GPS & compass heading stream
│   ├── HealthKitManager.swift          # HKWorkoutSession for live watchOS heart rate collection
│   ├── BluetoothDiscoveryManager.swift # CoreBluetooth peripheral advertising & central scanner
│   ├── FirebaseSyncManager.swift       # Firebase engine with late-packet rejection filter
│   ├── SubscriptionManager.swift       # RevenueCat $9.99 lifetime squad unlock & paywall logic
│   └── GameStateManager.swift          # Environment coordinator binding sensors and state
├── Views/
│   ├── ContentView.swift               # Command center / root navigation
│   ├── Map/
│   │   ├── TacticalRadarMapView.swift  # Interactive tactical MapKit view & HUD overlays
│   │   └── MemberAnnotationView.swift  # Directional blip, heading cone & live BPM badge
│   ├── Room/
│   │   ├── RoomDiscoveryView.swift     # BLE radar scanner & direct room code join
│   │   ├── CreateRoomView.swift        # Room creator with capacity limiter & paywall trigger
│   │   └── SquadLobbyView.swift        # Squad roster, member status, and launch button
│   ├── Paywall/
│   │   └── PaywallView.swift           # RevenueCat $9.99 lifetime unlock paywall
│   └── Settings/
│       └── SettingsView.swift          # Callsign config, layer selector, telemetry stats
└── Resources/
    └── Info.plist                      # HealthKit, CoreLocation, and Bluetooth permissions
```

---

## In-App Purchase & RevenueCat Configuration

### 1. App Store Connect Setup
1. Log into [App Store Connect](https://appstoreconnect.apple.com/) and navigate to your app's **In-App Purchases** page.
2. Click **Create In-App Purchase (+)** and select **Non-Consumable**.
3. Configure the product:
   - **Reference Name**: `Squad Leader Lifetime Unlock`
   - **Product ID**: `com.radarmap.watch.unlimited_squad`
   - **Price**: Tier 10 ($9.99 USD) or desired price
   - **Family Sharing**: Enable (Checked)
   - **Localization**: Add English (U.S.) displayName `"Squad Leader Lifetime"` and description `"Create squads of >4 operators and place tactical map indicators."`

### 2. RevenueCat Dashboard Setup
1. In the [RevenueCat Dashboard](https://app.revenuecat.com/), create a project or select **RadarMap**.
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
2. Edit your Scheme (**Product > Scheme > Edit Scheme...**).
3. Select the **Run** action on the left, navigate to the **Options** tab.
4. Under **StoreKit Configuration**, select `RadarMap.storekit` (located in `RadarMap/Resources/`).
5. Run on watchOS Simulator — all purchase and restore flows will execute locally with StoreKit test dialogs without hitting live servers or requiring test accounts.

---

## Running & Testing

### Run Unit Tests
```bash
swift test
```

### Opening in Xcode
Open the directory in Xcode or use `xed .`. Select an Apple Watch Simulator (e.g. Apple Watch Series 9 or Ultra 2, watchOS 10+) to build and run.


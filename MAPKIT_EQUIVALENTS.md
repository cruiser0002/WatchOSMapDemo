# MapKit Equivalents & Native Behavioral Standards

This document serves as the architectural reference for MapKit integration, visual equivalences, and UX behaviors in RadarMap.

> **CRITICAL ARCHITECTURAL RULE**  
> **NEVER deviate from MapKit native behavior.**

---

## 1. Feature Equivalence Mapping

| Feature | MapKit Native Component | RadarMap Implementation | Code Reference | Key Behavior & Rules |
| :--- | :--- | :--- | :--- | :--- |
| **Me** | Local user dot | Custom local user dot with heading and breathing; can be player icon, commander icon, or X | [`StandardMapView.swift`](file:///Users/cruiser/Documents/antigravity/jolly-hypatia/RadarMap/Views/Map/StandardMapView.swift)<br>[`MemberAnnotationView.swift`](file:///Users/cruiser/Documents/antigravity/jolly-hypatia/RadarMap/Views/Map/MemberAnnotationView.swift)<br>[`SquadTacticalIcons.swift`](file:///Users/cruiser/Documents/antigravity/jolly-hypatia/RadarMap/Views/Map/SquadTacticalIcons.swift) | • Uses SwiftUI `UserAnnotation` to suppress MapKit's default blue dot and replace it with custom tactical vector shapes.<br>• Icon dynamically switches based on role (`SquadLeaderShape` vs `SquadPlayerShape`) or status (`SquadDeadXShape`).<br>• Central core dot pulses (`SquadPulseCore`) at frequency proportional to real-time BPM. |
| **Other players** | Annotations | Custom annotation with heading and breathing; can be player icon, commander icon, or X; fade to gray based on location age | [`StandardMapView.swift`](file:///Users/cruiser/Documents/antigravity/jolly-hypatia/RadarMap/Views/Map/StandardMapView.swift)<br>[`MemberAnnotationView.swift`](file:///Users/cruiser/Documents/antigravity/jolly-hypatia/RadarMap/Views/Map/MemberAnnotationView.swift) | • Rendered via `Annotation(coordinate:anchor: .center)`.<br>• When telemetry is stale (`member.isStale == true`), color turns to `.gray`.<br>• Directional rotation follows heading; center pulse follows teammate BPM. |
| **Tac** | Annotations | Custom tactical annotation (Orders & Enemy markers) | [`TacticalIndicatorOverlayView.swift`](file:///Users/cruiser/Documents/antigravity/jolly-hypatia/RadarMap/Views/Map/TacticalIndicatorOverlayView.swift) | • Rendered via `Annotation`.<br>• Hardware GPU texture cache (`TacticalSpriteCache`).<br>• 5-minute linear fade to grayscale for enemy markers.<br>• Hold-to-delete interaction. |
| **Center map** | Center map | Center map without changing zoom level | [`MapStateMachine.swift`](file:///Users/cruiser/Documents/antigravity/jolly-hypatia/RadarMap/Models/MapStateMachine.swift)<br>[`GameStateManager.swift`](file:///Users/cruiser/Documents/antigravity/jolly-hypatia/RadarMap/Managers/GameStateManager.swift) | • Bottom-left HUD button triggers `gameState.centerMapOnLocalUser()`.<br>• Re-locks `MapTrackingState` to `.locked` at the **current zoom scale** (`scaleMeters` is preserved, never reset). |
| **Gestures** | Gesture | Standard pan/drag, tap, and native pinch-to-zoom gestures | [`StandardMapView.swift`](file:///Users/cruiser/Documents/antigravity/jolly-hypatia/RadarMap/Views/Map/StandardMapView.swift) | • Native `.interactionModes: [.pan, .zoom]` on iOS (`.pan` on watchOS).<br>• Drag gesture transitions state from `.locked` to `.unlocked` (panning).<br>• Pinch to zoom dynamically updates altitude with live Scale Ruler feedback, snapping to discrete `[1, 2.5, 5]` scales on release.<br>• Tap gesture handles indicator placement when menu is pending. |
| **Crown / Pinch Zoom** | Zoom | MapKit zoom with discrete decade levels `[1, 2.5, 5]` | [`AppConstants.swift`](file:///Users/cruiser/Documents/antigravity/jolly-hypatia/RadarMap/AppConstants.swift)<br>[`TacticalRadarMapView.swift`](file:///Users/cruiser/Documents/antigravity/jolly-hypatia/RadarMap/Views/Map/TacticalRadarMapView.swift)<br>[`StandardMapView.swift`](file:///Users/cruiser/Documents/antigravity/jolly-hypatia/RadarMap/Views/Map/StandardMapView.swift) | • Digital Crown rotation (watchOS) or MapKit pinch-to-zoom (iOS) steps through discrete minor scales `[1.0, 2.5, 5.0, 10.0, 25.0, 50.0, 100.0, 250.0, 500.0, 1000.0, 2500.0]`.<br>• Altitude is calculated using MapKit camera FOV trigonometry (`cameraDistance(forScale:)` and `scaleMeters(forCameraDistance:)`). |
| **Other buttons** | *(none)* | Custom definitions not related to MapKit | [`TacticalRadarMapView.swift`](file:///Users/cruiser/Documents/antigravity/jolly-hypatia/RadarMap/Views/Map/TacticalRadarMapView.swift) | • Top-left: Settings Gear.<br>• Top-center: Squad Leader / Commander Menu (`star.fill`).<br>• Bottom-center: Scale Ruler / Hold-to-Act KIA Button.<br>• Bottom-right: Map Style Toggle (Standard MapKit vs OLED Radar). |

---

## 2. Core MapKit Implementation Rules

1. **User Annotation Placement**: Always use `UserAnnotation` in `StandardMapView` for the local user so MapKit coordinates location tracking without double-rendering native blue dots.
2. **Camera Altitude & Aspect Ratio**: MapKit camera altitude is bound to the tactical scale via `StandardMapView.cameraDistance(forScale:)` with FOV tangent trigonometry ($V = 2 \cdot \text{altitude} \cdot \tan(15^\circ)$).
3. **Decade Zoom Progression**: Zoom levels are constrained to the $1 \to 2.5 \to 5$ decade sequence across metric ranges ($1\text{m} \to 2.5\text{km}$).
4. **Non-Destructive Centering**: Re-centering to the local user resets panning coordinates but strictly retains current camera distance / scale.

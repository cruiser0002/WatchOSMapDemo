import SwiftUI

public struct ContentView: View {
    @EnvironmentObject var gameState: GameStateManager
    @Environment(\.scenePhase) private var scenePhase
    #if os(watchOS)
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    #endif
    
    public init() {}
    
    public var body: some View {
        TacticalRadarMapView()
            .environmentObject(gameState)
            .preferredColorScheme(.dark)
            .onAppear {
                updateWristActivity(phase: scenePhase)
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    gameState.handleAppResume()
                } else if newPhase == .background {
                    gameState.handleAppSuspend()
                } else {
                    updateWristActivity(phase: newPhase)
                }
            }
            #if os(watchOS)
            .onChange(of: isLuminanceReduced) { _, reduced in
                if !reduced && scenePhase != .background {
                    gameState.handleAppResume()
                } else {
                    updateWristActivity(phase: scenePhase)
                }
            }
            #endif
    }
    
    private func updateWristActivity(phase: ScenePhase) {
        #if os(watchOS)
        let isActive = (phase != .background) && !isLuminanceReduced
        #else
        let isActive = (phase == .active)
        #endif
        gameState.setWristActive(isActive)
    }
}


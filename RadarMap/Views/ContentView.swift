import SwiftUI

public struct ContentView: View {
    @EnvironmentObject var gameState: GameStateManager
    
    public init() {}
    
    public var body: some View {
        TacticalRadarMapView()
            .environmentObject(gameState)
            .preferredColorScheme(.dark)
    }
}


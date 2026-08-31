import SwiftUI

#if os(watchOS)
@main
struct RadarMapApp: App {
    @StateObject private var gameState = GameStateManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gameState)
                .task {
                    gameState.subscriptionManager.configureRevenueCat()
                }
        }
    }
}
#endif

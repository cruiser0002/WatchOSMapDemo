import SwiftUI

#if os(iOS)
@main
struct RadarMapCompanionApp: App {
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

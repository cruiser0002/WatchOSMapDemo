import SwiftUI

#if os(watchOS) || os(iOS)
@main
struct RadarMapApp: App {
    @StateObject private var gameState = GameStateManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(gameState)
        }
    }
}
#endif

import SwiftUI

@main
struct RadarMapCompanionApp: App {
    var body: some Scene {
        WindowGroup {
            iOSCompanionContentView()
        }
    }
}

struct iOSCompanionContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(.system(size: 72))
                    .foregroundStyle(.green)

                VStack(spacing: 8) {
                    Text("Radar Map")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.primary)

                    Text("Tactical Radar for Apple Watch")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 14) {
                    Label("Standalone tactical GPS radar", systemImage: "location.fill")
                    Label("Real-time squad positioning & BLE sync", systemImage: "person.2.fill")
                    Label("Live biometric & heart rate streaming", systemImage: "heart.fill")
                    Label("Dead reckoning inertial tracking", systemImage: "figure.walk")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
                .background(Color(UIColor.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                Spacer()

                Text("Launch Radar Map directly on your Apple Watch to start or join a tactical squad session.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
            }
            .padding(.top, 20)
            .navigationTitle("Radar Map")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

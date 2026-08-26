import SwiftUI

public struct PaywallView: View {
    @EnvironmentObject var gameState: GameStateManager
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    public var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                // Header Icon & Title
                VStack(spacing: 4) {
                    Image(systemName: "person.3.sequence.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.yellow)
                    
                    Text("Squad Leader")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("Create rooms with >4 operators")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 4)
                
                Divider()
                
                // Features
                VStack(alignment: .leading, spacing: 6) {
                    FeatureRow(icon: "infinity", text: "Host unlimited players")
                    FeatureRow(icon: "antenna.radiowaves.left.and.right", text: "Broadcast BLE Radar")
                    FeatureRow(icon: "person.badge.shield.checkmark.fill", text: "Others join 100% free")
                }
                .padding(.horizontal, 4)
                
                // Pricing & Purchase Button
                VStack(spacing: 6) {
                    Button(action: {
                        Task {
                            let success = await gameState.subscriptionManager.purchaseLifetimeUnlock()
                            if success {
                                dismiss()
                            }
                        }
                    }) {
                        HStack {
                            if gameState.subscriptionManager.isPurchasing {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Text("Unlock for \(SubscriptionManager.lifetimePriceString)")
                                    .font(.system(size: 12, weight: .bold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(gameState.subscriptionManager.isPurchasing)
                    
                    // Restore Purchases
                    Button(action: {
                        Task {
                            let restored = await gameState.subscriptionManager.restorePurchases()
                            if restored {
                                dismiss()
                            }
                        }
                    }) {
                        Text("Restore Purchase")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 8)
        }
        .navigationTitle("Upgrade")
        #if os(watchOS) || os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.green)
                .frame(width: 14)
            
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white)
        }
    }
}

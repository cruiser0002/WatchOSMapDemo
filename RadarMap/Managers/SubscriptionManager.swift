import Foundation
import Combine
import StoreKit

public final class SubscriptionManager: ObservableObject {
    public static let shared = RevenueCatSharedKey()
    
    // RevenueCat Entitlement & Product IDs
    public static let entitlementID = "unlimited_squad_size"
    public static let productID = "com.radarmap.watch.unlimited_squad"
    public static let lifetimePriceString = "$9.99"
    
    public static let freeTierMaxCapacity = 4
    
    @Published public var hasUnlimitedSquadUnlock: Bool = false
    @Published public var isPurchasing: Bool = false
    @Published public var errorMessage: String?
    
    public init() {
        // Load persisted unlock status from local storage
        self.hasUnlimitedSquadUnlock = UserDefaults.standard.bool(forKey: "hasUnlimitedSquadUnlock")
    }
    
    // MARK: - Paywall Check
    
    /// Free users can create a room of <= 4 people.
    /// Creating a room with > 4 people requires the $9.99 lifetime unlock.
    /// Joining a room of any size is always free.
    public func canCreateRoom(withCapacity capacity: Int) -> Bool {
        if capacity <= SubscriptionManager.freeTierMaxCapacity {
            return true
        }
        return hasUnlimitedSquadUnlock
    }
    
    // MARK: - Purchase Flow (RevenueCat / StoreKit wrapper)
    
    @MainActor
    public func purchaseLifetimeUnlock() async -> Bool {
        self.isPurchasing = true
        self.errorMessage = nil
        
        // Simulating RevenueCat purchase call: Purchases.shared.purchase(package:)
        do {
            // Simulated network delay for in-app purchase
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            self.hasUnlimitedSquadUnlock = true
            UserDefaults.standard.set(true, forKey: "hasUnlimitedSquadUnlock")
            self.isPurchasing = false
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            self.isPurchasing = false
            return false
        }
    }
    
    @MainActor
    public func restorePurchases() async -> Bool {
        self.isPurchasing = true
        self.errorMessage = nil
        
        do {
            try await Task.sleep(nanoseconds: 800_000_000)
            let unlocked = UserDefaults.standard.bool(forKey: "hasUnlimitedSquadUnlock")
            self.hasUnlimitedSquadUnlock = unlocked
            self.isPurchasing = false
            return unlocked
        } catch {
            self.errorMessage = error.localizedDescription
            self.isPurchasing = false
            return false
        }
    }
}

public struct RevenueCatSharedKey {
    public let apiKey = "appl_mock_revenuecat_key_milsim"
}

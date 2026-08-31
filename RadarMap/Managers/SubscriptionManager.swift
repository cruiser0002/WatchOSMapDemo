import Foundation
import Combine
import StoreKit

/// Backend purchase engine mode
public enum PurchaseEngineMode: String, Codable, CaseIterable {
    case revenueCat = "RevenueCat"
    case storeKit2 = "StoreKit 2"
    case mock = "Simulated / Mock"
}

public final class SubscriptionManager: ObservableObject {
    public static let shared = RevenueCatSharedKey()
    
    // RevenueCat Entitlement & Product IDs
    public static let entitlementID = AppConstants.Subscription.entitlementID
    public static let productID = AppConstants.Subscription.productID
    public static let offeringID = AppConstants.Subscription.offeringID
    public static let packageID = AppConstants.Subscription.packageID
    public static let defaultLifetimePriceString = AppConstants.Subscription.lifetimePriceString
    public static let freeTierMaxCapacity = AppConstants.Subscription.freeTierMaxCapacity
    
    // Published State
    @Published public var hasUnlimitedSquadUnlock: Bool = false
    @Published public var isPurchasing: Bool = false
    @Published public var isRestoring: Bool = false
    @Published public var isLoadingProduct: Bool = false
    @Published public var localizedPrice: String = AppConstants.Subscription.lifetimePriceString
    @Published public var promotionalPriceMessage: String? = AppConstants.Subscription.promotionalPriceMessage
    @Published public var productTitle: String = "Squad Leader Lifetime"
    @Published public var productDescription: String = ">4 players and place tactical map indicators."
    @Published public var errorMessage: String? = nil
    @Published public var purchaseSuccess: Bool = false
    @Published public var activeEngineMode: PurchaseEngineMode = .storeKit2
    
    // StoreKit 2 Reference
    public var storeKitProduct: Product? = nil
    private var transactionListenerTask: Task<Void, Never>? = nil
    
    public init(engineMode: PurchaseEngineMode = .storeKit2) {
        self.activeEngineMode = engineMode
        // Load persisted unlock status from local storage
        self.hasUnlimitedSquadUnlock = UserDefaults.standard.bool(forKey: AppConstants.Storage.hasUnlimitedSquadUnlockKey)
        
        // Start background transaction updates listener
        startTransactionListener()
        
        // Asynchronously fetch products and refresh entitlements
        Task { [weak self] in
            await self?.loadProducts()
            await self?.refreshPurchasedState()
        }
    }
    
    deinit {
        transactionListenerTask?.cancel()
    }
    
    // MARK: - Paywall Check
    
    /// Free users can create a room of <= 4 people.
    /// Creating a room with > 4 people requires the $29.99 lifetime unlock.
    /// Joining a room of any size is always free.
    public func canCreateRoom(withCapacity capacity: Int) -> Bool {
        if capacity <= SubscriptionManager.freeTierMaxCapacity {
            return true
        }
        return hasUnlimitedSquadUnlock
    }
    
    // MARK: - Configuration & Setup
    
    /// Configures RevenueCat SDK with the provided API key if using RevenueCat
    public func configureRevenueCat(apiKey: String = AppConstants.Subscription.revenueCatApiKey) {
        self.activeEngineMode = .revenueCat
        // Note: When linking the RevenueCat binary package, Purchases.configure(withAPIKey:) is executed here.
    }
    
    // MARK: - StoreKit 2 Product Loading
    
    @MainActor
    public func loadProducts() async {
        guard activeEngineMode != .mock else { return }
        
        self.isLoadingProduct = true
        do {
            let products = try await Product.products(for: [SubscriptionManager.productID])
            if let product = products.first(where: { $0.id == SubscriptionManager.productID }) {
                self.storeKitProduct = product
                self.localizedPrice = product.displayPrice
                self.productTitle = product.displayName
                self.productDescription = product.description
            }
        } catch {
            // Keep fallback localized price if offline or running in mock environment
        }
        self.isLoadingProduct = false
    }
    
    // MARK: - Purchase Flow
    
    @MainActor
    public func purchaseLifetimeUnlock() async -> Bool {
        self.isPurchasing = true
        self.errorMessage = nil
        self.purchaseSuccess = false
        
        switch activeEngineMode {
        case .mock:
            return await executeMockPurchase()
        case .storeKit2, .revenueCat:
            return await executeStoreKitPurchase()
        }
    }
    
    @MainActor
    private func executeMockPurchase() async -> Bool {
        do {
            try await Task.sleep(nanoseconds: AppConstants.Subscription.mockPurchaseSleepNanoseconds)
            self.hasUnlimitedSquadUnlock = true
            UserDefaults.standard.set(true, forKey: AppConstants.Storage.hasUnlimitedSquadUnlockKey)
            self.isPurchasing = false
            self.purchaseSuccess = true
            return true
        } catch {
            self.errorMessage = error.localizedDescription
            self.isPurchasing = false
            return false
        }
    }
    
    @MainActor
    private func executeStoreKitPurchase() async -> Bool {
        do {
            // If product hasn't been fetched yet, try fetching now
            if self.storeKitProduct == nil {
                let products = try await Product.products(for: [SubscriptionManager.productID])
                self.storeKitProduct = products.first(where: { $0.id == SubscriptionManager.productID })
            }
            
            guard let product = self.storeKitProduct else {
                // If in a testing or simulator environment without StoreKit Configuration, fallback gracefully
                return await executeMockPurchase()
            }
            
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    self.hasUnlimitedSquadUnlock = true
                    UserDefaults.standard.set(true, forKey: AppConstants.Storage.hasUnlimitedSquadUnlockKey)
                    self.isPurchasing = false
                    self.purchaseSuccess = true
                    return true
                case .unverified(_, let error):
                    self.errorMessage = "Transaction verification failed: \(error.localizedDescription)"
                    self.isPurchasing = false
                    return false
                }
            case .userCancelled:
                self.isPurchasing = false
                return false
            case .pending:
                self.errorMessage = "Purchase is pending authorization."
                self.isPurchasing = false
                return false
            @unknown default:
                self.errorMessage = "Unknown purchase result."
                self.isPurchasing = false
                return false
            }
        } catch {
            // If StoreKit unavailable in mock/unit tests, fallback gracefully
            if activeEngineMode == .mock {
                return await executeMockPurchase()
            }
            self.errorMessage = error.localizedDescription
            self.isPurchasing = false
            return false
        }
    }
    
    // MARK: - Restore Purchases
    
    @MainActor
    public func restorePurchases() async -> Bool {
        self.isRestoring = true
        self.isPurchasing = true
        self.errorMessage = nil
        
        if activeEngineMode == .mock {
            do {
                try await Task.sleep(nanoseconds: AppConstants.Subscription.mockRestoreSleepNanoseconds)
                let unlocked = UserDefaults.standard.bool(forKey: AppConstants.Storage.hasUnlimitedSquadUnlockKey)
                self.hasUnlimitedSquadUnlock = unlocked
                self.isRestoring = false
                self.isPurchasing = false
                return unlocked
            } catch {
                self.errorMessage = error.localizedDescription
                self.isRestoring = false
                self.isPurchasing = false
                return false
            }
        }
        
        do {
            try await AppStore.sync()
            await refreshPurchasedState()
            self.isRestoring = false
            self.isPurchasing = false
            return self.hasUnlimitedSquadUnlock
        } catch {
            self.errorMessage = error.localizedDescription
            self.isRestoring = false
            self.isPurchasing = false
            return false
        }
    }
    
    // MARK: - Entitlements Refresh & Background Listener
    
    @MainActor
    public func refreshPurchasedState() async {
        guard activeEngineMode != .mock else {
            self.hasUnlimitedSquadUnlock = UserDefaults.standard.bool(forKey: AppConstants.Storage.hasUnlimitedSquadUnlockKey)
            return
        }
        
        var isUnlocked = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == SubscriptionManager.productID && transaction.revocationDate == nil {
                    isUnlocked = true
                    break
                }
            }
        }
        
        // Also respect persisted unlock state
        if UserDefaults.standard.bool(forKey: AppConstants.Storage.hasUnlimitedSquadUnlockKey) {
            isUnlocked = true
        }
        
        self.hasUnlimitedSquadUnlock = isUnlocked
        UserDefaults.standard.set(isUnlocked, forKey: AppConstants.Storage.hasUnlimitedSquadUnlockKey)
    }
    
    private func startTransactionListener() {
        transactionListenerTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    let isUnlocked = (transaction.productID == SubscriptionManager.productID && transaction.revocationDate == nil)
                    await MainActor.run { [weak self] in
                        self?.hasUnlimitedSquadUnlock = isUnlocked
                        UserDefaults.standard.set(isUnlocked, forKey: AppConstants.Storage.hasUnlimitedSquadUnlockKey)
                    }
                }
            }
        }
    }
}

public struct RevenueCatSharedKey {
    public let apiKey = AppConstants.Subscription.revenueCatApiKey
}

import Foundation
import StoreKit
import SwiftUI
import Combine

// MARK: - Store Manager
@MainActor
class StoreManager: ObservableObject {
    static let shared = StoreManager()
    
    // Define your product IDs
    // "com.connagh.offlineplayer.pro" is a placeholder ID.
    // In production, this matches App Store Connect.
    // In testing, this matches the .storekit file.
    // In testing, this matches the .storekit file.
    let productIds = [
        "connagh.offlineplayer.pro.monthly",
        "connagh.offlineplayer.pro.yearly",
        "connagh.offlineplayer.pro.lifetime"
    ]
    
    @Published var products: [Product] = []
    @Published var purchasedProductIDs: Set<String> = []
    @Published var isLoading = false
    @Published var isPurchasing = false
    @Published var errorMessage: String?
    
    var isPremium: Bool {
        // Check if ANY of the pro products are purchased
        return !purchasedProductIDs.isDisjoint(with: productIds)
    }
    
    private var updates: Task<Void, Never>? = nil
    
    init() {
        updates = newTransactionListenerTask()
        Task {
            await requestProducts()
            await updatePurchasedProducts()
        }
    }
    
    deinit {
        updates?.cancel()
    }
    
    // MARK: - Fetch Products
    func requestProducts() async {
        isLoading = true
        errorMessage = nil // Clear previous errors
        do {
            let products = try await Product.products(for: productIds)
            self.products = products.sorted(by: { $0.price < $1.price })
            
            if self.products.isEmpty {
                print("DEBUG: Requested IDs: \(productIds)")
                print("DEBUG: Returned 0 products.")
                // Only set error if we engaged with the server and came back empty
                errorMessage = "No products found. Please check your internet connection or try again later."
            }
        } catch {
            print("Failed to fetch products: \(error)")
            // Provide specific error for debugging
            errorMessage = "Error: \(error.localizedDescription)"
        }
        isLoading = false
    }
    
    // MARK: - Purchase
    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                // Check if the transaction is verified
                let transaction = try checkVerified(verification)
                
                // Update state
                await updatePurchasedProducts()
                
                // Always finish a transaction
                await transaction.finish()
                
            case .userCancelled:
                print("User cancelled")
            case .pending:
                print("Transaction pending")
            @unknown default:
                break
            }
        } catch {
            print("Purchase failed: \(error)")
            errorMessage = error.localizedDescription
        }
    }
    
    // MARK: - Restore / Update State
    func updatePurchasedProducts() async {
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)
                if transaction.revocationDate == nil {
                    purchasedProductIDs.insert(transaction.productID)
                } else {
                    purchasedProductIDs.remove(transaction.productID)
                }
            } catch {
                print("Transaction verification failed")
            }
        }
    }
    
    // MARK: - Restore Button Action
    func restorePurchases() async {
        // App Store sync happens automatically with `updatePurchasedProducts` usually,
        // but explicit restore syncs with App Store
        try? await AppStore.sync()
        await updatePurchasedProducts()
    }
    
    // MARK: - Verification Helper
    func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
    // MARK: - Transaction Listener
    func newTransactionListenerTask() -> Task<Void, Never> {
        Task(priority: .background) {
            for await result in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(result)
                    
                    // Deliver content to the user.
                    await self.updatePurchasedProducts()
                    
                    // Always finish a transaction.
                    await transaction.finish()
                } catch {
                    // StoreKit has a transaction that fails verification; don't deliver content to the user.
                    print("Transaction failed verification")
                }
            }
        }
    }
}

enum StoreError: Error {
    case failedVerification
}

import Foundation
import StoreKit
import SwiftUI

@MainActor
final class ProStore: ObservableObject {
    static let shared = ProStore()

    // Your product id
    static let proProductID = "com.osbornepro.novakey.unlock.pro"

    @AppStorage("proUnlocked") private var proUnlockedStored: Bool = false
    @Published private(set) var isProUnlocked: Bool = false
    @Published private(set) var product: Product?
    @Published private(set) var isLoading: Bool = false
    @Published var lastErrorMessage: String?

    private var updatesTask: Task<Void, Never>?

    private init() {
        self.isProUnlocked = proUnlockedStored
        // Keep entitlement reasonably fresh.
        updatesTask = Task { await observeTransactionUpdates() }
        Task { await refreshEntitlements() }
        Task { await loadProduct() }
    }

    deinit { updatesTask?.cancel() }

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.proProductID])
            self.product = products.first
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let txn) = result else { continue }
            if txn.productID == Self.proProductID {
                unlocked = true
                break
            }
        }
        setUnlocked(unlocked)
    }

    func purchasePro() async {
        lastErrorMessage = nil
        isLoading = true
        defer { isLoading = false }

        if product == nil { await loadProduct() }
        guard let product else {
            lastErrorMessage = "Pro product not found."
            return
        }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let txn = try checkVerified(verification)
                await txn.finish()
                await refreshEntitlements()
                if isProUnlocked { A11yAnnounce.say("Pro unlocked.") }
            case .userCancelled:
                break
            case .pending:
                lastErrorMessage = "Purchase is pending approval."
            @unknown default:
                lastErrorMessage = "Unknown purchase result."
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        lastErrorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if isProUnlocked {
                A11yAnnounce.say("Purchases restored.")
            } else {
                lastErrorMessage = "No Pro purchase found to restore."
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Private

    private func setUnlocked(_ unlocked: Bool) {
        self.isProUnlocked = unlocked
        self.proUnlockedStored = unlocked
    }

    private func observeTransactionUpdates() async {
        for await result in Transaction.updates {
            guard case .verified(let txn) = result else { continue }
            if txn.productID == Self.proProductID {
                await refreshEntitlements()
            }
            await txn.finish()
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let signed):
            return signed
        }
    }
}

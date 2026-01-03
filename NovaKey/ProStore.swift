import Foundation
import StoreKit
#if canImport(UIKit)
import UIKit
#endif
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

    /// Presents Apple's built-in offer code redemption sheet (IAP offer codes).
    /// - Note: For iOS 16+, uses `AppStore.presentOfferCodeRedeemSheet(in:)`.
    ///         For iOS 14–15, falls back to `SKPaymentQueue.presentCodeRedemptionSheet()`.
    func presentOfferCodeRedemption() {
        lastErrorMessage = nil

        #if canImport(UIKit)
        if #available(iOS 16.0, *) {
            guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
                ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
            else {
                lastErrorMessage = "Unable to find an active window to present the code redemption sheet."
                return
            }

            Task {
                do {
                    try await AppStore.presentOfferCodeRedeemSheet(in: scene)
                    // After redemption, refresh local entitlements.
                    await refreshEntitlements()
                } catch {
                    let msg = error.localizedDescription
                    if msg.localizedCaseInsensitiveContains("cancel") {
                            return
                    }
                    if msg.localizedCaseInsensitiveContains("no active account") {
                        lastErrorMessage = """
                        Redeem Code requires an App Store account. This usually won’t work in the Simulator.
                        Try on a real device signed into the App Store.
                        """
                    } else {
                        lastErrorMessage = msg
                    }
                }
            }
        } else {
            SKPaymentQueue.default().presentCodeRedemptionSheet()
        }
        #else
        // Should never happen on iOS, but keep it safe for other platforms.
        lastErrorMessage = "Code redemption isn't available on this platform."
        #endif
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

import SwiftUI
import StoreKit

struct ProPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var proStore: ProStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Unlock NovaKey Pro")
                            .font(.title.bold())
                        Text("Unlimited listeners and secrets.")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityAddTraits(.isHeader)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Unlimited listeners", systemImage: "antenna.radiowaves.left.and.right")
                        Label("Unlimited secrets", systemImage: "lock.fill")
                        Label("Clipboard sending (included)", systemImage: "doc.on.clipboard")
                    }
                    .font(.body)

                    if let product = proStore.product {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Price:")
                                .foregroundStyle(.secondary)
                            Text(product.displayPrice)
                                .font(.headline)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Price \(product.displayPrice)")
                    } else {
                        Text("Loading price…")
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 10) {
                        Button {
                            Task { await proStore.purchasePro() }
                        } label: {
                            if proStore.isLoading {
                                ProgressView()
                            } else {
                                Text("Unlock Pro")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityHint("Purchases the Pro unlock.")

                        Button {
                            Task { await proStore.restorePurchases() }
                        } label: {
                            Text("Restore Purchases")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityHint("Restores your previous purchases.")
                    }

                    if proStore.isProUnlocked {
                        Text("Pro is unlocked on this device.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Pro is unlocked.")
                    }

                    if let msg = proStore.lastErrorMessage, !msg.isEmpty {
                        Text(msg)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(msg)
                    }

                    Text("SKU: NOVAKEY_IOS")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("SKU NOVAKEY I O S")
                }
                .padding()
            }
            .navigationTitle("NovaKey Pro")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await proStore.loadProduct()
                await proStore.refreshEntitlements()
            }
        }
    }
}

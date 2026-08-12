import Foundation
import Observation

@MainActor
@Observable
final class SettingsFeatureModel {
    var apiKeyInput = ""
    var declaredPlan = "Unknown"
    private(set) var isConfigured = false
    private(set) var isWorking = false
    private(set) var observedPlan = "Unknown"
    private(set) var entitlement: MarketEntitlementState = .unknown
    private(set) var capabilities: [MarketCapability] = []
    private(set) var endpointCapabilities: [ProviderEndpointCapability] = []
    private(set) var lastSuccessfulValidation: UTCInstant?
    private(set) var cacheStatistics: MarketCacheStatistics?
    private(set) var statusMessage: String?
    private(set) var errorMessage: String?
    var selectedMaximumMiB = 512

    @ObservationIgnored private let provider: any MarketDataProvider
    @ObservationIgnored private let credentialCoordinator: ProviderCredentialCoordinator
    @ObservationIgnored private let cache: MarketCacheStore
    @ObservationIgnored private let clock: any Clock

    init(
        provider: any MarketDataProvider,
        credentialCoordinator: ProviderCredentialCoordinator,
        cache: MarketCacheStore,
        clock: any Clock
    ) {
        self.provider = provider
        self.credentialCoordinator = credentialCoordinator
        self.cache = cache
        self.clock = clock
    }

    func load() async {
        isWorking = true
        defer { isWorking = false }
        do {
            isConfigured = try await credentialCoordinator.isConfigured()
            await refreshCapabilities()
            try await refreshCacheStatistics()
        } catch {
            errorMessage = safeMessage(for: error)
        }
    }

    func saveCredential() async {
        isWorking = true
        errorMessage = nil
        statusMessage = nil
        defer {
            apiKeyInput = ""
            isWorking = false
        }
        do {
            try await credentialCoordinator.save(apiKeyInput)
            isConfigured = true
            statusMessage = "Twelve Data credential saved in Keychain. The key is not displayed."
            await refreshCapabilities()
        } catch {
            errorMessage = safeMessage(for: error)
        }
    }

    func validateCredential() async {
        isWorking = true
        errorMessage = nil
        statusMessage = nil
        defer { isWorking = false }
        do {
            let usage = try await credentialCoordinator.validate()
            observedPlan = usage.planName ?? "Unknown"
            entitlement = usage.entitlement
            lastSuccessfulValidation = usage.observedAt
            statusMessage = "Credential validation succeeded. Capabilities remain endpoint-verified, not inferred from a typed plan name."
            await refreshCapabilities()
        } catch {
            errorMessage = safeMessage(for: error)
            await refreshCapabilities()
        }
    }

    func disconnect() async {
        isWorking = true
        errorMessage = nil
        statusMessage = nil
        defer { isWorking = false }
        do {
            _ = try await credentialCoordinator.disconnect()
            isConfigured = false
            observedPlan = "Unknown"
            entitlement = .missing
            lastSuccessfulValidation = nil
            capabilities = []
            endpointCapabilities = []
            statusMessage = "Disconnected. Keychain credential and Twelve Data recoverable cache were deleted."
            try await refreshCacheStatistics()
        } catch {
            errorMessage = safeMessage(for: error)
        }
    }

    func deleteCredential() async {
        isWorking = true
        errorMessage = nil
        statusMessage = nil
        defer { isWorking = false }
        do {
            _ = try await credentialCoordinator.deleteCredential()
            isConfigured = false
            entitlement = .missing
            observedPlan = "Unknown"
            lastSuccessfulValidation = nil
            capabilities = []
            endpointCapabilities = []
            statusMessage = "Key deleted. New requests stopped and Twelve Data recoverable cache was removed."
            try await refreshCacheStatistics()
        } catch {
            errorMessage = safeMessage(for: error)
        }
    }

    func removeExpired() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let result = try await cache.removeExpired(now: clock.now())
            statusMessage = "Removed \(result.removedEntries) expired recoverable cache entries."
            try await refreshCacheStatistics()
        } catch {
            errorMessage = safeMessage(for: error)
        }
    }

    func resetCache() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await cache.reset()
            statusMessage = "Market Cache reset and rebuilt. Permanent wealth data was outside this operation."
            selectedMaximumMiB = 512
            try await refreshCacheStatistics()
        } catch {
            errorMessage = safeMessage(for: error)
        }
    }

    func applyMaximum() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            let product = Int64(selectedMaximumMiB).multipliedReportingOverflow(
                by: CachePolicyConfiguration.mebibyte
            )
            guard !product.overflow else { throw CachePolicyError.overflow }
            let result = try await cache.updateMaximumBytes(product.partialValue, now: clock.now())
            statusMessage = "Market Cache capacity updated to \(selectedMaximumMiB) MiB; removed \(result.removedEntries) recoverable entries (\(result.removedBytes) bytes)."
            try await refreshCacheStatistics()
        } catch {
            errorMessage = safeMessage(for: error)
        }
    }

    func capability(for mic: String) -> MarketCapability? {
        capabilities.first(where: { $0.mic == mic })
    }

    private func refreshCapabilities() async {
        let observed = await provider.capabilities()
        entitlement = observed.entitlement
        observedPlan = observed.observedPlanName ?? observedPlan
        capabilities = observed.markets
        endpointCapabilities = observed.endpointCapabilities
    }

    private func refreshCacheStatistics() async throws {
        let statistics = try await cache.statistics()
        cacheStatistics = statistics
        selectedMaximumMiB = Int(statistics.maximumBytes / CachePolicyConfiguration.mebibyte)
    }

    private func safeMessage(for error: Error) -> String {
        switch error {
        case ProviderBoundaryError.missingCredential:
            "No Twelve Data API key is configured in Keychain."
        case ProviderBoundaryError.invalidOrExpired:
            "Twelve Data rejected the credential as invalid or expired. The key was not displayed or logged."
        case ProviderBoundaryError.unsupportedEntitlement:
            "The credential is valid enough to reach Twelve Data, but this operation is not authorized by the current entitlement."
        case ProviderBoundaryError.unsupportedMarket(let mic):
            "The current entitlement does not support market \(mic)."
        case ProviderBoundaryError.upgradeRequired:
            "This operation requires a higher Twelve Data plan or market entitlement."
        case ProviderBoundaryError.offline:
            "Validation is unavailable while offline. The credential was not deleted."
        case ProviderBoundaryError.timeout:
            "Provider validation timed out. Try again later."
        case ProviderBoundaryError.rateLimited:
            "Twelve Data rate limit reached. Retry after the provider window resets."
        case ProviderBoundaryError.requestCostExceedsLimit(let required, let available):
            "This endpoint costs \(required) credits, above the currently verified \(available)-credit request window."
        case ProviderBoundaryError.cancelled:
            "The operation was cancelled."
        case CachePolicyError.persistentRetentionUnverified:
            "Persistent Twelve Data caching is disabled until current retention rights are verified."
        case CachePolicyError.capacityCannotBeSatisfied:
            "The cache capacity cannot safely accept this entry. Permanent data remains available."
        case CredentialStoreError.invalidCredential:
            "Enter a non-empty user-owned Twelve Data API key."
        case is CredentialStoreError:
            "Keychain operation failed. No credential value was exposed."
        default:
            "The provider or cache operation failed without exposing credential or financial data."
        }
    }
}

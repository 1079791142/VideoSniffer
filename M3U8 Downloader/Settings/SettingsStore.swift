import Foundation
import Observation

@MainActor
@Observable
final class SettingsStore {
    private enum Key {
        static let concurrencyLimit = "settings.concurrencyLimit"
        static let retryLimit = "settings.retryLimit"
        static let timeoutSeconds = "settings.timeoutSeconds"
        static let proxyConfiguration = "settings.proxyConfiguration"
    }

    private let defaults: UserDefaults
    private let keychain: KeychainStore

    var concurrencyLimit: Int {
        didSet {
            defaults.set(concurrencyLimit, forKey: Key.concurrencyLimit)
        }
    }

    var retryLimit: Int {
        didSet {
            defaults.set(retryLimit, forKey: Key.retryLimit)
        }
    }

    var timeoutSeconds: Double {
        didSet {
            defaults.set(timeoutSeconds, forKey: Key.timeoutSeconds)
        }
    }

    var proxyConfiguration: ProxyConfiguration {
        didSet { saveProxyConfiguration() }
    }

    var proxyPassword: String {
        didSet {
            try? keychain.set(proxyPassword, account: "proxyPassword")
        }
    }

    init(defaults: UserDefaults = .standard, keychain: KeychainStore = .shared) {
        self.defaults = defaults
        self.keychain = keychain

        let storedConcurrency = defaults.integer(forKey: Key.concurrencyLimit)
        self.concurrencyLimit = storedConcurrency == 0 ? 6 : storedConcurrency.clamped(to: 1...24)

        let storedRetries = defaults.object(forKey: Key.retryLimit) as? Int
        self.retryLimit = (storedRetries ?? 3).clamped(to: 0...10)

        let storedTimeout = defaults.object(forKey: Key.timeoutSeconds) as? Double
        self.timeoutSeconds = (storedTimeout ?? 30).clamped(to: 5...300)

        if let data = defaults.data(forKey: Key.proxyConfiguration),
           let proxy = try? JSONDecoder().decode(ProxyConfiguration.self, from: data) {
            self.proxyConfiguration = proxy
        } else {
            self.proxyConfiguration = .disabled
        }

        self.proxyPassword = (try? keychain.string(account: "proxyPassword")) ?? ""
    }

    func makeURLSessionConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeoutSeconds
        configuration.timeoutIntervalForResource = max(timeoutSeconds, 60)
        proxyConfiguration.applying(to: configuration, password: proxyPassword)
        return configuration
    }

    private func saveProxyConfiguration() {
        if let data = try? JSONEncoder().encode(proxyConfiguration) {
            defaults.set(data, forKey: Key.proxyConfiguration)
        }
    }
}

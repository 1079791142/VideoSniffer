import Foundation

enum ProxyType: String, Codable, CaseIterable, Identifiable, Sendable {
    case none
    case http
#if os(macOS)
    case https
    case socks
#endif

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .none: .none
        case .http: .http
#if os(macOS)
        case .https: .https
        case .socks: .socks
#endif
        }
    }
}

struct ProxyConfiguration: Codable, Equatable, Sendable {
    var type: ProxyType
    var host: String
    var port: Int
    var username: String

    static let disabled = ProxyConfiguration(type: .none, host: "", port: 7890, username: "")

    var isEnabled: Bool {
        type != .none && !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && port > 0
    }

    func applying(to configuration: URLSessionConfiguration, password: String?) {
        guard isEnabled else {
            configuration.connectionProxyDictionary = nil
            return
        }

        var dictionary: [AnyHashable: Any] = [:]
        switch type {
        case .none:
            break
        case .http:
            dictionary[kCFNetworkProxiesHTTPEnable as String] = true
            dictionary[kCFNetworkProxiesHTTPProxy as String] = host
            dictionary[kCFNetworkProxiesHTTPPort as String] = port
#if os(macOS)
        case .https:
            dictionary[kCFNetworkProxiesHTTPSEnable as String] = true
            dictionary[kCFNetworkProxiesHTTPSProxy as String] = host
            dictionary[kCFNetworkProxiesHTTPSPort as String] = port
        case .socks:
            dictionary[kCFNetworkProxiesSOCKSEnable as String] = true
            dictionary[kCFNetworkProxiesSOCKSProxy as String] = host
            dictionary[kCFNetworkProxiesSOCKSPort as String] = port
#endif
        }
        
        if !username.isEmpty {
            dictionary[kCFProxyUsernameKey as String] = username
        }
        if let password, !password.isEmpty {
            dictionary[kCFProxyPasswordKey as String] = password
        }
        configuration.connectionProxyDictionary = dictionary
    }
}

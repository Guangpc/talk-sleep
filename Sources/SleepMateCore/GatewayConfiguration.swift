import Foundation

public struct AppGatewayConfiguration: Equatable, Sendable {
    public enum ValidationError: Error, Equatable, Sendable {
        case missingURL
        case invalidURL
        case unsupportedScheme
        case pathNotAllowed
        case missingToken
        case invalidToken
    }

    public let baseURL: URL
    public let appToken: String

    public init(gatewayURL: String, appToken: String) throws {
        let urlText = gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = appToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !urlText.isEmpty else { throw ValidationError.missingURL }
        guard var url = URL(string: urlText), url.host != nil else { throw ValidationError.invalidURL }
        guard url.scheme == "http" || url.scheme == "https" else { throw ValidationError.unsupportedScheme }
        guard url.path.isEmpty || url.path == "/" else { throw ValidationError.pathNotAllowed }
        guard !token.isEmpty else { throw ValidationError.missingToken }
        guard token.count >= 16, !token.contains(where: { $0.isWhitespace }) else { throw ValidationError.invalidToken }
        if url.path == "/" {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.path = ""
            guard let normalizedURL = components?.url else { throw ValidationError.invalidURL }
            url = normalizedURL
        }
        self.baseURL = url
        self.appToken = token
    }

    public init?(environment: [String: String]) {
        guard let gatewayURL = environment["SLEEPMATE_GATEWAY_URL"],
              let appToken = environment["SLEEPMATE_GATEWAY_TOKEN"] else { return nil }
        guard let configuration = try? Self(gatewayURL: gatewayURL, appToken: appToken) else { return nil }
        self = configuration
    }

    public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Self? {
        Self(environment: environment)
    }
}

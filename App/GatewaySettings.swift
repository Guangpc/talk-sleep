import SwiftUI
import Foundation
import Security
import SleepMateCore

@MainActor
final class GatewaySettings: ObservableObject {
    @Published private(set) var gatewayURL: String
    @Published private(set) var hasToken: Bool
    @Published private(set) var revision = 0
    @Published private(set) var lastError: String?

    private let defaults: UserDefaults
    private let tokenStore: GatewayTokenStore
    private let environment: [String: String]

    init(
        defaults: UserDefaults = .standard,
        tokenStore: GatewayTokenStore = KeychainGatewayTokenStore(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.defaults = defaults
        self.tokenStore = tokenStore
        self.environment = environment
        self.gatewayURL = defaults.string(forKey: Self.gatewayURLKey)
            ?? environment["SLEEPMATE_GATEWAY_URL"]
            ?? "http://127.0.0.1:8787"
        self.hasToken = (try? tokenStore.load())?.isEmpty == false
            || environment["SLEEPMATE_GATEWAY_TOKEN"]?.isEmpty == false
    }

    var configuration: AppGatewayConfiguration? {
        let token = (try? tokenStore.load()) ?? environment["SLEEPMATE_GATEWAY_TOKEN"]
        guard let token else { return nil }
        return try? AppGatewayConfiguration(gatewayURL: gatewayURL, appToken: token)
    }

    func refreshFromExternalConfiguration() {
        let environmentConfiguration = AppGatewayConfiguration.fromEnvironment(environment)
        guard let environmentConfiguration else { return }
        gatewayURL = environmentConfiguration.baseURL.absoluteString
        hasToken = true
        revision += 1
    }

    func save(gatewayURL: String, appToken: String) throws {
        let existingToken = try tokenStore.load()
        let token = appToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (existingToken ?? environment["SLEEPMATE_GATEWAY_TOKEN"] ?? "")
            : appToken
        let configuration = try AppGatewayConfiguration(gatewayURL: gatewayURL, appToken: token)
        try tokenStore.save(configuration.appToken)
        defaults.set(configuration.baseURL.absoluteString, forKey: Self.gatewayURLKey)
        self.gatewayURL = configuration.baseURL.absoluteString
        hasToken = true
        lastError = nil
        revision += 1
    }

    func clear() throws {
        try tokenStore.delete()
        defaults.removeObject(forKey: Self.gatewayURLKey)
        gatewayURL = environment["SLEEPMATE_GATEWAY_URL"] ?? "http://127.0.0.1:8787"
        hasToken = environment["SLEEPMATE_GATEWAY_TOKEN"]?.isEmpty == false
        lastError = nil
        revision += 1
    }

    private static let gatewayURLKey = "sleepmate.gateway.url"
}

protocol GatewayTokenStore {
    func load() throws -> String?
    func save(_ token: String) throws
    func delete() throws
}

struct KeychainGatewayTokenStore: GatewayTokenStore {
    private let service = "com.sleepmate.app.gateway"
    private let account = "app-token"

    func load() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return token
    }

    func save(_ token: String) throws {
        guard token.count >= 16, !token.contains(where: { $0.isWhitespace }) else {
            throw AppGatewayConfiguration.ValidationError.invalidToken
        }
        try delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(token.utf8),
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

struct GatewaySettingsCard: View {
    @ObservedObject var settings: GatewaySettings
    @State private var gatewayURL: String
    @State private var appToken: String
    @State private var isShowingToken = false
    @State private var message = ""
    @State private var isSaving = false
    @State private var isTesting = false

    init(settings: GatewaySettings) {
        self.settings = settings
        _gatewayURL = State(initialValue: settings.gatewayURL)
        _appToken = State(initialValue: "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Gateway 配置", systemImage: "network")
                .font(.headline)
            TextField("Gateway URL", text: $gatewayURL)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .accessibilityIdentifier("gateway-url-input")
            HStack {
                Group {
                    if isShowingToken {
                        TextField("App token", text: $appToken)
                    } else {
                        SecureField("App token", text: $appToken)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                Button {
                    isShowingToken.toggle()
                } label: {
                    Image(systemName: isShowingToken ? "eye.slash" : "eye")
                }
                .accessibilityLabel(isShowingToken ? "隐藏 App token" : "显示 App token")
            }
            Text("本地开发可使用 http://127.0.0.1:8787；App token 仅保存在 Keychain，不会显示或上传到 provider。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    save()
                } label: {
                    if isSaving { ProgressView() } else { Label("保存配置", systemImage: "checkmark") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || isTesting)
                Button {
                    testConnection()
                } label: {
                    if isTesting { ProgressView() } else { Label("测试连接", systemImage: "bolt.horizontal") }
                }
                .buttonStyle(.bordered)
                .disabled(isSaving || isTesting)
                if settings.hasToken {
                    Label("Token 已配置", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            if !message.isEmpty {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(message.hasPrefix("配置成功") ? .green : .red)
            }
        }
        .padding(16)
        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary))
        .onChange(of: settings.revision) { _, _ in
            gatewayURL = settings.gatewayURL
        }
    }

    private func testConnection() {
        isTesting = true
        message = ""
        Task { @MainActor in
            defer { isTesting = false }
            guard let configuration = settings.configuration else {
                message = "请先保存有效配置。"
                return
            }
            var request = URLRequest(url: configuration.baseURL.appendingPathComponent("health"))
            request.httpMethod = "GET"
            request.setValue("Bearer \(configuration.appToken)", forHTTPHeaderField: "Authorization")
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    message = "连接失败：gateway 未返回 200。"
                    return
                }
                message = "连接成功。"
            } catch {
                message = "连接失败：请检查 gateway 是否启动和 URL 是否可达。"
            }
        }
    }

    private func save() {
        isSaving = true
        defer { isSaving = false }
        do {
            try settings.save(gatewayURL: gatewayURL, appToken: appToken)
            appToken = ""
            message = "配置成功，下一次分析或创建好友会使用此 gateway。"
        } catch {
            message = "配置无效：请检查 URL 和 App token。"
        }
    }
}

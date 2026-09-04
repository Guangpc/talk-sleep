import Foundation
import XCTest
@testable import SleepMateCore

final class GatewayConfigurationTests: XCTestCase {
    func testAppGatewayConfigurationLoadsValidURLAndToken() throws {
        let configuration = try AppGatewayConfiguration(
            gatewayURL: "http://127.0.0.1:8787",
            appToken: "local-token-1234567890"
        )

        XCTAssertEqual(configuration.baseURL.absoluteString, "http://127.0.0.1:8787")
        XCTAssertEqual(configuration.appToken, "local-token-1234567890")
    }

    func testAppGatewayConfigurationRejectsMissingOrMalformedValues() {
        XCTAssertThrowsError(try AppGatewayConfiguration(gatewayURL: "", appToken: "token"))
        XCTAssertThrowsError(try AppGatewayConfiguration(gatewayURL: "127.0.0.1:8787", appToken: "token"))
        XCTAssertThrowsError(try AppGatewayConfiguration(gatewayURL: "http://127.0.0.1:8787", appToken: "short"))
        XCTAssertThrowsError(try AppGatewayConfiguration(gatewayURL: "http://127.0.0.1:8787/path", appToken: "local-token-1234567890"))
    }

    func testAppGatewayConfigurationTrimsInputsAndRejectsWhitespaceInToken() throws {
        let configuration = try AppGatewayConfiguration(
            gatewayURL: "  http://127.0.0.1:8787/  ",
            appToken: "  local-token-1234567890  "
        )
        XCTAssertEqual(configuration.baseURL.absoluteString, "http://127.0.0.1:8787")
        XCTAssertEqual(configuration.appToken, "local-token-1234567890")

        XCTAssertThrowsError(try AppGatewayConfiguration(gatewayURL: "http://127.0.0.1:8787", appToken: "local token 123456"))
    }
}

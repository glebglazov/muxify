import XCTest

final class CommandLineToolForwardingTests: XCTestCase {
    private let tool = "/Applications/Muxify.app/Contents/Resources/bin/muxify"

    func testShellLookupOfMuxifyHandsArgumentsToTheTool() {
        XCTAssertEqual(CommandLineToolForwarding.toolArguments(for: ["muxify", "browser", "open", "https://example.com"], tool: tool),
                       [tool, "browser", "open", "https://example.com"])
        XCTAssertEqual(CommandLineToolForwarding.toolArguments(for: ["/Applications/Muxify.app/Contents/MacOS/muxify"], tool: tool),
                       [tool])
    }

    func testAppLaunchesKeepRunningTheApp() {
        XCTAssertNil(CommandLineToolForwarding.toolArguments(for: ["/Applications/Muxify.app/Contents/MacOS/Muxify"], tool: tool))
        XCTAssertNil(CommandLineToolForwarding.toolArguments(for: ["Muxify", "-NSDocumentRevisionsDebugMode", "YES"], tool: tool))
        XCTAssertNil(CommandLineToolForwarding.toolArguments(for: [], tool: tool))
    }
}

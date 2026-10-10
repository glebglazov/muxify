import XCTest
@testable import MuxifyCore

final class ShowAgentsTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suite = "ShowAgentsTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testBothModesStartFromTheSingleEarlierValue() {
        defaults.set(false, forKey: "agentsVisible")
        let showAgents = ShowAgents(defaults: defaults)
        XCTAssertFalse(showAgents[.topics])
        XCTAssertFalse(showAgents[.sessions])
    }

    func testBothModesShowAgentsWithNoStoredValue() {
        let showAgents = ShowAgents(defaults: defaults)
        XCTAssertTrue(showAgents[.topics])
        XCTAssertTrue(showAgents[.sessions])
    }

    func testTogglingOneModeKeepsTheOtherModesValue() {
        defaults.set(true, forKey: "agentsVisible")
        var showAgents = ShowAgents(defaults: defaults)
        showAgents[.topics] = false
        XCTAssertFalse(ShowAgents(defaults: defaults)[.topics], "the Topics value is remembered")
        XCTAssertTrue(ShowAgents(defaults: defaults)[.sessions], "the Sessions value still starts from the earlier value")
    }
}

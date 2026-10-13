import XCTest

final class WindowNavigationTests: XCTestCase {
    func testNumberedPositionsAreOneBased() {
        for position in 1...9 {
            XCTAssertEqual(WindowNavigation.position(position).targetIndex(currentIndex: 4, count: 12), position - 1)
        }
    }

    func testMissingPositionsDoNotSwitchToTheLastWindow() {
        for position in [-1, 0, 4, 9] {
            XCTAssertNil(WindowNavigation.position(position).targetIndex(currentIndex: 0, count: 3))
        }
    }

    func testLastMeansTheLastWindowRatherThanPositionNine() {
        XCTAssertEqual(WindowNavigation.last.targetIndex(currentIndex: 0, count: 12), 11)
        XCTAssertEqual(WindowNavigation.position(9).targetIndex(currentIndex: 0, count: 12), 8)
    }

    func testNavigationWithOnlyOneWindow() {
        for navigation in [WindowNavigation.position(1), .last] {
            XCTAssertEqual(navigation.targetIndex(currentIndex: 0, count: 1), 0)
        }
        XCTAssertNil(WindowNavigation.position(2).targetIndex(currentIndex: 0, count: 1))
    }

    func testNavigationWithoutACurrentWindowDoesNothing() {
        for navigation in [WindowNavigation.position(1), .last] {
            XCTAssertNil(navigation.targetIndex(currentIndex: 0, count: 0))
            XCTAssertNil(navigation.targetIndex(currentIndex: -1, count: 3))
            XCTAssertNil(navigation.targetIndex(currentIndex: 3, count: 3))
        }
    }
}

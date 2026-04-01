import XCTest
@testable import MenuBarManagerCore

final class VisibilityPolicyTests: XCTestCase {
    func testStateIsOnlyProcessedWhenStatusOrVisibilityChanges() {
        XCTAssertFalse(
            MenuBarVisibilityPolicy.shouldProcess(
                previousStatus: "hidden",
                previousVisibility: false,
                currentStatus: "hidden",
                currentVisibility: false,
                force: false
            )
        )
        XCTAssertTrue(
            MenuBarVisibilityPolicy.shouldProcess(
                previousStatus: "hidden",
                previousVisibility: true,
                currentStatus: "hidden",
                currentVisibility: false,
                force: false
            )
        )
        XCTAssertTrue(
            MenuBarVisibilityPolicy.shouldProcess(
                previousStatus: "visible",
                previousVisibility: true,
                currentStatus: "hidden",
                currentVisibility: true,
                force: false
            )
        )
        XCTAssertTrue(
            MenuBarVisibilityPolicy.shouldProcess(
                previousStatus: "hidden",
                previousVisibility: false,
                currentStatus: "hidden",
                currentVisibility: false,
                force: true
            )
        )
    }

    func testCollapsedHiddenItemsAreHidden() {
        XCTAssertEqual(
            MenuBarVisibilityPolicy.action(
                status: "hidden",
                isRevealed: false,
                isCurrentlyVisible: true
            ),
            .hide
        )
    }

    func testDesiredPlacementMapsStatusesToStableZones() {
        XCTAssertEqual(
            MenuBarVisibilityPolicy.desiredPlacement(
                status: "hidden",
                isExpanded: false
            ),
            .hidden
        )
        XCTAssertEqual(
            MenuBarVisibilityPolicy.desiredPlacement(
                status: "hidden",
                isExpanded: true
            ),
            .hidden
        )
        XCTAssertEqual(
            MenuBarVisibilityPolicy.desiredPlacement(
                status: "disabled",
                isExpanded: true
            ),
            .disabled
        )
        XCTAssertEqual(
            MenuBarVisibilityPolicy.desiredPlacement(
                status: "visible",
                isExpanded: false
            ),
            .visible
        )
    }

    func testRevealedHiddenItemsAreLeftVisible() {
        XCTAssertEqual(
            MenuBarVisibilityPolicy.action(
                status: "hidden",
                isRevealed: true,
                isCurrentlyVisible: false
            ),
            .none
        )
    }

    func testDisabledItemsStayHiddenEvenWhenRevealed() {
        XCTAssertEqual(
            MenuBarVisibilityPolicy.action(
                status: "disabled",
                isRevealed: true,
                isCurrentlyVisible: true
            ),
            .hide
        )
    }

    func testVisibleItemsAreLeftAlone() {
        XCTAssertEqual(
            MenuBarVisibilityPolicy.action(
                status: "visible",
                isRevealed: false,
                isCurrentlyVisible: false
            ),
            .none
        )
    }

    func testMissingItemsAreOnlyRetainedWhileOwnerIsRunning() {
        XCTAssertTrue(
            MenuBarVisibilityPolicy.shouldRetainMissingItem(
                status: "hidden",
                processIsRunning: true
            )
        )
        XCTAssertTrue(
            MenuBarVisibilityPolicy.shouldRetainMissingItem(
                status: "disabled",
                processIsRunning: true
            )
        )
        XCTAssertFalse(
            MenuBarVisibilityPolicy.shouldRetainMissingItem(
                status: "visible",
                processIsRunning: true
            )
        )
        XCTAssertFalse(
            MenuBarVisibilityPolicy.shouldRetainMissingItem(
                status: "hidden",
                processIsRunning: false
            )
        )
    }
}

import XCTest
@testable import MalatangLog

final class StoreAccessPolicyTests: XCTestCase {
    func testFiveUniqueStoresRemainFree() {
        let fourStores = Set((0..<4).map { _ in UUID() })

        XCTAssertFalse(
            StoreAccessPolicy.requiresUnlock(
                isUnlocked: false,
                visitedStoreIDs: fourStores,
                selectedStoreID: UUID()
            )
        )
    }

    func testSixthUniqueStoreRequiresUnlock() {
        let fiveStores = Set((0..<5).map { _ in UUID() })

        XCTAssertTrue(
            StoreAccessPolicy.requiresUnlock(
                isUnlocked: false,
                visitedStoreIDs: fiveStores,
                selectedStoreID: UUID()
            )
        )
    }

    func testExistingStoreNeverRequiresUnlock() throws {
        let fiveStores = Set((0..<5).map { _ in UUID() })
        let existing = try XCTUnwrap(fiveStores.first)

        XCTAssertFalse(
            StoreAccessPolicy.requiresUnlock(
                isUnlocked: false,
                visitedStoreIDs: fiveStores,
                selectedStoreID: existing
            )
        )
    }

    func testUnlockedUserHasNoStoreLimit() {
        let stores = Set((0..<20).map { _ in UUID() })

        XCTAssertFalse(
            StoreAccessPolicy.requiresUnlock(
                isUnlocked: true,
                visitedStoreIDs: stores,
                selectedStoreID: UUID()
            )
        )
    }

    func testRecordWithoutStoreDoesNotRequireUnlock() {
        let stores = Set((0..<5).map { _ in UUID() })

        XCTAssertFalse(
            StoreAccessPolicy.requiresUnlock(
                isUnlocked: false,
                visitedStoreIDs: stores,
                selectedStoreID: nil
            )
        )
    }

    func testRemainingFreeStoresNeverBecomesNegative() {
        XCTAssertEqual(StoreAccessPolicy.remainingFreeStores(visitedStoreCount: 3), 2)
        XCTAssertEqual(StoreAccessPolicy.remainingFreeStores(visitedStoreCount: 5), 0)
        XCTAssertEqual(StoreAccessPolicy.remainingFreeStores(visitedStoreCount: 12), 0)
    }
}

import XCTest
import SwiftData
@testable import MalatangLog

final class BackupServiceTests: XCTestCase {

    private func makeContext() throws -> ModelContext {
        let container = try AppModelContainer.make(inMemory: true)
        return ModelContext(container)
    }

    private func seedSampleData(_ context: ModelContext) throws -> Serving {
        MasterService.seedIfNeeded(context)
        let soups = try context.fetch(FetchDescriptor<Soup>())
        let noodles = try context.fetch(FetchDescriptor<Noodle>())
        let ingredients = try context.fetch(FetchDescriptor<Ingredient>())
        let store = MasterService.findOrCreateStore(
            name: "テスト店",
            branch: "本店",
            address: "Đà Nẵng, Việt Nam",
            latitude: 16.0544,
            longitude: 108.2022,
            in: context
        )

        let serving = Serving(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            spiceLevel: 4,
            numbnessLevel: 3,
            priceYen: 1_280,
            rating: 4,
            memo: "テスト記録",
            store: store,
            soup: soups.first,
            noodles: Array(noodles.prefix(2)),
            ingredients: Array(ingredients.prefix(5))
        )
        context.insert(serving)
        try context.save()
        return serving
    }

    func testExportAndRestoreRoundTrip() throws {
        let source = try makeContext()
        let original = try seedSampleData(source)

        let url = try BackupService.export(context: source)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.pathExtension, BackupFormat.fileExtension)

        let inspection = try BackupService.inspect(url: url)
        XCTAssertEqual(inspection.payload.formatVersion, BackupFormat.currentVersion)
        XCTAssertEqual(inspection.payload.servings.count, 1)

        let destination = try makeContext()
        let result = try BackupService.restore(inspection: inspection, mode: .append, context: destination)

        XCTAssertEqual(result.addedServings, 1)
        XCTAssertEqual(result.skippedServings, 0)

        let restored = try destination.fetch(FetchDescriptor<Serving>())
        XCTAssertEqual(restored.count, 1)
        let restoredServing = try XCTUnwrap(restored.first)
        XCTAssertEqual(restoredServing.uuid, original.uuid)
        XCTAssertEqual(restoredServing.spiceLevel, 4)
        XCTAssertEqual(restoredServing.numbnessLevel, 3)
        XCTAssertEqual(restoredServing.priceYen, 1_280)
        XCTAssertEqual(restoredServing.memo, "テスト記録")
        XCTAssertEqual(restoredServing.store?.displayName, "テスト店 本店")
        XCTAssertEqual(restoredServing.store?.address, "Đà Nẵng, Việt Nam")
        XCTAssertEqual(restoredServing.store?.latitude, 16.0544)
        XCTAssertEqual(restoredServing.store?.longitude, 108.2022)
        XCTAssertEqual(restoredServing.noodles.count, original.noodles.count)
        XCTAssertEqual(restoredServing.ingredients.count, original.ingredients.count)
    }

    func testRestoringSameBackupTwiceSkipsDuplicates() throws {
        let source = try makeContext()
        _ = try seedSampleData(source)
        let url = try BackupService.export(context: source)
        defer { try? FileManager.default.removeItem(at: url) }

        let destination = try makeContext()
        let inspection = try BackupService.inspect(url: url)

        let first = try BackupService.restore(inspection: inspection, mode: .append, context: destination)
        XCTAssertEqual(first.addedServings, 1)

        let second = try BackupService.restore(inspection: inspection, mode: .append, context: destination)
        XCTAssertEqual(second.addedServings, 0)
        XCTAssertEqual(second.skippedServings, 1)

        XCTAssertEqual(try destination.fetch(FetchDescriptor<Serving>()).count, 1, "同じバックアップを2回入れても件数は増えない")
    }

    func testReplaceAllWipesExistingRecords() throws {
        let source = try makeContext()
        _ = try seedSampleData(source)
        let url = try BackupService.export(context: source)
        defer { try? FileManager.default.removeItem(at: url) }

        let destination = try makeContext()
        MasterService.seedIfNeeded(destination)
        let other = Serving(date: Date(), spiceLevel: 1, numbnessLevel: 1)
        destination.insert(other)
        try destination.save()
        XCTAssertEqual(try destination.fetch(FetchDescriptor<Serving>()).count, 1)

        let inspection = try BackupService.inspect(url: url)
        let result = try BackupService.restore(inspection: inspection, mode: .replaceAll, context: destination)

        XCTAssertEqual(result.mode, .replaceAll)
        let servings = try destination.fetch(FetchDescriptor<Serving>())
        XCTAssertEqual(servings.count, 1)
        XCTAssertEqual(servings.first?.memo, "テスト記録", "既存の記録は消えてバックアップの内容に入れ替わる")
    }

    func testInspectRejectsNonArchive() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("broken.malaarchive")
        try Data("これはバックアップではありません".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try BackupService.inspect(url: url))
    }

    func testEstimateReportsCounts() throws {
        let context = try makeContext()
        _ = try seedSampleData(context)
        let estimate = BackupService.estimate(context: context)
        XCTAssertEqual(estimate.servingCount, 1)
        XCTAssertEqual(estimate.storeCount, 1)
        XCTAssertGreaterThan(estimate.estimatedBytes, 0)
        XCTAssertFalse(estimate.estimatedSizeText.isEmpty)
    }
}

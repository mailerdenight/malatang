import XCTest
import SwiftData
import UIKit
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

    private enum TestFailure: Error { case diskFull }

    private struct SafetyFixture {
        let context: ModelContext
        let photos: PhotoStore
        let oldPhotoID: String
        let oldPhoto: Data
        var inspection: BackupService.Inspection
    }

    private func makeSafetyFixture() throws -> SafetyFixture {
        let context = try makeContext()
        let serving = try seedSampleData(context)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let photos = try PhotoStore(directory: directory)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let favorites = FavoriteStoreService.shared.ids
        addTeardownBlock {
            FavoriteStoreService.shared.removeAll()
            for id in favorites {
                FavoriteStoreService.shared.set(Store(uuid: id, name: ""), isFavorite: true)
            }
        }
        FavoriteStoreService.shared.set(try XCTUnwrap(serving.store), isFavorite: true)
        let oldPhotoID = UUID().uuidString
        // Distinct valid JPEGs exercise photo-ID collision without corrupt archive data.
        let oldPhoto = try imageData(color: .red)
        XCTAssertTrue(photos.writeRaw(oldPhoto, id: oldPhotoID))
        serving.photoID = oldPhotoID
        try context.save()
        var payload = BackupService.makePayload(context: context)
        payload.servings[0].memo = "復元後"
        payload.stores[0].isFavorite = false
        let inspection = BackupService.Inspection(
            payload: payload, images: [oldPhotoID: try imageData(color: .blue)]
        )
        return SafetyFixture(
            context: context, photos: photos, oldPhotoID: oldPhotoID,
            oldPhoto: oldPhoto, inspection: inspection
        )
    }

    private func imageData(color: UIColor) throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { renderer in
            color.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        return try XCTUnwrap(image.jpegData(compressionQuality: 1))
    }

    private func snapshot(_ context: ModelContext) throws -> Data {
        var payload = BackupService.makePayload(context: context)
        payload.exportedAt = Date(timeIntervalSince1970: 0)
        payload.stores.sort { $0.uuid.uuidString < $1.uuid.uuidString }
        payload.soups.sort { $0.uuid.uuidString < $1.uuid.uuidString }
        payload.noodles.sort { $0.uuid.uuidString < $1.uuid.uuidString }
        payload.ingredients.sort { $0.uuid.uuidString < $1.uuid.uuidString }
        payload.servings.sort { $0.uuid.uuidString < $1.uuid.uuidString }
        for index in payload.servings.indices {
            payload.servings[index].noodleUUIDs.sort { $0.uuidString < $1.uuidString }
            payload.servings[index].ingredientUUIDs.sort { $0.uuidString < $1.uuidString }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(payload)
    }

    private func assertOriginalPreserved(
        _ fixture: SafetyFixture, snapshot expected: Data, favorites: Set<UUID>,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertEqual(try snapshot(fixture.context), expected, file: file, line: line)
        // Verify persisted data independently of the context that performed rollback.
        let freshContext = ModelContext(fixture.context.container)
        XCTAssertEqual(try snapshot(freshContext), expected, file: file, line: line)
        XCTAssertEqual(fixture.photos.rawData(fixture.oldPhotoID), fixture.oldPhoto, file: file, line: line)
        XCTAssertEqual(FavoriteStoreService.shared.ids, favorites, file: file, line: line)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: fixture.photos.directory.path),
            ["\(fixture.oldPhotoID).jpg"], file: file, line: line
        )
        XCTAssertFalse(fixture.context.hasChanges, file: file, line: line)
    }

    func testReplaceSaveFailurePreservesRecordsPhotosAndFavorites() throws {
        let fixture = try makeSafetyFixture()
        fixture.context.autosaveEnabled = true
        let expected = try snapshot(fixture.context)
        let favorites = FavoriteStoreService.shared.ids
        var operations = BackupService.RestoreOperations()
        operations.photos = fixture.photos
        operations.save = { context in
            XCTAssertFalse(context.autosaveEnabled)
            XCTAssertTrue(context.hasChanges)
            throw TestFailure.diskFull
        }
        XCTAssertThrowsError(try BackupService.restore(
            inspection: fixture.inspection, mode: .replaceAll,
            context: fixture.context, operations: operations
        ))
        try assertOriginalPreserved(fixture, snapshot: expected, favorites: favorites)
        XCTAssertTrue(fixture.context.autosaveEnabled)
    }

    func testReplacePhotoWriteFailureAfterFirstPhotoRollsBack() throws {
        var fixture = try makeSafetyFixture()
        var second = fixture.inspection.payload.servings[0]
        second.uuid = UUID()
        second.photoID = UUID().uuidString
        fixture.inspection.payload.servings.append(second)
        fixture.inspection.images[try XCTUnwrap(second.photoID)] = fixture.oldPhoto
        let expected = try snapshot(fixture.context)
        let favorites = FavoriteStoreService.shared.ids
        var operations = BackupService.RestoreOperations()
        operations.photos = fixture.photos
        var writes = 0
        operations.writePhoto = { data, id, photos in
            writes += 1
            // Also exercise cleanup of the failing operation's partially created file.
            XCTAssertTrue(photos.writeRaw(data, id: id))
            if writes == 2 { throw TestFailure.diskFull }
        }
        XCTAssertThrowsError(try BackupService.restore(
            inspection: fixture.inspection, mode: .replaceAll,
            context: fixture.context, operations: operations
        ))
        XCTAssertEqual(writes, 2)
        try assertOriginalPreserved(fixture, snapshot: expected, favorites: favorites)
    }

    func testActualPhotoWriteFailurePreservesOriginals() throws {
        let fixture = try makeSafetyFixture()
        let expected = try snapshot(fixture.context)
        let favorites = FavoriteStoreService.shared.ids
        // A regular file used as a directory forces the real atomic photo write to fail.
        let blocked = fixture.photos.directory.appendingPathComponent("blocked")
        var operations = BackupService.RestoreOperations()
        operations.photos = try PhotoStore(directory: blocked)
        try FileManager.default.removeItem(at: blocked)
        try Data([0]).write(to: blocked)
        XCTAssertThrowsError(try BackupService.restore(
            inspection: fixture.inspection, mode: .replaceAll,
            context: fixture.context, operations: operations
        ))
        try FileManager.default.removeItem(at: blocked)
        try assertOriginalPreserved(fixture, snapshot: expected, favorites: favorites)
    }

    func testAppendSaveFailureDoesNotOverwriteCollidingPhoto() throws {
        var fixture = try makeSafetyFixture()
        fixture.inspection.payload.servings[0].uuid = UUID()
        let expected = try snapshot(fixture.context)
        let favorites = FavoriteStoreService.shared.ids
        var operations = BackupService.RestoreOperations()
        operations.photos = fixture.photos
        operations.save = { _ in throw TestFailure.diskFull }
        XCTAssertThrowsError(try BackupService.restore(
            inspection: fixture.inspection, mode: .append,
            context: fixture.context, operations: operations
        ))
        try assertOriginalPreserved(fixture, snapshot: expected, favorites: favorites)
    }

    func testReplaceSuccessCommitsSameUUIDsPhotosAndFavorites() throws {
        let fixture = try makeSafetyFixture()
        var operations = BackupService.RestoreOperations()
        operations.photos = fixture.photos
        let result = try BackupService.restore(
            inspection: fixture.inspection, mode: .replaceAll,
            context: fixture.context, operations: operations
        )
        XCTAssertEqual(result.restoredPhotos, 1)
        XCTAssertEqual(result.missingPhotos, 0)
        let freshContext = ModelContext(fixture.context.container)
        let servings = try freshContext.fetch(FetchDescriptor<Serving>())
        let serving = try XCTUnwrap(servings.first)
        XCTAssertEqual(servings.count, 1)
        XCTAssertEqual(serving.uuid, fixture.inspection.payload.servings[0].uuid)
        XCTAssertEqual(serving.memo, "復元後")
        XCTAssertEqual(serving.store?.uuid, fixture.inspection.payload.stores[0].uuid)
        XCTAssertEqual(serving.noodles.count, fixture.inspection.payload.servings[0].noodleUUIDs.count)
        XCTAssertEqual(serving.ingredients.count, fixture.inspection.payload.servings[0].ingredientUUIDs.count)
        XCTAssertNotEqual(serving.photoID, fixture.oldPhotoID)
        XCTAssertEqual(fixture.photos.rawData(serving.photoID), fixture.inspection.images[fixture.oldPhotoID])
        XCTAssertFalse(fixture.photos.exists(fixture.oldPhotoID))
        XCTAssertFalse(FavoriteStoreService.shared.contains(serving.store))
    }

    func testAppendSuccessPreservesExistingPhotoOnIDCollision() throws {
        var fixture = try makeSafetyFixture()
        fixture.inspection.payload.servings[0].uuid = UUID()
        var operations = BackupService.RestoreOperations()
        operations.photos = fixture.photos
        let result = try BackupService.restore(
            inspection: fixture.inspection, mode: .append,
            context: fixture.context, operations: operations
        )
        XCTAssertEqual(result.addedServings, 1)
        XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<Serving>()).count, 2)
        XCTAssertEqual(fixture.photos.rawData(fixture.oldPhotoID), fixture.oldPhoto)
        let second = try BackupService.restore(
            inspection: fixture.inspection, mode: .append,
            context: fixture.context, operations: operations
        )
        XCTAssertEqual(second.skippedServings, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.photos.directory.path).count, 2)
    }

    func testInvalidArchivesAreRejectedBeforeMutation() throws {
        let fixture = try makeSafetyFixture()
        let expected = try snapshot(fixture.context)
        let favorites = FavoriteStoreService.shared.ids
        var invalid: [BackupService.Inspection] = []
        var duplicate = fixture.inspection
        duplicate.payload.servings.append(duplicate.payload.servings[0])
        invalid.append(duplicate)
        var missingReference = fixture.inspection
        missingReference.payload.servings[0].storeUUID = UUID()
        invalid.append(missingReference)
        var unsafePhoto = fixture.inspection
        unsafePhoto.payload.servings[0].photoID = "../outside"
        invalid.append(unsafePhoto)
        var corruptPhoto = fixture.inspection
        corruptPhoto.images[fixture.oldPhotoID] = Data([0, 1, 2])
        invalid.append(corruptPhoto)
        var futureVersion = fixture.inspection
        futureVersion.payload.formatVersion = BackupFormat.currentVersion + 1
        invalid.append(futureVersion)
        var operations = BackupService.RestoreOperations()
        operations.photos = fixture.photos
        operations.writePhoto = { _, _, _ in XCTFail("Validation must precede photo writes") }
        operations.save = { _ in XCTFail("Validation must precede save") }
        for inspection in invalid {
            XCTAssertThrowsError(try BackupService.restore(
                inspection: inspection, mode: .replaceAll,
                context: fixture.context, operations: operations
            ))
            try assertOriginalPreserved(fixture, snapshot: expected, favorites: favorites)
        }
    }

    func testMissingPhotosAndLegacyFavoritesRemainCompatible() throws {
        var fixture = try makeSafetyFixture()
        fixture.inspection.images = [:]
        fixture.inspection.payload.stores[0].isFavorite = nil
        var operations = BackupService.RestoreOperations()
        operations.photos = fixture.photos
        let result = try BackupService.restore(
            inspection: fixture.inspection, mode: .replaceAll,
            context: fixture.context, operations: operations
        )
        XCTAssertEqual(result.missingPhotos, 1)
        XCTAssertEqual(result.addedServings, 1)
        XCTAssertNil(try fixture.context.fetch(FetchDescriptor<Serving>()).first?.photoID)
    }

    func testPhotoArchiveExportInspectAndRestoreRoundTrip() throws {
        let source = try makeContext()
        let original = try seedSampleData(source)
        let photoID = UUID().uuidString
        let photo = try imageData(color: .green)
        XCTAssertTrue(PhotoStore.shared.writeRaw(photo, id: photoID))
        defer { PhotoStore.shared.delete(photoID) }
        original.photoID = photoID
        try source.save()
        let archive = try BackupService.export(context: source)
        defer { try? FileManager.default.removeItem(at: archive) }
        let inspection = try BackupService.inspect(url: archive)
        XCTAssertEqual(inspection.images[photoID], photo)

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let photos = try PhotoStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = try makeContext()
        var operations = BackupService.RestoreOperations()
        operations.photos = photos
        let result = try BackupService.restore(
            inspection: inspection, mode: .append, context: destination, operations: operations
        )
        XCTAssertEqual(result.restoredPhotos, 1)
        let restored = try XCTUnwrap(try destination.fetch(FetchDescriptor<Serving>()).first)
        XCTAssertEqual(photos.rawData(restored.photoID), photo)
        XCTAssertEqual(restored.uuid, original.uuid)
    }

    func testPendingEditsSurviveRestoreSaveFailure() throws {
        let fixture = try makeSafetyFixture()
        let serving = try XCTUnwrap(try fixture.context.fetch(FetchDescriptor<Serving>()).first)
        serving.memo = "復元前の未保存編集"
        let expected = try snapshot(fixture.context)
        let favorites = FavoriteStoreService.shared.ids
        var operations = BackupService.RestoreOperations()
        operations.photos = fixture.photos
        operations.save = { _ in throw TestFailure.diskFull }
        XCTAssertThrowsError(try BackupService.restore(
            inspection: fixture.inspection, mode: .replaceAll,
            context: fixture.context, operations: operations
        ))
        try assertOriginalPreserved(fixture, snapshot: expected, favorites: favorites)
    }

}

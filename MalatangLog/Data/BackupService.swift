import Foundation
import SwiftData
import UIKit

/// .malaarchive の書き出しと取り込み。
/// 単一ファイルに見せるため FileWrapper のシリアライズ表現を使う（中身は database.json + images/）。
enum BackupService {

    // MARK: - 事前見積り

    static func estimate(context: ModelContext) -> ExportEstimate {
        let servings = (try? context.fetch(FetchDescriptor<Serving>())) ?? []
        let stores = (try? context.fetch(FetchDescriptor<Store>())) ?? []
        let photoIDs = servings.compactMap(\.photoID).filter { PhotoStore.shared.exists($0) }
        let photoBytes = photoIDs.reduce(Int64(0)) { sum, id in
            let size = (try? PhotoStore.shared.fileURL(for: id).resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
        // JSON はおおよそ 1件 1.5KB 程度
        let jsonBytes = Int64(servings.count) * 1_500 + 20_000
        return ExportEstimate(
            servingCount: servings.count,
            photoCount: photoIDs.count,
            storeCount: stores.count,
            estimatedBytes: photoBytes + jsonBytes
        )
    }

    // MARK: - 書き出し

    static func makePayload(context: ModelContext) -> BackupPayload {
        let servings = (try? context.fetch(FetchDescriptor<Serving>())) ?? []
        let stores = (try? context.fetch(FetchDescriptor<Store>())) ?? []
        let soups = (try? context.fetch(FetchDescriptor<Soup>())) ?? []
        let noodles = (try? context.fetch(FetchDescriptor<Noodle>())) ?? []
        let ingredients = (try? context.fetch(FetchDescriptor<Ingredient>())) ?? []

        return BackupPayload(
            formatVersion: BackupFormat.currentVersion,
            appVersion: AppInfo.versionString,
            exportedAt: Date(),
            stores: stores.map {
                StoreDTO(
                    uuid: $0.uuid, name: $0.name, branch: $0.branch, address: $0.address,
                    latitude: $0.latitude, longitude: $0.longitude, createdAt: $0.createdAt,
                    isFavorite: FavoriteStoreService.shared.contains($0)
                )
            },
            soups: soups.map {
                SoupDTO(
                    uuid: $0.uuid, name: $0.name, reading: $0.reading, aliases: $0.aliases,
                    isCustom: $0.isCustom, isHidden: $0.isHidden, sortOrder: $0.sortOrder
                )
            },
            noodles: noodles.map {
                NoodleDTO(
                    uuid: $0.uuid, name: $0.name, reading: $0.reading, aliases: $0.aliases,
                    isCustom: $0.isCustom, isHidden: $0.isHidden, sortOrder: $0.sortOrder
                )
            },
            ingredients: ingredients.map {
                IngredientDTO(
                    uuid: $0.uuid, name: $0.name, reading: $0.reading, aliases: $0.aliases,
                    category: $0.categoryRaw, isCustom: $0.isCustom, isHidden: $0.isHidden,
                    isPinned: $0.isPinned, pinnedAt: $0.pinnedAt, sortOrder: $0.sortOrder
                )
            },
            servings: servings.map { serving in
                ServingDTO(
                    uuid: serving.uuid,
                    date: serving.date,
                    photoID: serving.photoID,
                    spiceLevel: serving.spiceLevel,
                    numbnessLevel: serving.numbnessLevel,
                    spiceNote: serving.spiceNote,
                    priceYen: serving.priceYen,
                    currencyCode: serving.currencyCode,
                    totalWeightGrams: serving.totalWeightGrams,
                    pricePer100gYen: serving.pricePer100gYen,
                    soupSurchargeYen: serving.soupSurchargeYen,
                    rating: serving.rating,
                    memo: serving.memo,
                    isUsual: serving.isUsual,
                    usualMarkedAt: serving.usualMarkedAt,
                    isHallOfFame: serving.isHallOfFame,
                    hallOfFameMarkedAt: serving.hallOfFameMarkedAt,
                    richness: serving.richness,
                    oiliness: serving.oiliness,
                    sesameNote: serving.sesameNote,
                    herbalNote: serving.herbalNote,
                    sourness: serving.sourness,
                    garlic: serving.garlic,
                    cilantro: serving.cilantro,
                    createdAt: serving.createdAt,
                    storeUUID: serving.store?.uuid,
                    soupUUID: serving.soup?.uuid,
                    noodleUUIDs: serving.noodles.map(\.uuid),
                    ingredientUUIDs: serving.ingredients.map(\.uuid)
                )
            }
        )
    }

    /// 一時ディレクトリに .malaarchive を書き出し、その URL を返す。共有シートに渡す想定。
    static func export(context: ModelContext) throws -> URL {
        let payload = makePayload(context: context)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let jsonData: Data
        do {
            jsonData = try encoder.encode(payload)
        } catch {
            throw BackupError.writeFailed(error.localizedDescription)
        }

        var imageWrappers: [String: FileWrapper] = [:]
        for id in payload.servings.compactMap(\.photoID) {
            guard let data = PhotoStore.shared.rawData(id) else { continue }
            imageWrappers["\(id).jpg"] = FileWrapper(regularFileWithContents: data)
        }

        let root = FileWrapper(directoryWithFileWrappers: [
            BackupFormat.databaseFileName: FileWrapper(regularFileWithContents: jsonData),
            BackupFormat.imagesFolderName: FileWrapper(directoryWithFileWrappers: imageWrappers)
        ])

        guard let serialized = root.serializedRepresentation else {
            throw BackupError.writeFailed(String(localized: "パッケージの作成に失敗しました"))
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let localizedAppName = String(localized: "麻辣湯ログ")
        let fileName = "\(localizedAppName)_\(formatter.string(from: Date())).\(BackupFormat.fileExtension)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try serialized.write(to: url, options: .atomic)
        } catch {
            throw BackupError.writeFailed(error.localizedDescription)
        }
        return url
    }

    // MARK: - 読み取り（検証のみ）

    struct Inspection {
        var payload: BackupPayload
        var images: [String: Data]
    }

    static func inspect(url: URL) throws -> Inspection {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw BackupError.decodeFailed(error.localizedDescription)
        }

        guard let wrapper = FileWrapper(serializedRepresentation: data), wrapper.isDirectory else {
            throw BackupError.notAPackage
        }
        guard
            let dbWrapper = wrapper.fileWrappers?[BackupFormat.databaseFileName],
            let dbData = dbWrapper.regularFileContents
        else {
            throw BackupError.databaseMissing
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload: BackupPayload
        do {
            payload = try decoder.decode(BackupPayload.self, from: dbData)
        } catch {
            throw BackupError.decodeFailed(error.localizedDescription)
        }
        guard payload.formatVersion <= BackupFormat.currentVersion else {
            throw BackupError.unsupportedVersion(payload.formatVersion)
        }

        var images: [String: Data] = [:]
        if let imagesWrapper = wrapper.fileWrappers?[BackupFormat.imagesFolderName],
           let children = imagesWrapper.fileWrappers {
            for (name, child) in children {
                guard name.hasSuffix(".jpg"), let content = child.regularFileContents else { continue }
                images[String(name.dropLast(4))] = content
            }
        }
        let inspection = Inspection(payload: payload, images: images)
        try validate(inspection)
        return inspection
    }

    // MARK: - 復元

    /// Failure injection is internal to the module; production uses the real disk/save operations.
    struct RestoreOperations {
        var photos: PhotoStore = .shared
        var save: (ModelContext) throws -> Void = { try $0.save() }
        var writePhoto: (Data, String, PhotoStore) throws -> Void = { data, id, photos in
            guard photos.writeRaw(data, id: id) else {
                throw BackupError.restoreFailed("Photo write failed")
            }
        }
    }

    @discardableResult
    static func restore(
        inspection: Inspection,
        mode: RestoreMode,
        context: ModelContext,
        operations: RestoreOperations = RestoreOperations()
    ) throws -> RestoreResult {
        let payload = inspection.payload
        try validate(inspection)

        // Preserve unrelated pending edits before establishing the rollback boundary.
        // Failure here occurs before any restore mutation or photo write.
        if context.hasChanges { try context.save() }
        let autosaveEnabled = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = autosaveEnabled }

        var newPhotoIDs: Set<String> = []
        var committed = false
        defer {
            if !committed {
                context.rollback()
                for id in newPhotoIDs { operations.photos.delete(id) }
            }
        }

        // Fetch everything before deleting anything; a fetch failure is never an empty database.
        let oldServings = try context.fetch(FetchDescriptor<Serving>())
        let oldStores = try context.fetch(FetchDescriptor<Store>())
        let oldSoups = try context.fetch(FetchDescriptor<Soup>())
        let oldNoodles = try context.fetch(FetchDescriptor<Noodle>())
        let oldIngredients = try context.fetch(FetchDescriptor<Ingredient>())

        // Build maps before mutation, with duplicate UUIDs reported rather than trapping.
        var storeMap = try modelMap(mode == .replaceAll ? [] : oldStores, id: { $0.uuid })
        var soupMap = try modelMap(mode == .replaceAll ? [] : oldSoups, id: { $0.uuid })
        var noodleMap = try modelMap(mode == .replaceAll ? [] : oldNoodles, id: { $0.uuid })
        var ingredientMap = try modelMap(mode == .replaceAll ? [] : oldIngredients, id: { $0.uuid })
        try validateReferences(
            payload,
            stores: Set(storeMap.keys), soups: Set(soupMap.keys),
            noodles: Set(noodleMap.keys), ingredients: Set(ingredientMap.keys)
        )

        if mode == .replaceAll {
            // No intermediate save, photo deletion, or favorite change.
            for item in oldServings { context.delete(item) }
            for item in oldStores { context.delete(item) }
            for item in oldSoups { context.delete(item) }
            for item in oldNoodles { context.delete(item) }
            for item in oldIngredients { context.delete(item) }
        }

        var result = RestoreResult(
            mode: mode, addedServings: 0, skippedServings: 0,
            addedStores: 0, addedMasters: 0, restoredPhotos: 0, missingPhotos: 0
        )

        // --- マスター ---
        for dto in payload.stores where storeMap[dto.uuid] == nil {
            let store = Store(
                uuid: dto.uuid, name: dto.name, branch: dto.branch, address: dto.address,
                latitude: dto.latitude, longitude: dto.longitude
            )
            store.createdAt = dto.createdAt
            context.insert(store)
            storeMap[dto.uuid] = store
            result.addedStores += 1
        }
        for dto in payload.soups where soupMap[dto.uuid] == nil {
            let soup = Soup(
                uuid: dto.uuid, name: dto.name, reading: dto.reading,
                aliases: dto.aliases, isCustom: dto.isCustom, sortOrder: dto.sortOrder
            )
            soup.isHidden = dto.isHidden
            context.insert(soup)
            soupMap[dto.uuid] = soup
            result.addedMasters += 1
        }

        for dto in payload.noodles where noodleMap[dto.uuid] == nil {
            let noodle = Noodle(
                uuid: dto.uuid, name: dto.name, reading: dto.reading,
                aliases: dto.aliases, isCustom: dto.isCustom, sortOrder: dto.sortOrder
            )
            noodle.isHidden = dto.isHidden
            context.insert(noodle)
            noodleMap[dto.uuid] = noodle
            result.addedMasters += 1
        }

        for dto in payload.ingredients where ingredientMap[dto.uuid] == nil {
            let ingredient = Ingredient(
                uuid: dto.uuid, name: dto.name, reading: dto.reading, aliases: dto.aliases,
                category: IngredientCategory(rawValue: dto.category) ?? .other,
                isCustom: dto.isCustom, sortOrder: dto.sortOrder
            )
            ingredient.isHidden = dto.isHidden
            ingredient.isPinned = dto.isPinned
            ingredient.pinnedAt = dto.pinnedAt
            context.insert(ingredient)
            ingredientMap[dto.uuid] = ingredient
            result.addedMasters += 1
        }

        // --- 記録 ---
        let existingServingIDs = Set(mode == .replaceAll ? [] : oldServings.map(\.uuid))
        var restoredPhotoIDs: [String: String] = [:]

        for dto in payload.servings {
            guard existingServingIDs.contains(dto.uuid) == false else {
                result.skippedServings += 1
                continue
            }

            var photoID: String?
            if let originalID = dto.photoID {
                if let data = inspection.images[originalID] {
                    if let stagedID = restoredPhotoIDs[originalID] {
                        photoID = stagedID
                    } else {
                        // Never overwrite a photo belonging to an existing record, even on append.
                        var stagedID = UUID().uuidString
                        while operations.photos.exists(stagedID) { stagedID = UUID().uuidString }
                        newPhotoIDs.insert(stagedID)
                        try operations.writePhoto(data, stagedID, operations.photos)
                        restoredPhotoIDs[originalID] = stagedID
                        photoID = stagedID
                    }
                    result.restoredPhotos += 1
                } else if mode == .append && operations.photos.exists(originalID) {
                    photoID = originalID
                } else {
                    result.missingPhotos += 1
                }
            }

            let serving = Serving(
                uuid: dto.uuid,
                date: dto.date,
                photoID: photoID,
                spiceLevel: dto.spiceLevel,
                numbnessLevel: dto.numbnessLevel,
                spiceNote: dto.spiceNote,
                priceYen: dto.priceYen,
                currencyCode: AppCurrency.normalizedCode(dto.currencyCode),
                totalWeightGrams: dto.totalWeightGrams,
                pricePer100gYen: dto.pricePer100gYen,
                soupSurchargeYen: dto.soupSurchargeYen,
                rating: dto.rating,
                memo: dto.memo,
                store: dto.storeUUID.flatMap { storeMap[$0] },
                soup: dto.soupUUID.flatMap { soupMap[$0] },
                noodles: dto.noodleUUIDs.compactMap { noodleMap[$0] },
                ingredients: dto.ingredientUUIDs.compactMap { ingredientMap[$0] }
            )
            serving.isUsual = dto.isUsual
            serving.usualMarkedAt = dto.usualMarkedAt
            serving.isHallOfFame = dto.isHallOfFame
            serving.hallOfFameMarkedAt = dto.hallOfFameMarkedAt
            serving.richness = dto.richness
            serving.oiliness = dto.oiliness
            serving.sesameNote = dto.sesameNote
            serving.herbalNote = dto.herbalNote
            serving.sourness = dto.sourness
            serving.garlic = dto.garlic
            serving.cilantro = dto.cilantro
            serving.createdAt = dto.createdAt
            context.insert(serving)
            result.addedServings += 1
        }

        // Deletions and insertions are committed together. On error, defer rolls back
        // the database and removes only newly written photos; originals were never touched.
        try operations.save(context)
        committed = true

        // These nonthrowing operations only run after the database commit.
        if mode == .replaceAll { FavoriteStoreService.shared.removeAll() }
        for dto in payload.stores {
            guard let store = storeMap[dto.uuid], let isFavorite = dto.isFavorite else { continue }
            FavoriteStoreService.shared.set(store, isFavorite: isFavorite)
        }
        if mode == .replaceAll {
            operations.photos.removeOrphans(referencedIDs: Set(restoredPhotoIDs.values))
        }
        return result
    }

    private static func modelMap<T>(_ values: [T], id: (T) -> UUID) throws -> [UUID: T] {
        var result: [UUID: T] = [:]
        for value in values {
            guard result.updateValue(value, forKey: id(value)) == nil else {
                throw BackupError.decodeFailed("Duplicate UUID")
            }
        }
        return result
    }

    private static func validate(_ inspection: Inspection) throws {
        let payload = inspection.payload
        guard payload.formatVersion > 0, payload.formatVersion <= BackupFormat.currentVersion else {
            throw BackupError.unsupportedVersion(payload.formatVersion)
        }
        _ = try modelMap(payload.stores, id: { $0.uuid })
        _ = try modelMap(payload.soups, id: { $0.uuid })
        _ = try modelMap(payload.noodles, id: { $0.uuid })
        _ = try modelMap(payload.ingredients, id: { $0.uuid })
        _ = try modelMap(payload.servings, id: { $0.uuid })
        for id in payload.servings.compactMap(\.photoID) {
            guard !id.isEmpty, id != ".", id != "..",
                  !id.contains("/"), !id.contains("\\"), !id.contains("\0") else {
                throw BackupError.decodeFailed("Invalid photo ID")
            }
            if let data = inspection.images[id], UIImage(data: data) == nil {
                throw BackupError.decodeFailed("Invalid photo data")
            }
        }
        // Missing photos remain a reported warning, as in existing archives/export behavior.
    }

    private static func validateReferences(
        _ payload: BackupPayload,
        stores: Set<UUID>, soups: Set<UUID>, noodles: Set<UUID>, ingredients: Set<UUID>
    ) throws {
        let stores = stores.union(payload.stores.map(\.uuid))
        let soups = soups.union(payload.soups.map(\.uuid))
        let noodles = noodles.union(payload.noodles.map(\.uuid))
        let ingredients = ingredients.union(payload.ingredients.map(\.uuid))
        for serving in payload.servings {
            guard serving.storeUUID.map({ stores.contains($0) }) ?? true,
                  serving.soupUUID.map({ soups.contains($0) }) ?? true,
                  Set(serving.noodleUUIDs).isSubset(of: noodles),
                  Set(serving.ingredientUUIDs).isSubset(of: ingredients) else {
                throw BackupError.decodeFailed("Missing related data")
            }
        }
    }

}

enum AppInfo {
    static var shortVersionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var versionString: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(shortVersionString) (\(build))"
    }
}

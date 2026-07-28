import Foundation

/// .malaarchive の中身。FileWrapper で database.json と images/ をまとめる。
enum BackupFormat {
    static let currentVersion = 1
    static let fileExtension = "malaarchive"
    static let databaseFileName = "database.json"
    static let imagesFolderName = "images"
    static let uti = "com.malatanglog.archive"
}

struct BackupPayload: Codable {
    var formatVersion: Int
    var appVersion: String
    var exportedAt: Date
    var stores: [StoreDTO]
    var soups: [SoupDTO]
    var noodles: [NoodleDTO]
    var ingredients: [IngredientDTO]
    var servings: [ServingDTO]
}

struct StoreDTO: Codable {
    var uuid: UUID
    var name: String
    var branch: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    var createdAt: Date
    /// v1.0バックアップには存在しないためoptionalで後方互換にする。
    var isFavorite: Bool?
}

struct SoupDTO: Codable {
    var uuid: UUID
    var name: String
    var reading: String
    var aliases: [String]
    var isCustom: Bool
    var isHidden: Bool
    var sortOrder: Int
}

struct NoodleDTO: Codable {
    var uuid: UUID
    var name: String
    var reading: String
    var aliases: [String]
    var isCustom: Bool
    var isHidden: Bool
    var sortOrder: Int
}

struct IngredientDTO: Codable {
    var uuid: UUID
    var name: String
    var reading: String
    var aliases: [String]
    var category: String
    var isCustom: Bool
    var isHidden: Bool
    var isPinned: Bool
    var pinnedAt: Date?
    var sortOrder: Int
}

struct ServingDTO: Codable {
    var uuid: UUID
    var date: Date
    var photoID: String?
    var spiceLevel: Int
    var numbnessLevel: Int
    var spiceNote: String
    var priceYen: Int?
    var totalWeightGrams: Int?
    var pricePer100gYen: Int?
    var soupSurchargeYen: Int?
    var rating: Int
    var memo: String
    var isUsual: Bool
    var usualMarkedAt: Date?
    var isHallOfFame: Bool
    var hallOfFameMarkedAt: Date?
    var richness: Int
    var oiliness: Int
    var sesameNote: Int
    var herbalNote: Int
    var sourness: Int
    var garlic: Int
    var cilantro: Int
    var createdAt: Date
    var storeUUID: UUID?
    var soupUUID: UUID?
    var noodleUUIDs: [UUID]
    var ingredientUUIDs: [UUID]
}

/// 復元方式
enum RestoreMode: String, CaseIterable, Identifiable {
    /// 既存データを残し、重複IDはスキップして足す
    case append
    /// 既存データを全部消してから入れ替える
    case replaceAll

    var id: String { rawValue }

    var title: String {
        switch self {
        case .append: return "追加"
        case .replaceAll: return "全置換"
        }
    }

    var explanation: String {
        switch self {
        case .append:
            return "今ある記録を残したまま、バックアップの記録を足します。同じ記録は二重に入りません。"
        case .replaceAll:
            return "今ある記録・写真をすべて消してから、バックアップの内容に入れ替えます。取り消せません。"
        }
    }
}

struct ExportEstimate {
    var servingCount: Int
    var photoCount: Int
    var storeCount: Int
    var estimatedBytes: Int64

    var estimatedSizeText: String {
        ByteCountFormatter.string(fromByteCount: estimatedBytes, countStyle: .file)
    }
}

struct RestoreResult {
    var mode: RestoreMode
    var addedServings: Int
    var skippedServings: Int
    var addedStores: Int
    var addedMasters: Int
    var restoredPhotos: Int
    var missingPhotos: Int
}

enum BackupError: LocalizedError {
    case notAPackage
    case databaseMissing
    case unsupportedVersion(Int)
    case decodeFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAPackage:
            return "このファイルは麻辣湯ログのバックアップとして読み取れませんでした。"
        case .databaseMissing:
            return "バックアップの中にデータ本体が見つかりませんでした。"
        case .unsupportedVersion(let version):
            return "このバックアップ（形式 v\(version)）は、今のアプリでは開けません。アプリを更新してください。"
        case .decodeFailed(let detail):
            return "バックアップの読み取りに失敗しました。（\(detail)）"
        case .writeFailed(let detail):
            return "バックアップの書き出しに失敗しました。（\(detail)）"
        }
    }
}

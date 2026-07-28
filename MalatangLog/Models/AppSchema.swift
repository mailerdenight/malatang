import Foundation
import SwiftData

/// バージョン付きスキーマ。将来のマイグレーションはここに段階を足していく。
enum MalatangSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [Serving.self, Store.self, Ingredient.self, Noodle.self, Soup.self]
    }
}

enum MalatangMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [MalatangSchemaV1.self]
    }

    /// V2以降を足すときに MigrationStage を追加する。
    static var stages: [MigrationStage] { [] }
}

enum AppModelContainer {
    /// 失敗したら投げる。呼び出し側で復旧導線を出すため、黙ってメモリ内へ落とさない。
    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: MalatangSchemaV1.self)
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: MalatangMigrationPlan.self,
            configurations: configuration
        )
    }
}

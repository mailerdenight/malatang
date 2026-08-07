import Foundation
import SwiftData

@Model
final class Noodle {
    var uuid: UUID = UUID()
    var name: String = ""
    var reading: String = ""
    var aliases: [String] = []
    var isCustom: Bool = false
    var isHidden: Bool = false
    var sortOrder: Int = 0
    var createdAt: Date = Date()

    @Relationship(inverse: \Serving.noodles)
    var servings: [Serving] = []

    init(
        uuid: UUID = UUID(),
        name: String,
        reading: String = "",
        aliases: [String] = [],
        isCustom: Bool = false,
        sortOrder: Int = 0
    ) {
        self.uuid = uuid
        self.name = name
        self.reading = reading
        self.aliases = aliases
        self.isCustom = isCustom
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}

extension Noodle {
    var localizedDisplayName: String {
        AppLocalization.masterName(name, isCustom: isCustom)
    }

    var searchHaystack: String {
        ([name, localizedDisplayName, reading] + aliases).joined(separator: " ")
    }

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.isEmpty == false else { return true }
        return searchHaystack.localizedCaseInsensitiveContains(q)
    }
}

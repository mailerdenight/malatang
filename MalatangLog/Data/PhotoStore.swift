import Foundation
import UIKit

/// 写真は Application Support 配下に保存し、DB にはファイルIDだけを持つ。
struct PhotoStore {

    static let shared = PhotoStore()

    /// 長辺の目標サイズ
    static let maxDimension: CGFloat = 1600
    static let jpegQuality: CGFloat = 0.82

    let directory: URL

    init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        directory = base.appendingPathComponent("Photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func fileURL(for id: String) -> URL {
        directory.appendingPathComponent("\(id).jpg")
    }

    // MARK: - 保存

    /// 保存に失敗しても記録自体は続行できるよう、throw ではなく nil を返す。
    func save(_ image: UIImage) -> String? {
        let id = UUID().uuidString
        guard let data = Self.jpegData(from: image) else { return nil }
        do {
            try data.write(to: fileURL(for: id), options: .atomic)
            return id
        } catch {
            return nil
        }
    }

    /// 復元用。既存のJPEGデータをIDそのままで書き戻す。
    @discardableResult
    func writeRaw(_ data: Data, id: String) -> Bool {
        do {
            try data.write(to: fileURL(for: id), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // MARK: - 読み出し

    func load(_ id: String?) -> UIImage? {
        guard let id, id.isEmpty == false else { return nil }
        let url = fileURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    func rawData(_ id: String?) -> Data? {
        guard let id, id.isEmpty == false else { return nil }
        return try? Data(contentsOf: fileURL(for: id))
    }

    func exists(_ id: String?) -> Bool {
        guard let id, id.isEmpty == false else { return false }
        return FileManager.default.fileExists(atPath: fileURL(for: id).path)
    }

    // MARK: - 削除

    func delete(_ id: String?) {
        guard let id, id.isEmpty == false else { return }
        try? FileManager.default.removeItem(at: fileURL(for: id))
    }

    /// DBから参照されていない写真を掃除する。
    @discardableResult
    func removeOrphans(referencedIDs: Set<String>) -> Int {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return 0 }
        var removed = 0
        for file in files where file.hasSuffix(".jpg") {
            let id = String(file.dropLast(4))
            if referencedIDs.contains(id) == false {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
                removed += 1
            }
        }
        return removed
    }

    var totalBytes: Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(Int64(0)) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
    }

    // MARK: - 縮小

    static func jpegData(from image: UIImage) -> Data? {
        let resized = resize(image, maxDimension: maxDimension)
        return resized.jpegData(compressionQuality: jpegQuality)
    }

    static func resize(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension, longest > 0 else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

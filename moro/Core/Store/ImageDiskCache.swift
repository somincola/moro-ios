import CryptoKit
import Foundation

/// All file access shares one utility queue. A generation prevents downloads
/// started before a manual clear from writing the old cache back afterwards.
nonisolated final class ImageDiskCache: @unchecked Sendable {
    private struct Entry { var date: Date; let bytes: Int64 }
    private let directory: URL
    private let maximumBytes: Int64
    private let maximumAge: TimeInterval
    private let queue = DispatchQueue(label: "com.moro.image-disk-cache", qos: .utility)
    private var entries: [String: Entry]?
    private var generation = UUID()
    private let generationLock = NSLock()

    init(directory: URL, maximumBytes: Int64 = 128 * 1_024 * 1_024, maximumAge: TimeInterval = 7 * 86_400) {
        self.directory = directory
        self.maximumBytes = max(0, maximumBytes)
        self.maximumAge = max(0, maximumAge)
    }

    var writeGeneration: UUID { generationLock.withLock { generation } }

    func data(for url: URL) -> Data? {
        queue.sync {
            prepare()
            let key = filename(url)
            guard let entry = entries?[key], Date().timeIntervalSince(entry.date) < maximumAge else {
                remove(key); return nil
            }
            guard let data = try? Data(contentsOf: directory.appendingPathComponent(key)) else {
                entries?[key] = nil; return nil
            }
            return data
        }
    }

    func store(_ data: Data, for url: URL, generation expected: UUID) {
        queue.async {
            guard expected == self.writeGeneration, Int64(data.count) <= self.maximumBytes else { return }
            self.prepare()
            let key = self.filename(url)
            do {
                try data.write(to: self.directory.appendingPathComponent(key), options: .atomic)
                self.entries?[key] = Entry(date: Date(), bytes: Int64(data.count))
                self.trim()
            } catch { /* A failed cache write never prevents displaying an image. */ }
        }
    }

    func size() async -> Int64 {
        await withCheckedContinuation { continuation in
            queue.async {
                // iOS may evict Library/Caches while the process is alive.
                self.entries = nil
                self.prepare()
                continuation.resume(returning: self.byteCount)
            }
        }
    }

    func clear() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.generationLock.withLock { self.generation = UUID() }
                do {
                    if FileManager.default.fileExists(atPath: self.directory.path) {
                        try FileManager.default.removeItem(at: self.directory)
                    }
                    try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
                    self.entries = [:]
                    continuation.resume()
                } catch {
                    self.entries = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private var byteCount: Int64 { entries?.values.reduce(0) { $0 + $1.bytes } ?? 0 }
    private func filename(_ url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func prepare() {
        guard entries == nil else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        entries = [:]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]
        )) ?? []
        for file in files {
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            entries?[file.lastPathComponent] = Entry(date: values.contentModificationDate ?? .distantPast, bytes: Int64(values.fileSize ?? 0))
        }
        trim()
    }

    private func remove(_ key: String) {
        let url = directory.appendingPathComponent(key)
        do {
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            entries?[key] = nil
        } catch { /* Keep the entry in the reported size if removal failed. */ }
    }

    private func trim() {
        let cutoff = Date().addingTimeInterval(-maximumAge)
        for (key, entry) in entries ?? [:] where entry.date < cutoff { remove(key) }
        var remaining = byteCount
        guard remaining > maximumBytes else { return }
        for (key, entry) in (entries ?? [:]).sorted(by: { $0.value.date < $1.value.date }) {
            guard remaining > maximumBytes else { break }
            remove(key)
            if entries?[key] == nil { remaining -= entry.bytes }
        }
    }
}

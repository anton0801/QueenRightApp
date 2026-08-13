//
//  LocalStore.swift
//  QueenRight
//
//  Local-first persistence (§7). Everything the app needs to run at the hive lives in
//  Application Support as versioned JSON, so the board, the projection and capture all
//  work with no signal and no account (§11 acceptance 14).
//  Weather is cached separately in Caches — it is derived data and may be evicted.
//

import Foundation

/// Every payload is wrapped so a schema bump can migrate on decode rather than crash.
struct Versioned<T: Codable>: Codable {
    var v: Int
    var value: T
}

final class LocalStore {
    static let shared = LocalStore()

    static let schemaVersion = 1

    private let fm = FileManager.default
    private let dir: URL
    private let cacheDir: URL

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // Well-known filenames.
    enum Key: String {
        case apiary = "apiary.json"
        case preferences = "preferences.json"
        case weather = "weather.json"
        /// Версии ульев, от которых правило это устройство (см. SyncService).
        case syncState = "sync-state.json"
    }

    private init() {
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = support.appendingPathComponent("QueenRight", isDirectory: true)
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        cacheDir = caches.appendingPathComponent("QueenRight", isDirectory: true)
        for d in [dir, cacheDir] {
            if !fm.fileExists(atPath: d.path) {
                try? fm.createDirectory(at: d, withIntermediateDirectories: true)
            }
        }
    }

    private func url(for key: Key) -> URL {
        key == .weather ? cacheDir.appendingPathComponent(key.rawValue)
                        : dir.appendingPathComponent(key.rawValue)
    }

    // MARK: - Read / write

    func load<T: Codable>(_ type: T.Type, from key: Key) -> T? {
        let u = url(for: key)
        guard let data = try? Data(contentsOf: u) else { return nil }
        if let wrapped = try? decoder.decode(Versioned<T>.self, from: data) {
            return wrapped.value
        }
        // Tolerate an unwrapped payload written by an older build.
        return try? decoder.decode(T.self, from: data)
    }

    func save<T: Codable>(_ value: T, to key: Key) {
        let u = url(for: key)
        let wrapped = Versioned(v: Self.schemaVersion, value: value)
        guard let data = try? encoder.encode(wrapped) else { return }
        try? data.write(to: u, options: .atomic)
    }

    func delete(_ key: Key) {
        try? fm.removeItem(at: url(for: key))
    }

    /// Wipe every local trace — used by account deletion (§14).
    func wipeEverything() {
        for d in [dir, cacheDir] {
            if let items = try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil) {
                for item in items { try? fm.removeItem(at: item) }
            }
        }
        PhotoStore.shared.deleteAll()
    }
}

// MARK: - Photos

/// Frame photographs live as files, not in the JSON, and never leave the device (§7).
final class PhotoStore {
    static let shared = PhotoStore()

    private let fm = FileManager.default
    private let dir: URL

    private init() {
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = support.appendingPathComponent("QueenRight/Photos", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    func url(for id: String) -> URL {
        dir.appendingPathComponent("\(id).jpg")
    }

    @discardableResult
    func save(_ data: Data, id: String) -> URL? {
        let u = url(for: id)
        do {
            try data.write(to: u, options: .atomic)
            return u
        } catch {
            return nil
        }
    }

    func data(for id: String) -> Data? {
        try? Data(contentsOf: url(for: id))
    }

    func delete(id: String) {
        try? fm.removeItem(at: url(for: id))
    }

    func deleteAll() {
        if let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for item in items { try? fm.removeItem(at: item) }
        }
    }
}

// MARK: - Preferences

struct Preferences: Codable, Equatable {
    var hasOnboarded: Bool = false
    var appearance: AppearanceMode = .system
    /// Set once the user has been asked about notifications, so we never ask twice.
    var notificationsRequested: Bool = false
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

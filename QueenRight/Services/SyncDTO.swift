//
//  SyncDTO.swift
//  QueenRight
//
//  Формы обмена с собственным API. Вынесены отдельно от SyncService намеренно:
//  здесь нет ни SwiftUI, ни Combine, поэтому эти типы можно скомпилировать в
//  отдельный бинарник и проверить контракт против живого сервера — что и было
//  сделано (совпадение имён полей, формат дат, целостность вложенного payload).
//

import Foundation

// MARK: - DTO

/// Вложенная часть улья: ровно те поля модели, которые сервер не разбирает,
/// а хранит одним JSON-документом.
struct HivePayload: Codable {
    var boxes: [Box]
    var queen: Queen
    var cellObservations: [QueenCellObservation]
    var cellsCutAt: Date?
    var queenlessSince: Date?
    var swarmEvents: [SwarmEvent]
    var archivedProjections: [ArchivedProjection]
    var createdAt: Date
}

struct HiveDTO: Codable {
    var id: String
    var name: String
    var position_x: Double
    var position_y: Double
    var last_inspection: Date
    var payload: HivePayload
    var version: Int?
    var base_version: Int?
    var deleted: Bool?
}

struct ApiaryDTO: Codable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var system: String
    var version: Int
}

struct PullResponse: Codable {
    var server_time: Date
    var apiary: ApiaryDTO?
    var hives: [HiveDTO]
    var deleted_hive_ids: [String]
}

struct PushResponse: Codable {
    struct Applied: Codable {
        var id: String
        var version: Int
    }
    struct Conflict: Codable {
        var id: String
        var reason: String
        var server: HiveDTO?
    }
    var server_time: Date
    var applied: [Applied]
    var conflicts: [Conflict]
}

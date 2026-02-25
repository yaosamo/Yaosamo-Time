import Foundation

struct ZoneClock: Identifiable, Codable {
    let id: UUID
    let timeZone: String
    let title: String
    let subtitle: String

    init(id: UUID = UUID(), timeZone: String, title: String, subtitle: String) {
        self.id = id
        self.timeZone = timeZone
        self.title = title
        self.subtitle = subtitle
    }
}

struct HourReference {
    let sourceZoneID: UUID
    let sourceTimeZone: String
    let localHour: Int
    let utcDate: Date
}



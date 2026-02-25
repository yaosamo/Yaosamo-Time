import Foundation

struct ViewerResolvedZone {
    let timeZone: String
    let title: String
    let subtitle: String
}

struct PersistedClockStoreState: Codable {
    let zones: [ZoneClock]
    let selected: PersistedSelectedReference?
}

struct PersistedSelectedReference: Codable {
    let sourceZoneID: UUID
    let localHour: Int
}

struct ViewerHourFormatResponse: Decodable {
    let city: String?
    let countryCode: String?
    let geoapifyPlace: ViewerGeoapifyPlace?
    let hourFormat: String?
    let regionCode: String?
    let timeZone: String?
}

struct ViewerGeoapifyPlace: Decodable {
    let title: String?
    let subtitle: String?
    let timeZone: String?
}

struct GeoapifyAutocompleteResponse: Decodable {
    let results: [GeoapifyAutocompleteRawResult]?
}

struct GeoapifyAutocompleteRawResult: Decodable {
    let addressLine1: String?
    let city: String?
    let country: String?
    let countryCode: String?
    let county: String?
    let formatted: String?
    let hamlet: String?
    let name: String?
    let region: String?
    let state: String?
    let stateCode: String?
    let stateDistrict: String?
    let suburb: String?
    let timezone: GeoapifyTimeZoneValue?
    let town: String?
    let village: String?

    enum CodingKeys: String, CodingKey {
        case addressLine1 = "address_line1"
        case city
        case country
        case countryCode = "country_code"
        case county
        case formatted
        case hamlet
        case name
        case region
        case state
        case stateCode = "state_code"
        case stateDistrict = "state_district"
        case suburb
        case timezone
        case town
        case village
    }
}

enum GeoapifyTimeZoneValue: Decodable {
    case string(String)
    case object(GeoapifyTimeZoneObject)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
            return
        }
        self = .object(try container.decode(GeoapifyTimeZoneObject.self))
    }
}

struct GeoapifyTimeZoneObject: Decodable {
    let id: String?
    let name: String?
}

struct GeoapifySearchResult: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let timeZone: String
}

struct WhenThereSharePayload: Encodable {
    let zones: [WhenThereShareZone]
    let selected: WhenThereShareSelected?
}

struct WhenThereShareZone: Encodable {
    let id: String
    let timeZone: String
    let title: String
    let subtitle: String
}

struct WhenThereShareSelected: Encodable {
    let zoneId: String?
    let timeZone: String
    let localHour: Int
}

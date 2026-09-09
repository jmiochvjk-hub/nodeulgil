import Foundation

enum PersonRole: String, Codable, CaseIterable, Identifiable {
    case manager
    case employee
    case parttime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manager: "점장"
        case .employee: "직원"
        case .parttime: "알바"
        }
    }
}

struct Shop: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var createdAt: Int64
}

struct Person: Codable, Identifiable, Equatable {
    var id: String
    var storeId: String
    var name: String
    var pin: String
    var role: PersonRole
}

struct Admin: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var pin: String
}

struct WorkRecord: Codable, Identifiable, Equatable {
    var id: String
    var storeId: String
    var staffId: String
    var date: String
    var start: String
    var end: String
    var review: Int
    var note: String
    var ok: Bool
}

struct Reservation: Codable, Identifiable, Equatable {
    var id: String
    var storeId: String
    var staffId: String?
    var datetime: String
    var customer: String
    var phone: String
    var memo: String
    var remindMin: Int
    var notified: Bool
    var createdBy: String?
}

struct WorkDatabase: Codable, Equatable {
    var version: Int
    var shops: [Shop]
    var people: [Person]
    var admins: [Admin]
    var records: [WorkRecord]
    var reservations: [Reservation]

    static var seed: WorkDatabase {
        let shopId = "shop-nodeulgil"
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        return WorkDatabase(
            version: 4,
            shops: [Shop(id: shopId, name: "노들길", createdAt: now)],
            people: [
                Person(id: "person-wj1", storeId: shopId, name: "왕지선", pin: "1111", role: .employee),
                Person(id: "person-sj1", storeId: shopId, name: "석정윤", pin: "2222", role: .employee),
                Person(id: "person-mgr", storeId: shopId, name: "점장", pin: "2001", role: .manager)
            ],
            admins: [Admin(id: "admin-root", name: "최고관리자", pin: "9090")],
            records: [],
            reservations: []
        )
    }
}

enum AppSession: Equatable {
    case staff(Person)
    case manager(Person)
    case admin(Admin)

    var name: String {
        switch self {
        case .staff(let person), .manager(let person): person.name
        case .admin(let admin): admin.name
        }
    }

    var title: String {
        switch self {
        case .staff(let person): person.role.title
        case .manager: "점장"
        case .admin: "관리자"
        }
    }
}

struct SyncEnvelope: Codable {
    var v: Int64
    var data: WorkDatabase?
}

struct PushEnvelope: Encodable {
    var data: WorkDatabase
    var base: Int64
}

extension Date {
    var ymd: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }

    var monthKey: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM"
        return formatter.string(from: self)
    }
}
